import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/life_routine_analysis.dart';

/// 판정을 코치에게 맡기지 않는다는 것이 이 층의 전부다. 무엇을 말할지가
/// 아니라 말을 걸지 말지가 여기서 갈린다.
void main() {
  final now = DateTime(2026, 9, 1, 10); // 화요일

  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// [days]일치 기록. 하루에 [planned]개 잡고 [done]개 끝냈다.
  ///
  /// [startHour]를 주면 그 시각에 시작한 일이 하루에 하나씩 남는다.
  String history({
    int days = 20,
    int planned = 2,
    int done = 2,
    int? startHour,
    Set<int>? onlyWeekdays,
  }) {
    final records = <Map<String, dynamic>>[];
    for (var offset = 0; offset < days; offset++) {
      final day = DateTime(now.year, now.month, now.day - offset);
      if (onlyWeekdays != null && !onlyWeekdays.contains(day.weekday - 1)) {
        continue;
      }
      records.add({
        'date': key(day),
        'totalCount': planned,
        'doneCount': done,
        'tasks': [
          for (var i = 0; i < planned; i++)
            {
              'text': '할 일 $i',
              'done': i < done,
              if (startHour != null)
                'startedAt': DateTime(
                  day.year,
                  day.month,
                  day.day,
                  startHour,
                ).toIso8601String(),
            },
        ],
      });
    }
    return jsonEncode(records);
  }

  Map<String, dynamic> habit(
    String id,
    String name, {
    List<int> days = const [],
    String? timeStart,
  }) => {
    'id': id,
    'name': name,
    'freq': days.isEmpty ? 'daily' : 'weekly',
    'days': days,
    if (timeStart != null) 'timeStart': timeStart,
  };

  /// [id] 루틴을 [doneWeekdays] 요일마다 해냈다고 도장을 찍는다.
  String logs(String id, Set<int> doneWeekdays, {int days = 30}) {
    final byDate = <String, dynamic>{};
    for (var offset = 0; offset < days; offset++) {
      final day = DateTime(now.year, now.month, now.day - offset);
      if (!doneWeekdays.contains(day.weekday - 1)) continue;
      byDate[key(day)] = {'done': true};
    }
    return jsonEncode({id: byDate});
  }

  group('말을 걸지 않는 자리', () {
    test('집안일을 남이 주로 하면', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(),
        answers: const {'share': '다른 사람이 주로 해'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.speaks, isFalse);
    });

    test('챙기고 싶은 게 없다고 했으면', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(),
        answers: const {
          'want': ['딱히 없어'],
        },
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
    });

    test('기록이 모자라면', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 5),
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.reason, contains('모자라'));
    });

    test('담당 루틴이 잘 굴러가고 있으면', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(),
        habitsRaw: jsonEncode([habit('h1', '설거지')]),
        habitLogsRaw: logs('h1', {0, 1, 2, 3, 4, 5, 6}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.reason, contains('잘 유지'));
    });

    test('잡아둔 것도 절반을 못 끝내는 중이면 새로 넣지 않는다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(planned: 6, done: 1, startHour: 10),
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.reason, contains('절반'));
    });

    test('넣을 시간대를 못 찾으면', () {
      // 시작 기록이 아예 없는 사람. 비어 있는 시간은 많지만 자리는 아니다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(),
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.reason, contains('시간대'));
    });
  });

  group('루틴은 웬만하면 건드리지 않는다', () {
    test('절반쯤 되고 있으면 그대로 둔다', () {
      // 화·목으로 잡았는데 화요일만 되고 있다. 50%다.
      //
      // 루틴은 한 번 넣으면 거의 고정으로 두는 것이라, 이 정도로 옮기라
      // 줄이라 하면 도와주는 게 아니라 참견이 된다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([
          habit('h1', '운동', days: [1, 3]),
        ]),
        habitLogsRaw: logs('h1', {1}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
      expect(plan.reason, contains('건드리지 않음'));
    });

    test('반쯤 굴러가는 루틴을 둔 채 새로 얹지도 않는다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28, startHour: 10),
        habitsRaw: jsonEncode([
          habit('h1', '운동', days: [1, 3]),
        ]),
        habitLogsRaw: logs('h1', {1}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
    });

    test('만든 지 얼마 안 된 루틴은 판정하지 않는다', () {
      // 자리를 잡을 시간을 준 적이 없는데 안 되고 있다고 짚을 수는 없다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28, startHour: 10),
        habitsRaw: jsonEncode([
          {
            ...habit('h1', '새 루틴'),
            'createdAt': DateTime(
              now.year,
              now.month,
              now.day - 3,
            ).toIso8601String(),
          },
        ]),
        habitLogsRaw: jsonEncode({'h1': <String, dynamic>{}}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.hold);
    });
  });

  group('자리를 옮긴다', () {
    test('되는 요일이 따로 있으면', () {
      // 평일 다섯 날로 잡았는데 화요일만 되고 있다. 20%라 확실히 안 굴러간다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([
          habit('h1', '운동', days: [0, 1, 2, 3, 4]),
        ]),
        habitLogsRaw: logs('h1', {1}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      // 잡은 요일이 다섯인데 되는 요일이 하나라 횟수를 내리는 쪽으로 간다.
      expect(plan.verdict, LifeVerdict.reduce);
      expect(plan.target?.name, '운동');
      expect(plan.target?.workingDays, [1]);
    });

    test('잡은 요일과 되는 요일 수가 같으면 옮긴다', () {
      // 매일 루틴인데 화요일에만 붙고 있다. 잡힌 요일이 따로 없으니
      // 줄일 것이 아니라 그 자리로 옮길 일이다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([habit('h1', '스트레칭')]),
        habitLogsRaw: logs('h1', {1}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.move);
      expect(plan.target?.workingDays, [1]);
      expect(plan.reason, contains('화요일'));
    });
  });

  group('양을 줄인다', () {
    test('되는 요일이 하나도 없으면 자리를 옮길 곳이 없다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([habit('h1', '청소')]),
        habitLogsRaw: jsonEncode({'h1': <String, dynamic>{}}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.verdict, LifeVerdict.reduce);
      expect(plan.reason, contains('되는 요일이 따로 없어'));
    });
  });

  group('하나 넣는다', () {
    test('반복을 원한다고 한 사람에게만 루틴을 권한다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: true,
        now: now,
      );
      expect(plan.verdict, LifeVerdict.add);
      expect(plan.openWindows, isNotEmpty);
    });

    test('필요할 때만 하고 싶다고 하면 오늘 하루 안에서', () {
      // 루틴은 앞으로 계속 하겠다는 약속이라, 그걸 원한다고 하지 않은 사람에게
      // 권하면 안 지킬 것을 하나 더 떠안기는 셈이 된다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: false,
        now: now,
      );
      expect(plan.verdict, LifeVerdict.today);
    });

    test('루틴이 이미 5개면 반복을 더 얹지 않는다', () {
      // 담당이 다른 루틴이라 앞의 판정에는 하나도 안 걸리지만, 지키는 것은
      // 영역이 아니라 사람이다. 총량으로 막는 자리는 여기 하나뿐이다.
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        habitsRaw: jsonEncode([
          for (var i = 0; i < LifeRoutineAnalysis.maxRoutinesForNew; i++)
            habit('other$i', '남의 영역 루틴 $i'),
        ]),
        prefersRoutine: true,
        now: now,
      );
      expect(plan.verdict, LifeVerdict.today);
      expect(plan.reason, contains('5개'));
    });

    test('루틴이 4개면 아직 권한다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        habitsRaw: jsonEncode([
          for (var i = 0; i < LifeRoutineAnalysis.maxRoutinesForNew - 1; i++)
            habit('other$i', '남의 영역 루틴 $i'),
        ]),
        prefersRoutine: true,
        now: now,
      );
      expect(plan.verdict, LifeVerdict.add);
    });

    test('모르겠으면 가벼운 쪽부터', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        now: now,
      );
      expect(plan.verdict, LifeVerdict.today);
    });

    test('오늘 갈래에는 루틴을 만들자고 하지 말라고 못박는다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: false,
        now: now,
      );
      expect(plan.promptBlock(), contains('루틴으로 만들자고 하지 마세요'));
      expect(plan.promptBlock(), contains('이미 하는 일에 붙이는 것'));
    });

    test('자리는 근거가 많은 순서로', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: true,
        now: now,
      );
      final evidences = plan.openWindows.map((w) => w.evidence).toList();
      expect(evidences, orderedEquals([...evidences]..sort((a, b) => b - a)));
    });
  });

  group('빈자리 찾기', () {
    test('시작한 적 없는 시간은 자리가 아니다', () {
      // 늘 비어 있는 새벽에 넣으면 아무도 안 한다.
      final windows = LifeRoutineAnalysis.openWindows(
        historyRaw: history(startHour: 10),
        now: now,
      );
      expect(windows.every((w) => w.startHour == 10), isTrue);
    });

    test('이미 루틴이 잡힌 자리는 뺀다', () {
      final windows = LifeRoutineAnalysis.openWindows(
        historyRaw: history(startHour: 10),
        habitsRaw: jsonEncode([habit('h9', '기존 루틴', timeStart: '10:30')]),
        now: now,
      );
      expect(windows, isEmpty);
    });

    test('그 요일에 일정이 있으면 그 요일만 뺀다', () {
      final tuesday = DateTime(now.year, now.month, now.day);
      final windows = LifeRoutineAnalysis.openWindows(
        historyRaw: history(startHour: 10),
        schedulesRaw: jsonEncode({
          key(tuesday): [
            {'text': '회의', 'timeStart': '10:00'},
          ],
        }),
        now: now,
      );
      expect(windows.any((w) => w.weekday == 1), isFalse);
      expect(windows, isNotEmpty);
    });

    test('한두 번 시작한 것으로는 자리라고 하지 않는다', () {
      final windows = LifeRoutineAnalysis.openWindows(
        historyRaw: history(days: 1, startHour: 10),
        now: now,
      );
      expect(windows, isEmpty);
    });

    test('기록이 없으면 빈 목록', () {
      expect(LifeRoutineAnalysis.openWindows(now: now), isEmpty);
    });
  });

  group('코치에게 넘기는 묶음', () {
    test('말을 걸 자리가 아니면 아무것도 안 싣는다', () {
      expect(LifeRoutinePlan.quiet.promptBlock(), isEmpty);
    });

    test('넣을 때는 자리 후보까지 준다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: true,
        now: now,
      );
      final block = plan.promptBlock();
      expect(block, contains('하나만'));
      expect(block, contains('시'));
    });

    test('줄일 때는 후퇴가 아니라는 것을 전하게 한다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([habit('h1', '청소')]),
        habitLogsRaw: jsonEncode({'h1': <String, dynamic>{}}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.promptBlock(), contains('후퇴'));
    });

    test('옮길 때는 못 지킨 날을 짚지 말라고 한다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(days: 28),
        habitsRaw: jsonEncode([habit('h1', '스트레칭')]),
        habitLogsRaw: logs('h1', {1}),
        domainHabitIds: const {'h1'},
        now: now,
      );
      expect(plan.promptBlock(), contains('못 지킨 날을 짚지'));
    });

    test('앱이 센 값이라는 것을 밝힌다', () {
      final plan = LifeRoutineAnalysis.analyze(
        historyRaw: history(startHour: 10),
        prefersRoutine: true,
        now: now,
      );
      expect(plan.promptBlock(), contains('여기 없는 것은 세지 않았'));
    });
  });

  group('요일 이름', () {
    test('사람이 읽는 말로', () {
      const window = OpenWindow(weekday: 5, startHour: 9, evidence: 4);
      expect(window.label, '토요일 오전 9~11시');
    });

    test('오후도 열두 시간으로', () {
      const window = OpenWindow(weekday: 0, startHour: 20, evidence: 3);
      expect(window.label, '월요일 오후 8~10시');
    });
  });
}
