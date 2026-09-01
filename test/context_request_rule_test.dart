import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/prompts/coach_prompt.dart';
import 'package:nyang_coach/services/coach_context_scope.dart';

String rule({bool goals = false, bool tasks = false, bool past = false}) =>
    Prompts.contextRequestRule(
      goalsMissing: goals,
      tasksMissing: tasks,
      pastDayMissing: past,
    );

void main() {
  group('요청 규칙을 붙이는 조건', () {
    test('빠진 게 없으면 아무것도 붙이지 않는다', () {
      // 다 실어놓고 "모자라면 말해"라고 하면, 있는 정보를 다시 달라는 턴이 생긴다.
      expect(rule(), isEmpty);
    });

    test('빠진 항목만 골라 알려준다', () {
      expect(rule(goals: true), contains('[NEED: goals]'));
      expect(rule(goals: true), isNot(contains('[NEED: tasks]')));
      expect(rule(tasks: true), contains('[NEED: tasks]'));
      expect(rule(tasks: true), isNot(contains('[NEED: goals]')));
    });

    test('둘 다 빠지면 둘 다 알려준다', () {
      final text = rule(goals: true, tasks: true);
      expect(text, contains('[NEED: goals]'));
      expect(text, contains('[NEED: tasks]'));
    });

    test('어제 목록은 따로 부를 수 있다', () {
      // 어제 목록은 앱이 미리 싣지 않으니 늘 빠져 있고, 늘 부를 수 있어야 한다.
      final text = rule(past: true);
      expect(text, contains('[NEED: past]'));
      expect(text, isNot(contains('[NEED: tasks]')));
    });
  });

  group('첫 판이 안 터진 이유를 막는 문구', () {
    final text = rule(goals: true, tasks: true);

    test('출력 규칙보다 우선한다고 밝힌다', () {
      // 앞의 지시 전부가 "따뜻하게 답하고 버튼을 붙여라"라고 말한다.
      // 우선순위를 못 박지 않으면 태그만 내보내라는 지시가 진다.
      expect(text, contains('우선'));
    });

    test('함께 붙이면 안 되는 태그를 이름으로 막는다', () {
      // [NO_CHIPS]는 목록에서 뺐다. 시키는 곳도 읽는 곳도 없어진 태그라
      // 여기서 막을 것이 없다.
      for (final tag in ['[CHIPS]', '[TASK]', '[TIMER_CONFIRM]']) {
        expect(text, contains(tag), reason: tag);
      }
    });

    test('망설여질 때 어느 쪽으로 기울지 정해준다', () {
      expect(text, contains('망설여지면 태그를 쓰세요'));
    });

    test('잡담에는 쓰지 말라는 제동이 남아 있다', () {
      expect(text, contains('잡담'));
    });
  });

  group('규칙과 파서가 같은 태그를 쓴다', () {
    test('규칙이 알려준 태그를 그대로 읽어낼 수 있다', () {
      // 문구와 파서가 따로 놀면 코치가 요청해도 앱이 못 알아듣는다.
      expect(CoachContextRequest.parse('[NEED: goals]').goals, isTrue);
      expect(CoachContextRequest.parse('[NEED: tasks]').tasks, isTrue);
      expect(CoachContextRequest.parse('[NEED: past]').pastDay, isTrue);
    });
  });
}
