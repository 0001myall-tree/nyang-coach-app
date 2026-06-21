import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;
  static const double _krwPerUsd = 1400;
  static const double _gpt4oMiniOutputUsdPerMillionTokens = 0.60;

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static DocumentReference<Map<String, dynamic>> _userAnalyticsSummaryRef(
    String uid,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('analytics')
        .doc('summary');
  }

  static DocumentReference<Map<String, dynamic>> _userAnalyticsDailyRef(
    String uid,
    String dateKey,
  ) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('analytics_daily')
        .doc(dateKey);
  }

  static int _estimateCostWonFromTokens(int tokenCount) {
    if (tokenCount <= 0) return 0;
    final usdCost = tokenCount / 1000000 * _gpt4oMiniOutputUsdPerMillionTokens;
    return (usdCost * _krwPerUsd).round();
  }

  static int? readIntValue(Map data, List<String> keys) {
    for (final key in keys) {
      dynamic value = data;
      for (final segment in key.split('.')) {
        if (value is Map && value.containsKey(segment)) {
          value = value[segment];
        } else {
          value = null;
          break;
        }
      }
      if (value is int) return value;
      if (value is num) return value.round();
      if (value is String) return int.tryParse(value);
    }
    return null;
  }

  static int estimateChatTokens(
    List<Map<String, String>> messages,
    String reply,
  ) {
    final totalChars =
        messages.fold<int>(
          0,
          (total, item) => total + (item['content'] ?? '').length,
        ) +
        reply.length;
    return (totalChars / 3.2).ceil();
  }

  static Future<void> _safeSet(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
    String label,
  ) async {
    try {
      await ref.set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Analytics $label logging failed: $e');
    }
  }

  static Future<void> _safeTimelineEvent(
    String uid,
    String eventType,
    String description,
  ) async {
    try {
      await _logTimelineEvent(uid, eventType, description);
    } catch (e) {
      debugPrint('Analytics timeline wrapper failed: $e');
    }
  }

  /// 매일 최초 접속 시 DAU(일간 활성 사용자) 및 접속 기록 저장
  static Future<void> logAppOpen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey = _dateKey(now);
    final summaryRef = _userAnalyticsSummaryRef(user.uid);

    try {
      final summaryDoc = await summaryRef.get();
      final summaryData = summaryDoc.data();
      if (summaryData == null || summaryData['joinedAt'] == null) {
        await summaryRef.set({
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Analytics joinedAt logging failed: $e');
    }

    await _safeSet(summaryRef, {
      'uid': user.uid,
      'email': user.email,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'activeDates': FieldValue.arrayUnion([dateKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, 'user app open summary');

    await _safeSet(_userAnalyticsDailyRef(user.uid, dateKey), {
      'date': dateKey,
      'uid': user.uid,
      'email': user.email,
      'openedAt': FieldValue.serverTimestamp(),
      'appOpenCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, 'user app open daily');

    await _safeTimelineEvent(user.uid, 'app_open', '앱 접속');

    await _safeSet(_firestore.collection('analytics').doc('dau_$dateKey'), {
      'date': dateKey,
      'activeUsers': FieldValue.arrayUnion([user.uid]),
      'totalVisits': FieldValue.increment(1),
    }, 'global dau');
  }

  /// 특정 코치와 대화한 횟수 및 비용 로깅
  static Future<void> logConversationMessage({
    required String coachId,
    required bool usedApi,
    bool coachReplied = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateKey = _dateKey(DateTime.now());
    final conversationPayload = {
      'uid': user.uid,
      'email': user.email,
      'totalUserMessages': FieldValue.increment(1),
      'totalCoachReplies': FieldValue.increment(coachReplied ? 1 : 0),
      'apiReplies': FieldValue.increment(usedApi && coachReplied ? 1 : 0),
      'localReplies': FieldValue.increment(!usedApi && coachReplied ? 1 : 0),
      'coachUsage': {coachId: FieldValue.increment(1)},
      'lastActiveAt': FieldValue.serverTimestamp(),
      'activeDates': FieldValue.arrayUnion([dateKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _safeSet(
      _userAnalyticsSummaryRef(user.uid),
      conversationPayload,
      'user conversation summary',
    );

    await _safeSet(_userAnalyticsDailyRef(user.uid, dateKey), {
      'date': dateKey,
      ...conversationPayload,
    }, 'user conversation daily');

    await _safeSet(
      _firestore.collection('analytics').doc('conversation_usage'),
      {
        'totalUserMessages': FieldValue.increment(1),
        'totalCoachReplies': FieldValue.increment(coachReplied ? 1 : 0),
        'apiReplies': FieldValue.increment(usedApi && coachReplied ? 1 : 0),
        'localReplies': FieldValue.increment(!usedApi && coachReplied ? 1 : 0),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'global conversation',
    );

    await _safeSet(
      _firestore.collection('analytics').doc('conversation_usage_by_coach'),
      {
        '$coachId.totalUserMessages': FieldValue.increment(1),
        '$coachId.totalCoachReplies': FieldValue.increment(
          coachReplied ? 1 : 0,
        ),
        '$coachId.apiReplies': FieldValue.increment(
          usedApi && coachReplied ? 1 : 0,
        ),
        '$coachId.localReplies': FieldValue.increment(
          !usedApi && coachReplied ? 1 : 0,
        ),
        '$coachId.updatedAt': FieldValue.serverTimestamp(),
      },
      'global conversation by coach',
    );

    await _safeSet(
      _firestore
          .collection('analytics')
          .doc('conversation_usage_daily_$dateKey'),
      {
        'date': dateKey,
        'activeUsers': FieldValue.arrayUnion([user.uid]),
        'totalUserMessages': FieldValue.increment(1),
        'totalCoachReplies': FieldValue.increment(coachReplied ? 1 : 0),
        'apiReplies': FieldValue.increment(usedApi && coachReplied ? 1 : 0),
        'localReplies': FieldValue.increment(!usedApi && coachReplied ? 1 : 0),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'global conversation daily',
    );

    final replyLabel = coachReplied
        ? (usedApi ? 'API 응답' : '로컬 응답')
        : '사용자 입력만';
    await _safeTimelineEvent(
      user.uid,
      'chat',
      '대화 메시지 전송: $coachId ($replyLabel)',
    );
  }

  /// 특정 코치의 API 사용량 및 비용 로깅
  static Future<void> logApiUsage({
    required String coachId,
    required int estimatedTokens,
    int? actualTokens,
    int? actualCostWon,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateKey = _dateKey(DateTime.now());
    final tokenCount = actualTokens ?? estimatedTokens;
    // 서버에서 실제 비용을 내려주지 않으면 GPT-4o-mini 출력 단가 기준으로 보수적으로 추정합니다.
    final costWon = actualCostWon ?? _estimateCostWonFromTokens(tokenCount);
    final apiPayload = {
      'uid': user.uid,
      'email': user.email,
      'totalTokens': FieldValue.increment(tokenCount),
      'totalCostWon': FieldValue.increment(costWon),
      'apiCallCount': FieldValue.increment(1),
      'lastActiveAt': FieldValue.serverTimestamp(),
      'activeDates': FieldValue.arrayUnion([dateKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _safeSet(
      _userAnalyticsSummaryRef(user.uid),
      apiPayload,
      'user api summary',
    );

    await _safeSet(_userAnalyticsDailyRef(user.uid, dateKey), {
      'date': dateKey,
      ...apiPayload,
    }, 'user api daily');

    await _safeTimelineEvent(user.uid, 'chat', '코치($coachId)와 대화 진행');

    await _safeSet(_firestore.collection('analytics').doc('coach_usage'), {
      coachId: FieldValue.increment(1),
      'totalChats': FieldValue.increment(1),
    }, 'global coach usage');

    await _safeSet(_firestore.collection('analytics').doc('api_costs'), {
      'totalTokens': FieldValue.increment(tokenCount),
      'totalCostWon': FieldValue.increment(costWon),
      'apiCallCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    }, 'global api costs');

    await _safeSet(
      _firestore.collection('analytics').doc('api_costs_daily_$dateKey'),
      {
        'date': dateKey,
        'activeUsers': FieldValue.arrayUnion([user.uid]),
        'totalTokens': FieldValue.increment(tokenCount),
        'totalCostWon': FieldValue.increment(costWon),
        'apiCallCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      'global api costs daily',
    );
  }

  /// 기능 사용 로깅 (모닝콜, 명상, 나이트콜 등)
  static Future<void> logFeatureUsage(String featureName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateKey = _dateKey(DateTime.now());
    final featurePayload = {
      'uid': user.uid,
      'email': user.email,
      'features': {featureName: FieldValue.increment(1)},
      'lastActiveAt': FieldValue.serverTimestamp(),
      'activeDates': FieldValue.arrayUnion([dateKey]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _safeSet(
      _userAnalyticsSummaryRef(user.uid),
      featurePayload,
      'user feature summary',
    );

    await _safeSet(_userAnalyticsDailyRef(user.uid, dateKey), {
      'date': dateKey,
      ...featurePayload,
    }, 'user feature daily');

    await _safeTimelineEvent(user.uid, 'feature', '기능 사용: $featureName');

    await _safeSet(
      _firestore.collection('analytics').doc('feature_usage'),
      {featureName: FieldValue.increment(1)},
      'global feature usage',
    );
  }

  /// 에러 발생 시 로깅
  static Future<void> logError(
    String errorMessage,
    String stackTrace, {
    String? contextInfo,
  }) async {
    final user = _auth.currentUser;
    try {
      await _firestore.collection('error_logs').add({
        'timestamp': FieldValue.serverTimestamp(),
        'uid': user?.uid ?? 'anonymous',
        'errorMessage': errorMessage,
        'stackTrace': stackTrace,
        'context': contextInfo ?? '',
      });

      if (user != null) {
        await _logTimelineEvent(user.uid, 'error', '앱 내부 에러 발생: $errorMessage');
      }
    } catch (e) {
      debugPrint('Analytics error logging failed: $e');
    }
  }

  /// 테스터별 타임라인 기록
  static Future<void> _logTimelineEvent(
    String uid,
    String eventType,
    String description,
  ) async {
    try {
      // 최근 타임라인 기록 (Firestore 서브컬렉션에 기록)
      await _firestore.collection('users').doc(uid).collection('timeline').add({
        'timestamp': FieldValue.serverTimestamp(),
        'eventType': eventType,
        'description': description,
      });
    } catch (e) {
      debugPrint('Analytics timeline logging failed: $e');
    }
  }
}
