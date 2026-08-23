import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/distraction_coach_quota.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 프렌즈 등급의 딴짓 방지 코칭은 하루 한 일정까지다.
///
/// 규칙의 핵심은 "언제 몫이 줄어드는가"에 있다. 시작할 때가 아니라 냥냥이가
/// 실제로 나온 때다. 그래서 시작만 하고 딴짓하지 않은 일정은 몫을 넘긴다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final monday9am = DateTime(2026, 8, 24, 9);
  final monday10am = DateTime(2026, 8, 24, 10);
  final tuesday9am = DateTime(2026, 8, 25, 9);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> beFriends() => DistractionCoachQuota.setUnlimited(false);
  Future<void> beMaster() => DistractionCoachQuota.setUnlimited(true);

  group('마스터', () {
    test('일정마다 붙는다', () async {
      await beMaster();
      expect(await DistractionCoachQuota.claimNow('a', monday9am), isTrue);
      expect(await DistractionCoachQuota.claimNow('b', monday10am), isTrue);
    });

    test('하루치를 다 썼다는 말을 듣지 않는다', () async {
      await beMaster();
      await DistractionCoachQuota.claimNow('a', monday9am);
      expect(
        await DistractionCoachQuota.shouldTellQuotaSpent('b', monday10am),
        isFalse,
      );
    });
  });

  group('프렌즈 — 바로 나오는 갈래', () {
    test('처음 나온 일정이 오늘치를 가져간다', () async {
      await beFriends();
      expect(await DistractionCoachQuota.claimNow('a', monday9am), isTrue);
      expect(await DistractionCoachQuota.claimNow('b', monday10am), isFalse);
    });

    test('임자인 일정은 그날 내내 계속 나온다', () async {
      await beFriends();
      await DistractionCoachQuota.claimNow('a', monday9am);
      expect(await DistractionCoachQuota.claimNow('a', monday10am), isTrue);
    });

    test('날이 바뀌면 다시 하나', () async {
      await beFriends();
      await DistractionCoachQuota.claimNow('a', monday9am);
      expect(await DistractionCoachQuota.claimNow('b', tuesday9am), isTrue);
    });
  });

  group('프렌즈 — 30분 뒤에 나오는 갈래', () {
    test('나오기 전에 끝낸 일정은 몫을 쓰지 않는다', () async {
      await beFriends();
      await DistractionCoachQuota.reserve(
        taskId: 'a',
        firesAt: monday9am.add(const Duration(minutes: 30)),
        nowOverride: monday9am,
      );
      // 20분 만에 끝냈다. 걸어둔 배너가 취소되면서 자리도 풀린다.
      await DistractionCoachQuota.releaseUnconfirmedUnless(
        nowOverride: monday9am.add(const Duration(minutes: 20)),
      );

      final next = monday9am.add(const Duration(minutes: 25));
      expect(
        await DistractionCoachQuota.reserve(
          taskId: 'b',
          firesAt: next.add(const Duration(minutes: 30)),
          nowOverride: next,
        ),
        isTrue,
      );
    });

    test('맡아둔 시각이 지나면 그 일정이 임자로 굳는다', () async {
      await beFriends();
      await DistractionCoachQuota.reserve(
        taskId: 'a',
        firesAt: monday9am.add(const Duration(minutes: 30)),
        nowOverride: monday9am,
      );

      final after = monday9am.add(const Duration(minutes: 31));
      expect(await DistractionCoachQuota.ownerToday(after), 'a');
      // 지나간 뒤에는 풀리지 않는다.
      await DistractionCoachQuota.releaseUnconfirmedUnless(nowOverride: after);
      expect(
        await DistractionCoachQuota.reserve(
          taskId: 'b',
          firesAt: after.add(const Duration(minutes: 30)),
          nowOverride: after,
        ),
        isFalse,
      );
    });

    test('아직 나오지 않은 자리는 다음 일정이 가져간다', () async {
      await beFriends();
      await DistractionCoachQuota.reserve(
        taskId: 'a',
        firesAt: monday9am.add(const Duration(minutes: 30)),
        nowOverride: monday9am,
      );
      final soon = monday9am.add(const Duration(minutes: 10));
      expect(
        await DistractionCoachQuota.reserve(
          taskId: 'b',
          firesAt: soon.add(const Duration(minutes: 30)),
          nowOverride: soon,
        ),
        isTrue,
      );
      expect(await DistractionCoachQuota.ownerToday(soon), 'b');
    });
  });

  group('다 썼다고 알려주기', () {
    test('확정된 뒤에 다른 일정을 시작하면 하루 한 번 말한다', () async {
      await beFriends();
      await DistractionCoachQuota.claimNow('a', monday9am);
      expect(
        await DistractionCoachQuota.shouldTellQuotaSpent('b', monday10am),
        isTrue,
      );
      expect(
        await DistractionCoachQuota.shouldTellQuotaSpent('c', monday10am),
        isFalse,
      );
    });

    test('임자인 일정에는 말하지 않는다', () async {
      await beFriends();
      await DistractionCoachQuota.claimNow('a', monday9am);
      expect(
        await DistractionCoachQuota.shouldTellQuotaSpent('a', monday10am),
        isFalse,
      );
    });

    test('아직 나오지 않은 자리뿐이면 말하지 않는다', () async {
      await beFriends();
      await DistractionCoachQuota.reserve(
        taskId: 'a',
        firesAt: monday9am.add(const Duration(minutes: 30)),
        nowOverride: monday9am,
      );
      final soon = monday9am.add(const Duration(minutes: 10));
      expect(
        await DistractionCoachQuota.shouldTellQuotaSpent('b', soon),
        isFalse,
      );
    });
  });
}
