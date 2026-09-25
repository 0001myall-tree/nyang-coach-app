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
      // 하루를 닫는 말은 예산 밖이라 따로 본다. 여기서는 이미 건넨 것으로 둔다.
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: now,
        day: emptyDay(),
        budget: _spentBudget(today).wrappedUp(DateTime(2026, 9, 23, 21)),
      );
      expect(plan, isNull);
    });

    test('밤으로 밀리면 걸지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 21),
        day: emptyDay(),
        budget: freshBudget()
            .spoke(DateTime(2026, 9, 23, 20, 30))
            .wrappedUp(DateTime(2026, 9, 23, 21)),
      );
      // 22시 반으로 밀리는데 그 시각은 조용한 시간이다.
      expect(plan, isNull);
    });

    test('자정 넘어 계산하면 첫 차례는 아침 6시로 밀린다', () {
      final lateNight = DateTime(2026, 9, 23, 0, 30);
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a'), task('b')],
        now: lateNight,
        day: ActiveCoachingDay(date: ActiveCoachingStore.dateKey(lateNight)),
        budget: ActiveCoachingBudget(
          date: ActiveCoachingStore.dateKey(lateNight),
        ),
      );
      expect(plan?.at, DateTime(2026, 9, 23, 6));
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

  group('하루를 닫는 말', () {
    test('취침 두 시간 전에 선다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 19),
        day: emptyDay(),
        // 오늘 몫을 다 써서 다른 자리는 잡히지 않는 상태.
        budget: _spentBudget(today),
        bedtime: '23:00',
      );
      expect(plan?.signal, ActiveCoachingSignal.nightWrap);
      expect(plan?.at, DateTime(2026, 9, 23, 21));
    });

    test('취침을 안 정해뒀으면 9시', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 19),
        day: emptyDay(),
        budget: _spentBudget(today),
      );
      expect(plan?.at, DateTime(2026, 9, 23, 21));
    });

    test('늦게 자는 사람도 9시 반을 넘기지 않는다', () {
      // 그 뒤로 미루면 "10분만 손대볼까"가 자라고 할 시간에 일을 시키는 말이 된다.
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 19),
        day: emptyDay(),
        budget: _spentBudget(today),
        bedtime: '01:00',
      );
      expect(plan?.at, DateTime(2026, 9, 23, 21, 30));
    });

    test('오늘 몫을 다 썼어도 나간다', () {
      // 하루 종일 조용했던 사람에게 오히려 더 필요하다.
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 20, 30),
        day: emptyDay(),
        budget: _spentBudget(today),
      );
      expect(plan?.signal, ActiveCoachingSignal.nightWrap);
    });

    test('이미 건넸으면 다시 걸지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 20, 30),
        day: emptyDay(),
        budget: _spentBudget(today).wrappedUp(DateTime(2026, 9, 23, 21)),
      );
      expect(plan, isNull);
    });

    test('한 시간 넘게 지났으면 오늘은 넘긴다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', elapsedSeconds: 600)],
        now: DateTime(2026, 9, 23, 22, 30),
        day: emptyDay(),
        budget: _spentBudget(today),
      );
      expect(plan, isNull);
    });

    test('남은 일이 없으면 부르지 않는다', () {
      final plan = ActiveCoachingPlanner.next(
        tasks: [task('a', done: true)],
        now: DateTime(2026, 9, 23, 20, 30),
        day: emptyDay(),
        budget: _spentBudget(today),
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

  group('여유 시간', () {
    final spokeAt10 = ActiveCoachingBudget(
      date: today,
      lastSpokeAt: DateTime(2026, 9, 23, 10),
      spokenToday: 1,
    );

    ActiveCoachingPlan? nextWithGap(DateTime gap) => ActiveCoachingPlanner.next(
      tasks: [task('a'), task('b')],
      now: DateTime(2026, 9, 23, 10, 5),
      day: emptyDay(),
      budget: spokeAt10,
      gapTimes: [gap],
    );

    test('직전에서 1시간만 지났으면 여유 시간에 들른다', () {
      expect(
        nextWithGap(DateTime(2026, 9, 23, 11, 30))?.at,
        DateTime(2026, 9, 23, 11, 30),
      );
    });

    test('1시간도 안 지난 여유 시간은 건너뛴다', () {
      expect(
        nextWithGap(DateTime(2026, 9, 23, 10, 30))?.at,
        DateTime(2026, 9, 23, 12),
      );
    });

    test('2시간이 된 뒤 곧 여유 시간이 오면 그때까지 기다린다', () {
      expect(
        nextWithGap(DateTime(2026, 9, 23, 12, 30))?.at,
        DateTime(2026, 9, 23, 12, 30),
      );
    });

    test('여유 시간이 멀면 기다리지 않는다', () {
      expect(
        nextWithGap(DateTime(2026, 9, 23, 15))?.at,
        DateTime(2026, 9, 23, 12),
      );
    });
  });

  group('하루치 차례', () {
    List<ActiveCoachingPlan> queueFor(
      List tasks, {
      ActiveCoachingDay? day,
      DateTime? at,
    }) => ActiveCoachingPlanner.queue(
      tasks: tasks,
      now: at ?? DateTime(2026, 9, 23, 10),
      day: day ?? emptyDay(),
      budget: freshBudget(),
    );

    test('앱을 안 열어도 하루 동안 여러 번 찾아간다', () {
      final plans = queueFor([task('a'), task('b')]);
      expect(plans.length, greaterThanOrEqualTo(4));
      for (var i = 1; i < plans.length; i++) {
        expect(plans[i].at.isAfter(plans[i - 1].at), isTrue);
      }
    });

    test('차례 사이는 예산의 간격을 지킨다', () {
      final plans = queueFor(
        [task('a'), task('b')],
      ).where((plan) => plan.signal != ActiveCoachingSignal.nightWrap).toList();
      for (var i = 1; i < plans.length; i++) {
        expect(
          plans[i].at.difference(plans[i - 1].at) >=
              ActiveCoachingBudget.interval,
          isTrue,
        );
      }
    });

    test('밤 10시 이후에는 하루를 닫는 말 말고는 없다', () {
      for (final plan in queueFor([task('a'), task('b')])) {
        if (plan.signal == ActiveCoachingSignal.nightWrap) continue;
        expect(plan.at.hour, lessThan(ActiveCoachingBudget.quietFromHour));
      }
    });

    test('남은 일이 하나뿐이어도 한 번으로 끝나지 않는다', () {
      // 바로 앞에서 다룬 일을 건너뛰는 규칙이, 다른 일이 없을 때도 돌면 그
      // 하나를 다시 부를 수가 없다.
      final plans = queueFor([task('영양제')]);
      expect(
        plans.where((plan) => plan.taskId == '영양제').length,
        greaterThanOrEqualTo(2),
      );
    });

    test('약속은 제 시각에 끼우고, 그 전 차례도 빠뜨리지 않는다', () {
      final day = emptyDay().put(
        'p',
        TaskTracking(promisedAt: DateTime(2026, 9, 23, 16)),
      );
      final plans = queueFor([task('p'), task('a')], day: day);
      expect(
        plans.any(
          (plan) =>
              plan.signal == ActiveCoachingSignal.promised &&
              plan.at == DateTime(2026, 9, 23, 16),
        ),
        isTrue,
      );
      // 10시에 "4시에 할게"가 있어도 그 사이가 통째로 비지 않는다.
      expect(plans.first.at.isBefore(DateTime(2026, 9, 23, 16)), isTrue);
    });

    test('할 일이 없으면 차례도 없다', () {
      expect(queueFor([task('a', done: true)]), isEmpty);
    });
  });
}

/// 오늘 몫을 다 쓴 예산. 밤 카드가 예산 밖이라는 것을 보려고 쓴다.
ActiveCoachingBudget _spentBudget(String today) {
  var budget = ActiveCoachingBudget(date: today);
  var at = DateTime(2026, 9, 23, 6);
  for (var i = 0; i < ActiveCoachingBudget.dailyCap; i++) {
    budget = budget.spoke(at);
    at = at.add(const Duration(minutes: 30));
  }
  return budget;
}
