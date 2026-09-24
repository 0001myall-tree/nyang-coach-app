import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/user_data.dart';
import 'active_coaching_sync.dart';
import 'coach_tier_flags.dart';
import 'gap_coaching_service.dart';
import 'ongoing_task_nudge_service.dart';

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
/// 배너에는 버튼을 달지 않는다. 눌러서 앱을 열면 그 일정 칸이 번쩍여 어디를
/// 볼지 알려주고, 거기서 손으로 한다. 버튼을 달았던 때는 꾹 눌러야 나오는 데다,
/// 화면 없는 갈래에서 코드가 도는 길이라 잘못되면 앱이 통째로 꺼졌다.
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

  /// 어느 배너를 눌렀는지('start'/'running'/'resume'/'nextTask'). 할 일 창이
  /// 이 값을 보고 안드로이드 딴짓 방지 카드와 같은 질문을 팝업으로 띄운다.
  static const String answerKindKey = 'banner_answer_kind';

  /// 팝업에 그대로 쓸 일정 이름. 목록을 다시 뒤져 찾을 필요 없게 payload에
  /// 실려온 것을 그대로 남겨둔다.
  static const String answerTaskTextKey = 'banner_answer_task_text';

  /// 시작하고 처음 확인하기까지. 안드로이드 냥냥이와 같은 간격이다.
  static const Duration firstCheck = Duration(minutes: 30);

  /// 한 번 묻고 다음에 다시 묻기까지.
  static const Duration nextRound = Duration(hours: 1);

  /// 한 번에 하나만 걸어둔다. 다음 일정은 이 자리를 덮어쓴다.
  static const int notificationId = 1300;

  /// 도는 일정을 확인하는 배너의 자리들.
  ///
  /// 여러 개를 미리 걸어둔다. 안드로이드 냥냥이는 스스로 다음 차례를 잡지만,
  /// 배너는 앱 안에서만 걸 수 있어서 한 번 뜨고 나면 앱을 다시 열기 전까지
  /// 다음이 없었다. 일정을 켜둔 채 다른 앱에 있는 동안이 정확히 이 기능이
  /// 필요한 시간인데, 그때가 통째로 비어 있었다.
  static const List<int> runningNotificationIds = [1302, 1303, 1304, 1305];

  /// 방금 하나를 끝냈고 시간이 정해지지 않은 다음 일이 남았을 때의 자리들.
  ///
  /// 마스터 플랜 전용. 안드로이드는 매번 깨어나 조건을 다시 보고 정하지만,
  /// 아이폰은 그럴 수 없어서 완료 시각을 기준으로 22시까지 2시간 간격 자리를
  /// 한꺼번에 걸어둔다. 대신 [sync]가 저장이 일어날 때마다 전부 지우고 지금
  /// 상태로 다시 까는 것으로 "매번 조건을 다시 검사"를 흉내 낸다.
  static const List<int> nextTaskNotificationIds = [
    1306,
    1307,
    1308,
    1309,
    1310,
    1311,
  ];

  /// 시작해뒀다 멈춘 지 3시간 넘은 일을 다시 부르는 자리들. [nextTaskNotificationIds]와
  /// 같은 방식이고, 대상이 "시간이 정해지지 않은 새 일"이 아니라 "이미 손댄 그 일"이다.
  static const List<int> resumeNotificationIds = [
    1312,
    1313,
    1314,
    1315,
    1316,
    1317,
  ];

  /// 틈새 코칭 자리들. 시간 슬롯 3개 × 오늘/내일.
  ///
  /// 내일 것까지 미리 거는 이유는, 앱을 하루 안 열어도 그날 한 번은 찾아가야
  /// 하기 때문이다. 앱을 열거나 할 일을 저장하면 전부 지워지고 지금 상태로
  /// 다시 깔린다.
  ///
  /// [GapCoachingService.maxTimes]만큼 × 2일이 들어갈 자리가 있어야 한다.
  /// 모자라면 뒤쪽 자리가 조용히 안 걸린다.
  static const List<int> gapNotificationIds = [
    1318,
    1319,
    1320,
    1321,
    1322,
    1323,
  ];

  /// 적극 코칭 개입 자리. 하나뿐이다.
  ///
  /// 다음 한 번만 걸어둔다. 여러 개를 미리 걸면 그 사이에 목록이 바뀌었을 때
  /// 이미 끝낸 일을 부르게 되고, 아이폰의 예약 알림은 조건이 바뀌어도 스스로
  /// 취소되지 않는다.
  static const int activeNotificationId = 1324;

  /// 적극 코칭 배너 제목. 본문은 Dart가 미리 정해둔 한 줄이다.
  static const String activeTitle = '🐾 냥냥코치';

  /// 배너 제목. 본문은 그때 남은 일을 보고 [GapCoachingService.bodyFor]가 고른다.
  static const String gapTitle = '🐾 지금 잠깐 여유 있냥?';

  static const Duration _nextTaskRound = Duration(hours: 2);

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
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool('nyang_core_reminder_enabled') ?? false) ||
        await OngoingTaskNudgeService.isEnabled();
  }

  /// 저장된 할 일을 보고 다음 배너를 걸어둔다. 걸 것이 없으면 지운다.
  ///
  /// 일정에 붙는 배너는 한 번에 하나만 건다 — 시작하라는 말과 하는 중이냐는
  /// 말이 같이 오면 안 된다. 틈새 코칭은 그 뒤에 따로 본다. 하는 일이 겹치지
  /// 않지만, 같은 시간대에 둘이 겹치면 틈새 코칭 쪽이 물러난다.
  static Future<void> sync() async {
    if (!_isIOS) return;
    await _plugin.cancel(id: notificationId);
    for (final id in runningNotificationIds) {
      await _plugin.cancel(id: id);
    }
    for (final id in nextTaskNotificationIds) {
      await _plugin.cancel(id: id);
    }
    for (final id in resumeNotificationIds) {
      await _plugin.cancel(id: id);
    }
    for (final id in gapNotificationIds) {
      await _plugin.cancel(id: id);
    }
    await _plugin.cancel(id: activeNotificationId);

    final needed = await isNeededHere();
    // "다음 일" 카드는 딴짓 방지 스위치나 일정 알림과 무관하게, 마스터 플랜이면
    // 그 자체로 켜져 있는 기본 동작이다.
    final userData = await UserDataService.load();
    final masterEligible =
        userData.isPlanActive && userData.planType == 'master';
    if (!needed && !masterEligible) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString('nyang_tasks');

    List tasks = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        tasks = jsonDecode(raw) as List;
      } catch (_) {
        return;
      }
    }

    final now = DateTime.now();
    // 정해둔 시각마다 따로 배너를 걸던 자리가 여기 있었다. 지금은 적극 코칭이
    // 그 시각을 후보로 받아 하나로 묶어 부른다 — 둘 다 두면 말투도 내용도
    // 다른 배너가 1분 사이에 두 번 온다.
    await _syncTaskBanners(
      tasks,
      now,
      needed: needed,
      masterEligible: masterEligible,
    );
    if (masterEligible) await _scheduleActivePlan(prefs, now);
  }

  /// 적극 코칭이 미리 세워둔 계획 하나를 건다.
  ///
  /// 계산은 Dart가 이미 해뒀다. 여기서는 그 시각과 문장을 읽어 걸기만 한다 —
  /// 안드로이드 카드가 읽는 것과 같은 자리다.
  static Future<void> _scheduleActivePlan(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    final raw = prefs.getString(ActiveCoachingSync.plannedKey);
    if (raw == null || raw.isEmpty) return;
    final Map decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return;
      decoded = parsed;
    } catch (_) {
      return;
    }
    final millis = (decoded['at'] as num?)?.toInt();
    if (millis == null) return;
    final at = DateTime.fromMillisecondsSinceEpoch(millis);
    if (!at.isAfter(now)) return;
    final body = decoded['title']?.toString().replaceAll('\n', ' ').trim();
    if (body == null || body.isEmpty) return;

    _ensureTimeZone();
    await _plugin.zonedSchedule(
      id: activeNotificationId,
      title: activeTitle,
      body: body,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        iOS: DarwinNotificationDetails(
          // 앱을 보고 있는 동안에는 띄우지 않는다. 할 일이 이미 눈앞에 있는
          // 사람에게 그 위로 배너를 내리면 그건 참견이 아니라 방해다.
          // 안드로이드 카드도 같은 자리에서 접힌다.
          presentAlert: false,
          presentBanner: false,
          presentList: true,
          presentSound: false,
          // 방해금지를 뚫지 않는다. 조용히 해둔 사람에게 굳이 비집고 들어갈
          // 말이 아니다 — 알림 센터에는 남으므로 볼 기회는 그대로 있다.
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload:
          '$payloadPrefix:${jsonEncode({'kind': decoded['kind']?.toString() == 'night' ? 'activeCoachingNight' : 'activeCoaching', 'taskId': decoded['taskId']?.toString() ?? '', 'taskText': ''})}',
    );
  }

  /// 일정에 붙는 배너를 건다.
  static Future<void> _syncTaskBanners(
    List tasks,
    DateTime now, {
    required bool needed,
    required bool masterEligible,
  }) async {
    if (tasks.isEmpty) return;

    // 시작할 시각이 먼저다.
    //
    // 도는 일정이 있어도 마찬가지다. 하는 중이냐는 물음은 미뤄도 그 일이 없어지지
    // 않지만, 시작하기로 한 시각은 지나가면 그날치가 사라진다. 그 시각이 정리된
    // 뒤에 — 시작했거나, 창이 닫혔거나 — 하는 중이냐는 물음이 자리를 잇는다.
    if (needed) {
      final next = OngoingTaskNudgeService.nextUnstartedTask(tasks, now);
      if (next != null) {
        final at = next['_startAt'] as DateTime;
        await _schedule(
          taskId: next['id'].toString(),
          taskText: next['text']?.toString() ?? '',
          at: at,
          deadline: at.add(window),
        );
        return;
      }
    }

    Map<String, dynamic>? running;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] != true) continue;
      running = Map<String, dynamic>.from(item);
      break;
    }

    if (running != null) {
      // 딴짓 방지 스위치를 켠 사람에게만 "지금도 하는 중이야?"를 건다. 스위치가
      // 꺼져 있어도 무언가 도는 중이면, 다음 일 카드는 얹지 않는다 — 이미 손을
      // 대고 있는 사람에게 다른 걸 또 권하면 안 된다.
      if (needed) {
        await _scheduleRunningCheck(
          taskId: running['id'].toString(),
          taskText: running['text']?.toString() ?? '',
          runStartedAt: DateTime.tryParse(
            running['runStartedAt']?.toString() ?? '',
          ),
        );
      }
      return;
    }

    // 적극 코칭이 이 둘을 이미 본다 — 멈춘 일은 사다리 3번, 시간이 안 정해진
    // 남은 일은 5번이다. 둘 다 두면 같은 일로 두 번 부르게 된다.
    if (masterEligible && !await GapCoachingService.isEnabled()) {
      // 이미 손댄 일을 다시 붙잡을지가, 아직 안 건드린 일을 새로 시작할지보다
      // 앞선다.
      if (await _syncResumeNudge(tasks, now)) return;
      await _syncNextTaskNudge(tasks, now);
      return;
    }
  }

  /// 시작해뒀다 멈춘 지 3시간 넘은 일을 다시 부르는 알림 사슬을 다시 깐다.
  /// 하나라도 걸었으면 true.
  static Future<bool> _syncResumeNudge(List tasks, DateTime now) async {
    Map<String, dynamic>? candidate;
    DateTime? pausedAt;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) <= 0) continue;
      final paused = DateTime.tryParse(item['pausedAt']?.toString() ?? '');
      if (paused == null) continue;
      candidate = Map<String, dynamic>.from(item);
      pausedAt = paused;
      break;
    }
    if (candidate == null || pausedAt == null) return false;

    var at = pausedAt.add(const Duration(hours: 3));
    while (!at.isAfter(now)) {
      at = at.add(_nextTaskRound);
    }

    final taskId = candidate['id'].toString();
    final taskText = candidate['text']?.toString() ?? '';
    var scheduled = false;
    for (var i = 0; i < resumeNotificationIds.length; i++) {
      final fireAt = at.add(_nextTaskRound * i);
      if (fireAt.hour >= 22) break;
      await _scheduleResume(
        id: resumeNotificationIds[i],
        taskId: taskId,
        taskText: taskText,
        at: fireAt,
      );
      scheduled = true;
    }
    return scheduled;
  }

  static Future<void> _scheduleResume({
    required int id,
    required String taskId,
    required String taskText,
    required DateTime at,
  }) async {
    _ensureTimeZone();
    final payload =
        '$payloadPrefix:${jsonEncode({'kind': 'resume', 'taskId': taskId, 'taskText': taskText})}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: false,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: '🐾 ${taskText.isEmpty ? '멈춰 있는 일' : taskText}',
      body: '하다가 멈췄네. 다시 시작할까냥?',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 방금 하나를 끝냈고 시간이 정해지지 않은 다음 일이 남았을 때의 알림 사슬을
  /// 다시 깐다.
  ///
  /// 안드로이드는 깨어날 때마다 조건을 다시 보지만, 아이폰의 예약 알림은 한 번
  /// 걸면 조건이 바뀌어도 스스로 취소되지 않는다. 그래서 여기서 매번 통째로
  /// 지우고 지금 상태로 새로 깐다 — 저장이 일어날 때마다(완료·시작·수정) [sync]가
  /// 불리므로, 사실상 매번 조건을 다시 검사하는 것과 같다.
  static Future<void> _syncNextTaskNudge(List tasks, DateTime now) async {
    DateTime? anchor;
    for (final item in tasks) {
      if (item is! Map || item['done'] != true) continue;
      final completedAt = DateTime.tryParse(
        item['completedAt']?.toString() ?? '',
      );
      if (completedAt == null) continue;
      if (anchor == null || completedAt.isAfter(anchor)) anchor = completedAt;
    }
    // 오늘 끝낸 일이 없으면 기준으로 삼을 시각이 없다.
    if (anchor == null) return;

    // 안 끝난 일 중에 시간이 정해진 게 하나라도 있으면 걸지 않는다. 곧 있을
    // 약속을 앞두고 다른 것도 시작할지 물으면, 정작 지켜야 할 시각에 마음을
    // 못 쓰게 만든다.
    final hasTimedRemaining = tasks.any((item) {
      if (item is! Map || item['done'] == true) return false;
      final timeStart = item['timeStart']?.toString();
      return timeStart != null && timeStart.isNotEmpty;
    });
    if (hasTimedRemaining) return;

    Map<String, dynamic>? candidate;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['category'] == 'schedule') continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) continue;
      final timeStart = item['timeStart']?.toString();
      if (timeStart != null && timeStart.isNotEmpty) continue;
      candidate = Map<String, dynamic>.from(item);
      break;
    }
    if (candidate == null) return;

    // 완료 시각을 기준으로 3, 5, 7시간… 자리를 잡는다. 지금이 이미 그 자리를
    // 지났으면(오래 앱을 안 열었던 경우) 지금 이후의 다음 자리부터 잇는다 —
    // 지난 자리에 알림을 걸면 곧바로 울리거나 실패한다.
    var at = anchor.add(const Duration(hours: 3));
    while (!at.isAfter(now)) {
      at = at.add(_nextTaskRound);
    }

    final taskId = candidate['id'].toString();
    final taskText = candidate['text']?.toString() ?? '';
    for (var i = 0; i < nextTaskNotificationIds.length; i++) {
      final fireAt = at.add(_nextTaskRound * i);
      if (fireAt.hour >= 22) break;
      await _scheduleNextTask(
        id: nextTaskNotificationIds[i],
        taskId: taskId,
        taskText: taskText,
        at: fireAt,
      );
    }
  }

  static Future<void> _scheduleNextTask({
    required int id,
    required String taskId,
    required String taskText,
    required DateTime at,
  }) async {
    _ensureTimeZone();
    final payload =
        '$payloadPrefix:${jsonEncode({'kind': 'nextTask', 'taskId': taskId, 'taskText': taskText})}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBanner: true,
        presentList: true,
        presentSound: false,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.zonedSchedule(
      id: id,
      title: '🐾 ${taskText.isEmpty ? '남은 일' : taskText}',
      body: '냥이랑 남은 일정도 시작할까냥?',
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  /// 도는 일정에 "지금도 하는 중이야?"를 걸어둔다.
  ///
  /// 시작한 시각을 기준으로 30분 뒤에 묻는다. 저장이 일어날 때마다 다시 걸리는데,
  /// 기준이 시작 시각이라 물어볼 때가 뒤로 밀리지 않는다.
  static Future<List<DateTime>> _scheduleRunningCheck({
    required String taskId,
    required String taskText,
    DateTime? runStartedAt,
  }) async {
    final now = DateTime.now();
    var at = (runStartedAt ?? now).add(firstCheck);
    // 이미 지났으면 다음 차례로 넘긴다. 앱을 오랜만에 열었다고 해서 그 자리에서
    // 배너가 튀어나오면, 방금 앱을 연 사람에게 앱 밖에서 부르는 셈이 된다.
    if (!at.isAfter(now)) at = now.add(nextRound);

    // 플랜이 끝난 사람에게는 걸지 않는다. 스위치는 플랜이 있을 때 켜둔 채로
    // 남아 있을 수 있다.
    if (!await CoachTierFlags.isPaid()) return const [];

    // 앞으로 몇 차례를 한꺼번에 걸어둔다. 앱을 다시 열면 [sync]가 전부 지우고
    // 다시 깔기 때문에, 일정이 끝나거나 바뀌면 남은 차례도 함께 없어진다.
    final scheduled = <DateTime>[];
    for (var i = 0; i < runningNotificationIds.length; i++) {
      final fireAt = at.add(nextRound * i);
      await _scheduleRunning(
        id: runningNotificationIds[i],
        taskId: taskId,
        taskText: taskText,
        at: fireAt,
        startedAt: runStartedAt,
      );
      scheduled.add(fireAt);
    }
    return scheduled;
  }

  static Future<void> _scheduleRunning({
    required int id,
    required String taskId,
    required String taskText,
    required DateTime at,
    DateTime? startedAt,
  }) async {
    _ensureTimeZone();
    final payload =
        '$payloadPrefix:${jsonEncode({'kind': 'running', 'taskId': taskId, 'taskText': taskText})}';

    final details = NotificationDetails(
      iOS: DarwinNotificationDetails(
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
      id: id,
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

    final payload =
        '$payloadPrefix:${jsonEncode({'kind': 'start', 'taskId': taskId, 'taskText': taskText, 'deadline': deadline.millisecondsSinceEpoch})}';

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
      data =
          jsonDecode(payload.substring(payloadPrefix.length + 1))
              as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    final kind = data['kind']?.toString() ?? '';
    final taskId = data['taskId']?.toString() ?? '';
    // 적극 코칭이 "지금 뭐 할 수 있어?"를 물을 때는 가리킬 일이 없다. 그
    // 자리만 예외로, 이름 없이도 앱을 열어 팝업까지 간다.
    if (taskId.isEmpty && !kind.startsWith('activeCoaching')) return;

    // 앱이 열리면 할 일이 쭉 늘어서 있어서, 부른 쪽이 어느 것인지 알 수 없다.
    // 어느 칸을 볼지 적어두면 할 일 화면이 그 칸을 번쩍여준다.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(focusTaskKey, taskId);

    // 어느 배너였는지도 같이 남긴다 - 안드로이드 딴짓 방지 카드와 같은
    // 질문을 팝업으로 띄우는 데 쓴다([answerKindKey] 참고).
    if (kind.isEmpty) {
      await prefs.remove(answerKindKey);
      await prefs.remove(answerTaskTextKey);
    } else {
      await prefs.setString(answerKindKey, kind);
      await prefs.setString(
        answerTaskTextKey,
        data['taskText']?.toString() ?? '',
      );
    }

    // 이것만으로는 화면이 안 바뀐다 - 배너를 눌러도 앱이 있던 자리 그대로
    // 켜지고, 할 일 탭이 열려 있을 때만 번쩍임이 보였다. 위젯 눌렀을 때
    // 쓰는 것과 같은 자리표를 남겨서, 콜드 스타트(main.dart)와 웜
    // 리줌(main_tab_screen.dart의 _checkWidgetIntent) 양쪽이 이미 하던
    // 대로 할 일 창을 열게 한다.
    await prefs.setString('widget_route', 'tasks');
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
