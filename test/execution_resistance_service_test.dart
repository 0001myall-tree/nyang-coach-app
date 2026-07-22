import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_resistance_service.dart';

void main() {
  test('실행 저항 표현 판정', () {
    for (final t in ['하기 싫어', '귀찮아', '미루고 있어', '못 하겠어요', '손이 안 가네요', '엄두가 안 나요']) {
      expect(ExecutionResistanceService.isResistanceExpression(t), isTrue, reason: t);
    }
    for (final t in ['오늘 뭐부터 할까', '자기 싫어', '잠이 안 와', '발표 끝냈어', '우울해']) {
      expect(ExecutionResistanceService.isResistanceExpression(t), isFalse, reason: t);
    }
  });

  test('원인 불명확 답변 판정', () {
    for (final t in ['생각이 너무 많아요.', '나도 잘 모르겠어요.', '그냥 귀찮아요.', '다 하기 싫어요.', '이유를 모르겠어요.', '그냥요']) {
      expect(ExecutionResistanceService.isVagueCauseAnswer(t), isTrue, reason: t);
    }
    for (final t in ['자료 찾는 게 너무 오래 걸려서요', '분량이 너무 많아서 부담돼요', '어디부터 손대야 할지 순서가 안 잡혀요', '피드백 받는 게 무서워요']) {
      expect(ExecutionResistanceService.isVagueCauseAnswer(t), isFalse, reason: t);
    }
  });
}
