import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 로그인 기준 사용자 데이터 보존 기한을 Firestore에 남긴다.
///
/// 실제 삭제는 서버 배치나 콘솔 작업이 맡고, 앱은 폐기 판단에 필요한
/// 마지막 로그인 시각과 폐기 가능 시각만 갱신한다.
class AccountRetentionService {
  AccountRetentionService._();

  static final instance = AccountRetentionService._();

  static const retentionYears = 3;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> markLoggedIn(User user, {DateTime? now}) async {
    final loginAt = now ?? DateTime.now();
    final deleteAfter = retentionDeleteAfter(loginAt);

    try {
      await _db.collection('users').doc(user.uid).set({
        'email': user.email,
        'loginEmail': user.email,
        'lastLoginAt': FieldValue.serverTimestamp(),
        'retentionDeleteAfterAt': Timestamp.fromDate(deleteAfter),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Account retention update failed: $e');
    }
  }

  static DateTime retentionDeleteAfter(DateTime loginAt) {
    final utc = loginAt.toUtc();
    return DateTime.utc(
      utc.year + retentionYears,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    );
  }
}
