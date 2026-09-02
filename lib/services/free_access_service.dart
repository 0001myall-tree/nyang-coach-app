import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 플랜 없이 써볼 수 있는 기간. 계정당 한 번이고, 처음 쓴 날이 첫날이다.
///
/// 대화가 먼저 닫히고 입력이 하루 더 열려 있다. 코치를 부르는 데 돈이 들고,
/// 할 일을 적어두는 데는 안 들기 때문이다.
///
/// 늘리거나 줄일 일이 생기면 아래 두 숫자만 고치면 된다.
class FreeAccessService {
  FreeAccessService._();

  static final instance = FreeAccessService._();

  /// 코치와 대화할 수 있는 날수. 1이면 처음 쓴 그날 하루.
  /// 서버 값을 못 읽을 때 쓰는 기본값이다.
  static const int defaultChatDays = 1;

  /// 일정·루틴·목표를 적을 수 있는 날수.
  ///
  /// 대화와 같은 날수로 맞춘다. 2였을 때는 둘째 날에 코치가 사라지고 할 일
  /// 적기만 남는 구간이 생겼는데, 코치 빠진 이 앱은 그냥 할 일 목록이라
  /// 그 하루가 "별거 없네"로 읽혔다. 무료 구간이 이 앱의 제일 밋밋한 모습으로
  /// 끝나는 셈이었다.
  static const int defaultInputDays = 1;

  /// 이 두 날수는 앱을 다시 올리지 않고도 바꿀 수 있어야 한다. 심사 기간에만
  /// 넉넉히 열어두는 식으로 쓰게 되기 때문이다. 그래서 콘솔에서 고칠 수 있는
  /// 문서 하나(config/free_access)에서 읽고, 못 읽으면 위 기본값으로 돌아간다.
  ///
  /// 0을 넣으면 그 쪽이 통째로 닫힌다. 비용이 튀었을 때 심사 없이 잠글 수
  /// 있는 자리가 여기다.
  ///
  /// 문서 모양: { "chat_days": 1, "input_days": 1 }
  static const String configDocPath = 'config/free_access';

  /// 시작한 날. 기기에 두면 지우고 다시 깔아서 계속 쓸 수 있어 클라우드에 적는다.
  static const String startedOnField = 'free_access_started_on';

  /// 클라우드를 못 읽을 때만 쓰는 예비 기록.
  static const String _localStartedOnKey = 'nyang_free_access_started_on';

  String? _cachedStartedOn;
  String? _cachedForUid;
  int? _chatDays;
  int? _inputDays;
  DateTime? _configReadAt;

  Future<bool> canChat() async {
    await _loadConfig();
    return await _dayIndex() < (_chatDays ?? defaultChatDays);
  }

  Future<bool> canInput() async {
    await _loadConfig();
    return await _dayIndex() < (_inputDays ?? defaultInputDays);
  }

  /// 남은 날수. 안내 문구에 쓴다. 이미 끝났으면 0.
  Future<int> remainingInputDays() async {
    await _loadConfig();
    final left = (_inputDays ?? defaultInputDays) - await _dayIndex();
    return left < 0 ? 0 : left;
  }

  /// 앱을 켜 두는 내내 다시 읽지는 않는다. 한 시간에 한 번이면 충분하다.
  Future<void> _loadConfig() async {
    final readAt = _configReadAt;
    if (readAt != null &&
        DateTime.now().difference(readAt) < const Duration(hours: 1)) {
      return;
    }

    try {
      final parts = configDocPath.split('/');
      final doc = await FirebaseFirestore.instance
          .collection(parts.first)
          .doc(parts.last)
          .get();
      // 콘솔에서 칸을 나눠 넣어도 되고, `json` 칸 하나에 통째로 붙여넣어도 된다.
      final data = _readConfig(doc.data());
      if (data != null) {
        _chatDays = _positiveInt(data['chat_days']);
        _inputDays = _positiveInt(data['input_days']);
      }
      _configReadAt = DateTime.now();
    } catch (e) {
      debugPrint('Free access config read failed: $e');
      // 다음에 다시 시도한다. 못 읽은 동안은 기본값으로 돈다.
    }
  }

  Map<String, dynamic>? _readConfig(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (e) {
        debugPrint('Free access json parse failed: $e');
      }
      return null;
    }
    return data;
  }

  int? _positiveInt(Object? value) {
    final parsed = value is int ? value : int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  /// 아직 안 썼으면 오늘부터 시작한 것으로 친다. 시작한 날로부터 며칠째인지
  /// 돌려준다 (첫날이 0).
  Future<int> _dayIndex() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    final startedOn = await _startedOn(user.uid) ?? await _start(user.uid);
    final start = DateTime.tryParse(startedOn);
    if (start == null) return 0;

    final today = _dateOnly(DateTime.now());
    return today.difference(_dateOnly(start)).inDays;
  }

  Future<String?> _startedOn(String uid) async {
    if (_cachedForUid == uid && _cachedStartedOn != null) {
      return _cachedStartedOn;
    }

    String? cloudValue;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      cloudValue = doc.data()?[startedOnField]?.toString();
    } catch (e) {
      debugPrint('Free access read failed: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    final localValue = prefs.getString('${_localStartedOnKey}_$uid');

    // 둘 다 있으면 이른 쪽을 쓴다. 지우고 다시 깔아도 처음 날짜가 살아남는다.
    final value = _earlier(cloudValue, localValue);
    if (value == null) return null;

    if (cloudValue != value) await _writeCloud(uid, value);
    if (localValue != value) {
      await prefs.setString('${_localStartedOnKey}_$uid', value);
    }

    _cachedForUid = uid;
    _cachedStartedOn = value;
    return value;
  }

  Future<String> _start(String uid) async {
    final today = _dateOnly(DateTime.now()).toIso8601String();
    await _writeCloud(uid, today);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_localStartedOnKey}_$uid', today);
    _cachedForUid = uid;
    _cachedStartedOn = today;
    return today;
  }

  Future<void> _writeCloud(String uid, String value) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        startedOnField: value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Free access write failed: $e');
    }
  }

  String? _earlier(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    final dateA = DateTime.tryParse(a);
    final dateB = DateTime.tryParse(b);
    if (dateA == null) return b;
    if (dateB == null) return a;
    return dateA.isBefore(dateB) ? a : b;
  }

  /// 로그아웃하거나 계정을 지우면 다음 사람 것을 물고 가지 않도록 비운다.
  void clearCache() {
    _cachedForUid = null;
    _cachedStartedOn = null;
  }
}

/// 시각을 떼고 날짜만 남긴다. 하루 차이를 셀 때 시:분이 끼면 어긋난다.
DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
