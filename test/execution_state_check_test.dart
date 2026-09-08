import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_state_check.dart';
import 'package:nyang_coach/services/resistance_intervention_service.dart';

/// 판정을 읽는 자리와 물어보는 문구까지가 여기 몫이다. 어느 쪽이 맞는 답인지는
/// 모델이 정하는 것이라 여기서 못 본다.
void main() {
  group('답에서 판정 읽기', () {
    test('BODY만 있으면 몸이 안 움직이는 쪽', () {
      expect(ExecutionStateCheck.readVerdict('BODY'), isTrue);
      expect(ExecutionStateCheck.readVerdict(' body '), isTrue);
    });

    test('TASK면 저항 쪽', () {
      expect(ExecutionStateCheck.readVerdict('TASK'), isFalse);
    });

    test('둘 다 없거나 둘 다 있으면 못 읽은 것으로 본다', () {
      expect(ExecutionStateCheck.readVerdict(''), isFalse);
      expect(ExecutionStateCheck.readVerdict('잘 모르겠습니다'), isFalse);
      expect(ExecutionStateCheck.readVerdict('BODY 또는 TASK'), isFalse);
    });
  });

  group('물어보는 문구', () {
    test('양쪽 다 쓰는 말로 정하지 말라고 일러둔다', () {
      // "하기 싫어"는 몸이 바닥일 때도, 그 일만 무거울 때도 나온다. 이 한 줄이
      // 빠지면 판별기가 그 말 하나로 결론을 내린다.
      final prompt = ExecutionStateCheck.promptFor(const ['하기 싫어']);
      expect(prompt.contains('양쪽 다 쓰는 말'), isTrue);
    });

    test('모르겠으면 저항으로 두라고 못박는다', () {
      final prompt = ExecutionStateCheck.promptFor(const ['청소해야 되는데']);
      expect(prompt.contains('판단이 서지 않으면 TASK'), isTrue);
    });

    test('넘긴 말이 그대로 실린다', () {
      final prompt = ExecutionStateCheck.promptFor(const [
        '너무 지쳤어',
        '청소해야 되는데',
      ]);
      expect(prompt.contains('너무 지쳤어'), isTrue);
      expect(prompt.contains('청소해야 되는데'), isTrue);
    });
  });

  group('가른 뒤 어디로 가는가', () {
    test('몸이 안 움직이는 쪽이 지목하는 개입이 실제로 있다', () {
      // 판별기가 BODY라고 해도 지목할 개입이 없으면 아무 일도 안 일어난다.
      expect(ResistanceInterventionService.byId('wake_body'), isNotNull);
    });

    test('몸 먼저 깨우기는 순번에 없어 지목으로만 나온다', () {
      final next = ResistanceInterventionService.nextIntervention(
        const [],
        isMaster: true,
      );
      expect(next?.id, isNot('wake_body'));
    });
  });
}
