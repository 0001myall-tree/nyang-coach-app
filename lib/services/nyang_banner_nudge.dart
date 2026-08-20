import 'dart:convert';

import 'package:flutter/foundation.dart';
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
  static const String categoryId = 'nyang_banner_start';
  static const String actionStartNow = 'nyang_banner_start_now';
  static const String actionLater = 'nyang_banner_later';

  /// 한 번에 하나만 걸어둔다. 다음 일정은 이 자리를 덮어쓴다.
  static const int notificationId = 1300;

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
  static Future<void> sync() async {
    if (!_isIOS) return;
    await _plugin.cancel(id: notificationId);
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

    // 이미 도는 일정이 있으면 시작을 권할 일이 없다. 라이브 액티비티가 맡는다.
    for (final item in tasks) {
      if (item is Map && item['done'] != true && item['inProgress'] == true) {
        return;
      }
    }

    final next = OngoingTaskNudgeService.nextUnstartedTask(tasks, DateTime.now());
    if (next == null) return;

    await _schedule(
      taskId: next['id'].toString(),
      taskText: next['text']?.toString() ?? '',
      at: next['_startAt'] as DateTime,
      deadline: (next['_startAt'] as DateTime).add(window),
    );
  }

  /// 시작 시각을 기다리지 않고 지금 한번 확인한다.
  ///
  /// 이 기능은 정해둔 시각이 와야 확인되는데, 그 시각을 기다렸다가 안 오면
  /// 무엇이 막고 있는지 알 길이 없다. 설정 안에 지금 보는 길이 있어야 한다.
  static Future<void> showTest() async {
    if (!_isIOS) return;
    final now = DateTime.now();
    await _schedule(
      taskId: 'nyang_banner_test',
      taskText: '지금 한번 보기',
      at: now.add(const Duration(seconds: 8)),
      // 확인용이라 "좀 더 있다가"로 다시 부를 일은 없다.
      deadline: now.add(const Duration(minutes: 1)),
    );
  }

  static Future<void> _schedule({
    required String taskId,
    required String taskText,
    required DateTime at,
    required DateTime deadline,
  }) async {
    if (at.isAfter(deadline)) return;

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
      id: notificationId,
      title: '🐾 ${taskText.isEmpty ? '지금 시작하기로 한 일' : taskText}',
      body: '시작하는 거 잊지 않았지?',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 배너에서 고른 답을 처리한다. 앱이 떠 있든 아니든 같은 길을 탄다.
  static Future<void> handle(NotificationResponse response) async {
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

    switch (response.actionId) {
      case actionStartNow:
        // 여기서 바로 시작으로 적는다. 앱에 들어가 ▶를 다시 누르게 하면,
        // 시작하겠다고 말한 사람에게 한 칸을 더 시키는 셈이다.
        await TaskCompletionService.startStoredTask(taskId: taskId);
        return;
      case actionLater:
        await _rescheduleLater(data);
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

    // 앱이 아니라 알림에서 깨어난 갈래일 수 있다. 그쪽 격리 공간에는 시간대가
    // 아직 준비되어 있지 않아서, 예약 전에 여기서 세워둔다.
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    } catch (_) {}

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

const String nyangBannerPayload = NyangBannerNudge.payloadPrefix;

Future<void> handleNyangBannerResponse(NotificationResponse response) =>
    NyangBannerNudge.handle(response);

/// 앱이 떠 있지 않을 때 버튼을 누르면 이쪽으로 온다. 별도의 격리 공간에서
/// 도는 갈래라 최상위 함수여야 하고, 지워지지 않게 표시해 두어야 한다.
@pragma('vm:entry-point')
void nyangBannerBackgroundHandler(NotificationResponse response) {
  NyangBannerNudge.handle(response);
}
