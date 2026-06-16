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

    try {
      final prefs = await SharedPreferences.getInstance();
      final batch = FirebaseFirestore.instance.batch();

      final keys = prefs.getKeys().where((k) => k.startsWith('nyang_'));
      final hasSyncedFromCloud = prefs.getBool('nyang_has_synced_from_cloud') ?? false;

      for (final key in keys) {
        if (key == 'nyang_user_data') continue; // UserDataService에서 별도 관리

        final value = prefs.get(key);
        if (value != null) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('appData')
              .doc(key);

          if (!hasSyncedFromCloud &&
              value is String &&
              _criticalDataKeys.contains(key) &&
              _isEmptyEncodedValue(value) &&
              await _hasNonEmptyCloudValue(docRef)) {
            debugPrint(
              '⚠️ TasksSyncService: 첫 동기화 완료 전 빈 로컬 데이터가 기존 클라우드 $key 값을 덮어쓰지 않도록 건너뜁니다.',
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

  static Future<Map<String, dynamic>> syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {
        'status': 'ERROR',
        'message': 'NOT_LOGGED_IN',
      };
    }

    final diag = <String, dynamic>{
      'uid': user.uid,
      'email': user.email ?? 'no-email',
      'doc_count': 0,
      'keys_found': <String>[],
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      await UserDataService.syncFromCloud();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appData')
          .get();

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ TasksSyncService: 클라우드에 백업된 데이터가 없습니다.');
        diag['status'] = 'EMPTY';
        diag['message'] = 'EMPTY_CLOUD_DATA';
        await prefs.setBool('nyang_has_synced_from_cloud', true);
        return diag;
      }

      diag['doc_count'] = snapshot.docs.length;
      final foundKeys = <String>[];

      for (final doc in snapshot.docs) {
        final key = doc.id;
        final data = doc.data();
        foundKeys.add(key);

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

      diag['keys_found'] = foundKeys;
      await WidgetSyncService.syncFromStoredTasks();
      debugPrint('✅ TasksSyncService: 클라우드 데이터를 로컬에 성공적으로 복원했습니다.');
      diag['status'] = 'SUCCESS';
      diag['message'] = 'OK';
      await prefs.setBool('nyang_has_synced_from_cloud', true);
      return diag;
    } catch (e) {
      debugPrint('❌ TasksSyncService syncFromCloud 오류: $e');
      diag['status'] = 'ERROR';
      diag['message'] = e.toString();
      return diag;
    }
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nyang_has_synced_from_cloud');
    await prefs.remove('nyang_tasks');
    await prefs.remove('nyang_core_tasks');
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
