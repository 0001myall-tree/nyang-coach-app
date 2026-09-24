/// 할 일 하나를 다른 날로 옮기는 일을 화면 밖에서 처리한다.
///
/// 플래너 화면에도 옮기는 자리가 있다. 거기는 날짜·시각·알람을 한 화면에서
/// 고르는 자리이고, 여기는 **"내일로"만** 하는 좁은 길이다. 밤에 뜬 카드에서
/// 누른 답을 앱이 켜질 때 반영하려면 화면 없이 도는 길이 필요하다.
///
/// 옮기는 것은 곧 오늘 목록에서 빼는 것이다. 이 앱에서 다른 날 일정은
/// `nyang_schedules`의 그 날짜 칸에 들어간다. 시각은 안 정한 채로 넘긴다 —
/// 밤에 카드 한 번 누르면서 내일 몇 시에 할지까지 고르게 할 수는 없고,
/// 정하고 싶으면 내일 그 화면에서 정하면 된다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'task_completion_service.dart';

class TaskMoveService {
  const TaskMoveService._();

  static const String schedulesKey = 'nyang_schedules';

  /// 그 일을 [to] 날짜로 옮긴다. 그런 일이 없으면 false.
  static Future<bool> moveStoredTask({
    required String taskId,
    required DateTime to,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final tasks = _decodeList(prefs.getString(TaskCompletionService.tasksKey));
    Map? target;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['id']?.toString() == taskId) {
        target = item;
        break;
      }
    }
    if (target == null) return false;
    if (target['done'] == true) return false;

    final text = target['text']?.toString().trim() ?? '';
    if (text.isEmpty) return false;

    tasks.removeWhere(
      (item) => item is Map && item['id']?.toString() == taskId,
    );
    await prefs.setString(TaskCompletionService.tasksKey, jsonEncode(tasks));

    // 핵심으로도 찍혀 있으면 같이 뺀다. 목록에 없는 핵심이 남으면 오늘 탭이
    // 없는 일을 붙들게 된다.
    final cores = _decodeList(
      prefs.getString(TaskCompletionService.coreTasksKey),
    );
    final before = cores.length;
    cores.removeWhere(
      (item) => item is Map && item['id']?.toString() == taskId,
    );
    if (cores.length != before) {
      await prefs.setString(
        TaskCompletionService.coreTasksKey,
        jsonEncode(cores),
      );
    }

    final schedules = _decodeMap(prefs.getString(schedulesKey));
    final dateKey = _dateKey(to);
    final day = schedules[dateKey];
    final entries = day is List ? List.from(day) : <dynamic>[];
    entries.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'text': text,
      'done': false,
      'createdAt': DateTime.now().toIso8601String(),
      // 시각을 안 정했으니 알람도 없다. 켜둔 채로 넘기면 울릴 시각이 없는
      // 알람이 남는다.
      'isReminderEnabled': false,
      // 몇 번째 미루는 중인지는 따라가야 한다. 세 번째 미루는 사람에게는
      // 다른 말을 해야 한다.
      'deferredCount': ((target['deferredCount'] as num?)?.toInt() ?? 0) + 1,
      'isRecurring': false,
      // 날짜만 옮기는 것이라 적어둔 메모는 그대로 따라간다.
      if ((target['memo']?.toString().trim() ?? '').isNotEmpty)
        'memo': target['memo'],
    });
    schedules[dateKey] = entries;
    await prefs.setString(schedulesKey, jsonEncode(schedules));

    // 화면이 열려 있는 채로 여기서 고쳤을 수 있다. 그 화면이 메모리에 든 옛
    // 목록을 그대로 저장하면 방금 옮긴 일이 오늘로 되돌아온다.
    await TaskCompletionService.markChangedNow();
    return true;
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static List _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }
}
