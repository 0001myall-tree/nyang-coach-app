import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/user_title_service.dart';
import 'package:nyang_coach/services/analytics_service.dart';
import 'package:nyang_coach/services/api_usage_limit_service.dart';
import 'package:nyang_coach/services/task_resistance_service.dart';
import 'package:nyang_coach/services/execution_resistance_service.dart';
import 'package:nyang_coach/services/start_pattern_service.dart';
import 'package:nyang_coach/services/tasks_sync_service.dart';
import 'package:nyang_coach/models/user_data.dart';
import 'coach_config.dart';
import 'tasks_screen.dart'; // for HabitItem, etc.

class RecordsScreen extends StatefulWidget {
  final String coachId;
  const RecordsScreen({super.key, required this.coachId});

  /// 코치 한마디를 다시 뽑게 만들 때 올리는 번호.
  ///
  /// 기록탭의 캐시와 탭에 붙는 안 읽음 표시가 이 하나를 함께 본다. 따로 두었을
  /// 때는 한마디를 새로 뽑게 해놓고 표시 쪽 번호를 안 올려서, 새 한마디가
  /// 나왔는데 사용자는 모르는 일이 생겼다.
  static const int weeklyFeedbackVersion = 5;

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {

  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  Map<String, Map<String, dynamic>> _habitLogs = {};
  List<HabitItem> _habits = [];
  String _userTitle = UserTitleService.defaultTitle;
  String? _weeklyFeedbackText;
  bool _isGeneratingWeeklyFeedback = false;
  bool _hasMasterPlan = false;
  String _lastDate = '';
  List<_WeeklyCoachRank> _weeklyFavoriteCoachRanks = const [];
  int _weeklyCompletedResistanceCount = 0;
  final HttpsCallable _chatProxy = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable('chatProxy');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = await UserDataService.load();
    _hasMasterPlan = userData.isPlanActive && userData.planType == 'master';

    // 1. History (nyang_history)
    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory != null) {
      final List decoded = jsonDecode(rawHistory);
      _history = decoded.cast<Map<String, dynamic>>();
    }

    // 2. Habits
    final rawHabits = prefs.getString('nyang_habits');
    if (rawHabits != null) {
      final List decoded = jsonDecode(rawHabits);
      _habits = decoded.map((e) => HabitItem.fromJson(e)).toList();
    }

    // 3. Habit Logs
    final rawLogs = prefs.getString('nyang_habit_logs');
    if (rawLogs != null) {
      final Map decoded = jsonDecode(rawLogs);
      _habitLogs = decoded.map(
        (k, v) => MapEntry(
          k.toString(),
          (v as Map).map((k2, v2) => MapEntry(k2.toString(), v2)),
        ),
      );
    }


    _userTitle = await UserTitleService.getTitle();
    _lastDate = prefs.getString('nyang_last_date') ?? '';
    if (_lastDate.isEmpty) {
      final n = DateTime.now();
      var base = DateTime(n.year, n.month, n.day);
      if (n.hour < 3) {
        base = base.subtract(const Duration(days: 1));
      }
      _lastDate =
          '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
    }
    await _loadWeeklyCompanionStats(prefs);

