import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_data.dart';
import 'apple_calendar_sync_service.dart';
import 'widget_sync_service.dart';

class TasksSyncService {
  static Timer? _syncTimer;
  static const _criticalDataKeys = {
    'nyang_tasks',
    'nyang_core_tasks',
    'nyang_schedules',
    'nyang_history',
    'nyang_visions',
    'nyang_today_tasks_by_date',
    // 습관과 그 완료 기록. 빠져 있던 동안에는 습관을 완료할 때마다 실시간
    // 리스너가 오늘 기록을 옛 값으로 되돌렸고, 그 되돌림이 목록 전체를 다시
    // 읽게 만들어 방금 민 완료가 없던 일이 됐다.
    'nyang_habits',
    'nyang_habit_logs',
    'nyang_morning_call_enabled',
    'nyang_morning_call_time',
    'nyang_morning_call_coach',
    'nyang_premium_min_sleep_time',
    'nyang_premium_sleep_duration',
    'nyang_premium_routines',
    // 프렌즈 코치가 설문으로 받아둔 생활 맥락. 기기를 바꿔도 다시 묻지
    // 않으려면 실려야 한다.
    'nyang_life_pattern',
    // 주간 코치 한마디 캐시. 빠져 있던 동안에는 방금 만든 한마디를 실시간
    // 리스너가 옛 값으로 되돌렸고, 기록탭에 들어갈 때마다 다시 만들어졌다.
    // 만드는 데 API를 쓰기 때문에 들어갈 때마다 비용이 나갔다.
    'nyang_coach_weekly_feedback_nyang_halbae',
  };

  /// 접두어로만 알 수 있는 핵심 데이터. 코치마다 키가 갈라져서 위 목록에
  /// 하나씩 적어둘 수가 없다.
  ///
  /// 채팅 기록이 보호를 못 받던 동안에는, 방금 한 대화가 4초 뒤 업로드를
  /// 기다리는 사이에 도착한 클라우드 스냅샷에 옛 값으로 덮여 사라졌다.
  /// 스냅샷은 바뀐 항목만 보는 게 아니라 전부 훑기 때문에, 다른 기기에서
  /// 할 일 하나가 바뀌기만 해도 오래된 대화가 딸려 와 새 대화를 지웠다.
  static const _criticalKeyPrefixes = {
    'nyang_chat_history_',
    'nyang_chat_archive_',
  };

  /// 오래된 클라우드 값이 덮어써서는 안 되는 키.
  @visibleForTesting
  static bool isCriticalKey(String key) =>
      _criticalDataKeys.contains(key) ||
      _criticalKeyPrefixes.any(key.startsWith);

  /// 기기 로컬 전용 키. 클라우드에 백업/복원하지 않는다.
  /// ('이 기기가 첫 복원을 마쳤는가'는 기기별 사실이라, 클라우드에서 true를
  /// 물려받으면 새 기기의 덮어쓰기 보호가 무력화된다.)
  static const _localOnlyKeys = {'nyang_has_synced_from_cloud'};

  /// 로컬에서 막 수정됐지만 아직 클라우드로 업로드되지 않은 키.
  /// 이 키들은 클라우드 스냅샷/다운로드가 로컬을 덮어쓰지 못하게 막아,
  /// 방금 저장한 값(예: 메모)이 오래된 클라우드 데이터로 사라지는 것을 방지한다.
  static final Set<String> _pendingUploadKeys = {};

  /// 접두어로 걸리는 핵심 데이터도 업로드 대기 중인지.
  /// [_pendingUploadKeys]와 생애주기가 같다.
  static bool _criticalPrefixesPending = false;

  /// 클라우드 값이 이 키의 로컬 값을 덮어써도 되는지.
  static bool _isPendingUpload(String key) =>
      _pendingUploadKeys.contains(key) ||
      (_criticalPrefixesPending && _criticalKeyPrefixes.any(key.startsWith));

  static void scheduleSyncToCloud({
    Duration delay = const Duration(seconds: 4),
  }) {
    if (FirebaseAuth.instance.currentUser == null) return;
    // 업로드가 확정되기 전까지 핵심 데이터를 "로컬이 최신" 상태로 표시한다.
    _pendingUploadKeys.addAll(_criticalDataKeys);
    _criticalPrefixesPending = true;
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
      final hasSyncedFromCloud =
          prefs.getBool('nyang_has_synced_from_cloud') ?? false;

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
        if (_localOnlyKeys.contains(key)) continue;

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
              isCriticalKey(key) &&
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
          if (key.startsWith('nyang_') &&
              key != 'nyang_user_data' &&
              (_localOnlyKeys.contains(key) || !keys.contains(key))) {
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
      // 업로드가 확정됐으므로 "로컬 최신" 표시를 해제한다.
      // (removeAll(keys)를 쓰면 로컬에 아직 없는 키가 pending에 영원히 남아
      // 클라우드 복원을 계속 막는 누수가 생긴다.)
      _pendingUploadKeys.clear();
      _criticalPrefixesPending = false;
      debugPrint('✅ TasksSyncService: 로컬 데이터를 클라우드에 성공적으로 백업했습니다.');
    } catch (e) {
      debugPrint('❌ TasksSyncService syncToCloud 오류: $e');
    }
  }

  /// syncFromCloud를 재시도 포함으로 실행한다. 각 시도는 12초 타임아웃이며,
  /// 일시적 네트워크 문제로 첫 복원이 실패해 빈 화면으로 진입하는 것을 줄인다.
  static Future<Map<String, dynamic>> syncFromCloudWithRetry({
    int maxAttempts = 2,
  }) async {
    Map<String, dynamic> diag = {'status': 'ERROR', 'message': 'NOT_ATTEMPTED'};
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        diag = await syncFromCloud().timeout(
          const Duration(seconds: 12),
          onTimeout: () => {'status': 'ERROR', 'message': 'TIMEOUT'},
        );
      } catch (e) {
        diag = {'status': 'ERROR', 'message': e.toString()};
      }
      if (diag['status'] == 'SUCCESS' || diag['status'] == 'EMPTY') return diag;
      if (attempt < maxAttempts) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return diag;
  }

  static Future<Map<String, dynamic>> syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return {'status': 'ERROR', 'message': 'NOT_LOGGED_IN'};
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
        if (_isPendingUpload(key)) continue;

        if (_localOnlyKeys.contains(key)) continue;

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
      unawaited(
        AppleCalendarSyncService.instance.syncAll(pullExternalChanges: false),
      );
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
        .listen(
          (snapshot) async {
            final prefs = await SharedPreferences.getInstance();
            bool changed = false;

            for (final doc in snapshot.docs) {
              final key = doc.id;
              final data = doc.data();

              // 방금 로컬에서 수정돼 아직 업로드 대기 중인 키는 덮어쓰지 않는다.
              // (오래된 클라우드 스냅샷이 방금 저장한 메모 등을 지우는 것을 방지)
              if (_isPendingUpload(key)) continue;
              if (_localOnlyKeys.contains(key)) continue;

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
              debugPrint(
                '🔔 TasksSyncService: Firestore 변경 감지되어 로컬 데이터 동기화 완료!',
              );
              await WidgetSyncService.syncFromStoredTasks();
              unawaited(
                AppleCalendarSyncService.instance.syncAll(
                  pullExternalChanges: false,
                ),
              );
              onDataChanged();
            }
          },
          onError: (e) {
            debugPrint('❌ TasksSyncService realTimeSync 오류: $e');
          },
        );
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
