import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'memory_service.dart';
import 'tasks_sync_service.dart';

class DailyResetService {
  static const String lastResetAtKey = 'nyang_last_daily_reset_at';
  static const String lastResetFromDateKey = 'nyang_last_daily_reset_from_date';
  static const String lastResetToDateKey = 'nyang_last_daily_reset_to_date';
  static const String previousDayHadTasksKey = 'nyang_previous_day_had_tasks';
  static const String previousDayAllDoneKey =
      'nyang_previous_day_all_tasks_done';

  /// "지난 대화 보기"용 코치별 로컬 보관함 키 접두사. 최근 7일치만 유지한다.
  static const String chatArchivePrefix = 'nyang_chat_archive_';
  static const int chatArchiveDays = 7;

  /// 리셋으로 지워지는 채팅 원문을 코치별 보관함에 합치고 7일 이전은 버린다.
  /// 서버로 올리지 않는 순수 로컬 저장이며, 열람 표시 용도로만 쓴다.
  static Future<void> _archiveChatHistory(
    SharedPreferences prefs,
    String coachId,
  ) async {
    final rawHistory = prefs.getString('nyang_chat_history_$coachId');
    if (rawHistory == null) return;
    List<dynamic> todays;
    try {
      todays = jsonDecode(rawHistory) as List;
    } catch (_) {
      return;
    }
    if (todays.isEmpty) return;

    final archiveKey = '$chatArchivePrefix$coachId';
    List<dynamic> archive;
    try {
      archive = jsonDecode(prefs.getString(archiveKey) ?? '[]') as List;
    } catch (_) {
      archive = [];
    }

    archive.addAll(todays);

    // 7일 지난 메시지는 버린다. (time 파싱 실패한 항목은 보수적으로 유지)
    final cutoff = DateTime.now().subtract(
      const Duration(days: chatArchiveDays),
    );
    archive = archive.where((e) {
      final t = DateTime.tryParse((e is Map ? e['time'] : null)?.toString() ?? '');
      return t == null || t.isAfter(cutoff);
    }).toList();

    // 방어적 상한: 아주 많으면 최근 것만 유지.
    const maxEntries = 2000;
    if (archive.length > maxEntries) {
      archive = archive.sublist(archive.length - maxEntries);
    }

    await prefs.setString(archiveKey, jsonEncode(archive));
  }

  static Future<void> recordDayTransition({
    required SharedPreferences prefs,
    required String fromDate,
    required String toDate,
    required bool previousDayHadTasks,
    required bool previousDayAllDone,
  }) async {
    await prefs.setString(lastResetAtKey, DateTime.now().toIso8601String());
    await prefs.setString(lastResetFromDateKey, fromDate);
    await prefs.setString(lastResetToDateKey, toDate);
    await prefs.setBool(previousDayHadTasksKey, previousDayHadTasks);
    await prefs.setBool(previousDayAllDoneKey, previousDayAllDone);
  }

  static String _getTodayStr(double resetHour) {
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy-MM-dd').format(base);
  }

