import 'dart:convert';
import 'dart:io';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetSyncService {
  static const String androidWidgetNyang = 'NyangWidgetProvider';
  static const String androidWidgetCatCharacter = 'CatCharacterWidgetProvider';

  static const String iOSAppGroupId = 'group.com.nyang.nyangCoach';
  static const String iOSWidgetCharacter = 'NyangWidget';
  static const String iOSWidgetNyang = 'NyangCompactWidget';

  /// 마스터 플랜이 아니면 저장된 비서 위젯 선택을 해제하고
  /// 냥냥코치 위젯으로 설정을 전환합니다.
  static Future<bool> enforcePlanAccess({required bool hasMasterPlan}) async {
    final prefs = await SharedPreferences.getInstance();
    final previousAccess = prefs.getBool('widget_master_access_granted');
    await prefs.setBool('widget_master_access_granted', hasMasterPlan);
    await HomeWidget.saveWidgetData<bool>(
      'master_widget_access',
      hasMasterPlan,
    );
    if (hasMasterPlan) {
      if (previousAccess != true) {
        await syncFromStoredTasks();
        return true;
      }
      return false;
    }

    final hadMasterWidget =
        (prefs.getBool('widget_sec_male_enabled') ?? false) ||
        (prefs.getBool('widget_sec_female_enabled') ?? false);
    if (!hadMasterWidget && previousAccess == false) return false;

    if (hadMasterWidget) {
      await prefs.setBool('widget_sec_male_enabled', false);
      await prefs.setBool('widget_sec_female_enabled', false);
      await prefs.setBool('widget_nyang_enabled', true);
      await prefs.setBool('nyang_home_widget_enabled', true);
    }
    await syncFromStoredTasks();
    return true;
  }

  static Future<void> syncFromStoredTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getString('nyang_tasks');
    final tasks = rawTasks == null
        ? <Map<String, dynamic>>[]
        : _decodeTasks(rawTasks);
    final timedSchedule = _todayWidgetSchedule(prefs, tasks);

    final allItems = [...tasks, ..._todayMilestoneTasks(prefs)];
    final doneTasks = allItems.where((task) => task['done'] == true).toList();
    final remainingTasks = allItems
        .where((task) => task['done'] != true)
        .toList();
    final doneCount = doneTasks.length;
    final remainingCount = remainingTasks.length;
    final totalCount = doneCount + remainingCount;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;

    await syncData(
      progressPercentage: progress,
      isMasterCoach: false,
      doneCount: doneCount,
      remainingCount: remainingCount,
      doneTasksText: _buildTaskPreview(doneTasks),
      remainingTasksText: _buildTaskPreview(remainingTasks),
      widgetScheduleTime: timedSchedule?.time,
      widgetScheduleTitle: timedSchedule?.title,
    );
  }

  /// 오늘 날짜에 걸린 마일스톤을 tasks_screen.dart의
  /// _todayMilestoneItems 계산과 동일한 기준으로 뽑아 위젯 집계에 합산한다.
  static List<Map<String, dynamic>> _todayMilestoneTasks(
    SharedPreferences prefs,
  ) {
    final rawVisions = prefs.getString('nyang_visions');
    if (rawVisions == null) return <Map<String, dynamic>>[];

    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final todayStr =
        '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';

    try {
      final decoded = jsonDecode(rawVisions);
      if (decoded is! List) return <Map<String, dynamic>>[];
      final result = <Map<String, dynamic>>[];
      for (final vision in decoded) {
        if (vision is! Map) continue;
        final milestones = vision['milestones'];
        if (milestones is! List) continue;
        for (final m in milestones) {
          if (m is! Map) continue;
          if (m['date'] == todayStr) {
            result.add({'text': m['text'], 'done': m['done'] == true});
          }
        }
      }
      return result;
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static Future<void> syncData({
    required double progressPercentage,
    required bool isMasterCoach, // For legacy/general purposes if needed
    required int doneCount,
    required int remainingCount,
    required String doneTasksText,
    required String remainingTasksText,
    String? widgetScheduleTime,
    String? widgetScheduleTitle,
  }) async {
    await _configureIOSAppGroup();
    print(
      "WidgetSyncService.syncData called: pct=$progressPercentage, done=$doneCount, remaining=$remainingCount",
    );
    // Generate messages for all 3 supported widgets
    String messageCat = _getCoachMessage(progressPercentage, 'cat');
    String messageSecMale = _getCoachMessage(progressPercentage, 'sec_male');
    String messageSecFemale = _getCoachMessage(
      progressPercentage,
      'sec_female',
    );

    // Convert to 0~100 integer for display
    int progressInt = (progressPercentage * 100).round();

    // 휴식 모드 여부와 마지막 앱 접속 시각(밀리초)을 위젯에 전달한다.
    // syncData는 앱이 실행 중일 때만 호출되므로 호출 시각을 접속 시각으로 쓴다.
    final prefs = await SharedPreferences.getInstance();
    await HomeWidget.saveWidgetData<bool>(
      'vacation_mode',
      prefs.getString('nyang_vacation') != null,
    );
    await HomeWidget.saveWidgetData<int>(
      'last_opened_at',
      DateTime.now().millisecondsSinceEpoch,
    );

    // Save generic task data
    await HomeWidget.saveWidgetData<int>('progress', progressInt);
    await HomeWidget.saveWidgetData<int>('done_count', doneCount);
    await HomeWidget.saveWidgetData<int>('remaining_count', remainingCount);
    await HomeWidget.saveWidgetData<String>('done_tasks_text', doneTasksText);
    await HomeWidget.saveWidgetData<String>(
      'remaining_tasks_text',
      remainingTasksText,
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_schedule_time',
      widgetScheduleTime ?? '',
    );
    await HomeWidget.saveWidgetData<String>(
      'widget_schedule_title',
      widgetScheduleTitle ?? '',
    );

    // Save coach-specific messages
    await HomeWidget.saveWidgetData<String>('coach_message_cat', messageCat);
    await HomeWidget.saveWidgetData<String>(
      'coach_message_sec_male',
      messageSecMale,
    );
    await HomeWidget.saveWidgetData<String>(
      'coach_message_sec_female',
      messageSecFemale,
    );

    // Update the two public widgets: the 2x2 mini widget and the horizontal
    // character widget. Coach-specific Android widgets are no longer exposed.
    await HomeWidget.updateWidget(
      name: androidWidgetNyang,
      androidName: androidWidgetNyang,
      iOSName: iOSWidgetNyang,
    );
    await HomeWidget.updateWidget(
      name: androidWidgetCatCharacter,
      androidName: androidWidgetCatCharacter,
      iOSName: iOSWidgetCharacter,
    );
  }

  static Future<bool> requestPinWidget(String widgetId) async {
    await _configureIOSAppGroup();
    await syncFromStoredTasks();

    bool? isSupported = await HomeWidget.isRequestPinWidgetSupported();
    if (isSupported == true) {
      String providerName = androidWidgetNyang;
      if (widgetId == 'cat_character') providerName = androidWidgetCatCharacter;

      await HomeWidget.requestPinWidget(
        name: providerName,
        androidName: providerName,
      );
      return true;
    }
    return false;
  }

  static Future<void> _configureIOSAppGroup() async {
    if (Platform.isIOS) {
      await HomeWidget.setAppGroupId(iOSAppGroupId);
    }
  }

  static List<Map<String, dynamic>> _decodeTasks(String rawTasks) {
    try {
      final decoded = jsonDecode(rawTasks);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((task) => Map<String, dynamic>.from(task))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static _WidgetScheduleItem? _todayWidgetSchedule(
    SharedPreferences prefs,
    List<Map<String, dynamic>> tasks,
  ) {
    final todayStr = _effectiveTodayKey(prefs);
    final candidates = <_WidgetScheduleItem>[];

    final rawSchedules = prefs.getString('nyang_schedules');
    if (rawSchedules != null) {
      try {
        final decoded = jsonDecode(rawSchedules);
        final todayItems = decoded is Map ? decoded[todayStr] : null;
        if (todayItems is List) {
          for (final item in todayItems) {
            if (item is Map) {
              final candidate = _scheduleCandidateFromMap(item);
              if (candidate != null) candidates.add(candidate);
            }
          }
        }
      } catch (_) {
        // Widget data should never block the main planner flow.
      }
    }

    for (final task in tasks) {
      if (task['category'] != 'schedule') continue;
      final candidate = _scheduleCandidateFromMap(task);
      if (candidate != null &&
          !candidates.any(
            (existing) =>
                existing.timeMinutes == candidate.timeMinutes &&
                existing.title == candidate.title,
          )) {
        candidates.add(candidate);
      }
    }

    candidates.sort((a, b) => a.timeMinutes.compareTo(b.timeMinutes));
    return candidates.isEmpty ? null : candidates.first;
  }

  static _WidgetScheduleItem? _scheduleCandidateFromMap(Map item) {
    if (item['done'] == true) return null;

    final title = item['text']?.toString().trim();
    if (title == null || title.isEmpty) return null;

    final parsedTime = _parseStoredTime(item['timeStart']?.toString());
    if (parsedTime == null) return null;

    return _WidgetScheduleItem(
      time: parsedTime.label,
      title: title,
      timeMinutes: parsedTime.minutes,
    );
  }

  static _ParsedWidgetTime? _parseStoredTime(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(raw.trim());
    if (match == null) return null;

    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return _ParsedWidgetTime(
      label:
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      minutes: hour * 60 + minute,
    );
  }

  static String _localDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String _effectiveTodayKey(SharedPreferences _) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    return _localDateKey(base);
  }

  static String _buildTaskPreview(List<Map<String, dynamic>> tasks) {
    final preview = tasks
        .take(5)
        .map((task) => task['text']?.toString().trim() ?? '')
        .where((text) => text.isNotEmpty)
        .map((text) => "• $text")
        .join("\n");
    if (tasks.length > 5) return "$preview\n...";
    return preview;
  }

  static String _getCoachMessage(double progress, String coachId) {
    if (coachId == 'cat') {
      if (progress >= 1.0) return "최고다냥! 다 했다냥!";
      if (progress >= 0.80) return "거의 다 왔다냥!";
      if (progress >= 0.51) return "아주 잘하고 있다냥!";
      if (progress >= 0.21) return "차근차근 간다냥!";
      return "오늘도 시작해보자냥!";
    } else if (coachId == 'sec_female') {
      // 여비서 코치
      if (progress >= 1.0) return "오늘도 멋지게 해냈어요.";
      if (progress >= 0.80) return "끝까지 응원할게요.";
      if (progress >= 0.51) return "오늘 흐름도 좋은데요?";
      if (progress >= 0.21) return "충분히 해낼 수 있어요.";
      return "오늘도 응원할게요.";
    } else {
      // 남비서 코치 (sec_male)
      if (progress >= 1.0) return "오늘도 수고 많으셨습니다.";
      if (progress >= 0.80) return "마지막까지 함께합니다.";
      if (progress >= 0.51) return "흐름이 아주 좋습니다.";
      if (progress >= 0.21) return "차근차근 좋습니다.";
      return "오늘도 함께 해보시죠.";
    }
  }
}

class _WidgetScheduleItem {
  final String time;
  final String title;
  final int timeMinutes;

  const _WidgetScheduleItem({
    required this.time,
    required this.title,
    required this.timeMinutes,
  });
}

class _ParsedWidgetTime {
  final String label;
  final int minutes;

  const _ParsedWidgetTime({required this.label, required this.minutes});
}
