/// 계획 → 시작 → 완료를 지나면서 어디서 제일 많이 새는지.
///
/// 이 앱은 오래 각 숫자를 정해진 선에 대봤다. 완료율 0.7 이상이면 안정형,
/// 하루 평균 3개 이상이면 계획 과다형 하는 식으로. 그러면 다른 축이 어떤지를
/// 안 보게 되고, 앞뒤가 정반대인 두 사람이 같은 칸에 들어간다.
///
/// 적어둔 것의 25%에 손대고 그 전부를 끝낸 사람과, 80%에 손대고 그중 30%만
/// 끝낸 사람은 계획 대비 완료율이 둘 다 25% 언저리다. 그런데 첫 사람에게
/// 할 말은 "잡는 양을 줄이자"이고 둘째에게 할 말은 "끝까지 가는 크기로
/// 자르자"다. 정반대인데 문턱은 둘을 못 가른다.
///
/// 그래서 여기서는 단계끼리 견준다. 절대값으로 남는 선은 둘뿐이다 — 말할 만큼
/// 데이터가 있는지, 그리고 다 잘 되고 있어서 새는 곳이 없는지.
///
/// 단위도 둘로 나눠 센다. 날 단위와 항목 단위가 다른 이야기를 하기 때문이다.
/// 날 단위는 높은데 항목 단위가 낮으면 매일 손은 대는데 적어둔 것의 일부만
/// 건드린다는 뜻이라, 병목은 시작이 아니라 한 번에 잡는 양이다.
library;

import 'dart:convert';

/// 제일 많이 새는 자리.
enum FunnelLeak {
  /// 아직 아무것도 안 하고 있다. 병목을 짚을 것이 아니라 시작점을 잡아줄 자리.
  notStarted,

  /// 목록을 만드는 날 자체가 드물다.
  planning,

  /// 한 번에 잡는 양이 많다. 날마다 손은 대는데 적어둔 것의 일부만 건드린다.
  amount,

  /// 적어두고 손을 안 댄다.
  starting,

  /// 손은 대는데 끝까지 못 간다.
  finishing,

  /// 세 단계가 다 잘 지나간다. 건드릴 것이 없다.
  none,
}

class ExecutionFunnel {
  const ExecutionFunnel({
    required this.evaluatedDays,
    required this.daysWithPlan,
    required this.daysDirectPlan,
    required this.daysTouched,
    required this.daysAnyDone,
    required this.daysAllDone,
    required this.planned,
    required this.touched,
    required this.done,
    required this.startedMarked,
    required this.maxPlanInDay,
    required this.minPlanInDay,
    this.lateNightDays = 0,
    this.startHours = const [],
  });

  /// 셀 수 있었던 날. 오늘과 첫 기록 이전은 뺀다.
  final int evaluatedDays;

  /// 목록에 무언가 있던 날. 루틴만 있어도 여기 든다 — 루틴이 그날의 계획이다.
  final int daysWithPlan;

  /// 그중 직접 적은 계획이 있던 날.
  ///
  /// 축을 가르지는 않는다. 다만 루틴만 걸어둔 사람과 매일 직접 적는 사람이
  /// 같은 100%로 보이는 것은 사실과 다르다.
  final int daysDirectPlan;

  final int daysTouched;
  final int daysAnyDone;
  final int daysAllDone;

  final int planned;
  final int touched;
  final int done;

  /// 시작 표시가 실제로 남은 항목 수.
  ///
  /// 이게 적으면 시작과 완료를 가를 수 없다. ▶를 안 누르고 체크만 하는
  /// 사람은 손댄 것과 끝낸 것이 같아져서, "시작하면 끝내는 사람"과
  /// "타이머를 안 쓰는 사람"이 똑같은 숫자로 나온다.
  final int startedMarked;

  final int maxPlanInDay;
  final int minPlanInDay;

  /// 밤 10시 이후에 서로 다른 일 셋 이상을 한꺼번에 시작한 날.
  ///
  /// 어느 단계가 새는지와는 다른 축이다. 다 끝냈어도 막판에 몰린 것은 몰린
  /// 것이라, 단계 비교에 섞지 않고 곁들이는 정보로만 둔다.
  final int lateNightDays;

