import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'ongoing_task_nudge_service.dart';
import 'task_completion_service.dart';

/// 다이내믹 아일랜드가 없는 아이폰을 위한 냥냥이 배너.
///
/// 안드로이드는 다른 앱 위에 냥냥이를 직접 그린다. 아이폰은 그럴 수 없고,
/// 라이브 액티비티가 그 자리를 대신하지만 그것도 다이내믹 아일랜드가 있어야
/// 딴짓하는 중에 눈에 들어온다. 없는 기종에서는 잠금화면에만 남는데, 그건
/// 딴짓을 막아주는 것이 아니라 진행 중이라는 표시일 뿐이다.
///
/// 그래서 그런 기종에서는 알림으로 찾아간다. 알림 배너는 어느 아이폰에서나
/// 다른 앱 위로 내려온다.
///
/// 시작하라는 배너는 눌러서 앱을 열게만 한다. 버튼을 달 수도 있지만 꾹 눌러야
/// 나오는 데다, 앱을 열면 할 일 목록에 ▶가 바로 보여서 아끼는 것이 한 번
/// 누르는 정도다. 하는 중이냐는 배너에만 버튼을 둔다 — 그쪽은 앱에서 하려면
/// 카드를 찾아 들어가야 해서 아끼는 것이 크다.
///
/// 세기는 안드로이드만 못하다. 배너가 몇 초 뒤 올라가기 때문인데, 얼마나
/// 머무를지는 앱이 정할 수 없고 사용자의 배너 스타일 설정이 정한다. 그래서 켤 때
/// "지속"으로 바꾸는 길을 한 번 알려준다. 배너가 올라가도 알림 자체는 잠금화면에
/// 남으므로 나중에 눌러도 된다.
class NyangBannerNudge {
  static const String payloadPrefix = 'nyangbanner';

  /// 배너를 눌러 앱에 들어왔을 때, 어느 일정을 보라고 할지 적어두는 자리.
  ///
  /// 'nyang_'으로 시작하지 않는 키를 쓴다. 그 접두어는 클라우드 복원이 덮어써서
  /// 이 기기에서만 쓰이고 곧 지워질 값을 담기에 맞지 않는다.
  static const String focusTaskKey = 'banner_focus_task_id';

  /// 시작하고 처음 확인하기까지. 안드로이드 냥냥이와 같은 간격이다.
  static const Duration firstCheck = Duration(minutes: 30);

  /// 한 번 묻고 다음에 다시 묻기까지.
  static const Duration nextRound = Duration(hours: 1);

  /// 한 번에 하나만 걸어둔다. 다음 일정은 이 자리를 덮어쓴다.
  static const int notificationId = 1300;

  /// 도는 일정을 확인하는 배너의 자리.
  static const int runningNotificationId = 1302;

  /// "지금 한번 보기"는 자기 자리를 쓴다.
  ///
  /// 같은 자리를 쓰면, 확인하려고 걸어둔 것을 앱으로 돌아오는 순간 [sync]가
  /// 지워버린다. 기다리던 사람만 헛수고한다.
  static const int testNotificationId = 1301;

  /// 시작 시각을 지나고 이만큼까지만 부른다. 그 뒤로는 잔소리가 된다.
  static const Duration window = Duration(hours: 1);

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 이 기기가 배너로 찾아가야 하는 기기인지.
  ///
  /// 아이폰이면 기종을 가리지 않는다. 다이내믹 아일랜드가 있어도 배너가 필요하다 —
  /// 알약은 얼마나 지났는지를 보여줄 뿐 아무것도 묻지 않고, 펼쳐도 누를 것이 없어서
  /// 답하려면 앱을 열어야 한다. 게다가 시작하기 전에는 알약 자체가 없다.
  /// 라이브 액티비티는 표시고 배너는 부름이라, 하는 일이 겹치지 않는다.
  static Future<bool> isNeededHere() async {
    if (!_isIOS) return false;
    return OngoingTaskNudgeService.isEnabled();
  }

