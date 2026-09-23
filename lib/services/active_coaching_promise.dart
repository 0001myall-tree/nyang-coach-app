/// 사용자가 정한 "몇 시에 할게"를 실제로 적어두는 자리.
///
/// 두 군데에 남긴다.
///
/// - **할 일의 시작 시각**: 그러면 화면·위젯·캘린더·기존 시작 카드가 딸려온다.
///   사용자 눈에도 약속이 남는다 — 4시를 골랐는데 화면 어디에도 안 보이면 진짜
///   약속 같지가 않다.
/// - **추적**: 원래 시각과 함께 적는다. 덮어쓰기만 하면 "3시에 하기로 했다가
///   못 했다"가 사라지는데, 세 번째 미루는 사람에게는 다른 말을 해야 한다.
///
/// 시작 시각에 넣는 것만으로는 부족하다. 기존 시작 카드는 "아직 손도 안 댄 일
/// 중 가장 이른 것 하나"만 보기 때문에, 하다 멈춘 일은 빠지고 약속보다 이른
/// 일이 있으면 그쪽이 자리를 가져간다. 약속 시각은 적극 코칭이 자기가 따로 본다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'active_coaching_state.dart';
import 'active_coaching_time.dart';
import 'task_completion_service.dart';

class ActiveCoachingPromise {
  const ActiveCoachingPromise._();

  /// 그 일을 [at]에 하기로 적어둔다. 그런 일이 없으면 false.
  ///
  /// 값을 몰래 바꾸지 않는다. 부르는 쪽이 "4시로 시작 설정했어. 그때 알려줄게"를
  /// 반드시 함께 보여줘야 한다 — 이 앱은 값을 바꿀 때 알리는 쪽이다.
  static Future<bool> keep({
    required String taskId,
    required DateTime at,
    String? reason,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final tasks = _decode(prefs.getString(TaskCompletionService.tasksKey));
    final task = _find(tasks, taskId);
    if (task == null) return false;

    final day = ActiveCoachingStore.readDay(prefs, at);
    final before = day.of(taskId);

    // 원래 시각은 첫 약속에서만 챙긴다. 두 번째 약속에서 다시 읽으면 첫
    // 약속으로 덮인 값을 "원래 시각"으로 적게 된다.
    final original = before.promisedAt == null
        ? task['timeStart']?.toString()
        : before.originalStart;

    task['timeStart'] = ActiveCoachingTime.format(at);
    // 시작을 뒤로 미뤄 끝보다 늦어졌으면 끝은 버린다. 끝이 시작보다 앞에 있는
    // 일정은 화면에서 읽을 수가 없다.
    final end = _minutes(task['timeEnd']?.toString());
    if (end != null && end <= at.hour * 60 + at.minute) {
      task.remove('timeEnd');
    }

    await prefs.setString(TaskCompletionService.tasksKey, jsonEncode(tasks));
    await ActiveCoachingStore.writeDay(
      prefs,
      day.put(
        taskId,
        before.copyWith(
          promisedAt: at,
          originalStart: original,
          reason: reason,
        ),
      ),
    );
    // 화면이 열려 있는 채로 여기서 고쳤을 수 있다. 그 화면이 메모리에 든 옛
    // 목록을 그대로 저장하면 방금 정한 약속이 되돌아간다.
    await TaskCompletionService.markChangedNow();
    return true;
  }

  /// 그 일에 말을 걸었다고 적는다.
  static Future<void> noteNudged({
    required String taskId,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final day = ActiveCoachingStore.readDay(prefs, at);
    final before = day.of(taskId);
    await ActiveCoachingStore.writeDay(
      prefs,
      day.put(
        taskId,
        before.copyWith(lastNudgedAt: at, nudges: before.nudges + 1),
      ),
    );
  }

  /// 사용자가 내린 결정을 적는다. 그날 그 일에는 더 말 걸지 않는다.
  static Future<void> decide({
    required String taskId,
    required ActiveCoachingDecision decision,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final day = ActiveCoachingStore.readDay(prefs, at);
    await ActiveCoachingStore.writeDay(
      prefs,
      day.put(taskId, day.of(taskId).copyWith(decision: decision)),
    );
  }

  /// 사용자가 목록에서 직접 고른 일이라고 적는다.
  ///
  /// 본인이 "이건 할 수 있다"고 말한 일이라, 다음에 개입할 때 먼저 본다.
  static Future<void> notePickedByUser({
    required String taskId,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final day = ActiveCoachingStore.readDay(prefs, at);
    await ActiveCoachingStore.writeDay(
      prefs,
      day.put(taskId, day.of(taskId).copyWith(pickedByUser: true)),
    );
  }

  static List _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  static Map? _find(List tasks, String taskId) {
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['id']?.toString() == taskId) return item;
    }
    return null;
  }

  static int? _minutes(String? hhmm) {
    final parts = (hhmm ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }
}
