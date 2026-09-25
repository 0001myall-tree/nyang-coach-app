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
    DateTime? Function(DateTime at)? busyEndAfter,
    String? bedtime,
    List<DateTime> gapTimes = const [],
    bool includePromises = true,
  }) {
    // 참견하지 않기로 한 요일이다. 약속 시각도 여기서는 걸지 않는다 — 그 요일에
    // 안 부르기로 한 사람에게 약속이라고 뚫고 들어가면 설정이 거짓말이 된다.
    if (!onDays.contains(now.weekday)) return null;

    if (includePromises) {
      final promised = _earliestPromise(day, now);
      if (promised != null) return promised;
    }

    final settled = day.settled;
    // 바로 앞에서 다룬 일은 한 번 건너뛴다 — 다른 일이 남아 있을 때만. 그 일
    // 하나뿐인데 건너뛰면 그날은 다시 부를 것이 없어, 영양제 하나 남은 사람에게
    // 한 번 말하고 끝난다.
    final skip = _hasOtherPending(tasks, settled, budget.lastTaskId)
        ? budget.lastTaskId
        : null;

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
      var when = _usable(at, busyAt: busyAt, busyEndAfter: busyEndAfter);
      if (when == null) return;
      // 새벽이면 아침으로 민다. 버리면 자정 넘어 앱을 한 번 연 날은 차례가
      // 하나도 안 잡혀, 다시 열 때까지 조용하다.
      if (when.hour < ActiveCoachingBudget.quietUntilHour) {
        when = DateTime(
          when.year,
          when.month,
          when.day,
          ActiveCoachingBudget.quietUntilHour,
        );
      }
      // 오늘 자리만 건다. 내일 것은 내일 다시 계산하는 편이 맞다 — 오늘 밤
      // 사이에 목록도 약속도 바뀐다.
      if (when.day != now.day || when.month != now.month) return;
      if (!onDays.contains(when.weekday)) return;
      // 하루를 닫는 말은 조용한 시간 앞에 서 있으라고 자리를 잡아둔 것이라
      // 여기서 다시 거르지 않는다.
      if (signal != ActiveCoachingSignal.nightWrap &&
          when.hour >= ActiveCoachingBudget.quietFromHour) {
        return;
      }
      if (best != null && !when.isBefore(best!.at)) return;
      best = ActiveCoachingPlan(
        at: when,
        signal: signal,
        taskId: task?['id']?.toString(),
        taskText: task?['text']?.toString().trim(),
      );
    }

    // 하루를 닫는 말. 예산 밖이라 오늘 몫을 다 썼어도 나간다 — 하루 종일
    // 조용했던 사람에게 오히려 더 필요하다.
    final night = _nightWrapAt(now, bedtime);
    if (night != null &&
        !budget.wrappedUpToday &&
        !standing.isNone &&
        _worthSaying(standing, now)) {
      consider(night, ActiveCoachingSignal.nightWrap, standing.task);
    }

    // 사용자가 적어둔 여유 시간. "이때 들러줘"라고 말해둔 자리다.
    //
    // 간격은 평소보다 짧게 본다 — 직전에서 [gapInterval]만 지나면 된다. 두
    // 시간을 그대로 지키면 적어둔 시각이 대부분 그 안에 걸려 버려져서, 들러
    // 달라고 해둔 자리가 거의 쓰이지 않았다. 다만 10시 15분과 10시 30분을
    // 함께 적어둔 사람에게 15분 간격으로 두 번 가지는 않는다.
    // 진행 중인 일이 있으면 아래 [standing]이 비어서 애초에 걸리지 않는다.
    final gapFrom = _allowedFrom(budget, now, interval: gapInterval);
    final upcomingGaps = [
      for (final at in gapTimes)
        if (at.isAfter(now) && !at.isBefore(gapFrom)) at,
    ];
    if (!standing.isNone && _worthSaying(standing, now)) {
      for (final at in upcomingGaps) {
        consider(at, standing.signal, standing.task);
      }
    }

    if (late != null) {
      final at = late.key.isAfter(allowedFrom) ? late.key : allowedFrom;
      consider(at, ActiveCoachingSignal.lateStart, late.value);
    }
    // 평소 차례. 곧 여유 시간이 오면 그때까지 기다린다 — 사용자가 적어둔
    // 시각이 더 낫고, 2시간 되자마자 먼저 가버리면 그 시각은 간격에 걸려 버려진다.
    final waitForGap = upcomingGaps.any(
      (at) => at.isAfter(allowedFrom) && !at.isAfter(allowedFrom.add(gapWait)),
    );
    if (!standing.isNone &&
        standing.signal != ActiveCoachingSignal.lateStart &&
        _worthSaying(standing, now) &&
        !waitForGap) {
      consider(allowedFrom, standing.signal, standing.task);
    }
    return best;
  }

  /// 여유 시간에 들를 때 직전 차례에서 이만큼만 지나면 된다.
  static const Duration gapInterval = Duration(hours: 1);

  /// 평소 차례가 여유 시간을 기다려주는 폭.
  static const Duration gapWait = Duration(hours: 1);

  /// 오늘 남은 차례 전부. 이른 것부터.
  ///
  /// [next]를 한 번만 부르면 그 한 번이 지나간 뒤에는 앱을 다시 열 때까지 걸린
  /// 것이 없다. 앱을 안 여는 사람일수록 코치가 필요한데, 그 사람에게 하루 한
  /// 번뿐이었다. 그래서 차례마다 "나갔는데 답이 없었다"고 치고 다음 차례를
  /// 이어서 계산해 둔다. 실제로 나가면 예산에도 그렇게 적히므로(무응답), 앱이
  /// 열려 다시 계산해도 같은 줄이 나온다.
  ///
  /// 그 사이에 목록이 바뀔 수 있다. 그 일을 끝냈거나 카드에서 답했으면
  /// 네이티브가 띄우기 직전에 걸러낸다.
  static List<ActiveCoachingPlan> queue({
    required List tasks,
    required DateTime now,
    required ActiveCoachingDay day,
    required ActiveCoachingBudget budget,
    List coreTasks = const [],
    Set<int> onDays = const {1, 2, 3, 4, 5, 6, 7},
    bool Function(DateTime at)? busyAt,
    DateTime? Function(DateTime at)? busyEndAfter,
    String? bedtime,
    List<DateTime> gapTimes = const [],
    int limit = maxQueue,
  }) {
    if (!onDays.contains(now.weekday)) return const [];

    // 약속은 따로 끼운다. [next]는 약속이 있으면 그것부터 내놓는데, 그대로
    // 이어 붙이면 10시에 "4시에 할게"가 있을 때 그 사이 차례가 통째로 빠진다.
    final promises = <ActiveCoachingPlan>[
      for (final entry in day.promises.entries)
        if (entry.value.isAfter(now))
          ActiveCoachingPlan(
            at: entry.value,
            signal: ActiveCoachingSignal.promised,
            taskId: entry.key,
          ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    final chain = <ActiveCoachingPlan>[];
    var at = now;
    var spent = budget;
    while (chain.length < limit) {
      final plan = next(
        tasks: tasks,
        now: at,
        day: day,
        budget: spent,
        coreTasks: coreTasks,
        onDays: onDays,
        busyAt: busyAt,
        busyEndAfter: busyEndAfter,
        bedtime: bedtime,
        gapTimes: gapTimes,
        includePromises: false,
      );
      if (plan == null) break;
      // 같은 자리를 또 내놓으면 여기서 멈춘다. 예산이 한 번 쓰이면 다음 자리는
      // 늘 뒤로 밀리므로 정상이라면 걸리지 않는다.
      if (chain.isNotEmpty && !plan.at.isAfter(chain.last.at)) break;
      chain.add(plan);
      if (plan.signal == ActiveCoachingSignal.nightWrap) {
        spent = spent.wrappedUp(plan.at);
      }
      // 나간 차례를 앱이 예산에 적는 셈과 같게 센다. 둘이 다르면 앱이 열려
      // 다시 계산할 때 줄이 바뀐다.
      spent = spent.spoke(plan.at, taskId: plan.taskId).noReply();
      at = plan.at;
    }

    // 약속 바로 앞뒤의 차례는 뺀다. 약속한 시각을 확인하러 가는 참에 다른 말이
    // 붙으면 두 번 말 건 것이다.
    bool nearPromise(ActiveCoachingPlan plan) => promises.any(
      (promise) =>
          plan.at.isAfter(promise.at.subtract(promiseQuietBefore)) &&
          plan.at.isBefore(promise.at.add(ActiveCoachingBudget.interval)),
    );
    final result = [
      ...promises,
      for (final plan in chain)
        if (plan.signal == ActiveCoachingSignal.nightWrap || !nearPromise(plan))
          plan,
    ]..sort((a, b) => a.at.compareTo(b.at));
    return result.take(limit).toList(growable: false);
  }

  /// 약속한 시각 이만큼 앞으로는 다른 차례를 두지 않는다.
  static const Duration promiseQuietBefore = Duration(minutes: 30);

  /// 하루에 미리 걸어두는 차례의 상한. 예산 총량에 밤 인사와 약속 한둘을 더한
  /// 만큼이다. 아이폰 알림 자리도 이 수만큼 잡혀 있다.
  static const int maxQueue = 10;

  /// 하루를 닫는 말을 건넬 시각. 이미 너무 늦었으면 null.
  ///
  /// 취침 두 시간 전에 선다. 안 정해둔 사람은 밤 9시다. 늦게 자는 사람에게도
  /// 9시 반을 넘기지 않는다 — 그 뒤로 미루면 "10분만 손대볼까"가 자라고 할
  /// 시간에 일을 시키는 말이 된다.
  static DateTime? _nightWrapAt(DateTime now, String? bedtime) {
    final parsed = _parseHhMm(bedtime);
    var at = DateTime(now.year, now.month, now.day, 21);
    if (parsed != null) {
      var sleepAt = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.$1,
        parsed.$2,
      );
      // 자정을 넘겨 자는 사람의 취침은 다음 날 것이다. 새벽 1시에 자는 사람의
      // "두 시간 전"은 어제 밤 11시가 아니라 오늘 밤 11시다.
      if (parsed.$1 < 6) sleepAt = sleepAt.add(const Duration(days: 1));
      at = sleepAt.subtract(const Duration(hours: 2));
    }
    final latest = DateTime(now.year, now.month, now.day, 21, 30);
    if (at.isAfter(latest)) at = latest;
    // 그 시각을 이미 지났으면 지금 건넨다. 한 시간 넘게 지났으면 오늘은 넘긴다.
    if (at.isBefore(now)) {
      if (now.difference(at) > const Duration(hours: 1)) return null;
      return now;
    }
    return at;
  }

  static (int, int)? _parseHhMm(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
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
  static DateTime _allowedFrom(
    ActiveCoachingBudget budget,
    DateTime now, {
    Duration? interval,
  }) {
    if (budget.spokenToday >= ActiveCoachingBudget.dailyCap) {
      // 오늘 몫을 다 썼다. 내일은 어차피 다시 계산하므로 아주 먼 시각으로 민다.
      return DateTime(now.year, now.month, now.day + 1);
    }
    final last = budget.lastSpokeAt;
    if (last == null) return now;
    final next = last.add(interval ?? budget.currentInterval);
    return next.isAfter(now) ? next : now;
  }

  /// 그 시각에 실제로 부를 수 있는 때. 매인 시간대면 끝난 뒤로 민다.
  static DateTime? _usable(
    DateTime at, {
    bool Function(DateTime at)? busyAt,
    DateTime? Function(DateTime at)? busyEndAfter,
  }) {
    if (busyAt == null || !busyAt(at)) return at;
    final after = busyEndAfter?.call(at);
    if (after == null) return null;
    // 끝나는 시각에 바로 부르지 않는다. 회의가 끝나는 순간은 아직 자리를
    // 정리하는 중이다.
    return after.add(const Duration(minutes: 5));
  }

  static bool _hasOtherPending(List tasks, Set<String> settled, String? skip) {
    if (skip == null) return false;
    return tasks.any((item) {
      if (item is! Map) return false;
      if (item['done'] == true || item['inProgress'] == true) return false;
      if (item['category'] == 'schedule') return false;
      final id = item['id']?.toString() ?? '';
      return id.isNotEmpty && id != skip && !settled.contains(id);
    });
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
