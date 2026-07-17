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
import '../screens/night_call_screen.dart';
import '../screens/core_reminder_screen.dart';
import '../screens/coach_config.dart';
import '../screens/main_tab_screen.dart';
import 'analytics_service.dart';
import 'morning_call_alarm_session.dart';
import 'tasks_sync_service.dart';
import 'user_title_service.dart';
import '../models/user_data.dart';

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
  static const int _inactiveReturnNotificationId = 889;
  static const Duration _inactiveReturnDelay = Duration(days: 3);
  static const Duration _inactiveReturnCooldown = Duration(days: 5);
  static const List<String> _inactiveReturnMessages = [
    '집사야, 요즘 뭐해? 보고 싶다냥.',
    '집사야, 냥냥코치가 기다리고 있다냥.',
    '요즘 조용하다냥. 잠깐 얼굴 보여줄래?',
    '집사야, 오늘은 어떻게 지내고 있냥?',
    '냥냥코치가 슬쩍 안부 물으러 왔다냥.',
  ];
  String? _lastMorningPayload;
  DateTime? _lastMorningOpenedAt;

  String _morningCallChannelId(String? soundName) {
    return 'nyang_morning_call_${soundName ?? 'default'}_v6';
  }

  String _coreReminderChannelId(String? soundName) {
    return 'nyang_core_reminder_${soundName ?? 'push'}_v2';
  }

  String _nightCallChannelId(String? soundName) {
    return 'nyang_night_call_${soundName ?? 'default'}_v3';
  }

  bool _isInvalidSoundError(Object error) {
    return error is PlatformException && error.code == 'invalid_sound';
  }

  NotificationDetails _nightCallFallbackDetails() {
    const androidDetails = AndroidNotificationDetails(
      'nyang_night_call_default_v3',
      '냥냥코치 나이트콜',
      channelDescription: '비서의 하루 마무리 알람입니다.',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      fullScreenIntent: true,
      audioAttributesUsage: AudioAttributesUsage.alarm,
    );
    const iosDetails = DarwinNotificationDetails(
      presentSound: true,
      presentAlert: true,
      presentBadge: true,
      presentBanner: true,
      presentList: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  String? _coreReminderSoundName(String coachId, int advanceMinutes) {
    if (coachId == 'push') return null;
    if (!_coreReminderSoundMinutes.contains(advanceMinutes)) return null;
    return '${coachId}_reminder_$advanceMinutes';
  }

  ({String coachId, String? soundName}) _parseMorningPayload(String payload) {
    if (!payload.startsWith('morning:')) {
      return (coachId: payload, soundName: null);
    }
    final parts = payload.split(':');
    return (
      coachId: parts.length > 1 ? parts[1] : 'cat',
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

  ({String coachId, String? soundName}) _parseNightPayload(String payload) {
    if (!payload.startsWith('night:')) {
      return (coachId: payload, soundName: null);
    }
    final parts = payload.split(':');
    return (
      coachId: parts.length > 1 ? parts[1] : 'sec_male',
      soundName: parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null,
    );
  }

  void _openNightCall(String payload) {
    final parsed = _parseNightPayload(payload);
    AnalyticsService.logFeatureUsage('night_call');
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NightCallScreen(
          coachId: parsed.coachId,
          soundName: parsed.soundName,
        ),
      ),
    );
  }

  Future<void> _openCoreReminder(String payload) async {
    // payload format: core:coachId:soundName:fireKey:taskText (or old format: core:coachId:soundName:taskText)
    final parts = payload.split(':');
    if (parts.length >= 4) {
      final coachId = parts[1];
      final soundName = parts[2].isEmpty ? null : parts[2];

      String fireKey = '';
      String taskText = '';
      if (parts.length >= 5 && parts[3].startsWith('reminder_')) {
        fireKey = parts[3];
        taskText = parts.sublist(4).join(':');
      } else {
        taskText = parts.sublist(3).join(':');
      }

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

  Future<void> _openInactiveReturn(String payload) async {
    final parts = payload.split(':');
    final coachId = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : 'cat';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_inactive_return_last_opened_at',
      DateTime.now().toIso8601String(),
    );
    await prefs.setString(
      'nyang_last_app_active_at',
      DateTime.now().toIso8601String(),
    );
    await UserDataService.setSelectedCoach(coachId);
    AnalyticsService.logFeatureUsage('inactive_return_push');

    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => MainTabScreen(coachId: coachId)),
      (route) => false,
    );
  }

  Future<void> init() async {
    if (kIsWeb) return;
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
          defaultPresentBanner: true,
          defaultPresentList: true,
          defaultPresentSound: true,
        );
    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        final payload = response.payload;
        if (payload == null) return;
        if (payload.startsWith('night:')) {
          _openNightCall(payload);
          return;
        }
        if (payload.startsWith('core:')) {
          _openCoreReminder(payload);
          return;
        }
        if (payload.startsWith('morning:')) {
          await _openMorningCall(payload);
          return;
        }
        if (payload.startsWith('inactive_return:')) {
          await _openInactiveReturn(payload);
        }
      },
    );

    // 안드로이드 13 이상을 위한 권한 요청 팝업 띄우기
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> handleLaunchNotification() async {
    if (kIsWeb) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;
    if (payload == null || details?.didNotificationLaunchApp != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (payload.startsWith('night:')) {
        _openNightCall(payload);
      } else if (payload.startsWith('core:')) {
        _openCoreReminder(payload);
      } else if (payload.startsWith('morning:')) {
        _openMorningCall(payload);
      } else if (payload.startsWith('inactive_return:')) {
        _openInactiveReturn(payload);
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
    await _plugin.cancel(id: _inactiveReturnNotificationId);
  }

  Future<void> scheduleInactiveReturnReminder() async {
    if (kIsWeb) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_last_app_active_at', now.toIso8601String());

    final lastOpenedRaw = prefs.getString(
      'nyang_inactive_return_last_opened_at',
    );
    if (lastOpenedRaw != null) {
      final lastOpened = DateTime.tryParse(lastOpenedRaw);
      if (lastOpened != null &&
          now.difference(lastOpened) < _inactiveReturnCooldown) {
        await _plugin.cancel(id: _inactiveReturnNotificationId);
        return;
      }
    }

    const androidDetails = AndroidNotificationDetails(
      'nyang_inactive_return_v1',
      '냥냥코치 재방문 알림',
      channelDescription: '며칠 동안 앱에 접속하지 않았을 때 냥냥코치가 안부를 전합니다.',
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

    final message =
        _inactiveReturnMessages[Random().nextInt(
          _inactiveReturnMessages.length,
        )];

    await _plugin.cancel(id: _inactiveReturnNotificationId);
    await _plugin.zonedSchedule(
      id: _inactiveReturnNotificationId,
      title: '냥냥코치',
      body: message,
      scheduledDate: tz.TZDateTime.from(
        now.add(_inactiveReturnDelay),
        tz.local,
      ),
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'inactive_return:cat',
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
    String targetCoachId = coachId;

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
    } else if ((CoachConfigs.all[targetCoachId]?.voiceCount ?? 0) <= 0) {
      targetCoachId = 'cat';
    }
    // Save the resolved coach ID to SharedPreferences so the in-app engine can align with it
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_morning_call_resolved_coach', targetCoachId);

    // CoachConfig에서 목소리 개수 읽기 → 나중에 목소리 추가 시 coach_config.dart만 수정하면 됨
    final count = CoachConfigs.all[targetCoachId]?.voiceCount ?? 0;
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

    if (defaultTargetPlatform == TargetPlatform.android) {
      await _androidAlarmChannel.invokeMethod('scheduleMorningAlarm', {
        'triggerMillis': scheduled.millisecondsSinceEpoch,
        'payload': 'morning:$targetCoachId:${soundName ?? ''}',
      });
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

  Future<void> scheduleNightCall({
    required int hour,
    required int minute,
    required String coachId,
  }) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: 999);
    final targetCoachId = coachId == 'sec_female' || coachId == 'sec_male'
        ? coachId
        : 'sec_male';
    final soundName = '${targetCoachId}_night_${Random().nextInt(6) + 1}';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _nightCallChannelId(soundName),
          '냥냥코치 나이트콜',
          channelDescription: '비서의 하루 마무리 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound(soundName),
          playSound: true,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      sound: '$soundName.caf',
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

    try {
      await _plugin.zonedSchedule(
        id: 999,
        title: '🌙 나이트콜 시간입니다!',
        body: '정리하고 취침 준비 하실 시간입니다.',
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'night:$targetCoachId:$soundName',
      );
    } catch (e) {
      if (!_isInvalidSoundError(e)) rethrow;
      debugPrint('Night call custom sound unavailable, using default: $e');
      await _plugin.zonedSchedule(
        id: 999,
        title: '🌙 나이트콜 시간입니다!',
        body: '정리하고 취침 준비 하실 시간입니다.',
        scheduledDate: scheduled,
        notificationDetails: _nightCallFallbackDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'night:$targetCoachId:$soundName',
      );
    }
  }

  Future<void> scheduleDailyNightCall({
    required int hour,
    required int minute,
    required String coachId,
  }) async {
    if (kIsWeb) return;
    await cancelDailyNightCall();
    final targetCoachId = coachId == 'sec_female' || coachId == 'sec_male'
        ? coachId
        : 'sec_male';
    final soundName = '${targetCoachId}_night_${Random().nextInt(6) + 1}';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _nightCallChannelId(soundName),
          '냥냥코치 나이트콜',
          channelDescription: '비서의 하루 마무리 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          sound: RawResourceAndroidNotificationSound(soundName),
          playSound: true,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      sound: '$soundName.caf',
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

    try {
      await _plugin.zonedSchedule(
        id: 998,
        title: '🌙 나이트콜 시간입니다!',
        body: '정리하고 취침 준비 하실 시간입니다.',
        scheduledDate: scheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'night:$targetCoachId:$soundName',
      );
    } catch (e) {
      if (!_isInvalidSoundError(e)) rethrow;
      debugPrint(
        'Daily night call custom sound unavailable, using default: $e',
      );
      await _plugin.zonedSchedule(
        id: 998,
        title: '🌙 나이트콜 시간입니다!',
        body: '정리하고 취침 준비 하실 시간입니다.',
        scheduledDate: scheduled,
        notificationDetails: _nightCallFallbackDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'night:$targetCoachId:$soundName',
      );
    }
  }

  Future<void> cancelDailyNightCall() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: 998);
  }

  Future<void> syncDailyNightCall() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('nyang_night_call_daily_enabled') ?? false;
    if (!isEnabled) {
      await cancelDailyNightCall();
      return;
    }

    final minSleepTime = prefs.getString('nyang_premium_min_sleep_time');
    if (minSleepTime == null) {
      await cancelDailyNightCall();
      return;
    }

    final parts = minSleepTime.split(':');
    final bedHour = int.tryParse(parts[0]);
    final bedMinute = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    if (bedHour == null) {
      await cancelDailyNightCall();
      return;
    }

    var nightCallHour = bedHour - 2;
    if (nightCallHour < 0) nightCallHour += 24;
    await scheduleDailyNightCall(
      hour: nightCallHour,
      minute: bedMinute,
      coachId: prefs.getString('nyang_night_call_coach') ?? 'sec_male',
    );
  }

  Future<void> showImmediateNotification({
    required String title,
    required String body,
  }) async {
    if (kIsWeb) return;
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'nyang_push_channel',
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
      case 'sec_male':
        bodyMsg = '정말 고생하셨습니다! 끝까지 해내신 대표님이 자랑스럽습니다. 최고예요! 🎉';
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
          'nyang_focus_timer_channel_v3',
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
      return;
    }
    final isEnabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;
    if (!isEnabled) return;

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

    final soundName = _coreReminderSoundName(targetCoachId, advanceMinutes);

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
          fullScreenIntent: true,
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

    // Compute today base date and todayStr matching TasksScreen logic
    final resetHour = 3.0;
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

      final fireKey =
          'reminder_${alarmId}_${targetDate.toIso8601String()}_$dateKey';

      await _plugin.zonedSchedule(
        id: notificationId,
        title: '🔔 [$taskText] 일정을 시작할 시간이에요!',
        body: '앱 밖에서도 잊지 않게 알려드려요!',
        scheduledDate: tzScheduled,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: 'core:$targetCoachId:${soundName ?? ''}:$fireKey:$taskText',
      );
      notificationId++;
    }
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
