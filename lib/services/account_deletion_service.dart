import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'free_access_service.dart';
import 'tasks_sync_service.dart';

/// 계정 삭제. 클라우드에 쌓인 것과 이 기기에 남은 것을 모두 지우고
/// 로그인 계정 자체를 없앤다. 되돌릴 수 없다.
class AccountDeletionResult {
  const AccountDeletionResult._(this.status, [this.message = '']);

  final AccountDeletionStatus status;
  final String message;

  bool get isSuccess => status == AccountDeletionStatus.deleted;

  static const deleted = AccountDeletionResult._(AccountDeletionStatus.deleted);

  static const notSignedIn = AccountDeletionResult._(
    AccountDeletionStatus.notSignedIn,
    '로그인된 계정이 없어요.',
  );

  static const reauthRequired = AccountDeletionResult._(
    AccountDeletionStatus.reauthRequired,
    '보안을 위해 다시 로그인한 뒤 삭제할 수 있어요. 로그아웃했다가 다시 로그인해주세요.',
  );

  factory AccountDeletionResult.failed(String message) =>
      AccountDeletionResult._(AccountDeletionStatus.failed, message);
}

enum AccountDeletionStatus { deleted, notSignedIn, reauthRequired, failed }

class AccountDeletionService {
  AccountDeletionService._();

  static final instance = AccountDeletionService._();

  /// users/{uid} 아래에 데이터가 쌓이는 곳들. 클라우드에는 폴더라는 게 없어서
  /// 문서를 지운다고 그 아래가 같이 사라지지 않는다. 하나씩 지워야 한다.
  static const _subcollections = [
    'appData',
    'analytics',
    'analytics_daily',
    'timeline',
  ];

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<AccountDeletionResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return AccountDeletionResult.notSignedIn;

    // 실시간 동기화가 돌고 있으면 지우는 족족 다시 내려받아 저장한다. 먼저 끈다.
    TasksSyncService.stopRealTimeSync();

    try {
      await _deleteCloudData(user.uid);
    } catch (e) {
      debugPrint('Account cloud data delete failed: $e');
      return AccountDeletionResult.failed('데이터를 지우는 중 문제가 생겼어요. 잠시 후 다시 시도해주세요.');
    }

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // 마지막 로그인이 오래됐다. 데이터는 이미 지워졌으니, 다시 로그인해
        // 한 번 더 누르면 계정까지 정리된다.
        return AccountDeletionResult.reauthRequired;
      }
      debugPrint('Account delete failed: ${e.code}');
      return AccountDeletionResult.failed('계정을 지우지 못했어요. 잠시 후 다시 시도해주세요.');
    }

    await _clearLocalData();
    FreeAccessService.instance.clearCache();
    return AccountDeletionResult.deleted;
  }

  Future<void> _deleteCloudData(String uid) async {
    final userDoc = _db.collection('users').doc(uid);

    for (final name in _subcollections) {
      await _deleteAllDocuments(userDoc.collection(name));
    }

    await userDoc.delete();
  }

  /// 한 번에 다 지우면 요청이 너무 커진다. 500개씩 끊어서 비울 때까지 돈다.
  Future<void> _deleteAllDocuments(CollectionReference<Object?> collection) async {
    while (true) {
      final snapshot = await collection.limit(500).get();
      if (snapshot.docs.isEmpty) return;

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < 500) return;
    }
  }

  Future<void> _clearLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
