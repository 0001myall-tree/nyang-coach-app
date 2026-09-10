/// 어떤 조건에서 더 잘 움직이는 사람인지, 기록에서 세어본다.
///
/// 주간 리포트의 다른 회고는 "이번 주에 얼마나 했는가"를 말한다. 이건 다른
/// 질문이다 — **무엇이 다를 때 실행도 달라졌는가**. 쓸수록 값이 커지는 유일한
/// 자리라, 기록이 모자란 사람에게는 아무 말도 하지 않는다.
///
/// 세는 일을 앱이 맡는 이유는 하나다. 날짜별 원기록을 그대로 넘기고 "관계를
/// 찾아보세요"라고 하면, 코치는 눈대중으로 읽고 **확신에 찬 한 문장**을
/// 만들어낸다. 억지로 만들지 말라고 부탁해도 못 막는다 — 스스로는 억지로
/// 만든 줄 모르기 때문이다. 그래서 억지로 만들 재료를 아예 주지 않는다.
///
/// 여기서 나오는 것은 인과가 아니다. 조건을 무작위로 배정할 수 없으니 인과는
/// 애초에 못 밝힌다. 할 수 있는 건 둘뿐이다 — 같은 방향이 **반복되는지**, 그리고
/// 그 조건이 **다음 날을 깎지 않는지**.
library;

import 'dart:convert';

/// 조건이 참인 날과 거짓인 날을 견준 결과 하나.
class ConditionFinding {
  const ConditionFinding({
    required this.axis,
    required this.label,
    required this.whenTrueDays,
    required this.whenFalseDays,
    required this.whenTrueRate,
    required this.whenFalseRate,
    required this.nextDayTrueRate,
    required this.nextDayFalseRate,
    required this.consistent,
    required this.trueDates,
    this.cutoff,
  });

  final ConditionAxis axis;

  /// 사람이 읽을 조건 이름. 코치에게 넘어가는 말이라 숫자가 아니라 말로 적는다.
  final String label;

  final int whenTrueDays;
  final int whenFalseDays;

  /// 조건이 참/거짓일 때의 결과값. 축마다 무엇을 재는지가 다르다.
  final double whenTrueRate;
  final double whenFalseRate;

  /// 다음 날 완료율. 잴 수 없었으면 null.
  final double? nextDayTrueRate;
  final double? nextDayFalseRate;

  /// 창을 앞뒤로 갈랐을 때 양쪽에서 방향이 같았는지.
  ///
  /// 어떤 통계 검정보다 이 데이터에 잘 맞는 확인이다. 앞에선 높고 뒤에선
  /// 낮으면 그건 관계가 아니라 우연이다.
  final bool consistent;

  /// 경계를 찾아낸 축이면 그 숫자. 아니면 null.
  ///
  /// "적게 잡은 날"보다 "네 개까지 잡은 날"이 훨씬 쓸모 있다. 앞은 다음 주에
  /// 뭘 해야 할지 알 수 없고, 뒤는 그대로 하면 된다.
  final int? cutoff;

  /// 조건이 참이었던 날들(yyyy-MM-dd).
  ///
  /// 이번 주 주력한 일이 이 날들과 얼마나 겹치는지 세는 데 쓴다. 그 일만 따로
  /// 견준 것이 아니라 **겹친 날 수**일 뿐이라, 사실로만 전하고 그 일의 원인으로
  /// 말하지는 않는다.
  final Set<String> trueDates;

  double get gap => whenTrueRate - whenFalseRate;

  /// 다음 날이 깎이는지. 잴 수 없으면 null.
  double? get nextDayGap => (nextDayTrueRate == null || nextDayFalseRate == null)
      ? null
      : nextDayTrueRate! - nextDayFalseRate!;

  /// 그날은 좋았는데 다음 날이 낮아지는 자리.
  ///
  /// 사용자 눈에는 안 보이는 발견이다. 하루 안에서는 성공으로 끝났기 때문에,
  /// 다음 날 처진 것을 어제와 이어 보기가 어렵다. 앱만 볼 수 있는 자리라
  /// 제안 대신 주고받기로 전한다.
  bool get borrowsFromTomorrow {
    final next = nextDayGap;
    return next != null && gap > 0 && next <= -ConditionInsights.minGap;
  }

