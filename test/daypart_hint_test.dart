import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daypart_hint.dart';

/// 시각은 안 적고 때만 적은 일에 시각을 붙여준다.
///
/// 구간의 뒤쪽을 고른다. 저녁을 6시로 잡으면 8시에 하려던 사람을 두 시간
/// 일찍 찌르고, 늦게 잡으면 이미 한 사람에게 알림이 안 가는 정도로 끝난다.
void main() {
  group('때를 읽는다', () {
    test('저녁은 구간 뒤쪽으로', () {
      expect(
        DaypartHint.read('저녁 글쓰기')?.time,
        const TimeOfDay(hour: 19, minute: 30),
      );
    });

    test('조사가 붙어도 읽는다', () {
      expect(DaypartHint.read('아침에 스트레칭')?.word, '아침');
      expect(DaypartHint.read('밤에 일기')?.word, '밤');
      expect(DaypartHint.read('점심때 약 먹기')?.word, '점심');
    });

    test('맨 끝에 와도 읽는다', () {
      expect(DaypartHint.read('산책 저녁')?.word, '저녁');
    });

    test('붙여 쓴 말은 때가 아니다', () {
      // 글자만 훑으면 '밤고구마'의 '밤'이 걸린다.
      expect(DaypartHint.read('밤고구마 사기'), isNull);
      expect(DaypartHint.read('아침형 인간 되기'), isNull);
    });

    test('때가 없으면 null', () {
      expect(DaypartHint.read('분기 리포트 쓰기'), isNull);
    });
  });

  group('잠드는 시각', () {
    test('자기 전은 취침 한 시간 전으로 당긴다', () {
      final hint = DaypartHint.read(
        '자기 전 스트레칭',
        bedtime: const TimeOfDay(hour: 23, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 22, minute: 0));
    });

    test('일찍 자는 사람은 밤 일도 당겨준다', () {
      final hint = DaypartHint.read(
        '밤에 일기',
        bedtime: const TimeOfDay(hour: 22, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 21, minute: 0));
    });

    test('늦게 자는 사람은 그대로 둔다', () {
      final hint = DaypartHint.read(
        '저녁 글쓰기',
        bedtime: const TimeOfDay(hour: 2, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 19, minute: 30));
    });
  });

  group('퇴근 시각', () {
    test('저녁 일은 퇴근 뒤로 민다', () {
      // 9시부터 7시까지 일하는 사람에게 저녁 7시 30분은 아직 회사다.
      final hint = DaypartHint.read(
        '저녁 글쓰기',
        workEnd: const TimeOfDay(hour: 20, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 20, minute: 30));
    });

    test('일찍 끝나면 원래 시각 그대로', () {
      final hint = DaypartHint.read(
        '저녁 글쓰기',
        workEnd: const TimeOfDay(hour: 18, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 19, minute: 30));
    });

    test('아침 일은 퇴근 뒤로 밀지 않는다', () {
      final hint = DaypartHint.read(
        '아침 스트레칭',
        workEnd: const TimeOfDay(hour: 20, minute: 0),
      );
      expect(hint?.time, const TimeOfDay(hour: 9, minute: 0));
    });
  });

  test('퇴근이 늦어도 취침 시각을 넘지 않는다', () {
    final hint = DaypartHint.read(
      '저녁 글쓰기',
      workEnd: const TimeOfDay(hour: 22, minute: 0),
      bedtime: const TimeOfDay(hour: 23, minute: 0),
    );
    expect(hint?.time, const TimeOfDay(hour: 22, minute: 0));
  });
}
