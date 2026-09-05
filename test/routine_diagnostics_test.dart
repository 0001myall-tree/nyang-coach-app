import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_diagnostics.dart';

/// 루틴이 오늘 탭에서 사라졌을 때 무엇을 보여주는지.
///
/// "루틴 탭에는 있는데 오늘 탭에는 없다"를 만났을 때, 반복 설정 때문인지
/// 그날 쉬기로 찍힌 것인지 목록을 만들다 빠진 것인지 갈라 보여야 한다.
void main() {
  final now = DateTime(2026, 9, 5, 14, 30);
  const today = '2026-09-05';

  String report({
    List<Map<String, dynamic>> habits = const [],
    Map<String, dynamic> logs = const {},
    List<Map<String, dynamic>> tasks = const [],
    String? lastDate = today,
    String? resetDoneDate = today,
  }) {
    return RoutineDiagnostics.build(
      rawHabits: jsonEncode(habits),
      rawHabitLogs: jsonEncode(logs),
      rawTasks: jsonEncode(tasks),
      lastDate: lastDate,
      resetDoneDate: resetDoneDate,
      now: now,
    );
  }

  test('오늘 목록에 있는 루틴과 없는 루틴을 갈라 보여준다', () {
    final text = report(
      habits: [
        {'id': 1, 'name': 'SNS 글쓰기', 'freq': 'daily'},
        {'id': 2, 'name': '영양제 챙겨먹기', 'freq': 'daily'},
      ],
      tasks: [
        {'id': 'habit_1_$today', 'habitId': '1', 'text': 'SNS 글쓰기'},
      ],
    );

    expect(text, contains('SNS 글쓰기'));
    expect(text, contains('영양제 챙겨먹기'));
    expect(text, contains('오늘 목록: 있음'));
    expect(text, contains('오늘 목록: 없음'));
  });

  test('그날 쉬기로 찍힌 것이 보인다', () {
    final text = report(
      habits: [
        {'id': 2, 'name': '영양제 챙겨먹기', 'freq': 'daily'},
      ],
      logs: {
        '2': {
          today: {
            'done': false,
            'status': 'skipped',
            'skippedAt': '2026-09-05T09:12:00.000',
          },
        },
      },
    );

    expect(text, contains('쉬기 (09:12)'));
  });

  test('요일을 하나도 안 고른 루틴이 드러난다', () {
    final text = report(
      habits: [
        {'id': 3, 'name': '스트레칭', 'freq': 'weekly', 'days': <int>[]},
      ],
    );

    expect(text, contains('요일 지정 (고른 요일 없음)'));
  });

  test('반복 설정을 사람 말로 적는다', () {
    final text = report(
      habits: [
        {'id': 1, 'name': '매일 것', 'freq': 'daily'},
        {'id': 2, 'name': '주 것', 'freq': 'weekly_count', 'weeklyTargetCount': 3},
        {
          'id': 3,
          'name': '요일 것',
          'freq': 'weekly',
          'days': [0, 2, 4],
        },
      ],
    );

    expect(text, contains('반복: 매일'));
    expect(text, contains('반복: 주 3일'));
    expect(text, contains('반복: 요일 지정 월/수/금'));
  });

  test('저장된 날짜가 오늘이 아니면 짚어준다', () {
    final text = report(lastDate: '2026-09-04');
    expect(text, contains('저장된 날짜가 오늘이 아님'));
  });

  test('날짜가 맞으면 경고하지 않는다', () {
    final text = report();
    expect(text, isNot(contains('저장된 날짜가 오늘이 아님')));
  });

  test('읽을 수 없는 값이 와도 무너지지 않는다', () {
    final text = RoutineDiagnostics.build(
      rawHabits: '{망가진 json',
      rawHabitLogs: null,
      rawTasks: '',
      lastDate: null,
      resetDoneDate: null,
      now: now,
    );

    expect(text, contains('[루틴 0개]'));
    expect(text, contains('비어 있음'));
  });

  group('빠진 이유 짚기', () {
    test('쉬기로 찍혔으면 그걸 짚는다', () {
      final reason = RoutineDiagnostics.missingReason(
        habit: {'id': 2, 'freq': 'daily'},
        logs: {
          '2': {
            today: {'status': 'skipped'},
          },
        },
        today: today,
      );
      expect(reason, '오늘 쉬기로 찍혀 있음');
    });

    test('요일을 안 골랐으면 그걸 짚는다', () {
      final reason = RoutineDiagnostics.missingReason(
        habit: {'id': 3, 'freq': 'weekly', 'days': <int>[]},
        logs: const {},
        today: today,
      );
      expect(reason, '요일 지정인데 고른 요일이 없음');
    });

    test('멀쩡한 매일 루틴이면 짚을 게 없다', () {
      final reason = RoutineDiagnostics.missingReason(
        habit: {'id': 1, 'freq': 'daily'},
        logs: const {},
        today: today,
      );
      expect(reason, isNull);
    });
  });
}
