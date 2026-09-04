import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import 'free_access_service.dart';

class ApiUsageLimitResult {
  final bool allowed;
  final String message;
  final int dailyUsed;
  final int dailyLimit;
  final int organizeUsed;
  final int organizeLimit;

  const ApiUsageLimitResult({
    required this.allowed,
    required this.message,
    this.dailyUsed = 0,
    this.dailyLimit = 0,
    this.organizeUsed = 0,
    this.organizeLimit = 0,
  });
}

class ApiUsageLimitException implements Exception {
  final String message;
  const ApiUsageLimitException(this.message);

  @override
  String toString() => message;
}

class ApiUsageNotice {
  final String message;
  final int stage;
  final bool suggestsUpgrade;

  const ApiUsageNotice({
    required this.message,
    required this.stage,
    this.suggestsUpgrade = false,
  });
}

class ApiUsageLimitService {
  // 한도는 최악의 경우에 얼마까지 나갈 수 있는가를 정하는 값이다. 실사용은
  // 테스터 기준 1인당 하루 7원(월 210원)이라 한도 근처에 가지도 않는다.
  //
  // 계산은 gpt-5-mini 혼합 단가 100만 토큰당 868원
  // ([AnalyticsService] 참고, 실측으로 맞춰본 적 없는 어림값), 한 턴 4천 토큰
  // 기준이다. 구글 수수료 15%를 뗀 실수령은 마스터 월간 7,565원 / 6개월권
  // 월 6,715원, 프렌즈 월간 5,015원 / 6개월권 월 4,165원이다.
  //
  // 기본 한도를 매일 꽉 채우면 프렌즈 3,900원, 마스터 7,800원이다. 마스터
  // 6개월권은 이 상태로 적자여서, 많이 쓴 다음 날은 한도를 낮춘다
  // ([adjustedDailyLimit]). 계속 많이 쓰는 사람은 낮아진 한도에 머물러
  // 프렌즈 3,100원 / 마스터 6,200원 선에서 묶인다 — 어느 상품이든 안 밑진다.
  //
  // 조여야 할 때는 고급 모델 횟수보다 이 토큰 한도를 먼저 건드린다. 비용의 절반
  // 이상이 평범한 대화가 쌓여서 나오고, 답이 나빠지는 건 모델을 내릴 때가 크다.

  // 아래 둘은 코치가 아니라 플랜에 걸리는 한도다. 쓴 양도 사용자 한 명의 하루
  // 총합으로 세므로, 어느 코치와 대화하든 같은 통에서 빠져나간다. 마스터 플랜
  // 사용자가 냥냥이와 15만을 쓰면 마스터 코치에게 남는 것도 그만큼 줄어든다.

  /// 10만 → 20만 → 15만. 하루 37턴쯤.
  static const int friendsPlanDailyTokenLimit = 150000;

  /// 20만 → 30만 → 40만 → 30만. 마스터 코치는 목표와 기록까지 실어서 턴당
  /// 소모가 크고, 이 플랜은 그 코치를 쓸 수 있어 한도를 두 배로 준다. 30만이면
  /// 75턴쯤 된다.
  static const int masterPlanDailyTokenLimit = 300000;
  static const int masterDailyOrganizeLimit = 7;

  /// 어제 쓴 양에 따라 오늘 한도를 올리거나 내리는 폭.
  static const int dailyLimitFlexStep = 50000;

  /// 이만큼 이하로 쓴 날은 '아껴 쓴 날'이다.
  static const int lightDayTokens = 50000;

  /// 기본 한도의 이 비율 이상 쓴 날은 '많이 쓴 날'이다.
  ///
  /// 90%로 두면, 매일 89%씩 쓰는 사람은 한 번도 안 걸리면서 마스터 6개월권
  /// 실수령을 넘긴다. 80%면 그 자리에서도 안 밑진다.
  static const double heavyDayRatio = 0.8;

  /// 어제 쓴 양을 보고 오늘 한도를 정한다.
  ///
  /// 아껴 쓴 다음 날은 [dailyLimitFlexStep]만큼 더 주고, 많이 쓴 다음 날은 그만큼
  /// 덜 준다. 하루를 크게 쓸 일이 있는 사람은 그 앞뒤로 아끼면 되고, 매일 크게
  /// 쓰는 사람은 낮아진 한도에 머문다.
  ///
  /// 어제 기록이 없는 사람(처음 쓰거나 어제 안 연 사람)은 0으로 들어와 올려주는
  /// 쪽에 걸린다. 그게 뜻이다 — 안 쓴 만큼 다음 날 여유를 준다.
  ///
  /// 판정 기준은 어제 실제로 걸려 있던 한도가 아니라 늘 기본 한도다. 어제 한도를
  /// 알려면 그 앞날까지 봐야 하고, 대화 한 턴마다 읽는 자리라 조회를 늘리지
  /// 않는다.
  static int adjustedDailyLimit({
    required int base,
    required int yesterdayUsed,
  }) {
    if (base <= 0) return base;
    if (yesterdayUsed <= lightDayTokens) return base + dailyLimitFlexStep;
    if (yesterdayUsed >= base * heavyDayRatio) {
      return base - dailyLimitFlexStep;
    }
    return base;
  }