  /// 다음 주에 해보자고 권할 수 있는 자리인지.
  bool get canSuggest =>
      axis.suggestable &&
      gap >= ConditionInsights.minGap &&
      consistent &&
      !borrowsFromTomorrow;
}

/// 견주어 볼 조건들.
///
/// 고르는 기준은 하나다 — **다음 주에 사용자가 직접 돌릴 수 있는 손잡이인가.**
/// 하루가 끝나야 알 수 있는 것은 조건이 아니라 결과라, 알려줘도 손댈 데가 없다.
enum ConditionAxis {
  /// 그날 적어둔 양이 평소보다 적었는지.
  smallPlan(suggestable: true),

  /// 첫 손을 낮 전에 댔는지.
  earlyStart(suggestable: true),

  /// 루틴을 하나라도 끝냈는지. 결과는 **루틴이 아닌** 할 일의 완료율이다.
  routineDone(suggestable: true),

  /// 목록 첫 칸을 끝냈는지. 결과는 **첫 칸을 뺀 나머지**의 완료율이다.
  firstTaskDone(suggestable: true),

  /// 손댄 시각이 여러 구간에 흩어졌는지.
  ///
  /// 제안하지 않는다. 아침에 "오늘은 나눠서 해야지"를 정할 수가 없어서
  /// 손잡이가 없고, 손대려면 결국 첫 시작을 당기라는 말이 되어 [earlyStart]와
  /// 같은 자리가 된다. 다만 다음 날과 묶어 보면 벼락치기 이야기에 근거가 한 겹
  /// 붙으므로, 보고 전용으로 남긴다.
  ///
  /// 결과도 그날이 아니라 **다음 날** 완료율로 잰다. 흩어졌는지를 완료 시각으로
  /// 판정해놓고 결과까지 그날 완료율로 보면 같은 값을 두 번 쓰는 셈이다.
  spread(suggestable: false, measuresNextDay: true);

  const ConditionAxis({
    required this.suggestable,
    this.measuresNextDay = false,
  });

  /// 제안까지 갈 수 있는 축인지. 아니면 관찰만 전한다.
  final bool suggestable;

  /// 결과값을 그날이 아니라 다음 날에서 재는 축인지.
  final bool measuresNextDay;
}

/// 하루치 기록에서 뽑아둔, 견주는 데 필요한 값들.
class _Day {
  _Day({
    required this.date,
    required this.planned,
    required this.done,
    required this.firstStartHour,
    required this.routineDone,
    required this.nonRoutinePlanned,
    required this.nonRoutineDone,
    required this.firstTaskDone,
    required this.restPlanned,
    required this.restDone,
    required this.touchedSlots,
  });

  final DateTime date;
  final int planned;
  final int done;
  final int? firstStartHour;
  final bool routineDone;
  final int nonRoutinePlanned;
  final int nonRoutineDone;
  final bool? firstTaskDone;
  final int restPlanned;
  final int restDone;
  final int touchedSlots;

  double get rate => planned == 0 ? 0 : done / planned;
  double get nonRoutineRate =>
      nonRoutinePlanned == 0 ? 0 : nonRoutineDone / nonRoutinePlanned;
  double get restRate => restPlanned == 0 ? 0 : restDone / restPlanned;
}

class ConditionInsights {
  const ConditionInsights(this.findings, {required this.evaluatedDays});

  final List<ConditionFinding> findings;
  final int evaluatedDays;

  /// 한쪽에 이만큼은 모여야 견준다.
  ///
  /// 이레치로 나누면 3일 대 4일이 된다. 하루가 빠지고 들어갈 때마다 비율이
  /// 25%p씩 튀어서, 매주 다른 소리를 하게 된다.
  static const int minSideDays = 5;

