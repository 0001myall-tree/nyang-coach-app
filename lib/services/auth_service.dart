import 'package:flutter/foundation.dart'; // kIsWeb 추가
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/distraction_coach_quota.dart';
import '../services/free_access_service.dart';
import '../services/memory_service.dart';
import '../services/notification_service.dart';
import '../services/tasks_sync_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email']);
  String? _lastErrorMessage;

  String? get lastErrorMessage => _lastErrorMessage;

  // 유저 상태 스트림 (로그인/로그아웃 상태 변화 감지)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 유저 가져오기
  User? get currentUser => _auth.currentUser;

  /// 로그인한 사람은 모두 들어온다. allowedEmails는 이제 문을 지키는 목록이
  /// 아니라, 테스터에게 플랜을 미리 얹어주는 용도로만 남는다.
  Future<bool> ensureCurrentUserAllowed() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await _applyAllowedEmailEntitlement(await _allowedEmailData(user.email));
    return true;
  }

  // 구글 로그인
  Future<UserCredential?> signInWithGoogle() async {
    _lastErrorMessage = null;
    try {
      UserCredential? cred;
      if (kIsWeb) {
        // 웹(Web) 환경일 때는 복잡한 설정 없이 Firebase 내장 팝업을 바로 띄웁니다!
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        cred = await _auth.signInWithPopup(authProvider);
      } else {
        // 모바일(안드로이드/iOS) 환경
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null; // 사용자가 창을 닫아 취소함

        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        cred = await _auth.signInWithCredential(credential);
      }

      await _syncAfterSignIn(cred);

      return cred;
    } catch (e) {
      _lastErrorMessage = _formatSignInError(e);
      debugPrint("Google Sign-In Error: $_lastErrorMessage");
      return null;
    }
  }

  Future<UserCredential?> signInWithApple() async {
    _lastErrorMessage = null;
    try {
      final appleProvider = AppleAuthProvider()..addScope('email');
      final cred = kIsWeb
          ? await _auth.signInWithPopup(appleProvider)
          : await _auth.signInWithProvider(appleProvider);

      await _syncAfterSignIn(cred);
      return cred;
    } catch (e) {
      _lastErrorMessage = _formatSignInError(e);
      debugPrint("Apple Sign-In Error: $_lastErrorMessage");
      return null;
    }
  }

  Future<UserCredential?> signInWithNaverTest() async {
    _lastErrorMessage = null;
    try {
      if (_auth.currentUser != null) return null;

      final cred = await _auth.signInAnonymously();
      await cred.user?.updateDisplayName('네이버 테스트');
      final allowed = await _isAllowedEmail(cred.user?.email);
      if (!allowed) {
        await _signOutAuthOnly();
        _lastErrorMessage = '등록된 이메일 계정만 이용할 수 있습니다.';
        return null;
      }
      await _createNaverTestProfile();
      return cred;
    } catch (e) {
      _lastErrorMessage = _formatSignInError(e);
      debugPrint("Naver Test Sign-In Error: $_lastErrorMessage");
      return null;
    }
  }

  String _formatSignInError(Object error) {
    if (error is FirebaseAuthException) {
      return '${error.code}: ${error.message ?? error.toString()}';
    }
    return error.toString();
  }

  Future<void> _createNaverTestProfile() async {
    final testData = UserData(
      planType: 'master',
      selectedCoachId: 'cat',
      ownedCoaches: const [
        'cat',
        'boyfriend',
        'bro',
        'halmae',
        'nyang_halbae',
        'sec_female',
      ],
    );
    await UserDataService.save(testData);
    await NotificationService().syncDailyMorningCall();
    await NotificationService().disableNightCallReminders();
    await NotificationService().syncCoreReminders();
  }

  Future<void> _syncAfterSignIn(UserCredential? cred) async {
    final user = cred?.user;
    if (user == null) return;
    await _clearDataOfPreviousAccount(user);
    final allowData = await _allowedEmailData(user.email);
    await UserDataService.syncFromCloud();
    await _applyAllowedEmailEntitlement(allowData);
    await MemoryService().syncFromCloud();
    await TasksSyncService.syncFromCloudWithRetry();
    await _syncNotificationsSafely();
  }

  /// 이 기기에 마지막으로 로그인했던 사람. 'nyang_'으로 시작하지 않는 키를
  /// 쓴다 — 그 접두어는 클라우드 복원이 덮어쓰는데, 이건 이 기기에서 방금
  /// 일어난 일이라 기기마다 달라야 한다.
  static const _lastUidKey = 'last_signed_in_uid';

  /// 다른 사람이 로그인하면 앞사람이 남긴 것을 지운다.
  ///
  /// 앱 데이터는 기기에 있고 계정과 묶여 있지 않다. 그래서 로그아웃하고
  /// 다른 계정으로 들어와도 앞사람의 플랜과 코치, 일정과 대화가 그대로
  /// 남아 있었다. 클라우드에서 받아오는 것도 도움이 안 됐다 — 새 계정은
  /// 클라우드에 아무것도 없어서, 덮어쓸 값이 없으니 앞사람 것이 살아남았다.
  ///
  /// 처음 로그인하는 기기에서는 지우지 않는다. 지울 앞사람이 없고, 이미
  /// 쓰고 있던 분이 이 버전으로 올라오는 길이기도 하다.
  Future<void> _clearDataOfPreviousAccount(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final lastUid = prefs.getString(_lastUidKey);

    if (lastUid != null && lastUid != user.uid) {
      final keys = prefs
          .getKeys()
          .where((key) => key.startsWith('nyang_'))
          .toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.remove(DistractionCoachQuota.unlimitedKey);
      UserDataService.clearCache();
      MemoryService().clearCache();
      FreeAccessService.instance.clearCache();
    }

    await prefs.setString(_lastUidKey, user.uid);
  }

  Future<bool> _isAllowedEmail(String? email) async {
    return _isEnabledAllowedEmail(await _allowedEmailData(email));
  }

  bool _isEnabledAllowedEmail(Map<String, dynamic>? data) {
    return data?['enabled'] == true;
  }

  Future<Map<String, dynamic>?> _allowedEmailData(String? email) async {
    final normalizedEmail = email?.trim().toLowerCase();
    if (normalizedEmail == null || normalizedEmail.isEmpty) return null;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('allowedEmails')
          .doc(normalizedEmail)
          .get();
      return doc.exists ? doc.data() : null;
    } catch (e) {
      debugPrint('Allowed email check failed: $e');
      return null;
    }
  }

  Future<void> _applyAllowedEmailEntitlement(
    Map<String, dynamic>? allowData,
  ) async {
    if (allowData == null || !allowData.containsKey('plan_type')) return;

    final planType = allowData['plan_type']?.toString();
    if (planType != 'none' && planType != 'friends' && planType != 'master') {
      return;
    }
    final entitledPlanType = planType!;

    final data = await UserDataService.load();
    var changed = false;

    if (data.planType != entitledPlanType) {
      data.planType = entitledPlanType;
      changed = true;
    }

    final planExpiresAt = _parseNullableDate(allowData['plan_expires_at']);
    if (data.planExpiresAt?.toIso8601String() !=
        planExpiresAt?.toIso8601String()) {
      data.planExpiresAt = planExpiresAt;
      changed = true;
    }

    final ownedCoaches = _stringListFromValue(allowData['owned_coaches']);
    if (ownedCoaches != null && !listEquals(data.ownedCoaches, ownedCoaches)) {
      data.ownedCoaches = ownedCoaches;
      changed = true;
    }

    final ownedCoachExpiresAt = _coachExpiryMapFromValue(
      allowData['owned_coach_expires_at'],
    );
    if (ownedCoachExpiresAt != null &&
        !_expiryMapsEqual(data.ownedCoachExpiresAt, ownedCoachExpiresAt)) {
      data.ownedCoachExpiresAt = ownedCoachExpiresAt;
      changed = true;
    }

    if (changed) {
      await UserDataService.save(data);
    }
  }

  DateTime? _parseNullableDate(Object? value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    return DateTime.tryParse(value.toString());
  }

  List<String>? _stringListFromValue(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList(growable: true);
    }
    return null;
  }

  Map<String, DateTime?>? _coachExpiryMapFromValue(Object? value) {
    if (value is! Map) return null;
    return value.map(
      (key, expiry) => MapEntry(key.toString(), _parseNullableDate(expiry)),
    );
  }

  bool _expiryMapsEqual(
    Map<String, DateTime?> left,
    Map<String, DateTime?> right,
  ) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key)) return false;
      if (right[entry.key]?.toIso8601String() !=
          entry.value?.toIso8601String()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _signOutAuthOnly() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  Future<void> _syncNotificationsSafely() async {
    try {
      await NotificationService().syncDailyMorningCall();
    } catch (e) {
      debugPrint('Morning notification sync skipped: $e');
    }
    try {
      await NotificationService().disableNightCallReminders();
    } catch (e) {
      debugPrint('Night notification cleanup skipped: $e');
    }
    try {
      await NotificationService().syncCoreReminders();
    } catch (e) {
      debugPrint('Core reminder sync skipped: $e');
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _signOutAuthOnly();
    UserDataService.clearCache();
    MemoryService().clearCache();
    FreeAccessService.instance.clearCache();
    await TasksSyncService.clearCache();
  }
}

class AuthAccessDeniedException implements Exception {
  const AuthAccessDeniedException();

  @override
  String toString() => '등록된 이메일 계정만 이용할 수 있습니다.';
}
