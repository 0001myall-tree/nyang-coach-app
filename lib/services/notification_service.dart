import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../main.dart';
import '../screens/morning_call_screen.dart';
import '../screens/night_call_screen.dart';
import '../screens/core_reminder_screen.dart';
import '../screens/coach_config.dart';
import '../models/user_data.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  String? _lastMorningPayload;
  DateTime? _lastMorningOpenedAt;

  String _morningCallChannelId(String? soundName) {
    return 'nyang_morning_call_screen_${soundName ?? 'default'}_v3';
  }

  String _coreReminderChannelId(String? soundName) {
    return 'nyang_core_reminder_${soundName ?? 'push'}_v2';
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

    final parsed = _parseMorningPayload(payload);
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => MorningCallScreen(
          coachId: parsed.coachId,
          soundName: parsed.soundName,
        ),
      ),
    );
  }

  void _openNightCall(String coachId) {
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => NightCallScreen(coachId: coachId),
      ),
    );
  }

  void _openCoreReminder(String payload) {
    // payload format: core:coachId:soundName:taskText
    final parts = payload.split(':');
    if (parts.length >= 4) {
      final coachId = parts[1];
      final soundName = parts[2].isEmpty ? null : parts[2];
      final taskText = parts.sublist(3).join(':');
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
          final coachId = payload.substring('night:'.length);
          _openNightCall(coachId);
          return;
        }
        if (payload.startsWith('core:')) {
          _openCoreReminder(payload);
          return;
        }
        await _openMorningCall(payload);
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
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> handleLaunchNotification() async {
    if (kIsWeb) return;
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    final payload = response?.payload;
    if (payload == null || details?.didNotificationLaunchApp != true) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (payload.startsWith('night:')) {
        _openNightCall(payload.substring('night:'.length));
      } else if (payload.startsWith('core:')) {
        _openCoreReminder(payload);
      } else {
        _openMorningCall(payload);
      }
    });
  }

  Future<void> scheduleDailyMorningCall({
    required int hour,
    required int minute,
    required String coachId,
  }) async {
    if (kIsWeb) return;
    await _plugin.cancel(id: 0);
    String targetCoachId = coachId;

    // UserDataService 로드하여 보유 코치 체크
    final userData = await UserDataService.load();

    if (targetCoachId == 'random') {
      final availableCoaches = CoachConfigs.all.values
          .where((coach) => userData.canAccessCoach(coach.id))
          .map((coach) => coach.id)
          .toList();
      if (availableCoaches.isNotEmpty) {
        targetCoachId =
            availableCoaches[Random().nextInt(availableCoaches.length)];
      } else {
        targetCoachId = 'cat';
      }
    }
    // CoachConfig에서 목소리 개수 읽기 → 나중에 목소리 추가 시 coach_config.dart만 수정하면 됨
    final count = CoachConfigs.all[targetCoachId]?.voiceCount ?? 0;
    String? soundName;
    if (count > 0) {
      final randNum = Random().nextInt(count) + 1;
      soundName = '${targetCoachId}_${randNum}';
    }
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _morningCallChannelId(soundName),
          '냥냥코치 모닝콜',
          channelDescription: '냥냥코치 모닝콜 알림입니다.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: false,
      presentAlert: true,
      presentBadge: true,
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
    await _plugin.zonedSchedule(
      id: 0,
      title: '⏰ 모닝콜 시간입니다!',
      body: '코치가 깨우러 왔어요. 얼른 일어나세요!',
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'morning:$targetCoachId:${soundName ?? ''}',
    );
  }

  Future<void> cancelAllMorningCalls() async {
    if (kIsWeb) return;
    await _plugin.cancel(id: 0);
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
    final targetCoachId = coachId == 'sec_female' || coachId == 'sec_male'
        ? coachId
        : 'sec_male';

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'nyang_night_call_channel',
          '냥냥코치 나이트콜',
          channelDescription: '비서의 하루 마무리 알람입니다.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: false,
      presentAlert: true,
      presentBadge: true,
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

    await _plugin.zonedSchedule(
      id: 999,
      title: '🌙 나이트콜 시간입니다!',
      body: '정리하고 취침 준비 하실 시간입니다.',
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'night:$targetCoachId',
    );
  }

  Future<void> scheduleDailyNightCall({
    required int hour,
    required int minute,
    required String coachId,
  }) async {
    if (kIsWeb) return;
    final targetCoachId = coachId == 'sec_female' || coachId == 'sec_male'
        ? coachId
        : 'sec_male';

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'nyang_night_call_channel',
          '냥냥코치 나이트콜',
          channelDescription: '비서의 하루 마무리 알림입니다.',
          importance: Importance.max,
          priority: Priority.high,
          playSound: false,
          fullScreenIntent: true,
          audioAttributesUsage: AudioAttributesUsage.alarm,
        );

    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentSound: false,
      presentAlert: true,
      presentBadge: true,
    );

    const NotificationDetails details = NotificationDetails(
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

    await _plugin.zonedSchedule(
      id: 998,
      title: '🌙 나이트콜 시간입니다!',
      body: '정리하고 취침 준비 하실 시간입니다.',
      scheduledDate: scheduled,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: 'night:$targetCoachId',
    );
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
          '기본 푸시 알림',
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

  Future<void> syncCoreReminders() async {
    if (kIsWeb) return;

    await cancelCoreReminders();

    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;
    if (!isEnabled) return;

    final rawCore = prefs.getString('nyang_core_tasks');
    if (rawCore == null || rawCore.isEmpty) return;

    String targetCoachId =
        prefs.getString('nyang_core_reminder_coach') ?? 'cat';
    final advanceMinutes = prefs.getInt('nyang_core_reminder_advance') ?? 10;

    if (targetCoachId == 'random') {
      final userData = await UserDataService.load();
      final availableCoaches = CoachConfigs.all.values
          .where((coach) => userData.canAccessCoach(coach.id))
          .map((coach) => coach.id)
          .toList();
      if (availableCoaches.isNotEmpty) {
        targetCoachId =
            availableCoaches[Random().nextInt(availableCoaches.length)];
      } else {
        targetCoachId = 'cat';
      }
    }

    String? soundName;
    if (targetCoachId != 'push') {
      soundName = '${targetCoachId}_reminder_$advanceMinutes';
    }

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          _coreReminderChannelId(soundName),
          '핵심 일정 리마인더',
          channelDescription: '지정된 핵심 일정 시작 전 알림입니다.',
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
    );
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final coreList = jsonDecode(rawCore) as List;
    final now = DateTime.now();
    int notificationId = 1000;

    for (var item in coreList) {
      if (item['isReminderEnabled'] == false) continue;
      final tTimeStart = item['timeStart'];
      if (tTimeStart != null && tTimeStart is String) {
        final parts = tTimeStart.split(':');
        if (parts.length == 2) {
          final tHour = int.tryParse(parts[0]) ?? 0;
          final tMin = int.tryParse(parts[1]) ?? 0;
          final scheduledDate = DateTime(
            now.year,
            now.month,
            now.day,
            tHour,
            tMin,
          );
          final targetDate = scheduledDate.subtract(
            Duration(minutes: advanceMinutes),
          );

          if (targetDate.isAfter(now)) {
            final tzScheduled = tz.TZDateTime.from(targetDate, tz.local);
            final taskText = item['text'] ?? '오늘의 핵심 일정';

            await _plugin.zonedSchedule(
              id: notificationId,
              title: '🔔 [$taskText] 일정을 시작할 시간이에요!',
              body: '앱 밖에서도 잊지 않게 알려드려요!',
              scheduledDate: tzScheduled,
              notificationDetails: details,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              payload: 'core:$targetCoachId:${soundName ?? ''}:$taskText',
            );
            notificationId++;
            if (notificationId > 1100) break; // Limit
          }
        }
      }
    }
  }
}
