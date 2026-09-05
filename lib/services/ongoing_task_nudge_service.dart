import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'distraction_coach_quota.dart';
import 'task_completion_service.dart';

/// 냥냥이가 물어본 것에 사용자가 고른 답.
class OngoingNudgeAnswer {
  const OngoingNudgeAnswer({required this.taskId, required this.action});

  final String taskId;

  /// 'done' = 다 했어, 'started' = (시작 전 일정에) 시작할게.
  /// '계속하는 중', '다시 시작할게', '좀 더 있다가'는 일정을 바꾸지 않으므로
  /// 답이 남지 않는다.
  final String action;

  bool get isDone => action == 'done';
  bool get isStarted => action == 'started';
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

  static void _log(String message) {
    debugPrint('[OngoingNudge] $message');
  }

  /// 할 일 화면에서 타이머를 켜뒀는지. (할 일 화면이 쓰는 값과 같은 자리다)
  ///
  /// 끈 사람에게는 잠금화면과 다이내믹 아일랜드에서도 숫자를 안 보여준다.
  /// 타이머를 끄는 이유는 대개 쫓기는 느낌이 싫어서인데, 거기는 앱보다 더 자주
  /// 눈에 띄는 자리라 계속 흐르면 끈 의미가 없어진다.
  static Future<bool> _showsTimer() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('nyang_show_task_timer') ?? true;
  }

  /// 이 기능이 쓰는 키는 'nyang_'으로 시작하지 않는다.
  ///
  /// 그 접두어가 붙은 값은 통째로 클라우드에 올라갔다 내려온다. 여기 담기는 건
  /// 전부 이 기기에서만 뜻이 있는 것들이라 — 이 폰에 오버레이 권한이 있는지,
  /// 지금 이 폰에서 뭘 눌렀는지 — 다른 기기 값에 덮이면 안 된다.
  static const String enabledKey = 'ongoing_nudge_enabled';
  static const String _resultKey = 'ongoing_nudge_pending_result';

  /// 켤지 물어본 적이 있는지. 무엇으로 답했든 한 번 물으면 끝이다.
  ///
  /// 묻는 자리가 둘이라 — 일정을 처음 시작한 순간, 그리고 대화 중 —
  /// 이 키를 양쪽이 같이 본다. 아니면 방금 거절한 사람에게 또 묻게 된다.
  static const String offerShownKey = 'ongoing_nudge_offer_shown';

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 아직 한 번도 정하지 않았을 때 켜져 있다고 볼지.
  ///
  /// 아이폰은 켜져 있는 게 기본이다. 라이브 액티비티는 시스템에서 이미 켜져
  /// 있고, 잠금화면에 조용히 한 줄 남는 것뿐이라 꺼져 있을 이유가 없다.
  ///
  /// 안드로이드는 반대다. "다른 앱 위에 표시"가 없으면 켜도 아무것도 나오지
  /// 않는다. 기본을 켜짐으로 두면 설정에는 켜졌다고 적혀 있는데 냥냥이는
  /// 영영 안 나오는, 고장 난 것과 구별할 수 없는 상태가 된다. 그래서 여기서는
  /// 물어본 뒤에 켠다.
  static bool get defaultEnabled => isSupported && !_isAndroid;

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? defaultEnabled;
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
    if (!isSupported) {
      _log('isAvailable=false: unsupported platform');
      return false;
    }
    try {
      final method = _isAndroid ? 'canDrawOverlays' : 'isAvailable';
      final available = await _channel.invokeMethod<bool>(method) ?? false;
      _log('isAvailable=$available via $method');
      return available;
    } on PlatformException catch (error) {
      _log(
        'isAvailable=false: PlatformException(${error.code}, ${error.message})',
      );
      return false;
    } on MissingPluginException catch (error) {
      _log('isAvailable=false: MissingPluginException($error)');
      return false;
    }
  }

  /// 이 아이폰이 다른 앱 위에 냥냥이를 보여줄 수 있는지.
  ///
  /// 다이내믹 아일랜드가 있으면 다른 앱을 보는 중에도 화면 맨 위에 남는다. 없으면
  /// 잠금화면에서만 보이는데, 그건 딴짓을 막아주는 것이 아니라 진행 중이라는 표시일
  /// 뿐이다. 같은 문구로 안내하면 한쪽에게는 지키지 못할 약속이 된다.
  ///
  /// 안드로이드는 오버레이로 어느 기종에서나 나가므로 늘 참이다.
  static Future<bool> showsOverOtherApps() async {
    if (!isSupported) return false;
    if (_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('hasDynamicIsland') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 배너가 누를 때까지 남아 있는 설정인지("지속").
  ///
  /// 앱이 정할 수 없는 값이라 부탁밖에 할 수 없지만, 어느 쪽인지는 읽을 수 있다.
  /// 이미 바꿔둔 사람에게 또 부탁하지 않으려면 이것부터 봐야 한다.
  static Future<bool> isBannerPersistent() async {
    if (!isSupported || _isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('isBannerPersistent') ?? true;
    } on PlatformException {
      return true;
    } on MissingPluginException {
      return true;
    }
  }

  /// 이 앱의 알림 설정 화면을 바로 연다. 아이폰에만 있다.
  static Future<void> openNotificationSettings() async {
    if (!isSupported || _isAndroid) {
      await openSystemSettings();
      return;
    }
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } on PlatformException {
      await openSystemSettings();
    } on MissingPluginException {
      await openSystemSettings();
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
    _log(
      'start requested taskId=$taskId, taskTextLength=${taskText.length}, elapsedSeconds=$elapsedSeconds',
    );
    if (!isSupported) {
      _log('start skipped: isSupported=false');
      return;
    }
    final enabled = await isEnabled();
    _log('start guard isEnabled=$enabled');
    if (!enabled) return;
    // 다이내믹 아일랜드가 없으면 라이브 액티비티는 잠금화면에만 남는다. 딴짓을
    // 막아주지도 못하면서 자리만 차지하고, 그 자리에서 제대로 그려지지도 않았다.
    // 그 기종은 배너가 대신하므로 아예 띄우지 않는다.
    if (!_isAndroid && !await showsOverOtherApps()) {
      _log('start skipped: no dynamic island, banner covers this phone');
      await stop();
      return;
    }
    final available = await isAvailable();
    _log('start guard isAvailable=$available');
    if (!available) return;
    // 다이내믹 아일랜드에 붙는 알약은 시작하자마자 나온다. 딴짓 중인지 알 수
    // 없어서 30분을 기다릴 근거가 없고, 그래서 이 갈래에서는 발동 시점이 곧
    // 시작 시점이다 — 프렌즈의 하루치는 그날 처음 시작한 일정이 가져간다.
    //
    // 안드로이드는 여기서 보지 않는다. 30분 뒤 딴짓 중인지 확인하고 나가는
    // 판단이 네이티브에 있고, 그 판단이 곧 발동이라 하루치도 거기서 센다.
    if (!_isAndroid && !await DistractionCoachQuota.claimNow(taskId)) {
      _log('start skipped: friends plan daily quota already spent');
      await stop();
      return;
    }
    try {
      final startedAt = DateTime.now().subtract(
        Duration(seconds: elapsedSeconds),
      );
      await _channel.invokeMethod('start', {
        'taskId': taskId,
        'taskText': taskText,
        'startedAtMillis': startedAt.millisecondsSinceEpoch,
        'showsTimer': await _showsTimer(),
      });
      _log('start channel call completed');
    } on PlatformException catch (error) {
      _log('start failed: PlatformException(${error.code}, ${error.message})');
    } on MissingPluginException catch (error) {
      _log('start failed: MissingPluginException($error)');
    }
  }

  /// 아직 시작하지 않은 일정의 시작 시각을 기다리게 한다.
  ///
  /// 안드로이드에만 있다. 아이폰은 다른 앱 위에 그릴 수 없어서, 시작하지 않은
  /// 일정에는 보여줄 자리가 없다(라이브 액티비티는 도는 일정에만 붙는다).
  static Future<void> remindStart({
    required String taskId,
    required String taskText,
    required DateTime startAt,
  }) async {
    if (!_isAndroid) return;
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod('remindStart', {
        'taskId': taskId,
        'taskText': taskText,
        'startAtMillis': startAt.millisecondsSinceEpoch,
      });
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 시작 시각을 기다리던 자리를 접는다. 더 기다릴 시간 있는 일정이 없을 때 쓴다.
  static Future<void> clearStart() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('clearStart');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 방금 하나를 끝냈고, 시간이 정해지지 않은 다음 일이 남아 있을 때 다시 부른다.
  ///
  /// 안드로이드에만 있다. 아이폰은 [NyangBannerNudge]가 같은 역할을 알림 배너로
  /// 대신한다. 조건은 이때 한 번만 보고 넘긴다 — 그 뒤로 22시까지 이어지는
  /// 반복은 네이티브가 매번 조건을 다시 검사하며 스스로 잇는다.
  static Future<void> remindNextTask({
    required String taskId,
    required String taskText,
    required DateTime fireAt,
  }) async {
    if (!_isAndroid) return;
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod('remindNextTask', {
        'taskId': taskId,
        'taskText': taskText,
        'fireAtMillis': fireAt.millisecondsSinceEpoch,
      });
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 시작해뒀다 멈춘 일을, 그 상태로 오래 있으면 다시 부른다.
  ///
  /// 안드로이드에만 있다. 아이폰은 [NyangBannerNudge]가 같은 역할을 대신한다.
  /// [remindNextTask]와 같은 이유로 조건은 이때 한 번만 보고, 그 뒤는 네이티브가
  /// 스스로 잇는다.
  static Future<void> remindResume({
    required String taskId,
    required String taskText,
    required DateTime fireAt,
  }) async {
    if (!_isAndroid) return;
    if (!await isAvailable()) return;
    try {
      await _channel.invokeMethod('remindResume', {
        'taskId': taskId,
        'taskText': taskText,
        'fireAtMillis': fireAt.millisecondsSinceEpoch,
      });
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  /// 오늘 시작할 시각이 정해져 있는데 아직 손대지 않은 일정 중 가장 이른 것.
  ///
  /// 이미 시작했거나 끝낸 것, 시각이 없는 것, 시각이 지나버린 것은 뺀다.
  /// 지나버린 것까지 챙기면 하루 종일 밀린 일정을 들고 다니게 된다.
  static Map<String, dynamic>? nextUnstartedTask(
    List<dynamic> tasks,
    DateTime now,
  ) {
    Map<String, dynamic>? best;
    DateTime? bestAt;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) continue;
      final at = _startTimeOf(item['timeStart']?.toString(), now);
      if (at == null || !at.isAfter(now)) continue;
      if (bestAt == null || at.isBefore(bestAt)) {
        best = Map<String, dynamic>.from(item);
        bestAt = at;
      }
    }
    if (best == null || bestAt == null) return null;
    return {...best, '_startAt': bestAt};
  }

  /// "HH:mm"을 오늘의 시각으로. 형식이 아니면 null.
  static DateTime? _startTimeOf(String? raw, DateTime now) {
    if (raw == null) return null;
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 저장된 할 일을 보고 지금 상태에 맞춰준다.
  ///
  /// 플래너 화면이 열려 있지 않아도 맞춰져야 한다. 앱을 강제 종료했다 켜면
  /// 아이폰 잠금화면에 다 끝난 일정이 계속 떠 있을 수 있고, 안드로이드는
  /// 재부팅 뒤 예약이 비어 있을 수 있다.
  static Future<void> reconcile() async {
    if (!isSupported) return;
    final ongoingEnabled = await isEnabled();

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('nyang_tasks');
    if (raw == null || raw.isEmpty) {
      await stopPreservingNextTask();
      await clearStart();
      return;
    }

    final List tasks;
    try {
      tasks = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }

    Map<String, dynamic>? running;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] != true) continue;
      running = Map<String, dynamic>.from(item);
      break;
    }

    if (running == null) {
      await stopPreservingNextTask();
    } else if (!ongoingEnabled) {
      await stop();
    } else {
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

    // 시작 시각 알림은 딴짓 방지 스위치는 물론, 도는 일정이 있는지와도 무관한
    // 별도 자리다. 진행 중인 일정이 있어도 매번 다시 본다.
    final next = nextUnstartedTask(tasks, DateTime.now());
    if (next != null) {
      await remindStart(
        taskId: next['id'].toString(),
        taskText: next['text']?.toString() ?? '',
        startAt: next['_startAt'] as DateTime,
      );
    } else {
      await clearStart();
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

  /// 도는 일도, 시작 기다리는 일도 없을 때 부르는 [stop] 대신 이걸 쓴다.
  ///
  /// 안드로이드는 "다음 일" 카드를 이 서비스와 같은 자리에 걸어둔다. 할 일을
  /// 하나 편집하는 것처럼 관계없는 저장에도 [stop]이 불리는 자리가 많아서,
  /// 그 카드가 22시까지 기다리는 중이면 그것만 건드리지 않는다.
  static Future<void> stopPreservingNextTask() async {
    if (!_isAndroid) return stop();
    try {
      await _channel.invokeMethod('stopUnlessNextTask');
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
    // "시작할게"는 네이티브가 이미 저장소에 적었다. 여기서는 화면이 다시 읽도록
    // 바뀌었다고만 알린다.
    if (answer.isStarted) return true;
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
