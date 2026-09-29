import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_data.dart';
import 'apple_calendar_sync_service.dart';
import 'chat_store.dart';
import 'life_pattern_service.dart';
import 'sync_base.dart';
import 'task_completion_service.dart';
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
    // 지난주 완료율. 기록은 이레치만 남아서 지난주를 다시 셀 수가 없다.
    // 이게 안 실리면 기기를 바꾼 주에는 올랐는지 내렸는지를 모른 채,
    // 코치가 낮은 숫자를 첫 문장에 그대로 박는다.
    'nyang_weekly_completion_pct',
    // 적극 코칭이 따라붙는 중인 것들. 방금 "8시에 할게"라고 한 약속이 옛
    // 스냅샷에 덮이면, 8시에 아무 일도 일어나지 않는다.
    'nyang_active_coaching',
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

  /// 이 기기에 담긴 대화가 누구 것인지.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다 — 그 접두어는 클라우드 복원이 덮어쓰는데,
  /// 이건 이 기기에 무엇이 들어 있는지를 적는 자리라 덮이면 안 된다.
  ///
  /// 로그아웃은 대화를 지우지 않는다. 그래서 한 기기에서 계정을 바꿔 로그인하면
  /// 앞사람 대화가 남아 있고, 합치기는 그것을 새 계정 대화에 섞어 서버로
  /// 올려버린다. 주인이 다르면 합치지 않고 서버 것으로 갈아치운다.
  static const String chatOwnerKey = 'chat_owner_uid';

  /// 이 기기의 대화를 지금 로그인한 사람 것으로 볼 수 있는지.
  ///
  /// 주인을 아직 안 적어둔 기기(새로 깐 기기, 이 기능 이전부터 쓰던 기기)는
  /// 지금 사람 것으로 본다. 그 기기의 대화는 원래 이 계정 것이었다.
  static bool _chatBelongsToUser(SharedPreferences prefs, String uid) {
    final owner = prefs.getString(chatOwnerKey);
    return owner == null || owner == uid;
  }

  /// 이 계정 서버에 없는 대화를 이 기기에서 지운다. 주인이 바뀐 기기에서만 쓴다.
  ///
  /// 로그아웃이 대화를 지우지 않아서, 계정을 바꿔 로그인하면 앞사람이 쓰던
  /// 코치의 대화가 그대로 남아 보였다. 새 사람의 서버에 있는 것은 받아온
  /// 값으로 이미 갈렸으니 건드리지 않는다.
  static Future<void> _dropChatNotIn(
    SharedPreferences prefs,
    Set<String> cloudKeys,
  ) async {
    final stale = prefs
        .getKeys()
        .where((key) => ChatStore.isChatKey(key) && !cloudKeys.contains(key))
        .toList();
    for (final key in stale) {
      await prefs.remove(key);
    }
  }

  /// 대화는 덮지 않고 합친다. 겹치면 이 기기 것을 남긴다.
  ///
  /// 값에 "언제 적은 것"이라는 표시가 없어서 서버는 새 것과 옛 것을 가릴 수
  /// 없다. 그래서 나중에 올린 쪽이 무조건 이겼다 — 며칠 안 켠 기기를 켜면 그
  /// 낡은 뭉치가 그동안의 대화를 지웠다. 대화는 덧붙이기만 하는 목록이라,
  /// 최신을 가리는 것보다 합치는 것이 답이다.
  static String _mergedChatValue({
    required String? localRaw,
    required Object? cloudValue,
  }) => ChatStore.mergedValue(
    ChatStore.decode(localRaw),
    ChatStore.decode(cloudValue is String ? cloudValue : null),
  );

  /// 이 기기가 마지막으로 클라우드와 맞춘 값의 지문([SyncBase]).
  ///
  /// 메모리에 한 벌만 두고 모두가 같은 것을 고친다. 올리기와 실시간 받기가
  /// 각자 읽어 고쳐 쓰면, 한쪽이 적은 것을 다른 쪽이 옛 값으로 덮는다.
  static Map<String, String>? _bases;
  static String? _basesUid;

  static Map<String, String> _basesFor(SharedPreferences prefs, String uid) {
    if (_bases == null || _basesUid != uid) {
      _bases = SyncBase.read(prefs, uid);
      _basesUid = uid;
    }
    return _bases!;
  }

  static Future<void> _saveBases(SharedPreferences prefs, String uid) async {
    final bases = _bases;
    if (bases == null || _basesUid != uid) return;
    await SyncBase.write(prefs, uid, bases);
  }

  /// 대화와 설문 답은 합치는 쪽이라 세 값 견주기를 거치지 않는다.
  static bool _mergedKey(String key) =>
      ChatStore.isChatKey(key) || key == LifePatternService.storeKey;

  /// 클라우드 값을 이 기기에 적는다.
  static Future<void> _writeLocal(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
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

  /// 실시간 받기가 화면에 알리는 길. 올리기 도중 클라우드 값을 받았을 때도
  /// 같은 길로 알린다 — 화면이 옛 목록을 쥔 채로 저장하면 받은 값이 다시
  /// 옛 것으로 올라간다.
  static VoidCallback? _onDataChanged;

  /// 오래된 클라우드 값이 덮어써서는 안 되는 키.
  @visibleForTesting
  static bool isCriticalKey(String key) =>
      _criticalDataKeys.contains(key) ||
      _criticalKeyPrefixes.any(key.startsWith);

  /// 기기 로컬 전용 키. 클라우드에 백업/복원하지 않는다.
  /// ('이 기기가 첫 복원을 마쳤는가'는 기기별 사실이라, 클라우드에서 true를
  /// 물려받으면 새 기기의 덮어쓰기 보호가 무력화된다.)
  ///
  /// 애플 캘린더 이벤트 표도 마찬가지다. 그 안의 id는 그 아이폰의 EventKit이
  /// 발급한 것이라 다른 기기에서는 뜻이 없는데, 접두어 때문에 클라우드로
  /// 오르내렸다. 옛 표가 아이폰으로 내려오면 이미 없는 이벤트를 찾게 되고,
  /// 안 잡힌 루틴은 그날이 쉬기로 찍혔다. 지금은 접두어 없는 자리로 옮겼고,
  /// 여기 남은 옛 이름은 클라우드에 있는 것을 지우기 위한 것이다.
  static const _localOnlyKeys = {
    'nyang_has_synced_from_cloud',
    'nyang_apple_calendar_event_map',
  };

  /// 아직 클라우드로 못 올린 로컬 변경이 남아 있는지. 앱을 껐다 켜도 살아남아야
  /// 하므로 prefs에 적는다.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다 — 그 접두어는 클라우드 복원이 덮어쓰는데,
  /// 이건 이 기기에서 방금 일어난 사실이라 덮이면 안 된다.
  static const String pendingUploadFlagKey = 'pending_cloud_upload';

  /// 로그인 전에 밀린 업로드가 있으면 지금 올린다.
  ///
  /// 클라우드에서 받아오기 전에 불러야 한다. 안 그러면 옛 클라우드 값이 아직
  /// 안 올라간 로컬 값을 덮어쓰고, 그 대화는 양쪽에서 사라진다.
  ///
  /// 무엇을 올릴지는 [syncToCloud]가 [SyncBase]로 가린다. 이 표시를 단 채
  /// 며칠 꺼져 있던 폰이라도, 그동안 클라우드가 바뀐 것은 올리지 않고 받는다.
  static Future<void> flushPendingUpload() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(pendingUploadFlagKey) ?? false)) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    await syncToCloud();
  }

  /// 업로드를 예약한다.
  ///
  /// 로그인 전이어도 그냥 돌아서지 않는다. 자정 정리는 로그인 복원보다 먼저
  /// 끝나는 일이 잦은데, 여기서 아무 표시도 안 남기면 잠시 뒤 도착하는 클라우드
  /// 복원이 방금 보관함으로 옮긴 어제 대화를 정리 이전 값으로 되돌린다.
  /// 올리지도 못했으니 클라우드에도 없어서, 양쪽에서 사라진다.
  static void scheduleSyncToCloud({
    Duration delay = const Duration(seconds: 4),
  }) {
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(pendingUploadFlagKey, true),
      ),
    );
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
      final chatIsOurs = _chatBelongsToUser(prefs, user.uid);
      final bases = _basesFor(prefs, user.uid);
      final settled = <String, String>{};
      final gone = <String>{};
      var tookCloud = false;

      // 1. 로컬에 존재하는 데이터 업로드 및 업데이트
      for (final key in keys) {
        if (key == 'nyang_user_data') continue; // UserDataService에서 별도 관리
        if (_localOnlyKeys.contains(key)) continue;

        // 앞사람 대화가 남아 있는 기기다. 그걸 이 계정에 올리면 두 사람 대화가
        // 섞인다. 받아오는 쪽에서 서버 것으로 갈아치울 테니 여기서는 건너뛴다.
        if (!chatIsOurs && ChatStore.isChatKey(key)) continue;

        final value = prefs.get(key);
        if (value != null) {
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .collection('appData')
              .doc(key);

          // 대화는 서버에 있던 것과 합쳐서 올린다. 이 기기가 며칠 뒤처져 있어도
          // 그동안 다른 기기에서 한 대화를 지우지 않는다.
          if (ChatStore.isChatKey(key) && value is String) {
            final cloudDoc = cloudKeys.contains(key)
                ? snapshot.docs.firstWhere((d) => d.id == key)
                : null;
            final merged = _mergedChatValue(
              localRaw: value,
              cloudValue: cloudDoc?.data()['value'],
            );
            if (merged != value) await prefs.setString(key, merged);
            batch.set(docRef, {'value': merged}, SetOptions(merge: true));
            continue;
          }

          // 설문 답도 합쳐서 올린다. 이 기기가 뒤처져 있어도 다른 기기에서
          // 답한 문항을 지우지 않는다.
          if (key == LifePatternService.storeKey && value is String) {
            final cloudDoc = cloudKeys.contains(key)
                ? snapshot.docs.firstWhere((d) => d.id == key)
                : null;
            final cloudValue = cloudDoc?.data()['value'];
            final merged = LifePatternService.mergedValue(
              value,
              cloudValue is String ? cloudValue : null,
            );
            if (merged != value) await prefs.setString(key, merged);
            batch.set(docRef, {'value': merged}, SetOptions(merge: true));
            continue;
          }

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

          // 무조건 올리지 않는다. 며칠 꺼져 있던 기기의 값은 이 기기에선 멀쩡해
          // 보여도 클라우드에선 한참 옛 것이다([SyncBase]).
          final cloudDoc = cloudKeys.contains(key)
              ? snapshot.docs.firstWhere((d) => d.id == key)
              : null;
          final cloudValue = cloudDoc?.data()['value'];
          final localPrint = SyncBase.fingerprint(value);
          final cloudPrint = cloudDoc == null
              ? null
              : SyncBase.fingerprint(cloudValue);
          switch (SyncBase.decide(
            local: localPrint,
            cloud: cloudPrint,
            base: bases[key],
          )) {
            case SyncMove.same:
              settled[key] = localPrint!;
            case SyncMove.push:
              batch.set(docRef, {'value': value}, SetOptions(merge: true));
              settled[key] = localPrint!;
            case SyncMove.takeCloud:
              debugPrint('↩️ TasksSyncService: $key 은 클라우드가 더 새것이라 받아옵니다.');
              await _writeLocal(prefs, key, cloudValue);
              settled[key] = cloudPrint!;
              tookCloud = true;
            case SyncMove.deleteCloud:
              break;
          }
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
            // 이 기기에 없다고 지운 것인지, 다른 기기에서 새로 생긴 것인지
            // 가린다. 예전에는 다 지웠는데, 옛 기기가 켜지면 그동안 새로 생긴
            // 것까지 없앴다. 대화는 오래된 날을 걷어내는 쪽이라 예전대로 둔다.
            final cloudValue = snapshot.docs
                .firstWhere((d) => d.id == key)
                .data()['value'];
            if (!_localOnlyKeys.contains(key) &&
                !_mergedKey(key) &&
                cloudValue != null) {
              final move = SyncBase.decide(
                local: null,
                cloud: SyncBase.fingerprint(cloudValue),
                base: bases[key],
              );
              if (move != SyncMove.deleteCloud) {
                await _writeLocal(prefs, key, cloudValue);
                settled[key] = SyncBase.fingerprint(cloudValue)!;
                tookCloud = true;
                continue;
              }
              gone.add(key);
            }
            batch.delete(docRef);
            debugPrint('🗑️ TasksSyncService: 로컬에서 삭제된 $key 키를 클라우드에서도 삭제합니다.');
          }
        }
      }

      await batch.commit();
      // 올라간 것이 확정된 뒤에 적는다. 실패했는데 적어두면 다음에 이 기기
      // 값을 "이미 맞춘 것"으로 보고 클라우드 것을 받아버린다.
      bases.addAll(settled);
      gone.forEach(bases.remove);
      await _saveBases(prefs, user.uid);
      if (tookCloud) {
        await TaskCompletionService.markChangedNow();
        _onDataChanged?.call();
      }
      await prefs.remove(pendingUploadFlagKey);
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
      // 받아오기 전에, 못 올린 게 있으면 먼저 올린다. 순서가 뒤집히면 옛
      // 클라우드 값이 아직 안 올라간 로컬 값을 덮는다.
      await flushPendingUpload();
      await UserDataService.syncFromCloud();
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('appData')
          .get();

      final chatIsOurs = _chatBelongsToUser(prefs, user.uid);
      final bases = _basesFor(prefs, user.uid);

      if (snapshot.docs.isEmpty) {
        debugPrint('ℹ️ TasksSyncService: 클라우드에 백업된 데이터가 없습니다.');
        diag['status'] = 'EMPTY';
        diag['message'] = 'EMPTY_CLOUD_DATA';
        if (!chatIsOurs) await _dropChatNotIn(prefs, const {});
        await prefs.setString(chatOwnerKey, user.uid);
        await prefs.setBool('nyang_has_synced_from_cloud', true);
        return diag;
      }

      diag['doc_count'] = snapshot.docs.length;
      final foundKeys = <String>[];

      for (final doc in snapshot.docs) {
        final key = doc.id;
        final data = doc.data();
        foundKeys.add(key);

        // 대화는 합친다. 합치면 이 기기 말이 사라지지 않으므로, 업로드 대기
        // 여부를 볼 필요가 없다. 주인이 다른 기기에서만 갈아치운다.
        if (ChatStore.isChatKey(key)) {
          final cloudValue = data['value'];
          if (!chatIsOurs) {
            if (cloudValue is String) await prefs.setString(key, cloudValue);
            continue;
          }
          await prefs.setString(
            key,
            _mergedChatValue(
              localRaw: prefs.getString(key),
              cloudValue: cloudValue,
            ),
          );
          continue;
        }

        // 설문 답도 합친다. 문항 단위로 보므로 양쪽에서 답한 것이 다 남는다.
        if (key == LifePatternService.storeKey) {
          final cloudValue = data['value'];
          await prefs.setString(
            key,
            LifePatternService.mergedValue(
              prefs.getString(key),
              cloudValue is String ? cloudValue : null,
            ),
          );
          continue;
        }

        if (_localOnlyKeys.contains(key)) continue;
        if (!data.containsKey('value')) continue;

        // 이 기기가 고쳐서 아직 못 올린 것만 남기고 나머지는 받는다. 예전에는
        // "못 올린 게 있음" 표시 하나로 모든 핵심 데이터를 지켰는데, 그 표시를
        // 달고 며칠 꺼져 있던 폰은 옛 데이터 전부를 지키다 올려버렸다.
        final value = data['value'];
        if (value == null) continue;
        final cloudPrint = SyncBase.fingerprint(value)!;
        final move = SyncBase.decide(
          local: SyncBase.fingerprint(prefs.get(key)),
          cloud: cloudPrint,
          base: bases[key],
        );
        if (move == SyncMove.push) continue;
        if (move == SyncMove.takeCloud) await _writeLocal(prefs, key, value);
        bases[key] = cloudPrint;
      }
      await _saveBases(prefs, user.uid);

      diag['keys_found'] = foundKeys;
      // 앞사람 대화 중 이 계정 서버에 없는 것은 이 기기에서 지운다. 안 지우면
      // 새로 로그인한 사람에게 남의 대화가 그대로 보인다.
      if (!chatIsOurs) await _dropChatNotIn(prefs, foundKeys.toSet());
      // 이제 이 기기의 대화는 이 사람 것이다. 다음부터는 합쳐도 안전하다.
      await prefs.setString(chatOwnerKey, user.uid);
      await WidgetSyncService.syncFromStoredTasks();
      unawaited(AppleCalendarSyncService.instance.syncAll());
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

  /// 로그아웃할 때 부른다.
  ///
  /// [chatOwnerKey]는 지우지 않는다. 다음에 로그인한 사람이 앞사람과 같은지
  /// 가리는 유일한 표시라, 지우면 남의 대화를 그 사람 것으로 합쳐버린다.
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('nyang_has_synced_from_cloud');
    // 다음 사람은 이 기기에서 맞춘 적이 없다.
    await SyncBase.clear(prefs);
    _bases = null;
    _basesUid = null;
    await prefs.remove('nyang_tasks');
    await prefs.remove('nyang_core_tasks');
  }

  static StreamSubscription<QuerySnapshot>? _realTimeSubscription;

  static void startRealTimeSync(String uid, VoidCallback onDataChanged) {
    _onDataChanged = onDataChanged;
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
            final chatIsOurs = _chatBelongsToUser(prefs, uid);
            final bases = _basesFor(prefs, uid);

            for (final doc in snapshot.docs) {
              final key = doc.id;
              final data = doc.data();

              // 대화는 덮지 않고 합친다. 그래서 옛 스냅샷이 도착해도 방금 한
              // 말이 사라지지 않는다. 주인이 다른 기기는 여기서 손대지 않고
              // 받아오기 쪽이 정리하게 둔다.
              if (ChatStore.isChatKey(key)) {
                if (!chatIsOurs) continue;
                final localRaw = prefs.getString(key);
                final merged = _mergedChatValue(
                  localRaw: localRaw,
                  cloudValue: data['value'],
                );
                if (merged != localRaw) {
                  await prefs.setString(key, merged);
                  changed = true;
                }
                continue;
              }

              // 설문 답도 덮지 않고 합친다. 옛 스냅샷이 도착해도 방금 고른
              // 답이 사라지지 않는다.
              if (key == LifePatternService.storeKey) {
                final localRaw = prefs.getString(key);
                final cloudValue = data['value'];
                final merged = LifePatternService.mergedValue(
                  localRaw,
                  cloudValue is String ? cloudValue : null,
                );
                if (merged != localRaw) {
                  await prefs.setString(key, merged);
                  changed = true;
                }
                continue;
              }

              if (_localOnlyKeys.contains(key)) continue;
              if (!data.containsKey('value')) continue;

              // 방금 이 기기에서 고쳐 아직 못 올린 것은 두고, 나머지는 받는다.
              // 옛 스냅샷이 늦게 도착해도 그건 이 기기가 마지막으로 맞춘 값과
              // 같아서 "이 기기가 고친 것"으로 남는다.
              final value = data['value'];
              if (value == null) continue;
              final cloudPrint = SyncBase.fingerprint(value)!;
              final move = SyncBase.decide(
                local: SyncBase.fingerprint(prefs.get(key)),
                cloud: cloudPrint,
                base: bases[key],
              );
              if (move == SyncMove.push) continue;
              if (move == SyncMove.takeCloud) {
                await _writeLocal(prefs, key, value);
                changed = true;
              }
              bases[key] = cloudPrint;
            }
            await _saveBases(prefs, uid);

            if (changed) {
              debugPrint(
                '🔔 TasksSyncService: Firestore 변경 감지되어 로컬 데이터 동기화 완료!',
              );
              await WidgetSyncService.syncFromStoredTasks();
              unawaited(AppleCalendarSyncService.instance.syncAll());
              onDataChanged();
            }
          },
          onError: (e) {
            debugPrint('❌ TasksSyncService realTimeSync 오류: $e');
          },
        );
  }

  static void stopRealTimeSync() {
    _onDataChanged = null;
    _realTimeSubscription?.cancel();
    _realTimeSubscription = null;
  }

  /// 저장된 값과 클라우드 값이 같은 것인지.
  ///
  /// 목록은 `==`로 견주면 안 된다. Dart에서 리스트 비교는 내용이 아니라 같은
  /// 물건이냐를 보는데, 클라우드에서 내려온 목록은 매번 새로 만들어진 것이라
  /// 내용이 똑같아도 영원히 "달라졌다"가 된다. 그 판정 하나 때문에 앱은 스냅샷이
  /// 올 때마다 바뀐 게 있다고 믿고 다시 올렸고, 올린 것이 다시 스냅샷으로
  /// 돌아와 4초마다 왕복이 끝나지 않았다. 그 왕복이 한 바퀴마다 모닝콜 알람을
  /// 다시 걸어, 울릴 시각을 지나는 바퀴가 알람을 통째로 내일로 밀어버렸다.
  ///
  /// 목록은 올릴 때 [Object.toString]으로 펴서 보내므로, 견줄 때도 같은 모양으로 본다.
  @visibleForTesting
  static bool sameStoredValue(Object? local, Object? cloud) {
    if (local is List && cloud is List) {
      if (local.length != cloud.length) return false;
      for (var i = 0; i < local.length; i++) {
        if (local[i].toString() != cloud[i].toString()) return false;
      }
      return true;
    }
    return local == cloud;
  }

  static bool _isEmptyEncodedValue(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == '[]' || trimmed == '{}';
  }
}
