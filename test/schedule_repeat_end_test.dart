import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/schedule_repeat_end.dart';

/// 반복 일정이 언제까지인지 읽는다.
///
/// 이 값이 없으면 반복은 끝나지 않는다. 학원이 10월에 끝나는데 화·금마다
/// 1년치가 들어가면, 끝난 뒤로도 계속 뜬다.
void main() {
  final today = DateTime(2026, 9, 5);

  group('읽는 것', () {
    test('물결로 시작하는 날짜', () {
      expect(
        ScheduleRepeatEnd.parse('~2026-10-31', today: today),
        DateTime(2026, 10, 31),
      );
    });

    test('구분자가 달라도 읽는다', () {
      expect(
        ScheduleRepeatEnd.parse('~2026.10.31', today: today),
        DateTime(2026, 10, 31),
      );
      expect(
        ScheduleRepeatEnd.parse('~2026/10/31', today: today),
        DateTime(2026, 10, 31),
      );
    });

    test('한 자리 월·일도 읽는다', () {
      expect(
        ScheduleRepeatEnd.parse('~2026-1-5', today: today),
        isNull, // 지난 날이라 안 받는다
      );
      expect(
        ScheduleRepeatEnd.parse('~2027-1-5', today: today),
        DateTime(2027, 1, 5),
      );
    });

    test('"까지"를 붙여 써도 읽는다', () {
      expect(
        ScheduleRepeatEnd.parse('2026-10-31까지', today: today),
        DateTime(2026, 10, 31),
      );
    });

    test('until을 써도 읽는다', () {
      expect(
        ScheduleRepeatEnd.parse('until:2026-10-31', today: today),
        DateTime(2026, 10, 31),
      );
    });

    test('오늘까지도 받는다', () {
      expect(
        ScheduleRepeatEnd.parse('~2026-09-05', today: today),
        DateTime(2026, 9, 5),
      );
    });
  });

  group('안 받는 것', () {
    test('빈 값', () {
      expect(ScheduleRepeatEnd.parse(null, today: today), isNull);
      expect(ScheduleRepeatEnd.parse('', today: today), isNull);
      expect(ScheduleRepeatEnd.parse('~', today: today), isNull);
    });

    test('지난 날', () {
      expect(ScheduleRepeatEnd.parse('~2026-08-31', today: today), isNull);
    });

    test('없는 날', () {
      expect(ScheduleRepeatEnd.parse('~2026-02-31', today: today), isNull);
      expect(ScheduleRepeatEnd.parse('~2026-13-01', today: today), isNull);
    });

    test('날짜가 아닌 말', () {
      // 코치가 옮기지 않고 그대로 보낸 경우다. 앱은 이걸 날짜로 못 바꾼다.
      expect(ScheduleRepeatEnd.parse('~10월 말', today: today), isNull);
      expect(ScheduleRepeatEnd.parse('~이번 학기', today: today), isNull);
    });
  });

  group('종료일 조각인지 알아보기', () {
    test('물결이나 까지가 붙으면 종료일', () {
      expect(ScheduleRepeatEnd.looksLikeEnd('~2026-10-31'), isTrue);
      expect(ScheduleRepeatEnd.looksLikeEnd('2026-10-31까지'), isTrue);
      expect(ScheduleRepeatEnd.looksLikeEnd('until:2026-10-31'), isTrue);
    });

    test('알람은 종료일이 아니다', () {
      expect(ScheduleRepeatEnd.looksLikeEnd('알람'), isFalse);
      expect(ScheduleRepeatEnd.looksLikeEnd(''), isFalse);
    });
  });

  test('사람에게 보여줄 말', () {
    expect(ScheduleRepeatEnd.label(DateTime(2026, 10, 31)), '10월 31일까지');
  });
}
