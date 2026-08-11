import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';

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
  // 한도를 정할 때 비용을 실제보다 훨씬 크게 잡고 있었다. 테스터 5명이 15일간
  // 쓴 API 비용이 550원, 1인당 하루 7원꼴이다. 그래서 한 번 올렸다.
  //
  // 다만 한도는 최악의 경우에 얼마까지 나갈 수 있는가를 정하는 값이다. 한 턴에
  // 4천 토큰으로 잡으면 아래 숫자에서 나오는 월 최대 비용은 프렌즈 4천 원,
  // 마스터 7천 2백 원쯤이다. 정상가(8,900원) 아래이되, 얼리버드 1년권(월 5,900원)
  // 사용자가 마스터 한도를 매일 꽉 채우면 적자다. 실사용의 20배가 넘는 경우라
  // 현실성은 낮지만, 더 올리려면 이 계산부터 다시 할 것.
  //
  // 조여야 할 때는 고급 모델 횟수보다 이 토큰 한도를 먼저 건드린다. 비용의 절반
  // 이상이 평범한 대화가 쌓여서 나오고, 답이 나빠지는 건 모델을 내릴 때가 크다.

  /// 10만 → 20만. 하루 50턴쯤.
  static const int friendsDailyTokenLimit = 200000;

  /// 20만 → 30만 → 40만. 마스터 코치는 목표와 기록까지 실어서 턴당 소모가
  /// 프렌즈보다 크다. 40만이면 100턴쯤 된다.
  static const int masterDailyTokenLimit = 400000;
  static const int masterDailyOrganizeLimit = 7;

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
    final limits = _tokenLimitsFor(userData);
    if (limits == null) {
      return const ApiUsageLimitResult(
        allowed: false,
        message: 'AI 대화는 구독 플랜에서 이용할 수 있어요.',
      );
    }

    final today = DateTime.now();
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
    final limits = _tokenLimitsFor(userData);
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

  static _TokenLimits? _tokenLimitsFor(UserData userData) {
    if (!userData.isPlanActive) return null;
    if (userData.planType == 'friends') {
      return const _TokenLimits(daily: friendsDailyTokenLimit);
    }
    if (userData.planType == 'master') {
      return const _TokenLimits(daily: masterDailyTokenLimit);
    }
    return null;
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
