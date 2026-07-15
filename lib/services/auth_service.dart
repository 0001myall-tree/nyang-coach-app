import 'package:flutter/foundation.dart'; // kIsWeb 추가
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_data.dart';
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

      // Cloud Data Sync
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
        'girlfriend',
        'bro',
        'halmae',
        'sec_male',
        'sec_female',
      ],
    );
    await UserDataService.save(testData);
    await NotificationService().syncDailyMorningCall();
    await NotificationService().syncDailyNightCall();
    await NotificationService().syncCoreReminders();
  }

  Future<void> _syncAfterSignIn(UserCredential? cred) async {
    if (cred?.user == null) return;
    await UserDataService.syncFromCloud();
    await MemoryService().syncFromCloud();
    await TasksSyncService.syncFromCloud();
    await _syncNotificationsSafely();
  }

  Future<void> _syncNotificationsSafely() async {
    try {
      await NotificationService().syncDailyMorningCall();
    } catch (e) {
      debugPrint('Morning notification sync skipped: $e');
    }
    try {
      await NotificationService().syncDailyNightCall();
    } catch (e) {
      debugPrint('Night notification sync skipped: $e');
    }
    try {
      await NotificationService().syncCoreReminders();
    } catch (e) {
      debugPrint('Core reminder sync skipped: $e');
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    UserDataService.clearCache();
    MemoryService().clearCache();
    await TasksSyncService.clearCache();
  }
}
