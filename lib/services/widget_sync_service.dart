import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetSyncService {
  static const String androidWidgetNyang = 'NyangWidgetProvider';
  static const String androidWidgetSecMale = 'SecMaleWidgetProvider';
  static const String androidWidgetSecFemale = 'SecFemaleWidgetProvider';

  static const String iOSWidgetName = 'NyangWidget';

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
    );
  }

  /// 오늘 날짜(설정된 리셋 시각 반영)에 걸린 마일스톤을 tasks_screen.dart의
  /// _todayMilestoneItems 계산과 동일한 기준으로 뽑아 위젯 집계에 합산한다.
  static List<Map<String, dynamic>> _todayMilestoneTasks(
    SharedPreferences prefs,
  ) {
    final rawVisions = prefs.getString('nyang_visions');
    if (rawVisions == null) return <Map<String, dynamic>>[];

    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
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
  }) async {
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

    // Save generic task data
    await HomeWidget.saveWidgetData<int>('progress', progressInt);
    await HomeWidget.saveWidgetData<int>('done_count', doneCount);
    await HomeWidget.saveWidgetData<int>('remaining_count', remainingCount);
    await HomeWidget.saveWidgetData<String>('done_tasks_text', doneTasksText);
    await HomeWidget.saveWidgetData<String>(
      'remaining_tasks_text',
      remainingTasksText,
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

    // Update all 3 widgets always to ensure real-time synchronization
    await HomeWidget.updateWidget(
      name: androidWidgetNyang,
      androidName: androidWidgetNyang,
      iOSName: iOSWidgetName,
    );
    await HomeWidget.updateWidget(
      name: androidWidgetSecMale,
      androidName: androidWidgetSecMale,
      iOSName: iOSWidgetName,
    );
    await HomeWidget.updateWidget(
      name: androidWidgetSecFemale,
      androidName: androidWidgetSecFemale,
      iOSName: iOSWidgetName,
    );
  }

  static Future<bool> requestPinWidget(String widgetId) async {
    await syncFromStoredTasks();

    bool? isSupported = await HomeWidget.isRequestPinWidgetSupported();
    if (isSupported == true) {
      String providerName = androidWidgetNyang;
      if (widgetId == 'sec_male') providerName = androidWidgetSecMale;
      if (widgetId == 'sec_female') providerName = androidWidgetSecFemale;

      await HomeWidget.requestPinWidget(
        name: providerName,
        androidName: providerName,
      );
      return true;
    }
    return false;
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