    setState(() => _isLoading = false);
    if (_isMaster) {
      _loadOrGenerateWeeklyFeedback();
    }
  }

  bool get _isMaster => _hasMasterPlan;
  CoachConfig get _coach => CoachConfigs.get(widget.coachId);
  CoachConfig get _recordCoach =>
      _isMaster ? CoachConfigs.get('sec_female') : _coach;

  // ── 최근 7일(또는 30일) 데이터 계산 ─────────────────────
  DateTime _feedbackBaseDate() {
    final baseDateParts = _lastDate.split('-');
    if (baseDateParts.length >= 3) {
      final y = int.tryParse(baseDateParts[0]) ?? DateTime.now().year;
      final m = int.tryParse(baseDateParts[1]) ?? DateTime.now().month;
      final d = int.tryParse(baseDateParts[2]) ?? DateTime.now().day;
      return DateTime(y, m, d);
    }

    final n = DateTime.now();
    var baseDate = DateTime(n.year, n.month, n.day);
    if (n.hour < 3) {
      baseDate = baseDate.subtract(const Duration(days: 1));
    }
    return baseDate;
  }

  List<Map<String, dynamic>> _getLast7Records({
    bool includeCurrentAppDate = true,
  }) {
    final baseDate = includeCurrentAppDate
        ? _feedbackBaseDate()
        : _feedbackBaseDate().subtract(const Duration(days: 1));

    final List<Map<String, dynamic>> last7 = [];
    for (int i = 6; i >= 0; i--) {
      final d = baseDate.subtract(Duration(days: i));
      final dateStr =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

      // history에서 찾기
      final existing = _history.where((r) => r['date'] == dateStr).toList();
      if (existing.isNotEmpty) {
        // 쉬는 날 표시는 그날 기록에 적혀 있던 것을 그대로 쓴다. 휴식 모드는
        // 걷어냈지만 지난 기록의 값은 남아 있고, 그 숫자를 지금 다시 계산해
        // 덮어쓰면 예전에 쉬었던 날이 실패로 바뀐다.
        last7.add(Map<String, dynamic>.from(existing.last));
      } else {
        // 기록이 없으면 빈 데이터
        last7.add({
          'date': dateStr,
          'totalCount': 0,
          'doneCount': 0,
          'success': false,
          'isVacation': false,
          'tasks': [],
        });
      }
    }
    return last7;
  }

  String _getWeekMondayStr() {
    final baseDate = _feedbackBaseDate();
    final monday = baseDate.subtract(Duration(days: baseDate.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  DateTime _weekStartDate() => DateTime.parse(_getWeekMondayStr());

  DateTime _weekEndExclusive() {
    final base = _feedbackBaseDate();
    final end = DateTime(base.year, base.month, base.day);
    return end.add(const Duration(days: 1));
  }

  bool _isInCurrentWeek(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return !normalized.isBefore(_weekStartDate()) &&
        normalized.isBefore(_weekEndExclusive());
  }

  Future<void> _loadWeeklyCompanionStats(SharedPreferences prefs) async {
    final coachMessageCounts = <String, int>{};

    for (final coachId in CoachConfigs.all.keys) {
      final messages = <dynamic>[];
      for (final key in [
        'nyang_chat_history_$coachId',
        'nyang_chat_archive_$coachId',
      ]) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          messages.addAll(jsonDecode(raw) as List);
        } catch (_) {}
      }

      final count = messages.where((message) {
        if (message is! Map) return false;
        if (message['isUser'] != true) return false;
        final time = DateTime.tryParse(message['time']?.toString() ?? '');
        return time != null && _isInCurrentWeek(time);
      }).length;
      if (count > 0) coachMessageCounts[coachId] = count;
    }

    final coachOrder = CoachConfigs.all.keys.toList();
    final sortedFavoriteCoaches = coachMessageCounts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return coachOrder.indexOf(a.key).compareTo(coachOrder.indexOf(b.key));
      });

    final events = await TaskResistanceService.getAllEvents();
    final completedResistanceKeys = <String>{};
    for (final event in events) {
      if (event.signalType != 'explicit') continue;
      if (!event.completedEventually) continue;
      final date = DateTime.tryParse(event.date);
      if (date == null || !_isInCurrentWeek(date)) continue;
      completedResistanceKeys.add(
        _resistanceTaskKey(event.date, event.taskText),
      );
    }
    final completedResistanceCount =
        completedResistanceKeys.length +
        _inferCompletedResistanceCountFromChat(
          prefs,
          countedTaskKeys: completedResistanceKeys,
        );

    _weeklyFavoriteCoachRanks = [
      for (var i = 0; i < sortedFavoriteCoaches.length && i < 2; i++)
        _WeeklyCoachRank(
          rank: i + 1,
          coachName: CoachConfigs.get(sortedFavoriteCoaches[i].key).name,
        ),
    ];
    _weeklyCompletedResistanceCount = completedResistanceCount;
  }

  int _inferCompletedResistanceCountFromChat(
    SharedPreferences prefs, {
    required Set<String> countedTaskKeys,
  }) {
    final resistanceMessagesByDate = <String, List<String>>{};
    for (final coachId in CoachConfigs.all.keys) {
      for (final key in [
        'nyang_chat_history_$coachId',
        'nyang_chat_archive_$coachId',
      ]) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final messages = jsonDecode(raw) as List;
          for (final message in messages.whereType<Map>()) {
            if (message['isUser'] != true) continue;
            final text = message['text']?.toString() ?? '';
            if (!ExecutionResistanceService.isResistanceExpression(text)) {
              continue;
            }
            final time = DateTime.tryParse(message['time']?.toString() ?? '');
            if (time == null || !_isInCurrentWeek(time)) continue;
            final dateKey = _dateKey(time);
            resistanceMessagesByDate
                .putIfAbsent(dateKey, () => <String>[])
                .add(text);
          }
        } catch (_) {}
      }
    }

    final inferredKeys = <String>{};
    var count = 0;

    void countCompletedTasksForDate(
      String date,
      Iterable<Map<String, dynamic>> tasks,
    ) {
      final messages = resistanceMessagesByDate[date];
      if (messages == null || messages.isEmpty) return;
      for (final task in tasks) {
        if (task['done'] != true) continue;
        final taskText = task['text']?.toString() ?? '';
        if (taskText.trim().isEmpty) continue;
        final key = _resistanceTaskKey(date, taskText);
        if (countedTaskKeys.contains(key) || inferredKeys.contains(key)) {
          continue;
        }
        final mentioned = messages.any(
          (message) => TaskResistanceService.messageMentionsTask(
            message: message,
            taskText: taskText,
          ),
        );
        if (!mentioned) continue;
        inferredKeys.add(key);
        count++;
      }
    }

    for (final record in _getLast7Records()) {
      final date = record['date']?.toString() ?? '';
      countCompletedTasksForDate(date, _visibleRecordTasks(record));
    }

    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks != null) {
      try {
        final tasks = (jsonDecode(rawTasks) as List)
            .whereType<Map>()
            .map((task) => Map<String, dynamic>.from(task))
            .where(
              (task) =>
                  task['category'] == 'today' ||
                  task['category'] == 'habit' ||
                  task['category'] == 'schedule',
            );
        countCompletedTasksForDate(_dateKey(_feedbackBaseDate()), tasks);
      } catch (_) {
        // Ignore malformed local task snapshots.
      }
    }
    return count;
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  String _resistanceTaskKey(String date, String taskText) =>
      '$date|${TaskResistanceService.normalizeForTaskMatch(taskText)}';

  List<Map<String, dynamic>> _visibleRecordTasks(Map<String, dynamic> record) {
    final rawTasks = (record['tasks'] as List?) ?? [];
    return rawTasks
        .whereType<Map>()
        .map((task) => Map<String, dynamic>.from(task))
        .where((task) => task['deferred'] != true)
        .toList();
  }

  int _recordTotalCount(Map<String, dynamic> record) {
    final visibleTasks = _visibleRecordTasks(record);
    if (visibleTasks.isNotEmpty) return visibleTasks.length;
    return (record['totalCount'] as num?)?.toInt() ?? 0;
  }

  int _recordDoneCount(Map<String, dynamic> record) {
    final visibleTasks = _visibleRecordTasks(record);
    if (visibleTasks.isNotEmpty) {
      return visibleTasks.where((task) => task['done'] == true).length;
    }
    return (record['doneCount'] as num?)?.toInt() ?? 0;
  }

  /// 그날 손을 댄 할 일 수. 끝냈든 시작만 했든 센다.
  ///
  /// 시작 기록만 세면 안 된다. 타이머를 거치지 않고 체크만 해서 끝낸 일은
  /// 시작 기록이 없어서, 손댄 수가 완료 수보다 작아지는 일이 생긴다.
  int _recordTouchedCount(Map<String, dynamic> record) {
    final visibleTasks = _visibleRecordTasks(record);
    if (visibleTasks.isNotEmpty) {
      return visibleTasks
          .where((task) => task['done'] == true || _taskWasStarted(task))
          .length;
    }
    return (record['doneCount'] as num?)?.toInt() ?? 0;
  }

  int _selectFeedbackType(SharedPreferences prefs, String weekMonday) {
    final thisMonday = DateTime.parse(weekMonday);
    final lastWeekMonday = thisMonday.subtract(const Duration(days: 7));
    final twoWeeksAgoMonday = thisMonday.subtract(const Duration(days: 14));

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final usedTypes = <int>{};
    try {
      final d1 =
          prefs.getString('nyang_coach_weekly_feedback_nyang_halbae') ??
          prefs.getString('nyang_coach_weekly_feedback_sec_male');
      if (d1 != null) {
        final m = jsonDecode(d1) as Map<String, dynamic>;
        if (m['weekMonday'] == fmt(lastWeekMonday) && m['type'] != null) {
          usedTypes.add(m['type'] as int);
        }
      }
      final d2 = prefs.getString('nyang_feedback_prev_week');
      if (d2 != null) {
        final m = jsonDecode(d2) as Map<String, dynamic>;
        if (m['weekMonday'] == fmt(twoWeeksAgoMonday) && m['type'] != null) {
          usedTypes.add(m['type'] as int);
        }
      }
    } catch (_) {}

    final available = [0, 1, 2].where((t) => !usedTypes.contains(t)).toList()
      ..shuffle();
    return available.first;
  }

  Future<void> _loadOrGenerateWeeklyFeedback() async {
    if (_isGeneratingWeeklyFeedback) return;
    final prefs = await SharedPreferences.getInstance();
    final legacyMaleFeedback = prefs.getString(
      'nyang_coach_weekly_feedback_sec_male',
    );
    if (legacyMaleFeedback != null &&
        prefs.getString('nyang_coach_weekly_feedback_nyang_halbae') == null) {
      await prefs.setString(
        'nyang_coach_weekly_feedback_nyang_halbae',
        legacyMaleFeedback,
      );
    }
    await prefs.remove('nyang_coach_weekly_feedback_sec_male');

    // 구버전이 쓰던 여비서용 캐시 키 정리. 코치의 한마디는 마스터 공용으로
    // nyang_halbae 키 하나만 사용한다. (로컬에 남아 있으면 클라우드에 계속 재업로드됨)
    await prefs.remove('nyang_coach_weekly_feedback_sec_female');
    final weekMonday = _getWeekMondayStr();
    final cacheKey = 'nyang_coach_weekly_feedback_nyang_halbae';
    final cachedData = prefs.getString(cacheKey);

    try {
      if (cachedData != null) {
        final cached = jsonDecode(cachedData) as Map<String, dynamic>;
        if (cached['weekMonday'] == weekMonday &&
            cached['version'] == RecordsScreen.weeklyFeedbackVersion &&
            (cached['text'] as String?)?.trim().isNotEmpty == true) {
          if (!mounted) return;
          setState(() {
            _weeklyFeedbackText = cached['text'] as String;
          });
          return;
        }
      }
    } catch (_) {}

    final feedbackType = _selectFeedbackType(prefs, weekMonday);
    await _triggerWeeklyFeedback(weekMonday, cacheKey, feedbackType);
  }

  Future<void> _triggerWeeklyFeedback(
    String weekMonday,
    String cacheKey,
    int feedbackType,
  ) async {
    if (_isGeneratingWeeklyFeedback) return;
    _isGeneratingWeeklyFeedback = true;
    if (mounted) {
      setState(() {
        _weeklyFeedbackText = null;
      });
    }

    try {
      final prompt = await _buildWeeklyFeedbackPrompt(feedbackType);
      final estimatedPromptTokens = AnalyticsService.estimateChatTokens([
        {'content': prompt},
      ], '');
      final limit = await ApiUsageLimitService.checkChatAllowance(
        estimatedTokens: estimatedPromptTokens,
      );
      if (!limit.allowed) {
        if (mounted) {
          setState(() {
            _weeklyFeedbackText = limit.message;
          });
        }
        return;
      }

      final response = await _chatProxy.call({
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.5,
      });
      final feedbackText = (response.data['content'] as String? ?? '')
          .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
          .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
          .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
          .trim();

      if (feedbackText.isEmpty) return;

      // API 사용 기록 (주간 리포트 생성에 따른 토큰/비용 집계)
      final estimatedTokens = AnalyticsService.estimateChatTokens([
        {'content': prompt},
      ], feedbackText);
      final usageData = response.data is Map ? response.data as Map : const {};
      final actualTokens = AnalyticsService.readIntValue(usageData, [
        'totalTokens',
        'total_tokens',
        'tokens',
        'usage.totalTokens',
        'usage.total_tokens',
      ]);
      final actualCostWon = AnalyticsService.readIntValue(usageData, [
        'costWon',
        'cost_won',
        'estimatedCostWon',
        'estimated_cost_won',
        'usage.costWon',
      ]);

      AnalyticsService.logApiUsage(
        coachId: widget.coachId,
        estimatedTokens: estimatedTokens,
        actualTokens: actualTokens,
        actualCostWon: actualCostWon,
        usageSource: 'weekly_feedback',
        countAsUserUsage: false,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'weekMonday': weekMonday,
          'text': feedbackText,
          'type': feedbackType,
          'version': RecordsScreen.weeklyFeedbackVersion,
        }),
      );
      await prefs.setString(
        'nyang_feedback_prev_week',
        jsonEncode({'weekMonday': weekMonday, 'type': feedbackType}),
      );
      // 클라우드에도 올린다. 이 키는 클라우드와 동기화되는데 올려두지 않으면
      // 실시간 리스너가 옛 값으로 되돌리고, 그러면 기록탭에 들어갈 때마다
      // 한마디를 다시 만든다. 만드는 데 API를 쓰므로 그때마다 비용이 나간다.
      TasksSyncService.scheduleSyncToCloud();

      if (!mounted) return;
      setState(() {
        _weeklyFeedbackText = feedbackText;
      });
    } catch (e) {
      debugPrint('주간 코치 피드백 생성 실패: $e');
      if (!mounted) return;
      setState(() {
        _weeklyFeedbackText = _getMasterPatternFeedback(
          _getLast7Records(includeCurrentAppDate: false),
        );
      });
    } finally {
      _isGeneratingWeeklyFeedback = false;
    }
  }

  /// 하루 기록에 남은 할 일 한 건이 시작 버튼을 거쳤는지.
  /// 완료 도장만 보면 시작해서 붙잡고 있던 일이 기록에서 사라진다.
  static bool _taskWasStarted(Map map) =>
      map['startedAt'] != null || map['inProgress'] == true;

  Future<String> _buildWeeklyFeedbackPrompt(int feedbackType) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _getLast7Records(includeCurrentAppDate: false);
    final visibleVisions = _formatVisionText(prefs.getString('nyang_visions'));
    final hasVisibleVisions = visibleVisions != '없음';
    final weekGoalText = _formatGoalText(prefs.getString('nyang_week_goals'));
    final monthGoalText = _formatGoalText(prefs.getString('nyang_month_goals'));

    final allTaskTexts = <String>{};
    for (final record in records) {
      if (record['isVacation'] == true) continue;
      final tasks = (record['tasks'] as List?) ?? [];
      for (final task in tasks) {
        final text = (task as Map?)?['text']?.toString().trim();
        if (text != null && text.isNotEmpty) allTaskTexts.add(text);
      }
    }

    final resumedTasks = <String>[];
    final resumedStartTasks = <String>[];
    final consistentTasks = <String>[];
    final consistentStartTasks = <String>[];
    final heldOverDayCounts = <String, int>{};
    final activeRecords = records
        .where((record) => record['isVacation'] != true)
        .toList();

    /// 3일 이상 비어 있다가 다시 걸린 적이 있는지.
    bool resumedAfterGap(List<bool> status) {
      var gap = 0;
      var resumed = false;
      for (final hit in status) {
        if (!hit) {
          gap++;
        } else {
          if (gap >= 3) resumed = true;
          gap = 0;
        }
      }
      return resumed;
    }

    for (final text in allTaskTexts) {
      List<bool> statusOf(bool Function(Map map) test) {
        return activeRecords.map((record) {
          final tasks = (record['tasks'] as List?) ?? [];
          return tasks.any((task) {
            final map = task as Map?;
            if (map == null || map['text'] != text) return false;
            return test(map);
          });
        }).toList();
      }

      final dailyStatus = statusOf((map) => map['done'] == true);
      // 끝내지 못했어도 손을 댄 날. 완료만 세면 두 시간 붙잡고 있던 날이
      // 손도 안 댄 날과 똑같아진다.
      final dailyTouched = statusOf(
        (map) => map['done'] == true || _taskWasStarted(map),
      );
      final dailyCarried = statusOf(
        (map) => map['done'] != true && _taskWasStarted(map),
      );

      // 그 주의 주력은 손댄 날이 많으면서 하루에 안 끝난 일이다.
      // 손댄 날만 세면 3초짜리 습관이 매일 걸려서 1등을 차지한다.
      final touchedDays = dailyTouched.where((hit) => hit).length;
      if (touchedDays >= 2 && dailyCarried.any((hit) => hit)) {
        heldOverDayCounts[text] = touchedDays;
      }

      if (dailyStatus.length >= 7 &&
          dailyStatus[4] &&
          dailyStatus[5] &&
          dailyStatus[6]) {
        consistentTasks.add(text);
      } else if (dailyTouched.length >= 7 &&
          dailyTouched[4] &&
          dailyTouched[5] &&
          dailyTouched[6]) {
        consistentStartTasks.add(text);
      }

      final alreadyListed =
          consistentTasks.contains(text) || consistentStartTasks.contains(text);
      if (resumedAfterGap(dailyStatus) && !consistentTasks.contains(text)) {
        resumedTasks.add(text);
      } else if (resumedAfterGap(dailyTouched) && !alreadyListed) {
        resumedStartTasks.add(text);
      }
    }

    // 시작한 일이 끝까지 간 비율.
    //
    // 완료율과 재는 것이 다르다. 완료율은 계획한 것 중 몇 개를 끝냈는지라
    // 계획을 크게 세운 사람은 낮게 나오는데, 이 값은 손을 댄 것 중 몇 개가
    // 끝났는지다. 이게 높으면 그 사람의 문턱은 지속이 아니라 시작이고,
    // 다음 주에 필요한 것도 "덜 계획하기"가 아니라 "시작하는 자리 만들기"다.
    var startedTaskCount = 0;
    var startedThenDoneCount = 0;
    for (final text in allTaskTexts) {
      var touched = false;
      var finished = false;
      for (final record in activeRecords) {
        for (final task in (record['tasks'] as List?) ?? []) {
          final map = task as Map?;
          if (map == null || map['text'] != text) continue;
          if (map['done'] == true) finished = true;
          if (map['done'] == true || _taskWasStarted(map)) touched = true;
        }
      }
      if (!touched) continue;
      startedTaskCount++;
      if (finished) startedThenDoneCount++;
    }
    // 두세 개로는 사람의 패턴이라고 말할 수 없다. 그 아래는 숫자를 주지 않는다.
    final startToFinishText = startedTaskCount >= 4
        ? '손댄 일 $startedTaskCount개 중 $startedThenDoneCount개 완료 '
              '(${(startedThenDoneCount * 100 / startedTaskCount).round()}%)'
        : '표본이 적어 판단 보류';

    final heldOverRanked = heldOverDayCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final heldOverText = heldOverRanked
        .take(3)
        .map((e) => '${e.key}(${e.value}일)')
        .join(', ');

    final recordBuffer = StringBuffer();
    final completionSummaryBuffer = StringBuffer();
    final lowCompletionDays = <String>[];
    final partialCompletionDays = <String>[];
    final perfectCompletionDays = <String>[];
    var trackableDays = 0;
    var totalDoneCount = 0;
    var totalTaskCount = 0;

    for (final record in records) {
      if (record['isVacation'] == true) {
        recordBuffer.writeln(
          '- ${record['date']}: 휴무일(회복일)로 설정됨. 완료/미완료 평가에서 제외.',
        );
        continue;
      }

      final dateStr = record['date']?.toString() ?? '';
      final doneCount = _recordDoneCount(record);
      final taskCount = _recordTotalCount(record);
      final pct = taskCount == 0 ? 0 : ((doneCount / taskCount) * 100).round();
      if (taskCount > 0) {
        trackableDays++;
        totalDoneCount += doneCount;
        totalTaskCount += taskCount;
        if (doneCount == taskCount) {
          perfectCompletionDays.add('$dateStr($pct%)');
        } else {
          partialCompletionDays.add('$dateStr($pct%)');
          if (pct <= 40) lowCompletionDays.add('$dateStr($pct%)');
        }
      }

      final tasks = (record['tasks'] as List?) ?? [];
      final done = tasks
          .where((task) => (task as Map?)?['done'] == true)
          .map((task) => (task as Map)['text'].toString())
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      String undoneLabels({required bool started}) => tasks
          .where((task) {
            final map = task as Map?;
            if (map == null || map['done'] == true) return false;
            return _taskWasStarted(map) == started;
          })
          .map((task) {
            final map = task as Map;
            final isDeferred = map['deferred'] == true;
            return map['text'].toString() + (isDeferred ? ' (다른 날로 이월함)' : '');
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');

      // 미완료를 '하다 만 일'과 '손도 못 댄 일'로 나눈다. 한 덩어리로 주면
      // 종일 붙잡고 있던 일이 펼쳐보지도 않은 일과 같은 취급을 받는다.
      final startedUndone = undoneLabels(started: true);
      final untouched = undoneLabels(started: false);
      recordBuffer.writeln(
        '- ${record['date']}: 완료한 일[${done.isEmpty ? '없음' : done}], '
        '시작했지만 끝내지 못한 일[${startedUndone.isEmpty ? '없음' : startedUndone}], '
        '손대지 못한 일[${untouched.isEmpty ? '없음' : untouched}]',
      );
    }

    final weeklyPct = totalTaskCount == 0
        ? 0
        : ((totalDoneCount / totalTaskCount) * 100).round();
    final lowPlannerAttendance = trackableDays <= 3;
    final manyLowCompletionDays =
        trackableDays > 0 &&
        lowCompletionDays.length >= (trackableDays / 2).ceil();
    completionSummaryBuffer.writeln('- 평가 대상일: $trackableDays일');
    completionSummaryBuffer.writeln(
      '- 주간 전체 완료율: $weeklyPct% ($totalDoneCount/$totalTaskCount)',
    );
    completionSummaryBuffer.writeln(
      '- 100% 완료한 날: ${perfectCompletionDays.isEmpty ? '없음' : perfectCompletionDays.join(', ')}',
    );
    completionSummaryBuffer.writeln(
      '- 일부 미완료가 있던 날: ${partialCompletionDays.isEmpty ? '없음' : partialCompletionDays.join(', ')}',
    );
    completionSummaryBuffer.writeln(
      '- 저조한 완료율(40% 이하)인 날: ${lowCompletionDays.isEmpty ? '없음' : lowCompletionDays.join(', ')}',
    );
    completionSummaryBuffer.writeln(
      '- 저조한 날이 많은 주인가: ${manyLowCompletionDays ? '예' : '아니오'}',
    );
    completionSummaryBuffer.writeln(
      '- 플래너 기록일이 적은 주인가: ${lowPlannerAttendance ? '예' : '아니오'}',
    );

    final isMale = !_isMaster && widget.coachId == 'nyang_halbae';
    final title = _userTitle;

    final trackingHabits = _habits.where((h) => h.tracking == true).toList();
    final habitFreqBuffer = StringBuffer();
    if (trackingHabits.isEmpty) {
      habitFreqBuffer.writeln('설정된 루틴 없음');
    } else {
      const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
      for (final h in trackingHabits) {
        final freqLabel = h.freq == 'daily'
            ? '매일'
            : h.freq == 'weekly_count'
            ? '주 ${h.weeklyTargetCount ?? 5}일'
            : h.days.map((d) => dayNames[d]).join(', ');
        habitFreqBuffer.writeln('- ${h.name}: $freqLabel');
      }
    }

    // 장기 비전형 작성을 위한 마일스톤 상세 데이터
    List<VisionItem> visionItems = [];
    try {
      final visionsRaw = prefs.getString('nyang_visions');
      if (visionsRaw != null) {
        visionItems = (jsonDecode(visionsRaw) as List)
            .whereType<Map>()
            .map((e) => VisionItem.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (_) {}

    final visionEmptyGuidance = hasVisibleVisions
        ? '- 장기 비전은 이미 제공되어 있습니다. 절대 장기 비전이 비어 있다고 말하지 말고, 제공된 장기 비전 이름과 상세 데이터를 기준으로 회고하세요.'
        : '- 장기 비전이 비어 있다면, 장기 비전을 작성하면 매주 실행과 연결해 점검할 수 있다고 안내하세요.';

    DateTime? parseDotDate(String? s) {
      if (s == null || s.isEmpty) return null;
      final parts = s.split('.');
      if (parts.length != 3) return null;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    final weekStart =
        DateTime.tryParse(records.first['date']) ?? DateTime.now();
    final weekEnd = DateTime.tryParse(records.last['date']) ?? DateTime.now();
    final todayNormalized = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final completedThisWeekMilestones = <String>[];
    final recentlyUpdatedVisionNotes = <String>[];
    final overdueMilestones = <String>[];
    String? nearestUpcomingLabel;
    DateTime? nearestUpcomingDate;

    for (final v in visionItems) {
      final updatedAt = DateTime.tryParse(v.updatedAt);
      if (updatedAt != null &&
          !updatedAt.isBefore(weekStart) &&
          !updatedAt.isAfter(weekEnd.add(const Duration(days: 1)))) {
        final memoedMilestone = v.milestones.where(
          (m) =>
              (m.memo?.isNotEmpty ?? false) ||
              (m.memoSections?.isNotEmpty ?? false),
        );
        if (memoedMilestone.isNotEmpty) {
          recentlyUpdatedVisionNotes.add(
            '${v.name} - "${memoedMilestone.first.text}" 관련 메모 추가/수정됨',
          );
        } else {
          recentlyUpdatedVisionNotes.add('${v.name} 비전이 최근 업데이트됨');
        }
      }

      for (final m in v.milestones) {
        if (m.done) {
          final achieved = parseDotDate(m.achievedDate);
          if (achieved != null &&
              !achieved.isBefore(weekStart) &&
              !achieved.isAfter(weekEnd)) {
            completedThisWeekMilestones.add('${v.name} - ${m.text}');
          }
        } else {
          final deadline = (m.date?.isNotEmpty ?? false)
              ? DateTime.tryParse(m.date!)
              : null;
          if (deadline != null) {
            if (deadline.isBefore(todayNormalized)) {
              overdueMilestones.add('${v.name} - ${m.text} (마감: ${m.date})');
            } else if (nearestUpcomingDate == null ||
                deadline.isBefore(nearestUpcomingDate)) {
              nearestUpcomingDate = deadline;
              nearestUpcomingLabel = '${v.name} - ${m.text} (마감: ${m.date})';
            }
          }
        }
      }
    }

    // 지난 주 일일 대화 요약 (메모리 시스템 산출물). 저조한 주의 원인을
    // 추측이 아니라 실제 컨디션/고민 기록으로 해석하기 위한 근거로 쓴다.
    String chatSummarySection = '';
    final dsRaw = prefs.getString('nyang_daily_summaries');
    if (dsRaw != null) {
      try {
        final summaries = (jsonDecode(dsRaw) as List).whereType<Map>().where((
          s,
        ) {
          final d = DateTime.tryParse(s['date']?.toString() ?? '');
          return d != null && !d.isBefore(weekStart) && !d.isAfter(weekEnd);
        }).toList();
        if (summaries.isNotEmpty) {
          final buffer = StringBuffer('\n[지난 주 대화 기록 요약]\n');
          for (final s in summaries) {
            buffer.writeln(
              '- ${s['date']}: 컨디션(${s['condition'] ?? '-'}) / 고민(${s['concern'] ?? '-'}) / 감정(${s['emotion'] ?? '-'})',
            );
          }
          chatSummarySection = buffer.toString().trimRight();
        }
      } catch (_) {}
    }

    return '''당신은 사용자의 한 주간 성과를 분석하는 수석 비서이자 전문 코치입니다.
사용자의 오늘 전날까지 최근 7일간의 실제 할 일 완료 내역과 현재 설정된 목표/비전을 바탕으로, $title께 드리는 주간 코칭 한마디를 격식 있게 작성해 주세요.
오늘은 아직 진행 중인 하루이므로 오늘 완료율, 오늘 미완료, 오늘 아직 안 했다는 식의 평가는 절대 하지 마세요.

[사용자의 오늘 전날까지 최근 7일간 할 일 완료 현황]
$recordBuffer

[주간 완료율 요약]
${completionSummaryBuffer.toString().trim()}

[분석 참고 데이터]
- 꾸준히 해낸 일 (3일 이상 연속 완료): ${consistentTasks.join(', ').isEmpty ? '없음' : consistentTasks.join(', ')}
- 꾸준히 손댄 일 (완료까지는 아니어도 3일 이상 연속으로 시작): ${consistentStartTasks.join(', ').isEmpty ? '없음' : consistentStartTasks.join(', ')}
- 이번 주 주력한 일 (하루에 끝나지 않아 여러 날 붙잡은 일, 괄호는 손댄 날 수): ${heldOverText.isEmpty ? '없음' : heldOverText}
${feedbackType == 0 ? '- 시작한 일이 완료로 이어진 비율: $startToFinishText\n' : ''}
- 미루다 다시 완료한 일 (3일 이상 미루다 최근 다시 완료): ${resumedTasks.join(', ').isEmpty ? '없음' : resumedTasks.join(', ')}
- 미루다 다시 시작한 일 (3일 이상 손대지 못하다 최근 다시 시작, 완료는 아직): ${resumedStartTasks.join(', ').isEmpty ? '없음' : resumedStartTasks.join(', ')}

[사용자의 현재 목표 및 장기 비전]
- 주간 목표: $weekGoalText
- 월간 목표: $monthGoalText
- 장기 비전: $visibleVisions

[장기 비전 상세 데이터]
- 이번 주 완료된 마일스톤: ${completedThisWeekMilestones.isEmpty ? '없음' : completedThisWeekMilestones.join(', ')}
- 최근 새로 추가/수정된 장기비전 메모나 마일스톤: ${recentlyUpdatedVisionNotes.isEmpty ? '없음' : recentlyUpdatedVisionNotes.join(' / ')}
- 가장 가까운 마감 예정 마일스톤: ${nearestUpcomingLabel ?? '없음'}
- 마감일이 지난 미완료 마일스톤: ${overdueMilestones.isEmpty ? '없음' : overdueMilestones.join(', ')}

[현재 설정된 루틴 트래킹 빈도]
${habitFreqBuffer.toString().trim()}
$chatSummarySection

[회고 유형: ${feedbackType == 0
        ? '실행 회고형'
        : feedbackType == 1
        ? '장기 비전형'
        : '컨디션 회고형'}]

[작성 지침]
1. 어투: ${isMale ? '냥할배로서 부드럽고 느긋한 반말 기반 말투. 존댓말과 냥 말투를 섞지 말고, "$title" 호칭도 남발하지 마세요.' : '여비서로서 지적이고 부드러운 "$title" 호칭의 격식체 (~했어요, ~어떨까요).'}
2. 공통 원칙:
   - 휴무일(회복일)은 미완료나 실패로 해석하지 말고, 필요한 회복을 일정에 포함한 것으로 자연스럽게 존중해 주세요.
   - "시작했지만 끝내지 못한 일"과 "손대지 못한 일"을 한데 묶어 미완료로 말하지 마세요. 시작한 일은 아무것도 하지 않은 일이 아닙니다.
   - [현재 설정된 루틴 트래킹 빈도]를 반드시 참고하세요. 특정 요일에만 하기로 한 루틴이라면 그 빈도에 맞게 평가해 주세요.
   - [주간 완료율 요약]의 수치를 우선 기준으로 삼으세요. 100% 완료한 날이 대부분이고 저조한 날이 하루뿐이면 "계획대로 진행되지 않은 날이 많았다", "저조한 날이 많았다", "대부분 미완료였다" 같은 복수/다수 표현을 절대 쓰지 마세요.
   - 플래너 기록일이 적은 주(플래너 기록일이 적은 주인가: 예)에는 완료율을 강하게 평가하지 말고, 먼저 플래너로 돌아오는 리듬을 부드럽게 제안하세요.
   - 완료율이 저조한 주(저조한 날이 많은 주인가: 예)에는 원인을 추측으로 단정하지 말고, [지난 주 대화 기록 요약]이 있다면 거기 나타난 컨디션과 고민을 근거로 원인을 해석해 주세요. 요약에 없는 사정을 지어내지 마세요.
3. 유형별 작성 방식:
${feedbackType == 0
        ? '''   [실행 회고형]
   - 사용자가 실제로 무엇을 했고, 무엇을 미뤘으며, 무엇이 개선되었는지를 중심으로 회고합니다.
   - 목표/비전과 연결되는 중요한 활동 1~2개를 콕 집어 구체적으로 칭찬하세요. (추상적 칭찬 금지) 후보는 [이번 주 주력한 일]과 완료한 일 양쪽에서 고르세요.
   - 여러 날 붙잡은 일은 끝내지 못했어도 그 주의 주력으로 인정하고, 끝낸 일은 끝낸 것으로 칭찬하세요. (예: "이번 주는 보고서에 나흘을 쓰셨네요." / "수요일에 보고서를 끝내셨네요.")
   - 미루다 다시 완료한 일이나 다시 시작한 일이 있다면 특별히 언급해 주세요. 완료까지 가지 못했어도 다시 손을 댄 것 자체를 인정해 주세요.
   - '시작한 일이 완료로 이어진 비율'이 7할을 넘으면, 완료율이 낮은 주라도 그 사람은 일단 손을 대면 끝내는 사람입니다. 그 점을 이번 주의 강점으로 짚고, 다음 주 제안은 계획을 줄이는 쪽보다 시작하는 자리를 만드는 쪽으로 하세요. (예: 첫 10분만 정해두기, 시작 시각을 미리 잡아두기)
   - 다시 시작은 했는데 완료 기록이 적다면, 의지나 성실함의 문제로 읽지 말고 하루에 실행 가능한 크기로 계획을 나누자고 제안해 주세요.
   - 반복적으로 밀린 중요한 일이 있다면 부드럽게 지적하고 다음 주 우선순위로 권유하세요. 단, 시작 기록이 있는 일은 밀린 일로 지적하지 마세요. 손을 댄 일은 진행 중인 일입니다.
   - 단, [주간 완료율 요약]에서 "저조한 날이 많은 주인가: 예"인 경우에만 밀린 항목을 나열하거나 지적하지 말고 이 구조로 쓰세요: 수고 인정 → 원인 해석([지난 주 대화 기록 요약]이 있으면 그 근거로, 없으면 계획이 컨디션보다 컸을 가능성으로) → 다음 주에는 확실히 해낼 수 있는 만큼만 계획하자는 제안.
   - 플래너 기록일이 적은 주라면 아래 구조를 따르세요: "이번 주는 완료율보다 플래너에 다시 돌아오는 리듬을 먼저 잡는 것이 좋아 보입니다. 기록이 적었던 만큼 성과를 크게 판단하기는 어렵겠습니다. 해야 할 일이 있는데 하기 싫을 때는 냥냥코치를 기억해 주세요. 하기 싫은 마음까지 달래드리겠습니다." 성과 판단 보류 문장과 냥냥코치 안내 문장은 반드시 서로 다른 문장으로 분리하세요. "판단하기보다는, 냥냥코치를..."처럼 하나의 비교 문장으로 연결하지 마세요.
   - 저조한 날이 하루뿐이면 전체 주간은 긍정적으로 평가하고, 해당 날짜만 "토요일 하루 완료율이 낮았습니다"처럼 단수로 정확히 언급하세요.'''
        : feedbackType == 1
        ? '''   [장기 비전형]
   - 현재 장기 비전과 마일스톤을 중심으로 회고합니다. [장기 비전 상세 데이터]를 반드시 참고하세요.
   - 이번 주 완료된 마일스톤이 있다면 구체적으로 언급하며 칭찬하세요.
   - 최근 새로 추가/수정된 장기비전 메모나 마일스톤이 있다면, 미래를 준비하고 있다는 점을 자연스럽게 언급하세요. (예: "최근에는 '앱 출시 준비' 관련 메모도 추가했네요. 실행뿐 아니라 방향까지 구상하시는 점이 인상적입니다.")
   - 가장 가까운 마감 예정 마일스톤이 있다면 다음 준비 대상으로 안내하세요.
   - 마감일이 지난 미완료 마일스톤이 있다면 부드럽게 확인을 권유하세요.
   $visionEmptyGuidance
   - 마지막으로 미래를 응원하는 한마디로 마무리하세요.'''
        : '''   [컨디션 회고형]
   - 실행이나 성장보다 이번 주의 컨디션 흐름에 초점을 맞춥니다.
   - 완료율, 휴무일 패턴, 할 일 밀도 등을 바탕으로 체력/휴식/회복 측면을 분석하세요.
   - 무리한 주였는지, 잘 쉰 주였는지, 회복이 더 필요한지를 부드럽게 짚어주세요.
   - 꾸준히 해낸 일이나 꾸준히 손댄 일이 있다면 컨디션 속에서도 놓치지 않았다는 점을 자연스럽게 언급해 주세요. 완료까지 가지 못했더라도 시작한 것은 그대로 인정해 주세요.
   - 다음 주 컨디션 관리를 위한 한 가지 제안으로 마무리하세요.'''}
4. 분량: 3~4문장으로 간결하게. JSON이나 마크다운 없이 순수 텍스트로만 답변해 주세요.
5. 가독성: 문장 앞에 접속어가 올 때는 그 접속어 앞에서 한 줄을 비우고, 들여쓰기 없이 문단을 시작해 주세요. 예: "또한,", "특히,", "다만,", "하지만,", "그리고,", "앞으로,".''';
  }

  String _formatCoachCommentForDisplay(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final connectorPattern = RegExp(
      r'\s+(특히|또한|다만|하지만|그러나|그리고|그래서|따라서|그러므로|한편|반면|더불어|아울러|앞으로|다음으로),',
    );

    final formatted = trimmed
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAllMapped(connectorPattern, (match) => '\n\n${match.group(1)},')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    // 첫 인사말("소연님," 등)과 본문 사이의 줄바꿈을 없애 한 문장처럼 붙인다.
    return formatted.replaceFirstMapped(
      RegExp(r'^([가-힣]{1,12}(?:님|께),)\s*\n+\s*'),
      (m) => '${m.group(1)} ',
    );
  }

  String _formatGoalText(String? raw) {
    if (raw == null) return '없음';
    try {
      final decoded = jsonDecode(raw) as List;
      final text = decoded
          .map((goal) {
            final map = goal as Map;
            final status = map['done'] == true ? '완료' : '진행중';
            return '[$status] ${map['text'] ?? ''}';
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      return text.isEmpty ? '없음' : text;
    } catch (_) {
      return '없음';
    }
  }

  String _formatVisionText(String? raw) {
    if (raw == null) return '없음';
    try {
      final decoded = jsonDecode(raw) as List;
      final text = decoded
          .map((vision) {
            final map = vision as Map;
            // VisionItem은 비전 제목을 'name'에 저장한다. ('text'는 과거 호환용)
            final name = (map['name'] ?? map['text'] ?? '').toString().trim();
            final desc = (map['desc'] ?? '').toString().trim();
            if (name.isEmpty) return '';
            return desc.isEmpty ? name : '$name ($desc)';
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      return text.isEmpty ? '없음' : text;
    } catch (_) {
      return '없음';
    }
  }

  String _getDayLabel(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return days[dt.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final records = _getLast7Records();
    int successDays = 0;
    int streak = 0;
    final vacationDays = records.where((r) => r['isVacation'] == true).length;
    final trackableDays = records.length - vacationDays;
    for (final r in records) {
      if (r['isVacation'] == true) continue;
      if (_recordDoneCount(r) > 0) {
        successDays++;
      }
    }
    // 휴무일은 연속 기록을 끊지 않고 건너뜁니다.
    for (int i = records.length - 1; i >= 0; i--) {
      if (records[i]['isVacation'] == true) continue;
      if (_recordDoneCount(records[i]) > 0) {
        streak++;
      } else {
        // 오늘은 아직 끝나지 않은 하루다. 아침에 연 사람에게 어제까지 쌓은
        // 숫자를 0으로 되돌려 보여주면, 하루가 시작도 하기 전에 기운이 빠진다.
        // 오늘이 그대로 지나가면 자정 뒤에 어제로서 끊긴다.
        if (i == records.length - 1) continue;
        break;
      }
    }
    final flowPct = trackableDays == 0
        ? 100
        : ((successDays / trackableDays) * 100).round();

    return Container(
      color: _isMaster ? Colors.transparent : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bar_chart_rounded,
                        size: 22,
                        color: Color(0xFF3D3A4E),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        // 여기 숫자들은 최근 7일만 본다. 그냥 "나의 기록"이면
                        // 시작부터 쌓인 값으로 읽혀서, 연속이 7에서 안 올라가는
                        // 것이 고장처럼 보인다.
                        '이번 주 기록',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    _isMaster ? '최근 30일 ▾' : '최근 7일 ▾',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ),
            // 스크롤 영역
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    // 4칸 통계 요약 (패턴 써머리) -> 2칸으로 축소됨
                    _buildSummaryGrid(
                      successDays,
                      flowPct,
                      streak,
                      vacationDays,
                    ),
                    const SizedBox(height: 4),

                    // 코치의 한마디
                    _buildCoachCommentCard(records),
                    const SizedBox(height: 20),

                    // 이번 주 기록 (차트)
                    _buildWeeklyChartCard(records),
                    const SizedBox(height: 20),

                    // 습관 트래킹
                    _buildHabitTrackingCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(
    int successDays,
    int flowPct,
    int streak,
    int restDays,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      children: [
        _summaryCard(
          // 들어온 날이 아니라 할 일을 하나라도 끝낸 날을 센다. "출석"이라고
          // 하면 매일 들어오는 사람이 0을 보고 고장인 줄 안다.
          '연속 달성',
          '$streak일',
          '최고 -일',
          Icons.local_fire_department_outlined,
          _recordCoach.accentColor,
          true,
        ),
        _summaryCard(
          '쉬는 날',
          '$restDays일',
          '-',
          Icons.bedtime_outlined,
          const Color(0xFF6EBF8B),
          false,
        ),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    String sub,
    IconData icon,
    Color color,
    bool isAccent,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAccent ? color : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isAccent ? color : const Color(0xFFE8E3F8)),
        boxShadow: isAccent
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: isAccent ? Colors.white : color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.notoSansKr(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isAccent ? Colors.white : const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isAccent
                      ? Colors.white.withValues(alpha: 0.9)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPatternFeedback(List<Map<String, dynamic>> records) {
    final activeRecords = records
        .where((r) => r['isVacation'] != true)
        .toList();
    final vacationCount = records.length - activeRecords.length;
    if (activeRecords.isEmpty) {
      return vacationCount > 0
          ? '이번 주는 쉬어가는 흐름이야. 잘 쉬는 것도 루틴을 오래 가져가는 방법이야.'
          : '아직 기록이 부족해. 오늘 하나만 완료하면 패턴이 시작돼.';
    }

    int total = 0;
    int successDays = 0;
    int zeros = 0;
    Map<String, dynamic> best = activeRecords[0];
    double bestRate = -1;

    for (var r in activeRecords) {
      final int count = _recordDoneCount(r);
      final int recordTotal = _recordTotalCount(r);
      total += count;
      if (count > 0) successDays++;
      if (count == 0) zeros++;
      if (recordTotal > 0) {
        final double rate = count / recordTotal;
        if (rate > bestRate) {
          bestRate = rate;
          best = r;
        }
      }
    }

    if (total == 0) {
      return vacationCount > 0
          ? '휴무일은 잘 쉬어가고 있어. 다시 시작하는 날엔 오늘 하나만 잡아도 충분해.'
          : '아직 기록이 부족해. 오늘 하나만 완료하면 패턴이 시작돼.';
    }

    final bestDay = _getDayLabel(best['date'] ?? '');

    if (successDays >= 5) {
      return '이번 주 $successDays일 성공. 흐름이 꽤 안정적이야. 특히 $bestDay요일에 강해.';
    }
    if (zeros >= 3) {
      return '끊긴 날이 조금 보여. 지금은 큰 계획보다 하루 1개 완료를 기준으로 잡는 게 좋아.';
    }
    return '$bestDay요일에 제일 잘했어. 그 시간대나 환경을 다시 써먹으면 좋아.';
  }

  /// 마스터 한마디를 API로 못 받았을 때 대신 내보내는 문장.
  /// 마스터일 때만 불리고 화면도 마스터일 때만 그리므로 여비서 존댓말 하나면 된다.
  String _getMasterPatternFeedback(List<Map<String, dynamic>> records) {
    final activeRecords = records
        .where((r) => r['isVacation'] != true)
        .toList();
    final vacationCount = records.length - activeRecords.length;
    int total = 0;
    int successDays = 0;
    int totalTaskCount = 0;
    for (var r in activeRecords) {
      final int doneCount = _recordDoneCount(r);
      final int totCount = _recordTotalCount(r);
      total += doneCount;
      totalTaskCount += totCount;
      if (doneCount > 0) successDays++;
    }

    if (total == 0) {
      final feedback = vacationCount > 0
          ? '이번 주에는 회복을 선택하신 날이 있어요. 잘 쉬는 것도 일정 관리의 일부예요, 대표님.'
          : '아직 이번 주 기록이 없어요. 오늘 하나만 시작해보는 건 어떨까요, 대표님?';
      return feedback.replaceAll(UserTitleService.defaultTitle, _userTitle);
    }

    List<String> parts = [];
    if (successDays >= 5) {
      parts.add('이번 주도 열심히 달리신 한 주였어요, 대표님!');
    } else {
      parts.add('장기 목표를 설정해두시면 더 잘 챙겨드릴 수 있어요!');
    }

    bool isOverloaded = totalTaskCount >= 35;
    if (isOverloaded && successDays >= 4) {
      parts.add('이번 주 할 일이 많으셨는데도 잘 해내셨어요. 다음 주엔 체력 관리도 함께 챙겨주세요.');
    }

    return parts
        .join(' ')
        .replaceAll(UserTitleService.defaultTitle, _userTitle);
  }

  Widget _buildCoachCommentCard(List<Map<String, dynamic>> records) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: AssetImage(
              _isMaster
                  ? 'assets/images/sec_female.png'
                  : 'assets/images/${widget.coachId}.png',
            ),
            backgroundColor: const Color(0xFFF3F0FF),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '코치의 한마디',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _recordCoach.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isMaster
                      ? _formatCoachCommentForDisplay(
                          _weeklyFeedbackText ??
                              '이번 주 활동과 목표를 분석하여 $_userTitle께 드릴 한마디를 작성하고 있습니다. 약 5초 정도만 잠시 기다려주십시오...',
                        )
                      : _getPatternFeedback(records),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3D3A4E),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChartCard(List<Map<String, dynamic>> records) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/chart-simple.svg',
                width: 17,
                height: 17,
                colorFilter: ColorFilter.mode(
                  _recordCoach.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                // 바깥 화면 제목이 이미 '이번 주 기록'이다. 같은 이름을 안에서
                // 또 쓰면 어디를 보고 있는지 흐려진다.
                '종합 기록',
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: records.map((r) {
              final isVacation = r['isVacation'] == true;
              final doneCount = _recordDoneCount(r);
              final touchedCount = _recordTouchedCount(r);
              final totalCount = _recordTotalCount(r);
              final pct = totalCount > 0
                  ? ((doneCount / totalCount) * 100).round()
                  : 0;
              final touchedPct = totalCount > 0
                  ? ((touchedCount / totalCount) * 100).round()
                  : 0;
              final isToday =
                  r['date'] ==
                  "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

              return Column(
                children: [
                  Text(
                    isVacation ? '쉼' : (pct > 0 ? '$pct%' : '-'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isVacation
                          ? const Color(0xFF6EBF8B)
                          : const Color(0xFFA0A0B0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isVacation
                          ? const Color(0xFFEAF7EF)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.bottomCenter,
                    // 두 층으로 쌓는다. 뒤에 연한 층이 손댄 비율, 앞의 진한 층이
                    // 완료율. 둘의 간격이 곧 붙잡고 있었지만 못 끝낸 몫이다.
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        if (!isVacation && touchedPct > pct)
                          Container(
                            width: 24,
                            height: 100.0 * (touchedPct / 100.0),
                            decoration: BoxDecoration(
                              color: _recordCoach.accentColor.withValues(
                                alpha: 0.32,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        Container(
                          width: 24,
                          height: isVacation ? 100 : 100.0 * (pct / 100.0),
                          decoration: BoxDecoration(
                            color: isVacation
                                ? const Color(0xFF6EBF8B)
                                : _recordCoach.accentColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getDayLabel(r['date']),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isVacation
                          ? const Color(0xFF6EBF8B)
                          : isToday
                          ? _recordCoach.accentColor
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          if (records.any(
            (r) =>
                r['isVacation'] != true &&
                _recordTouchedCount(r) > _recordDoneCount(r),
          )) ...[
            const SizedBox(height: 10),
            _buildChartLegend(),
          ],
          const SizedBox(height: 16),
          _buildWeeklyCompanionSummary(),
          const SizedBox(height: 10),
          _buildStartPatternSummary(),
        ],
      ),
    );
  }

  /// 막대 두 층이 뭘 뜻하는지 한 줄로. 손댄 층이 보이는 주에만 붙인다.
  Widget _buildChartLegend() {
    Widget swatch(Color color) => Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );

    final labelStyle = GoogleFonts.notoSansKr(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: const Color(0xFF8B8698),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        swatch(_recordCoach.accentColor.withValues(alpha: 0.32)),
        const SizedBox(width: 5),
        Text('손댐', style: labelStyle),
        const SizedBox(width: 14),
        swatch(_recordCoach.accentColor),
        const SizedBox(width: 5),
        Text('완료', style: labelStyle),
      ],
    );
  }

  /// 하루를 언제 시작했을 때 그날이 잘 풀렸는지.
  ///
  /// 위 차트가 "어느 날 잘했나"라면 이건 "몇 시에 시작한 날 잘했나"다.
  /// 프렌즈와 마스터 모두에게 보여준다.
  Widget _buildStartPatternSummary() {
    // 30일치까지 본다. 며칠 안 쌓였을 때 단정하지 않는 건 서비스가 판단한다.
    final recent = _history.length > 30
        ? _history.sublist(_history.length - 30)
        : _history;
    final pattern = StartPatternService.analyze(recent);
    final isEstablished =
        pattern.confidence == StartPatternConfidence.established;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeeklyCompanionHeader(
            iconPath: 'assets/icons/fa-hourglass-start-solid.svg',
            // "시작시간"만 적으면 어떤 일의 시작인지 헷갈린다. 이건 그날 첫
            // 일과를 언제 잡았느냐이지, 특정 할 일 얘기가 아니다.
            label: isEstablished ? '내 첫 시작 패턴' : '내게 좋은 첫 시작시간',
          ),
          const SizedBox(height: 8),
          if (!pattern.hasResult)
            Text(
              '조금 더 기록하면 하루가 잘 풀리는 시작 시간대를 알려드릴게요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF8A8A9E),
                height: 1.5,
              ),
            )
          else ...[
            Text(
              pattern.window!.label,
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _recordCoach.accentColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isEstablished
                  ? "이 시간에 첫 할 일을 '시작'한 날 완료율이 가장 높네요."
                  : "지금까지는 이 시간에 첫 할 일을 '시작'한 날 완료율이 높았어요.",
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF8A8A9E),
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyCompanionSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWeeklyCompanionHeader(
            iconPath: 'assets/icons/fa-heart-solid.svg',
            label: '이번 주 애착 코치',
          ),
          const SizedBox(height: 8),
          _buildFavoriteCoachRanks(),
          if (_weeklyCompletedResistanceCount > 0) ...[
            const SizedBox(height: 12),
            _buildWeeklyCompanionHeader(
              iconPath: 'assets/icons/fa-handshake-solid.svg',
              label: '귀찮았지만 함께 완료한 일',
              value: '$_weeklyCompletedResistanceCount회',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeeklyCompanionHeader({
    required String iconPath,
    required String label,
    String? value,
  }) {
    return Row(
      children: [
        SvgPicture.asset(
          iconPath,
          width: 14,
          height: 14,
          colorFilter: ColorFilter.mode(
            _recordCoach.accentColor,
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF7A748E),
            ),
          ),
        ),
        if (value != null) ...[
          const SizedBox(width: 10),
          Text(
            value,
            textAlign: TextAlign.right,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: _recordCoach.accentColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFavoriteCoachRanks() {
    if (_weeklyFavoriteCoachRanks.isEmpty) {
      // "아직 없음"은 사용자가 뭘 안 한 것처럼 읽힌다. 실제로는 앱이 아직
      // 셀 만큼 못 모은 것이다.
      //
      // 코치 이름이 들어갈 자리라 원래는 굵고 컸는데, 안내 문장이 들어오면
      // 바로 위 제목보다 커져서 위계가 뒤집힌다. 이 경우만 본문 크기로 쓴다.
      return Text(
        '아직 정보가 부족합니다',
        style: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: const Color(0xFF9A94AA),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: _weeklyFavoriteCoachRanks.map(_buildFavoriteCoachChip).toList(),
    );
  }

  Widget _buildFavoriteCoachChip(_WeeklyCoachRank coachRank) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5DFF8)),
      ),
      child: Text(
        '${coachRank.rank}위 ${coachRank.coachName}',
        style: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF5E5576),
        ),
      ),
    );
  }

  Widget _buildHabitTrackingCard() {
    final trackingHabits = _habits.where((h) => h.tracking == true).toList();
    if (trackingHabits.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/icons/seedling.svg',
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(
                      _recordCoach.accentColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '루틴 트래킹',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                ],
              ),
              Text(
                _isMaster ? '최근 30일' : '최근 7일',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFA0A0B0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...trackingHabits.map((h) {
            // 임시로 달성률 계산 (habitLogs 사용)
            final days = _isMaster ? 30 : 7;
            double hSuccess = 0;
            int hTotal = 0;
            final logs = _habitLogs[h.id.toString()] ?? {};

            final now = DateTime.now();
            DateTime? createdAtDate;
            try {
              final parsed = DateTime.parse(h.createdAt);
              createdAtDate = DateTime(parsed.year, parsed.month, parsed.day);
            } catch (_) {}

            DateTime periodEnd = DateTime(now.year, now.month, now.day);
            DateTime periodStart = now.subtract(Duration(days: days - 1));
            periodStart = DateTime(
              periodStart.year,
              periodStart.month,
              periodStart.day,
            );

            if (createdAtDate != null && periodStart.isBefore(createdAtDate)) {
              periodStart = createdAtDate;
            }

            String dateKey(DateTime d) {
              return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
            }

            DateTime weekStartOf(DateTime d) {
              final normalized = DateTime(d.year, d.month, d.day);
              return normalized.subtract(
                Duration(days: normalized.weekday - 1),
              );
            }

            double logCompletionRatio(dynamic log) {
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

            String formatYYMMDD(DateTime d) {
              return '${d.year.toString().substring(2)}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
            }

            String formatMMDD(DateTime d) {
              return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
            }

            String periodText;
            if (periodStart.year == periodEnd.year) {
              periodText =
                  '${formatYYMMDD(periodStart)}~${formatMMDD(periodEnd)}';
            } else {
              periodText =
                  '${formatYYMMDD(periodStart)}~${formatYYMMDD(periodEnd)}';
            }

            if (h.freq == 'weekly_count') {
              final rawTarget = h.weeklyTargetCount ?? 5;
              final target = rawTarget < 1
                  ? 1
                  : (rawTarget > 7 ? 7 : rawTarget);
              final weekTotals = <String, int>{};
              final weekSuccesses = <String, double>{};

              for (
                var cursor = periodStart;
                !cursor.isAfter(periodEnd);
                cursor = cursor.add(const Duration(days: 1))
              ) {
                final weekKey = dateKey(weekStartOf(cursor));
                weekTotals[weekKey] = (weekTotals[weekKey] ?? 0) + 1;
                weekSuccesses[weekKey] =
                    (weekSuccesses[weekKey] ?? 0) +
                    logCompletionRatio(logs[dateKey(cursor)]);
              }

              for (final entry in weekTotals.entries) {
                final weekTarget = entry.value < target ? entry.value : target;
                final weekDone = weekSuccesses[entry.key] ?? 0;
                hTotal += weekTarget;
                hSuccess += weekDone > weekTarget ? weekTarget : weekDone;
              }
            } else {
              for (int i = 0; i < days; i++) {
                final d = now.subtract(Duration(days: i));
                final dNormalized = DateTime(d.year, d.month, d.day);

                // 생성일 이전은 카운트 제외
                if (createdAtDate != null &&
                    dNormalized.isBefore(createdAtDate)) {
                  continue;
                }

                // 요일 체크 (주간 반복일 경우 지정된 요일만 카운트)
                if (h.freq == 'weekly' && h.days.isNotEmpty) {
                  if (!h.days.contains(d.weekday - 1)) {
                    continue;
                  }
                }

                hTotal++;
                hSuccess += logCompletionRatio(logs[dateKey(d)]);
              }
            }
            final hPct = hTotal == 0 ? 0 : ((hSuccess / hTotal) * 100).round();

            const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
            final freqLabel = h.freq == 'daily'
                ? '매일'
                : h.freq == 'weekly_count'
                ? '주 ${h.weeklyTargetCount ?? 5}일'
                : h.days.map((d) => dayNames[d]).join('/');

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                h.name,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3D3A4E),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                freqLabel,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$hPct%',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _recordCoach.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hPct / 100.0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFF3F4F6),
                      valueColor: AlwaysStoppedAnimation(
                        _recordCoach.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '(트래킹 기간 : $periodText)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFA0A0B0),
                        ),
                      ),
                    ],
                  ),
                  if (_isMaster) ...[
                    const SizedBox(height: 12),
                    _buildHabitPattern(h),
                  ],
                ],
              ),
            );
          }),
          if (!_isMaster) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SvgPicture.asset(
                    'assets/icons/crown.svg',
                    width: 11,
                    height: 11,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF8B7CFF),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '마스터 코치 기록탭에서는 30일치 루틴 달성률과 루틴 달성 패턴까지 확인할 수 있습니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHabitPattern(HabitItem h) {
    final logs = _habitLogs[h.id.toString()] ?? {};
    final validLogs = <Map<String, dynamic>>[];

    DateTime? createdAtDate;
    try {
      final parsed = DateTime.parse(h.createdAt);
      createdAtDate = DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {}

    final now = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final d = now.subtract(Duration(days: i));
      final dNormalized = DateTime(d.year, d.month, d.day);

      if (createdAtDate != null && dNormalized.isBefore(createdAtDate)) {
        continue;
      }
      final dateStr =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

      final log = logs[dateStr];
      if (log != null && log['done'] == true && log['completedAt'] != null) {
        validLogs.add({
          'dateStr': dateStr,
          'completedAt': log['completedAt'],
          // 예전 기록은 진행중 시작 시각이 없으니 완료 시각으로 대체
          'startedAt': log['startedAt'] ?? log['completedAt'],
        });
      }
    }

    if (validLogs.length < 3) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '아직은 분석할 기록이 조금 부족해요.\n조금만 더 이어가면 루틴 패턴을 찾아드릴게요.',
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B7280),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final timeCounts = <int, int>{};
    final dayCounts = <int, int>{};
    final priorTaskCounts = <String, int>{};

    for (final log in validLogs) {
      try {
        final dt = DateTime.parse(log['completedAt']);
        // Time slot (2-hour windows) - 완료로 이어진 "진행중 시작" 시각 기준
        final startDt = DateTime.parse(log['startedAt']);
        final slot = startDt.hour ~/ 2;
        timeCounts[slot] = (timeCounts[slot] ?? 0) + 1;

        // Weekday (1=Mon..7=Sun)
        dayCounts[dt.weekday] = (dayCounts[dt.weekday] ?? 0) + 1;

        // Prior task
        final dateStr = log['dateStr'];
        final dayHistory = _history.where((r) => r['date'] == dateStr).toList();
        if (dayHistory.isNotEmpty) {
          final tasks = (dayHistory.last['tasks'] as List?) ?? [];
          final completedTasks = tasks
              .where((t) {
                if (t is! Map) return false;
                if (t['done'] != true || t['completedAt'] == null) return false;
                if (t['text'] == h.name) return false;
                return true;
              })
              .map((t) => t as Map<String, dynamic>)
              .toList();

          completedTasks.sort((a, b) {
            final ta = DateTime.parse(a['completedAt']);
            final tb = DateTime.parse(b['completedAt']);
            return ta.compareTo(tb);
          });

          for (int j = completedTasks.length - 1; j >= 0; j--) {
            final taskTime = DateTime.parse(completedTasks[j]['completedAt']);
            if (taskTime.isBefore(dt)) {
              // 가장 직전에 완료한 단 1개의 할 일만 확인
              if (dt.difference(taskTime).inMinutes <= 180) {
                final text = completedTasks[j]['text'].toString();
                priorTaskCounts[text] = (priorTaskCounts[text] ?? 0) + 1;
              }
              break; // 3시간 이내든 아니든 직전 1개만 보고 루프 종료
            }
          }
        }
      } catch (_) {}
    }

    // Top time
    int bestSlot = 0;
    int maxSlotCount = -1;
    timeCounts.forEach((slot, count) {
      if (count > maxSlotCount) {
        maxSlotCount = count;
        bestSlot = slot;
      }
    });

    final slotNames = {
      0: '밤 12시~2시',
      1: '새벽 2시~4시',
      2: '새벽 4시~6시',
      3: '아침 6시~8시',
      4: '오전 8시~10시',
      5: '오전 10시~12시',
      6: '낮 12시~2시',
      7: '오후 2시~4시',
      8: '오후 4시~6시',
      9: '저녁 6시~8시',
      10: '밤 8시~10시',
      11: '밤 10시~12시',
    };
    final bestTimeStr = slotNames[bestSlot] ?? '알 수 없음';

    // Top days
    int maxDayCount = -1;
    dayCounts.forEach((day, count) {
      if (count > maxDayCount) maxDayCount = count;
    });
    final bestDays = dayCounts.entries
        .where((e) => e.value == maxDayCount)
        .map((e) => e.key)
        .toList();
    bestDays.sort();

    final dayNames = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    String bestDayStr = bestDays.map((d) => dayNames[d]!).join(' · ');
    if (bestDays.length == 2 && bestDays.contains(6) && bestDays.contains(7)) {
      bestDayStr = '주말';
    } else if (bestDays.length == 5 &&
        !bestDays.contains(6) &&
        !bestDays.contains(7)) {
      bestDayStr = '평일';
    } else if (bestDays.length == 7) {
      bestDayStr = '매일';
    } else {
      bestDayStr += '요일';
    }

    // Top prior task
    String? bestPriorTask;
    if (validLogs.length >= 5) {
      int maxPriorCount = -1;
      priorTaskCounts.forEach((text, count) {
        if (count >= 2 && count > maxPriorCount) {
          maxPriorCount = count;
          bestPriorTask = text;
        }
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/seedling.svg',
                width: 14,
                height: 14,
                colorFilter: ColorFilter.mode(
                  _recordCoach.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '루틴 패턴',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _patternRow(
            'assets/icons/fa-clock-regular.svg',
            '성공 시작 시간',
            bestTimeStr,
            iconColor: const Color(0xFF63C7B2),
          ),
          const SizedBox(height: 6),
          _patternRow(
            'assets/icons/calendar-week.svg',
            '주로 완료한 요일',
            bestDayStr,
            iconColor: const Color(0xFF63C7B2),
          ),
          if (bestPriorTask != null) ...[
            const SizedBox(height: 6),
            _patternRow(
              'assets/icons/fa-arrow-rotate-left-solid.svg',
              '루틴 전에 자주 한 일',
              bestPriorTask!,
              iconColor: const Color(0xFF9CA3AF),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SvgPicture.asset(
                  'assets/icons/fa-lightbulb-solid.svg',
                  width: 14,
                  height: 14,
                  colorFilter: ColorFilter.mode(
                    const Color(0xFFF2B84B),
                    BlendMode.srcIn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '최근에는 $bestDayStr $bestTimeStr에 시작했을 때 완료로 가장 잘 이어졌어요.\n비슷한 시간에 시작해보세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4B5563),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patternRow(
    String iconPath,
    String label,
    String value, {
    required Color iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 14,
          height: 18,
          child: Align(
            alignment: Alignment.center,
            child: SvgPicture.asset(
              iconPath,
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF3D3A4E),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}

class _WeeklyCoachRank {
  final int rank;
  final String coachName;

  const _WeeklyCoachRank({required this.rank, required this.coachName});
}
