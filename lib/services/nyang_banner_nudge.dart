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
/// 다른 앱 위로 내려오고, 버튼을 달면 앱을 열지 않고 그 자리에서 시작할 수 있다.
///
/// 세기는 안드로이드만 못하다. 배너가 몇 초 뒤 올라가기 때문인데, 얼마나
/// 머무를지는 앱이 정할 수 없고 사용자의 배너 스타일 설정이 정한다. 그래서 켤 때
/// "지속"으로 바꾸는 길을 한 번 알려준다. 배너가 올라가도 알림 자체는 잠금화면에
/// 남으므로, 버튼은 지울 때까지 계속 누를 수 있다.
class NyangBannerNudge {
  static const String payloadPrefix = 'nyangbanner';

  /// 시작할 시각에 찾아가는 배너.
  static const String categoryId = 'nyang_banner_start';
  static const String actionStartNow = 'nyang_banner_start_now';
  static const String actionLater = 'nyang_banner_later';

  /// 이미 도는 일정을 확인하는 배너.
  static const String runningCategoryId = 'nyang_banner_running';
  static const String actionDone = 'nyang_banner_done';
  static const String actionKeepGoing = 'nyang_banner_keep';
  static const String actionRestart = 'nyang_banner_restart';

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

  /// "좀 더 있다가"를 골랐을 때 다시 부르기까지. 안드로이드와 같은 간격이다.
  static const Duration snooze = Duration(minutes: 30);

  /// 시작 시각을 지나고 이만큼까지만 부른다. 그 뒤로는 잔소리가 된다.
  static const Duration window = Duration(hours: 1);

  static bool get _isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// 이 기기가 배너로 찾아가야 하는 기기인지.
  ///
  /// 다른 앱 위에 냥냥이를 직접 보여줄 수 있으면 배너는 군더더기다.
  static Future<bool> isNeededHere() async {
    if (!_isIOS) return false;
    if (!await OngoingTaskNudgeService.isEnabled()) return false;
    if (!await OngoingTaskNudgeService.showsOverOtherApps()) return true;
    return false;
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
    await _scheduleRunning(taskId: taskId, taskText: taskText, at: at);
  }

  static Future<void> _scheduleRunning({
    required String taskId,
    required String taskText,
    required DateTime at,
  }) async {
    _ensureTimeZone();
    final payload = '$payloadPrefix:${jsonEncode({
      'kind': 'running',
      'taskId': taskId,
      'taskText': taskText,
    })}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        categoryIdentifier: runningCategoryId,
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: false,
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
      body: '지금도 하는 중이야?',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
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
        categoryIdentifier: categoryId,
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
      body: '시작하는 거 잊지 않았지?',
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
    final raw = response.payload;
    if (raw == null || !raw.startsWith('$payloadPrefix:')) return;

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(raw.substring(payloadPrefix.length + 1))
          as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final taskId = data['taskId']?.toString() ?? '';
    if (taskId.isEmpty) return;

    final taskText = data['taskText']?.toString() ?? '';

    switch (response.actionId) {
      case actionStartNow:
        // 여기서 바로 시작으로 적는다. 앱에 들어가 ▶를 다시 누르게 하면,
        // 시작하겠다고 말한 사람에게 한 칸을 더 시키는 셈이다.
        await TaskCompletionService.startStoredTask(taskId: taskId);
        // 이제 도는 중이다. 30분 뒤에 한 번 보는 자리로 넘긴다.
        await _scheduleRunningCheck(
          taskId: taskId,
          taskText: taskText,
          runStartedAt: DateTime.now(),
        );
        return;
      case actionLater:
        await _rescheduleLater(data);
        return;
      case actionDone:
        await TaskCompletionService.completeStoredTask(taskId: taskId);
        return;
      case actionKeepGoing:
      case actionRestart:
        // 일정은 건드리지 않는다. "다시 시작할게"도 시계를 멈추지 않는다 —
        // 돌아가겠다는 사람에게 다시 시작부터 시키면 그 한 칸이 문턱이 된다.
        await _scheduleRunning(
          taskId: taskId,
          taskText: taskText,
          at: DateTime.now().add(nextRound),
        );
        return;
      default:
        // 알림 자체를 누른 경우. 앱이 열리므로 여기서 할 일은 없다.
        return;
    }
  }

  static Future<void> _rescheduleLater(Map<String, dynamic> data) async {
    final deadlineMillis = (data['deadline'] as num?)?.toInt();
    if (deadlineMillis == null) return;
    final deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMillis);
    final next = DateTime.now().add(snooze);
    // 창이 닫혔으면 조용히 물러난다. 두 번째가 마지막이다.
    if (next.isAfter(deadline)) return;

    await _schedule(
      taskId: data['taskId']?.toString() ?? '',
      taskText: data['taskText']?.toString() ?? '',
      at: next,
      deadline: deadline,
    );
  }
}

/// 아이폰 알림에 붙는 버튼 두 개.
///
/// 둘 다 앱을 열지 않는다. 딴짓하는 중에 앱까지 열리면, 챙겨주려던 것이
/// 방해가 된다.
final DarwinNotificationCategory nyangBannerCategory =
    DarwinNotificationCategory(
      NyangBannerNudge.categoryId,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(
          NyangBannerNudge.actionStartNow,
          '시작할게',
        ),
        DarwinNotificationAction.plain(NyangBannerNudge.actionLater, '좀 더 있다가'),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    );

/// 도는 일정을 확인하는 배너에 붙는 버튼 셋. 안드로이드 카드와 같은 답이다.
final DarwinNotificationCategory nyangBannerRunningCategory =
    DarwinNotificationCategory(
      NyangBannerNudge.runningCategoryId,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain(NyangBannerNudge.actionDone, '다 했어'),
        DarwinNotificationAction.plain(
          NyangBannerNudge.actionKeepGoing,
          '계속하는 중',
        ),
        DarwinNotificationAction.plain(
          NyangBannerNudge.actionRestart,
          '다시 시작할게',
        ),
      ],
      options: <DarwinNotificationCategoryOption>{
        DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
      },
    );

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
