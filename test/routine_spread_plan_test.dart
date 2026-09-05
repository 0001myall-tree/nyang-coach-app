import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/routine_spread_plan.dart';

/// 매일 루틴을 요일로 나눌 때 쓰는 값들.
void main() {
  test('기본 요일은 화·목이다', () {
    expect(RoutineSpreadPlan.defaultDays, [1, 3]);
    expect(RoutineSpreadPlan.label(RoutineSpreadPlan.defaultDays), '화·목');
  });

  test('기본 요일은 매일도 아니고 빈 것도 아니다', () {
    // 이레를 다 고르면 나눈 것이 아니고, 하나도 없으면 오늘 탭에서 사라진다.
    expect(RoutineSpreadPlan.defaultDays, isNotEmpty);
    expect(RoutineSpreadPlan.defaultDays.length, lessThan(7));
  });

  test('요일을 사람이 읽는 말로 적는다', () {
    expect(RoutineSpreadPlan.label([0, 2, 4]), '월·수·금');
    expect(RoutineSpreadPlan.label([6]), '일');
  });

  test('배정은 이름과 요일을 함께 든다', () {
    const assignment = RoutineDayAssignment(name: '운동', days: [0, 2, 4]);
    expect(assignment.name, '운동');
    expect(assignment.dayLabel, '월·수·금');
  });
}
