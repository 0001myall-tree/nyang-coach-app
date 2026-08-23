import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../services/coach_id_service.dart';
import '../services/distraction_coach_quota.dart';

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

  factory UserData.fromJson(Map<String, dynamic> j) {
    final owned = List<String>.from(
      j['owned_coaches'] ?? [],
    ).map(CoachIdService.normalize).toSet().toList();
    final expires = <String, DateTime?>{};
    for (final entry in ((j['owned_coach_expires_at'] as Map?) ?? {}).entries) {
      final key = CoachIdService.normalize(entry.key.toString());
      expires[key] ??= entry.value == null
          ? null
          : DateTime.tryParse(entry.value.toString());
    }

    return UserData(
      planType: j['plan_type'] ?? 'none',
      points: (j['points'] ?? 0) as int,
      ownedCoaches: owned,
      ownedCoachExpiresAt: expires,
      planExpiresAt: j['plan_expires_at'] != null
          ? DateTime.tryParse(j['plan_expires_at'])
          : null,
      selectedCoachId: j['selected_coach_id'] == null
          ? null
          : CoachIdService.normalize(j['selected_coach_id'].toString()),
    );
  }

  // ── 권한 헬퍼 ─────────────────────────────────────────────

  /// 플랜이 현재 유효한지 (plan_type != 'none' && 만료 전)
  bool get isPlanActive {
    if (planType == 'none') return false;
    if (planExpiresAt == null) return true; // 만료일 미설정 = 영구
    return planExpiresAt!.isAfter(DateTime.now());
  }

  /// 특정 코치에 접근 가능한지
  /// 1. 냥냥코치(cat): 누구나 무료 입장
  /// 2. 마스터 코치(nyang_halbae/sec_female): master 플랜 구독자만
  /// 3. 나머지 friends 코치: friends/master 플랜 구독자 중 해당 코치를 구매한 사람만
  bool canAccessCoach(String coachId) {
    final normalizedCoachId = CoachIdService.normalize(coachId);
    if (normalizedCoachId == 'cat') return true;
    if (!isPlanActive) return false;
    if (CoachIdService.isMaster(normalizedCoachId)) {
      return planType == 'master';
    }
    // 나머지 friends 코치 — 플랜 활성 + 개별 구매 필요
    return isOwnedCoachActive(normalizedCoachId);
  }

  bool isOwnedCoachActive(String coachId) {
    final normalizedCoachId = CoachIdService.normalize(coachId);
    if (!ownedCoaches.contains(normalizedCoachId)) return false;
    final expiresAt = ownedCoachExpiresAt[normalizedCoachId];
    if (expiresAt == null) return true;
    return expiresAt.isAfter(DateTime.now());
  }

  DateTime? ownedCoachExpiry(String coachId) =>
      ownedCoachExpiresAt[CoachIdService.normalize(coachId)];

  String ownedCoachRemainingLabel(String coachId) {
    final normalizedCoachId = CoachIdService.normalize(coachId);
    if (!ownedCoaches.contains(normalizedCoachId)) return '미구매';
    final expiresAt = ownedCoachExpiresAt[normalizedCoachId];
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
    await _publishDistractionCoachTier(data);

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
          await _publishDistractionCoachTier(cloudData);
        }
      } catch (e) {
        debugPrint('Firestore UserData load error: $e');
      }
    }
  }

  /// 딴짓 방지 코칭이 일정마다 붙는 등급인지를 적어둔다.
  ///
  /// 안드로이드는 앱이 꺼진 사이에 냥냥이를 내보낼지 판단하는데, 그때는
  /// 사용자 정보를 읽을 수 없다. 등급이 바뀔 수 있는 자리는 전부 [save]와
  /// [syncFromCloud]를 지나므로 여기 한 곳에서 알려준다.
  static Future<void> _publishDistractionCoachTier(UserData data) =>
      DistractionCoachQuota.setUnlimited(
        data.isPlanActive && data.planType == 'master',
      );

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
    final normalizedCoachId = CoachIdService.normalize(coachId);
    if (!data.ownedCoaches.contains(normalizedCoachId)) {
      data.ownedCoaches.add(normalizedCoachId);
    }
    data.ownedCoachExpiresAt[normalizedCoachId] = DateTime.now().add(
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
    data.selectedCoachId = CoachIdService.normalize(coachId);
    await save(data);
  }
}
