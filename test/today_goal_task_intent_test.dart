import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/today_goal_task_intent.dart';

void main() {
  group('오늘 목표 표현', () {
    test('당일 표현과 구체적인 분량은 오늘 할 일이다', () {
      expect(TodayGoalTaskIntent.parse('오늘 목표는 1000자 쓰기')?.title, '1000자 쓰기');
      expect(
        TodayGoalTaskIntent.parse('오늘은 책 30페이지가 목표야')?.title,
        '책 30페이지 읽기',
      );
      expect(TodayGoalTaskIntent.parse('오늘 공부 목표는 강의 2개야')?.title, '강의 2개 듣기');
      expect(
        TodayGoalTaskIntent.parse('오늘도 어제처럼 1000자 쓸 거야')?.title,
        '1000자 쓰기',
      );
      expect(TodayGoalTaskIntent.parse('오늘 1000자가 목표야')?.title, '1000자 쓰기');
    });

    test('이전 문장의 분량을 오늘 목표로 받는다', () {
      expect(
        TodayGoalTaskIntent.parse(
          '내가 어제 1000자 정도를 썼어. 오늘도 그걸 목표로 하려고 해.',
        )?.title,
        '1000자 쓰기',
      );
    });

    test('장기 목표와 목표 탭 요청은 오늘 할 일이 아니다', () {
      expect(TodayGoalTaskIntent.parse('올해 목표는 소설 한 편 완결하기'), isNull);
      expect(TodayGoalTaskIntent.parse('내 목표 보여줘'), isNull);
      expect(TodayGoalTaskIntent.parse('목표 수정할래'), isNull);
      expect(TodayGoalTaskIntent.parse('목표 화면으로 가줘'), isNull);
      expect(TodayGoalTaskIntent.parse('오늘 목표 화면으로 가줘'), isNull);
    });
  });
}
