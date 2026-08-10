/// 작업과 휴식을 번갈아 돌리는 타이머 설정.
///
/// 5분·15분·25분 버튼은 한 번 재고 끝난다. 그걸로 충분한 사람이 대부분이라
/// 그대로 뒀고, 포모도로처럼 쓰고 싶은 사람만 이 설정을 쓴다.
///
/// 순서는 작업 → 휴식 → 작업 → … 인데, **마지막 작업 뒤에는 휴식이 없다.**
/// 4회 반복이면 작업이 네 번, 휴식은 세 번이다. 마지막에 쉬라고 띄워봐야
/// 이미 끝난 타이머라 아무도 그 쉬는 시간을 안 지킨다.
library;

enum FocusPhase {
  work,
  rest;

  bool get isWork => this == FocusPhase.work;
}

/// 사용자가 저장해둔 설정.
class FocusCycleSetting {
  const FocusCycleSetting({
    required this.workMinutes,
    required this.restMinutes,
    required this.rounds,
  });

  static const FocusCycleSetting pomodoro = FocusCycleSetting(
    workMinutes: 25,
    restMinutes: 5,
    rounds: 4,
  );

  final int workMinutes;
  final int restMinutes;
  final int rounds;

  /// 고를 수 있는 값들. 자유 입력이면 "0분"이나 "300분" 같은 값이 들어온다.
  static const List<int> workChoices = [10, 15, 20, 25, 30, 40, 45, 50, 60];
  static const List<int> restChoices = [3, 5, 10, 15, 20];
  static const List<int> roundChoices = [1, 2, 3, 4, 5, 6, 8];

  bool get isValid =>
      workChoices.contains(workMinutes) &&
      restChoices.contains(restMinutes) &&
      roundChoices.contains(rounds);

  /// 반복이 1회면 휴식이 낄 자리가 없다. 그냥 한 번 재는 것과 같다.
  bool get hasRest => rounds > 1;

  /// 타이머 카드에 작게 붙는 줄. "25분 집중 · 5분 휴식 · 4회 반복"
  String get summary => hasRest
      ? '$workMinutes분 집중 · $restMinutes분 휴식 · $rounds회 반복'
      : '$workMinutes분 집중';

  /// 다 돌면 얼마나 걸리는지. 마지막 휴식이 빠지므로 (작업+휴식)×횟수가 아니다.
  int get totalMinutes =>
      workMinutes * rounds + restMinutes * (rounds - 1).clamp(0, rounds);

  String get totalLabel {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  Map<String, dynamic> toJson() => {
    'work': workMinutes,
    'rest': restMinutes,
    'rounds': rounds,
  };

  static FocusCycleSetting? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    int? read(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      return int.tryParse('$value');
    }

    final work = read('work');
    final rest = read('rest');
    final rounds = read('rounds');
    if (work == null || rest == null || rounds == null) return null;
    final setting = FocusCycleSetting(
      workMinutes: work,
      restMinutes: rest,
      rounds: rounds,
    );
    return setting.isValid ? setting : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FocusCycleSetting &&
      other.workMinutes == workMinutes &&
      other.restMinutes == restMinutes &&
      other.rounds == rounds;

  @override
  int get hashCode => Object.hash(workMinutes, restMinutes, rounds);

  @override
  String toString() => 'FocusCycleSetting($summary)';
}

/// 지금 돌아야 할 한 구간.
class FocusCycleStep {
  const FocusCycleStep({
    required this.phase,
    required this.round,
    required this.minutes,
  });

  final FocusPhase phase;

  /// 1부터 센다. 휴식 구간의 회차는 그 앞 작업의 회차다.
  final int round;

  final int minutes;

  @override
  bool operator ==(Object other) =>
      other is FocusCycleStep &&
      other.phase == phase &&
      other.round == round &&
      other.minutes == minutes;

  @override
  int get hashCode => Object.hash(phase, round, minutes);

  @override
  String toString() => 'FocusCycleStep(${phase.name} $round회차 $minutes분)';
}

class FocusCycle {
  const FocusCycle._();

  /// 맨 처음 돌 구간. 언제나 1회차 작업이다.
  static FocusCycleStep first(FocusCycleSetting setting) => FocusCycleStep(
    phase: FocusPhase.work,
    round: 1,
    minutes: setting.workMinutes,
  );

  /// [current]가 끝난 뒤 이어서 돌 구간. 다 돌았으면 null.
  static FocusCycleStep? next(
    FocusCycleSetting setting,
    FocusCycleStep current,
  ) {
    if (current.phase.isWork) {
      // 마지막 작업이 끝나면 쉬지 않고 전체를 닫는다.
      if (current.round >= setting.rounds) return null;
      if (!setting.hasRest) return null;
      return FocusCycleStep(
        phase: FocusPhase.rest,
        round: current.round,
        minutes: setting.restMinutes,
      );
    }
    return FocusCycleStep(
      phase: FocusPhase.work,
      round: current.round + 1,
      minutes: setting.workMinutes,
    );
  }

  /// 화면에 띄우는 진행 표시. "2회차 집중 (2/4)"
  static String progressLabel(FocusCycleSetting setting, FocusCycleStep step) {
    final what = step.phase.isWork ? '집중' : '휴식';
    return '${step.round}회차 $what (${step.round}/${setting.rounds})';
  }
}
