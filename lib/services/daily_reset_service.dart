import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'memory_service.dart';
import 'tasks_sync_service.dart';

class DailyResetService {
  static String _getTodayStr(double resetHour) {
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy-MM-dd').format(base);
  }

  static String _getWeekMondayStr() {
    final now = DateTime.now();
    final dayOfWeek = now.weekday; // 1=Mon ~ 7=Sun
    final monday = now.subtract(Duration(days: dayOfWeek - 1));
    return DateFormat('yyyy-MM-dd').format(monday);
  }

  static Future<void> checkAndExecuteReset() async {
    final prefs = await SharedPreferences.getInstance();
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final today = _getTodayStr(resetHour);
    final lastDate = prefs.getString('nyang_last_date');

    if (lastDate == null) {
      await prefs.setString('nyang_last_date', today);
      return;
    }

    if (lastDate != today) {
      // 1. Calculate streak
      final rawHistory = prefs.getString('nyang_history');
      List<dynamic> history = [];
      if (rawHistory != null) {
        history = jsonDecode(rawHistory);
      }

      final prev = history.cast<Map<String, dynamic>>().firstWhere(
        (h) => h['date'] == lastDate,
        orElse: () => <String, dynamic>{},
      );

      final n = DateTime.now();
      var yesterday = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
      if (n.hour < resetHour) {
        yesterday = yesterday.subtract(const Duration(days: 1));
      }
      final yStr = DateFormat('yyyy-MM-dd').format(yesterday);

      int streak = prefs.getInt('nyang_streak') ?? 0;
      final rawVacation = prefs.getString('nyang_vacation');
      final isLastVacation = rawVacation != null;

      if (lastDate == yStr) {
        if (prev.isNotEmpty && prev['success'] == true) {
          streak += 1;
        } else if (isLastVacation) {
          /* keep streak */
        } else {
          streak = 0;
        }
      } else {
        if (prev.isNotEmpty && (prev['success'] == true || isLastVacation)) {
          streak = 1;
        } else {
          streak = 0;
        }
      }
      await prefs.setInt('nyang_streak', streak);

      // 2. Clear tasks in preferences
      await prefs.setString('nyang_tasks', '[]');
      await prefs.setString('nyang_core_tasks', '[]');
      await prefs.setBool('nyang_core_reminder_enabled', false);
      await prefs.remove('nyang_core_reminder_coach');
      await prefs.remove('nyang_core_reminder_advance');
      await prefs.remove('nyang_deferred_tasks_today');

      // 3. Generate daily summary
      final currentChar = prefs.getString('nyang_selected_coach') ?? '';
      if (currentChar.isNotEmpty) {
        final historyStr = prefs.getString('nyang_chat_history_$currentChar');
        if (historyStr != null) {
          try {
            final List<dynamic> oldChatHistory = jsonDecode(historyStr);
            if (oldChatHistory.isNotEmpty) {
              await MemoryService().loadMemoryData();
              await MemoryService().generateDailySummary(lastDate, oldChatHistory);
            }
          } catch (_) {}
        }
      }

      // 4. Clear all chat histories
      final coachIds = ['cat', 'boyfriend', 'girlfriend', 'halmae', 'bro', 'sec_male', 'sec_female'];
      for (final id in coachIds) {
        await prefs.setString('nyang_chat_history_$id', '[]');
      }

      await prefs.setString('nyang_last_date', today);

      // 5. Inject habits & schedules to prefs for the new day
      await _injectTodayHabitsAndSchedulesDirectly(prefs, today);
      TasksSyncService.scheduleSyncToCloud();
    }

    // Weekly/Monthly Reset Check
    final thisWeek = _getWeekMondayStr();
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final lastWeek = prefs.getString('nyang_last_week');
    if (lastWeek == null) {
      await prefs.setString('nyang_last_week', thisWeek);
    } else if (lastWeek != thisWeek) {
      await prefs.setString('nyang_last_week', thisWeek);
      await prefs.setString('nyang_week_goals', '[]');
    }

    final lastMonth = prefs.getString('nyang_last_month');
    if (lastMonth == null) {
      await prefs.setString('nyang_last_month', thisMonth);
    } else if (lastMonth != thisMonth) {
      await prefs.setString('nyang_last_month', thisMonth);
      await prefs.setString('nyang_month_goals', '[]');
    }
  }

