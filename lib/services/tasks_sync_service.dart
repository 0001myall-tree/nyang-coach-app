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

  /// 로컬에서 막 수정됐지만 아직 클라우드로 업로드되지 않은 키.
  /// 이 키들은 클라우드 스냅샷/다운로드가 로컬을 덮어쓰지 못하게 막아,
  /// 방금 저장한 값(예: 메모)이 오래된 클라우드 데이터로 사라지는 것을 방지한다.
  static final Set<String> _pendingUploadKeys = {};

  static void scheduleSyncToCloud({
    Duration delay = const Duration(seconds: 4),
  }) {
    if (FirebaseAuth.instance.currentUser == null) return;
    // 업로드가 확정되기 전까지 핵심 데이터를 "로컬이 최신" 상태로 표시한다.
    _pendingUploadKeys.addAll(_criticalDataKeys);
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

      final keys = prefs.getKeys().where((k) => k.startsWith('nyang_')).toSet();
      final hasSyncedFromCloud = prefs.getBool('nyang_has_synced_from_cloud') ?? false;

      // Firestore의 현재 백업된 데이터 목록 가져오기
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appData')
          .get();
      final cloudKeys = snapshot.docs.map((doc) => doc.id).toSet();

      // 1. 로컬에 존재하는 데이터 업로드 및 업데이트
      for (final key in keys) {
        if (key == 'nyang_user_data') continue; // UserDataService에서 별도 관리

        final value = prefs.get(key);
        if (value != null) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('appData')
              .doc(key);

          // 첫 동기화 완료 전 기존 클라우드 값을 빈 값으로 덮어쓰지 않도록 보호
          if (!hasSyncedFromCloud &&
              value is String &&
              _criticalDataKeys.contains(key) &&
              _isEmptyEncodedValue(value) &&
              cloudKeys.contains(key)) {
            
            final doc = snapshot.docs.firstWhere((d) => d.id == key);
            final cloudVal = doc.data()['value'];
            bool cloudIsEmpty = true;
            if (cloudVal is String) {
              cloudIsEmpty = _isEmptyEncodedValue(cloudVal);
            } else if (cloudVal is List) {
              cloudIsEmpty = cloudVal.isEmpty;
            } else {
              cloudIsEmpty = cloudVal == null;
            }

            if (!cloudIsEmpty) {
              debugPrint(
                '⚠️ TasksSyncService: 첫 동기화 완료 전 빈 로컬 데이터가 기존 클라우드 $key 값을 덮어쓰지 않도록 건너뜁니다.',
              );
              continue;
            }
          }

          // String, bool, int, double, StringList 등 기본 타입 지원
          batch.set(docRef, {'value': value}, SetOptions(merge: true));
        }
      }

      // 2. 로컬에서 삭제된 데이터를 클라우드에서도 삭제 (첫 동기화가 완료된 상태에서만 안전하게 실행)
      if (hasSyncedFromCloud) {
        for (final key in cloudKeys) {
          if (key.startsWith('nyang_') && key != 'nyang_user_data' && !keys.contains(key)) {
            final docRef = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('appData')
                .doc(key);
            batch.delete(docRef);
            debugPrint('🗑️ TasksSyncService: 로컬에서 삭제된 $key 키를 클라우드에서도 삭제합니다.');
          }
        }
      }

      await batch.commit();
      // 업로드가 확정됐으므로 방금 올린 키들의 "로컬 최신" 표시를 해제한다.
      _pendingUploadKeys.removeAll(keys);
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

        // 업로드 대기 중인(로컬이 더 최신인) 키는 클라우드 값으로 덮지 않는다.
        if (_pendingUploadKeys.contains(key)) continue;

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

  static StreamSubscription<QuerySnapshot>? _realTimeSubscription;

  static void startRealTimeSync(String uid, VoidCallback onDataChanged) {
    _realTimeSubscription?.cancel();
    _realTimeSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('appData')
        .snapshots()
        .listen((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      bool changed = false;

      for (final doc in snapshot.docs) {
        final key = doc.id;
        final data = doc.data();

        // 방금 로컬에서 수정돼 아직 업로드 대기 중인 키는 덮어쓰지 않는다.
        // (오래된 클라우드 스냅샷이 방금 저장한 메모 등을 지우는 것을 방지)
        if (_pendingUploadKeys.contains(key)) continue;

        if (data.containsKey('value')) {
          final value = data['value'];
          final localValue = prefs.get(key);

          if (localValue != value) {
            changed = true;
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
      }

      if (changed) {
        debugPrint('🔔 TasksSyncService: Firestore 변경 감지되어 로컬 데이터 동기화 완료!');
        await WidgetSyncService.syncFromStoredTasks();
        onDataChanged();
      }
    }, onError: (e) {
      debugPrint('❌ TasksSyncService realTimeSync 오류: $e');
    });
  }

  static void stopRealTimeSync() {
    _realTimeSubscription?.cancel();
    _realTimeSubscription = null;
  }

  static bool _isEmptyEncodedValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '[]' || trimmed == '{}';
  }
}
