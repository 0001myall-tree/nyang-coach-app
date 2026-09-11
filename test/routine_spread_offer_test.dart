import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_spread_offer.dart';

/// 코치가 짜온 요일 배정을 읽는 자리.
///
/// 여기서 반드시 막아야 하는 것이 하나 있다. 요일이 하나도 없는 배정이다.
/// 그렇게 저장되면 그 루틴은 루틴 탭에는 그대로 보이는데 오늘 탭에는 영영
/// 올라오지 않는다. 사용자에게는 지워진 것과 구별되지 않는다.
void main() {
  group('코치가 짜온 안을 읽을 때', () {
    test('이름과 요일을 갈라낸다', () {
      final proposal = RoutineSpreadOffer.parse(
        '영양제는 매일 두자냥. 운동이랑 독서는 나눠보자냥.\n'
        '[SPREAD: 아침 운동|월수금; 독서|화목]',
      );

      expect(proposal, isNotNull);
      expect(proposal!.assignments.length, 2);
      expect(proposal.assignments.first.name, '아침 운동');
      expect(proposal.assignments.first.days, [0, 2, 4]);
      expect(proposal.assignments.last.name, '독서');
      expect(proposal.assignments.last.days, [1, 3]);
    });

    test('태그는 말에서 떼어낸다', () {
      final proposal = RoutineSpreadOffer.parse(
        '운동은 나눠보자냥. [SPREAD: 운동|화목]',
      );

      expect(proposal!.message, '운동은 나눠보자냥.');
    });

    test('적힌 순서와 상관없이 요일 순으로 돌려준다', () {
      final proposal = RoutineSpreadOffer.parse('나누자. [SPREAD: 운동|금월수]');

      expect(proposal!.assignments.first.days, [0, 2, 4]);
    });

    test('요일이 없으면 그 루틴은 버린다', () {
      final proposal = RoutineSpreadOffer.parse(
        '나누자. [SPREAD: 운동|; 독서|화목]',
      );

      expect(proposal!.assignments.length, 1);
      expect(proposal.assignments.first.name, '독서');
    });

    test('요일이 하나도 안 읽히면 그 루틴은 버린다', () {
      final proposal = RoutineSpreadOffer.parse(
        '나누자. [SPREAD: 운동|아무때나; 독서|화목]',
      );

      expect(proposal!.assignments.map((a) => a.name), ['독서']);
    });

    test('이레 내내는 나눈 것이 아니라 버린다', () {
      final proposal = RoutineSpreadOffer.parse(
        '나누자. [SPREAD: 운동|월화수목금토일; 독서|화목]',
      );

      expect(proposal!.assignments.map((a) => a.name), ['독서']);
    });

    test('한 번에 두 개까지만 받는다', () {
      final proposal = RoutineSpreadOffer.parse(
        '나누자. [SPREAD: 가|월; 나|화; 다|수; 라|목; 마|금]',
      );

      expect(proposal!.assignments.length, RoutineSpreadOffer.maxAssignments);
      expect(proposal.assignments.map((a) => a.name), ['가', '나']);
    });

    test('같은 루틴이 두 번 나오면 한 번만 센다', () {
      final proposal = RoutineSpreadOffer.parse(
        '나누자. [SPREAD: 운동|월수금; 운동|화목]',
      );

      expect(proposal!.assignments.length, 1);
      expect(proposal.assignments.first.days, [0, 2, 4]);
    });

    test('태그가 없으면 나눌 것이 없다는 답이다', () {
      final proposal = RoutineSpreadOffer.parse('다 매일 해야 하는 것들이구나냥.');

      expect(proposal, isNotNull);
      expect(proposal!.assignments, isEmpty);
      expect(proposal.message, '다 매일 해야 하는 것들이구나냥.');
    });

    test('쓸 만한 배정이 하나도 없어도 답은 답이다', () {
      final proposal = RoutineSpreadOffer.parse('나누자. [SPREAD: 운동|]');

      expect(proposal, isNotNull);
      expect(proposal!.assignments, isEmpty);
    });

    test('태그만 있고 할 말이 없으면 제안이 아니다', () {
      expect(RoutineSpreadOffer.parse('[SPREAD: 운동|화목]'), isNull);
    });
  });
}
