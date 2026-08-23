import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 코치 답변 신고. 코치가 하는 말은 그때그때 만들어지는 거라 미리 다 볼 수
/// 없다. 이상한 말이 나왔을 때 사용자가 곧바로 알릴 길을 열어둔다.
class ContentReportService {
  ContentReportService._();

  static final instance = ContentReportService._();

  /// 신고 사유. 사용자가 고르는 그대로 저장한다.
  static const reasons = [
    '불쾌하거나 공격적인 말',
    '위험하거나 해로운 조언',
    '사실과 다른 내용',
    '성적이거나 부적절한 내용',
    '기타',
  ];

  Future<bool> submit({
    required String reason,
    required String replyText,
    String? note,
    String? coachId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      await FirebaseFirestore.instance.collection('content_reports').add({
        'uid': user.uid,
        'email': user.email,
        'reason': reason,
        'note': note,
        'coachId': coachId,
        'replyText': replyText,
        'createdAt': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.name,
      });
      return true;
    } catch (e) {
      debugPrint('Content report failed: $e');
      return false;
    }
  }
}
