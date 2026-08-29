import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/day_capacity_service.dart';

/// [daysAgo]일 전 기록 하나.
Map<String, dynamic> day(int daysAgo, {required int planned, required int done}) {
  final date = DateTime.now().subtract(Duration(days: daysAgo));
  return {
    'date':
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}',
    'tasks': [
      for (var i = 0; i < planned; i++) {'text': '할 일 $i', 'done': i < done},
    ],
  };
}

String history(List<Map<String, dynamic>> days) => jsonEncode(days);

void main() {
  group('시간을 물어볼 사람인지', () {
    test('많이 잡고 못 끝내는 사람에게는 묻는다', () {
      expect(
        DayCapacityService.worthAsking(
          history([
            day(1, planned: 6, done: 2),
            day(2, planned: 5, done: 1),
            day(3, planned: 3, done: 2),
          ]),
        ),
        isTrue,
      );
    });

    test('많이 잡아도 다 해내면 묻지 않는다', () {
      // 자기 하루를 이미 맞춰 잡고 있는 사람에게 시간을 묻는 건 검사가 된다.
      expect(
        DayCapacityService.worthAsking(
          history([
            day(1, planned: 6, done: 6),
            day(2, planned: 5, done: 5),
            day(3, planned: 5, done: 4),
          ]),
        ),
        isFalse,
      );
    });

    test('적게 잡는 사람에게는 묻지 않는다', () {
      // 두세 개만 적는 사람에게는 잴 것이 없다. 완료율이 낮아도 마찬가지다.
      expect(
        DayCapacityService.worthAsking(
          history([
            day(1, planned: 2, done: 0),
            day(2, planned: 3, done: 1),
            day(3, planned: 2, done: 0),
          ]),
        ),
        isFalse,
      );
    });

    test('오늘 잡은 것으로는 판단하지 않는다', () {
      // 오늘은 아직 끝나지 않았다. 아침에 여섯 개 적어둔 것만 보고 물으면
      // 그날 하루도 안 지켜보고 판단하는 셈이다.
      expect(
        DayCapacityService.worthAsking(history([day(0, planned: 6, done: 0)])),
        isFalse,
      );
    });

    test('기록이 없으면 묻지 않는다', () {
      expect(DayCapacityService.worthAsking(null), isFalse);
      expect(DayCapacityService.worthAsking('[]'), isFalse);
      expect(DayCapacityService.worthAsking('망가진 값'), isFalse);
    });

    test('지난주 것은 세지 않는다', () {
      expect(
        DayCapacityService.worthAsking(history([day(10, planned: 8, done: 0)])),
        isFalse,
      );
    });
  });
}
