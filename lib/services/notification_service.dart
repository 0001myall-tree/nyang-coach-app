import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../main.dart';
import '../screens/morning_call_screen.dart';
import '../screens/core_reminder_screen.dart';
import '../screens/coach_config.dart';
import '../screens/main_tab_screen.dart';
import 'analytics_service.dart';
import 'coach_id_service.dart';
import 'morning_call_alarm_session.dart';
import 'nyang_banner_nudge.dart';
import 'preemptive_nudge_service.dart';
import 'tasks_sync_service.dart';
import 'user_title_service.dart';
import '../models/user_data.dart';

/// 알람(모닝콜·일정 알람)이 실제로 울릴 수 있는지를 막고 있는 권한.
/// 둘 다 같은 시스템 권한을 쓰기 때문에 한 가지로 본다.
/// [notifications]가 없으면 알람 시각에 백그라운드에서 아무 소리도 나지 않는다.
/// (네이티브 수신부가 알림을 못 만들고 그대로 종료되기 때문에, 나중에 앱을 열어야
///  밀린 알람이 그제서야 울린다.) 나머지 둘은 소리는 나지만 화면 표시가 제한된다.
enum AlarmPermissionIssue { none, notifications, exactAlarm, fullScreen }

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const MethodChannel _androidAlarmChannel = MethodChannel(
    'nyang_coach/morning_alarm',
  );
  static const int _morningCallRepeatCount = 3;
  static const int _maxScheduledCoreReminders = 50;
  static const Set<int> _coreReminderSoundMinutes = {10, 30};
  static const int _dailyPlannerNudgeNotificationId = 889;
  static const int _dailyPlannerNudgeHour = 12;
  static const int _dailyPlannerNudgeMinute = 5;
  static const String _androidMorningChannelVersion = 'v10';
  static const String _androidCoreReminderChannelVersion = 'v4';
  static const bool _releaseCoreReminderVoiceAlarmEnabled = false;
  static const String _androidPushChannelId = 'nyang_push_channel';
  static const String _staleScheduleCleanupKey =
      'nyang_stale_schedule_cleanup_v1';
  static const String _androidFocusTimerChannelId =
      'nyang_focus_timer_channel_v3';
  /// 낮에 보낸 선제 메시지를 채팅으로 이어붙이려고 남겨두는 자리.
  ///
  /// 'nyang_'으로 시작하지 않는 키를 쓴다. 그 접두어는 클라우드 복원이
  /// 덮어써서 기기마다 다른 값이 되어야 하는 것을 담기에 맞지 않는다.
  static const String pendingNudgeKey = 'preemptive_nudge_pending';

  /// 이미 울려서 채팅이 이어받을 차례인 선제 메시지.
  static const String firedNudgeKey = 'preemptive_nudge_fired';

  /// 예약해둔 선제 메시지가 이미 울렸으면 채팅이 이어받을 자리로 옮긴다.
  ///
  /// 울리는 순간에 코드가 도는 게 아니라서, 예약 시각이 지났다는 사실로 울린
  /// 것을 안다. 옮겨두지 않으면 다음 예약이 그 위에 덮어써서, 푸시를 눌러
  /// 들어온 사람에게 방금 받은 말이 사라진다.
  ///
  /// 예약을 갈아끼우는 쪽과 채팅 양쪽에서 부른다. 어느 쪽이 먼저 돌아도
  /// 결과가 같아야 해서 여러 번 불러도 되게 두었다.
  static Future<void> promoteFiredNudge(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    final raw = prefs.getString(pendingNudgeKey);
    if (raw == null) return;
    DateTime? firesAt;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        firesAt = DateTime.tryParse(decoded['firesAt']?.toString() ?? '');
      }
    } catch (_) {}
    if (firesAt == null || now.isBefore(firesAt)) return;
    await prefs.setString(firedNudgeKey, raw);
    await prefs.remove(pendingNudgeKey);
  }
  String? _lastMorningPayload;
  DateTime? _lastMorningOpenedAt;

  String _morningCallChannelId(String? soundName) {
    return 'nyang_morning_call_${soundName ?? 'default'}_$_androidMorningChannelVersion';
  }

  String _coreReminderChannelId(String? soundName) {
    return 'nyang_core_reminder_${soundName ?? 'push'}_$_androidCoreReminderChannelVersion';
  }

  /// 일정 알람의 중복 발사를 막는 키.
  /// payload를 ':'로 잘라 읽기 때문에 키 안에 ':'이 들어가면 안 된다
  /// (시각의 ':'이 그대로 남으면 뒤쪽 일정 이름 자리로 밀려 들어간다).
  static String coreReminderFireKey({
    required Object? alarmId,
    required DateTime targetDate,
    required String dateKey,
  }) {
    final stamp = targetDate.toIso8601String().replaceAll(':', '-');
    return 'reminder_${alarmId}_${stamp}_$dateKey';
  }

  String? _coreReminderSoundName(String coachId, int advanceMinutes) {
    final normalizedCoachId = CoachIdService.normalize(
      coachId,
      fallback: 'push',
    );
    if (normalizedCoachId == 'push') return null;
    if ((CoachConfigs.get(normalizedCoachId).voiceCount) <= 0) return null;
    if (!_coreReminderSoundMinutes.contains(advanceMinutes)) return null;
    return '${normalizedCoachId}_reminder_$advanceMinutes';
  }

  ({String coachId, String? soundName}) _parseMorningPayload(String payload) {
    if (!payload.startsWith('morning:')) {
      return (coachId: CoachIdService.normalize(payload), soundName: null);
    }
    final parts = payload.split(':');
    return (
      coachId: CoachIdService.normalize(parts.length > 1 ? parts[1] : 'cat'),
      soundName: parts.length > 2 ? parts[2] : null,
    );
  }

  Future<void> _openMorningCall(String payload) async {
    final now = DateTime.now();
    if (_lastMorningPayload == payload &&
        _lastMorningOpenedAt != null &&
        now.difference(_lastMorningOpenedAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastMorningPayload = payload;
    _lastMorningOpenedAt = now;

    // Removed 1-time per day restriction so users can test the morning call multiple times.
    // Instead of completely blocking it for the day, we just rely on the 2-second debounce above.
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_last_morning_call_date', todayStr);

    final parsed = _parseMorningPayload(payload);
    AnalyticsService.logFeatureUsage('morning_call');
    MorningCallAlarmSession().start(
      coachId: parsed.coachId,
      soundName: parsed.soundName,
      initialDelay: const Duration(seconds: 3),
    );
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => MorningCallScreen(
          coachId: parsed.coachId,
          soundName: parsed.soundName,
        ),
      ),
    );

    // Reschedule next morning call (picks a new random coach for tomorrow)
    await rescheduleNextMorningCall();
  }

  Future<void> _openCoreReminder(String payload) async {
    // payload format: core:coachId:soundName:fireKey:taskText (or old format: core:coachId:soundName:taskText)
    final parts = payload.split(':');
    if (parts.length >= 4) {
      final coachId = CoachIdService.normalize(parts[1]);
      final soundName = parts[2].isEmpty ? null : parts[2];

      String fireKey = '';
      String taskText = '';
      if (parts.length >= 5 && parts[3].startsWith('reminder_')) {
        fireKey = parts[3];
        taskText = parts.sublist(4).join(':');
      } else {
        taskText = parts.sublist(3).join(':');
      }

      // 예약 시각의 ':'을 그대로 담던 옛 payload가 남아 있으면
      // 일정 이름 앞에 "50:00.000_2026-08-18:" 같은 찌꺼기가 붙는다. 떼어낸다.
      taskText = taskText.replaceFirst(
        RegExp(r'^\d{2}:\d{2}\.\d{3}_\d{4}-\d{2}-\d{2}:'),
        '',
      );

      if (fireKey.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final firedList =
            prefs.getStringList('nyang_fired_core_reminders') ?? [];
        if (!firedList.contains(fireKey)) {
          firedList.add(fireKey);
          await prefs.setStringList('nyang_fired_core_reminders', firedList);
        }
      }

      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => CoreReminderScreen(
            coachId: coachId,
            soundName: soundName,
            taskText: taskText,
          ),
        ),
      );
    }
  }

  Future<void> _openDailyPlannerNudge(String payload) async {
    final parts = payload.split(':');
    final coachId = CoachIdService.normalize(
      parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'cat',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_daily_planner_nudge_last_opened_at',
      DateTime.now().toIso8601String(),
    );
    await prefs.setString(
      'nyang_last_app_active_at',
      DateTime.now().toIso8601String(),
    );
    await UserDataService.setSelectedCoach(coachId);
    AnalyticsService.logFeatureUsage('daily_planner_nudge_push');
    await recordPlannerOpened();

    // 채팅으로 들여보낸다. 코치가 방금 건넨 말이 거기 떠 있고, 그 자리에서
    // 바로 답할 수 있다. 할 일 창을 먼저 띄우면 그 말이 가려져서, 푸시와
    // 채팅이 따로 노는 예전 모양으로 돌아간다.
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainTabScreen(coachId: coachId)),
      (route) => false,
    );
  }

  Future<void> init() async {
    if (kIsWeb) return;
    // 여기서 예외가 나면 아래 _plugin.initialize()까지 통째로 건너뛰어 알림이 전부 죽는다.
    // tz는 iOS 예약에만 쓰이므로 실패해도 나머지 초기화는 계속 진행한다.
    try {
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
      debugPrint('타임존 초기화 완료: tz.local=${tz.local.name}');
    } catch (e) {
      debugPrint('타임존 초기화 실패: $e');
    }
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    final DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentSound: true,
          notificationCategories: const <DarwinNotificationCategory>[],
        );
    final InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveBackgroundNotificationResponse: nyangBannerBackgroundHandler,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        if (payload != null && payload.startsWith('$nyangBannerPayload:')) {
          await handleNyangBannerResponse(response);
          return;
        }
        if (payload == null) return;
        if (payload.startsWith('core:')) {
          _openCoreReminder(payload);
          return;
        }
        if (payload.startsWith('morning:')) {
          await _openMorningCall(payload);
          return;
        }
        if (payload.startsWith('daily_planner_nudge:') ||
            payload.startsWith('inactive_return:')) {
          await _openDailyPlannerNudge(payload);
        }
      },
    );
    await _ensureAndroidNotificationChannels();
    await _purgeStaleScheduledNotificationsOnce();
  }

  /// 기기에 남아 있는 예약 알림을 한 번만 전부 지운다.
  ///
  /// 타임존을 기기 설정에서 자동 감지하던 기간(2026-07-20 ~ 07-28)에 예약된 알림들이
  /// 잘못된 시각으로 등록돼 엉뚱한 때 울렸다. 코드는 Asia/Seoul로 되돌렸지만 기기에 이미
  /// 박힌 예약은 그대로 남기 때문에, 한 번 싹 지우고 아래 sync들이 다시 예약하게 한다.
  /// (main.dart에서 init() 직후 syncDailyMorningCall / syncCoreReminders가 호출된다.)
  Future<void> _purgeStaleScheduledNotificationsOnce() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_staleScheduleCleanupKey) ?? false) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('예약 알림 초기화 실패: $e');
      return;
    }
    await prefs.setBool(_staleScheduleCleanupKey, true);
  }

  Future<void> _ensureAndroidNotificationChannels() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;

    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidPushChannelId,
        '기본 푸시 알림',
        description: '냥냥코치 기본 푸시 알림입니다.',
        importance: Importance.max,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _androidFocusTimerChannelId,
        '집중 타이머',
        description: '집중 타이머 완료 알림입니다.',
        importance: Importance.max,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _morningCallChannelId(null),
        '냥냥코치 모닝콜',
        description: '냥냥코치 모닝콜 알람입니다.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 450, 180, 450, 350, 900]),
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
    await android.createNotificationChannel(
      AndroidNotificationChannel(
        _coreReminderChannelId(null),
        '냥냥코치 일정 알림',
        description: '지정된 일정 시작 전 알림입니다.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );

    final voiceCoachIds = CoachConfigs.all.values
        .where((coach) => coach.voiceCount > 0)
        .map((coach) => coach.id);
    for (final coachId in voiceCoachIds) {
      final count = CoachConfigs.get(coachId).voiceCount;
      for (int i = 1; i <= count; i++) {
        final soundName = '${coachId}_$i';
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            _morningCallChannelId(soundName),
            '냥냥코치 모닝콜',
            description: '냥냥코치 모닝콜 알람입니다.',
            importance: Importance.max,
            sound: RawResourceAndroidNotificationSound(soundName),
            playSound: true,
            enableVibration: true,
            vibrationPattern: Int64List.fromList([0, 450, 180, 450, 350, 900]),
            audioAttributesUsage: AudioAttributesUsage.alarm,
          ),
        );
      }

      if (_releaseCoreReminderVoiceAlarmEnabled) {
        for (final minutes in _coreReminderSoundMinutes) {
          final soundName = '${coachId}_reminder_$minutes';
          await android.createNotificationChannel(
            AndroidNotificationChannel(
              _coreReminderChannelId(soundName),
              '냥냥코치 일정 알림',
              description: '지정된 일정 시작 전 알림입니다.',
              importance: Importance.max,
              sound: RawResourceAndroidNotificationSound(soundName),
              playSound: true,
              enableVibration: true,
              audioAttributesUsage: AudioAttributesUsage.alarm,
            ),
          );
        }
      }
    }
  }

  Future<bool> requestNotificationPermissions() async {
    if (kIsWeb) return true;

    final androidAllowed =
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        true;
    final iosAllowed =
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        true;

    return androidAllowed && iosAllowed;
  }

  /// 이 기기에서 앱 알림이 켜져 있는지.
  ///
  /// 처음 물었을 때 거절하면 시스템은 다시 묻지 않는다. 그 뒤로는 설정에서
  /// 직접 켜는 수밖에 없어서, 알림에 기대는 기능은 켤 때마다 이것을 확인해야
  /// 한다. 확인하지 않으면 켜졌다고 적힌 채 아무것도 오지 않는다.
  Future<bool> areNotificationsEnabled() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      return granted?.isEnabled ?? true;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled() ??
        true;
  }

  Future<bool> _invokeAndroidAlarmPermissionCheck(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      return await _androidAlarmChannel.invokeMethod<bool>(method) ?? true;
    } catch (_) {
      return true;
    }
  }

  Future<void> _openAndroidAlarmPermissionSettings(String method) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _androidAlarmChannel.invokeMethod(method);
    } catch (_) {}
  }

  Future<bool> canUseMorningCallFullScreen() async {
    return _invokeAndroidAlarmPermissionCheck('canUseFullScreenIntent');
  }

  /// 알람(모닝콜·일정 알람)을 막고 있는 권한을 하나 찾아 돌려준다. 설정 화면은 열지 않는다.
  /// 여러 개가 없을 수 있으므로 가장 치명적인 것(알림 권한)부터 확인한다.
  Future<AlarmPermissionIssue> checkAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return AlarmPermissionIssue.none;
    }
    if (!await _invokeAndroidAlarmPermissionCheck('canPostNotifications')) {
      return AlarmPermissionIssue.notifications;
    }
    if (!await _invokeAndroidAlarmPermissionCheck('canScheduleExactAlarms')) {
      return AlarmPermissionIssue.exactAlarm;
    }
    if (!await canUseMorningCallFullScreen()) {
      return AlarmPermissionIssue.fullScreen;
    }
    return AlarmPermissionIssue.none;
  }

  /// [checkAlarmPermission]이 찾아낸 권한의 시스템 설정 화면을 연다.
  Future<void> openAlarmPermissionSettings(
    AlarmPermissionIssue issue,
  ) async {
    switch (issue) {
      case AlarmPermissionIssue.notifications:
        await _openAndroidAlarmPermissionSettings('openNotificationSettings');
      case AlarmPermissionIssue.exactAlarm:
        await _openAndroidAlarmPermissionSettings('openExactAlarmSettings');
      case AlarmPermissionIssue.fullScreen:
        await _openAndroidAlarmPermissionSettings(
          'openFullScreenIntentSettings',
        );
      case AlarmPermissionIssue.none:
        break;
    }
  }

  Future<bool> ensureMorningCallPresentationPermission({
    bool openSettings = false,
  }) async {
    final canPostNotifications = await _invokeAndroidAlarmPermissionCheck(
      'canPostNotifications',
    );
    final canScheduleExactAlarms = await _invokeAndroidAlarmPermissionCheck(
      'canScheduleExactAlarms',
    );
    final canUseFullScreen = await canUseMorningCallFullScreen();

    if (openSettings) {
      if (!canPostNotifications) {
        await _openAndroidAlarmPermissionSettings('openNotificationSettings');
      } else if (!canScheduleExactAlarms) {
        await _openAndroidAlarmPermissionSettings('openExactAlarmSettings');
      } else if (!canUseFullScreen) {
        await _openAndroidAlarmPermissionSettings(
          'openFullScreenIntentSettings',
        );
      }
    }

    return canPostNotifications && canScheduleExactAlarms && canUseFullScreen;
  }

  Future<void> handleLaunchNotification() async {
    if (kIsWeb) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;
    if (payload == null || details?.didNotificationLaunchApp != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (payload.startsWith('core:')) {
        _openCoreReminder(payload);
      } else if (payload.startsWith('morning:')) {
        _openMorningCall(payload);
      } else if (payload.startsWith('daily_planner_nudge:') ||
          payload.startsWith('inactive_return:')) {
        _openDailyPlannerNudge(payload);
      }
    });
  }

  Future<void> recordAppActive() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_last_app_active_at',
      DateTime.now().toIso8601String(),
    );
    await syncDailyPlannerNudge();
  }

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  DateTime _nextPlannerNudgeTime(DateTime now) {
    var scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      _dailyPlannerNudgeHour,
      _dailyPlannerNudgeMinute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = DateTime(
        now.year,
        now.month,
        now.day + 1,
        _dailyPlannerNudgeHour,
        _dailyPlannerNudgeMinute,
      );
    }
    return scheduled;
  }

  Future<void> recordPlannerOpened() async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_last_planner_open_date',
      _dateKey(DateTime.now()),
    );
    await syncDailyPlannerNudge();
  }

  List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  /// 낮에 코치가 먼저 부를지 정하고, 부를 말까지 만들어 예약해둔다.
  ///
  /// 알림은 예약할 때 글자가 고정된다. 12시에 깨어나 상태를 조회할 수단이
  /// 없으므로, 상태가 바뀔 만한 자리마다 이 함수를 다시 불러 예약을 갈아끼운다.
  /// 오전에 일을 시작하면 그 순간 예약이 취소되는 것도 이 방식 덕이다.
  Future<void> syncDailyPlannerNudge() async {
    if (kIsWeb) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_last_app_active_at', now.toIso8601String());
    await promoteFiredNudge(prefs, now);

    final scheduled = _nextPlannerNudgeTime(now);

    // 오늘 몫이 지나 내일로 잡히는 경우엔 내일 상태를 알 길이 없다. 자정이
    // 지나면 오늘 할 일은 비워지므로, 계획을 세우자는 말로 걸어두고 내일 앱을
    // 열 때 다시 계산한다.
    final isForToday = _dateKey(scheduled) == _dateKey(now);
    final nudge = isForToday
        ? PreemptiveNudgeService.decide(
            todayTasks: _decodeList(prefs.getString('nyang_tasks')),
            coreTasks: _decodeList(prefs.getString('nyang_core_tasks')),
            history: _decodeList(prefs.getString('nyang_history')),
          )
        : PreemptiveNudge(
            kind: NudgeKind.noPlan,
            message: PreemptiveNudgeService.noPlanMessages.first,
          );

    await _plugin.cancel(id: _dailyPlannerNudgeNotificationId);
    await prefs.remove(pendingNudgeKey);
    // 이미 움직이고 있는 사람에게는 보내지 않는다.
    if (nudge == null) return;

    const androidDetails = AndroidNotificationDetails(
      'nyang_daily_planner_nudge_v1',
      '냥냥코치 플래너 알림',
      channelDescription: '낮까지 플래너에 들어오지 않았을 때 냥냥코치가 가볍게 부릅니다.',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      audioAttributesUsage: AudioAttributesUsage.notification,
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 보낸 말을 남겨둔다. 푸시를 보고 곧바로 들어온 사람에게 채팅에서도 같은
    // 말을 보여주려면, 무엇을 보냈는지와 언제 울렸는지가 필요하다.
    await prefs.setString(
      pendingNudgeKey,
      jsonEncode({...nudge.toJson(), 'firesAt': scheduled.toIso8601String()}),
    );

    await _plugin.zonedSchedule(
      id: _dailyPlannerNudgeNotificationId,
      title: '냥냥코치',
      body: nudge.message.replaceAll('\n', ' '),
      scheduledDate: tz.TZDateTime.from(scheduled, tz.local),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'daily_planner_nudge:cat',
    );
  }

  Future<void> handleNativeMorningAlarm() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final payload = prefs.getString('native_morning_payload');
    if (payload == null || !payload.startsWith('morning:')) return;
    await prefs.remove('native_morning_payload');
    await prefs.remove('native_morning_alarm_at');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openMorningCall(payload);
    });
  }

  Future<void> scheduleDailyMorningCall({
    required int hour,
    required int minute,
    required String coachId,
  }) async {
    if (kIsWeb) return;
    for (int i = 0; i < _morningCallRepeatCount; i++) {
      await _plugin.cancel(id: i);
    }
    String targetCoachId = CoachIdService.normalize(coachId);

    if (targetCoachId == 'random') {
      final availableCoaches = CoachConfigs.all.values
          .where((coach) => coach.voiceCount > 0)
          .map((coach) => coach.id)
          .toList();
      if (availableCoaches.isNotEmpty) {
        targetCoachId =
            availableCoaches[Random().nextInt(availableCoaches.length)];
      } else {
        targetCoachId = 'cat';
      }
    } else if (!CoachConfigs.all.containsKey(targetCoachId)) {
      targetCoachId = 'cat';
    }
    // Save the resolved coach ID to SharedPreferences so the in-app engine can align with it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_morning_call_resolved_coach', targetCoachId);

    // CoachConfig에서 목소리 개수 읽기 → 나중에 목소리 추가 시 coach_config.dart만 수정하면 됨
    final count = CoachConfigs.get(targetCoachId).voiceCount;
    String? soundName;
    if (count > 0) {
      final randNum = Random().nextInt(count) + 1;
      soundName = '${targetCoachId}_$randNum';
    }
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _morningCallChannelId(soundName),
          '냥냥코치 모닝콜',
          channelDescription: '냥냥코치 모닝콜 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          sound: soundName != null
              ? RawResourceAndroidNotificationSound(soundName)
              : null,
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 450, 180, 450, 350, 900]),
          fullScreenIntent: true,
          category: AndroidNotificationCategory.alarm,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      sound: soundName != null ? '$soundName.caf' : null,
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 안드로이드는 AlarmManager에 epoch millis를 그대로 넘기고 기기 시계로 발화하므로
      // timezone 패키지를 거치지 않고 순수 DateTime(= 기기 로컬 시각)으로 계산한다.
      // tz.local이 Asia/Seoul이 아니라 UTC로 잡히면 벽시계 시각이 9시간 밀리기 때문이다.
      // (Kotlin의 MorningAlarmScheduler.rescheduleFromPrefs와 같은 계산이다.)
      final now = DateTime.now();
      var scheduled = DateTime(now.year, now.month, now.day, hour, minute);
      if (!scheduled.isAfter(now)) {
        // 날짜 필드를 +1 하면 서머타임이 있어도 벽시계 시각이 그대로 유지된다.
        scheduled = DateTime(now.year, now.month, now.day + 1, hour, minute);
      }
      await _androidAlarmChannel.invokeMethod('scheduleMorningAlarm', {
        'triggerMillis': scheduled.millisecondsSinceEpoch,
        'payload': 'morning:$targetCoachId:${soundName ?? ''}',
      });
      return;
    }

    final now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    // iOS cannot start the in-app audio loop from a killed/background state
    // without user interaction, so the system notification itself is the alarm.
    // Schedule a short burst so a locked phone behaves closer to a clock alarm.
    for (int i = 0; i < _morningCallRepeatCount; i++) {
      final targetTime = scheduled.add(Duration(minutes: i));
      await _plugin.zonedSchedule(
        id: i,
        title: '⏰ 모닝콜 시간입니다!',
        body: '코치가 깨우러 왔어요. 얼른 일어나세요!',
        scheduledDate: targetTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'morning:$targetCoachId:${soundName ?? ''}',
      );
    }
  }

  /// 알람이 막혔던 적이 있으면, 풀린 뒤에 예약을 다시 건다.
  ///
  /// 권한이 없는 채로 켠 알람은 스위치만 켜져 있고 예약이 서 있지 않을 수 있다.
  /// 사용자는 설정에서 알림을 켠 것으로 할 일을 다 했다고 여기므로, 돌아왔을 때
  /// 앱이 알아서 다시 걸어야 한다. 다시 말하게 하면 그 자리에서 포기한다.
  ///
  /// 'nyang_'으로 시작하지 않는 키를 쓴다. 그 접두어는 클라우드 복원이 덮어쓰는데,
  /// 이건 이 기기의 권한 상태라 기기마다 달라야 한다.
  static const String _alarmBlockedKey = 'alarm_permission_blocked';

  Future<void> reapplyAlarmsIfPermissionRecovered() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final issue = await checkAlarmPermission();
    if (issue != AlarmPermissionIssue.none) {
      await prefs.setBool(_alarmBlockedKey, true);
      return;
    }
    if (prefs.getBool(_alarmBlockedKey) != true) return;
    await prefs.remove(_alarmBlockedKey);
    await rescheduleNextMorningCall();
    await syncCoreReminders();
  }

  Future<void> rescheduleNextMorningCall() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('nyang_morning_call_enabled') ?? false;
    if (!enabled) return;

    final timeStr = prefs.getString('nyang_morning_call_time');
    final coachId = prefs.getString('nyang_morning_call_coach') ?? 'cat';
    if (timeStr == null || timeStr.isEmpty) return;

    final parts = timeStr.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = (parts.length > 1 ? int.tryParse(parts[1]) : 0) ?? 0;
    if (hour != null) {
      await scheduleDailyMorningCall(
        hour: hour,
        minute: minute,
        coachId: coachId,
      );
    }
  }

  Future<void> syncDailyMorningCall() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('nyang_morning_call_enabled') ?? false;
    if (!enabled) {
      await cancelAllMorningCalls();
      await prefs.remove('nyang_morning_call_resolved_coach');
      return;
    }

    final timeStr = prefs.getString('nyang_morning_call_time');
    if (timeStr == null || timeStr.isEmpty) {
      await cancelAllMorningCalls();
      await prefs.remove('nyang_morning_call_resolved_coach');
      return;
    }

    final parts = timeStr.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = (parts.length > 1 ? int.tryParse(parts[1]) : 0) ?? 0;
    if (hour == null) {
      await cancelAllMorningCalls();
      await prefs.remove('nyang_morning_call_resolved_coach');
      return;
    }

    await scheduleDailyMorningCall(
      hour: hour,
      minute: minute,
      coachId: prefs.getString('nyang_morning_call_coach') ?? 'cat',
    );
  }

  Future<void> cancelAllMorningCalls() async {
    if (kIsWeb) return;
    for (int i = 0; i < _morningCallRepeatCount; i++) {
      await _plugin.cancel(id: i);
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      await _androidAlarmChannel.invokeMethod('cancelMorningAlarm');
    }
  }

  Future<void> cancelCoreReminders() async {
    if (kIsWeb) return;
    for (int id = 1000; id <= 1100; id++) {
      await _plugin.cancel(id: id);
    }
  }

  Future<void> disableNightCallReminders() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nyang_night_call_enabled', false);
    await prefs.setBool('nyang_night_call_daily_enabled', false);
    await _plugin.cancel(id: 999);
    await _plugin.cancel(id: 998);
  }

  Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _androidPushChannelId,
          '기본 푸시 알람',
          importance: Importance.max,
          priority: Priority.high,
        );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails();
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _plugin.show(
      id: DateTime.now().millisecond,
      title: title,
      body: body,
      notificationDetails: details,
    );
  }

  Future<void> scheduleFocusTimerNotification({
    required int seconds,
    required String coachId,
  }) async {
    if (kIsWeb) return;

    String bodyMsg = '수고하셨습니다. 집중 시간이 완료되었습니다.';
    switch (coachId) {
      case 'nyang_halbae':
        bodyMsg = '끝까지 왔구나. 오늘은 여기까지 충분하다냥.';
        break;
      case 'sec_female':
        bodyMsg = '정말 수고하셨어요. 오늘 집중 시간이 참 뿌듯하네요. 🌸';
        break;
      case 'halmae':
        bodyMsg = '아이고 고생 많았재! 우리 똥강아지 이제 좀 쉬어라잉~';
        break;
      case 'bro':
        bodyMsg = '오케이! 수고했어. 역시 넌 한다면 하는구나!';
        break;
    }
    bodyMsg = await UserTitleService.applyForCoach(bodyMsg, coachId);

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _androidFocusTimerChannelId,
          '집중 타이머 알람',
          channelDescription: '집중 타이머 완료 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          audioAttributesUsage: AudioAttributesUsage.notification,
        );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final scheduledDate = tz.TZDateTime.now(
      tz.local,
    ).add(Duration(seconds: seconds));

    await _plugin.zonedSchedule(
      id: 888,
      title: '⏱ FOCUS TIMER 완료',
      body: bodyMsg,
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'focus_timer_done',
    );
  }

  Future<void> cancelFocusTimerNotification() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: 888);
  }

  Future<void> syncCoreReminders() async {
    if (kIsWeb) return;

    await cancelCoreReminders();

    final prefs = await SharedPreferences.getInstance();
    final userData = await UserDataService.load();
    if (!userData.isPlanActive) {
      await prefs.setBool('nyang_core_reminder_enabled', false);
      await prefs.remove('nyang_core_reminder_resolved_coach');
      await _clearStoredCoreReminderFlags(prefs);
      await NyangBannerNudge.sync();
      return;
    }
    final isEnabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;
    if (!isEnabled) {
      await NyangBannerNudge.sync();
      return;
    }

    String targetCoachId =
        prefs.getString('nyang_core_reminder_coach') ?? 'push';
    final advanceMinutes = prefs.getInt('nyang_core_reminder_advance') ?? 10;

    if (targetCoachId == 'random') {
      targetCoachId = 'push';
      await prefs.setString('nyang_core_reminder_coach', targetCoachId);
    } else if (targetCoachId != 'push' &&
        !CoachConfigs.all.containsKey(targetCoachId)) {
      targetCoachId = 'push';
      await prefs.setString('nyang_core_reminder_coach', targetCoachId);
    }
    // Save the resolved core reminder coach ID to SharedPreferences
    await prefs.setString('nyang_core_reminder_resolved_coach', targetCoachId);

    // 출시 버전에서는 일정 알람을 캐릭터 음성 알람으로 울리지 않는다.
    // 기존 coach/sound payload 구조는 남겨두되, 실제 예약은 일반 푸시 알림으로 고정한다.
    final soundName = _releaseCoreReminderVoiceAlarmEnabled
        ? _coreReminderSoundName(targetCoachId, advanceMinutes)
        : null;

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _coreReminderChannelId(soundName),
          '일정 알람',
          channelDescription: '지정된 일정 시작 전 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          sound: soundName != null
              ? RawResourceAndroidNotificationSound(soundName)
              : null,
          playSound: true,
          fullScreenIntent: false,
          audioAttributesUsage: AudioAttributesUsage.notification,
        );
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      sound: soundName != null ? '$soundName.caf' : null,
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // Compute today base date and todayStr matching TasksScreen logic
    const resetHour = 0.0;
    final now = DateTime.now();
    var baseToday = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      baseToday = baseToday.subtract(const Duration(days: 1));
    }
    final todayStr =
        '${baseToday.year}-${baseToday.month.toString().padLeft(2, '0')}-${baseToday.day.toString().padLeft(2, '0')}';

    // Helper list for alarms to schedule
    final List<Map<String, dynamic>> alarms = [];

    // 1. Collect from today's tasks ('nyang_tasks')
    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks != null && rawTasks.isNotEmpty) {
      try {
        final taskList = jsonDecode(rawTasks) as List;
        for (var item in taskList) {
          if (item is! Map) continue;
          if (item['category'] == 'schedule') continue;
          if (item['isReminderEnabled'] == false) continue;
          final tTimeStart = item['timeStart'];
          if (tTimeStart != null && tTimeStart is String) {
            final parts = tTimeStart.split(':');
            if (parts.length == 2) {
              final tHour = int.tryParse(parts[0]) ?? 0;
              final tMin = int.tryParse(parts[1]) ?? 0;
              final scheduledDate = DateTime(
                baseToday.year,
                baseToday.month,
                baseToday.day,
                tHour,
                tMin,
              );
              final targetDate = scheduledDate.subtract(
                Duration(minutes: advanceMinutes),
              );
              if (targetDate.isAfter(now)) {
                alarms.add({
                  'time': targetDate,
                  'text': item['text'] ?? '일정',
                  'id': item['id'],
                  'dateKey': todayStr,
                });
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Collect from schedules ('nyang_schedules') for future dates
    final rawSchedules = prefs.getString('nyang_schedules');
    if (rawSchedules != null && rawSchedules.isNotEmpty) {
      try {
        final Map<String, dynamic> schedulesMap = jsonDecode(rawSchedules);
        schedulesMap.forEach((dateKey, list) {
          if (dateKey.compareTo(todayStr) < 0) return; // skip past dates only
          if (list is! List) return;

          final dateParts = dateKey.split('-');
          if (dateParts.length != 3) return;
          final sYear = int.tryParse(dateParts[0]) ?? 0;
          final sMonth = int.tryParse(dateParts[1]) ?? 0;
          final sDay = int.tryParse(dateParts[2]) ?? 0;
          if (sYear == 0 || sMonth == 0 || sDay == 0) return;

          for (var item in list) {
            if (item is! Map) continue;
            if (item['isReminderEnabled'] != true) continue;
            final tTimeStart = item['timeStart'];
            if (tTimeStart != null && tTimeStart is String) {
              final parts = tTimeStart.split(':');
              if (parts.length == 2) {
                final tHour = int.tryParse(parts[0]) ?? 0;
                final tMin = int.tryParse(parts[1]) ?? 0;
                final scheduledDate = DateTime(
                  sYear,
                  sMonth,
                  sDay,
                  tHour,
                  tMin,
                );
                final targetDate = scheduledDate.subtract(
                  Duration(minutes: advanceMinutes),
                );
                if (targetDate.isAfter(now)) {
                  alarms.add({
                    'time': targetDate,
                    'text': item['text'] ?? '일정',
                    'id': item['id'],
                    'dateKey': dateKey,
                  });
                }
              }
            }
          }
        });
      } catch (_) {}
    }

    // Sort alarms chronologically (ascending)
    alarms.sort(
      (a, b) => (a['time'] as DateTime).compareTo(b['time'] as DateTime),
    );

    // iOS keeps a limited number of pending local notifications per app.
    // Leave room for recurring morning/night calls and other timers.
    int notificationId = 1000;
    for (var alarm in alarms.take(_maxScheduledCoreReminders)) {
      final targetDate = alarm['time'] as DateTime;
      final taskText = alarm['text'] as String;
      final alarmId = alarm['id'];
      final dateKey = alarm['dateKey'] as String;
      final tzScheduled = tz.TZDateTime.from(targetDate, tz.local);

      final fireKey = coreReminderFireKey(
        alarmId: alarmId,
        targetDate: targetDate,
        dateKey: dateKey,
      );

      await _plugin.zonedSchedule(
        id: notificationId,
        title: '🔔 [$taskText] 일정이 곧 시작돼요!',
        body: '$advanceMinutes분 뒤 시작해요. 앱 밖에서도 잊지 않게 알려드려요!',
        scheduledDate: tzScheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'core:$targetCoachId:${soundName ?? ''}:$fireKey:$taskText',
      );
      notificationId++;
    }
    await NyangBannerNudge.sync();
  }

  Future<void> _clearStoredCoreReminderFlags(SharedPreferences prefs) async {
    var changed = false;

    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks != null && rawTasks.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTasks);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map && item['isReminderEnabled'] == true) {
              item['isReminderEnabled'] = false;
              changed = true;
            }
          }
          if (changed) {
            await prefs.setString('nyang_tasks', jsonEncode(decoded));
          }
        }
      } catch (_) {}
    }

    final rawSchedules = prefs.getString('nyang_schedules');
    if (rawSchedules != null && rawSchedules.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSchedules);
        var scheduleChanged = false;
        if (decoded is Map) {
          for (final list in decoded.values) {
            if (list is! List) continue;
            for (final item in list) {
              if (item is Map && item['isReminderEnabled'] == true) {
                item['isReminderEnabled'] = false;
                scheduleChanged = true;
              }
            }
          }
          if (scheduleChanged) {
            await prefs.setString('nyang_schedules', jsonEncode(decoded));
            changed = true;
          }
        }
      } catch (_) {}
    }

    if (changed) {
      TasksSyncService.scheduleSyncToCloud();
    }
  }
}
