import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/planner_action.dart';

void main() {
  group('옮기기', () {
    test('시각만 말한다', () {
      final a = PlannerAction.parse('그래 옮겨줄게 [MOVE: 집필|20:00]')!;
      expect(a.kind, PlannerActionKind.move);
      expect(a.target, '집필');
      expect(a.time?.hour, 20);
      expect(a.time?.minute, 0);
      expect(a.date, isNull);
      expect(a.isUsable, isTrue);
    });

    test('날짜만 말한다', () {
      final a = PlannerAction.parse('[MOVE: 집필|2026-08-22]')!;
      expect(a.date, DateTime(2026, 8, 22));
      expect(a.time, isNull);
      expect(a.isUsable, isTrue);
    });

    test('날짜와 시각을 함께 말한다', () {
      final a = PlannerAction.parse('[MOVE: 팀 회의|2026-08-22 09:30]')!;
      expect(a.target, '팀 회의');
      expect(a.date, DateTime(2026, 8, 22));
      expect(a.time?.hour, 9);
      expect(a.time?.minute, 30);
    });

    test('값이 없으면 쓸 수 없다', () {
      expect(PlannerAction.parse('[MOVE: 집필]')!.isUsable, isFalse);
      expect(PlannerAction.parse('[MOVE: |20:00]')!.isUsable, isFalse);
    });
  });

  group('완료', () {
    test('오늘 것', () {
      final a = PlannerAction.parse('잘했다냥 [DONE: 운동]')!;
      expect(a.kind, PlannerActionKind.done);
      expect(a.target, '운동');
      expect(a.date, isNull);
      expect(a.isUsable, isTrue);
    });

    test('지난 날 것', () {
      final a = PlannerAction.parse('[DONE: 청소|2026-08-20]')!;
      expect(a.date, DateTime(2026, 8, 20));
    });
  });

  group('알람', () {
    test('켜기와 끄기', () {
      expect(PlannerAction.parse('[REMIND: 집필|on]')!.enabled, isTrue);
      expect(PlannerAction.parse('[REMIND: 집필|off]')!.enabled, isFalse);
    });

    test('켜는지 끄는지 없으면 쓸 수 없다', () {
      expect(PlannerAction.parse('[REMIND: 집필]')!.isUsable, isFalse);
    });
  });

  group('모닝콜', () {
    test('시각을 정한다', () {
      final a = PlannerAction.parse('[MORNING: 07:30]')!;
      expect(a.kind, PlannerActionKind.morning);
      expect(a.target, isEmpty);
      expect(a.time?.hour, 7);
      expect(a.time?.minute, 30);
      expect(a.isUsable, isTrue);
    });

    test('끈다', () {
      final a = PlannerAction.parse('[MORNING: off]')!;
      expect(a.enabled, isFalse);
      expect(a.isUsable, isTrue);
    });
  });

  group('읽지 않는 것', () {
    test('태그가 없다', () {
      expect(PlannerAction.parse('오늘 뭐 할까냥?'), isNull);
    });

    test('없는 날짜와 시각', () {
      expect(PlannerAction.parse('[MOVE: 집필|2026-02-30]')!.date, isNull);
      expect(PlannerAction.parse('[MOVE: 집필|25:00]')!.time, isNull);
      expect(PlannerAction.parse('[MOVE: 집필|20:99]')!.time, isNull);
    });

    test('여러 개가 오면 첫 번째만', () {
      final a = PlannerAction.parse('[DONE: 운동] [MOVE: 집필|20:00]')!;
      expect(a.kind, PlannerActionKind.done);
      expect(a.target, '운동');
    });
  });

  group('태그 떼기', () {
    test('본문만 남는다', () {
      expect(
        PlannerAction.strip('그래 옮겨줄게 [MOVE: 집필|20:00]'),
        '그래 옮겨줄게',
      );
    });

    test('여러 개도 다 뗀다', () {
      expect(PlannerAction.strip('[DONE: 운동][MORNING: 07:00]'), isEmpty);
    });
  });
}
