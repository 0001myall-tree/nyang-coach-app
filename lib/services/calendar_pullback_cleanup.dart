import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reset_service.dart';
import 'tasks_sync_service.dart';

/// 아이폰 캘린더를 되읽던 시절이 남긴 것을 한 번 치운다.
///
/// 그 길은 캘린더에서 되읽은 시각이 내보낸 값과 조금이라도 다르면 "옮겼다"로
/// 읽었다. 그러면 그날을 쉬기로 찍고, 그 자리에 일회성 할 일을 하나 만들었다.
/// 루틴은 90일치를 미리 내보내므로, 한 루틴이 계속 어긋나면 **90일이 통째로**
/// 쉬는 날이 되고 90개의 유령 할 일이 생긴다. 2026-09-09에 실제로 그랬다.
///
/// 길은 없앴지만 이미 적힌 것은 그대로 남는다. 클라우드에도 올라가 있어서
/// 기기를 새로 깔아도 따라온다.
///
/// 무엇을 치우고 무엇을 남기는지가 중요하다:
/// - 유령 할 일(`habit_exception_...`)은 전부 치운다. 앱에는 이걸 만드는 다른
///   길이 없어서, 남아 있는 것은 모두 그 시절의 것이다.
/// - 쉬기 기록은 **아직 오지 않은 날짜만** 치운다. 앱에는 미래를 미리 쉬는
///   날로 정하는 기능이 없으니 그것도 전부 그 시절의 것이다. 오늘과 지난 날은
///   사용자가 직접 누른 것일 수 있어서 건드리지 않는다.
class CalendarPullbackCleanup {
  const CalendarPullbackCleanup._();

  /// 한 번만 돌면 된다는 표시. 'nyang_' 접두어를 쓰지 않는다 — 이 기기에서
  /// 치웠다는 것은 기기별 사실이라 클라우드가 덮으면 안 된다.
  static const String doneKey = 'calendar_pullback_cleanup_done';

  static const String _tasksKey = 'nyang_tasks';
  static const String _plannedKey = 'nyang_today_tasks_by_date';
  static const String _habitLogsKey = 'nyang_habit_logs';

  static const String _exceptionIdPrefix = 'habit_exception_';

  /// 치운 게 있으면 true.
  ///
  /// [cloudRestorePending]은 테스트에서만 넘긴다. 기본값은 파이어베이스를
  /// 보는데, 테스트에는 그게 없다.
  static Future<bool> runOnce({
    DateTime? now,
    bool? cloudRestorePending,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(doneKey) ?? false) return false;
    // 클라우드에서 아직 못 받아왔으면 치울 대상이 안 보인다. 여기서 끝냈다고
    // 적어버리면, 잠시 뒤 도착하는 값은 영영 안 치워진다.
    final pending =
        cloudRestorePending ?? DailyResetService.isCloudRestorePending(prefs);
    if (pending) return false;

    final today = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    var changed = false;

    changed = _cleanTasks(prefs) || changed;
    changed = _cleanPlanned(prefs) || changed;
    changed = _cleanFutureSkips(prefs, today) || changed;

    await prefs.setBool(doneKey, true);
    if (changed) TasksSyncService.scheduleSyncToCloud();
    return changed;
  }

  static bool _cleanTasks(SharedPreferences prefs) {
    final raw = prefs.getString(_tasksKey);
    if (raw == null) return false;
    final list = _decodeList(raw);
    if (list == null) return false;
    final kept = list.where((t) => !_isExceptionTask(t)).toList();
    if (kept.length == list.length) return false;
    prefs.setString(_tasksKey, jsonEncode(kept));
    return true;
  }

  static bool _cleanPlanned(SharedPreferences prefs) {
    final raw = prefs.getString(_plannedKey);
    if (raw == null) return false;
    final map = _decodeMap(raw);
    if (map == null) return false;

    var changed = false;
    final cleaned = <String, dynamic>{};
    map.forEach((dateKey, value) {
      if (value is! List) {
        cleaned[dateKey] = value;
        return;
      }
      final kept = value.where((t) => !_isExceptionTask(t)).toList();
      if (kept.length != value.length) changed = true;
      // 유령만 들어 있던 날짜는 칸까지 없앤다. 빈 칸을 남기면 플래너가 그날을
      // "계획을 세웠다가 다 지운 날"로 읽는다.
      if (kept.isNotEmpty) cleaned[dateKey] = kept;
    });
    if (!changed) return false;
    prefs.setString(_plannedKey, jsonEncode(cleaned));
    return true;
  }

  static bool _cleanFutureSkips(SharedPreferences prefs, String today) {
    final raw = prefs.getString(_habitLogsKey);
    if (raw == null) return false;
    final logs = _decodeMap(raw);
    if (logs == null) return false;

    var changed = false;
    final cleaned = <String, dynamic>{};
    logs.forEach((habitId, byDate) {
      if (byDate is! Map) {
        cleaned[habitId] = byDate;
        return;
      }
      final keptDays = <String, dynamic>{};
      byDate.forEach((dateKey, log) {
        final isFuture = dateKey.toString().compareTo(today) > 0;
        final isSkip = log is Map && log['status'] == 'skipped';
        if (isFuture && isSkip) {
          changed = true;
          return;
        }
        keptDays[dateKey.toString()] = log;
      });
      cleaned[habitId] = keptDays;
    });
    if (!changed) return false;
    prefs.setString(_habitLogsKey, jsonEncode(cleaned));
    return true;
  }

  @visibleForTesting
  static bool isExceptionTask(Object? task) => _isExceptionTask(task);

  static bool _isExceptionTask(Object? task) =>
      task is Map && task['id'].toString().startsWith(_exceptionIdPrefix);

  static List<dynamic>? _decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _decodeMap(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? decoded.map((k, v) => MapEntry(k.toString(), v))
          : null;
    } catch (_) {
      return null;
    }
  }
}
