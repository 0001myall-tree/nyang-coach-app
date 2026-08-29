import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_blocker_service.dart';
import 'package:nyang_coach/services/resistance_intervention_service.dart';

void main() {
  group('막는 것과 개입 잇기', () {
    test('고를 수 있는 답마다 짝지을 개입이 실제로 있다', () {
      // 이름을 바꾸다 짝을 잃으면 그 답을 고른 사람은 순번대로 아무거나 받는다.
      for (final label in ExecutionBlockerService.answers.keys) {
        final id = ExecutionBlockerService.interventionFor(label);
        expect(id, isNotNull, reason: '$label에 짝지은 개입이 없다');
        expect(
          ResistanceInterventionService.byId(id!),
          isNotNull,
          reason: '$label이 가리키는 $id가 개입 목록에 없다',
        );
      }
    });

    test('직접 적은 답에는 짝을 두지 않는다', () {
      // 무슨 말이 나올지 모르니 앱이 개입을 고를 수 없다. 코치가 읽고 판단한다.
      expect(
        ExecutionBlockerService.interventionFor(
          ExecutionBlockerService.otherLabel,
        ),
        isNull,
      );
    });
  });
}
