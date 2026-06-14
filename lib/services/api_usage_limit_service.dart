import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_data.dart';

class ApiUsageLimitResult {
  final bool allowed;
  final String message;
  final int dailyUsed;
  final int dailyLimit;
  final int weeklyUsed;
  final int weeklyLimit;
  final int organizeUsed;
  final int organizeLimit;

  const ApiUsageLimitResult({
    required this.allowed,
    required this.message,
    this.dailyUsed = 0,
    this.dailyLimit = 0,
    this.weeklyUsed = 0,
    this.weeklyLimit = 0,
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

class ApiUsageLimitService {
  static const int friendsDailyTokenLimit = 100000;
  static const int friendsWeeklyTokenLimit = 500000;
  static const int masterDailyTokenLimit = 300000;
  static const int masterWeeklyTokenLimit = 1500000;
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
    final weeklyUsed = await _weeklyTokenUsage(user.uid, today);
    final nextDaily = dailyUsed + estimatedTokens;
    final nextWeekly = weeklyUsed + estimatedTokens;

    if (dailyUsed >= limits.daily || nextDaily > limits.daily) {
      return ApiUsageLimitResult(
        allowed: false,
        message: '오늘의 AI 대화 사용량을 모두 사용했어요. 내일 다시 이어가요.',
        dailyUsed: dailyUsed,
        dailyLimit: limits.daily,
        weeklyUsed: weeklyUsed,
        weeklyLimit: limits.weekly,
      );
    }

    if (weeklyUsed >= limits.weekly || nextWeekly > limits.weekly) {
      return ApiUsageLimitResult(
        allowed: false,
        message: '이번 주 AI 대화 사용량을 모두 사용했어요. 다음 주에 다시 이어가요.',
        dailyUsed: dailyUsed,
        dailyLimit: limits.daily,
        weeklyUsed: weeklyUsed,
        weeklyLimit: limits.weekly,
      );
    }

    return ApiUsageLimitResult(
      allowed: true,
      message: '',
      dailyUsed: dailyUsed,
      dailyLimit: limits.daily,
      weeklyUsed: weeklyUsed,
      weeklyLimit: limits.weekly,
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

  static _TokenLimits? _tokenLimitsFor(UserData userData) {
    if (!userData.isPlanActive) return null;
    if (userData.planType == 'friends') {
      return const _TokenLimits(
        daily: friendsDailyTokenLimit,
        weekly: friendsWeeklyTokenLimit,
      );
    }
    if (userData.planType == 'master') {
      return const _TokenLimits(
        daily: masterDailyTokenLimit,
        weekly: masterWeeklyTokenLimit,
      );
    }
    return null;
  }

  static Future<int> _dailyTokenUsage(String uid, DateTime date) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('analytics_daily')
        .doc(_dateKey(date))
        .get();
    return _readInt(doc.data()?['totalTokens']);
  }

  static Future<int> _weeklyTokenUsage(String uid, DateTime today) async {
    var total = 0;
    for (var i = 0; i < 7; i += 1) {
      total += await _dailyTokenUsage(uid, today.subtract(Duration(days: i)));
    }
    return total;
  }

  static Future<int> _dailyFeatureUsage(
    String uid,
    DateTime date,
    String featureName,
  ) async {
    final doc = await _firestore
        .collection('users')
        .doc(uid)
        .collection('analytics_daily')
        .doc(_dateKey(date))
        .get();
    final features = doc.data()?['features'];
    if (features is Map) {
      return _readInt(features[featureName]);
    }
    return 0;
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
  final int weekly;

  const _TokenLimits({required this.daily, required this.weekly});
}
