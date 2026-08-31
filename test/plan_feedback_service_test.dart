import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/plan_feedback_service.dart';

void main() {
  group('PlanFeedbackService pinpoint parser', () {
    test('keeps only the first message block when the model returns extras', () {
      final parsed = PlanFeedbackService.parsePinpointResponseForTest(
        '''
이유: 도서관 가기는 어느 도서관인지와 머무를 시간이 정해지지 않음
계획: 도서관 가기
말: 대표님, 도서관 가기 일정이 보이니 어느 도서관에서 몇 시에 몇 시간 머무를지 정하면 좋겠습니다. 심리학에 따르면 언제·어디서 할지 미리 정해두는 실행 의도가 실행률을 높입니다. 이미 생각해뒀으면 그대로 가면 된다

이유: 운동은 어떤 종목과 강도, 소요시간이 정해지지 않음
계획: 운동
말: 대표님, 운동 일정이 있네요. 어떤 운동을 언제 얼마나 할지 정해두면 시작하기 쉽습니다.
''',
        ['도서관 가기', '운동'],
      );

      expect(parsed?.task, '도서관 가기');
      expect(
        parsed?.line,
        '대표님, 도서관 가기 일정이 보이니 어느 도서관에서 몇 시에 몇 시간 머무를지 정하면 좋겠습니다. 심리학에 따르면 언제·어디서 할지 미리 정해두는 실행 의도가 실행률을 높입니다. 이미 생각해뒀으면 그대로 가면 된다',
      );
    });

    test('ignores invented task names', () {
      final parsed = PlanFeedbackService.parsePinpointResponseForTest(
        '''
이유: 막막함
계획: 지어낸 일
말: 이 말은 쓰면 안 됩니다.
''',
        ['도서관 가기'],
      );

      expect(parsed, isNull);
    });
  });
}