  static Future<void> _injectTodayHabitsAndSchedulesDirectly(SharedPreferences prefs, String today) async {
    final todayDow = DateTime.now().weekday; // 1=Mon ~ 7=Sun
    final dbDow = todayDow - 1; // 0=Mon ~ 6=Sun

    // 1. habits load
    final rawHabits = prefs.getString('nyang_habits') ?? '[]';
    final List<dynamic> habitsList = jsonDecode(rawHabits);
    final rawLogs = prefs.getString('nyang_habit_logs') ?? '{}';
    final Map<String, dynamic> habitLogs = jsonDecode(rawLogs);

    List<Map<String, dynamic>> injectedTasks = [];

    for (final h in habitsList) {
      if (h is! Map) continue;
      final freq = h['freq'] ?? 'daily';
      final days = List<int>.from(h['days'] ?? []);
      bool matches = false;
      if (freq == 'daily') matches = true;
      if (freq == 'weekly') matches = days.contains(dbDow);

      if (matches) {
        final habitId = h['id'].toString();
        final log = (habitLogs[habitId] ?? {})[today];
        final isSkipped = log != null && log['status'] == 'skipped';
        if (isSkipped) continue;

        final isDone = log != null && log['done'] == true;
        final taskId = 'habit_${habitId.replaceAll('.', '_')}_$today';
        String? tTime;
        if (h['timeType'] == 'single' && h['timeStart'] != null) tTime = h['timeStart'];
        if (h['timeType'] == 'range' && h['timeStart'] != null) {
          tTime = h['timeEnd'] != null ? "${h['timeStart']} ~ ${h['timeEnd']}" : h['timeStart'];
        }

        injectedTasks.add({
          'id': taskId,
          'habitId': habitId,
          'text': h['name'],
          'category': 'habit',
          'done': isDone,
          'isHabit': true,
          'time': tTime,
          'duration': h['habitDuration'],
          'timeStart': h['timeStart'],
          'timeEnd': h['timeEnd'],
          'createdAt': DateTime.now().toIso8601String(),
          'completedAt': isDone ? log['completedAt'] : null,
          'isReminderEnabled': h['isReminderEnabled'] ?? false,
        });
      }
    }

    // 2. schedules load
    final rawSchedules = prefs.getString('nyang_schedules') ?? '{}';
    final Map<String, dynamic> schedulesMap = jsonDecode(rawSchedules);
    final List<dynamic> todaySchedules = schedulesMap[today] ?? [];

    for (final s in todaySchedules) {
      if (s is! Map) continue;
      final taskId = 'schedule_${s['id']}';
      injectedTasks.add({
        'id': taskId,
        'text': s['text'],
        'category': 'schedule',
        'done': s['done'] ?? false,
        'time': s['time'],
        'duration': s['duration'],
        'timeStart': s['timeStart'],
        'timeEnd': s['timeEnd'],
        'createdAt': s['createdAt'] ?? DateTime.now().toIso8601String(),
        'isReminderEnabled': s['isReminderEnabled'] ?? false,
        'deferredCount': s['deferredCount'] ?? 0,
        'googleEventId': s['googleEventId'],
        'googleUpdated': s['googleUpdated'],
        'isRecurring': s['isRecurring'] ?? false,
      });

      if (s['isReminderEnabled'] == true) {
        final rawCore = prefs.getString('nyang_core_tasks') ?? '[]';
        final List<dynamic> coreList = jsonDecode(rawCore);
        final coreExists = coreList.any((t) => t['id'].toString() == taskId);
        if (!coreExists) {
          coreList.add({
            'id': taskId,
            'text': s['text'],
            'category': 'schedule',
            'done': s['done'] ?? false,
            'time': s['time'],
            'duration': s['duration'],
            'timeStart': s['timeStart'],
            'timeEnd': s['timeEnd'],
            'createdAt': s['createdAt'] ?? DateTime.now().toIso8601String(),
            'isReminderEnabled': true,
            'deferredCount': s['deferredCount'] ?? 0,
            'googleEventId': s['googleEventId'],
            'googleUpdated': s['googleUpdated'],
            'isRecurring': s['isRecurring'] ?? false,
          });
          await prefs.setString('nyang_core_tasks', jsonEncode(coreList));
        }
      }
    }

    await prefs.setString('nyang_tasks', jsonEncode(injectedTasks));
  }
}
