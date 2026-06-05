import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 매일 최초 접속 시 DAU(일간 활성 사용자) 및 접속 기록 저장
  static Future<void> logAppOpen() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final now = DateTime.now();
      final dateKey = _dateKey(now);

      // 사용자별 타임라인 이벤트 추가
      await _logTimelineEvent(user.uid, 'app_open', '앱 접속');

      // 날짜별 DAU 기록 (Set을 이용하여 중복 방지)
      await _firestore.collection('analytics').doc('dau_$dateKey').set({
        'date': dateKey,
        'activeUsers': FieldValue.arrayUnion([user.uid]),
        'totalVisits': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Analytics app open logging failed: $e');
    }
  }

  /// 특정 코치와 대화한 횟수 및 비용 로깅
  static Future<void> logConversationMessage({
    required String coachId,
    required bool usedApi,
    bool coachReplied = true,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final dateKey = _dateKey(DateTime.now());
      await _firestore.collection('analytics').doc('conversation_usage').set({
        'totalUserMessages': FieldValue.increment(1),
        'totalCoachReplies': FieldValue.increment(coachReplied ? 1 : 0),
        'apiReplies': FieldValue.increment(usedApi && coachReplied ? 1 : 0),
        'localReplies': FieldValue.increment(!usedApi && coachReplied ? 1 : 0),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore
          .collection('analytics')
          .doc('conversation_usage_by_coach')
          .set({
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
          }, SetOptions(merge: true));

      await _firestore
          .collection('analytics')
          .doc('conversation_usage_daily_$dateKey')
          .set({
            'date': dateKey,
            'activeUsers': FieldValue.arrayUnion([user.uid]),
            'totalUserMessages': FieldValue.increment(1),
            'totalCoachReplies': FieldValue.increment(coachReplied ? 1 : 0),
            'apiReplies': FieldValue.increment(usedApi && coachReplied ? 1 : 0),
            'localReplies': FieldValue.increment(
              !usedApi && coachReplied ? 1 : 0,
            ),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Analytics conversation logging failed: $e');
    }
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

    try {
      final dateKey = _dateKey(DateTime.now());
      final tokenCount = actualTokens ?? estimatedTokens;
      // 서버에서 실제 비용을 내려주지 않으면 임시 추정 비용을 기록합니다.
      final costWon = actualCostWon ?? (tokenCount * 0.1).round();

      // 사용자 타임라인 이벤트 추가
      await _logTimelineEvent(user.uid, 'chat', '코치($coachId)와 대화 진행');

      // 1. 코치별 사용량 누적
      await _firestore.collection('analytics').doc('coach_usage').set({
        coachId: FieldValue.increment(1),
        'totalChats': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // 2. 전체 토큰 및 예상 비용 누적
      await _firestore.collection('analytics').doc('api_costs').set({
        'totalTokens': FieldValue.increment(tokenCount),
        'totalCostWon': FieldValue.increment(costWon),
        'apiCallCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _firestore
          .collection('analytics')
          .doc('api_costs_daily_$dateKey')
          .set({
            'date': dateKey,
            'activeUsers': FieldValue.arrayUnion([user.uid]),
            'totalTokens': FieldValue.increment(tokenCount),
            'totalCostWon': FieldValue.increment(costWon),
            'apiCallCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Analytics api usage logging failed: $e');
    }
  }

  /// 기능 사용 로깅 (모닝콜, 명상, 나이트콜 등)
  static Future<void> logFeatureUsage(String featureName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      await _logTimelineEvent(user.uid, 'feature', '기능 사용: $featureName');

      await _firestore.collection('analytics').doc('feature_usage').set({
        featureName: FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Analytics feature logging failed: $e');
    }
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
