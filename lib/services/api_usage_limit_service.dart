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
  static const int friendsDailyTokenLimit = 150000;
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
            ? '오늘 AI 대화 사용량을 모두 썼어요.\n마스터 플랜에서는 더 많이 대화할 수 있어요.'
            : '오늘은 정말 많이 이야기했네요.\n내일 다시 이어서 이야기해요.',
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

    if (dailyStage == 0) return null;

    final scopeKey = _dateKey(today);

    final prefs = await SharedPreferences.getInstance();
    final noticeKey =
        'nyang_api_usage_notice_${user.uid}_daily_${scopeKey}_$dailyStage';
    // 반복 테스트를 위해 임시로 캐시 무시 (주석 처리)
    // if (prefs.getBool(noticeKey) == true) return null;
    // await prefs.setBool(noticeKey, true);

    return ApiUsageNotice(
      message: _dailyUsageNotice(dailyStage, userData.planType),
      stage: dailyStage,
      suggestsUpgrade: userData.planType == 'friends',
    );
  }

  static _TokenLimits? _tokenLimitsFor(UserData userData) {
    if (!userData.isPlanActive) return null;
    if (userData.planType == 'friends') {
      return const _TokenLimits(
        daily: friendsDailyTokenLimit,
      );
    }
    if (userData.planType == 'master') {
      return const _TokenLimits(
        daily: masterDailyTokenLimit,
      );
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

  static String _weekKey(DateTime date) {
    final monday = DateTime(
      date.year,
      date.month,
      date.day,
    ).subtract(Duration(days: date.weekday - 1));
    return _dateKey(monday);
  }

  static int _usageNoticeStage(int used, int limit) {
    if (limit <= 0) return 0;
    final ratio = used / limit;
    if (ratio >= 1) return 100;
    if (ratio >= 0.95) return 95;
    if (ratio >= 0.8) return 80;
    return 0;
  }

  static String _dailyUsageNotice(int stage, String planType) {
    if (stage >= 100) {
      return planType == 'friends'
          ? '오늘 AI 대화 사용량을 모두 썼어요.\n마스터 플랜에서는 더 많이 대화할 수 있어요.'
          : '오늘은 정말 많이 이야기했네요.\n내일 다시 이어서 이야기해요.';
    }
    if (stage >= 95) {
      return '오늘의 대화가 거의 끝나가고 있어요.\n조금만 더 이야기할 수 있어요.';
    }
    return '오늘은 코치와 이야기를 많이 나눴네요.\n남은 대화가 얼마 남지 않았어요.';
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