  /// 무언가를 시작한 시각들. 주로 언제 손대는 사람인지 여기서 나온다.
  final List<int> startHours;

  /// 하루 몇 개 이상이 밤에 몰려야 벼락치기로 보는지.
  static const int crammedTaskThreshold = 3;

  /// 이 시각 이후를 밤으로 본다.
  static const int lateNightHour = 22;

  /// 시간대 이야기를 하려면 시작 기록이 이만큼은 있어야 한다.
  static const int minStartHourSamples = 5;

  /// 주로 시작하는 두 시간짜리 구간. 표본이 모자라면 null.
  int? get busiestStartHour {
    if (startHours.length < minStartHourSamples) return null;
    final counts = <int, int>{};
    for (final hour in startHours) {
      final slot = hour - hour % 2;
      counts[slot] = (counts[slot] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    // 골고루 퍼져 있으면 시간대라고 부를 것이 없다.
    return top.value * 2 >= startHours.length ? top.key : null;
  }

  /// 이만큼은 있어야 무슨 말이든 한다.
  static const int minEvaluatedDays = 3;

  /// 시작과 완료를 갈라 말하려면 시작 표시가 이만큼은 있어야 한다.
  static const int minStartSamples = 3;

  /// 모든 단계가 이만큼 지나가면 새는 곳이 없다고 본다.
  ///
  /// 절대값으로 남은 유일한 선이다. 이게 없으면 95%로 지나가는 사람에게도
  /// 제일 낮은 단계를 찾아 "여기가 샌다"고 말하게 된다.
  static const double flowsWellRate = 0.7;

  /// 날 단위가 항목 단위보다 이만큼 앞서면, 새는 곳은 시작이 아니라 양이다.
  ///
  /// 날마다 손은 대는데 적어둔 것의 일부만 건드린다는 뜻이라, 첫 발이
  /// 문제가 아니라 한 번에 잡는 양이 많은 것이다.
  static const double amountGap = 0.3;

  bool get hasEnough => evaluatedDays >= minEvaluatedDays && planned > 0;

  /// 시작과 완료를 갈라 말할 수 있는지.
  bool get canSplitStartAndFinish => startedMarked >= minStartSamples;

  /// 목록을 만든 날의 비율.
  double get planPass =>
      evaluatedDays == 0 ? 0 : daysWithPlan / evaluatedDays;

  /// 적어둔 것 중 손댄 비율.
  double get startPass => planned == 0 ? 0 : touched / planned;

  /// 목록이 있던 날 중 손댄 날의 비율.
  double get dayStartPass =>
      daysWithPlan == 0 ? 0 : daysTouched / daysWithPlan;

  /// 손댄 것 중 끝낸 비율.
  double get finishPass => touched == 0 ? 0 : done / touched;

  /// 목록이 있던 날엔 평균 몇 개를 잡는지.
  double get planPerPlannedDay =>
      daysWithPlan == 0 ? 0 : planned / daysWithPlan;

  FunnelLeak get leak {
    if (!hasEnough) return FunnelLeak.notStarted;
    if (touched == 0) return FunnelLeak.notStarted;

    // 완료 축은 가를 수 있을 때만 견준다. 시작 표시가 없으면 손댄 것과 끝낸
    // 것이 같아져서 늘 100%로 나오고, 그 100%가 다른 축을 이겨버린다.
    final stages = <FunnelLeak, double>{
      FunnelLeak.planning: planPass,
      FunnelLeak.starting: startPass,
      if (canSplitStartAndFinish) FunnelLeak.finishing: finishPass,
    };

    final lowest = stages.entries.reduce(
      (a, b) => a.value <= b.value ? a : b,
    );
    if (lowest.value >= flowsWellRate) return FunnelLeak.none;

    if (lowest.key == FunnelLeak.starting &&
        dayStartPass - startPass >= amountGap) {
      return FunnelLeak.amount;
    }
    return lowest.key;
  }

  static const Map<FunnelLeak, String> leakNames = {
    FunnelLeak.notStarted: '아직 시작 전',
    FunnelLeak.planning: '목록을 만드는 것',
    FunnelLeak.amount: '한 번에 잡는 양',
    FunnelLeak.starting: '첫 발 떼기',
    FunnelLeak.finishing: '끝까지 가는 것',
    FunnelLeak.none: '없음',
  };

  /// 코치에게 넘길 묶음. 셀 것이 모자라면 빈 문자열.
  ///
  /// 유형 이름을 여기서 붙이지 않는다. 이름은 정보를 잃는 압축이라, 앞뒤가
  /// 다른 두 사람이 같은 이름으로 묶이면 처방까지 같이 틀린다.
  String promptBlock({String purpose = ''}) {
    if (!hasEnough) return '';

    final buffer = StringBuffer('\n[실행 - 앱이 최근 이레 기록에서 센 값]\n');
    if (purpose.isNotEmpty) buffer.writeln(purpose);
    buffer.writeln('평가한 날 $evaluatedDays일 (오늘 제외)');
    buffer.writeln(
      '계획  목록이 있던 날 $daysWithPlan일 (루틴만 있어도 포함) / '
      '그중 직접 적은 날 $daysDirectPlan일 / '
      '있던 날엔 평균 ${planPerPlannedDay.toStringAsFixed(1)}개'
      '${maxPlanInDay > minPlanInDay ? ' (많은 날 $maxPlanInDay개, 적은 날 $minPlanInDay개)' : ''}',
    );
    buffer.writeln(
      '시작  목록 있던 날 중 손댄 날 $daysTouched일 / '
      '적어둔 것 중 ${_pct(startPass)}에 손댐',
    );
    if (canSplitStartAndFinish) {
      buffer.writeln(
        '완료  손댄 날 중 하나라도 끝낸 날 $daysAnyDone일 · 다 끝낸 날 $daysAllDone일 / '
        '손댄 것 중 ${_pct(finishPass)} 끝냄 (시작 표시가 남은 항목 $startedMarked개)',
      );
    } else {
      buffer.writeln(
        '완료  손댄 날 중 하나라도 끝낸 날 $daysAnyDone일 · 다 끝낸 날 $daysAllDone일',
      );
      buffer.writeln(
        '*시작 표시가 남은 항목이 $startedMarked개뿐이라 시작과 완료를 가를 수 없습니다. '
        '이 사람은 시작 버튼을 안 쓰고 체크만 하는 것일 수 있으니, 끝까지 못 간다고 단정하지 마세요.',
      );
    }
    // 시간대는 단계 비교에 섞지 않는다. 아침에 시작하느냐는 어디가 새는지와
    // 다른 축이고, 한 줄에 섞으면 새는 곳을 고르는 자리를 그것이 차지한다.
    final aside = <String>[];
    final busiest = busiestStartHour;
    if (busiest != null) {
      aside.add('주로 ${_clock(busiest)}~${_clock(busiest + 2)} 사이에 손댐');
    }
    if (lateNightDays >= 2) {
      aside.add(
        '밤 $lateNightHour시 이후에 여러 개를 한꺼번에 시작한 날이 $lateNightDays일 '
        '(다 끝냈는지와 무관하게 시작이 막판에 몰림)',
      );
    }
    if (aside.isNotEmpty) buffer.writeln('곁들여  ${aside.join(' / ')}');

    buffer.writeln('→ 제일 많이 새는 곳: ${leakNames[leak]}');
    buffer.writeln('- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.');
    return buffer.toString();
  }

  static String _pct(double value) => '${(value * 100).round()}%';

  /// "오전 8시"처럼. 화면 표기와 같은 모양으로 적는다.
  static String _clock(int hour) {
    final wrapped = hour % 24;
    final prefix = wrapped < 6
        ? '새벽'
        : wrapped < 12
        ? '오전'
        : '오후';
    final h = wrapped % 12 == 0 ? 12 : wrapped % 12;
    return '$prefix $h시';
  }

  // ── 세기 ──────────────────────────────────────

  /// [historyRaw]에서 최근 [windowDays]일을 센다. 오늘은 빼고, 첫 기록보다
  /// 이전 날도 뺀다 — 그건 거른 날이 아니라 아직 앱을 안 쓰던 날이다.
  static ExecutionFunnel from(String? historyRaw, {DateTime? now, int windowDays = 7}) {
    final at = now ?? DateTime.now();
    final byDate = <String, Map<String, dynamic>>{};
    DateTime? firstDay;

    for (final record in _decodeList(historyRaw)) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      byDate[_key(day)] = record;
      if (firstDay == null || day.isBefore(firstDay)) firstDay = day;
    }
    if (firstDay == null) return empty;

    var evaluatedDays = 0;
    var daysWithPlan = 0;
    var daysDirectPlan = 0;
    var daysTouched = 0;
    var daysAnyDone = 0;
    var daysAllDone = 0;
    var planned = 0;
    var touched = 0;
    var done = 0;
    var startedMarked = 0;
    var maxPlanInDay = 0;
    var minPlanInDay = 0;
    var lateNightDays = 0;
    final startHours = <int>[];

    for (var back = 1; back <= windowDays; back++) {
      final day = DateTime(at.year, at.month, at.day - back);
      if (day.isBefore(firstDay)) continue;
      evaluatedDays++;

      final record = byDate[_key(day)];
      final tasks = _asList(record?['tasks']);
      if (tasks.isEmpty) continue;

      daysWithPlan++;
      var dayPlanned = 0;
      var dayTouched = 0;
      var dayDone = 0;
      var dayDirect = 0;
      var dayLateStarts = 0;

      for (final task in tasks) {
        // 이월 표시는 그날 세운 계획이 아니라 넘어온 것이다.
        if (task['deferred'] == true) continue;
        dayPlanned++;
        if (_isDirectPlan(task)) dayDirect++;

        final isDone = task['done'] == true;
        final startedAt = DateTime.tryParse(
          task['startedAt']?.toString() ?? '',
        );
        if (startedAt != null) {
          startedMarked++;
          startHours.add(startedAt.hour);
          if (startedAt.hour >= lateNightHour) dayLateStarts++;
        }
        if (isDone) dayDone++;
        if (isDone || startedAt != null) dayTouched++;
      }
      if (dayLateStarts >= crammedTaskThreshold) lateNightDays++;

      if (dayPlanned == 0) {
        daysWithPlan--;
        continue;
      }

      planned += dayPlanned;
      touched += dayTouched;
      done += dayDone;
      if (dayDirect > 0) daysDirectPlan++;
      if (dayTouched > 0) daysTouched++;
      if (dayDone > 0) daysAnyDone++;
      if (dayDone == dayPlanned) daysAllDone++;
      if (dayPlanned > maxPlanInDay) maxPlanInDay = dayPlanned;
      if (minPlanInDay == 0 || dayPlanned < minPlanInDay) {
        minPlanInDay = dayPlanned;
      }
    }

    return ExecutionFunnel(
      evaluatedDays: evaluatedDays,
      daysWithPlan: daysWithPlan,
      daysDirectPlan: daysDirectPlan,
      daysTouched: daysTouched,
      daysAnyDone: daysAnyDone,
      daysAllDone: daysAllDone,
      planned: planned,
      touched: touched,
      done: done,
      startedMarked: startedMarked,
      maxPlanInDay: maxPlanInDay,
      minPlanInDay: minPlanInDay,
      lateNightDays: lateNightDays,
      startHours: startHours,
    );
  }

  static const ExecutionFunnel empty = ExecutionFunnel(
    evaluatedDays: 0,
    daysWithPlan: 0,
    daysDirectPlan: 0,
    daysTouched: 0,
    daysAnyDone: 0,
    daysAllDone: 0,
    planned: 0,
    touched: 0,
    done: 0,
    startedMarked: 0,
    maxPlanInDay: 0,
    minPlanInDay: 0,
  );

  /// 루틴에서 내려온 것과 마일스톤은 직접 적은 계획이 아니다.
  static bool _isDirectPlan(Map<String, dynamic> task) {
    final category = task['category']?.toString();
    if (category == 'habit' || category == 'milestone') return false;
    if (task['habitId'] != null) return false;
    return true;
  }

  static String _key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}
