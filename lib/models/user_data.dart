import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────
// UserData 모델
// ─────────────────────────────────────────────────────────────
class UserData {
  /// 'none' | 'friends' | 'master'
  String planType;

  /// 포인트 (리워드 등)
  int points;

  /// 개별 구매한 코치 ID 목록
  List<String> ownedCoaches;

  /// 개별 구매한 코치별 만료일 (구매 시점부터 1년)
  Map<String, DateTime?> ownedCoachExpiresAt;

  /// 플랜 만료일 (null = 영구)
  DateTime? planExpiresAt;

  /// 선택한 코치 ID
  String? selectedCoachId;

  UserData({
    this.planType = 'none',
    this.points = 0,
    List<String>? ownedCoaches,
    Map<String, DateTime?>? ownedCoachExpiresAt,
    this.planExpiresAt,
    this.selectedCoachId,
  }) : ownedCoaches = ownedCoaches ?? [],
       ownedCoachExpiresAt = ownedCoachExpiresAt ?? {};

  // ── 직렬화 ────────────────────────────────────────────────
  Map<String, dynamic> toJson() => {
    'plan_type': planType,
    'points': points,
    'owned_coaches': ownedCoaches,
    'owned_coach_expires_at': ownedCoachExpiresAt.map(
      (key, value) => MapEntry(key, value?.toIso8601String()),
    ),
    'plan_expires_at': planExpiresAt?.toIso8601String(),
    'selected_coach_id': selectedCoachId,
  };

  factory UserData.fromJson(Map<String, dynamic> j) => UserData(
    planType: j['plan_type'] ?? 'none',
    points: (j['points'] ?? 0) as int,
    ownedCoaches: List<String>.from(j['owned_coaches'] ?? []),
    ownedCoachExpiresAt: ((j['owned_coach_expires_at'] as Map?) ?? {}).map(
      (key, value) => MapEntry(
        key.toString(),
        value == null ? null : DateTime.tryParse(value.toString()),
      ),
    ),
    planExpiresAt: j['plan_expires_at'] != null
        ? DateTime.tryParse(j['plan_expires_at'])
        : null,
    selectedCoachId: j['selected_coach_id'],
  );

  // ── 권한 헬퍼 ─────────────────────────────────────────────

  /// 플랜이 현재 유효한지 (plan_type != 'none' && 만료 전)
  bool get isPlanActive {
    if (planType == 'none') return false;
    if (planExpiresAt == null) return true; // 만료일 미설정 = 영구
    return planExpiresAt!.isAfter(DateTime.now());
  }

  /// 특정 코치에 접근 가능한지
  /// 1. 냥냥코치(cat): 누구나 무료 입장
  /// 2. 비서코치(sec_male/sec_female): master 플랜 구독자만
  /// 3. 나머지 friends 코치: friends/master 플랜 구독자 중 해당 코치를 구매한 사람만
  bool canAccessCoach(String coachId) {
    if (coachId == 'cat') return true;
    if (!isPlanActive) return false;
    if (coachId == 'sec_male' || coachId == 'sec_female') {
      return planType == 'master';
    }
    // 나머지 friends 코치 — 플랜 활성 + 개별 구매 필요
    return isOwnedCoachActive(coachId);
  }

  bool isOwnedCoachActive(String coachId) {
    if (!ownedCoaches.contains(coachId)) return false;
    final expiresAt = ownedCoachExpiresAt[coachId];
    if (expiresAt == null) return true;
    return expiresAt.isAfter(DateTime.now());
  }

  DateTime? ownedCoachExpiry(String coachId) => ownedCoachExpiresAt[coachId];

  String ownedCoachRemainingLabel(String coachId) {
    if (!ownedCoaches.contains(coachId)) return '미구매';
    final expiresAt = ownedCoachExpiresAt[coachId];
    if (expiresAt == null) return '이용 중';
    final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
    if (remaining <= 0) return '만료됨';
    return '$remaining일 남음';
  }
}

// ─────────────────────────────────────────────────────────────
// UserDataService — SharedPreferences CRUD & Firestore Sync
// ─────────────────────────────────────────────────────────────
class UserDataService {
  static const _key = 'nyang_user_data';

  static UserData? _cache;

  static Future<UserData> load() async {
    if (_cache != null) return _cache!;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    _cache = raw != null ? UserData.fromJson(jsonDecode(raw)) : UserData();
    return _cache!;
  }

  static Future<void> save(UserData data) async {
    _cache = data;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data.toJson()));

    // Firestore Sync
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': user.email,
          'loginEmail': user.email,
          'userData': data.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore UserData sync error: $e');
      }
    }
  }

  static Future<void> syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists &&
            doc.data() != null &&
            doc.data()!.containsKey('userData')) {
          final cloudData = UserData.fromJson(doc.data()!['userData']);
          _cache = cloudData;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_key, jsonEncode(cloudData.toJson()));
        }
      } catch (e) {
        debugPrint('Firestore UserData load error: $e');
      }
    }
  }

  /// 캐시 무효화 (테스트 등)
  static void clearCache() => _cache = null;

  // ── 편의 메서드 ───────────────────────────────────────────

  static Future<void> setPlan(String planType, {DateTime? expiresAt}) async {
    final data = await load();
    data.planType = planType;
    data.planExpiresAt = expiresAt;
    await save(data);
  }

  static Future<void> addOwnedCoach(String coachId) async {
    final data = await load();
    if (!data.ownedCoaches.contains(coachId)) {
      data.ownedCoaches.add(coachId);
    }
    data.ownedCoachExpiresAt[coachId] = DateTime.now().add(
      const Duration(days: 365),
    );
    await save(data);
  }

  static Future<void> addPoints(int delta) async {
    final data = await load();
    data.points = (data.points + delta).clamp(0, 999999);
    await save(data);
  }

  static Future<void> setSelectedCoach(String coachId) async {
    final data = await load();
    data.selectedCoachId = coachId;
    await save(data);
  }
}
