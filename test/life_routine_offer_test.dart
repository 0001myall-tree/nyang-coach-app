import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/life_routine_offer.dart';

/// 부르는 쪽은 통신이라 여기서 돌릴 수 없다. 남은 태그를 떼는 부분만 본다.
///
/// [TASK]는 부르는 쪽이 먼저 읽어 "추가할까?" 카드로 바꾼다. 여기 오는 것은
/// 그러고도 남은 것들이고, 이 말은 평소 답변과 달리 화면에 바로 꽂혀서 남아
/// 있으면 사용자에게 대괄호가 그대로 보인다.
void main() {
  group('받아온 말 다듬기', () {
    test('그냥 말이면 그대로', () {
      expect(
        LifeRoutineOffer.clean('토요일 오전에 20분만 해볼까?'),
        '토요일 오전에 20분만 해볼까?',
      );
    });

    test('읽히지 않고 남은 태그는 떼어낸다', () {
      expect(
        LifeRoutineOffer.clean('토요일 오전에 청소 20분 어때? [HABIT: 청소]'),
        '토요일 오전에 청소 20분 어때?',
      );
    });

    test('이름 없는 태그도 뗀다', () {
      expect(LifeRoutineOffer.clean('해보자 [REMIND]'), '해보자');
    });

    test('빈 줄이 늘어지지 않게 한다', () {
      expect(LifeRoutineOffer.clean('앞\n\n\n\n뒤'), '앞\n\n뒤');
    });

    test('태그만 오면 아무 말도 안 한 것으로 본다', () {
      expect(LifeRoutineOffer.clean('[HABIT: 청소]'), isNull);
    });

    test('빈 답도 마찬가지', () {
      expect(LifeRoutineOffer.clean('   '), isNull);
    });
  });
}
