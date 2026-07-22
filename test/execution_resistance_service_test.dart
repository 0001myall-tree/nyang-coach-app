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

  test('완료 보고와 부정 표현은 저항으로 보지 않는다', () {
    for (final t in [
      '미루던 보고서 드디어 다 했어요',
      '귀찮은 일 다 끝냈어요',
      '하기 싫었는데 결국 했어요',
      '오늘은 하나도 안 귀찮아',
      '이번엔 미루지 않았어요',
      '미뤄뒀던 청소 완료',
    ]) {
      expect(ExecutionResistanceService.isResistanceExpression(t), isFalse, reason: t);
    }
  });

  test('완료 뒤에 나온 저항은 지금의 저항으로 본다', () {
    for (final t in [
      '오늘 할 일 다 했는데 운동은 하기 싫어',
      '청소 끝냈는데 설거지가 귀찮아',
      '보고서는 마쳤어요. 근데 발표 준비는 자꾸 미루게 돼요',
    ]) {
      expect(ExecutionResistanceService.isResistanceExpression(t), isTrue, reason: t);
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