  /// 저장된 할 일을 보고 다음 배너를 걸어둔다. 걸 것이 없으면 지운다.
  ///
  /// 한 번에 하나만 건다 — 시작하라는 말과 하는 중이냐는 말이 같이 오면 안 된다.
  /// 둘이 겹치면 시작할 시각 쪽이 이긴다.
  static Future<void> sync() async {
    if (!_isIOS) return;
    await _plugin.cancel(id: notificationId);
    await _plugin.cancel(id: runningNotificationId);
    if (!await isNeededHere()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('nyang_tasks');
    if (raw == null || raw.isEmpty) return;

    final List tasks;
    try {
      tasks = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }

    // 시작할 시각이 먼저다.
    //
    // 도는 일정이 있어도 마찬가지다. 하는 중이냐는 물음은 미뤄도 그 일이 없어지지
    // 않지만, 시작하기로 한 시각은 지나가면 그날치가 사라진다. 그 시각이 정리된
    // 뒤에 — 시작했거나, 창이 닫혔거나 — 하는 중이냐는 물음이 자리를 잇는다.
    final next = OngoingTaskNudgeService.nextUnstartedTask(
      tasks,
      DateTime.now(),
    );
    if (next != null) {
      await _schedule(
        taskId: next['id'].toString(),
        taskText: next['text']?.toString() ?? '',
        at: next['_startAt'] as DateTime,
        deadline: (next['_startAt'] as DateTime).add(window),
      );
      return;
    }

    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] != true) continue;
      await _scheduleRunningCheck(
        taskId: item['id'].toString(),
        taskText: item['text']?.toString() ?? '',
        runStartedAt: DateTime.tryParse(
          item['runStartedAt']?.toString() ?? '',
        ),
      );
      return;
    }
  }

  /// 도는 일정에 "지금도 하는 중이야?"를 걸어둔다.
  ///
  /// 시작한 시각을 기준으로 30분 뒤에 묻는다. 저장이 일어날 때마다 다시 걸리는데,
  /// 기준이 시작 시각이라 물어볼 때가 뒤로 밀리지 않는다.
  static Future<void> _scheduleRunningCheck({
    required String taskId,
    required String taskText,
    DateTime? runStartedAt,
  }) async {
    final now = DateTime.now();
    var at = (runStartedAt ?? now).add(firstCheck);
    // 이미 지났으면 다음 차례로 넘긴다. 앱을 오랜만에 열었다고 해서 그 자리에서
    // 배너가 튀어나오면, 방금 앱을 연 사람에게 앱 밖에서 부르는 셈이 된다.
    if (!at.isAfter(now)) at = now.add(nextRound);
    await _scheduleRunning(
      taskId: taskId,
      taskText: taskText,
      at: at,
      startedAt: runStartedAt,
    );
  }

  static Future<void> _scheduleRunning({
    required String taskId,
    required String taskText,
    required DateTime at,
    DateTime? startedAt,
  }) async {
    _ensureTimeZone();
    final payload = '$payloadPrefix:${jsonEncode({
      'kind': 'running',
      'taskId': taskId,
      'taskText': taskText,
    })}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: false,
        // 버튼은 달지 않는다. 시작 배너와 같은 이유다 — 꾹 눌러야 나오는 데다,
        // 화면 없는 갈래에서 도는 코드라 잘못되면 그 자리에서 조용히 끝난다.
        // 눌러서 앱으로 오면 그 일정 칸이 번쩍여 어디를 볼지 알려준다.
        // 여기도 방해금지를 뚫는다.
        //
        // 집중하는 사람을 깨울까 싶었지만, 집중하는 사람은 폰을 보고 있지 않다.
        // 안 보는 화면에 뜬 배너는 아무것도 방해하지 않는다. 이걸 보게 되는 사람은
        // 시작해놓고 폰을 든 사람뿐이고, 그 사람은 스스로 자기를 방해한 것이다.
        // 되돌리라고 부르는 자리라 조용할 이유가 없다.
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.zonedSchedule(
      id: runningNotificationId,
      title: '🐾 ${taskText.isEmpty ? '진행 중인 일정' : taskText}',
      body: startedAt == null
          ? '지금도 하는 중이야?'
          : '${_clock(startedAt)}에 시작했어. 지금도 하는 중이야?',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 배너에 적을 시각. "오후 2시", "오후 2시 30분".
  ///
  /// 배너를 그 자리에서 보지 못하고 나중에 잠금화면에서 발견하는 일이 흔하다.
  /// 시각이 없으면 그 사람에게는 언제 이야기인지 알 길이 없다.
  static String _clock(DateTime at) {
    final ampm = at.hour < 12 ? '오전' : '오후';
    final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
    final minute = at.minute == 0 ? '' : ' ${at.minute}분';
    return '$ampm $hour12시$minute';
  }

  /// 예약을 걸기 전에 시간대를 세워둔다.
  ///
  /// 버튼을 눌러 깨어난 갈래에는 시간대가 준비되어 있지 않다. 그대로 예약하면
  /// 그 자리에서 터지고, 다음 배너가 조용히 사라진다. 앱 안에서는 이미 서 있으므로
  /// 여러 번 불러도 손해가 없다.
  static void _ensureTimeZone() {
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}
  }

  /// 지금 걸려 있는 배너가 실제로 예약돼 있는지.
  ///
  /// 안 나올 때 원인이 둘로 갈린다 — 예약이 안 된 것과, 예약은 됐는데 화면에
  /// 안 뜬 것. 이 둘은 고칠 곳이 완전히 달라서, 물어보지 않으면 계속 헤맨다.
  static Future<String> diagnose() async {
    if (!_isIOS) return '아이폰이 아니에요.';
    final pending = await _plugin.pendingNotificationRequests();
    final mine = pending
        .where((p) => p.id == notificationId || p.id == testNotificationId)
        .toList();
    final lines = <String>[
      '예약된 알림 전체: ${pending.length}개',
      mine.isEmpty ? '냥냥이 배너: 예약 없음' : '냥냥이 배너: 예약됨',
    ];
    if (mine.isNotEmpty) {
      lines.add('제목: ${mine.first.title ?? '(없음)'}');
    }
    return lines.join('\n');
  }

  /// 시작 시각을 기다리지 않고 지금 한번 확인한다.
  ///
  /// 이 기능은 정해둔 시각이 와야 확인되는데, 그 시각을 기다렸다가 안 오면
  /// 무엇이 막고 있는지 알 길이 없다. 설정 안에 지금 보는 길이 있어야 한다.
  static Future<void> showTest() async {
    if (!_isIOS) return;
    final now = DateTime.now();
    await _schedule(
      id: testNotificationId,
      taskId: 'nyang_banner_test',
      taskText: '지금 한번 보기',
      at: now.add(const Duration(seconds: 8)),
      // 확인용이라 "좀 더 있다가"로 다시 부를 일은 없다.
      deadline: now.add(const Duration(minutes: 1)),
    );
  }

  static Future<void> _schedule({
    int id = notificationId,
    required String taskId,
    required String taskText,
    required DateTime at,
    required DateTime deadline,
  }) async {
    if (at.isAfter(deadline)) return;
    _ensureTimeZone();

    final payload = '$payloadPrefix:${jsonEncode({
      'taskId': taskId,
      'taskText': taskText,
      'deadline': deadline.millisecondsSinceEpoch,
    })}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        // 버튼을 달지 않는다. 눌러서 앱을 열면 할 일 목록에 ▶가 바로 보이므로
        // 버튼이 아끼는 것은 한 번 누르는 정도인데, 그 버튼은 화면 없는 갈래에서
        // 코드를 돌리는 길이라 잘못되면 아무 일도 일어나지 않는 쪽으로 끝난다.
        // 아끼는 것보다 잃을 것이 크다.
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: false,
        // 방해금지 모드를 뚫고 나온다. 딴짓하는 동안 조용한 알림은 없는 것과 같다.
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: '🐾 ${taskText.isEmpty ? '지금 시작하기로 한 일' : taskText}',
      body: '${_clock(at)}, 시작할 시간이야',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 배너에서 고른 답을 처리한다. 앱이 떠 있든 아니든 같은 길을 탄다.
  ///
  /// 여기서 나는 예외는 밖으로 내보내지 않는다. 앱이 꺼져 있을 때 이 코드는
  /// 화면 없는 갈래에서 도는데, 거기서 터지면 사용자에게는 앱이 죽은 것으로
  /// 보인다 — 챙겨주려던 버튼이 앱을 죽이는 버튼이 되는 셈이다.
  static Future<void> handle(NotificationResponse response) async {
    try {
      await _handle(response);
    } catch (_) {
      // 답을 못 옮겼을 뿐이다. 다음에 앱을 열면 그 일정은 그대로 있다.
    }
  }

  static Future<void> _handle(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || !payload.startsWith('$payloadPrefix:')) return;

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(payload.substring(payloadPrefix.length + 1)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final taskId = data['taskId']?.toString() ?? '';
    if (taskId.isEmpty) return;

    // 앱이 열리면 할 일이 쭉 늘어서 있어서, 부른 쪽이 어느 것인지 알 수 없다.
    // 어느 칸을 볼지 적어두면 할 일 화면이 그 칸을 번쩍여준다.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(focusTaskKey, taskId);
  }

}

const String nyangBannerPayload = NyangBannerNudge.payloadPrefix;

Future<void> handleNyangBannerResponse(NotificationResponse response) =>
    NyangBannerNudge.handle(response);

/// 앱이 떠 있지 않을 때 버튼을 누르면 이쪽으로 온다.
///
/// 별도의 격리 공간에서 도는 갈래라 최상위 함수여야 하고, 지워지지 않게 표시해
/// 두어야 한다. 그리고 그 공간에는 플러그인이 아직 하나도 붙어 있지 않다 —
/// 세워두지 않고 저장소를 건드리면 그대로 터진다.
@pragma('vm:entry-point')
void nyangBannerBackgroundHandler(NotificationResponse response) {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  NyangBannerNudge.handle(response);
}