  static String _getWeekMondayStr(String today) {
    final parts = today.split('-');
    DateTime baseDate;
    if (parts.length >= 3) {
      baseDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } else {
      final now = DateTime.now();
      baseDate = DateTime(now.year, now.month, now.day);
    }
    final dayOfWeek = baseDate.weekday; // 1=Mon ~ 7=Sun
    final monday = baseDate.subtract(Duration(days: dayOfWeek - 1));
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
      final previousTasksRaw = prefs.getString('nyang_tasks') ?? '[]';
      List<dynamic> previousTasks = [];
      try {
        previousTasks = jsonDecode(previousTasksRaw) as List;
      } catch (_) {}
      final previousDayHadTasks = previousTasks.isNotEmpty;
      final previousDayAllDone =
          previousDayHadTasks &&
          previousTasks.every((task) => task is Map && task['done'] == true);
      await recordDayTransition(
        prefs: prefs,
        fromDate: lastDate,
        toDate: today,
        previousDayHadTasks: previousDayHadTasks,
        previousDayAllDone: previousDayAllDone,
      );

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
      var yesterday = DateTime(
        n.year,
        n.month,
        n.day,
      ).subtract(const Duration(days: 1));
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

      // '오늘만 쉬기'는 이전 활동일의 기록과 연속 출석을 보호한 뒤 자동 종료합니다.
      if (rawVacation != null) {
        try {
          final vacation = jsonDecode(rawVacation) as Map<String, dynamic>;
          if (vacation['type'] == 'today' &&
              vacation['date']?.toString() != today) {
            await prefs.remove('nyang_vacation');
          }
        } catch (_) {}
      }

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
              await MemoryService().generateDailySummary(
                lastDate,
                oldChatHistory,
              );
            }
          } catch (_) {}
        }
      }

      // 4. Archive each coach's chat into a rolling 7-day store, then clear.
      //    "지난 대화 보기"에서 최근 7일치를 열람하는 데만 쓰이는 로컬 보관함이다.
      final coachIds = [
        'cat',
        'boyfriend',
        'girlfriend',
        'halmae',
        'bro',
        'sec_male',
        'sec_female',
      ];
      for (final id in coachIds) {
        await _archiveChatHistory(prefs, id);
        await prefs.setString('nyang_chat_history_$id', '[]');
      }

      await prefs.setString('nyang_last_date', today);

      // 5. Inject habits & schedules to prefs for the new day
      await _injectTodayHabitsAndSchedulesDirectly(prefs, today);
      TasksSyncService.scheduleSyncToCloud();
    }

    // Weekly/Monthly Reset Check
    final thisWeek = _getWeekMondayStr(today);
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

  static Future<void> _injectTodayHabitsAndSchedulesDirectly(
    SharedPreferences prefs,
    String today,
  ) async {
    final parts = today.split('-');
    int todayDow = DateTime.now().weekday;
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final d = int.tryParse(parts[2]) ?? DateTime.now().day;
      todayDow = DateTime(y, m, d).weekday;
    }
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
        if (h['timeType'] == 'single' && h['timeStart'] != null)
          tTime = h['timeStart'];
        if (h['timeType'] == 'range' && h['timeStart'] != null) {
          tTime = h['timeEnd'] != null
              ? "${h['timeStart']} ~ ${h['timeEnd']}"
              : h['timeStart'];
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
    await _saveTodayRecordDirectly(prefs, today, injectedTasks);
  }

  static Future<void> _saveTodayRecordDirectly(
    SharedPreferences prefs,
    String todayStr,
    List<Map<String, dynamic>> tasksList,
  ) async {
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      try {
        final List decoded = jsonDecode(rawHistory);
        history = decoded.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    final doneTasks = tasksList.where((t) => t['done'] == true).toList();

    // 밤 9시 이후 이월된 일정 로드
    final rawDeferred = prefs.getString('nyang_deferred_tasks_today');
    List<dynamic> deferredList = [];
    if (rawDeferred != null) {
      try {
        deferredList = jsonDecode(rawDeferred);
      } catch (_) {}
    }

    final mergedTasks = [
      ...tasksList.map(
        (t) => {
          'text': t['text'],
          'done': t['done'] ?? false,
          'inProgress': t['inProgress'] ?? false,
          if (t['inProgressAt'] != null) 'startedAt': t['inProgressAt'],
          if (t['completedAt'] != null) 'completedAt': t['completedAt'],
          'category': t['category'] ?? 'today',
          'deferred': false,
        },
      ),
      ...deferredList.map(
        (t) => {
          'text': t['text'],
          'done': t['done'] ?? false,
          'category': t['category'] ?? 'today',
          'deferred': true,
        },
      ),
    ];

    final rawVacation = prefs.getString('nyang_vacation');
    final record = {
      'date': todayStr,
      'totalCount': tasksList.length,
      'doneCount': doneTasks.length,
      'success': doneTasks.isNotEmpty,
      'isVacation': rawVacation != null,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': mergedTasks,
    };

    final idx = history.indexWhere((h) => h['date'] == todayStr);
    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
    }

    history.sort((a, b) => a['date']!.compareTo(b['date']!));
    if (history.length > 30) history = history.sublist(history.length - 30);

    await prefs.setString('nyang_history', jsonEncode(history));
  }
}
