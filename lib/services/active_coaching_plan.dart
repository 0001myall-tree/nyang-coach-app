/// 다음에 말을 걸 시각을 정한다.
///
/// 사다리(`ActiveCoachingTarget`)는 "지금 말을 건다면 무엇을 잡을까"를 답한다.
/// 여기는 그 앞의 물음에 답한다 — **언제 걸까**.
///
/// 그 시각을 미리 알아야 하는 이유는 두 폰 다 미리 걸어둬야 하기 때문이다.
/// 안드로이드는 알람을 걸어야 앱이 꺼진 사이에도 깨어나고, 아이폰은 아예 예약할
/// 때 문구까지 굳는다. "지금 상태를 보고 그때 정한다"는 길이 없다.
///
/// 부를 자리는 셋이다.
///
/// ```
/// 약속 시각          사용자가 정한 시각. 예산 밖이고 매인 시간대도 뚫는다
/// 시작 시각 +30분    적어둔 시각이 지나도록 손도 안 댄 일
/// 예산이 허락하는 때  멈춘 일·핵심·"지금 뭐 할 수 있어?"가 기다리는 자리
/// ```
///
/// 셋 중 가장 이른 것 하나만 돌려준다. 여러 개를 한꺼번에 걸면 그게 곧 알림
/// 폭탄이고, 앞엣것을 다루고 나면 뒤엣것은 어차피 다시 계산해야 한다.
library;

import 'active_coaching_state.dart';
import 'active_coaching_target.dart';

/// 다음 개입 하나.
class ActiveCoachingPlan {
  const ActiveCoachingPlan({
    required this.at,
    required this.signal,
    this.taskId,
    this.taskText,
  });

  final DateTime at;

  /// 왜 부르는지. 건넬 말이 여기서 갈린다.
  final ActiveCoachingSignal signal;

  /// 부를 일. "지금 뭐 할 수 있어?"를 물을 자리에는 없다.
  final String? taskId;
  final String? taskText;

  /// 사용자가 정한 시각인지. 그러면 하루 총량에서 빼고 매인 시간대도 뚫는다.
  bool get isPromise => signal == ActiveCoachingSignal.promised;
}

class ActiveCoachingPlanner {
  const ActiveCoachingPlanner._();

  /// 다음에 말을 걸 자리. 없으면 null.
  ///
  /// [busyAt]은 그 시각에 매여 있는지. [busyEndAfter]는 그 시간대가 끝나는
  /// 시각이다 — 매인 시간은 건너뛰는 것이 아니라 **끝난 뒤로 미룬다**. 그냥
  /// 건너뛰면 9시부터 6시까지 일하는 사람은 하루의 절반이 통째로 빈다.
  static ActiveCoachingPlan? next({
    required List tasks,
    required DateTime now,
    required ActiveCoachingDay day,
    required ActiveCoachingBudget budget,
    List coreTasks = const [],
    Set<int> onDays = const {1, 2, 3, 4, 5, 6, 7},
    bool Function(DateTime at)? busyAt,
    DateTime Function(DateTime at)? busyEndAfter,
  }) {
    // 참견하지 않기로 한 요일이다. 약속 시각도 여기서는 걸지 않는다 — 그 요일에
    // 안 부르기로 한 사람에게 약속이라고 뚫고 들어가면 설정이 거짓말이 된다.
    if (!onDays.contains(now.weekday)) return null;

    final promised = _earliestPromise(day, now);
    if (promised != null) return promised;

    final settled = day.settled;
    final skip = budget.lastTaskId;

    // 예산이 허락하는 가장 이른 시각. 아직 쉬는 중이면 그 뒤로 밀린다.
    final allowedFrom = _allowedFrom(budget, now);

    final late = _earliestLateStart(
      tasks,
      now: now,
      settled: settled,
      skip: skip,
    );

    // 사다리가 지금 잡을 것이 있는지. 멈춘 일도 핵심도 없고 물을 목록조차
    // 없으면 예산이 남아 있어도 부를 이유가 없다.
    final standing = ActiveCoachingTarget.pick(
      tasks: tasks,
      now: now,
      coreTasks: coreTasks,
      settled: settled,
      skipTaskId: skip,
    );

    ActiveCoachingPlan? best;
    void consider(DateTime at, ActiveCoachingSignal signal, Map? task) {
      final when = _usable(at, busyAt: busyAt, busyEndAfter: busyEndAfter);
      if (when == null) return;
      // 오늘 자리만 건다. 내일 것은 내일 다시 계산하는 편이 맞다 — 오늘 밤
      // 사이에 목록도 약속도 바뀐다.
      if (when.day != now.day || when.month != now.month) return;
      if (!onDays.contains(when.weekday)) return;
      if (when.hour >= ActiveCoachingBudget.quietFromHour) return;
      if (best != null && !when.isBefore(best!.at)) return;
      best = ActiveCoachingPlan(
        at: when,
        signal: signal,
        taskId: task?['id']?.toString(),
        taskText: task?['text']?.toString().trim(),
      );
    }

    if (late != null) {
      final at = late.key.isAfter(allowedFrom) ? late.key : allowedFrom;
      consider(at, ActiveCoachingSignal.lateStart, late.value);
    }
    if (!standing.isNone &&
        standing.signal != ActiveCoachingSignal.lateStart &&
        _worthSaying(standing, now)) {
      consider(allowedFrom, standing.signal, standing.task);
    }
    return best;
  }