  /// 무슨 말이든 하려면 이만큼은 쌓여야 한다.
  ///
  /// 진짜 방어선은 이 값이 아니라 [minSideDays]다. 양쪽에 5일씩 모이려면
  /// 기록이 최소 열흘은 있어야 해서, 이 선을 더 내려봐야 아무것도 통과하지
  /// 못한다 — 이레치로는 아무리 잘 갈라도 5대 2다.
  static const int minEvaluatedDays = 10;

  /// 이만큼 차이 나야 차이라고 부른다.
  static const double minGap = 0.2;

  /// 양쪽이 넉넉히 모였을 때는 조금 더 작은 차이도 본다.
  static const int comfortableSideDays = 7;
  static const double comfortableGap = 0.15;

  /// 경계를 찾을 때 여기서부터 대본다. 하나 이하로 잡으라는 말은 계획을 세우지
  /// 말라는 말과 다르지 않아서, 찾아내도 권할 수가 없다.
  static const int minPlanCutoff = 2;

  /// 낮 이 시각 전에 첫 손을 댔으면 이르다고 본다.
  static const int earlyStartHour = 12;

  /// 손댄 시각을 이 길이의 구간으로 묶는다.
  static const int slotHours = 2;

  /// 제일 센 것 하나. 없으면 null.
  ///
  /// 여러 개를 나열하지 않는다. 다섯 축을 재면 그중 하나쯤은 우연히 크게
  /// 벌어지기 때문에, 나열하는 순간 가짜가 섞인다.
  ConditionFinding? get top {
    if (findings.isEmpty) return null;
    final sorted = [...findings]
      ..sort((a, b) => b.gap.abs().compareTo(a.gap.abs()));
    // 권할 수 있는 것이 있으면 그것부터. 없으면 주고받기라도 전한다.
    for (final finding in sorted) {
      if (finding.canSuggest) return finding;
    }
    for (final finding in sorted) {
      if (finding.borrowsFromTomorrow && finding.consistent) return finding;
    }
    return null;
  }

  bool get hasEnough => top != null;

  /// 코치에게 넘길 한 덩어리. 넘길 것이 없으면 빈 문자열.
  ///
  /// 숫자만 적고 해석은 적지 않는다. 다만 이 숫자를 **어떻게 말해야 하는지**는
  /// 여기 같이 적는다 — 지침이 프롬프트 저 위에 따로 있으면, 코치는 숫자를
  /// 보면서 지침을 잊는다.
  String promptBlock({String focusNote = ''}) {
    final finding = top;
    if (finding == null) return '';

    String pct(double value) => '${(value * 100).round()}%';

    final buffer = StringBuffer('\n[조건 - 앱이 최근 $evaluatedDays일 기록에서 견준 값]\n');
    buffer.writeln('견준 것: ${finding.label} vs 그렇지 않은 날');
    if (finding.cutoff != null) {
      buffer.writeln(
        '- 이 숫자(${finding.cutoff}개)는 기준을 여럿 대보고 제일 크게 갈린 자리입니다. '
        '딱 떨어지는 경계처럼 말하지 말고 "${finding.cutoff}개쯤"으로 쓰세요.',
      );
    }
    buffer.writeln(
      '- ${finding.label}: ${finding.whenTrueDays}일, 실행 ${pct(finding.whenTrueRate)}',
    );
    buffer.writeln(
      '- 그렇지 않은 날: ${finding.whenFalseDays}일, 실행 ${pct(finding.whenFalseRate)}',
    );
    final next = finding.nextDayGap;
    if (next != null) {
      buffer.writeln(
        '- 다음 날 완료율: ${pct(finding.nextDayTrueRate!)} vs ${pct(finding.nextDayFalseRate!)}',
      );
    }
    buffer.writeln('- 기간을 앞뒤로 갈랐을 때 방향이 같았는지: ${finding.consistent ? '예' : '아니오'}');
    if (focusNote.isNotEmpty) {
      buffer.writeln('- $focusNote');
      buffer.writeln(
        '*이 줄은 겹친 날 수일 뿐입니다. 그 일만 따로 견준 것이 아니니 '
        '"그 조건 덕분에 그 일이 잘 됐다"로 쓰지 말고, 조건 이야기를 그 일에 '
        '비추어 보여주는 데만 쓰세요.',
      );
    }

    if (finding.borrowsFromTomorrow) {
      buffer.writeln(
        '*그날은 높은데 다음 날이 낮습니다. 잘된 방법으로 권하지 마세요. '
        '그날 하루만 보면 성공이라 사용자는 이걸 스스로 알아채기 어렵습니다. '
        '"그날은 잘 끝났는데 다음 날이 낮았다"는 주고받기로 전하고, '
        '다음 주에는 이틀을 묶어서 보자고만 하세요. 하지 말라고는 하지 마세요.',
      );
    } else if (finding.canSuggest) {
      buffer.writeln(
        '*이 조건을 다음 주에 해볼 만한 것으로 하나만 제안하세요. '
        '매일 그러라고 하지 말고, 며칠만 해보는 크기로 말하세요.',
      );
    } else {
      buffer.writeln(
        '*관찰로만 전하고 제안까지 가지 마세요. 방향이 반복되지 않았거나 권할 수 있는 조건이 아닙니다.',
      );
    }
    buffer.writeln(
      '*"~했기 때문에 좋아졌다"로 쓰지 마세요. 조건을 골라서 시켜본 것이 아니라 '
      '지나간 기록을 견준 것뿐이라, 원인인지 아닌지는 여기서 알 수 없습니다. '
      '"~한 날에 실행도 함께 높았어요", "~가 도움이 되는 조건인지 조금 더 확인해볼 만합니다" 정도로 쓰세요.',
    );
    buffer.writeln('*여기 없는 숫자나 다른 관계를 지어내지 마세요. 견준 것은 이 하나뿐입니다.');
    return buffer.toString();
  }

