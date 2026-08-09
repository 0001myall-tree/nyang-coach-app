import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_resistance_service.dart';
import 'package:nyang_coach/services/focus_fatigue_service.dart';

void main() {
  test('집중력 저하 표현 판정', () {
    for (final t in [
      '집중이 안 돼',
      '집중이 너무 안 된다',
      '글 쓰는데 집중이 너무 안 된다',
      '머리에 안 들어와',
      '자꾸 딴짓하게 돼',
      '글이 안 써져',
      '집중력이 떨어졌어',
      '자꾸 멍때리고 있어',
      '오늘따라 산만해',
    ]) {
      expect(
        FocusFatigueService.isFocusFatigueExpression(t),
        isTrue,
        reason: t,
      );
    }
  });

  test('아직 시작 못 한 표현은 집중력 저하로 보지 않는다', () {
    // 이 말들은 실행 저항 쪽이라 여기서 걸리면 시작조차 못 한 사람에게
    // 환기를 권하게 된다.
    for (final t in ['손이 안 가', '엄두가 안 나', '시작을 못 하겠어', '하기 싫어', '귀찮아']) {
      expect(
        FocusFatigueService.isFocusFatigueExpression(t),
        isFalse,
        reason: t,
      );
    }
  });

  test('두 상태의 신호는 서로 겹치지 않는다', () {
    const focusOnly = ['집중이 안 돼', '머리에 안 들어와', '글이 안 써져', '자꾸 딴짓하게 돼'];
    for (final t in focusOnly) {
      expect(
        ExecutionResistanceService.isResistanceExpression(t),
        isFalse,
        reason: '$t 는 실행 저항이 아니어야 한다',
      );
    }
    const resistanceOnly = ['하기 싫어', '귀찮아', '손이 안 가', '엄두가 안 나'];
    for (final t in resistanceOnly) {
      expect(
        FocusFatigueService.isFocusFatigueExpression(t),
        isFalse,
        reason: '$t 는 집중력 저하가 아니어야 한다',
      );
    }
  });

  test('오래 작업했다는 답 판정', () {
    for (final t in [
      '아까부터 계속 쓰고 있었어',
      '세 시간째 붙잡고 있어',
      '아침부터 계속했어',
      '두 시간 동안 하고 있었어',
      '하루종일 했지',
    ]) {
      expect(FocusFatigueService.saysWorkedLong(t), isTrue, reason: t);
    }
    for (final t in ['방금 앉았어', '아직 시작도 못 했어', '몰라']) {
      expect(FocusFatigueService.saysWorkedLong(t), isFalse, reason: t);
    }
  });

  test('아직 시작 못 했다는 답 판정', () {
    for (final t in [
      '아직 시작도 못 했어',
      '한 글자도 못 썼어',
      '손도 안 댔어',
      '이제 하려고',
      '아직 아무것도 안 했어',
    ]) {
      expect(FocusFatigueService.saysNotStartedYet(t), isTrue, reason: t);
    }
    for (final t in ['아까부터 계속 쓰고 있었어', '두 시간쯤 했어']) {
      expect(FocusFatigueService.saysNotStartedYet(t), isFalse, reason: t);
    }
  });

  test('되묻기 답으로 볼 수 있는 턴만 후속으로 친다', () {
    for (final t in ['두 시간쯤', '아까부터 계속', '몰라', '아직 시작도 못 했어']) {
      expect(
        FocusFatigueService.looksLikeWorkHistoryAnswer(t),
        isTrue,
        reason: t,
      );
    }
    // 화제를 바꾼 긴 문장은 후속 턴이 아니다.
    expect(
      FocusFatigueService.looksLikeWorkHistoryAnswer(
        '아 참 내일 병원 예약 잡아야 하는데 그것 좀 할 일에 넣어줘',
      ),
      isFalse,
    );
  });
}
