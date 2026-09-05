import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_spread_analysis.dart';

/// 매일 루틴이 너무 많아 매일 다 못 채우는 상태를 가려낸다.
///
/// 요일로 나누자고 권하는 자리라, 나눌 거리가 없을 때는 아무 말도 하지 않아야
/// 한다. 잘 하고 있는 사람에게 "요즘 뜸하네요"가 나가면 그건 지적이 된다.
void main() {
  // 2026-09-04는 금요일. 앞선 평일 닷새는 9/3(목) 9/2(수) 9/1(화) 8/31(월) 8/28(금)이다.
  final now = DateTime(2026, 9, 4, 10);

  String habits(List<Map<String, dynamic>> items) => jsonEncode(items);

  Map<String, dynamic> daily(String id, String name, {String? createdAt}) => {
    'id': id,
    'name': name,
    'freq': 'daily',
    'createdAt': createdAt ?? '2026-01-01T09:00:00.000',
  };

  /// 앱이 세는 평일 중 가까운 쪽부터 [doneDays]일을 완료로 채운 기록.
  Map<String, dynamic> logsFor(Map<String, int> doneDaysById) {
    final weekdays = RoutineSpreadAnalysis.recentWeekdays(now);
    final logs = <String, dynamic>{};
    doneDaysById.forEach((id, doneDays) {
      final forHabit = <String, dynamic>{};
      for (var i = 0; i < doneDays && i < weekdays.length; i++) {
        forHabit[weekdays[i]] = {'done': true, 'status': 'done'};
      }
      logs[id] = forHabit;
    });
    return logs;
  }

  test('주말은 세지 않는다', () {
    final weekdays = RoutineSpreadAnalysis.recentWeekdays(now);
    // 금요일에서 거슬러 오르면 목·수·화·월, 그리고 주말을 건너뛴 지난 금요일.
    expect(weekdays, [
      '2026-09-03',
      '2026-09-02',
      '2026-09-01',
      '2026-08-31',
      '2026-08-28',
    ]);
  });

  test('금요일에만 묻는다', () {
    expect(RoutineSpreadAnalysis.isAskDay(DateTime(2026, 9, 4)), isTrue);
    expect(RoutineSpreadAnalysis.isAskDay(DateTime(2026, 9, 5)), isFalse);
    expect(RoutineSpreadAnalysis.isAskDay(DateTime(2026, 9, 7)), isFalse);
  });

  test('주말에 안 한 것은 빈 날로 세지 않는다', () {
    // 평일 닷새를 다 채웠고 주말에만 쉬었다. 잘 하고 있는 사람이다.
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '운동'),
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      habitLogsRaw: jsonEncode(
        logsFor({'1': 5, '2': 5, '3': 5, '4': 5, '5': 5}),
      ),
      now: now,
    );
    expect(found, isEmpty);
  });

  test('매일 루틴이 다섯 개가 안 되면 아무것도 안 고른다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '운동'),
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
      ]),
      habitLogsRaw: jsonEncode(logsFor({})),
      now: now,
    );
    expect(found, isEmpty);
  });

  test('다섯 개여도 잘 채우고 있으면 안 고른다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '운동'),
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      // 평일 닷새를 다 채웠으면 빈 날이 없다.
      habitLogsRaw: jsonEncode(
        logsFor({'1': 5, '2': 5, '3': 5, '4': 5, '5': 5}),
      ),
      now: now,
    );
    expect(found, isEmpty);
  });

  test('사흘 이상 빈 루틴만 고른다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '운동'),
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      habitLogsRaw: jsonEncode(
        logsFor({
          '1': 0, // 닷새 다 빔 → 후보
          '2': 2, // 사흘 빔 → 후보
          '3': 5, // 다 함
          '4': 4, // 하루 빔
          '5': 3, // 이틀 빔
        }),
      ),
      now: now,
    );

    expect(found.map((c) => c.name), ['운동', '독서']);
    expect(found.first.missedDays, 5);
    expect(found.first.doneDays, 0);
  });

  test('많이 빈 것이 앞에 온다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '조금 빈 것'),
        daily('2', '많이 빈 것'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      habitLogsRaw: jsonEncode(
        logsFor({'1': 2, '2': 0, '3': 5, '4': 5, '5': 5}),
      ),
      now: now,
    );
    expect(found.first.name, '많이 빈 것');
  });

  test('만든 지 일주일이 안 된 루틴은 세지 않는다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', '어제 만든 것', createdAt: '2026-09-03T09:00:00.000'),
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      habitLogsRaw: jsonEncode(logsFor({'2': 5, '3': 5, '4': 5, '5': 5})),
      now: now,
    );
    expect(found, isEmpty);
  });

  test('요일 지정 루틴은 세지 않는다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        {
          'id': '1',
          'name': '주말 청소',
          'freq': 'weekly',
          'days': [5, 6],
          'createdAt': '2026-01-01T09:00:00.000',
        },
        daily('2', '독서'),
        daily('3', '영양제'),
        daily('4', '스트레칭'),
        daily('5', '일기'),
      ]),
      habitLogsRaw: jsonEncode(logsFor({})),
      now: now,
    );
    // 매일 루틴이 넷뿐이라 문턱을 못 넘는다.
    expect(found, isEmpty);
  });

  test('넘기는 후보는 넷까지', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: habits([
        daily('1', 'ㄱ'),
        daily('2', 'ㄴ'),
        daily('3', 'ㄷ'),
        daily('4', 'ㄹ'),
        daily('5', 'ㅁ'),
        daily('6', 'ㅂ'),
      ]),
      habitLogsRaw: jsonEncode(logsFor({})),
      now: now,
    );
    expect(found.length, 4);
  });

  test('읽을 수 없는 값이 와도 무너지지 않는다', () {
    final found = RoutineSpreadAnalysis.candidates(
      habitsRaw: '{망가진',
      habitLogsRaw: null,
      now: now,
    );
    expect(found, isEmpty);
  });

  group('코치에게 넘기는 재료', () {
    test('후보가 없으면 빈 문자열', () {
      expect(
        RoutineSpreadAnalysis.promptBlock(
          candidates: const [],
          dailyRoutineCount: 5,
        ),
        isEmpty,
      );
    });

    test('이름과 함께 며칠 했는지 적는다', () {
      final block = RoutineSpreadAnalysis.promptBlock(
        candidates: const [
          RoutineSpreadCandidate(
            habitId: '1',
            name: '운동',
            missedDays: 3,
            doneDays: 2,
          ),
        ],
        dailyRoutineCount: 6,
      );
      expect(block, contains('매일 루틴 6개'));
      expect(block, contains('운동'));
      expect(block, contains('2일 함'));
      expect(block, contains('3일 비었음'));
    });
  });

  test('매일 루틴 개수를 센다', () {
    expect(
      RoutineSpreadAnalysis.dailyRoutineCount(
        habits([
          daily('1', 'ㄱ'),
          daily('2', 'ㄴ'),
          {
            'id': '3',
            'name': 'ㄷ',
            'freq': 'weekly',
            'days': [0],
          },
        ]),
      ),
      2,
    );
  });
}
