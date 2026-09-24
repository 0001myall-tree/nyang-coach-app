import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_chat.dart';

void main() {
  group('ActiveCoachingChat.read', () {
    test('고를 거리를 떼어 버튼으로, 나머지는 말로', () {
      final reply = ActiveCoachingChat.read(
        '영양제는 꺼내두기만 해도 반은 한 거야.\n[CHIPS: 식탁에 꺼내두기|물 한 컵 따르기|기타]',
      );
      expect(reply!.text, '영양제는 꺼내두기만 해도 반은 한 거야.');
      expect(reply.chips, ['식탁에 꺼내두기', '물 한 컵 따르기', '기타']);
    });

    test('이 창에서 할 수 없는 태그는 말에서 지운다', () {
      final reply = ActiveCoachingChat.read('5분만 붙잡아볼까? [TIMER_CONFIRM] [TASK: 책 읽기]');
      expect(reply!.text, '5분만 붙잡아볼까?');
      expect(reply.chips, isEmpty);
    });

    test('태그만 왔으면 쓸 말이 없다', () {
      expect(ActiveCoachingChat.read('[COUNTDOWN_START]'), isNull);
    });
  });
}
