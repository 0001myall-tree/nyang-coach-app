import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

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
  // 냥냥코치 일정 id -> 애플 캘린더 이벤트 id 매핑 (기기 로컬에만 저장)
  static const String _kEventMapKey = 'nyang_apple_calendar_event_map';
  // tasks_screen이 저장하는 SharedPreferences 키. 서비스는 여기서 직접 읽는다.
  static const String _kSchedulesPrefsKey = 'nyang_schedules';
  static const String _kTasksPrefsKey = 'nyang_tasks';
  static const String _kPlannedTasksPrefsKey = 'nyang_today_tasks_by_date';
  static const String _kHabitsPrefsKey = 'nyang_habits';
  static const String _kHabitLogsPrefsKey = 'nyang_habit_logs';
  static const String _kVisionsPrefsKey = 'nyang_visions';
  static const String _calendarName = '냥냥코치';
  // 이벤트를 탭하면 기존 위젯 딥링크 경로로 앱이 열리고 오늘 할 일 탭으로 진입한다.
  static const String _deepLink = 'nyangcoach://widget/cat/tasks';
  static const String _eventNote =
      '냥냥코치에서 보낸 항목이에요.\n수정·삭제는 냥냥코치 앱에서 해주세요.\n바로가기: $_deepLink';
  static const int _habitSyncDays = 90;

  bool get isSupportedPlatform => Platform.isIOS;

  Future<bool> isEnabled() async {
    if (!isSupportedPlatform) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? false;
  }

  // 동기화가 겹쳐 실행되면 같은 일정이 이벤트로 중복 생성될 수 있어 한 줄로 직렬화한다.
  Future<void> _syncGate = Future.value();
  Future<void> _serializeSync(Future<void> Function() task) {
    final next = _syncGate.then((_) => task());
    _syncGate = next.catchError((_) {});
    return next;
  }

  bool _tzReady = false;
  Future<void> _ensureTimezone() async {
    if (_tzReady) return;
    // notification_service와 동일하게 기기 시간대를 따르고, 실패 시 한국 시간으로 폴백.
    try {
      tzdata.initializeTimeZones();
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
      return savedId;
    }
    if (cals != null) {
      for (final c in cals) {
        if (c.name == _calendarName && c.isReadOnly != true && c.id != null) {
          await prefs.setString(_kCalendarIdKey, c.id!);
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

  Future<Map<String, String>> _loadEventMap() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kEventMapKey);
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

  /// 연동 켜기: 권한 요청 → 전용 캘린더 확보 → 현재 일정 전체 내보내기.
  Future<AppleCalendarEnableResult> enable() async {
    if (!isSupportedPlatform) return AppleCalendarEnableResult.unsupported;
    await _ensureTimezone();
    if (!await _ensurePermissions()) {
      return AppleCalendarEnableResult.permissionDenied;
    }
    final calId = await _ensureCalendar();
    if (calId == null) return AppleCalendarEnableResult.failed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, true);
    await _serializeSync(
      () async => _syncInternal(await _loadEntriesFromPrefs(), calId),
    );
    return AppleCalendarEnableResult.success;
  }

  /// 연동 끄기: 플래그를 내리고, 기본적으로 전용 캘린더를 통째로 삭제(이벤트도 함께 제거).
  Future<void> disable({bool removeCalendar = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, false);
    if (!isSupportedPlatform) return;
    if (removeCalendar) {
      final calId = prefs.getString(_kCalendarIdKey);
      if (calId != null) {
        await _plugin.deleteCalendar(calId);
      }
      await prefs.remove(_kCalendarIdKey);
      await _saveEventMap({});
    }
  }

  /// 현재 일정 전체를 캘린더에 반영한다. 연동이 꺼져 있으면 아무 것도 하지 않는다.
  Future<void> syncAll({bool pullExternalChanges = true}) async {
    if (!await isEnabled()) return;
    await _ensureTimezone();
    final calId = await _ensureCalendar();
    if (calId == null) return;
    await _serializeSync(() async {
      var entries = await _loadEntriesFromPrefs();
      final oldMap = await _loadEventMap();
      if (pullExternalChanges && oldMap.isNotEmpty) {
        await _pullExternalChanges(calId, entries, oldMap);
        entries = await _loadEntriesFromPrefs();
      }
      await _syncInternal(entries, calId);
    });
  }

  /// tasks_screen이 저장한 항목(JSON)을 읽어 애플 캘린더 엔트리 목록으로 변환한다.
  Future<List<CalendarScheduleEntry>> _loadEntriesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = <String, CalendarScheduleEntry>{};
    final todayKey = _getTodayKey(prefs);

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
      if (category == 'schedule') return;
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
              freq == 'daily' || (freq == 'weekly' && days.contains(dbDow));
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
              kindLabel: '습관',
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
      final eventId = await _upsertEvent(calId, e, oldMap[e.id]);
      if (eventId != null) newMap[e.id] = eventId;
    }
    // 앱에서 사라진 일정 → 캘린더 이벤트도 삭제
    for (final entry in oldMap.entries) {
      if (!liveIds.contains(entry.key)) {
        await _plugin.deleteEvent(calId, entry.value);
      }
    }
    await _saveEventMap(newMap);
  }

  Future<void> _pullExternalChanges(
    String calId,
    List<CalendarScheduleEntry> entries,
    Map<String, String> oldMap,
  ) async {
    final entryById = {for (final entry in entries) entry.id: entry};
    final ids = oldMap.values.toList();
    if (ids.isEmpty) return;

    final res = await _plugin.retrieveEvents(
      calId,
      RetrieveEventsParams(eventIds: ids),
    );
    if (!res.isSuccess) return;
    final events = res.data ?? const <Event>[];
    final eventById = {
      for (final event in events)
        if (event.eventId != null) event.eventId!: event,
    };

    for (final mapEntry in oldMap.entries) {
      final source = entryById[mapEntry.key];
      if (source == null) continue;
      final event = eventById[mapEntry.value];
      if (event == null) {
        await _applyExternalDelete(source);
      } else {
        await _applyExternalUpdate(source, event);
      }
    }
  }

  Future<void> _applyExternalDelete(CalendarScheduleEntry source) async {
    final parts = source.id.split(':');
    if (parts.isEmpty) return;
    switch (parts.first) {
      case 'schedule':
        if (parts.length >= 3) {
          await _deleteSchedule(parts[1], parts.sublist(2).join(':'));
        }
        break;
      case 'task':
        if (parts.length >= 3) {
          await _deleteTask(
            parts[1],
            parts.sublist(2).join(':'),
            fromToday: true,
          );
        }
        break;
      case 'planned':
        if (parts.length >= 3) {
          await _deleteTask(
            parts[1],
            parts.sublist(2).join(':'),
            fromToday: false,
          );
        }
        break;
      case 'habit':
        if (parts.length >= 3) {
          await _skipHabitOnDate(parts[1], parts.sublist(2).join(':'));
        }
        break;
      case 'milestone':
        if (parts.length >= 4) {
          await _clearMilestoneDate(
            dateKey: parts[1],
            visionId: parts[2],
            milestoneIndex: int.tryParse(parts[3]),
          );
        }
        break;
    }
  }

  Future<void> _applyExternalUpdate(
    CalendarScheduleEntry source,
    Event event,
  ) async {
    final parts = source.id.split(':');
    if (parts.isEmpty) return;

    final patch = _eventPatch(source, event);
    if (!patch.hasChanges) return;

    switch (parts.first) {
      case 'schedule':
        if (parts.length >= 3) {
          await _updateSchedule(
            oldDateKey: parts[1],
            id: parts.sublist(2).join(':'),
            patch: patch,
          );
        }
        break;
      case 'task':
        if (parts.length >= 3) {
          await _updateTask(
            oldDateKey: parts[1],
            id: parts.sublist(2).join(':'),
            fromToday: true,
            patch: patch,
          );
        }
        break;
      case 'planned':
        if (parts.length >= 3) {
          await _updateTask(
            oldDateKey: parts[1],
            id: parts.sublist(2).join(':'),
            fromToday: false,
            patch: patch,
          );
        }
        break;
      case 'habit':
        if (parts.length >= 3) {
          await _createHabitException(
            oldDateKey: parts[1],
            habitId: parts.sublist(2).join(':'),
            patch: patch,
          );
        }
        break;
      case 'milestone':
        if (parts.length >= 4) {
          await _updateMilestone(
            dateKey: parts[1],
            visionId: parts[2],
            milestoneIndex: int.tryParse(parts[3]),
            patch: patch,
          );
        }
        break;
    }
  }

  _ExternalEventPatch _eventPatch(CalendarScheduleEntry source, Event event) {
    final title = (event.title ?? '').trim().isEmpty
        ? source.title
        : event.title!.trim();
    final start = event.start;
    final dateKey = start == null ? source.dateKey : _dateKey(start);
    String? timeStart;
    String? timeEnd;
    if (event.allDay != true && start != null) {
      timeStart = _storedTime(start);
      if (source.timeEnd != null && event.end != null) {
        timeEnd = _storedTime(event.end!);
      }
    }
    return _ExternalEventPatch(
      title: title,
      dateKey: dateKey,
      timeStart: timeStart,
      timeEnd: timeEnd,
      hasChanges:
          title != source.title ||
          dateKey != source.dateKey ||
          timeStart != source.timeStart ||
          timeEnd != source.timeEnd,
    );
  }

  Future<void> _deleteSchedule(String dateKey, String id) async {
    final prefs = await SharedPreferences.getInstance();
    final schedules = _decodeMap(prefs.getString(_kSchedulesPrefsKey));
    final list = List<dynamic>.from(schedules[dateKey] as List? ?? const []);
    list.removeWhere((item) => item is Map && item['id']?.toString() == id);
    if (list.isEmpty) {
      schedules.remove(dateKey);
    } else {
      schedules[dateKey] = list;
    }
    await prefs.setString(_kSchedulesPrefsKey, jsonEncode(schedules));
  }

  Future<void> _updateSchedule({
    required String oldDateKey,
    required String id,
    required _ExternalEventPatch patch,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final schedules = _decodeMap(prefs.getString(_kSchedulesPrefsKey));
    Map<String, dynamic>? target;
    String? foundKey;
    schedules.forEach((dateKey, value) {
      if (target != null || value is! List) return;
      for (final item in value) {
        if (item is Map && item['id']?.toString() == id) {
          target = Map<String, dynamic>.from(item);
          foundKey = dateKey;
          break;
        }
      }
    });
    if (target == null) return;

    final sourceKey = foundKey ?? oldDateKey;
    final oldList = List<dynamic>.from(
      schedules[sourceKey] as List? ?? const [],
    );
    oldList.removeWhere((item) => item is Map && item['id']?.toString() == id);
    if (oldList.isEmpty) {
      schedules.remove(sourceKey);
    } else {
      schedules[sourceKey] = oldList;
    }

    _applyPatchToItem(target!, patch);
    _detachRecurringException(target!);
    final newList = List<dynamic>.from(
      schedules[patch.dateKey] as List? ?? const [],
    );
    newList.add(target);
    schedules[patch.dateKey] = newList;
    await prefs.setString(_kSchedulesPrefsKey, jsonEncode(schedules));
  }

  Future<void> _deleteTask(
    String dateKey,
    String id, {
    required bool fromToday,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (fromToday || dateKey == _getTodayKey(prefs)) {
      final tasks = _decodeList(prefs.getString(_kTasksPrefsKey));
      tasks.removeWhere((item) => item is Map && item['id']?.toString() == id);
      await prefs.setString(_kTasksPrefsKey, jsonEncode(tasks));
      return;
    }

    final planned = _decodeMap(prefs.getString(_kPlannedTasksPrefsKey));
    final list = List<dynamic>.from(planned[dateKey] as List? ?? const []);
    list.removeWhere((item) => item is Map && item['id']?.toString() == id);
    if (list.isEmpty) {
      planned.remove(dateKey);
    } else {
      planned[dateKey] = list;
    }
    await prefs.setString(_kPlannedTasksPrefsKey, jsonEncode(planned));
  }

  Future<void> _updateTask({
    required String oldDateKey,
    required String id,
    required bool fromToday,
    required _ExternalEventPatch patch,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final todayKey = _getTodayKey(prefs);
    final tasks = _decodeList(prefs.getString(_kTasksPrefsKey));
    final planned = _decodeMap(prefs.getString(_kPlannedTasksPrefsKey));

    Map<String, dynamic>? target;
    final emptyKeys = <String>[];
    tasks.removeWhere((item) {
      final matches = item is Map && item['id']?.toString() == id;
      if (matches) target = Map<String, dynamic>.from(item);
      return matches;
    });
    planned.forEach((dateKey, value) {
      if (value is! List) return;
      final list = List<dynamic>.from(value);
      list.removeWhere((item) {
        final matches = item is Map && item['id']?.toString() == id;
        if (matches && target == null) target = Map<String, dynamic>.from(item);
        return matches;
      });
      if (list.isEmpty) emptyKeys.add(dateKey);
      planned[dateKey] = list;
    });
    for (final key in emptyKeys) {
      planned.remove(key);
    }
    if (target == null) return;

    _applyPatchToItem(target!, patch);
    target!.putIfAbsent('category', () => 'today');
    if (patch.dateKey == todayKey) {
      tasks.add(target);
    } else {
      final newList = List<dynamic>.from(
        planned[patch.dateKey] as List? ?? const [],
      );
      newList.add(target);
      planned[patch.dateKey] = newList;
    }
    await prefs.setString(_kTasksPrefsKey, jsonEncode(tasks));
    await prefs.setString(_kPlannedTasksPrefsKey, jsonEncode(planned));
  }

  Future<void> _skipHabitOnDate(String dateKey, String habitId) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = _decodeMap(prefs.getString(_kHabitLogsPrefsKey));
    final habitLogs = Map<String, dynamic>.from(
      logs[habitId] as Map? ?? const <String, dynamic>{},
    );
    habitLogs[dateKey] = {
      'done': false,
      'status': 'skipped',
      'skippedAt': DateTime.now().toIso8601String(),
    };
    logs[habitId] = habitLogs;
    await prefs.setString(_kHabitLogsPrefsKey, jsonEncode(logs));
  }

  Future<void> _createHabitException({
    required String oldDateKey,
    required String habitId,
    required _ExternalEventPatch patch,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final habits = _decodeList(prefs.getString(_kHabitsPrefsKey));
    Map<String, dynamic>? habit;
    for (final item in habits) {
      if (item is Map && item['id']?.toString() == habitId) {
        habit = Map<String, dynamic>.from(item);
        break;
      }
    }
    if (habit == null) return;

    await _skipHabitOnDate(oldDateKey, habitId);

    final exceptionId = _habitExceptionTaskId(habitId, patch.dateKey);
    final task = _habitExceptionTask(
      habit: habit,
      habitId: habitId,
      id: exceptionId,
      patch: patch,
    );

    final todayKey = _getTodayKey(prefs);
    final todayTasks = _decodeList(prefs.getString(_kTasksPrefsKey));
    final planned = _decodeMap(prefs.getString(_kPlannedTasksPrefsKey));

    todayTasks.removeWhere(
      (item) =>
          item is Map &&
          (item['id']?.toString() == exceptionId ||
              item['id']?.toString() == _habitTaskId(habitId, oldDateKey)),
    );
    final emptyKeys = <String>[];
    planned.forEach((dateKey, value) {
      if (value is! List) return;
      final list = List<dynamic>.from(value)
        ..removeWhere(
          (item) =>
              item is Map &&
              (item['id']?.toString() == exceptionId ||
                  item['id']?.toString() == _habitTaskId(habitId, oldDateKey)),
        );
      if (list.isEmpty) emptyKeys.add(dateKey);
      planned[dateKey] = list;
    });
    for (final key in emptyKeys) {
      planned.remove(key);
    }

    if (patch.dateKey == todayKey) {
      todayTasks.add(task);
    } else {
      final list = List<dynamic>.from(
        planned[patch.dateKey] as List? ?? const [],
      );
      list.add(task);
      planned[patch.dateKey] = list;
    }

    await prefs.setString(_kTasksPrefsKey, jsonEncode(todayTasks));
    await prefs.setString(_kPlannedTasksPrefsKey, jsonEncode(planned));
  }

  Map<String, dynamic> _habitExceptionTask({
    required Map<String, dynamic> habit,
    required String habitId,
    required String id,
    required _ExternalEventPatch patch,
  }) {
    final timeStart = patch.timeStart ?? habit['timeStart']?.toString();
    final timeEnd = patch.timeEnd ?? habit['timeEnd']?.toString();
    String? time;
    if (timeStart != null) {
      time = timeEnd != null ? '$timeStart ~ $timeEnd' : timeStart;
    }
    return {
      'id': id,
      'habitId': habitId,
      'text': patch.title.trim().isEmpty
          ? (habit['name']?.toString() ?? '')
          : patch.title,
      'category': 'habit',
      'done': false,
      'isHabit': true,
      if (time != null) 'time': time,
      if (habit['habitDuration'] != null) 'duration': habit['habitDuration'],
      if (timeStart != null) 'timeStart': timeStart,
      if (timeEnd != null) 'timeEnd': timeEnd,
      'createdAt': DateTime.now().toIso8601String(),
      'isReminderEnabled': habit['isReminderEnabled'] ?? false,
      'source': 'apple_calendar_exception',
    };
  }

  String _habitTaskId(String habitId, String dateKey) {
    return 'habit_${habitId.replaceAll('.', '_')}_$dateKey';
  }

  String _habitExceptionTaskId(String habitId, String dateKey) {
    final normalized = habitId.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
    return 'habit_exception_${normalized}_$dateKey';
  }

  Future<void> _clearMilestoneDate({
    required String dateKey,
    required String visionId,
    required int? milestoneIndex,
  }) async {
    if (milestoneIndex == null) return;
    await _editMilestone(
      visionId: visionId,
      milestoneIndex: milestoneIndex,
      edit: (milestone) {
        if (milestone['date']?.toString() == dateKey) {
          milestone.remove('date');
        }
      },
    );
  }

  Future<void> _updateMilestone({
    required String dateKey,
    required String visionId,
    required int? milestoneIndex,
    required _ExternalEventPatch patch,
  }) async {
    if (milestoneIndex == null) return;
    await _editMilestone(
      visionId: visionId,
      milestoneIndex: milestoneIndex,
      edit: (milestone) {
        if (patch.title.trim().isNotEmpty) milestone['text'] = patch.title;
        milestone['date'] = patch.dateKey;
      },
    );
  }

  Future<void> _editMilestone({
    required String visionId,
    required int milestoneIndex,
    required void Function(Map<String, dynamic> milestone) edit,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final visions = _decodeList(prefs.getString(_kVisionsPrefsKey));
    for (final vision in visions) {
      if (vision is! Map || vision['id']?.toString() != visionId) continue;
      final milestones = vision['milestones'];
      if (milestones is! List || milestoneIndex >= milestones.length) return;
      final milestone = milestones[milestoneIndex];
      if (milestone is! Map) return;
      final edited = Map<String, dynamic>.from(milestone);
      edit(edited);
      milestones[milestoneIndex] = edited;
      await prefs.setString(_kVisionsPrefsKey, jsonEncode(visions));
      return;
    }
  }

  void _applyPatchToItem(Map<String, dynamic> item, _ExternalEventPatch patch) {
    if (patch.title.trim().isNotEmpty) item['text'] = patch.title;
    item
      ..remove('time')
      ..remove('timeStart')
      ..remove('timeEnd')
      ..remove('duration');
    if (patch.timeStart != null) item['timeStart'] = patch.timeStart;
    if (patch.timeEnd != null) item['timeEnd'] = patch.timeEnd;
  }

  void _detachRecurringException(Map<String, dynamic> item) {
    if (item['isRecurring'] != true) return;
    item['isRecurring'] = false;
    item
      ..remove('recurrenceGroupId')
      ..remove('recurrenceRule');
  }

  Future<String?> _upsertEvent(
    String calId,
    CalendarScheduleEntry entry,
    String? existingEventId,
  ) async {
    final date = DateTime.tryParse(entry.dateKey);
    if (date == null) return existingEventId;

    final timing = _computeTiming(date, entry);
    final event = Event(
      calId,
      eventId: existingEventId,
      title: entry.title.trim().isEmpty ? '일정' : entry.title,
      start: timing.start,
      end: timing.end,
      allDay: timing.allDay,
      description: '[${entry.kindLabel}]\n$_eventNote',
      url: Uri.parse(_deepLink),
    );
    final res = await _plugin.createOrUpdateEvent(event);
    if (res != null && res.isSuccess && res.data != null) {
      return res.data;
    }
    return existingEventId;
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
    // 시간 미정 → 종일 이벤트
    final dayStart = tz.TZDateTime(tz.local, date.year, date.month, date.day);
    return _EventTiming(
      start: dayStart,
      end: dayStart.add(const Duration(days: 1)),
      allDay: true,
    );
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

  String _storedTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  String _getTodayKey(SharedPreferences prefs) {
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return _dateKey(base);
  }

  String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <dynamic>[];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? List<dynamic>.from(decoded) : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }
}

class _ExternalEventPatch {
  final String title;
  final String dateKey;
  final String? timeStart;
  final String? timeEnd;
  final bool hasChanges;

  const _ExternalEventPatch({
    required this.title,
    required this.dateKey,
    this.timeStart,
    this.timeEnd,
    required this.hasChanges,
  });
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
