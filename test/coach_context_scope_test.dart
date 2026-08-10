import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/coach_context_scope.dart';

CoachContextScope master(
  String current, {
  String? previous,
  bool timer = false,
}) {
  return CoachContextScopeService.resolve(
    isMaster: true,
    currentText: current,
    previousUserText: previous,
    timerAuthorization: timer,
  );
}

void main() {
  group('프렌즈 코치', () {
    test('목표는 다루지 않고 오늘 할 일만 본다', () {
      final scope = CoachContextScopeService.resolve(
        isMaster: false,
        currentText: '오늘 뭐부터 하지?',
      );
      expect(scope.goal, GoalContextScope.none);
      expect(scope.tasks, isTrue);
    });

    test('목표 얘기가 오가도 비전은 열리지 않는다', () {
      final scope = CoachContextScopeService.resolve(
        isMaster: false,
        currentText: '이번 달 목표 어때?',
        previousUserText: '장기 비전 좀 봐줘',
      );
      expect(scope.goal, GoalContextScope.none);
      expect(scope.allowsGoals, isFalse);
    });

    test('코치가 목표를 요청해도 열어주지 않는다', () {
      final scope = CoachContextScopeService.resolve(
        isMaster: false,
        currentText: '심심해',
      ).escalated(goals: true);
      expect(scope.goal, GoalContextScope.none);
    });
  });

  group('이번 말로 판단', () {
    test('목표를 직접 물으면 전부 싣는다', () {
      final scope = master('오늘 뭐부터 하지?');
      expect(scope.goal, GoalContextScope.full);
      expect(scope.tasks, isTrue);
    });

    test('잡담에는 아무것도 싣지 않는다', () {
      final scope = master('아 배고파');
      expect(scope.goal, GoalContextScope.none);
      expect(scope.tasks, isFalse);
    });

    test('할 일 얘기에는 목표 없이 할 일만 싣는다', () {
      final scope = master('설거지 끝냈어');
      expect(scope.goal, GoalContextScope.none);
      expect(scope.tasks, isTrue);
    });

    test('타이머 동의 응답에는 할 일을 싣는다', () {
      final scope = master('응', timer: true);
      expect(scope.tasks, isTrue);
    });
  });

  group('계획 짜달라는 말', () {
    // 고정 문자열로만 찾던 때는 "계획짜줘"만 걸리고 사이에 부사가 끼면 전부
    // 빠져나갔다. 실제 문장은 거의 부사가 낀 쪽이라 대부분을 놓쳤다.
    const asksForAPlan = [
      '계획짜줘',
      '계획 짜줘',
      '계획 좀 짜줘',
      '계획 다시 짜줘',
      '오늘 계획 좀 짜줘',
      '일정 좀 짜줘',
      '스케줄 좀 짜줘',
      '하루 계획 세워줘',
      '오늘 계획 어떻게 세울까',
      '계획 세우는 것 좀 도와줘',
      '내일 일정 좀 잡아줘',
    ];
    for (final text in asksForAPlan) {
      test('"$text"는 기록을 전부 싣는다', () {
        expect(master(text).goal, GoalContextScope.full);
      });
    }

    // 조회와 보고는 판단이 아니다. 여기까지 걸리면 흔한 말마다 기록이 다 실린다.
    const doesNotAsk = ['오늘 일정 뭐야', '일정 잡았어', '오늘 할 일 확인해줘'];
    for (final text in doesNotAsk) {
      test('"$text"는 목표를 싣지 않는다', () {
        expect(master(text).goal, GoalContextScope.none);
      });
    }
  });

  group('직전 말 상속', () {
    test('직전이 목표 얘기였으면 제목만 싣는다', () {
      final scope = master('아 배고파', previous: '오늘 뭐부터 하지?');
      expect(scope.goal, GoalContextScope.light);
    });

    test('상속된 목표 신호에는 귀찮음 규칙을 붙이지 않는다', () {
      final scope = master('아 배고파', previous: '오늘 뭐부터 하지?');
      expect(scope.avoidanceLink, isFalse);
    });

    test('두 턴 전 목표 얘기는 상속하지 않는다', () {
      // 직전 말만 본다. "뭐부터" → "아 배고파" → "점심 뭐 먹지"에서 마지막 턴.
      final scope = master('점심 뭐 먹지', previous: '아 배고파');
      expect(scope.goal, GoalContextScope.none);
    });

    test('이번 말이 목표면 상속과 무관하게 전부 싣는다', () {
      final scope = master('이번 달 목표 어때?', previous: '아 배고파');
      expect(scope.goal, GoalContextScope.full);
    });
  });

  group('귀찮음', () {
    test('귀찮다고 하면 목표 제목과 연결 규칙을 함께 싣는다', () {
      final scope = master('아 귀찮아');
      expect(scope.goal, GoalContextScope.light);
      expect(scope.avoidanceLink, isTrue);
      expect(scope.tasks, isTrue);
    });

    test('직전에 귀찮다고 했어도 연결 규칙은 유지된다', () {
      final scope = master('음...', previous: '하기 싫어');
      expect(scope.goal, GoalContextScope.light);
      expect(scope.avoidanceLink, isTrue);
    });
  });

  group('코치의 정보 요청', () {
    test('평범한 답변은 요청으로 읽지 않는다', () {
      final request = CoachContextRequest.parse(
        '오늘은 이것부터 해보죠. [CHIPS: 좋아|나중에]',
      );
      expect(request.isEmpty, isTrue);
    });

    test('목표 요청을 읽는다', () {
      final request = CoachContextRequest.parse('[NEED: goals]');
      expect(request.goals, isTrue);
      expect(request.tasks, isFalse);
    });

    test('둘을 한 줄에 요청해도 읽는다', () {
      final request = CoachContextRequest.parse('[NEED: goals, tasks]');
      expect(request.goals, isTrue);
      expect(request.tasks, isTrue);
    });

    test('대소문자와 단수형도 받아준다', () {
      final request = CoachContextRequest.parse('[need: Task]');
      expect(request.tasks, isTrue);
    });

    test('모르는 이름은 무시한다', () {
      final request = CoachContextRequest.parse('[NEED: weather]');
      expect(request.isEmpty, isTrue);
    });

    test('태그가 답변에 섞여 나오면 지운다', () {
      final stripped = CoachContextRequest.strip('알겠습니다. [NEED: goals]');
      expect(stripped, '알겠습니다.');
    });

    test('태그만 있던 답변은 빈 문자열이 된다', () {
      expect(CoachContextRequest.strip('[NEED: goals]'), isEmpty);
    });
  });

  group('범위 넓히기', () {
    test('목표를 넓히면 할 일도 함께 열린다', () {
      final scope = master('아 배고파').escalated(goals: true);
      expect(scope.goal, GoalContextScope.full);
      expect(scope.tasks, isTrue);
    });

    test('할 일만 넓히면 목표는 그대로 둔다', () {
      final scope = master('아 배고파').escalated(tasks: true);
      expect(scope.goal, GoalContextScope.none);
      expect(scope.tasks, isTrue);
    });

    test('이미 열린 범위를 좁히지 않는다', () {
      final scope = master('오늘 뭐부터 하지?').escalated(tasks: true);
      expect(scope.goal, GoalContextScope.full);
    });
  });
}
