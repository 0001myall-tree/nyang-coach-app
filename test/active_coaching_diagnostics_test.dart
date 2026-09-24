import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_diagnostics.dart';
import 'package:nyang_coach/services/active_coaching_plan.dart';
import 'package:nyang_coach/services/active_coaching_state.dart';
import 'package:nyang_coach/services/active_coaching_target.dart';

/// 안 뜨는 길이 여럿인데 화면에는 "아무 일도 안 일어남"만 남는다.
/// 고치는 자리가 전부 달라서, 여기서 값을 그대로 읽어 적는다.
void main() {
  final now = DateTime(2026, 9, 24, 11, 37);
  final today = ActiveCoachingStore.dateKey(now);

  String report({
    bool enabled = true,
    bool master = true,
    Set<int> onDays = const {1, 2, 3, 4, 5, 6, 7},
    ActiveCoachingBudget? budget,
    ActiveCoachingDay? day,
    ActiveCoachingPlan? plan,
    DateTime? plannedAt,
    Map<String, bool> blockers = const {},
  }) => ActiveCoachingDiagnostics.build(
    now: now,
    enabled: enabled,
    master: master,
    onDays: onDays,
    times: const ['오후 3:30'],
    budget: budget ?? ActiveCoachingBudget(date: today),
    day: day ?? ActiveCoachingDay(date: today),
    plan: plan,
    plannedAt: plannedAt,
    blockers: blockers,
  );

  test('꺼져 있으면 그것부터 짚는다', () {
    expect(report(enabled: false), contains('※ 꺼져 있어'));
  });

  test('오늘이 참견하는 요일이 아니면 짚는다', () {
    // 2026-09-24는 목요일.
    expect(report(onDays: const {1, 2, 3}), contains('※ 오늘은 참견하지 않는 요일'));
    expect(report(onDays: const {4}), isNot(contains('참견하지 않는 요일')));
  });

  test('쉬는 중이면 언제부터 다시 부르는지 적는다', () {
    // 제일 흔한 "왜 안 뜨지"의 답이다. 방금 한 번 나갔으면 두 시간은 쉰다.
    final budget = ActiveCoachingBudget(
      date: today,
    ).spoke(DateTime(2026, 9, 24, 10, 50));
    expect(report(budget: budget), contains('※ 쉬는 중 — 12:50부터'));
  });

  test('오늘 몫을 다 썼으면 그렇게 적는다', () {
    var budget = ActiveCoachingBudget(date: today);
    var at = DateTime(2026, 9, 24, 6);
    for (var i = 0; i < ActiveCoachingBudget.dailyCap; i++) {
      budget = budget.spoke(at);
      at = at.add(const Duration(minutes: 30));
    }
    expect(report(budget: budget), contains('※ 오늘 몫을 다 씀'));
  });

  test('추적 중인 일은 무엇이 쌓였는지 보여준다', () {
    final day = ActiveCoachingDay(date: today).put(
      'a',
      TaskTracking(
        promisedAt: DateTime(2026, 9, 24, 20),
        nudges: 2,
        reason: '머리가 안 돌아가',
      ),
    );
    final text = report(day: day);
    expect(text, contains('약속 20:00'));
    expect(text, contains('2번 말 검'));
    expect(text, contains('머리가 안 돌아가'));
  });

  test('걸어둔 시각이 이미 지났으면 짚는다', () {
    expect(
      report(plannedAt: DateTime(2026, 9, 24, 11)),
      contains('※ 이미 지난 시각'),
    );
  });

  test('지금 다시 계산한 결과를 함께 보여준다', () {
    final plan = ActiveCoachingPlan(
      at: DateTime(2026, 9, 24, 12, 50),
      signal: ActiveCoachingSignal.lateStart,
      taskText: '분기 리포트',
    );
    final text = report(plan: plan);
    expect(text, contains('12:50'));
    expect(text, contains('시작 시각 +30분'));
    expect(text, contains('분기 리포트'));
  });

  test('부를 자리가 없으면 없다고 적는다', () {
    expect(report(), contains('부를 자리 없음'));
  });

  test('막는 것은 권한마다 뜻이 반대다', () {
    // 오버레이는 꺼져 있을 때 막힌 것이고, 절전은 켜져 있을 때 막힌 것이다.
    final text = report(
      blockers: const {'overlay': false, 'batteryRestricted': true},
    );
    expect(text, contains('다른 앱 위에 표시 막힘'));
    expect(text, contains('배터리 절전 막힘'));
  });

  test('적극 코칭과 무관한 값은 적지 않는다', () {
    // 넘어오는 값에는 딴짓 방지 스위치도 섞여 있다. 그걸 적으면 그 기능을
    // 꺼둔 사람에게 적극 코칭이 막힌 것처럼 보인다.
    final text = report(blockers: const {'enabled': false, 'overlay': true});
    expect(text, isNot(contains('enabled')));
    expect(text, contains('다른 앱 위에 표시 괜찮음'));
  });
}