  /// 플랜을 안 쓰는 사람도 냥냥코치와는 대화할 수 있다.
  ///
  /// 5만이었다. 프렌즈의 4분의 1이라 하루 12턴쯤이었는데, 이 통에서 빠져나가는
  /// 것이 대화만이 아니다 — 코치가 먼저 거는 인사, 생활 패턴 설문 세 문항,
  /// 등록 확인 카드가 전부 여기서 나간다. 실제로 주고받는 말은 그보다 적었다.
  ///
  /// 무료 구간을 하루로 줄이면서 그 하루를 넉넉하게 바꿨다. 날수로 아끼는 것과
  /// 한도로 아끼는 것을 둘 다 하면, 맛보기로 쓰기에도 모자란 하루가 된다.
  /// 8만이면 한 사람 하루 최대가 66원이다.
  static const int freePlanDailyTokenLimit = 80000;

  /// 무료 대화는 매일 주는 게 아니라 계정당 하루뿐이다. 며칠째인지 세는 일은
  /// [FreeAccessService]가 맡고, 여기서는 그날 하루의 토큰 상한만 본다.

  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static Future<ApiUsageLimitResult> checkChatAllowance({
    int estimatedTokens = 0,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return const ApiUsageLimitResult(
        allowed: false,
        message: '로그인 후 이용할 수 있어요.',
      );
    }

    final userData = await UserDataService.load();
    final limits = await _tokenLimitsFor(userData, user.uid);
    if (limits == null) {
      return const ApiUsageLimitResult(
        allowed: false,
        message: 'AI 대화는 구독 플랜에서 이용할 수 있어요.',
      );
    }

    final today = DateTime.now();

    if (!userData.isPlanActive && !await FreeAccessService.instance.canChat()) {
      return const ApiUsageLimitResult(
        allowed: false,
        message: '무료로 코치와 대화할 수 있는 하루가 끝났어요.',
      );
    }

    final dailyUsed = await _dailyTokenUsage(user.uid, today);
    final nextDaily = dailyUsed + estimatedTokens;

    if (dailyUsed >= limits.daily || nextDaily > limits.daily) {
      return ApiUsageLimitResult(
        allowed: false,
        message: userData.planType == 'friends'
            ? '오늘의 플래너 토큰을 모두 사용했어요.\n마스터 플랜에서는 더 많은 토큰을 사용할 수 있어요.'
            : '오늘의 플래너 토큰을 모두 사용했어요.\n내일 다시 이용해 주세요.',
        dailyUsed: dailyUsed,
        dailyLimit: limits.daily,
      );
    }

    return ApiUsageLimitResult(
      allowed: true,
      message: '',
      dailyUsed: dailyUsed,
      dailyLimit: limits.daily,
    );
  }

  // 고급 모델 자리를 하루 몇 번으로 세던 층이 여기 있었다.
  //
  // 무거운 턴만 좋은 모델에 태우고 잡담은 싼 모델이 받게 했더니, 코치가 어떤
  // 답은 멀쩡하고 어떤 답은 어색해졌다. 캐릭터가 들쭉날쭉한 게 조금 아끼는
  // 것보다 손해라, 모든 턴을 같은 모델이 받게 하고 이 층을 걷어냈다.
  // 총량은 위의 하루 토큰 한도가 묶는다.

  static Future<ApiUsageLimitResult> checkOrganizeAllowance() async {
    final user = _auth.currentUser;
    if (user == null) {
      return const ApiUsageLimitResult(
        allowed: false,
        message: '로그인 후 이용할 수 있어요.',
      );
    }

    final userData = await UserDataService.load();
    if (!userData.isPlanActive || userData.planType != 'master') {
      return const ApiUsageLimitResult(
        allowed: false,
        message: '✨ 정리 기능은 마스터 플랜에서 사용할 수 있어요.\n긴 메모를 핵심만 추려 보기 좋게 정리해드려요.',
      );
    }

    final used = await _dailyFeatureUsage(
      user.uid,
      DateTime.now(),
      'milestone_memo_organize',
    );
    if (used >= masterDailyOrganizeLimit) {
      return ApiUsageLimitResult(
        allowed: false,
        message: '오늘의 정리 기능을 모두 사용했어요.\n내일 다시 핵심만 착 정리해드릴게요.',
        organizeUsed: used,
        organizeLimit: masterDailyOrganizeLimit,
      );
    }

    return ApiUsageLimitResult(
      allowed: true,
      message: '',
      organizeUsed: used,
      organizeLimit: masterDailyOrganizeLimit,
    );
  }

