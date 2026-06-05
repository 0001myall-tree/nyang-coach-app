import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';

// AuthService를 전역적으로 제공하는 프로바이더
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

// 유저의 로그인 상태(인증 상태)를 실시간으로 감지하는 스트림 프로바이더
final authStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});