  static ConditionInsights from(String? rawHistory) {
    final days = _readDays(rawHistory);
    if (days.length < minEvaluatedDays) {
      return ConditionInsights(const [], evaluatedDays: days.length);
    }

    final findings = <ConditionFinding>[];

    void consider(
      ConditionAxis axis,
      String label,
      bool? Function(_Day) condition,
      double Function(_Day) outcome, {
      bool Function(_Day)? include,
    }) {
      final finding = _compare(
        days: days,
        axis: axis,
        label: label,
        condition: condition,
        outcome: outcome,
        include: include,
      );
      if (finding != null) findings.add(finding);
    }

    final planCutoff = _bestPlanCutoff(days);
    if (planCutoff != null) findings.add(planCutoff);

    consider(
      ConditionAxis.earlyStart,
      '첫 손을 낮 전에 댄 날',
      (day) => day.firstStartHour == null
          ? null
          : day.firstStartHour! < earlyStartHour,
      (day) => day.rate,
      include: (day) => day.planned > 0,
    );

    // 루틴을 한 날에 루틴까지 결과에 넣으면, 루틴을 했으니 완료율이 높다는
    // 동어반복이 된다. 루틴이 아닌 할 일만 본다.
    consider(
      ConditionAxis.routineDone,
      '루틴을 하나라도 끝낸 날',
      (day) => day.routineDone,
      (day) => day.nonRoutineRate,
      include: (day) => day.nonRoutinePlanned > 0,
    );

    // 첫 칸도 마찬가지다. 첫 칸을 끝냈으니 완료율이 높은 것은 발견이 아니다.
    consider(
      ConditionAxis.firstTaskDone,
      '목록 첫 칸을 끝낸 날',
      (day) => day.firstTaskDone,
      (day) => day.restRate,
      include: (day) => day.restPlanned > 0,
    );

    // 할 일이 하나뿐인 날은 자동으로 '몰아서'가 된다. 그러면 몰아서 한 날의
    // 완료율이 높다는 착시가 생기는데, 그건 시각이 아니라 개수가 만든 것이다.
    consider(
      ConditionAxis.spread,
      '손댄 시각이 여러 때에 나뉜 날',
      (day) => day.touchedSlots == 0 ? null : day.touchedSlots >= 2,
      (day) => day.rate,
      include: (day) => day.planned >= 2,
    );

    return ConditionInsights(findings, evaluatedDays: days.length);
  }

