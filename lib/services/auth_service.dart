import 'package:flutter/foundation.dart'; // kIsWeb 추가
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_data.dart';
import '../services/memory_service.dart';
import '../services/tasks_sync_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  // 유저 상태 스트림 (로그인/로그아웃 상태 변화 감지)
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 현재 유저 가져오기
  User? get currentUser => _auth.currentUser;

  // 구글 로그인
  Future<UserCredential?> signInWithGoogle() async {
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

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        cred = await _auth.signInWithCredential(credential);
      }
      
      // Cloud Data Sync
      if (cred?.user != null) {
        await UserDataService.syncFromCloud();
        await MemoryService().syncFromCloud();
        await TasksSyncService.syncFromCloud();
      }
      
      return cred;
    } catch (e) {
      debugPrint("Google Sign-In Error: $e");
      return null;
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
    UserDataService.clearCache();
    MemoryService().clearCache();
  }
}
