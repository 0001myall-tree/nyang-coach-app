import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import 'analytics_service.dart';

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
  static const int friendsDailyTokenLimit = 100000;

  /// 20만이었다. 한 턴에 4천 토큰쯤 나가니 하루 50턴에서 막혔는데, 마스터 코치는
  /// 목표와 기록까지 실어서 턴당 소모가 프렌즈보다 크다. 30만이면 75턴쯤 된다.
  static const int masterDailyTokenLimit = 300000;
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

  /// 고급 모델(gpt-4.1-mini)을 하루에 몇 번 쓸 수 있는지.
  static const int masterPremiumModelDailyLimit = 20;
  static const String premiumModelFeatureName = 'master_premium_model';

  /// 고급 모델 자리 하나를 잡는다. 잡았으면 true.
  ///
  /// 기기 안에 세던 것을 여기로 옮겼다. 로컬에 세면 앱을 지웠다 깔 때마다
  /// 0으로 돌아가고, 기기가 두 대면 하루치가 두 배가 된다. 토큰 한도는 이미
  /// 계정 단위로 세고 있어서 같은 문서에 나란히 둔다.
  ///
  /// 읽기에 실패하면 자리를 주지 않는다. 통신이 끊긴 사이 무제한으로 열리는
  /// 쪽보다 그 턴만 싼 모델이 받는 쪽이 낫다. 답이 안 나가는 것도 아니다.
  ///
  /// 세고 나서 올리는 순서라, 같은 순간에 두 턴이 겹치면 하나쯤 더 나갈 수
  /// 있다. 대화는 답을 받을 때까지 입력이 막혀서 실제로는 겹치지 않는다.
  static Future<bool> tryReserveMasterPremiumModelTurn() async {
    final user = _auth.currentUser;
    if (user == null) return false;

    final int used;
    try {
      final doc = await _userAnalyticsDailyDoc(user.uid, DateTime.now());
      used = _readInt(doc?['features']?[premiumModelFeatureName]);
    } catch (e) {
      return false;
    }
    if (used >= masterPremiumModelDailyLimit) return false;

    await AnalyticsService.logFeatureUsage(premiumModelFeatureName);
    return true;
  }

  static Future<Map<String, dynamic>?> _userAnalyticsDailyDoc(
    String uid,
    DateTime date,
  ) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('analytics_daily')
        .doc(_dateKey(date))
        .get();
    return doc.data();
  }

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
