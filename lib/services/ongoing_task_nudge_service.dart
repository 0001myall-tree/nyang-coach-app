import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'task_completion_service.dart';

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

/// 시작해둔 일정을 앱 밖에서도 떠올릴 수 있게 하는 기능.
///
/// 재촉이 아니라 "아 맞다, 나 이거 하던 중이었지"의 계기만 준다. 그래서
/// 소리도 진동도 없고, 눌러야만 무슨 일이 일어난다.
///
/// 보여주는 방법은 두 나라가 다르다. 앱이 부르는 말(start/stop)은 같고,
/// 그 뒤는 네이티브가 알아서 한다.
///
/// - 안드로이드: 30분 뒤 폰으로 딴 걸 보고 있으면 다른 앱 위에 냥냥이가
///   잠깐 나타났다 사라진다. 판단도 네이티브가 한다 — 앱이 꺼져 있는
///   동안에도 돌아가야 하기 때문이다.
/// - 아이폰: 다른 앱 위에 그리는 것이 아예 막혀 있다. 대신 일정이 도는 동안
///   잠금화면과 다이내믹 아일랜드에 조용히 머문다(라이브 액티비티). 딴짓
///   중인지는 알 수 없어서 시작하자마자 뜬다.
class OngoingTaskNudgeService {
  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/ongoing_nudge',
  );

  /// 이 기능이 쓰는 키는 'nyang_'으로 시작하지 않는다.
  ///
  /// 그 접두어가 붙은 값은 통째로 클라우드에 올라갔다 내려온다. 여기 담기는 건
  /// 전부 이 기기에서만 뜻이 있는 것들이라 — 이 폰에 오버레이 권한이 있는지,
  /// 지금 이 폰에서 뭘 눌렀는지 — 다른 기기 값에 덮이면 안 된다.
  static const String enabledKey = 'ongoing_nudge_enabled';
  static const String _resultKey = 'ongoing_nudge_pending_result';

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid =>
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

  /// 지금 이 기기에서 실제로 보여줄 수 있는 상태인지.
  ///
  /// 안드로이드는 "다른 앱 위에 표시" 권한, 아이폰은 라이브 액티비티 허용 여부다.
  /// 둘 다 팝업으로 물을 수 없어서 시스템 설정으로 보내야 한다.
  static Future<bool> isAvailable() async {
    if (!isSupported) return false;
    try {
      final method = _isAndroid ? 'canDrawOverlays' : 'isAvailable';
      return await _channel.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openSystemSettings() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod(
        _isAndroid ? 'openOverlaySettings' : 'openSystemSettings',
      );
    } on PlatformException {
      // 설정 화면이 없는 기기라면 할 수 있는 게 없다.
    } on MissingPluginException {
      // 네이티브가 아직 없는 빌드.
    }
  }

  /// 기기가 앱을 재워서 냥냥이가 제때 못 나갈 상태인지.
  ///
  /// 국내 안드로이드는 사실상 삼성이고 "사용하지 않는 앱 절전"이 기본으로
  /// 켜져 있다. 그대로 두면 30분 뒤에 나가야 할 냥냥이가 한참 뒤에 나가거나
  /// 아예 안 나간다. 기능이 고장 난 것처럼 보이는 가장 큰 원인이다.
  static Future<bool> isBatterySleepRestricted() async {
    if (!_isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isBatterySleepRestricted') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> openBatterySettings() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('openBatterySettings');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 냥냥코치를 보고 있는 동안에는 나가지 않는다. 앱 안에 이미 진행 중 카드가 있다.
  /// 안드로이드에서만 쓰는 신호다.
  ///
  /// 네이티브에 맡긴다. 표시와 함께 그 표시를 남긴 프로세스 번호를 적어둬야,
  /// 앱이 갑자기 종료됐을 때 "앞에 있음"으로 굳어 냥냥이가 영영 못 나가는 일이 없다.
  static Future<void> setAppForeground(bool value) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setAppForeground', {'value': value});
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 무엇이 냥냥이를 막고 있는지. 조용히 실패하면 어디가 문제인지 알 수 없다.
  static Future<Map<String, bool>> diagnose() async {
    if (!_isAndroid) return const {};
    try {
      final raw = await _channel.invokeMapMethod<String, bool>('diagnose');
      return raw ?? const {};
    } on PlatformException {
      return const {};
    } on MissingPluginException {
      return const {};
    }
  }

  /// 30분을 기다리지 않고 지금 확인해본다. 앱을 나가면 몇 초 안에 나타난다.
  static Future<void> showTestNudge() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('showTestNudge');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 진행 중인 일정 하나를 지켜보게 한다. 같은 일정이면 시계를 다시 돌리지 않는다.
  ///
  /// 어떤 코치를 쓰든 밖으로 나가는 얼굴은 냥냥이 하나다. 앱의 상징이라,
  /// 다른 앱 위에서는 이게 냥냥코치라는 걸 한눈에 알아야 한다.
  /// [elapsedSeconds]는 이미 쌓인 실행 시간. 아이폰에서 흐르는 시계를 그만큼
  /// 앞당겨 시작해야 이어서 흐르는 것처럼 보인다.
  static Future<void> start({
    required String taskId,
    required String taskText,
    int elapsedSeconds = 0,
  }) async {
    if (!isSupported) return;
    if (!await isEnabled()) return;
    if (!await isAvailable()) return;
    try {
      final startedAt = DateTime.now().subtract(
        Duration(seconds: elapsedSeconds),
      );
      await _channel.invokeMethod('start', {
        'taskId': taskId,
        'taskText': taskText,
        'startedAtMillis': startedAt.millisecondsSinceEpoch,
      });
    } on PlatformException {
      // 실패해도 앱 동작에는 영향이 없다.
    } on MissingPluginException {
      //
    }
  }

  /// 저장된 할 일을 보고 지금 상태에 맞춰준다.
  ///
  /// 플래너 화면이 열려 있지 않아도 맞춰져야 한다. 앱을 강제 종료했다 켜면
  /// 아이폰 잠금화면에 다 끝난 일정이 계속 떠 있을 수 있고, 안드로이드는
  /// 재부팅 뒤 예약이 비어 있을 수 있다.
  static Future<void> reconcile() async {
    if (!isSupported) return;
    if (!await isEnabled()) {
      await stop();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('nyang_tasks');
    if (raw == null || raw.isEmpty) {
      await stop();
      return;
    }

    Map<String, dynamic>? running;
    try {
      for (final item in jsonDecode(raw) as List) {
        if (item is! Map) continue;
        if (item['done'] == true) continue;
        if (item['inProgress'] != true) continue;
        running = Map<String, dynamic>.from(item);
        break;
      }
    } catch (_) {
      return;
    }

    if (running == null) {
      await stop();
      return;
    }

    // 쌓인 시간 + 지금 돌고 있는 구간.
    var elapsed = (running['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final runStartedAt = DateTime.tryParse(
      running['runStartedAt']?.toString() ?? '',
    );
    if (runStartedAt != null) {
      elapsed += DateTime.now().difference(runStartedAt).inSeconds;
    }

    await start(
      taskId: running['id'].toString(),
      taskText: running['text']?.toString() ?? '',
      elapsedSeconds: elapsed < 0 ? 0 : elapsed,
    );
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

  /// 냥냥이 카드에서 고른 답을 일정에 반영한다.
  ///
  /// 플래너 화면이 열려 있든 말든 상관없다. 앱이 켜지는 순간 여기서 끝난다 —
  /// 예전에는 그 화면이 열려야만 반영돼서, 채팅만 하다 나가면 코치가 계속
  /// "그거 아직 안 했네요"라고 했다.
  static Future<bool> applyPendingAnswer() async {
    final answer = await takeAnswer();
    if (answer == null) return false;
    if (answer.isDone) {
      return TaskCompletionService.completeStoredTask(taskId: answer.taskId);
    }
    return TaskCompletionService.pauseStoredTask(taskId: answer.taskId);
  }

  /// 냥냥이 카드에서 고른 답을 한 번만 꺼내온다.
  ///
  /// 네이티브가 앱 밖에서 저장한 값이라, 메모리에 남아 있는 옛 값을 보지 않도록
  /// 반드시 다시 읽고 시작한다.
  /// 안드로이드에만 있다. 아이폰 라이브 액티비티에는 버튼을 두지 않았다.
  static Future<OngoingNudgeAnswer?> takeAnswer() async {
    if (!_isAndroid) return null;
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
