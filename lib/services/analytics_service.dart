import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/user_data.dart';

class AnalyticsService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Firebase 콘솔 대시보드용. Firestore 집계(비용·토큰 등 상세 회계)와 별개로,
  /// 사용자 행동은 이쪽으로 보내 콘솔에서 리텐션·기능 사용량을 바로 본다.
  static final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

  /// 콘솔에서 플랜·코치별로 사용 패턴을 나눠 볼 수 있도록 사용자 속성을 심는다.
  static Future<void> _syncAnalyticsUserProperties(String uid) async {
    try {
      final data = await UserDataService.load();
      await analytics.setUserId(id: uid);
      await analytics.setUserProperty(
        name: 'plan_type',
        value: data.isPlanActive ? data.planType : 'none',
      );
      await analytics.setUserProperty(
        name: 'selected_coach',
        value: data.selectedCoachId ?? 'unset',
      );
    } catch (e) {
      debugPrint('Firebase Analytics user properties failed: $e');
    }
  }

  /// Analytics 전송 실패가 앱 동작이나 Firestore 집계를 막지 않게 감싼다.
  static Future<void> _safeAnalyticsEvent(
    String name, [
    Map<String, Object>? parameters,
  ]) async {
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      debugPrint('Firebase Analytics event failed ($name): $e');
    }
  }

  static const double _krwPerUsd = 1400;

  /// 0.285였다. 기록된 추정치가 실제 청구액보다 23% 높게 나와서 그만큼 낮췄다.
  /// 입력이 출력보다 훨씬 많은데(대화 이력과 긴 지시문이 매번 실린다) 혼합 비율을
  /// 출력 쪽으로 무겁게 잡고 있었던 것으로 보인다.
  static const double _gpt4oMiniBlendedUsdPerMillionTokens = 0.22;

  /// gpt-4.1-mini 혼합 단가. 4o-mini의 두 배 반쯤 든다.
  ///
  /// 위와 같은 비율로 낮췄다. 다만 이 값은 아직 실측으로 맞춰본 적이 없는
  /// 어림값이다. 프렌즈 코치까지 이 모델을 쓰기 시작했으니, 다음 청구서가
  /// 나오면 대시보드 금액과 비교해서 여기부터 맞출 것.
  static const double _gpt41MiniBlendedUsdPerMillionTokens = 0.59;

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

  /// [model]을 모르면 싼 모델로 친다. 부르는 쪽 대부분이 4o-mini다.
  static int _estimateCostWonFromTokens(int tokenCount, {String? model}) {
    if (tokenCount <= 0) return 0;
    final rate = (model != null && model.startsWith('gpt-4.1'))
        ? _gpt41MiniBlendedUsdPerMillionTokens
        : _gpt4oMiniBlendedUsdPerMillionTokens;
    final usdCost = tokenCount / 1000000 * rate;
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

  /// 글자당 토큰 수의 역수.
  ///
  /// 3.2였다. 영어 기준으로는 얼추 맞는 값이지만 이 앱의 프롬프트와 대화는
  /// 거의 전부 한국어다. o200k(gpt-4o-mini, gpt-4.1-mini의 토크나이저)로 실제
  /// 프롬프트를 재보니 한국어는 글자당 0.57~0.68토큰이 나왔고, 3.2로 나눈
  /// 값은 실제의 절반쯤(1.8~2.1배 과소)이었다. 짧은 발화일수록 더 벌어진다.
  ///
  /// 1.7은 그 측정치의 역수다. 영어가 섞이면 실제보다 많게 잡히는데, 한도를
  /// 거는 쪽에 쓰는 값이라 넘치는 방향으로 틀리는 편이 안전하다.
  static const double _charsPerToken = 1.7;

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
    return (totalChars / _charsPerToken).ceil();
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

    await _syncAnalyticsUserProperties(user.uid);

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

    await _safeAnalyticsEvent('chat_message', {
      'coach_id': coachId,
      'used_api': usedApi.toString(),
    });

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
    String usageSource = 'chat',
    bool countAsUserUsage = true,
    String? model,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final dateKey = _dateKey(DateTime.now());
    final tokenCount = actualTokens ?? estimatedTokens;
    // 서버에서 실제 비용을 내려주지 않으면 최근 OpenAI 대시보드 비용에 맞춘 혼합 단가로 추정합니다.
    // 모델마다 단가가 달라서 어느 모델이 받았는지를 함께 넘겨야 맞게 적힙니다.
    final costWon =
        actualCostWon ?? _estimateCostWonFromTokens(tokenCount, model: model);
    final commonCounters = {
      'allApiTokens': FieldValue.increment(tokenCount),
      'allEstimatedCostWon': FieldValue.increment(costWon),
      'allApiCallCount': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastApiUsageSource': usageSource,
    };
    final userMetadata = {
      'uid': user.uid,
      'email': user.email,
      'lastActiveAt': FieldValue.serverTimestamp(),
      'activeDates': FieldValue.arrayUnion([dateKey]),
    };
    final scopedPayload = countAsUserUsage
        ? {
            // 기존 admin/한도 로직과 호환되는 사용자-facing API 사용량.
            'totalTokens': FieldValue.increment(tokenCount),
            'totalCostWon': FieldValue.increment(costWon),
            'apiCallCount': FieldValue.increment(1),
            'userApiTokens': FieldValue.increment(tokenCount),
            'userEstimatedCostWon': FieldValue.increment(costWon),
            'userApiCallCount': FieldValue.increment(1),
          }
        : {
            // 백그라운드/시스템 AI 작업은 실제 사용자 채팅 사용량과 분리합니다.
            'systemApiTokens': FieldValue.increment(tokenCount),
            'systemEstimatedCostWon': FieldValue.increment(costWon),
            'systemApiCallCount': FieldValue.increment(1),
          };
    final apiPayload = {...userMetadata, ...commonCounters, ...scopedPayload};
    final globalApiPayload = {...commonCounters, ...scopedPayload};

    await _safeSet(
      _userAnalyticsSummaryRef(user.uid),
      apiPayload,
      'user api summary',
    );

    await _safeSet(_userAnalyticsDailyRef(user.uid, dateKey), {
      'date': dateKey,
      ...apiPayload,
    }, 'user api daily');

    await _safeTimelineEvent(
      user.uid,
      countAsUserUsage ? 'chat' : 'system_api',
      countAsUserUsage ? '코치($coachId)와 대화 진행' : '시스템 AI 작업 진행: $usageSource',
    );

    if (countAsUserUsage) {
      await _safeSet(
        _firestore.collection('analytics').doc('coach_usage'),
        {
          coachId: FieldValue.increment(1),
          'totalChats': FieldValue.increment(1),
        },
        'global coach usage',
      );
    }

    await _safeSet(
      _firestore.collection('analytics').doc('api_costs'),
      globalApiPayload,
      'global api costs',
    );

    await _safeSet(
      _firestore.collection('analytics').doc('api_costs_daily_$dateKey'),
      {
        'date': dateKey,
        'activeUsers': FieldValue.arrayUnion([user.uid]),
        ...globalApiPayload,
      },
      'global api costs daily',
    );
  }

  /// 기능 사용 로깅 (모닝콜, 명상 등)
  static Future<void> logFeatureUsage(String featureName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _safeAnalyticsEvent('feature_use', {'feature_name': featureName});

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