  static ConditionFinding? _compare({
    required List<_Day> days,
    required ConditionAxis axis,
    required String label,
    required bool? Function(_Day) condition,
    required double Function(_Day) outcome,
    bool Function(_Day)? include,
    int? cutoff,
  }) {
    final nextDayRate = _nextDayRates(days);

    final trues = <_Day>[];
    final falses = <_Day>[];
    for (final day in days) {
      if (include != null && !include(day)) continue;
      final value = condition(day);
      if (value == null) continue;
      (value ? trues : falses).add(day);
    }
    if (trues.length < minSideDays || falses.length < minSideDays) return null;

    double rateOf(List<_Day> group) =>
        group.map(outcome).reduce((a, b) => a + b) / group.length;

    double? nextOf(List<_Day> group) {
      final values = group
          .map((day) => nextDayRate[day.date])
          .whereType<double>()
          .toList();
      if (values.length < minSideDays) return null;
      return values.reduce((a, b) => a + b) / values.length;
    }

    final trueRate = axis.measuresNextDay ? nextOf(trues) : rateOf(trues);
    final falseRate = axis.measuresNextDay ? nextOf(falses) : rateOf(falses);
    if (trueRate == null || falseRate == null) return null;

    final gap = trueRate - falseRate;
    final threshold =
        (trues.length >= comfortableSideDays &&
            falses.length >= comfortableSideDays)
        ? comfortableGap
        : minGap;
    if (gap.abs() < threshold) return null;

    return ConditionFinding(
      axis: axis,
      label: label,
      whenTrueDays: trues.length,
      whenFalseDays: falses.length,
      whenTrueRate: trueRate,
      whenFalseRate: falseRate,
      nextDayTrueRate: nextOf(trues),
      nextDayFalseRate: nextOf(falses),
      cutoff: cutoff,
      trueDates: trues.map(_dateKey).toSet(),
      consistent: _sameDirectionInBothHalves(
        days: days,
        condition: condition,
        outcome: axis.measuresNextDay
            ? (day) => nextDayRate[day.date] ?? 0
            : outcome,
        include: axis.measuresNextDay
            ? (day) =>
                  (include == null || include(day)) &&
                  nextDayRate.containsKey(day.date)
            : include,
        direction: gap,
      ),
    );
  }

  /// 창을 앞뒤로 갈라, 양쪽에서 방향이 같은지 본다.
  ///
  /// 한쪽이라도 잴 수 없으면 false다. 반복되는 것을 확인하려는 자리라,
  /// 확인 못 한 것을 확인된 것으로 세면 안 된다.
  static bool _sameDirectionInBothHalves({
    required List<_Day> days,
    required bool? Function(_Day) condition,
    required double Function(_Day) outcome,
    required double direction,
    bool Function(_Day)? include,
  }) {
    final half = days.length ~/ 2;
    final halves = [days.sublist(0, half), days.sublist(half)];
    for (final part in halves) {
      final trues = <double>[];
      final falses = <double>[];
      for (final day in part) {
        if (include != null && !include(day)) continue;
        final value = condition(day);
        if (value == null) continue;
        (value ? trues : falses).add(outcome(day));
      }
      if (trues.isEmpty || falses.isEmpty) return false;
      double avg(List<double> v) => v.reduce((a, b) => a + b) / v.length;
      final gap = avg(trues) - avg(falses);
      if (gap == 0 || (gap > 0) != (direction > 0)) return false;
    }
    return true;
  }

  /// 각 날짜의 **다음 날** 완료율. 다음 날 기록이 없거나 하루 건너뛰었으면 뺀다.
  static Map<DateTime, double> _nextDayRates(List<_Day> days) {
    final rates = <DateTime, double>{};
    for (var i = 0; i < days.length - 1; i++) {
      final today = days[i];
      final next = days[i + 1];
      if (next.date.difference(today.date).inDays != 1) continue;
      if (next.planned == 0) continue;
      rates[today.date] = next.rate;
    }
    return rates;
  }