  /// 지금 말을 걸 이유가 되는지.
  ///
  /// "지금 뭐 할 수 있어?"는 지금 손댈 수 있는 일이 하나라도 있을 때만 뜻이
  /// 있다. 남은 것이 전부 이따 시작할 일이면 그 사람은 계획대로 가는 중이고,
  /// 거기에 대고 뭘 할 수 있냐고 묻는 것은 재촉이다. 그 일들은 시작 시각이
  /// 지나고 30분이 되면 자기 자리에서 걸린다.
  static bool _worthSaying(ActiveCoachingPick pick, DateTime now) {
    if (!pick.needsUserPick) return true;
    return pick.candidates.any((item) {
      final start = _startAt(item, now);
      return start == null || !start.isAfter(now);
    });
  }

  /// 아직 오지 않은 약속 중 가장 이른 것.
  ///
  /// 예산도 매인 시간대도 보지 않는다. 사용자가 직접 정한 시각이라 재촉이
  /// 아니라 약속이고, 예산에 넣으면 약속을 많이 한 날일수록 코치가 입을 다문다.
  static ActiveCoachingPlan? _earliestPromise(
    ActiveCoachingDay day,
    DateTime now,
  ) {
    MapEntry<String, DateTime>? earliest;
    for (final entry in day.promises.entries) {
      if (!entry.value.isAfter(now)) continue;
      if (earliest == null || entry.value.isBefore(earliest.value)) {
        earliest = entry;
      }
    }
    if (earliest == null) return null;
    return ActiveCoachingPlan(
      at: earliest.value,
      signal: ActiveCoachingSignal.promised,
      taskId: earliest.key,
    );
  }

  /// 적어둔 시작 시각에서 30분이 지나는 자리 중 가장 이른 것.
  ///
  /// 이미 지난 것도 센다. 창을 닫지 않는 기능이라 시각이 지났다고 놓지 않는다 —
  /// 다만 그때는 "지금부터"가 되므로 예산이 허락하는 시각으로 밀린다.
  static MapEntry<DateTime, Map>? _earliestLateStart(
    List tasks, {
    required DateTime now,
    required Set<String> settled,
    String? skip,
  }) {
    MapEntry<DateTime, Map>? earliest;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (item['category'] == 'schedule') continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty || id == skip || settled.contains(id)) continue;
      if (_touched(item)) continue;
      final start = _startAt(item, now);
      if (start == null) continue;
      final at = start.add(ActiveCoachingTarget.lateStartAfter);
      if (earliest == null || at.isBefore(earliest.key)) {
        earliest = MapEntry(at, item);
      }
    }
    return earliest;
  }

  /// 예산이 허락하는 가장 이른 시각.
  static DateTime _allowedFrom(ActiveCoachingBudget budget, DateTime now) {
    if (budget.spokenToday >= ActiveCoachingBudget.dailyCap) {
      // 오늘 몫을 다 썼다. 내일은 어차피 다시 계산하므로 아주 먼 시각으로 민다.
      return DateTime(now.year, now.month, now.day + 1);
    }
    final last = budget.lastSpokeAt;
    if (last == null) return now;
    final next = last.add(budget.currentInterval);
    return next.isAfter(now) ? next : now;
  }

  /// 그 시각에 실제로 부를 수 있는 때. 매인 시간대면 끝난 뒤로 민다.
  static DateTime? _usable(
    DateTime at, {
    bool Function(DateTime at)? busyAt,
    DateTime Function(DateTime at)? busyEndAfter,
  }) {
    if (busyAt == null || !busyAt(at)) return at;
    final after = busyEndAfter?.call(at);
    if (after == null) return null;
    // 끝나는 시각에 바로 부르지 않는다. 회의가 끝나는 순간은 아직 자리를
    // 정리하는 중이다.
    return after.add(const Duration(minutes: 5));
  }

  static bool _touched(Map item) {
    if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) return true;
    for (final key in ['pausedAt', 'inProgressAt', 'runStartedAt']) {
      if ((item[key]?.toString().trim() ?? '').isNotEmpty) return true;
    }
    return false;
  }

  static DateTime? _startAt(Map item, DateTime now) {
    final parts = (item['timeStart']?.toString() ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(now.year, now.month, now.day, hour, minute);
  }
}
