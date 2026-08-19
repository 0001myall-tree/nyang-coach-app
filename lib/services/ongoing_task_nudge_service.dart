import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 냥냥이가 물어본 것에 사용자가 고른 답.
class OngoingNudgeAnswer {
  const OngoingNudgeAnswer({required this.taskId, required this.action});

  final String taskId;

  /// 'done' = 다 했어, 'paused' = 잠깐 멈췄어.
  /// '계속하는 중'은 아무것도 바꾸지 않으므로 답이 남지 않는다.
  final String action;

  bool get isDone => action == 'done';
  bool get isPaused => action == 'paused';
}

/// 시작해둔 일정이 진행 중인데 사용자가 다른 앱으로 새어 나갔을 때,
/// 화면 가장자리에 냥냥이를 잠깐 내보내는 기능.
///
/// 재촉이 아니라 "아 맞다, 나 이거 하던 중이었지"의 계기만 준다. 그래서
/// 소리도 진동도 없고, 무시하면 스스로 사라진다. 판단은 전부 네이티브가 한다 —
/// 앱이 꺼져 있는 동안에도 돌아가야 하기 때문이다.
///
/// 안드로이드 전용이다. iOS는 다른 앱 위에 무언가를 그리는 것이 아예 막혀 있다.
class OngoingTaskNudgeService {
  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/ongoing_nudge',
  );

  /// 테스터에게만 켜주는 스위치.
  static const String enabledKey = 'nyang_ongoing_nudge_enabled';
  static const String _resultKey = 'nyang_nudge_pending_result';
  static const String _foregroundKey = 'nyang_app_in_foreground';

  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(enabledKey, value);
    if (!value) await stop();
  }

  /// "다른 앱 위에 표시" 권한. 팝업으로 물을 수 없어서 시스템 설정으로 보내야 한다.
  static Future<bool> canDrawOverlays() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openOverlaySettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('openOverlaySettings');
    } on PlatformException {
      // 설정 화면이 없는 기기라면 할 수 있는 게 없다.
    } on MissingPluginException {
      // 네이티브가 아직 없는 빌드.
    }
  }

  /// 냥냥코치를 보고 있는 동안에는 나가지 않는다. 앱 안에 이미 진행 중 카드가 있다.
  static Future<void> setAppForeground(bool value) async {
    if (!isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_foregroundKey, value);
  }

  /// 진행 중인 일정 하나를 지켜보게 한다. 같은 일정이면 시계를 다시 돌리지 않는다.
  ///
  /// 어떤 코치를 쓰든 밖으로 나가는 얼굴은 냥냥이 하나다. 앱의 상징이라,
  /// 다른 앱 위에서는 이게 냥냥코치라는 걸 한눈에 알아야 한다.
  static Future<void> start({
    required String taskId,
    required String taskText,
  }) async {
    if (!isSupported) return;
    if (!await isEnabled()) return;
    if (!await canDrawOverlays()) return;
    try {
      await _channel.invokeMethod('start', {
        'taskId': taskId,
        'taskText': taskText,
      });
    } on PlatformException {
      // 실패해도 앱 동작에는 영향이 없다.
    } on MissingPluginException {
      //
    }
  }

  static Future<void> stop() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 냥냥이 카드에서 고른 답을 한 번만 꺼내온다.
  ///
  /// 네이티브가 앱 밖에서 저장한 값이라, 메모리에 남아 있는 옛 값을 보지 않도록
  /// 반드시 다시 읽고 시작한다.
  static Future<OngoingNudgeAnswer?> takeAnswer() async {
    if (!isSupported) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(_resultKey);
    if (raw == null || raw.isEmpty) return null;
    await prefs.remove(_resultKey);
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final taskId = decoded['taskId']?.toString() ?? '';
      final action = decoded['action']?.toString() ?? '';
      if (taskId.isEmpty || action.isEmpty) return null;
      return OngoingNudgeAnswer(taskId: taskId, action: action);
    } catch (_) {
      return null;
    }
  }
}