  static Future<void> ensureChatAllowed({int estimatedTokens = 0}) async {
    final result = await checkChatAllowance(estimatedTokens: estimatedTokens);
    if (!result.allowed) {
      throw ApiUsageLimitException(result.message);
    }
  }

  static Future<ApiUsageNotice?> takeChatUsageNotice() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final userData = await UserDataService.load();
    final limits = await _tokenLimitsFor(userData, user.uid);
    if (limits == null) return null;

    final today = DateTime.now();
    final dailyUsed = await _dailyTokenUsage(user.uid, today);
    final dailyStage = _usageNoticeStage(dailyUsed, limits.daily);
    final dailyPercent = _usagePercent(dailyUsed, limits.daily);

    if (dailyStage == 0) return null;

    final scopeKey = _dateKey(today);

    final prefs = await SharedPreferences.getInstance();
    final noticeKey =
        'nyang_api_usage_notice_${user.uid}_daily_${scopeKey}_$dailyStage';
    if (prefs.getBool(noticeKey) == true) return null;
    await prefs.setBool(noticeKey, true);

    return ApiUsageNotice(
      message: _dailyUsageNotice(dailyStage, dailyPercent, userData.planType),
      stage: dailyStage,
      suggestsUpgrade: userData.planType == 'friends',
    );
  }

  /// 오늘 이 사람에게 걸리는 한도. 플랜이 아니면 null.
  ///
  /// 무료 구간은 어제를 보지 않는다 — 계정당 하루뿐이라 어제가 없다.
  static Future<_TokenLimits?> _tokenLimitsFor(
    UserData userData,
    String uid,
  ) async {
    if (!userData.isPlanActive) {
      return const _TokenLimits(daily: freePlanDailyTokenLimit);
    }
    final base = switch (userData.planType) {
      'friends' => friendsPlanDailyTokenLimit,
      'master' => masterPlanDailyTokenLimit,
      _ => 0,
    };
    if (base == 0) return null;

    final yesterdayUsed = await _dailyTokenUsage(
      uid,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    return _TokenLimits(
      daily: adjustedDailyLimit(base: base, yesterdayUsed: yesterdayUsed),
    );
  }

  static Future<int> _dailyTokenUsage(String uid, DateTime date) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('analytics_daily')
          .doc(_dateKey(date))
          .get();
      return _readInt(doc.data()?['totalTokens']);
    } catch (e) {
      return 0;
    }
  }

  static Future<int> _dailyFeatureUsage(
    String uid,
    DateTime date,
    String featureName,
  ) async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(uid)
          .collection('analytics_daily')
          .doc(_dateKey(date))
          .get();
      return _readInt(doc.data()?['features']?[featureName]);
    } catch (e) {
      return 0;
    }
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static int _usageNoticeStage(int used, int limit) {
    if (limit <= 0) return 0;
    final ratio = used / limit;
    if (ratio >= 1) return 100;
    if (ratio >= 0.95) return 95;
    if (ratio >= 0.8) return 80;
    return 0;
  }

  static int _usagePercent(int used, int limit) {
    if (limit <= 0 || used <= 0) return 0;
    return ((used / limit) * 100).floor().clamp(0, 100);
  }

  static String _dailyUsageNotice(int stage, int percent, String planType) {
    if (stage >= 100) {
      return planType == 'friends'
          ? '오늘의 플래너 토큰 사용량이 $percent%예요.\n마스터 플랜에서는 더 많은 토큰을 사용할 수 있어요.'
          : '오늘의 플래너 토큰 사용량이 $percent%예요.\n내일 다시 이용해 주세요.';
    }
    if (stage >= 95) {
      return '오늘의 플래너 토큰 사용량이 $percent%예요.\n남은 사용량이 많지 않아요.';
    }
    return '오늘의 플래너 토큰 사용량이 $percent%예요.\n남은 사용량을 확인해 주세요.';
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class _TokenLimits {
  final int daily;

  const _TokenLimits({required this.daily});
}