  static String _dateKey(_Day day) =>
      '${day.date.year}-${day.date.month.toString().padLeft(2, '0')}-'
      '${day.date.day.toString().padLeft(2, '0')}';

  /// 몇 개를 넘어가면 완료율이 떨어지는지, 경계를 찾는다.
  ///
  /// 평균이나 중앙값으로 가르면 "평소보다 적게 잡은 날"까지밖에 말할 수 없다.
  /// 그 말로는 다음 주에 뭘 해야 할지 알 수 없다 — 적게가 몇 개인지는 사람마다
  /// 다르고, 본인도 모른다. 그래서 기준을 하나씩 대보고 제일 크게 갈리는
  /// 자리를 찾는다.
  ///
  /// 기준을 여럿 대보는 만큼 우연히 벌어진 자리를 고를 위험도 커진다. 그래서
  /// 앞뒤 절반 방향이 같은 것만 남긴다 — 어느 기준이든 그 검사를 통과해야 한다.
  static ConditionFinding? _bestPlanCutoff(List<_Day> days) {
    final counts = days.map((day) => day.planned).where((c) => c > 0).toList();
    if (counts.isEmpty) return null;
    final highest = counts.reduce((a, b) => a > b ? a : b);

    ConditionFinding? best;
    for (var cutoff = minPlanCutoff; cutoff < highest; cutoff++) {
      final here = cutoff;
      final finding = _compare(
        days: days,
        axis: ConditionAxis.smallPlan,
        label: '계획을 $here개까지만 잡은 날',
        condition: (day) => day.planned <= here,
        outcome: (day) => day.rate,
        include: (day) => day.planned > 0,
        cutoff: here,
      );
      if (finding == null) continue;
      if (!finding.consistent) continue;
      if (best == null || finding.gap.abs() > best.gap.abs()) best = finding;
    }
    return best;
  }

  static List<_Day> _readDays(String? rawHistory) {
    if (rawHistory == null || rawHistory.isEmpty) return const [];
    List<dynamic> decoded;
    try {
      decoded = jsonDecode(rawHistory) as List;
    } catch (_) {
      return const [];
    }

    final days = <_Day>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      final date = DateTime.tryParse(entry['date']?.toString() ?? '');
      if (date == null) continue;
      final tasks = (entry['tasks'] as List?)
          ?.whereType<Map>()
          // 이월 항목은 그날 계획이 아니라 넘어온 것이라 분모에 넣지 않는다.
          .where((task) => task['deferred'] != true)
          .toList();
      if (tasks == null || tasks.isEmpty) continue;

      bool isDone(Map task) => task['done'] == true;
      bool isRoutine(Map task) => task['category'] == 'habit';

      final hours = <int>[];
      for (final task in tasks) {
        for (final key in const ['startedAt', 'completedAt']) {
          final at = DateTime.tryParse(task[key]?.toString() ?? '');
          if (at != null) hours.add(at.hour);
        }
      }
      final starts = tasks
          .map((task) => DateTime.tryParse(task['startedAt']?.toString() ?? ''))
          .whereType<DateTime>()
          .map((at) => at.hour)
          .toList()
        ..sort();

      final nonRoutine = tasks.where((task) => !isRoutine(task)).toList();
      final rest = tasks.skip(1).toList();

      days.add(
        _Day(
          date: DateTime(date.year, date.month, date.day),
          planned: tasks.length,
          done: tasks.where(isDone).length,
          firstStartHour: starts.isEmpty ? null : starts.first,
          routineDone: tasks.any((task) => isRoutine(task) && isDone(task)),
          nonRoutinePlanned: nonRoutine.length,
          nonRoutineDone: nonRoutine.where(isDone).length,
          firstTaskDone: isDone(tasks.first),
          restPlanned: rest.length,
          restDone: rest.where(isDone).length,
          touchedSlots: hours.map((h) => h - h % slotHours).toSet().length,
        ),
      );
    }

    days.sort((a, b) => a.date.compareTo(b.date));
    return days;
  }
}
