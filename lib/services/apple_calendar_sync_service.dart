import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'routine_schedule.dart';

/// 서비스가 ScheduleItem(UI 파일)에 직접 의존하지 않도록 넘겨받는 경량 일정 정보.
class CalendarScheduleEntry {
  final String id; // 캘린더 이벤트 매핑 키
  final String dateKey; // yyyy-MM-dd
  final String title;
  final String? timeStart; // HH:mm, 없으면 종일로 취급
  final String? timeEnd; // HH:mm
  final String kindLabel;

  const CalendarScheduleEntry({
    required this.id,
    required this.dateKey,
    required this.title,
    this.timeStart,
    this.timeEnd,
    required this.kindLabel,
  });
}

enum AppleCalendarEnableResult {
  success,
  permissionDenied,
  unsupported,
  failed,
}

/// 냥냥코치 일정을 아이폰(애플) 캘린더에 단방향으로 미러링한다.
///
/// - 냥냥코치가 원천(source of truth). 앱에서 일정이 바뀔 때마다 전용 캘린더를
///   현재 상태로 재동기화한다. (애플 캘린더 → 냥냥코치 역방향은 없음)
/// - iOS 전용. 안드로이드에서는 아무 동작도 하지 않는다.
class AppleCalendarSyncService {
  AppleCalendarSyncService._();
  static final AppleCalendarSyncService instance = AppleCalendarSyncService._();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  static const String _kEnabledKey = 'nyang_apple_calendar_enabled';
  static const String _kCalendarIdKey = 'nyang_apple_calendar_id';

  /// 냥냥코치 일정 id -> 애플 캘린더 이벤트 id 매핑.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이벤트 id는 이 기기의 EventKit이 발급한
  /// 것이라 다른 기기에서는 아무 뜻이 없다. 접두어가 붙어 있던 동안에는 이
  /// 표가 클라우드로 오르내렸고, 다른 기기가 들고 있던 옛 표가 내려오면
  /// 아이폰은 이미 없는 이벤트 id를 들고 캘린더를 뒤졌다. 안 잡히는 것은
  /// "사용자가 지웠다"로 읽혔으므로, 그 항목이 루틴이면 그날이 쉬기로 찍혔다 —
  /// 쉰다고 한 적 없는데 루틴이 사라지던 길이 이것이다.
  /// (지금은 지운 것으로 받아들이는 길 자체를 없앴다.)
  static const String _kEventMapKey = 'apple_calendar_event_map';

  /// 접두어가 붙어 있던 시절의 자리. 한 번 옮겨 오고 지운다.
  static const String _kLegacyEventMapKey = 'nyang_apple_calendar_event_map';
  // tasks_screen이 저장하는 SharedPreferences 키. 서비스는 여기서 직접 읽는다.
  static const String _kSchedulesPrefsKey = 'nyang_schedules';
  static const String _kTasksPrefsKey = 'nyang_tasks';
  static const String _kPlannedTasksPrefsKey = 'nyang_today_tasks_by_date';
  static const String _kHabitsPrefsKey = 'nyang_habits';
  static const String _kHabitLogsPrefsKey = 'nyang_habit_logs';
  static const String _kVisionsPrefsKey = 'nyang_visions';
  static const String _calendarName = '냥냥코치';
  // 이벤트를 탭하면 기존 위젯 딥링크 경로를 재사용해 앱 안의 플래너 전체창으로 진입한다.
  static const String _deepLinkBase = 'nyangcoach://widget/cat';
  static const int _habitSyncDays = 90;

  bool get isSupportedPlatform => Platform.isIOS;

