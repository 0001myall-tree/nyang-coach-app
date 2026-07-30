import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_resistance_event.dart';

// 하기 싫다고 말한 일의 저장/조회.
//
// 2026-07-30, 여기 있던 저항 예측·선제개입 층을 전부 걷어냈다: 태스크를 카테고리로 묶어
// 점수와 신뢰도를 매기고(그룹 프로필), 문턱을 넘으면 코치가 먼저 화제를 꺼내거나
// 시간 지정 일정 전에 배지로 찔러보던 것. 채팅 칩과 마스터 코치 인사로 코치가 먼저
// 말을 거는 자리가 이미 넓어져서, 점수로 개입 대상을 고르는 층은 없애기로 했다.
//
// 남은 몫은 하나다 — 저녁에 "하기 싫다던 그 일, 결국 하셨네요"라고 짚을 근거를 남기는 것.
class TaskResistanceService {
  static const String _eventsKey = 'nyang_resistance_events';

  /// 저녁 문구는 오늘 것만 읽지만, 하루 경계를 넘겨 앱이 켜져 있는 경우가 있어 며칠은 남긴다.
  static const int retentionDays = 7;

  /// 태스크당 보관 상한. 같은 일을 며칠에 걸쳐 싫다고 해도 기록이 무한히 쌓이지 않게 한다.
  static const int maxEventsPerTask = 12;

  static Future<List<TaskResistanceEvent>> _loadAll(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_eventsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (e) => TaskResistanceEvent.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(
    SharedPreferences prefs,
    List<TaskResistanceEvent> events,
  ) async {
    await prefs.setString(
      _eventsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  static List<TaskResistanceEvent> _pruneExpired(
    List<TaskResistanceEvent> events,
  ) {
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    return events.where((e) {
      final d = DateTime.tryParse(e.date);
      if (d == null) return true;
      return d.isAfter(cutoff);
    }).toList();
  }

  /// 태스크당 최근 [maxEventsPerTask]건 초과분은 오래된 것부터 삭제.
  static List<TaskResistanceEvent> _enforcePerTaskCap(
    List<TaskResistanceEvent> events,
  ) {
    final byTask = <String, List<TaskResistanceEvent>>{};
    for (final e in events) {
      byTask.putIfAbsent(e.taskId, () => []).add(e);
    }
    final result = <TaskResistanceEvent>[];
    for (final group in byTask.values) {
      group.sort((a, b) => a.date.compareTo(b.date)); // 오래된 순
      final overflow = group.length - maxEventsPerTask;
      result.addAll(overflow > 0 ? group.sublist(overflow) : group);
    }
    return result;
  }

  /// 명시적 저항신호 1건 기록. 같은 taskId+date 조합이 이미 있으면 무시(하루 중복 방지).
  static Future<void> recordExplicitSignal({
    required String taskId,
    required String taskText,
    required String date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var events = _pruneExpired(await _loadAll(prefs));

    final alreadyLoggedToday = events.any(
      (e) => e.taskId == taskId && e.date == date,
    );
    if (alreadyLoggedToday) return;

    events.add(
      TaskResistanceEvent(
        id: 'evt_${DateTime.now().millisecondsSinceEpoch}_${taskId.hashCode}',
        taskId: taskId,
        taskText: taskText,
        date: date,
        signalType: 'explicit',
        // 신호가 발생한 시점엔 아직 완료 여부를 모름. 실제 완료 시 [onTaskCompleted]로 갱신.
        completedEventually: false,
        totalTasksThatDay: 0,
      ),
    );

    await _saveAll(prefs, _enforcePerTaskCap(events));
  }

  /// 사용자 메시지에서 오늘 미완료 태스크 중 언급된 게 있는지 정규화 부분일치로 판별해 기록.
  /// 기존 _normalizeRestText와 동일한 방식(공백 제거)을 써서 판정 기준을 통일한다.
  /// 태스크 목록은 직접 로드하므로 호출부는 메시지 텍스트만 넘기면 된다.
  ///
  /// 계획에 없는 일("설거지 하기 싫어"인데 설거지가 목록에 없음)은 붙일 taskId가 없어
  /// 기록되지 않는다. 그 경우는 저녁 인사가 직접 물어본다(`eveningOffPlanAsk`).
  static Future<void> detectAndRecordFromMessage(String message) async {
    final normalizedMessage = message.replaceAll(RegExp(r'\s+'), '');
    if (normalizedMessage.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks == null) return;

    List<dynamic> tasksList;
    try {
      tasksList = jsonDecode(rawTasks) as List;
    } catch (_) {
      return;
    }

    final todayTasks = tasksList.whereType<Map>().where(
      (t) =>
          t['category'] == 'today' ||
          t['category'] == 'habit' ||
          t['category'] == 'schedule',
    );
    final incompleteTasks = todayTasks.where((t) => t['done'] != true);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (final task in incompleteTasks) {
      final taskText = task['text'] as String?;
      final taskId = task['id']?.toString();
      if (taskText == null || taskId == null || taskText.trim().length < 2) {
        continue; // 너무 짧은 텍스트는 오탐 위험이 커서 스킵
      }

      final normalizedTaskText = taskText.replaceAll(RegExp(r'\s+'), '');
      if (normalizedMessage.contains(normalizedTaskText)) {
        await recordExplicitSignal(
          taskId: taskId,
          taskText: taskText,
          date: today,
        );
      }
    }
  }

  /// 태스크가 실제로 완료됐을 때, 그날 남아있는 저항이벤트에 완료를 붙인다.
  /// tasks_screen.dart `_toggleTask`의 완료 처리 지점에 연결돼 있다.
  static Future<void> onTaskCompleted({
    required String taskId,
    required String date,
    required int completionOrder,
    required int totalTasksThatDay,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await _loadAll(prefs);

    var changed = false;
    final updated = events.map((e) {
      if (e.taskId == taskId && e.date == date && !e.completedEventually) {
        changed = true;
        return TaskResistanceEvent(
          id: e.id,
          taskId: e.taskId,
          taskText: e.taskText,
          date: e.date,
          signalType: e.signalType,
          completedEventually: true,
          completionOrder: completionOrder,
          totalTasksThatDay: totalTasksThatDay,
        );
      }
      return e;
    }).toList();

    if (changed) await _saveAll(prefs, updated);
  }

  static Future<List<TaskResistanceEvent>> getAllEvents() async {
    final prefs = await SharedPreferences.getInstance();
    return _pruneExpired(await _loadAll(prefs));
  }
}
