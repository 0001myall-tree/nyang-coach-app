import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/routine_spread_apply.dart';
import 'package:nyang_coach/services/routine_spread_budget.dart';
import 'package:nyang_coach/services/routine_spread_plan.dart';

/// 요일로 나누자는 제안을 얼마나 자주 꺼낼지, 그리고 받아들였을 때 무엇이
/// 저장되는지.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 9, 4, 19);

  group('언제 다시 물을 수 있는지', () {
    test('한 번도 안 물었으면 물어도 된다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      expect(await RoutineSpreadBudget.canAsk(prefs, now), isTrue);
    });

    test('거절한 지 한 달이 안 됐으면 안 묻는다', () async {
      SharedPreferences.setMockInitialValues({
        RoutineSpreadBudget.lastDeclinedKey: DateTime(
          2026,
          8,
          20,
        ).toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await RoutineSpreadBudget.canAsk(prefs, now), isFalse);
    });

    test('거절하고 한 달이 지나면 다시 묻는다', () async {
      SharedPreferences.setMockInitialValues({
        RoutineSpreadBudget.lastDeclinedKey: DateTime(
          2026,
          7,
          20,
        ).toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await RoutineSpreadBudget.canAsk(prefs, now), isTrue);
    });

    test('받아들인 뒤에도 두 주는 쉰다', () async {
      SharedPreferences.setMockInitialValues({
        RoutineSpreadBudget.lastAskedKey: DateTime(
          2026,
          8,
          28,
        ).toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await RoutineSpreadBudget.canAsk(prefs, now), isFalse);
    });

    test('코치가 달라도 같은 예산을 쓴다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await RoutineSpreadBudget.markAsked(prefs, now);
      // 코치 id를 받는 자리가 없다. 누가 물었든 한 번이다.
      expect(await RoutineSpreadBudget.canAsk(prefs, now), isFalse);
    });
  });

  group('요일을 실제로 적을 때', () {
    Future<List<dynamic>> savedHabits() async {
      final prefs = await SharedPreferences.getInstance();
      return jsonDecode(prefs.getString('nyang_habits') ?? '[]') as List;
    }

    test('매일에서 요일 지정으로 바뀐다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_habits': jsonEncode([
          {'id': '1', 'name': '운동', 'freq': 'daily'},
          {'id': '2', 'name': '영양제', 'freq': 'daily'},
        ]),
      });

      final applied = await RoutineSpreadApply.apply(
        const [RoutineDayAssignment(name: '운동', days: [0, 2, 4])],
      );

      expect(applied, ['운동']);
      final habits = await savedHabits();
      expect(habits[0]['freq'], 'weekly');
      expect(habits[0]['days'], [0, 2, 4]);
      // 짚지 않은 루틴은 그대로 매일이다.
      expect(habits[1]['freq'], 'daily');
    });

    test('없는 이름은 건너뛴다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_habits': jsonEncode([
          {'id': '1', 'name': '운동', 'freq': 'daily'},
        ]),
      });

      final applied = await RoutineSpreadApply.apply(
        const [RoutineDayAssignment(name: '있지도 않은 루틴', days: [0, 2])],
      );

      expect(applied, isEmpty);
      final habits = await savedHabits();
      expect(habits[0]['freq'], 'daily');
    });

    test('띄어쓰기가 달라도 찾는다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_habits': jsonEncode([
          {'id': '1', 'name': 'SNS 글쓰기', 'freq': 'daily'},
        ]),
      });

      final applied = await RoutineSpreadApply.apply(
        const [RoutineDayAssignment(name: 'SNS글쓰기', days: [1, 3])],
      );

      expect(applied, ['SNS글쓰기']);
      final habits = await savedHabits();
      expect(habits[0]['days'], [1, 3]);
    });

    test('주 n회로 쓰던 값은 지운다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_habits': jsonEncode([
          {
            'id': '1',
            'name': '운동',
            'freq': 'weekly_count',
            'weeklyTargetCount': 3,
          },
        ]),
      });

      await RoutineSpreadApply.apply(const [
        RoutineDayAssignment(name: '운동', days: [0, 2, 4]),
      ]);

      final habits = await savedHabits();
      expect(habits[0]['freq'], 'weekly');
      expect(habits[0].containsKey('weeklyTargetCount'), isFalse);
    });

    test('요일이 빈 배정은 적용하지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        'nyang_habits': jsonEncode([
          {'id': '1', 'name': '운동', 'freq': 'daily'},
        ]),
      });

      // 이대로 저장되면 그 루틴은 오늘 탭에서 영영 사라진다.
      final applied = await RoutineSpreadApply.apply(
        const [RoutineDayAssignment(name: '운동', days: [])],
      );

      expect(applied, isEmpty);
      final habits = await savedHabits();
      expect(habits[0]['freq'], 'daily');
    });

    test('읽을 수 없는 루틴 목록이면 아무것도 안 한다', () async {
      SharedPreferences.setMockInitialValues({'nyang_habits': '{망가진'});
      final applied = await RoutineSpreadApply.apply(
        const [RoutineDayAssignment(name: '운동', days: [0, 2])],
      );
      expect(applied, isEmpty);
    });
  });
}
