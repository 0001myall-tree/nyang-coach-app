import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'memory_service.dart';
import 'coach_id_service.dart';
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
  static const List<String> coachIds = [
    'cat',
    'boyfriend',
    'halmae',
    'bro',
    CoachIdService.nyangHalbaeId,
    'sec_female',
  ];

  /// 하루 요약용으로 모든 코치의 현재 채팅 기록을 모아 시간순으로 합친다.
  static List<dynamic> collectChatHistoryForDailySummary(
    SharedPreferences prefs,
  ) {
    final merged = <Map<String, dynamic>>[];
    for (final coachId in coachIds) {
      final normalizedCoachId = CoachIdService.normalize(coachId);
      final rawHistory = prefs.getString(
        'nyang_chat_history_$normalizedCoachId',
      );
      if (rawHistory == null) continue;
      try {
        final history = jsonDecode(rawHistory) as List;
        for (final item in history) {
          if (item is! Map) continue;
          final text = (item['text'] ?? item['content'] ?? '')
              .toString()
              .trim();
          if (text.isEmpty) continue;
          merged.add({
            ...item.cast<String, dynamic>(),
            'coachId': normalizedCoachId,
          });
        }
      } catch (_) {}
    }

    int byTime(Map<String, dynamic> a, Map<String, dynamic> b) {
      final at = DateTime.tryParse(a['time']?.toString() ?? '');
      final bt = DateTime.tryParse(b['time']?.toString() ?? '');
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    }

    merged.sort(byTime);
    return merged;
  }

  /// 리셋으로 지워지는 채팅 원문을 코치별 보관함에 합치고 7일 이전은 버린다.
  /// 서버로 올리지 않는 순수 로컬 저장이며, 열람 표시 용도로만 쓴다.
  static Future<List<dynamic>> _archiveChatHistory(
    SharedPreferences prefs,
    String coachId,
    String currentDate,
  ) async {
    final normalizedCoachId = CoachIdService.normalize(coachId);
    final rawHistory = prefs.getString('nyang_chat_history_$normalizedCoachId');
    if (rawHistory == null) return [];
    List<dynamic> history;
    try {
      history = jsonDecode(rawHistory) as List;
    } catch (_) {
      return [];
    }
    if (history.isEmpty) return [];

    final currentMessages = <dynamic>[];
    final pastMessages = <dynamic>[];
    for (final message in history) {
      final time = DateTime.tryParse(
        (message is Map ? message['time'] : null)?.toString() ?? '',
      );
      final messageDate = time == null
          ? null
          : DateFormat('yyyy-MM-dd').format(time);
      if (messageDate == currentDate) {
        currentMessages.add(message);
      } else {
        pastMessages.add(message);
      }
    }
    if (pastMessages.isEmpty) return currentMessages;

    final archiveKey = '$chatArchivePrefix$normalizedCoachId';
    List<dynamic> archive;
    try {
      archive = jsonDecode(prefs.getString(archiveKey) ?? '[]') as List;
    } catch (_) {
      archive = [];
    }

    archive.addAll(pastMessages);

    // 7일 지난 메시지는 버린다. (time 파싱 실패한 항목은 보수적으로 유지)
    final cutoff = DateTime.now().subtract(
      const Duration(days: chatArchiveDays),
    );
    archive = archive.where((e) {
      final t = DateTime.tryParse(
        (e is Map ? e['time'] : null)?.toString() ?? '',
      );
      return t == null || t.isAfter(cutoff);
    }).toList();

    // 방어적 상한: 아주 많으면 최근 것만 유지.
    const maxEntries = 2000;
    if (archive.length > maxEntries) {
      archive = archive.sublist(archive.length - maxEntries);
    }

    await prefs.setString(archiveKey, jsonEncode(archive));
    return currentMessages;
  }

  /// 날짜별 계획 보관함. 미래 계획과 함께, 자정에 넘어간 어제 목록도 여기 하루 머문다.
  static const String plannedTasksByDateKey = 'nyang_today_tasks_by_date';

  /// 지난 날의 목록을 며칠까지 남겨둘지.
  ///
  /// 하루만 남기면, 밤에 냥냥이에게 "다 했어"를 누르고 이틀 뒤에 들어온 사람은
  /// 그 표시를 잃는다. 오랜만에 여는 사람을 위해 사흘까지 들고 있는다.
  /// (오늘 탭에서 직접 열어볼 수 있는 건 어제까지다. 그 앞은 채워 넣을 자리로만 쓴다.)
  static const int archivedPastDays = 3;

  /// 자정 정리로 사라질 지난 목록을 보관함에 며칠 남긴다.
  ///
  /// 전날 완료 표시를 깜빡했거나 자정을 넘겨 끝낸 일을 나중에 채울 수 있게 하려는 것이다.
  static Future<void> archivePreviousDayTasks({
    required SharedPreferences prefs,
    required String fromDate,
    required String today,
    required List<dynamic> tasksJson,
  }) async {
    final todayDate = DateTime.tryParse(today);
    if (todayDate == null) return;
    final floor = DateFormat(
      'yyyy-MM-dd',
    ).format(todayDate.subtract(const Duration(days: archivedPastDays)));

    Map<String, dynamic> byDate = {};
    try {
      final raw = prefs.getString(plannedTasksByDateKey);
      if (raw != null && raw.isNotEmpty) {
        byDate = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}

    // 며칠 만에 열었다면 fromDate가 보관 범위 밖일 수 있다. 그때는 남길 것이 없다.
    if (tasksJson.isNotEmpty &&
        fromDate.compareTo(floor) >= 0 &&
        fromDate.compareTo(today) < 0) {
      byDate[fromDate] = tasksJson;
    }
    byDate.removeWhere((key, _) => key.compareTo(floor) < 0);

    await prefs.setString(plannedTasksByDateKey, jsonEncode(byDate));
  }

  /// 날짜별 계획을 저장할 때, 저장소에 있던 것과 합친다.
  ///
  /// 자정 정리는 두 곳에서 돈다 — 여기(저장소만 보고)와 플래너 화면(메모리를 보고).
  /// 둘이 같이 돌기 때문에, 화면이 표를 읽어둔 뒤에 이쪽이 어제 목록을 저장소에
  /// 넣는 순간이 생긴다. 그때 화면이 자기 표를 그대로 저장하면 방금 보관된 어제가
  /// 통째로 사라진다. 어제를 열었을 때 목록이 텅 비어 보이던 이유가 이것이다.
  ///
  /// 그래서 화면이 아예 모르는 날짜는 저장소 쪽을 남긴다. 화면이 아는 날짜는
  /// 비어 있더라도 화면이 이긴다 — 지운 것이 되살아나면 안 되기 때문이다.
  static Map<String, dynamic> mergePlannedTasksForSave({
    required Map<String, dynamic> stored,
    required Map<String, dynamic> encoded,
    required Set<String> knownKeys,
  }) {
    final merged = Map<String, dynamic>.from(encoded);
    stored.forEach((key, value) {
      if (knownKeys.contains(key)) return;
      merged[key] = value;
    });
    return merged;
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

  /// 로그인 상태인데 이 기기에서 첫 클라우드 복원이 아직 성공하지 않았으면 true.
  /// 이 상태에서 리셋이 돌면 재설치 직후의 빈 로컬을 기준으로 하루 전환이
  /// 실행되어, 곧 복원될 데이터를 지우거나 빈 값을 서버로 역전파할 수 있다.
  static bool isCloudRestorePending(SharedPreferences prefs) {
    if (FirebaseAuth.instance.currentUser == null) return false;
    return !(prefs.getBool('nyang_has_synced_from_cloud') ?? false);
  }

  static Future<void> checkAndExecuteReset() async {
    final prefs = await SharedPreferences.getInstance();
    if (isCloudRestorePending(prefs)) return;
    const resetHour = 0.0;
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

      // 2. Clear tasks in preferences (어제 목록은 보관함에 하루 남긴다)
      await archivePreviousDayTasks(
        prefs: prefs,
        fromDate: lastDate,
        today: today,
        tasksJson: previousTasks,
      );
      await prefs.setString('nyang_tasks', '[]');
      await prefs.setString('nyang_core_tasks', '[]');
      await prefs.setBool('nyang_core_reminder_enabled', false);
      await prefs.remove('nyang_core_reminder_coach');
      await prefs.remove('nyang_core_reminder_advance');
      await prefs.remove('nyang_deferred_tasks_today');

      // 3. Generate daily summary
      final oldChatHistory = collectChatHistoryForDailySummary(prefs);
      if (oldChatHistory.isNotEmpty) {
        await MemoryService().loadMemoryData();
        await MemoryService().generateDailySummary(lastDate, oldChatHistory);
      }

      // 4. Archive previous-day chat into a rolling 7-day store.
      //    Same-day messages stay in the current chat so app re-entry does not
      //    collapse today's conversation or trigger another automatic greeting.
      for (final id in coachIds) {
        final currentMessages = await _archiveChatHistory(prefs, id, today);
        await prefs.setString(
          'nyang_chat_history_$id',
          jsonEncode(currentMessages),
        );
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
      if (freq == 'weekly_count') {
        matches = _shouldShowWeeklyCountHabitOnDate(
          h,
          habitLogs,
          DateTime.tryParse(today) ?? DateTime.now(),
        );
      }
      if (freq == 'weekly') matches = days.contains(dbDow);

      if (matches) {
        final habitId = h['id'].toString();
        final log = (habitLogs[habitId] ?? {})[today];
        final isSkipped = log != null && log['status'] == 'skipped';
        if (isSkipped) continue;

        final isDone = log != null && log['done'] == true;
        final taskId = 'habit_${habitId.replaceAll('.', '_')}_$today';
        String? tTime;
        if (h['timeType'] == 'single' && h['timeStart'] != null) {
          tTime = _displayTimeFromStored(timeStart: h['timeStart']);
        }
        if (h['timeType'] == 'range' && h['timeStart'] != null) {
          tTime = _displayTimeFromStored(
            timeStart: h['timeStart'],
            timeEnd: h['timeEnd'],
          );
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

    // 3. 오늘 날짜로 미리 세워둔 계획 승격 + 지나간 날짜의 계획 정리
    final rawPlanned = prefs.getString('nyang_today_tasks_by_date');
    if (rawPlanned != null) {
      try {
        final Map<String, dynamic> plannedMap = jsonDecode(rawPlanned);
        final todayPlanned = plannedMap.remove(today);
        if (todayPlanned is List) {
          final existingIds = injectedTasks
              .map((t) => t['id'].toString())
              .toSet();
          for (final t in todayPlanned) {
            if (t is Map && existingIds.add(t['id'].toString())) {
              injectedTasks.add(Map<String, dynamic>.from(t));
            }
          }
        }
        // 키는 yyyy-MM-dd 형식이라 문자열 비교가 날짜 순서와 일치한다.
        // 지난 며칠은 남긴다. 뒤늦게 도착한 완료 표시를 채울 자리가 필요하다.
        final todayDate = DateTime.tryParse(today);
        final keepFrom = todayDate == null
            ? today
            : DateFormat('yyyy-MM-dd').format(
                todayDate.subtract(const Duration(days: archivedPastDays)),
              );
        plannedMap.removeWhere((key, _) => key.compareTo(keepFrom) < 0);
        await prefs.setString(
          'nyang_today_tasks_by_date',
          jsonEncode(plannedMap),
        );
      } catch (_) {}
    }

    await prefs.setString('nyang_tasks', jsonEncode(injectedTasks));
    await _saveTodayRecordDirectly(prefs, today, injectedTasks);
  }

  static DateTime _startOfWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  static String? _displayTimeFromStored({dynamic timeStart, dynamic timeEnd}) {
    final start = _parseStoredTime(timeStart?.toString());
    if (start == null) return timeStart?.toString();
    final end = _parseStoredTime(timeEnd?.toString());
    if (end == null) return _formatTimeParts(start.$1, start.$2);
    return '${_formatTimeParts(start.$1, start.$2)} ~ ${_formatTimeParts(end.$1, end.$2)}';
  }

  static (int, int)? _parseStoredTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static String _formatTimeParts(int hour, int minute) {
    final ap = hour >= 12 ? '오후' : '오전';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$ap $displayHour:${minute.toString().padLeft(2, '0')}';
  }

  static DateTime? _createdDateOf(Map<dynamic, dynamic> habit) {
    final rawCreatedAt = habit['createdAt']?.toString();
    if (rawCreatedAt == null || rawCreatedAt.isEmpty) return null;
    final createdAt = DateTime.tryParse(rawCreatedAt);
    if (createdAt == null) return null;
    return DateTime(createdAt.year, createdAt.month, createdAt.day);
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static int _weeklyVisibleTargetForDate(
    Map<dynamic, dynamic> habit,
    int target,
    DateTime date,
  ) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    final weekStart = _startOfWeek(normalizedDate);
    final createdDate = _createdDateOf(habit);
    if (createdDate == null ||
        createdDate.isBefore(weekStart) ||
        createdDate.isAfter(normalizedDate)) {
      return target;
    }

    final remainingDaysInCreationWeek = 8 - createdDate.weekday;
    return remainingDaysInCreationWeek < target
        ? remainingDaysInCreationWeek
        : target;
  }

  static bool _shouldShowWeeklyCountHabitOnDate(
    Map<dynamic, dynamic> habit,
    Map<String, dynamic> habitLogs,
    DateTime date,
  ) {
    final rawTarget = habit['weeklyTargetCount'];
    final parsedTarget = rawTarget is num
        ? rawTarget.toInt()
        : int.tryParse('$rawTarget') ?? 5;
    final rawClampedTarget = parsedTarget < 1
        ? 1
        : (parsedTarget > 7 ? 7 : parsedTarget);
    final target = _weeklyVisibleTargetForDate(habit, rawClampedTarget, date);
    final habitId = habit['id']?.toString();
    if (habitId == null) return true;

    final logsForHabit = habitLogs[habitId];
    if (logsForHabit is! Map) return true;

    final normalizedDate = DateTime(date.year, date.month, date.day);
    final weekStart = _startOfWeek(normalizedDate);
    final createdDate = _createdDateOf(habit);
    final countStart =
        createdDate != null &&
            !createdDate.isBefore(weekStart) &&
            createdDate.isBefore(normalizedDate)
        ? createdDate
        : weekStart;
    var doneCountBeforeDate = 0.0;

    for (
      var cursor = countStart;
      cursor.isBefore(normalizedDate);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      final log = logsForHabit[_dateKey(cursor)];
      doneCountBeforeDate += _habitLogCompletionRatio(log);
    }

    final todayLog = logsForHabit[_dateKey(normalizedDate)];
    final dateDone = todayLog is Map && todayLog['done'] == true;
    return dateDone || doneCountBeforeDate < target;
  }

  static double _habitLogCompletionRatio(dynamic log) {
    if (log is! Map || log['done'] != true) return 0;
    final rawRatio = log['progressRatio'];
    if (rawRatio is num) {
      final ratio = rawRatio.toDouble();
      return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
    }
    final count = (log['count'] as num?)?.toDouble();
    final countGoal = (log['countGoal'] as num?)?.toDouble();
    if (count != null && countGoal != null && countGoal > 0) {
      final ratio = count / countGoal;
      return ratio < 0 ? 0 : (ratio > 1 ? 1 : ratio);
    }
    return 1;
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

    final rawHabits = prefs.getString('nyang_habits') ?? '[]';
    final List<dynamic> habitsList = jsonDecode(rawHabits);
    final countableTasks = tasksList
        .where((t) => _countsTowardDailyCompletion(t, habitsList))
        .toList();
    final doneTasks = countableTasks.where((t) => t['done'] == true).toList();

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
      'totalCount': countableTasks.length,
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

  static bool _countsTowardDailyCompletion(
    Map<String, dynamic> task,
    List<dynamic> habits,
  ) {
    final habitId = task['habitId']?.toString();
    if (habitId == null) return true;
    Map<dynamic, dynamic>? habit;
    for (final item in habits) {
      if (item is Map && item['id']?.toString() == habitId) {
        habit = item;
        break;
      }
    }
    if (habit == null) return true;
    return habit['freq'] != 'weekly_count' || task['done'] == true;
  }
}
