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
  final String id; // 일정 고유 id (이벤트 매핑 키)
  final String dateKey; // yyyy-MM-dd
  final String title;
  final String? timeStart; // HH:mm, 없으면 종일로 취급
  final String? timeEnd; // HH:mm

  const CalendarScheduleEntry({
    required this.id,
    required this.dateKey,
    required this.title,
    this.timeStart,
    this.timeEnd,
  });
}

enum AppleCalendarEnableResult { success, permissionDenied, unsupported, failed }

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
  // tasks_screen이 일정을 저장하는 SharedPreferences 키. 서비스는 여기서 직접 읽는다.
  static const String _kSchedulesPrefsKey = 'nyang_schedules';
  static const String _calendarName = '냥냥코치';
  // 이벤트를 탭하면 기존 위젯 딥링크 경로로 앱이 열리고 오늘 할 일 탭으로 진입한다.
  static const String _deepLink = 'nyangcoach://widget/cat/tasks';
  static const String _eventNote =
      '냥냥코치에서 보낸 일정이에요.\n수정·삭제는 냥냥코치 앱에서 해주세요.';

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
  Future<void> syncAll() async {
    if (!await isEnabled()) return;
    await _ensureTimezone();
    final calId = await _ensureCalendar();
    if (calId == null) return;
    await _serializeSync(
      () async => _syncInternal(await _loadEntriesFromPrefs(), calId),
    );
  }

  /// tasks_screen이 저장한 일정(JSON)을 읽어 경량 엔트리 목록으로 변환한다.
  Future<List<CalendarScheduleEntry>> _loadEntriesFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSchedulesPrefsKey);
    if (raw == null) return const [];
    final entries = <CalendarScheduleEntry>[];
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded.forEach((dateKey, list) {
        if (list is! List) return;
        for (final item in list) {
          if (item is! Map) continue;
          final id = item['id']?.toString();
          if (id == null) continue;
          entries.add(
            CalendarScheduleEntry(
              id: id,
              dateKey: dateKey,
              title: item['text']?.toString() ?? '',
              timeStart: item['timeStart']?.toString(),
              timeEnd: item['timeEnd']?.toString(),
            ),
          );
        }
      });
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
      description: _eventNote,
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
