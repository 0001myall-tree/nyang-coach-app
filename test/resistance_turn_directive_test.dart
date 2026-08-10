import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/prompts/coach_prompt.dart';

/// 저항 턴 지시문이 개입 선택을 가로채지 않는지 지킨다.
///
/// 이 지시문들은 프롬프트 맨 끝에 붙는다. 방식까지 여기서 정하면 위에서 앱이
/// 고른 개입을 덮어쓰고, 모델은 마지막 말을 따른다. 실제로 그래서 두 번째
/// "귀찮아"부터 로테이션이 통째로 무시됐고 뒷번호 개입은 나올 일이 없었다.
void main() {
  const directives = {
    'turnCauseUnclear': Prompts.turnCauseUnclear,
    'turnCauseConfirmed': Prompts.turnCauseConfirmed,
    'turnSkipCauseQuestion': Prompts.turnSkipCauseQuestion,
    'resistanceFlowMaster': Prompts.resistanceFlowMaster,
  };

  test('방식은 개입 섹션에 넘긴다', () {
    directives.forEach((name, text) {
      expect(text, contains('[이번 턴에 쓸 개입]'), reason: name);
    });
  });

  test('지시문이 직접 방식을 정하지 않는다', () {
    // '가장 작은 첫 조각'은 범위 좁히기 개입이 할 말이다. 여기 적으면 앱이
    // 무엇을 골랐든 매번 그 하나로 수렴한다.
    directives.forEach((name, text) {
      expect(text, isNot(contains('가장 작은 첫 조각')), reason: name);
    });
  });

  test('원인 불명 턴이 카운트다운을 막지 않는다', () {
    // 로테이션이 '시작 신호 만들기'를 고른 턴에 이 지시가 같이 붙으면, 앱이
    // 고른 개입을 앱이 다시 금지하는 꼴이 된다. 코치가 먼저 띄우지 않게 막는
    // 일은 [실행 저항 원인 추론 흐름]과 개입 문구가 이미 맡고 있다.
    expect(Prompts.turnCauseUnclear, isNot(contains('카운트다운')));
    expect(Prompts.turnCauseUnclear, isNot(contains('COUNTDOWN_START')));
  });

  test('최소 행동 예시에 바라보기만 하는 것이 없다', () {
    // 보고 나도 일이 그대로인 행동은 압박만 주고 진행이 없다. 예시를 하나라도
    // 남기면 모델이 그 모양을 따라가서, 전에는 "고치고 싶은 부분을 1분 동안
    // 보기"까지 나왔다. 환기(창밖 보기)는 쉬는 행동이라 여기 해당하지 않는다.
    for (final text in [Prompts.thoughtOverload, Prompts.resultAnxietyLight]) {
      expect(text, isNot(contains('보기')));
      expect(text, isNot(contains('바라보')));
    }
  });

  test('원인을 다시 캐묻지 말라는 본래 역할은 남아 있다', () {
    expect(Prompts.turnCauseUnclear, contains('다시 하지 마세요'));
    expect(Prompts.turnCauseConfirmed, contains('다시 묻지 말고'));
    expect(Prompts.turnSkipCauseQuestion, contains('다시 묻지 말고'));
  });
}
