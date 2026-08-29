import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_pattern_service.dart';

/// [daysAgo]일 전 기록 하나.
Map<String, dynamic> day(
  int daysAgo, {
  required int planned,
  required int done,
  int startedNotDone = 0,
  int startHour = 10,
}) {
  final date = DateTime.now().subtract(Duration(days: daysAgo));
  final tasks = <Map<String, dynamic>>[];
  for (var i = 0; i < planned; i++) {
    final isDone = i < done;
    final started = isDone || i < done + startedNotDone;
    tasks.add({
      'text': '할 일 $i',
      'done': isDone,
      if (started)
        'startedAt': DateTime(
          date.year,
          date.month,
          date.day,
          startHour,
        ).toIso8601String(),
    });
  }
  return {
    'date':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'tasks': tasks,
  };
}

String history(List<Map<String, dynamic>> days) => jsonEncode(days);

void main() {
  group('셀 것이 모자랄 때', () {
    test('기록이 없으면 아무 말도 만들지 않는다', () {
      expect(ExecutionPatternService.blockFrom(null), isEmpty);
      expect(ExecutionPatternService.blockFrom('[]'), isEmpty);
    });

    test('이레 중 이틀만 적었으면 완료율 대신 그 사실만 말한다', () {
      final block = ExecutionPatternService.blockFrom(
        history([day(1, planned: 3, done: 0), day(3, planned: 2, done: 0)]),
      );
      expect(block, contains('뜸한 사용자'));
      expect(block, isNot(contains('하루 평균 계획')));
    });

    test('짚을 패턴이 없으면 숫자만 늘어놓지 않는다', () {
      // 완료율 60%에 시작 시각도 흩어져 있다. 과다도, 안정형도, 시간대도 아니다.
      final block = ExecutionPatternService.blockFrom(
        history([
          day(1, planned: 5, done: 3, startHour: 9),
          day(2, planned: 5, done: 3, startHour: 14),
          day(3, planned: 5, done: 3, startHour: 20),
          day(4, planned: 5, done: 3, startHour: 13),
          day(5, planned: 5, done: 3, startHour: 15),
        ]),
      );
      expect(block, isEmpty);
    });
  });

  group('패턴', () {
    test('계획이 해내는 양의 갑절이 넘으면 계획 과다형', () {
      final block = ExecutionPatternService.blockFrom(
        history(List.generate(5, (i) => day(i + 1, planned: 6, done: 2))),
      );
      expect(block, contains('계획 과다형'));
    });

    test('다 하는 날과 아예 안 하는 날로 갈리면 편차형', () {
      final block = ExecutionPatternService.blockFrom(
        history([
          day(1, planned: 3, done: 3),
          day(2, planned: 2, done: 0),
          day(3, planned: 2, done: 2),
          day(4, planned: 3, done: 0),
        ]),
      );
      expect(block, contains('편차형'));
    });

    test('편차형이면 계획 과다형은 붙지 않는다', () {
      // 하는 날에는 세 개도 다 끝내는 사람에게 계획을 줄이라고 하면 빗나간다.
      final block = ExecutionPatternService.blockFrom(
        history([
          day(1, planned: 4, done: 4),
          day(2, planned: 4, done: 0),
          day(3, planned: 4, done: 4),
          day(4, planned: 4, done: 0),
          day(5, planned: 4, done: 0),
        ]),
      );
      expect(block, contains('편차형'));
      expect(block, isNot(contains('계획 과다형')));
    });

    test('한쪽 날이 하루뿐이면 편차형으로 보지 않는다', () {
      // 하루씩으로는 그날 사정과 구분이 안 된다.
      final block = ExecutionPatternService.blockFrom(
        history([
          day(1, planned: 2, done: 2),
          day(2, planned: 2, done: 0),
          day(3, planned: 2, done: 1),
          day(4, planned: 2, done: 1),
        ]),
      );
      expect(block, isNot(contains('편차형')));
    });

    test('편차형이라도 지난주보다 해낸 날이 늘었으면 그것부터 알아준다', () {
      final block = ExecutionPatternService.blockFrom(
        history([
          // 이번 이레: 사흘 해냄
          day(1, planned: 2, done: 2),
          day(2, planned: 2, done: 0),
          day(3, planned: 2, done: 2),
          day(4, planned: 2, done: 0),
          day(5, planned: 2, done: 2),
          // 지난 이레: 하루만 해냄
          day(9, planned: 2, done: 2),
          day(10, planned: 2, done: 0),
          day(11, planned: 2, done: 0),
        ]),
      );
      expect(block, contains('편차형'));
      expect(block, contains('1일 → 3일'));
    });

    test('지난주보다 줄었으면 늘었다고 하지 않는다', () {
      final block = ExecutionPatternService.blockFrom(
        history([
          day(1, planned: 2, done: 2),
          day(2, planned: 2, done: 0),
          day(3, planned: 2, done: 2),
          day(4, planned: 2, done: 0),
          day(9, planned: 2, done: 2),
          day(10, planned: 2, done: 2),
          day(11, planned: 2, done: 2),
        ]),
      );
      expect(block, contains('편차형'));
      expect(block, isNot(contains('늘었음')));
    });

    test('시작은 하는데 못 끝내면 시작 꾸준형', () {
      // 다섯 개 중 둘 완료, 셋은 손댔지만 미완료 → 손댄 비율 100%.
      final block = ExecutionPatternService.blockFrom(
        history(
          List.generate(
            5,
            (i) => day(i + 1, planned: 5, done: 2, startedNotDone: 3),
          ),
        ),
      );
      expect(block, contains('시작 꾸준형'));
    });

    test('잘 돌아가는 사람에게는 건드리지 말라고 적는다', () {
      final block = ExecutionPatternService.blockFrom(
        history(List.generate(5, (i) => day(i + 1, planned: 4, done: 4))),
      );
      expect(block, contains('안정형'));
    });
  });

  group('시작 시간대', () {
    test('시작 기록이 다섯 개 미만이면 시간대를 말하지 않는다', () {
      // 하루 한 개씩만 시작. 사흘치라 표본이 셋뿐이다.
      final block = ExecutionPatternService.blockFrom(
        history(
          List.generate(
            3,
            (i) => day(i + 1, planned: 6, done: 1, startHour: 21),
          ),
        ),
      );
      expect(block, isNot(contains('시작하는 시간대')));
    });

    test('대부분 저녁에 시작하면 늦게 시작하는 편', () {
      final block = ExecutionPatternService.blockFrom(
        history(
          List.generate(
            5,
            (i) => day(i + 1, planned: 6, done: 2, startHour: 20),
          ),
        ),
      );
      expect(block, contains('늦게 시작하는 편'));
      expect(block, contains('오후 5시 이후'));
    });

    test('대부분 오전에 시작하면 아침형', () {
      final block = ExecutionPatternService.blockFrom(
        history(
          List.generate(
            5,
            (i) => day(i + 1, planned: 6, done: 2, startHour: 8),
          ),
        ),
      );
      expect(block, contains('아침형'));
    });
  });

  test('안정형이면 다른 패턴은 덮는다', () {
    // 완료율 75%인데 늘 저녁에 시작한다. "건드리지 마세요" 옆에
    // "낮에 조각을 만드세요"가 나란히 서면 서로 부딪힌다.
    final block = ExecutionPatternService.blockFrom(
      history(
        List.generate(5, (i) => day(i + 1, planned: 4, done: 3, startHour: 20)),
      ),
    );
    expect(block, contains('안정형'));
    expect(block, isNot(contains('늦게 시작하는 편')));
  });

  test('이레 중 이틀만 적었으면 뜸한 사용자', () {
    final block = ExecutionPatternService.blockFrom(
      history([day(1, planned: 3, done: 1), day(4, planned: 2, done: 0)]),
    );
    expect(block, contains('뜸한 사용자'));
  });
}
