import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_schedule.dart';

void main() {
  // 2026-08-17은 월요일이다. 주 시작이 그날이라 계산을 눈으로 따라가기 쉽다.
  final monday = DateTime(2026, 8, 17);
  final tuesday = DateTime(2026, 8, 18);
  final wednesday = DateTime(2026, 8, 19);
  final friday = DateTime(2026, 8, 21);

  Map<String, dynamic> doneLog({double? ratio}) => {
    'done': true,
    if (ratio != null) 'progressRatio': ratio,
  };

  group('주의 시작', () {
    test('월요일부터 센다', () {
      expect(RoutineSchedule.startOfWeek(wednesday), monday);
      expect(RoutineSchedule.startOfWeek(monday), monday);
      expect(RoutineSchedule.startOfWeek(DateTime(2026, 8, 23)), monday);
    });

    test('시각이 붙어 있어도 날짜만 본다', () {
      expect(RoutineSchedule.startOfWeek(DateTime(2026, 8, 19, 23, 40)), monday);
    });
  });

  group('주간 목표', () {
    test('없으면 5일', () {
      expect(RoutineSchedule.weeklyTarget(null), 5);
    });

    test('문자열로 저장돼 있어도 읽는다', () {
      expect(RoutineSchedule.weeklyTarget('3'), 3);
    });

    test('1~7을 벗어나면 끌어당긴다', () {
      expect(RoutineSchedule.weeklyTarget(0), 1);
      expect(RoutineSchedule.weeklyTarget(99), 7);
    });
  });

  group('만든 주에는 목표를 줄인다', () {
    test('금요일에 만든 주 5일은 그 주에 3일까지만', () {
      expect(
        RoutineSchedule.visibleWeeklyTarget(
          target: 5,
          createdDate: friday,
          date: friday,
        ),
        3,
      );
    });

    test('지난주에 만들었으면 그대로 5일', () {
      expect(
        RoutineSchedule.visibleWeeklyTarget(
          target: 5,
          createdDate: DateTime(2026, 8, 10),
          date: wednesday,
        ),
        5,
      );
    });

    test('남은 날이 목표보다 많으면 줄이지 않는다', () {
      expect(
        RoutineSchedule.visibleWeeklyTarget(
          target: 2,
          createdDate: monday,
          date: monday,
        ),
        2,
      );
    });
  });

  group('하루치를 몇 번으로 세는지', () {
    test('안 한 날은 0', () {
      expect(RoutineSchedule.logCompletionRatio(null), 0);
      expect(RoutineSchedule.logCompletionRatio({'done': false}), 0);
    });

    test('그냥 완료한 날은 1', () {
      expect(RoutineSchedule.logCompletionRatio(doneLog()), 1);
    });

    test('조금만 한 날은 그만큼만', () {
      expect(RoutineSchedule.logCompletionRatio(doneLog(ratio: 0.25)), 0.25);
    });

    test('수량으로 적힌 날은 비율로 환산한다', () {
      expect(
        RoutineSchedule.logCompletionRatio({
          'done': true,
          'count': 3,
          'countGoal': 4,
        }),
        0.75,
      );
    });

    test('목표를 넘겨도 1을 넘지 않는다', () {
      expect(RoutineSchedule.logCompletionRatio(doneLog(ratio: 2.5)), 1);
    });
  });

  group('이번 주에 몇 번 했는지', () {
    final logs = {
      RoutineSchedule.dateKey(monday): doneLog(),
      RoutineSchedule.dateKey(tuesday): doneLog(ratio: 0.5),
      RoutineSchedule.dateKey(wednesday): doneLog(),
    };

    test('그날 전까지 센다', () {
      expect(
        RoutineSchedule.doneCount(
          logs: logs,
          createdDate: null,
          date: wednesday,
          includeDate: false,
        ),
        1.5,
      );
    });

    test('그날까지 포함해 센다', () {
      expect(
        RoutineSchedule.doneCount(
          logs: logs,
          createdDate: null,
          date: wednesday,
          includeDate: true,
        ),
        2.5,
      );
    });

    test('만들기 전의 날은 세지 않는다', () {
      expect(
        RoutineSchedule.doneCount(
          logs: logs,
          createdDate: wednesday,
          date: wednesday,
          includeDate: true,
        ),
        1,
      );
    });

    test('지난주 기록은 넘어오지 않는다', () {
      final lastWeek = {
        RoutineSchedule.dateKey(DateTime(2026, 8, 14)): doneLog(),
      };
      expect(
        RoutineSchedule.doneCount(
          logs: lastWeek,
          createdDate: null,
          date: wednesday,
          includeDate: true,
        ),
        0,
      );
    });
  });

  group('주 몇 일짜리를 그날 올릴지', () {
    bool shows(Map<String, dynamic> logs, DateTime date, {Object? target = 2}) {
      return RoutineSchedule.shouldShowWeeklyCountOnDate(
        rawWeeklyTargetCount: target,
        rawCreatedAt: '2026-08-01',
        logs: logs,
        date: date,
      );
    }

    test('아직 못 채웠으면 올린다', () {
      expect(shows({RoutineSchedule.dateKey(monday): doneLog()}, wednesday), isTrue);
    });

    test('이번 주 목표를 채웠으면 그만 올린다', () {
      final logs = {
        RoutineSchedule.dateKey(monday): doneLog(),
        RoutineSchedule.dateKey(tuesday): doneLog(),
      };
      expect(shows(logs, wednesday), isFalse);
    });

    test('목표를 채웠어도 그날 한 것은 그대로 둔다', () {
      // 방금 완료한 카드가 눈앞에서 사라지면 완료가 취소된 것처럼 보인다.
      final logs = {
        RoutineSchedule.dateKey(monday): doneLog(),
        RoutineSchedule.dateKey(tuesday): doneLog(),
        RoutineSchedule.dateKey(wednesday): doneLog(),
      };
      expect(shows(logs, wednesday), isTrue);
    });

    test('조금만 한 날들은 목표를 채우지 못한다', () {
      final logs = {
        RoutineSchedule.dateKey(monday): doneLog(ratio: 0.5),
        RoutineSchedule.dateKey(tuesday): doneLog(ratio: 0.5),
      };
      expect(shows(logs, wednesday), isTrue);
    });

    test('기록이 아예 없으면 올린다', () {
      expect(shows(const {}, wednesday), isTrue);
    });

    test('만든 주에는 줄어든 목표로 판단한다', () {
      // 금요일에 만든 주 5일은 그 주에 3일까지다. 사흘을 채우면 그만 올린다.
      final logs = {
        RoutineSchedule.dateKey(friday): doneLog(),
        RoutineSchedule.dateKey(DateTime(2026, 8, 22)): doneLog(),
        RoutineSchedule.dateKey(DateTime(2026, 8, 23)): doneLog(),
      };
      final shownOnNextMonday = RoutineSchedule.shouldShowWeeklyCountOnDate(
        rawWeeklyTargetCount: 5,
        rawCreatedAt: '2026-08-21',
        logs: logs,
        date: DateTime(2026, 8, 24),
      );
      // 다음 주가 되면 목표는 다시 5일이고, 지난주 기록은 넘어오지 않는다.
      expect(shownOnNextMonday, isTrue);
    });
  });
}
