import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/planner_action.dart';

void main() {
  group('무엇을 가리키는지', () {
    test('옮기기', () {
      final a = PlannerAction.parse('그래 열어줄게 [MOVE: 집필]')!;
      expect(a.kind, PlannerActionKind.move);
      expect(a.target, '집필');
      expect(a.isUsable, isTrue);
    });

    test('완료', () {
      final a = PlannerAction.parse('잘했다냥 [DONE: 운동]')!;
      expect(a.kind, PlannerActionKind.done);
      expect(a.target, '운동');
    });

    test('알람', () {
      final a = PlannerAction.parse('[REMIND: 집필]')!;
      expect(a.kind, PlannerActionKind.remind);
      expect(a.target, '집필');
    });

    test('이름에 띄어쓰기가 있어도 그대로 읽는다', () {
      expect(PlannerAction.parse('[MOVE: 팀 회의]')!.target, '팀 회의');
    });
  });

  group('모닝콜', () {
    test('이름 없이 온다', () {
      final a = PlannerAction.parse('[MORNING]')!;
      expect(a.kind, PlannerActionKind.morning);
      expect(a.target, isEmpty);
      expect(a.isUsable, isTrue);
    });

    test('뒤에 뭐가 붙어 와도 받는다', () {
      // 예전 형식으로 시각을 적어 보내도 데려가는 데는 지장이 없다.
      expect(PlannerAction.parse('[MORNING: 09:00]')!.isUsable, isTrue);
    });
  });

  group('이름 없는 알람', () {
    test('일정 알람 자체를 가리킨다', () {
      // "일정 알람 켜줘"에는 가리킬 일정이 없다. 설정 시트로 데려간다.
      final a = PlannerAction.parse('[REMIND]')!;
      expect(a.kind, PlannerActionKind.remind);
      expect(a.target, isEmpty);
      expect(a.isUsable, isTrue);
    });
  });

  group('쓸 수 없는 것', () {
    test('이름이 비었다', () {
      expect(PlannerAction.parse('[MOVE: ]')!.isUsable, isFalse);
      expect(PlannerAction.parse('[DONE]')!.isUsable, isFalse);
    });

    test('태그가 없다', () {
      expect(PlannerAction.parse('오늘 뭐 할까냥?'), isNull);
    });

    test('여러 개가 오면 첫 번째만', () {
      final a = PlannerAction.parse('[DONE: 운동] [MOVE: 집필]')!;
      expect(a.kind, PlannerActionKind.done);
      expect(a.target, '운동');
    });
  });

  group('태그 떼기', () {
    test('본문만 남는다', () {
      expect(PlannerAction.strip('그래 열어줄게 [MOVE: 집필]'), '그래 열어줄게');
    });

    test('여러 개도 다 뗀다', () {
      expect(PlannerAction.strip('[DONE: 운동][MORNING]'), isEmpty);
    });
  });
}
