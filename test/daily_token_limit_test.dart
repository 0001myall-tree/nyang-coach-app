import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/api_usage_limit_service.dart';

/// 어제 쓴 양으로 오늘 한도를 조절한다.
///
/// 한도는 최악의 경우 비용을 묶는 울타리다. 계속 많이 쓰는 사람이 낮아진
/// 한도에 머물러야 그 울타리가 뜻이 있다.
void main() {
  const friends = ApiUsageLimitService.friendsPlanDailyTokenLimit;
  const master = ApiUsageLimitService.masterPlanDailyTokenLimit;
  const step = ApiUsageLimitService.dailyLimitFlexStep;

  int limitAfter(int base, int yesterdayUsed) =>
      ApiUsageLimitService.adjustedDailyLimit(
        base: base,
        yesterdayUsed: yesterdayUsed,
      );

  group('아껴 쓴 다음 날', () {
    test('한 걸음 더 준다', () {
      expect(limitAfter(friends, 50000), friends + step);
      expect(limitAfter(master, 50000), master + step);
    });

    test('어제 기록이 없는 사람도 더 받는다', () {
      expect(limitAfter(friends, 0), friends + step);
    });
  });

  group('많이 쓴 다음 날', () {
    test('한 걸음 덜 준다', () {
      expect(limitAfter(friends, friends), friends - step);
      expect(limitAfter(master, master), master - step);
    });

    test('기본 한도의 80%부터 많이 쓴 날로 본다', () {
      expect(limitAfter(master, (master * 0.8).round()), master - step);
      expect(limitAfter(master, (master * 0.8).round() - 1), master);
    });
  });

  test('어중간하게 쓴 다음 날은 기본 한도', () {
    expect(limitAfter(friends, 100000), friends);
    expect(limitAfter(master, 200000), master);
  });

  group('울타리가 실제로 묶이는지', () {
    /// 100만 토큰당 원. [AnalyticsService]의 gpt-5-mini 혼합 단가.
    const wonPerMillion = 868;

    int monthlyWon(int dailyTokens) =>
        (dailyTokens / 1000000 * wonPerMillion * 30).round();

    test('마스터는 낮아진 한도에 머문다', () {
      // 25만은 기본 30만의 80% 문턱을 넘어서, 또 꽉 채우면 다시 25만이다.
      expect(limitAfter(master, master - step), master - step);
    });

    test('프렌즈는 두 한도를 번갈아 오간다', () {
      // 10만은 기본 15만의 80%(12만)에 못 미쳐서 문턱에 안 걸린다. 그래서
      // 다음 날 기본으로 돌아가고, 그 날을 또 꽉 채우면 다시 내려간다.
      //
      // 판정 기준을 어제 실제로 걸려 있던 한도로 바꾸면 10만에 머물게 할 수
      // 있지만, 그러려면 하루치 기록에 그날 한도까지 써둬야 한다. 아래에서
      // 보듯 이틀 평균이 실수령 아래라 울타리는 이대로도 선다.
      expect(limitAfter(friends, friends - step), friends);
      expect(limitAfter(friends, friends), friends - step);
    });

    test('그 자리 월 비용이 실수령 아래다', () {
      // 구글 수수료 15%를 뗀 실수령: 마스터 6개월권 6,715원,
      // 프렌즈 6개월권 4,165원.
      expect(monthlyWon(master - step), lessThan(6715));
      // 프렌즈는 15만과 10만을 번갈아 쓰는 이틀 평균으로 본다.
      expect(monthlyWon(friends - step ~/ 2), lessThan(4165));
    });

    test('80% 문턱을 피해 다녀도 실수령 아래다', () {
      // 매일 문턱 바로 아래까지만 쓰면 한도가 안 낮아진다. 그 자리가 새는
      // 구멍이 되지 않아야 한다.
      final justUnder = (master * ApiUsageLimitService.heavyDayRatio).ceil() - 1;
      expect(limitAfter(master, justUnder), master);
      expect(monthlyWon(justUnder), lessThan(6715));
    });
  });
}
