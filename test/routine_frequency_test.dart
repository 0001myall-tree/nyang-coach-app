import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_frequency.dart';

/// 코치가 태그에 적어 보낸 반복 규칙을 읽는다.
///
/// 예전에는 사용자 말을 앱이 정규식으로 풀었는데, "평일만"처럼 정규식에 없는
/// 말은 그냥 매일이 됐다. 평일만 하겠다고 말해놓고 주말에도 뜨는 루틴을 받는
/// 셈이었다.
void main() {
  group('매일', () {
    test('매일을 읽는다', () {
      expect(RoutineFrequency.parse('매일')?.freq, 'daily');
      expect(RoutineFrequency.parse('daily')?.freq, 'daily');
      expect(RoutineFrequency.parse('날마다')?.freq, 'daily');
    });

    test('이레를 다 고른 것은 매일과 같다', () {
      expect(RoutineFrequency.parse('월화수목금토일')?.freq, 'daily');
      expect(RoutineFrequency.parse('주7회')?.freq, 'daily');
    });
  });

  group('평일과 주말', () {
    test('평일은 월~금이다', () {
      final parsed = RoutineFrequency.parse('평일');
      expect(parsed?.freq, 'weekly');
      expect(parsed?.days, [0, 1, 2, 3, 4]);
    });

    test('"평일만", "주중"도 같다', () {
      expect(RoutineFrequency.parse('평일만')?.days, [0, 1, 2, 3, 4]);
      expect(RoutineFrequency.parse('주중')?.days, [0, 1, 2, 3, 4]);
    });

    test('주말은 토·일이다', () {
      final parsed = RoutineFrequency.parse('주말');
      expect(parsed?.freq, 'weekly');
      expect(parsed?.days, [5, 6]);
    });
  });

  group('요일 나열', () {
    test('쉼표로 나눈 요일을 읽는다', () {
      final parsed = RoutineFrequency.parse('월,수,금');
      expect(parsed?.freq, 'weekly');
      expect(parsed?.days, [0, 2, 4]);
    });

    test('붙여 써도 읽는다', () {
      expect(RoutineFrequency.parse('월수금')?.days, [0, 2, 4]);
    });

    test('가운뎃점도 받는다', () {
      expect(RoutineFrequency.parse('화·목')?.days, [1, 3]);
    });

    test('"요일"을 붙여 써도 읽는다', () {
      expect(RoutineFrequency.parse('월요일,수요일')?.days, [0, 2]);
    });

    test('순서대로 정리된다', () {
      expect(RoutineFrequency.parse('금,월,수')?.days, [0, 2, 4]);
    });

    test('겹쳐도 한 번만 센다', () {
      expect(RoutineFrequency.parse('월,월,수')?.days, [0, 2]);
    });
  });

  group('주 n회', () {
    test('주3회를 읽는다', () {
      final parsed = RoutineFrequency.parse('주3회');
      expect(parsed?.freq, 'weekly_count');
      expect(parsed?.weeklyTargetCount, 3);
    });

    test('"주 3일", "일주일에 2번"도 같다', () {
      expect(RoutineFrequency.parse('주 3일')?.weeklyTargetCount, 3);
      expect(RoutineFrequency.parse('일주일에 2번')?.weeklyTargetCount, 2);
    });
  });

  group('못 읽는 것', () {
    test('빈 값이면 null', () {
      expect(RoutineFrequency.parse(null), isNull);
      expect(RoutineFrequency.parse(''), isNull);
      expect(RoutineFrequency.parse('   '), isNull);
    });

    test('모르는 말이면 null — 예전 방식이 맡는다', () {
      expect(RoutineFrequency.parse('가끔'), isNull);
      expect(RoutineFrequency.parse('생각날 때마다'), isNull);
      expect(RoutineFrequency.parse('격일'), isNull);
    });

    test('루틴 이름을 요일로 잘못 읽지 않는다', () {
      // '일기'의 '일', '수영'의 '수'가 요일로 읽히면 엉뚱한 반복이 된다.
      expect(RoutineFrequency.parse('일기'), isNull);
      expect(RoutineFrequency.parse('수영'), isNull);
      expect(RoutineFrequency.parse('금연'), isNull);
    });
  });
}
