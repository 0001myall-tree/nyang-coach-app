import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WidgetSyncService {
  static const String androidWidgetNyang = 'NyangWidgetProvider';
  static const String androidWidgetSecMale = 'SecMaleWidgetProvider';
  static const String androidWidgetSecFemale = 'SecFemaleWidgetProvider';

  static const String iOSWidgetName = 'NyangWidget';

  static Future<void> syncFromStoredTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getString('nyang_tasks');
    final tasks = rawTasks == null
        ? <Map<String, dynamic>>[]
        : _decodeTasks(rawTasks);
    final doneTasks = tasks.where((task) => task['done'] == true).toList();
    final remainingTasks = tasks.where((task) => task['done'] != true).toList();
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
      if (progress >= 1.0) return "최고다냥! 다 끝냈다냥! 💜";
      if (progress >= 0.80) return "거의 다 왔다냥! ✨";
      if (progress >= 0.51) return "아주 잘하고 있다냥! 💜";
      if (progress >= 0.21) return "차근차근 가고있다냥! ✨";
      return "오늘도 시작해보자냥! 💜";
    } else if (coachId == 'sec_female') {
      // 여비서 코치
      if (progress >= 1.0) return "오늘도 멋지게 해내셨네요 🌸";
      if (progress >= 0.80) return "조금만 더 힘내볼까요? 🌸";
      if (progress >= 0.51) return "아주 잘 해내고 계십니다. 🌸";
      if (progress >= 0.21) return "순조로운 흐름입니다. 🌸";
      return "오늘 하루도 응원합니다. 🌸";
    } else {
      // 남비서 코치 (sec_male)
      if (progress >= 1.0) return "오늘도 수고 많으셨습니다. ☕";
      if (progress >= 0.80) return "조금만 더 가면 됩니다. ☕";
      if (progress >= 0.51) return "아주 잘 해내고 계십니다. ☕";
      if (progress >= 0.21) return "흐름이 좋습니다. ☕";
      return "오늘도 함께 해보시죠. ☕";
    }
  }
}