  Future<bool> isEnabled() async {
    if (!isSupportedPlatform) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  // 동기화가 겹쳐 실행되면 같은 일정이 이벤트로 중복 생성될 수 있어 한 줄로 직렬화한다.
  Future<void> _syncGate = Future.value();
  Future<T> _serializeSync<T>(Future<T> Function() task) {
    final next = _syncGate.then((_) => task());
    _syncGate = next.then((_) {}).catchError((_) {});
    return next;
  }

  bool _tzReady = false;
  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    // 기기 시간대를 따르고, 실패 시 한국 시간으로 폴백.
    //
    // tz DB 로딩은 NotificationService.init()이 앱 시작 시 이미 끝내 놓으므로
    // (main.dart에서 이 서비스보다 먼저 await 된다) 여기서 initializeTimeZones()를
    // 다시 부르지 않는다. 그 함수는 마지막 줄이 setLocalLocation(UTC)라서, 다시 부르면
    // 아래 setLocalLocation이 끝날 때까지 앱 전역 tz.local이 UTC로 노출된다.
    try {
      final deviceTimeZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(deviceTimeZone));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      } catch (_) {}
    }
    _tzReady = true;
  }

  Future<bool> _ensurePermissions() async {
    var res = await _plugin.hasPermissions();
    if (res.isSuccess && res.data == true) return true;
    res = await _plugin.requestPermissions();
    return res.isSuccess && res.data == true;
  }

  /// 전용 "냥냥코치" 캘린더의 id를 확보한다. (저장된 것 재사용 → 이름으로 탐색 → 새로 생성)
  Future<String?> _ensureCalendar() async {
    final prefs = await SharedPreferences.getInstance();
    final calsRes = await _plugin.retrieveCalendars();
    final cals = calsRes.data;

    final savedId = prefs.getString(_kCalendarIdKey);
    if (savedId != null && cals != null && cals.any((c) => c.id == savedId)) {
      await _deleteDuplicateCalendars(cals, keepId: savedId);
      return savedId;
    }
    if (cals != null) {
      for (final c in cals) {
        if (c.name == _calendarName && c.isReadOnly != true && c.id != null) {
          await prefs.setString(_kCalendarIdKey, c.id!);
          await _deleteDuplicateCalendars(cals, keepId: c.id!);
          return c.id;
        }
      }
    }
    final created = await _plugin.createCalendar(
      _calendarName,
      calendarColor: const Color(0xFF8B7CFF),
      localAccountName: _calendarName,
    );
    final id = created.data;
    if (id != null) await prefs.setString(_kCalendarIdKey, id);
    return id;
  }

  Future<void> _deleteDuplicateCalendars(
    Iterable<Calendar> calendars, {
    required String keepId,
  }) async {
    for (final calendar in calendars) {
      final id = calendar.id;
      if (id == null || id == keepId) continue;
      if (calendar.name != _calendarName || calendar.isReadOnly == true) {
        continue;
      }
      try {
        await _plugin.deleteCalendar(id);
      } catch (_) {}
    }
  }

  Future<Map<String, String>> _loadEventMap() async {
    final prefs = await SharedPreferences.getInstance();
    var raw = prefs.getString(_kEventMapKey);
    if (raw == null) {
      // 옛 자리에 있던 표를 한 번 옮겨 온다. 빈손으로 시작하면 이미 캘린더에
      // 있는 이벤트를 못 알아보고 전부 다시 만들어, 같은 일정이 두 벌 생긴다.
      final legacy = prefs.getString(_kLegacyEventMapKey);
      if (legacy != null) {
        await prefs.setString(_kEventMapKey, legacy);
        raw = legacy;
      }
      // 옛 자리는 비운다. 로컬에서 사라지면 클라우드에서도 지워진다.
      await prefs.remove(_kLegacyEventMapKey);
    }
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveEventMap(Map<String, String> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEventMapKey, jsonEncode(map));
  }

  /// 진단 화면이 읽는 자리.
  static String get enabledKey => _kEnabledKey;
  static String get eventMapKey => _kEventMapKey;

  /// 연동 켜기: 권한 요청 → 전용 캘린더 확보 → 현재 일정 전체 내보내기.
  Future<AppleCalendarEnableResult> enable() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      if (!isSupportedPlatform) return AppleCalendarEnableResult.unsupported;
      await _ensureTimezone();
      if (!await _ensurePermissions()) {
        return AppleCalendarEnableResult.permissionDenied;
      }
      final previousCalendarId = prefs.getString(_kCalendarIdKey);
      final calId = await _ensureCalendar();
      if (calId == null) return AppleCalendarEnableResult.failed;
      if (previousCalendarId != null && previousCalendarId != calId) {
        await _saveEventMap({});
      }
      await prefs.setBool(_kEnabledKey, true);
      try {
        await _serializeSync(
          () async => _syncInternal(await _loadEntriesFromPrefs(), calId),
        );
      } catch (_) {}
      return AppleCalendarEnableResult.success;
    } catch (_) {
      await prefs.setBool(_kEnabledKey, false);
      return AppleCalendarEnableResult.failed;
    }
  }

  /// 연동 끄기: 플래그를 내리고, 기본적으로 전용 캘린더를 통째로 삭제(이벤트도 함께 제거).
  Future<void> disable({bool removeCalendar = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, false);
    if (!isSupportedPlatform) return;
    if (removeCalendar) {
      final calId = prefs.getString(_kCalendarIdKey);
      if (calId != null) {
        final result = await _plugin.deleteCalendar(calId);
        if (!(result.isSuccess && result.data == true)) return;
      }
      await prefs.remove(_kCalendarIdKey);
      await _saveEventMap({});
    }
  }

  /// 현재 일정 전체를 캘린더에 반영한다. 연동이 꺼져 있으면 아무 것도 하지 않는다.
  /// 앱의 일정을 아이폰 캘린더로 내보낸다. **한 방향뿐이다.**
  ///
  /// 한동안은 캘린더 쪽 변화를 앱으로 되읽었다. 그 길에서 두 가지가 나왔다.
  ///
  /// 이벤트가 조회에 안 잡히면 "사용자가 지웠다"로 읽어 루틴을 그날 쉬기로
  /// 찍었다. 그리고 되읽은 시각이 내보낸 값과 조금이라도 다르면 "옮겼다"로
  /// 읽어, 그날을 쉬기로 찍고 그 자리에 일회성 할 일을 하나 만들었다. 루틴은
  /// 90일치를 미리 내보내므로, 한 루틴이 계속 어긋나면 **90일이 통째로**
  /// 쉬는 날이 되고 90개의 유령 할 일이 생긴다. 2026-09-09에 실제로 그랬다 —
  /// 매일 루틴 하나가 오늘도 내일도 안 보였고, 그날 찍힌 쉬기의 시각은 아직
  /// 오지도 않은 시각이었다(며칠 전에 미리 찍혔으니까).
  ///
  /// 애초에 캘린더에서 냥냥코치 일정을 고치는 것은 계획에 없던 쓰임이다.
  /// 되읽는 길을 통째로 없앴다. 캘린더에서 지우거나 옮긴 것은 다음 내보내기가
  /// 제자리로 되돌린다.
  Future<bool> syncAll() async {
    if (!await isEnabled()) return false;
    await _ensureTimezone();
    final prefs = await SharedPreferences.getInstance();
    final previousCalendarId = prefs.getString(_kCalendarIdKey);
    final calId = await _ensureCalendar();
    if (calId == null) return false;
    final calendarWasReplaced =
        previousCalendarId != null && previousCalendarId != calId;
    return _serializeSync(() async {
      final entries = await _loadEntriesFromPrefs();
      if (calendarWasReplaced) {
        // 사용자가 전용 캘린더 자체를 삭제하면 EventKit 이벤트 id가 전부 사라진다.
        // 새 캘린더에 다시 내보내도록 매핑만 비운다.
        await _saveEventMap({});
      }
      await _syncInternal(entries, calId);
      return false;
    });
  }

  /// tasks_screen이 저장한 항목(JSON)을 읽어 애플 캘린더 엔트리 목록으로 변환한다.
  Future<List<CalendarScheduleEntry>> _loadEntriesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, CalendarScheduleEntry>{};
    final todayKey = _calendarTodayKey();
    final scheduleTaskIds = <String>{};

    void addEntry(CalendarScheduleEntry entry) {
      if (entry.title.trim().isEmpty) return;
      entries[entry.id] = entry;
    }

    void addTaskEntry({
      required Map item,
      required String dateKey,
      required String idPrefix,
      required String kindLabel,
    }) {
      final id = item['id']?.toString();
      if (id == null) return;
      final category = item['category']?.toString() ?? 'today';
      if (category == 'schedule' ||
          id.startsWith('schedule_') ||
          scheduleTaskIds.contains(id)) {
        return;
      }
      addEntry(
        CalendarScheduleEntry(
          id: '$idPrefix:$dateKey:$id',
          dateKey: dateKey,
          title: item['text']?.toString() ?? '',
          timeStart: item['timeStart']?.toString(),
          timeEnd: item['timeEnd']?.toString(),
          kindLabel: kindLabel,
        ),
      );
    }

    try {
      final raw = prefs.getString(_kSchedulesPrefsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((dateKey, list) {
          if (list is! List) return;
          for (final item in list) {
            if (item is! Map) continue;
            final id = item['id']?.toString();
            if (id == null) continue;
            scheduleTaskIds
              ..add(id)
              ..add('schedule_$id');
            addEntry(
              CalendarScheduleEntry(
                id: 'schedule:$dateKey:$id',
                dateKey: dateKey.toString(),
                title: item['text']?.toString() ?? '',
                timeStart: item['timeStart']?.toString(),
                timeEnd: item['timeEnd']?.toString(),
                kindLabel: '일정',
              ),
            );
          }
        });
      }
    } catch (_) {}

    try {
      final raw = prefs.getString(_kTasksPrefsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final category = item['category']?.toString() ?? 'today';
          if (category == 'habit' &&
              item['source']?.toString() != 'apple_calendar_exception') {
            continue;
          }
          addTaskEntry(
            item: item,
            dateKey: todayKey,
            idPrefix: 'task',
            kindLabel: '오늘 할 일',
          );
        }
      }
    } catch (_) {}

    try {
      final raw = prefs.getString(_kPlannedTasksPrefsKey);
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((dateKey, list) {
          if (list is! List) return;
          for (final item in list) {
            if (item is! Map) continue;
            addTaskEntry(
              item: item,
              dateKey: dateKey.toString(),
              idPrefix: 'planned',
              kindLabel: '할 일',
            );
          }
        });
      }
    } catch (_) {}

    _loadHabitEntriesFromPrefs(prefs, todayKey).forEach(addEntry);
    _loadMilestoneEntriesFromPrefs(prefs).forEach(addEntry);

    return entries.values.toList();
  }

  List<CalendarScheduleEntry> _loadHabitEntriesFromPrefs(
    SharedPreferences prefs,
    String todayKey,
  ) {
    final entries = <CalendarScheduleEntry>[];
    final raw = prefs.getString(_kHabitsPrefsKey);
    if (raw == null) return entries;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return entries;
      final habitLogs = _decodeMap(prefs.getString(_kHabitLogsPrefsKey));
      final today = DateTime.tryParse(todayKey) ?? DateTime.now();
      final base = DateTime(today.year, today.month, today.day);
      for (final item in decoded) {
        if (item is! Map) continue;
        if (item['tracking'] == false) continue;
        final id = item['id']?.toString();
        final title = item['name']?.toString() ?? '';
        if (id == null || title.trim().isEmpty) continue;
        final freq = item['freq']?.toString() ?? 'daily';
        final days =
            (item['days'] as List?)
                ?.map((day) => day is num ? day.toInt() : int.tryParse('$day'))
                .whereType<int>()
                .toSet() ??
            <int>{};

        for (var offset = 0; offset < _habitSyncDays; offset++) {
          final date = base.add(Duration(days: offset));
          final dbDow = date.weekday - 1;
          final matches =
              freq == 'daily' ||
              (freq == 'weekly_count' &&
                  _shouldShowWeeklyCountHabitOnDate(item, habitLogs, date)) ||
              (freq == 'weekly' && days.contains(dbDow));
          if (!matches) continue;
          final dateKey = _dateKey(date);
          final logsForHabit = habitLogs[id];
          final logForDate = logsForHabit is Map ? logsForHabit[dateKey] : null;
          if (logForDate is Map && logForDate['status'] == 'skipped') {
            continue;
          }
          entries.add(
            CalendarScheduleEntry(
              id: 'habit:$dateKey:$id',
              dateKey: dateKey,
              title: title,
              timeStart: item['timeStart']?.toString(),
              timeEnd: item['timeEnd']?.toString(),
              kindLabel: '루틴',
            ),
          );
        }
      }
    } catch (_) {}
    return entries;
  }

  List<CalendarScheduleEntry> _loadMilestoneEntriesFromPrefs(
    SharedPreferences prefs,
  ) {
    final entries = <CalendarScheduleEntry>[];
    final raw = prefs.getString(_kVisionsPrefsKey);
    if (raw == null) return entries;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return entries;
      for (final vision in decoded) {
        if (vision is! Map) continue;
        final visionId = vision['id']?.toString() ?? 'vision';
        final milestones = vision['milestones'];
        if (milestones is! List) continue;
        for (var i = 0; i < milestones.length; i++) {
          final item = milestones[i];
          if (item is! Map) continue;
          final dateKey = item['date']?.toString();
          if (dateKey == null || DateTime.tryParse(dateKey) == null) continue;
          entries.add(
            CalendarScheduleEntry(
              id: 'milestone:$dateKey:$visionId:$i',
              dateKey: dateKey,
              title: item['text']?.toString() ?? '',
              kindLabel: '마일스톤',
            ),
          );
        }
      }
    } catch (_) {}
    return entries;
  }

  Future<void> _syncInternal(
    List<CalendarScheduleEntry> entries,
    String calId,
  ) async {
    final oldMap = await _loadEventMap();
    final newMap = <String, String>{};
    final liveIds = <String>{};

    for (final e in entries) {
      liveIds.add(e.id);
      try {
        final eventId = await _upsertEvent(calId, e, oldMap[e.id]);
        if (eventId != null) newMap[e.id] = eventId;
      } catch (_) {
        final existingEventId = oldMap[e.id];
        if (existingEventId != null) newMap[e.id] = existingEventId;
      }
    }
    // 앱에서 사라진 일정 → 캘린더 이벤트도 삭제
    for (final entry in oldMap.entries) {
      if (!liveIds.contains(entry.key)) {
        try {
          await _plugin.deleteEvent(calId, entry.value);
        } catch (_) {}
      }
    }
    await _saveEventMap(newMap);
  }

  Future<String?> _upsertEvent(
    String calId,
    CalendarScheduleEntry entry,
    String? existingEventId,
  ) async {
    final date = DateTime.tryParse(entry.dateKey);
    if (date == null) return existingEventId;

    final timing = _computeTiming(date, entry);
    Event buildEvent(String? eventId) {
      return Event(
        calId,
        eventId: eventId,
        title: entry.title.trim().isEmpty ? '일정' : entry.title,
        start: timing.start,
        end: timing.end,
        allDay: timing.allDay,
        description:
            '[${entry.kindLabel}]\n${_eventNote(_deepLinkForEntry(entry))}',
        url: Uri.parse(_deepLinkForEntry(entry)),
      );
    }

    final res = await _plugin.createOrUpdateEvent(buildEvent(existingEventId));
    if (res != null && res.isSuccess && res.data != null) {
      return res.data;
    }
    if (existingEventId != null) {
      final recreated = await _plugin.createOrUpdateEvent(buildEvent(null));
      if (recreated != null && recreated.isSuccess && recreated.data != null) {
        return recreated.data;
      }
    }
    return null;
  }

  String _deepLinkForEntry(CalendarScheduleEntry entry) {
    final route = switch (entry.id.split(':').first) {
      'schedule' => 'schedule',
      'habit' => 'habit',
      'milestone' => 'vision',
      _ => 'tasks',
    };
    final encodedDate = Uri.encodeQueryComponent(entry.dateKey);
    final encodedId = Uri.encodeQueryComponent(entry.id);
    return '$_deepLinkBase/$route?date=$encodedDate&id=$encodedId';
  }

  String _eventNote(String deepLink) {
    return '냥냥코치에서 보낸 항목이에요.\n수정·삭제는 냥냥코치 앱에서 해주세요.\n바로가기: $deepLink';
  }

  _EventTiming _computeTiming(DateTime date, CalendarScheduleEntry entry) {
    final start = _parseHhMm(entry.timeStart);
    if (start != null) {
      final startDt = tz.TZDateTime(
        tz.local,
        date.year,
        date.month,
        date.day,
        start.$1,
        start.$2,
      );
      final end = _parseHhMm(entry.timeEnd);
      var endDt = end != null
          ? tz.TZDateTime(
              tz.local,
              date.year,
              date.month,
              date.day,
              end.$1,
              end.$2,
            )
          : startDt.add(const Duration(hours: 1));
      if (!endDt.isAfter(startDt)) {
        endDt = startDt.add(const Duration(hours: 1));
      }
      return _EventTiming(start: startDt, end: endDt, allDay: false);
    }
    // 시간 미정 → iOS 종일 이벤트. device_calendar의 iOS 구현은 endDate를
    // 그대로 EventKit에 전달하므로 다음날 00:00을 넣으면 화면에서 이틀짜리처럼
    // 보일 수 있다. 같은 날짜를 넣어 한 날짜 칸에만 표시되게 한다.
    final dayStart = tz.TZDateTime(tz.local, date.year, date.month, date.day);
    return _EventTiming(start: dayStart, end: dayStart, allDay: true);
  }

  (int, int)? _parseHhMm(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return (h, m);
  }

  String _calendarTodayKey() {
    return _dateKey(DateTime.now());
  }

  String _dateKey(DateTime date) => RoutineSchedule.dateKey(date);

  bool _shouldShowWeeklyCountHabitOnDate(
    Map<dynamic, dynamic> habit,
    Map<String, dynamic> habitLogs,
    DateTime date,
  ) {
    final habitId = habit['id']?.toString();
    if (habitId == null) return true;
    final logsForHabit = habitLogs[habitId];
    if (logsForHabit is! Map) return true;

    return RoutineSchedule.shouldShowWeeklyCountOnDate(
      rawWeeklyTargetCount: habit['weeklyTargetCount'],
      rawCreatedAt: habit['createdAt'],
      logs: logsForHabit,
      date: date,
    );
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.map((key, value) => MapEntry(key.toString(), value))
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class _EventTiming {
  final tz.TZDateTime start;
  final tz.TZDateTime end;
  final bool allDay;
  const _EventTiming({
    required this.start,
    required this.end,
    required this.allDay,
  });
}
