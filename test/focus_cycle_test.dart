import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/focus_cycle.dart';

/// 설정 하나를 끝까지 돌려서 지나간 구간을 순서대로 모은다.
List<FocusCycleStep> runAll(FocusCycleSetting setting) {
  final steps = <FocusCycleStep>[];
  FocusCycleStep? step = FocusCycle.first(setting);
  while (step != null) {
    steps.add(step);
    step = FocusCycle.next(setting, step);
    if (steps.length > 50) fail('끝나지 않는다');
  }
  return steps;
}

void main() {
  group('작업과 휴식이 번갈아 돈다', () {
    test('작업 다음은 휴식, 휴식 다음은 작업', () {
      final steps = runAll(FocusCycleSetting.pomodoro);
      expect(steps.map((s) => s.phase.name).toList(), [
        'work', 'rest', //
        'work', 'rest', //
        'work', 'rest', //
        'work',
      ]);
    });

    test('마지막 작업 뒤에는 쉬지 않고 끝난다', () {
      final steps = runAll(FocusCycleSetting.pomodoro);
      expect(steps.last.phase, FocusPhase.work);
      expect(steps.last.round, 4);
      expect(FocusCycle.next(FocusCycleSetting.pomodoro, steps.last), isNull);
    });

    test('작업은 반복 횟수만큼, 휴식은 하나 적게', () {
      final steps = runAll(FocusCycleSetting.pomodoro);
      expect(steps.where((s) => s.phase.isWork).length, 4);
      expect(steps.where((s) => !s.phase.isWork).length, 3);
    });

    test('각 구간의 길이는 설정대로', () {
      const setting = FocusCycleSetting(
        workMinutes: 50,
        restMinutes: 10,
        rounds: 2,
      );
      final steps = runAll(setting);
      expect(steps.map((s) => s.minutes).toList(), [50, 10, 50]);
    });

    test('회차는 1부터 세고 휴식은 앞 작업의 회차를 쓴다', () {
      final steps = runAll(FocusCycleSetting.pomodoro);
      expect(steps.map((s) => s.round).toList(), [1, 1, 2, 2, 3, 3, 4]);
    });
  });

  group('반복이 한 번뿐일 때', () {
    const once = FocusCycleSetting(workMinutes: 25, restMinutes: 5, rounds: 1);

    test('휴식 없이 한 번만 돈다', () {
      final steps = runAll(once);
      expect(steps.length, 1);
      expect(steps.single.phase, FocusPhase.work);
    });

    test('요약에 휴식을 적지 않는다', () {
      expect(once.summary, '25분 집중');
      expect(once.hasRest, isFalse);
    });
  });

  group('요약과 총 시간', () {
    test('요약 문구', () {
      expect(FocusCycleSetting.pomodoro.summary, '25분 집중 · 5분 휴식 · 4회 반복');
    });

    test('마지막 휴식은 총 시간에서 빠진다', () {
      // (25+5)×4 = 120이 아니라 25×4 + 5×3 = 115.
      expect(FocusCycleSetting.pomodoro.totalMinutes, 115);
      expect(FocusCycleSetting.pomodoro.totalLabel, '1시간 55분');
    });

    test('한 시간 단위로 딱 떨어지면 분을 적지 않는다', () {
      const setting = FocusCycleSetting(
        workMinutes: 30,
        restMinutes: 10,
        rounds: 2,
      );
      expect(setting.totalMinutes, 70);
      expect(setting.totalLabel, '1시간 10분');
      const hour = FocusCycleSetting(
        workMinutes: 20,
        restMinutes: 10,
        rounds: 3,
      );
      expect(hour.totalLabel, '1시간 20분');
    });

    test('한 시간이 안 되면 분만 적는다', () {
      const setting = FocusCycleSetting(
        workMinutes: 10,
        restMinutes: 5,
        rounds: 2,
      );
      expect(setting.totalLabel, '25분');
    });
  });

  group('저장과 복원', () {
    test('저장했다 읽으면 같은 설정', () {
      const setting = FocusCycleSetting(
        workMinutes: 50,
        restMinutes: 10,
        rounds: 3,
      );
      expect(FocusCycleSetting.fromJson(setting.toJson()), setting);
    });

    test('없거나 망가진 값은 읽지 않는다', () {
      expect(FocusCycleSetting.fromJson(null), isNull);
      expect(FocusCycleSetting.fromJson({'work': 25}), isNull);
      // 목록에 없는 값이 들어오면 버린다. 0분짜리 작업이 저장되면 타이머가
      // 시작하자마자 끝나고 그게 무한히 반복된다.
      expect(
        FocusCycleSetting.fromJson({'work': 0, 'rest': 5, 'rounds': 4}),
        isNull,
      );
      expect(
        FocusCycleSetting.fromJson({'work': 25, 'rest': 5, 'rounds': 99}),
        isNull,
      );
      // 목록에서 뺀 값으로 저장해둔 사람이 있으면 조용히 버리고 빠른 선택으로
      // 돌아간다. 없는 값이 화면에 뜨면 드롭다운이 터진다.
      for (final gone in [20, 40, 45]) {
        expect(
          FocusCycleSetting.fromJson({'work': gone, 'rest': 5, 'rounds': 4}),
          isNull,
          reason: '$gone분',
        );
      }
    });
  });

  group('진행 표시', () {
    test('몇 회차 중 몇 번째인지 보여준다', () {
      final steps = runAll(FocusCycleSetting.pomodoro);
      expect(
        FocusCycle.progressLabel(FocusCycleSetting.pomodoro, steps[0]),
        '1회차 집중 (1/4)',
      );
      expect(
        FocusCycle.progressLabel(FocusCycleSetting.pomodoro, steps[1]),
        '1회차 휴식 (1/4)',
      );
      expect(
        FocusCycle.progressLabel(FocusCycleSetting.pomodoro, steps[6]),
        '4회차 집중 (4/4)',
      );
    });
  });
}
