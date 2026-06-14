import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_data.dart';
import 'widget_sync_service.dart';

class TasksSyncService {
  static Timer? _syncTimer;
  static const _criticalDataKeys = {
    'nyang_tasks',
    'nyang_core_tasks',
    'nyang_schedules',
    'nyang_history',
    'nyang_visions',
  };

  static void scheduleSyncToCloud({
    Duration delay = const Duration(seconds: 4),
  }) {
    if (FirebaseAuth.instance.currentUser == null) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(delay, () {
      syncToCloud();
    });
  }

  /// SharedPreferences에 저장된 'nyang_'으로 시작하는 모든 앱 데이터(할일, 목표, 채팅기록 등)를
  /// Firestore의 users/{uid}/appData/{key} 경로에 백업합니다.
  static Future<void> syncToCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userData = await UserDataService.load();
    if (!userData.isPlanActive) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final batch = FirebaseFirestore.instance.batch();

      final keys = prefs.getKeys().where((k) => k.startsWith('nyang_'));

      for (final key in keys) {
        if (key == 'nyang_user_data') continue; // UserDataService에서 별도 관리

        final value = prefs.get(key);
        if (value != null) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('appData')
              .doc(key);

          if (value is String &&
              _criticalDataKeys.contains(key) &&
              _isEmptyEncodedValue(value) &&
              await _hasNonEmptyCloudValue(docRef)) {
            debugPrint(
              '⚠️ TasksSyncService: 빈 로컬 데이터가 기존 클라우드 $key 값을 덮어쓰지 않도록 건너뜁니다.',
            );
            continue;
          }

          // String, bool, int, double, StringList 등 기본 타입 지원
          batch.set(docRef, {'value': value}, SetOptions(merge: true));
        }
      }

      await batch.commit();
      debugPrint('✅ TasksSyncService: 로컬 데이터를 클라우드에 성공적으로 백업했습니다.');
    } catch (e) {
      debugPrint('❌ TasksSyncService syncToCloud 오류: $e');
    }
  }

  /// Firestore에 백업된 앱 데이터를 불러와서 SharedPreferences에 덮어씁니다.
  /// 앱 재설치 후 첫 로그인 시 호출됩니다.
  static Future<void> syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await UserDataService.syncFromCloud();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appData')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ TasksSyncService: 클라우드에 백업된 데이터가 없습니다.');
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      for (final doc in snapshot.docs) {
        final key = doc.id;
        final data = doc.data();

        if (data.containsKey('value')) {
          final value = data['value'];
          if (value is String) {
            await prefs.setString(key, value);
          } else if (value is bool) {
            await prefs.setBool(key, value);
          } else if (value is int) {
            await prefs.setInt(key, value);
          } else if (value is double) {
            await prefs.setDouble(key, value);
          } else if (value is List) {
            await prefs.setStringList(
              key,
              value.map((item) => item.toString()).toList(),
            );
          }
        }
      }

      await WidgetSyncService.syncFromStoredTasks();
      debugPrint('✅ TasksSyncService: 클라우드 데이터를 로컬에 성공적으로 복원했습니다.');
    } catch (e) {
      debugPrint('❌ TasksSyncService syncFromCloud 오류: $e');
    }
  }

  static bool _isEmptyEncodedValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '[]' || trimmed == '{}';
  }

  static Future<bool> _hasNonEmptyCloudValue(
    DocumentReference<Map<String, dynamic>> docRef,
  ) async {
    final snapshot = await docRef.get();
    if (!snapshot.exists) return false;

    final value = snapshot.data()?['value'];
    if (value is String) {
      return !_isEmptyEncodedValue(value);
    }
    if (value is List) {
      return value.isNotEmpty;
    }
    return value != null;
  }
}
