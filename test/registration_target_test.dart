import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/registration_target.dart';

void main() {
  group('이름이 이 문장에 없는 경우', () {
    test('넣을 자리만 말한다', () {
      for (final input in [
        '할일에',
        '할 일에',
        '오늘 할일에',
        '할일 목록에',
        '일정에',
        '캘린더에',
        '루틴으로',
        '습관에',
        '투두에',
        '스케줄에다가',
      ]) {
        expect(
          RegistrationTarget.nameIsElsewhere(input),
          isTrue,
          reason: input,
        );
      }
    });

    test('앞 턴을 가리킨다', () {
      for (final input in ['이거', '그거를', '방금 거', '아까 거', '이걸']) {
        expect(
          RegistrationTarget.nameIsElsewhere(input),
          isTrue,
          reason: input,
        );
      }
    });

    test('앞머리만 남았다', () {
      expect(RegistrationTarget.nameIsElsewhere('나 할일에'), isTrue);
      expect(RegistrationTarget.nameIsElsewhere('그럼 이거'), isTrue);
      expect(RegistrationTarget.nameIsElsewhere('   '), isTrue);
    });
  });

  group('이름이 문장 안에 있는 경우', () {
    test('이름만 있다', () {
      for (final input in ['스트레칭', '집필', '팀 회의', '아침 운동']) {
        expect(
          RegistrationTarget.nameIsElsewhere(input),
          isFalse,
          reason: input,
        );
      }
    });

    test('자리와 이름을 함께 말한다', () {
      for (final input in [
        '할일에 스트레칭',
        '오늘 할일에 집필',
        '내일 3시 회의',
        '루틴으로 물 마시기',
      ]) {
        expect(
          RegistrationTarget.nameIsElsewhere(input),
          isFalse,
          reason: input,
        );
      }
    });

    test('자리를 가리키는 말로 시작하는 이름은 지키다', () {
      // '일정 관리'라는 이름의 일정을 넣을 수도 있다.
      expect(RegistrationTarget.nameIsElsewhere('일정 관리 공부'), isFalse);
      expect(RegistrationTarget.nameIsElsewhere('할일 정리하기'), isFalse);
    });
  });
}
