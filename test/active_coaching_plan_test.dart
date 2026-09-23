import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_plan.dart';
import 'package:nyang_coach/services/active_coaching_state.dart';
import 'package:nyang_coach/services/active_coaching_target.dart';

/// 다음에 말을 걸 시각.
///
/// 두 폰 다 미리 걸어둬야 한다 — 안드로이드는 알람을 걸어야 앱이 꺼진 사이에도
/// 깨어나고, 아이폰은 예약할 때 문구까지 굳는다.
void main() {
  final now = DateTime(2026, 9, 23, 15, 0);
  final today = ActiveCoachingStore.dateKey(now);

  ActiveCoachingDay emptyDay() => ActiveCoachingDay(date: today);
  ActiveCoachingBudget freshBudget() => ActiveCoachingBudget(date: today);

  Map task(
    String id, {
    String? timeStart,
    bool done = false,
    bool inProgress = false,
    int elapsedSeconds = 0,
    String category = 'today',
  }) => {
    'id': id,
    'text': '할 일 $id',
    'done': done,
    if (inProgress) 'inProgress': true,
    if (timeStart != null) 'timeStart': timeStart,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    'category': category,
  };

  group('부를 자리 고르기', () {
    test('시작 시각 30분 뒤에 건다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', timeStart: '16:00')],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
      );
      expect(plan?.at, DateTime(2026, 9, 23, 16, 30));
      expect(plan?.signal, ActiveCoachingSignal.lateStart);
      expect(plan?.taskId, 'a');
    });

    test('약속 시각이 가장 먼저다', () {
      // 사용자가 직접 정한 시각이라 재촉이 아니라 약속이다.
      final day = emptyDay().put(
        'p',
        TaskTracking(promisedAt: DateTime(2026, 9, 23, 17)),
      );
      final plan = ActiveCoachingPlanner.next(
        tasks: [
          task('p'),
          task('a', timeStart: '17:30'),
        ],
        now: now,
        day: day,
        budget: freshBudget(),
      );
      expect(plan?.signal, ActiveCoachingSignal.promised);
      expect(plan?.at, DateTime(2026, 9, 23, 17));
      expect(plan?.isPromise, isTrue);
    });

    test('약속은 예산도 매인 시간대도 뚫는다', () {
      final day = emptyDay().put(
        'p',
        TaskTracking(promisedAt: DateTime(2026, 9, 23, 16)),
      );
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('p')],
        now: now,
        day: day,
        // 방금 말을 걸어 두 시간은 쉬어야 하는 상태다.
        budget: freshBudget().spoke(now),
        busyAt: (at) => true,
      );
      expect(plan?.at, DateTime(2026, 9, 23, 16));
    });

    test('멈춘 일은 예산이 허락하는 때로', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: now,
        day: emptyDay(),
        budget: freshBudget().spoke(DateTime(2026, 9, 23, 14)),
      );
      // 14시에 말했으니 두 시간 뒤인 16시부터.
      expect(plan?.at, DateTime(2026, 9, 23, 16));
      expect(plan?.signal, ActiveCoachingSignal.paused);
    });

    test('신호가 없으면 "지금 뭐 할 수 있어?"를 물을 자리로', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a'), task('b')],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
      );
      expect(plan?.signal, ActiveCoachingSignal.askUser);
      expect(plan?.at, now);
      expect(plan?.taskId, isNull);
    });
  });

  group('걸지 않는 때', () {
    test('참견하지 않는 요일이면 아무것도 안 건다', () {
      // 2026-09-23은 수요일.
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
        onDays: const {1, 2, 4, 5},
      );
      expect(plan, isNull);
    });

    test('오늘 몫을 다 썼으면 오늘은 더 안 건다', () {
      var budget = freshBudget();
      var at = DateTime(2026, 9, 23, 6);
      for (var i = 0; i < ActiveCoachingBudget.dailyCap; i++) {
        budget = budget.spoke(at);
        at = at.add(const Duration(minutes: 30));
      }
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: now,
        day: emptyDay(),
        budget: budget,
      );
      expect(plan, isNull);
    });

    test('밤으로 밀리면 걸지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 21),
        day: emptyDay(),
        budget: freshBudget().spoke(DateTime(2026, 9, 23, 20, 30)),
      );
      // 22시 반으로 밀리는데 그 시각은 조용한 시간이다.
      expect(plan, isNull);
    });

    test('붙잡고 있는 일이 있으면 걸지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', inProgress: true), task('b')],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
      );
      expect(plan, isNull);
    });

    test('결정이 난 일은 시작 시각이 지나도 안 부른다', () {
      final day = emptyDay().put(
        'a',
        const TaskTracking(decision: ActiveCoachingDecision.notToday),
      );
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', timeStart: '16:00')],
        now: now,
        day: day,
        budget: freshBudget(),
      );
      expect(plan, isNull);
    });
  });

  group('매인 시간대', () {
    test('건너뛰지 않고 끝난 뒤로 민다', () {
      // 그냥 건너뛰면 9시부터 6시까지 일하는 사람은 하루의 절반이 통째로 빈다.
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', timeStart: '16:00')],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
        busyAt: (at) => at.hour >= 16 && at.hour < 18,
        busyEndAfter: (at) => DateTime(at.year, at.month, at.day, 18),
      );
      expect(plan?.at, DateTime(2026, 9, 23, 18, 5));
    });

    test('언제 끝나는지 모르면 걸지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', timeStart: '16:00')],
        now: now,
        day: emptyDay(),
        budget: freshBudget(),
        busyAt: (at) => true,
      );
      expect(plan, isNull);
    });
  });

  test('바로 앞에서 다룬 일은 건너뛴다', () {
    final plan = ActiveCoachingPlanner.next(
      tasks: [
        task('a', timeStart: '16:00'),
        task('b', timeStart: '17:00'),
      ],
      now: now,
      day: emptyDay(),
      budget: ActiveCoachingBudget(date: today, lastTaskId: 'a'),
    );
    expect(plan?.taskId, 'b');
  });
}
