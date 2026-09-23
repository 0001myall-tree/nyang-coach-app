import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 적극 코칭이 따라붙으려면 무엇을 했고 사용자가 뭐라고 했는지가 남아야 한다.
void main() {
  final now = DateTime(2026, 9, 23, 15, 0);
  final today = ActiveCoachingStore.dateKey(now);

  group('할 일별 추적', () {
    test('약속 시각과 이유가 그대로 돌아온다', () {
      final day = ActiveCoachingDay(date: today).put(
        'a',
        TaskTracking(
          promisedAt: DateTime(2026, 9, 23, 20),
          originalStart: '15:00',
          reason: '머리가 안 돌아가',
          nudges: 2,
        ),
      );
      final back = ActiveCoachingDay.fromJson(day.toJson(), today: today);
      expect(back.of('a').promisedAt, DateTime(2026, 9, 23, 20));
      expect(back.of('a').originalStart, '15:00');
      expect(back.of('a').reason, '머리가 안 돌아가');
      expect(back.of('a').nudges, 2);
    });

    test('자정을 넘기면 들고 가지 않는다', () {
      // 추적은 그날 안에서만 한다. 밤 정리 개입이 그 전에 하루를 닫는다.
      final yesterday = ActiveCoachingDay(
        date: '2026-09-22',
      ).put('a', TaskTracking(promisedAt: DateTime(2026, 9, 22, 20)));
      final back = ActiveCoachingDay.fromJson(yesterday.toJson(), today: today);
      expect(back.tasks, isEmpty);
    });

    test('결정이 난 일은 약속에서 빠지고 settled로 간다', () {
      // 사용자가 "오늘은 안 하기로" 했는데 약속 시각이 남아 있으면, 그 시각에
      // 앱이 그 결정을 못 들은 것처럼 다시 부른다.
      final day = ActiveCoachingDay(date: today)
          .put(
            'a',
            TaskTracking(
              promisedAt: DateTime(2026, 9, 23, 20),
              decision: ActiveCoachingDecision.notToday,
            ),
          )
          .put('b', TaskTracking(promisedAt: DateTime(2026, 9, 23, 18)));
      expect(day.promises.keys, ['b']);
      expect(day.settled, {'a'});
    });

    test('오늘 목록에 없는 일은 걷어낸다', () {
      final day = ActiveCoachingDay(date: today)
          .put('a', const TaskTracking(nudges: 1))
          .put('gone', const TaskTracking(nudges: 1));
      expect(day.pruneMissing({'a'}).tasks.keys, ['a']);
    });

    test('아무것도 안 쌓인 일은 저장하지 않는다', () {
      final day = ActiveCoachingDay(date: today).put('a', const TaskTracking());
      expect((day.toJson()['tasks'] as Map), isEmpty);
    });
  });

  group('개입 예산', () {
    ActiveCoachingBudget budget() => ActiveCoachingBudget(date: today);

    test('처음에는 말을 걸 수 있다', () {
      expect(budget().allows(now), isTrue);
    });

    test('한 번 말했으면 두 시간은 쉰다', () {
      final spoken = budget().spoke(now);
      expect(spoken.allows(now.add(const Duration(hours: 1))), isFalse);
      expect(spoken.allows(now.add(const Duration(hours: 2))), isTrue);
    });

    test('연달아 세 번 무응답이면 간격이 네 시간으로', () {
      // 접지는 않는다. 오후 내내 못 봤다가 저녁에 폰을 잡는 사람이 있다.
      var state = budget().spoke(now).noReply().noReply().noReply();
      expect(state.allows(now.add(const Duration(hours: 3))), isFalse);
      expect(state.allows(now.add(const Duration(hours: 4))), isTrue);
    });

    test('한 번이라도 답하면 간격이 돌아온다', () {
      var state = budget().spoke(now).noReply().noReply().noReply().replied();
      expect(state.allows(now.add(const Duration(hours: 2))), isTrue);
    });

    test('하루 상한을 넘기면 더 안 부른다', () {
      var state = budget();
      var at = DateTime(2026, 9, 23, 8);
      for (var i = 0; i < ActiveCoachingBudget.dailyCap; i++) {
        state = state.spoke(at);
        at = at.add(const Duration(hours: 2));
      }
      expect(state.spokenToday, ActiveCoachingBudget.dailyCap);
      expect(state.allows(at), isFalse);
    });

    test('밤에는 말을 걸지 않는다', () {
      expect(budget().allows(DateTime(2026, 9, 23, 22)), isFalse);
    });

    test('약속 시각 확인은 총량에 안 들어가지만 시각은 남긴다', () {
      // 사용자가 정한 시각이라 재촉이 아니다. 다만 그 직후에 다른 개입이
      // 곧바로 따라붙으면 그건 두 번 말 건 것이다.
      final state = budget().spoke(now, countsTowardCap: false);
      expect(state.spokenToday, 0);
      expect(state.allows(now.add(const Duration(minutes: 10))), isFalse);
    });

    test('날짜가 바뀌면 통째로 비운다', () {
      final yesterday = ActiveCoachingBudget(
        date: '2026-09-22',
      ).spoke(DateTime(2026, 9, 22, 20)).noReply();
      final back = ActiveCoachingBudget.fromJson(
        yesterday.toJson(),
        today: today,
      );
      expect(back.spokenToday, 0);
      expect(back.noReplyStreak, 0);
      expect(back.allows(now), isTrue);
    });

    test('매인 시간대에 미뤄둔 것은 하나만 들고 간다', () {
      // 퇴근하자마자 밀린 것이 세 번 연달아 오면 그게 제일 나쁘다.
      final state = budget().holdOff('a').holdOff('b');
      expect(state.heldOffTaskId, 'b');
      expect(state.clearHeldOff().heldOffTaskId, isNull);
    });
  });

  group('저장하는 자리', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('추적은 클라우드로 가는 자리, 예산은 이 기기 자리', () {
      // 약속 시각은 기기를 바꿔도 따라와야 하고, 오늘 몇 번 말했는지는 다른
      // 기기에서 내려온 값에 덮이면 안 된다.
      expect(ActiveCoachingStore.trackingKey.startsWith('nyang_'), isTrue);
      expect(ActiveCoachingStore.budgetKey.startsWith('nyang_'), isFalse);
    });

    test('적어둔 것을 다시 읽어온다', () async {
      final prefs = await SharedPreferences.getInstance();
      await ActiveCoachingStore.writeDay(
        prefs,
        ActiveCoachingDay(
          date: today,
        ).put('a', TaskTracking(promisedAt: DateTime(2026, 9, 23, 20))),
      );
      await ActiveCoachingStore.writeBudget(
        prefs,
        ActiveCoachingBudget(date: today).spoke(now, taskId: 'a'),
      );

      expect(
        ActiveCoachingStore.readDay(prefs, now).of('a').promisedAt,
        DateTime(2026, 9, 23, 20),
      );
      final budget = ActiveCoachingStore.readBudget(prefs, now);
      expect(budget.spokenToday, 1);
      expect(budget.lastTaskId, 'a');
    });

    test('저장된 것이 깨져 있어도 빈 하루로 시작한다', () async {
      SharedPreferences.setMockInitialValues({
        ActiveCoachingStore.trackingKey: '{{{',
        ActiveCoachingStore.budgetKey: 'nope',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(ActiveCoachingStore.readDay(prefs, now).tasks, isEmpty);
      expect(ActiveCoachingStore.readBudget(prefs, now).allows(now), isTrue);
    });
  });
}
