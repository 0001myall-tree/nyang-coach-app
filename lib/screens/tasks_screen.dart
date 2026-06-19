import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'coach_config.dart';
import '../services/memory_service.dart';
import '../models/user_data.dart';
import '../services/notification_service.dart';
import '../services/tasks_sync_service.dart';
import '../services/user_title_service.dart';
import '../services/analytics_service.dart';
import '../services/api_usage_limit_service.dart';
import '../services/widget_sync_service.dart';

// ─────────────────────────────────────────────────────────────
// 데이터 모델 (웹앱 그대로)
// ─────────────────────────────────────────────────────────────
class TaskItem {
  final dynamic id; // int or String (habit_xxx)
  String text;
  String category; // 'today' | 'habit'
  bool done;
  String? habitId;
  bool isHabit;
  String? time;
  String? duration;
  String? timeStart;
  String? timeEnd;
  String createdAt;
  String? completedAt;
  bool isReminderEnabled;
  int? achievedCount;
  int? achievedDuration;
  int deferredCount;

  TaskItem({
    required this.id,
    required this.text,
    required this.category,
    this.done = false,
    this.habitId,
    this.isHabit = false,
    this.time,
    this.duration,
    this.timeStart,
    this.timeEnd,
    required this.createdAt,
    this.isReminderEnabled = true,
    this.completedAt,
    this.deferredCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category,
    'done': done,
    if (habitId != null) 'habitId': habitId,
    'isHabit': isHabit,
    if (time != null) 'time': time,
    if (duration != null) 'duration': duration,
    if (timeStart != null) 'timeStart': timeStart,
    if (timeEnd != null) 'timeEnd': timeEnd,
    'createdAt': createdAt,
    'isReminderEnabled': isReminderEnabled,
    if (completedAt != null) 'completedAt': completedAt,
    if (achievedCount != null) 'achievedCount': achievedCount,
    if (achievedDuration != null) 'achievedDuration': achievedDuration,
    'deferredCount': deferredCount,
  };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'],
    text: j['text'],
    category: j['category'] ?? 'today',
    done: j['done'] ?? false,
    habitId: j['habitId']?.toString(),
    isHabit: j['isHabit'] ?? false,
    time: j['time'],
    duration: j['duration'],
    timeStart: j['timeStart'],
    timeEnd: j['timeEnd'],
    createdAt: j['createdAt'] ?? DateTime.now().toIso8601String(),
    isReminderEnabled: j['isReminderEnabled'] ?? true,
    completedAt: j['completedAt'],
    deferredCount: j['deferredCount'] ?? 0,
  );
}

class GoalItem {
  final int id;
  String text;
  bool done;

  GoalItem({required this.id, required this.text, this.done = false});

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'done': done};
  factory GoalItem.fromJson(Map<String, dynamic> j) =>
      GoalItem(id: j['id'], text: j['text'], done: j['done'] ?? false);
}

class ParsedVoiceRegistration {
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final bool hasDate;
  final bool hasTime;
  final Map<String, dynamic>? repeatRule;
  final String rawSpeech;

  ParsedVoiceRegistration({
    required this.title,
    required this.date,
    this.time,
    required this.hasDate,
    required this.hasTime,
    this.repeatRule,
    required this.rawSpeech,
  });

  bool get isRecurring => repeatRule != null;
}

class HabitItem {
  final dynamic id;
  String name;
  String freq; // 'daily' | 'weekly'
  List<int> days; // 0=월~6=일
  String checkType; // 'check' | 'count' | 'duration' | 'both'
  String timeType; // 'none' | 'single' | 'range' | 'duration'
  bool tracking;
  int? countGoal;
  String? unit;
  int? durationGoal;
  String? timeStart;
  String? timeEnd;
  String? habitDuration;
  String createdAt;
  bool isReminderEnabled;

  HabitItem({
    required this.id,
    required this.name,
    this.freq = 'daily',
    this.days = const [],
    this.checkType = 'check',
    this.timeType = 'none',
    this.tracking = true,
    this.countGoal,
    this.unit,
    this.durationGoal,
    this.timeStart,
    this.timeEnd,
    this.habitDuration,
    required this.createdAt,
    this.isReminderEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'freq': freq,
    'days': days,
    'checkType': checkType,
    'timeType': timeType,
    'tracking': tracking,
    if (countGoal != null) 'countGoal': countGoal,
    if (unit != null) 'unit': unit,
    if (durationGoal != null) 'durationGoal': durationGoal,
    if (timeStart != null) 'timeStart': timeStart,
    if (timeEnd != null) 'timeEnd': timeEnd,
    if (habitDuration != null) 'habitDuration': habitDuration,
    'createdAt': createdAt,
    'isReminderEnabled': isReminderEnabled,
  };

  factory HabitItem.fromJson(Map<String, dynamic> j) => HabitItem(
    id: j['id'],
    name: j['name'],
    freq: j['freq'] ?? 'daily',
    days: List<int>.from(j['days'] ?? []),
    checkType: j['checkType'] ?? 'check',
    timeType: j['timeType'] ?? 'none',
    tracking: j['tracking'] ?? true,
    countGoal: j['countGoal'],
    unit: j['unit'],
    durationGoal: j['durationGoal'],
    timeStart: j['timeStart'],
    timeEnd: j['timeEnd'],
    habitDuration: j['habitDuration'],
    createdAt: j['createdAt'] ?? DateTime.now().toIso8601String(),
    isReminderEnabled: j['isReminderEnabled'] ?? true,
  );
}

class ScheduleItem {
  final String id;
  String text;
  String? timeStart;
  String? timeEnd;
  String? time;
  String? duration;
  bool done;
  String createdAt;
  bool isReminderEnabled;
  int deferredCount;
  bool isRecurring;
  String? recurrenceGroupId;
  Map<String, dynamic>? recurrenceRule;

  ScheduleItem({
    required this.id,
    required this.text,
    this.timeStart,
    this.timeEnd,
    this.time,
    this.duration,
    this.done = false,
    required this.createdAt,
    this.isReminderEnabled = false,
    this.deferredCount = 0,
    this.isRecurring = false,
    this.recurrenceGroupId,
    this.recurrenceRule,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'timeStart': timeStart,
    'timeEnd': timeEnd,
    'time': time,
    'duration': duration,
    'done': done,
    'createdAt': createdAt,
    'deferredCount': deferredCount,
    'isReminderEnabled': isReminderEnabled,
    'isRecurring': isRecurring,
    if (recurrenceGroupId != null) 'recurrenceGroupId': recurrenceGroupId,
    if (recurrenceRule != null) 'recurrenceRule': recurrenceRule,
  };

  factory ScheduleItem.fromJson(Map<String, dynamic> j) => ScheduleItem(
    id: j['id'].toString(),
    text: j['text'],
    timeStart: j['timeStart'],
    timeEnd: j['timeEnd'],
    time: j['time'],
    duration: j['duration'],
    done: j['done'] ?? false,
    createdAt: j['createdAt'] ?? DateTime.now().toIso8601String(),
    isReminderEnabled: j['isReminderEnabled'] ?? false,
    deferredCount: j['deferredCount'] ?? 0,
    isRecurring: j['isRecurring'] ?? false,
    recurrenceGroupId: j['recurrenceGroupId'],
    recurrenceRule: j['recurrenceRule'] is Map
        ? Map<String, dynamic>.from(j['recurrenceRule'])
        : null,
  );
}

class VisionDeadline {
  final String year;
  final String month;
  final String period;

  VisionDeadline({
    required this.year,
    required this.month,
    required this.period,
  });

  Map<String, dynamic> toJson() => {
    'year': year,
    'month': month,
    'period': period,
  };
  factory VisionDeadline.fromJson(Map<String, dynamic> j) => VisionDeadline(
    year: j['year'].toString(),
    month: j['month'].toString(),
    period: j['period'],
  );
}

class MemoSection {
  String title;
  String content;

  MemoSection({required this.title, required this.content});

  Map<String, dynamic> toJson() => {'title': title, 'content': content};
  factory MemoSection.fromJson(Map<String, dynamic> j) =>
      MemoSection(title: j['title'] ?? '', content: j['content'] ?? '');
}

class ActionCandidate {
  String? id;
  String title;
  String? convertedTaskId;
  String? convertedHabitId;
  String? convertedType;
  String? convertedDate;

  ActionCandidate({
    this.id,
    required this.title,
    this.convertedTaskId,
    this.convertedHabitId,
    this.convertedType,
    this.convertedDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'convertedTaskId': convertedTaskId,
    'convertedHabitId': convertedHabitId,
    'convertedType': convertedType,
    'convertedDate': convertedDate,
  };

  factory ActionCandidate.fromJson(Map<String, dynamic> j) => ActionCandidate(
    id: j['id'],
    title: j['title'] ?? j['text'] ?? '',
    convertedTaskId: j['convertedTaskId'],
    convertedHabitId: j['convertedHabitId'],
    convertedType: j['convertedType'],
    convertedDate: j['convertedDate'],
  );
}

class MilestoneItem {
  String text;
  bool done;
  String? date;
  String? achievedDate;
  String? memo;
  List<MemoSection>? memoSections;
  List<ActionCandidate>? actionCandidates;

  MilestoneItem({
    required this.text,
    this.done = false,
    this.date,
    this.achievedDate,
    this.memo,
    this.memoSections,
    this.actionCandidates,
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'done': done,
    'date': date,
    'achievedDate': achievedDate,
    'memo': memo,
    'memoSections': memoSections?.map((e) => e.toJson()).toList(),
    'actionCandidates': actionCandidates?.map((e) => e.toJson()).toList(),
  };

  factory MilestoneItem.fromJson(Map<String, dynamic> j) => MilestoneItem(
    text: j['text'],
    done: j['done'] ?? false,
    date: j['date'],
    achievedDate: j['achievedDate'],
    memo: j['memo'],
    memoSections: j['memoSections'] != null
        ? (j['memoSections'] as List)
              .map((e) => MemoSection.fromJson(e))
              .toList()
        : null,
    actionCandidates: j['actionCandidates'] != null
        ? (j['actionCandidates'] as List)
              .map((e) => ActionCandidate.fromJson(e))
              .toList()
        : null,
  );
}

class MilestoneWithVision {
  final MilestoneItem milestone;
  final VisionItem vision;
  MilestoneWithVision(this.milestone, this.vision);
}

class VisionItem {
  final String id;
  String name;
  String? desc;
  String coachId;
  VisionDeadline deadline;
  List<MilestoneItem> milestones;
  String updatedAt;

  VisionItem({
    required this.id,
    required this.name,
    this.desc,
    required this.coachId,
    required this.deadline,
    required this.milestones,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'desc': desc,
    'coachId': coachId,
    'deadline': deadline.toJson(),
    'milestones': milestones.map((e) => e.toJson()).toList(),
    'updatedAt': updatedAt,
  };

  factory VisionItem.fromJson(Map<String, dynamic> j) => VisionItem(
    id: j['id'].toString(),
    name: j['name'],
    desc: j['desc'],
    coachId: j['coachId'] ?? 'self',
    deadline: VisionDeadline.fromJson(j['deadline']),
    milestones:
        (j['milestones'] as List?)
            ?.map((e) => MilestoneItem.fromJson(e))
            .toList() ??
        [],
    updatedAt: j['updatedAt'] ?? DateTime.now().toIso8601String(),
  );
}

// ─────────────────────────────────────────────────────────────
// 할 일 화면
// ─────────────────────────────────────────────────────────────
class TasksScreen extends StatefulWidget {
  final String coachId;
  final void Function(String message)? onCoreTaskSet;
  final TasksScreenController? controller;
  final String? initialBottomSheet;
  const TasksScreen({
    super.key,
    required this.coachId,
    this.onCoreTaskSet,
    this.controller,
    this.initialBottomSheet,
  });

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class TasksScreenController {
  _TasksScreenState? _state;
  void _attach(_TasksScreenState state) => _state = state;
  void _detach() => _state = null;

  void openBedtimeMoveFlow({bool nextDay = false}) {
    _state?._openBedtimeMoveFlow(nextDay: nextDay);
  }

  void openBottomSheet(String type) {
    _state?._openBottomSheet(type);
  }
}

class MilestoneInfo {
  final String visionName;
  final String milestoneText;
  final bool isMilestoneSelf;
  final VisionItem vision;
  final MilestoneItem milestone;
  MilestoneInfo({
    required this.visionName,
    required this.milestoneText,
    required this.isMilestoneSelf,
    required this.vision,
    required this.milestone,
  });
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late CoachConfig _coach;

  // 데이터 (웹앱 변수 그대로)
  bool _isCoreReminderEnabledGlobally = false;
  List<TaskItem> tasks = [];
  List<TaskItem> coreTasks = [];
  bool _coreExpanded = false;
  List<GoalItem> weekGoals = [];
  List<GoalItem> monthGoals = [];
  List<HabitItem> habits = [];
  List<VisionItem> visions = [];
  String _planType = 'none'; // 'none' | 'friends' | 'master'
  Map<String, Map<String, dynamic>> habitLogs = {};
  Map<String, List<ScheduleItem>> schedules = {};
  Map<String, dynamic>? vacationInfo;
  double _resetHour = 3.0;

  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListeningToday = false;
  bool _isListeningSchedule = false;
  bool _isConfirmDialogShowing = false;

  DateTime _calFocusedDay = DateTime.now();
  DateTime _calSelectedDay = DateTime.now();
  final _schInputCtrl = TextEditingController();

  String _schTimeType = 'none'; // 'none', 'single', 'range', 'duration'
  TimeOfDay? _schStartTime;
  TimeOfDay? _schEndTime;
  String? _schDuration;
  bool _schReminderEnabled = false;
  bool _schRepeatEnabled = false;
  Map<String, dynamic>? _schRepeatRule;

  String _todayTimeType = 'none'; // 'none', 'single', 'range', 'duration'
  bool _todayReminderEnabled = false;
  TimeOfDay? _todayStartTime;
  TimeOfDay? _todayEndTime;
  String? _todayDuration;

  // 오늘 탭 입력
  final _todayInputCtrl = TextEditingController();
  // 주간 목표 입력
  final _weekInputCtrl = TextEditingController();
  // 월간 목표 입력
  final _monthInputCtrl = TextEditingController();

  // 목표 서브탭
  String _goalTab = 'week'; // 'week' | 'month'

  @override
  void initState() {
    super.initState();
    _coach = CoachConfigs.get(widget.coachId);
    _tabCtrl = TabController(length: 4, vsync: this);
    widget.controller?._attach(this);
    _loadAll();
    _initSpeech();
    // 플랜 타입 로드
    UserDataService.load().then((d) {
      if (mounted) setState(() => _planType = d.planType);
    });
  }

  @override
  void dispose() {
    widget.controller?._detach();
    _tabCtrl.dispose();
    _todayInputCtrl.dispose();
    _weekInputCtrl.dispose();
    _monthInputCtrl.dispose();
    super.dispose();
  }

  // ── 데이터 로드 ──────────────────────────────────────────
  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    final rawTasks = prefs.getString('nyang_tasks');
    final rawCore = prefs.getString('nyang_core_tasks');
    final rawWeek = prefs.getString('nyang_week_goals');
    final rawMonth = prefs.getString('nyang_month_goals');
    final rawHabits = prefs.getString('nyang_habits');
    final rawVisions = prefs.getString('nyang_visions');
    final rawSchedules = prefs.getString('nyang_schedules');
    final rawLogs = prefs.getString('nyang_habit_logs');
    final rawVacation = prefs.getString('nyang_vacation');
    final coreEnabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;

    setState(() {
      _isCoreReminderEnabledGlobally = coreEnabled;
      _todayReminderEnabled = false;
      if (rawTasks != null) {
        tasks = (jsonDecode(rawTasks) as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      }
      if (rawCore != null) {
        coreTasks = (jsonDecode(rawCore) as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      }
      if (rawWeek != null) {
        weekGoals = (jsonDecode(rawWeek) as List)
            .map((e) => GoalItem.fromJson(e))
            .toList();
      }
      if (rawMonth != null) {
        monthGoals = (jsonDecode(rawMonth) as List)
            .map((e) => GoalItem.fromJson(e))
            .toList();
      }
      if (rawHabits != null) {
        habits = (jsonDecode(rawHabits) as List)
            .map((e) => HabitItem.fromJson(e))
            .toList();
      }
      if (rawVisions != null) {
        visions = (jsonDecode(rawVisions) as List)
            .map((e) => VisionItem.fromJson(e))
            .toList();
      }
      if (rawSchedules != null) {
        final Map<String, dynamic> decodedMap = jsonDecode(rawSchedules);
        schedules = decodedMap.map((key, value) {
          final list = (value as List)
              .map((e) => ScheduleItem.fromJson(e))
              .toList();
          return MapEntry(key, list);
        });
      }
      if (rawLogs != null) {
        final decoded = jsonDecode(rawLogs) as Map<String, dynamic>;
        habitLogs = decoded.map(
          (k, v) => MapEntry(k, Map<String, dynamic>.from(v)),
        );
      }
      if (rawVacation != null) {
        vacationInfo = jsonDecode(rawVacation) as Map<String, dynamic>;
      }
      _resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    });

    await _checkReset(prefs);
    await _checkWeekMonthReset(prefs);
    _injectTodayHabits();
    _injectTodaySchedules();

    if (widget.initialBottomSheet != null) {
      _openBottomSheet(widget.initialBottomSheet!);
    }
  }

  Future<bool> _checkCoreReminderEnabledGlobally() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;
    if (mounted && _isCoreReminderEnabledGlobally != enabled) {
      setState(() {
        _isCoreReminderEnabledGlobally = enabled;
        if (!enabled) {
          _todayReminderEnabled = false;
          _schReminderEnabled = false;
        }
      });
    }
    return enabled;
  }

  void _openBottomSheet(String type) {
    if (type == 'done') {
      _showTasksBottomSheet(title: '오늘 완료한 할 일', showDone: true);
    } else if (type == 'remaining') {
      _showTasksBottomSheet(title: '오늘 남은 할 일', showDone: false);
    }
  }

  void _showTasksBottomSheet({required String title, required bool showDone}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final filteredTasks = tasks.where((t) => t.done == showDone).toList();
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 14),
              if (filteredTasks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '해당하는 할 일이 없습니다.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: const Color(0xFFA0A0B0),
                      ),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.4,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filteredTasks.length,
                    itemBuilder: (ctx, i) {
                      final t = filteredTasks[i];
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFF3F4F6)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              showDone
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: showDone
                                  ? const Color(0xFF8B7CFF)
                                  : const Color(0xFFD1D5DB),
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                t.text,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF3D3A4E),
                                  decoration: showDone
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkReset(SharedPreferences prefs) async {
    final today = _getTodayStr();
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
      var yesterday = DateTime(
        n.year,
        n.month,
        n.day,
      ).subtract(const Duration(days: 1));
      if (n.hour < _resetHour)
        yesterday = yesterday.subtract(const Duration(days: 1));
      final yStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      int streak = prefs.getInt('nyang_streak') ?? 0;
      final isLastVacation =
          vacationInfo !=
          null; // Need proper vacation logic based on date, simplified for now

      if (lastDate == yStr) {
        if (prev.isNotEmpty && prev['success'] == true)
          streak += 1;
        else if (isLastVacation) {
          /* keep streak */
        } else
          streak = 0;
      } else {
        if (prev.isNotEmpty && (prev['success'] == true || isLastVacation))
          streak = 1;
        else
          streak = 0;
      }

      await prefs.setInt('nyang_streak', streak);

      // 2. Clear tasks
      setState(() {
        tasks.clear();
        coreTasks.clear();
        _coreExpanded = false;
      });
      await prefs.setBool('nyang_core_reminder_enabled', false);
      await prefs.remove('nyang_core_reminder_coach');
      await prefs.remove('nyang_core_reminder_advance');
      await prefs.remove('nyang_deferred_tasks_today');
      await NotificationService().cancelCoreReminders();
      await _saveTasks();
      await _saveCoreTasks();

      // 3. Generate daily summary before clearing chat history
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
          } catch (e) {
            print('Failed to generate daily summary: $e');
          }
        }
      }

      // 4. Clear all chat histories
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
        await prefs.setString('nyang_chat_history_$id', '[]');
      }

      await prefs.setString('nyang_last_date', today);
    }
  }

  // ── checkWeekMonthReset ───────────────────────────────────
  Future<void> _checkWeekMonthReset(SharedPreferences prefs) async {
    final thisWeek = _getWeekMondayStr();
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    // 주 목표 리셋 (매주 월요일 기준)
    final lastWeek = prefs.getString('nyang_last_week');
    if (lastWeek == null) {
      // 최초 실행 — 현재 주 기록만, 리셋 없음
      await prefs.setString('nyang_last_week', thisWeek);
    } else if (lastWeek != thisWeek) {
      await prefs.setString('nyang_last_week', thisWeek);
      await prefs.setString('nyang_week_goals', '[]');
      setState(() => weekGoals.clear());
      TasksSyncService.scheduleSyncToCloud();
    }

    // 월 목표 리셋 (매월 1일 기준)
    final lastMonth = prefs.getString('nyang_last_month');
    if (lastMonth == null) {
      // 최초 실행 — 현재 달 기록만, 리셋 없음
      await prefs.setString('nyang_last_month', thisMonth);
    } else if (lastMonth != thisMonth) {
      await prefs.setString('nyang_last_month', thisMonth);
      await prefs.setString('nyang_month_goals', '[]');
      setState(() => monthGoals.clear());
      TasksSyncService.scheduleSyncToCloud();
    }
  }

  Future<void> _updateCoach() async {
    final prefs = await SharedPreferences.getInstance();
    final cId = prefs.getString('nyang_selected_coach') ?? 'cat';
    setState(() {
      _coach = CoachConfigs.all[cId] ?? CoachConfigs.all['cat']!;
    });
  }

  Future<bool> _showConfirmDeleteDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            title,
            style: GoogleFonts.notoSansKr(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: const Color(0xFF3D3A4E),
            ),
          ),
          content: Text(
            message,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: const Color(0xFF6B7280),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(
                  color: const Color(0xFF9593A5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                '삭제',
                style: GoogleFonts.notoSansKr(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  // ── _showHabitCompletionDialog (습관 입력 팝업) ────────────────
  Future<Map<String, int>?> _showHabitCompletionDialog(
    TaskItem t,
    HabitItem h,
  ) async {
    final countController = TextEditingController(text: '');
    final durationController = TextEditingController(text: '');

    // Percent calculation helper
    String getPct(String valStr, int? goal) {
      if (goal == null || goal <= 0) return '';
      final v = int.tryParse(valStr) ?? 0;
      return '${(v / goal * 100).round()}%';
    }

    return showDialog<Map<String, int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '🌱 ${h.name}',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '오늘 얼마나 했는지 기록해요!',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: const Color(0xFFA0A0B0),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (h.checkType == 'count' || h.checkType == 'both') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '🔢 오늘 ${h.unit ?? '수량'}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                          Text(
                            '목표: ${h.countGoal ?? '-'}${h.unit ?? ''}',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: const Color(0xFFA0A0B0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        onChanged: (val) => setDialogState(() {}),
                        decoration: InputDecoration(
                          suffixText: h.unit ?? '',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Text(
                              getPct(countController.text, h.countGoal),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _coach.accentColor,
                              ),
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9F9FB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    if (h.checkType == 'duration' || h.checkType == 'both') ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '⏱ 소요 시간 (분)',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                          Text(
                            '목표: ${h.durationGoal ?? '-'}분',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: const Color(0xFFA0A0B0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: durationController,
                        keyboardType: TextInputType.number,
                        onChanged: (val) => setDialogState(() {}),
                        decoration: InputDecoration(
                          suffixText: '분',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Text(
                              getPct(durationController.text, h.durationGoal),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: _coach.accentColor,
                              ),
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF9F9FB),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: const Color(0xFFF9F9FB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              '취소',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF8E8D9B),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              int? c;
                              int? d;
                              if (h.checkType == 'count' ||
                                  h.checkType == 'both') {
                                c = int.tryParse(countController.text) ?? 0;
                              }
                              if (h.checkType == 'duration' ||
                                  h.checkType == 'both') {
                                d = int.tryParse(durationController.text) ?? 0;
                              }
                              Navigator.pop(ctx, {
                                'count': c ?? 0,
                                'duration': d ?? 0,
                              });
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: _coach.accentColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              '완료',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _getWeekMondayStr() {
    final todayStr = _getTodayStr();
    final parts = todayStr.split('-');
    if (parts.length < 3) return todayStr;
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final day = int.tryParse(parts[2]) ?? DateTime.now().day;
    final baseDate = DateTime(year, month, day);
    final monday = baseDate.subtract(Duration(days: baseDate.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  // ── saveTasks (웹앱 그대로) ───────────────────────────────
  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_tasks',
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
    await _saveTodayRecord();
    await WidgetSyncService.syncFromStoredTasks();
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveTodayRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      history = List<Map<String, dynamic>>.from(jsonDecode(rawHistory));
    }

    final todayStr = _getTodayStr();
    final doneTasks = tasks.where((t) => t.done).toList();

    // 밤 9시 이후 이월된 일정 로드
    final rawDeferred = prefs.getString('nyang_deferred_tasks_today');
    List<dynamic> deferredList = [];
    if (rawDeferred != null) {
      try {
        deferredList = jsonDecode(rawDeferred);
      } catch (_) {}
    }

    final mergedTasks = [
      ...tasks.map(
        (t) => {
          'text': t.text,
          'done': t.done,
          'category': t.category,
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

    final record = {
      'date': todayStr,
      'totalCount': tasks.length + deferredList.length,
      'doneCount': doneTasks.length,
      'success': doneTasks.isNotEmpty,
      'isVacation': vacationInfo != null,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': mergedTasks,
    };

    final idx = history.indexWhere((h) => h['date'] == todayStr);
    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
    }

    // Keep last 90 days
    history.sort((a, b) => a['date'].compareTo(b['date']));
    if (history.length > 90) history = history.sublist(history.length - 90);

    await prefs.setString('nyang_history', jsonEncode(history));
  }

  Future<void> _saveCoreTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_core_tasks',
      jsonEncode(coreTasks.map((t) => t.toJson()).toList()),
    );
    NotificationService().syncCoreReminders();
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveVacation() async {
    final prefs = await SharedPreferences.getInstance();
    if (vacationInfo == null) {
      await prefs.remove('nyang_vacation');
    } else {
      await prefs.setString('nyang_vacation', jsonEncode(vacationInfo));
    }
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveGoals(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final goals = type == 'week' ? weekGoals : monthGoals;
    await prefs.setString(
      'nyang_${type}_goals',
      jsonEncode(goals.map((g) => g.toJson()).toList()),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveHabits() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_habits',
      jsonEncode(habits.map((h) => h.toJson()).toList()),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveVisions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_visions',
      jsonEncode(visions.map((v) => v.toJson()).toList()),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _saveSchedules() async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> toEncode = {};
    schedules.forEach((k, v) {
      if (v.isNotEmpty) toEncode[k] = v.map((e) => e.toJson()).toList();
    });
    await prefs.setString('nyang_schedules', jsonEncode(toEncode));
    TasksSyncService.scheduleSyncToCloud();

    // 일정 변경 시 오늘의 할 일 탭에도 즉시 반영
    _injectTodaySchedules();
  }

  Future<void> _saveHabitLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_habit_logs', jsonEncode(habitLogs));
    TasksSyncService.scheduleSyncToCloud();
  }

  // ── getTodayStr ───────────────────────────────────────────
  String _getTodayStr() {
    final n = DateTime.now();
    var base = DateTime(n.year, n.month, n.day);
    if (n.hour < _resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
  }

  // ── injectTodayHabits (웹앱 그대로) ──────────────────────
  void _injectTodayHabits() {
    final today = _getTodayStr();
    final todayDow = DateTime.now().weekday; // 1=월~7=일
    // 웹앱 dbDow: 0=월~6=일
    final dbDow = todayDow - 1;

    final todayHabits = habits.where((h) {
      if (h.freq == 'daily') return true;
      if (h.freq == 'weekly') return h.days.contains(dbDow);
      return false;
    }).toList();

    final todayHabitIds = todayHabits.map((h) => h.id.toString()).toList();

    // 오늘 해당 없는 habit 태스크 제거
    tasks.removeWhere((t) {
      if (t.habitId == null) return false;
      return !todayHabitIds.contains(t.habitId.toString());
    });

    // 오늘 습관 주입
    for (final h in todayHabits) {
      final existing = tasks.any(
        (t) => t.habitId?.toString() == h.id.toString(),
      );
      if (existing) continue;

      final log = (habitLogs[h.id.toString()] ?? {})[today];
      final isSkipped = log != null && log['status'] == 'skipped';
      if (isSkipped) continue;

      final isDone = log != null && log['done'] == true;

      final taskId = 'habit_${h.id.toString().replaceAll('.', '_')}_$today';
      String? tTime;
      if (h.timeType == 'single' && h.timeStart != null) tTime = h.timeStart;
      if (h.timeType == 'range' && h.timeStart != null) {
        tTime = h.timeEnd != null
            ? "${h.timeStart} ~ ${h.timeEnd}"
            : h.timeStart;
      }

      tasks.add(
        TaskItem(
          id: taskId,
          habitId: h.id.toString(),
          text: h.name,
          category: 'habit',
          done: isDone,
          isHabit: true,
          time: tTime,
          duration: h.habitDuration,
          timeStart: h.timeStart,
          timeEnd: h.timeEnd,
          createdAt: DateTime.now().toIso8601String(),
          completedAt: isDone ? log!['completedAt'] : null,
        ),
      );
    }

    setState(() {});
    _saveTasks();
  }

  // ── injectTodaySchedules ──────────────────────────────
  void _injectTodaySchedules() {
    final today = _getTodayStr();
    final todaySchedules = schedules[today] ?? [];
    final todayScheduleIds = todaySchedules.map((s) => s.id).toList();

    // 오늘 날짜가 아니게 된 (혹은 삭제된) 일정 태스크 제거
    tasks.removeWhere((t) {
      if (t.category != 'schedule') return false;
      return !todayScheduleIds.contains(
        t.id.toString().replaceAll('schedule_', ''),
      );
    });

    // 오늘 일정 주입
    bool coreTasksChanged = false;
    for (final s in todaySchedules) {
      final taskId = 'schedule_${s.id}';
      final existingIndex = tasks.indexWhere((t) => t.id.toString() == taskId);

      if (existingIndex >= 0) {
        final existingTask = tasks[existingIndex];
        existingTask.text = s.text;
        existingTask.time = _displayTimeFromStored(
          time: s.time,
          timeStart: s.timeStart,
          timeEnd: s.timeEnd,
        );
        existingTask.timeStart = s.timeStart;
        existingTask.timeEnd = s.timeEnd;
        existingTask.duration = s.duration;
        existingTask.done = s.done;
        existingTask.deferredCount = s.deferredCount;

        // Check if reminder was toggled from schedule edit
        bool reminderToggled =
            existingTask.isReminderEnabled != s.isReminderEnabled;
        existingTask.isReminderEnabled = s.isReminderEnabled;

        if (reminderToggled) {
          if (s.isReminderEnabled) {
            final coreExists = coreTasks.any((t) => t.id.toString() == taskId);
            if (!coreExists) {
              coreTasks.add(existingTask);
              coreTasksChanged = true;
            }
          } else {
            final initialLength = coreTasks.length;
            coreTasks.removeWhere((t) => t.id.toString() == taskId);
            if (coreTasks.length < initialLength) coreTasksChanged = true;
          }
        } else {
          // If it is already in core tasks, update its properties as well
          final coreIndex = coreTasks.indexWhere(
            (t) => t.id.toString() == taskId,
          );
          if (coreIndex >= 0) {
            coreTasks[coreIndex].text = s.text;
            coreTasks[coreIndex].time = _displayTimeFromStored(
              time: s.time,
              timeStart: s.timeStart,
              timeEnd: s.timeEnd,
            );
            coreTasks[coreIndex].timeStart = s.timeStart;
            coreTasks[coreIndex].timeEnd = s.timeEnd;
            coreTasks[coreIndex].duration = s.duration;
            coreTasks[coreIndex].done = s.done;
            coreTasks[coreIndex].deferredCount = s.deferredCount;
            coreTasksChanged = true;
          }
        }
      } else {
        final newTask = TaskItem(
          id: taskId,
          text: s.text,
          category: 'schedule',
          done: s.done,
          time: _displayTimeFromStored(
            time: s.time,
            timeStart: s.timeStart,
            timeEnd: s.timeEnd,
          ),
          duration: s.duration,
          timeStart: s.timeStart,
          timeEnd: s.timeEnd,
          createdAt: s.createdAt,
          isReminderEnabled: s.isReminderEnabled,
          deferredCount: s.deferredCount,
        );
        tasks.add(newTask);

        if (s.isReminderEnabled) {
          final coreExists = coreTasks.any((t) => t.id.toString() == taskId);
          if (!coreExists) {
            coreTasks.add(newTask);
            coreTasksChanged = true;
          }
        }
      }
    }

    if (coreTasksChanged) _saveCoreTasks();

    // _saveSchedules 에서 불릴 경우 중복될 수 있으나 UI 갱신을 위해 안전하게 호출
    setState(() {});
    _saveTasks();
  }

  // ── 자연어 시간 표현 추출 ─────────────────────────────────
  ({String cleanText, TimeOfDay? time})? _parseNaturalLanguageTime(
    String input,
  ) {
    // 오전/오후/아침/저녁/밤 + H시 (+ M분 또는 반)
    final timeRegex = RegExp(
      r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(?:(\d{1,2})분|반))?(?:\s*(?:에|쯤|경|까지))?',
    );
    final match = timeRegex.firstMatch(input);
    if (match == null) return null;

    final prefix = (match.group(1) ?? '').replaceAll(RegExp(r'\s'), '');
    final rawHour = int.tryParse(match.group(2)!) ?? 0;

    int minute = 0;
    if (match.group(3) != null) {
      minute = int.tryParse(match.group(3)!) ?? 0;
    } else if (match.group(0)!.contains('반')) {
      minute = 30;
    }

    if (rawHour < 1 || rawHour > 24) return null;

    int hour24 = rawHour;
    if (prefix == '오전' || prefix == '아침') {
      hour24 = rawHour == 12 ? 0 : rawHour;
    } else if (prefix == '오후' || prefix == '저녁' || prefix == '밤') {
      hour24 = rawHour == 12 ? 12 : rawHour + 12;
    } else {
      // 오전/오후 접두사가 없을 때 현재 시간 기준
      if (rawHour < 12) {
        final now = DateTime.now();
        if (now.hour > rawHour ||
            (now.hour == rawHour && now.minute >= minute)) {
          hour24 = rawHour + 12;
        }
      }
    }

    final time = TimeOfDay(hour: hour24, minute: minute);
    final cleanText = input
        .replaceFirst(match.group(0)!, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return (
      cleanText: cleanText.isEmpty ? input.trim() : cleanText,
      time: time,
    );
  }

  // ── addTask (웹앱 그대로) ─────────────────────────────────
  void _addTodayTask(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    String? timeStr;
    String? timeEndStr;
    String? durStr;
    String? timeStartStr;
    String finalTitle = trimmed;
    bool reminderEnabled = false;

    if (_todayTimeType == 'none') {
      final parsed = _parseNaturalLanguageTime(trimmed);
      if (parsed != null) {
        finalTitle = parsed.cleanText;
        timeStr = _formatTime(parsed.time!);
        timeStartStr =
            '${parsed.time!.hour.toString().padLeft(2, '0')}:${parsed.time!.minute.toString().padLeft(2, '0')}';
        // 자연어로 등록하는 일정이므로 글로벌 설정 상태에 따라 알람 자동 활성화
        reminderEnabled = _isCoreReminderEnabledGlobally;
      }
    } else {
      if (_todayTimeType == 'single' && _todayStartTime != null) {
        timeStr = _formatTime(_todayStartTime!);
        timeStartStr =
            '${_todayStartTime!.hour.toString().padLeft(2, '0')}:${_todayStartTime!.minute.toString().padLeft(2, '0')}';
      } else if (_todayTimeType == 'range' && _todayStartTime != null) {
        timeStr = _formatTime(_todayStartTime!);
        if (_todayEndTime != null) {
          timeStr += ' ~ ${_formatTime(_todayEndTime!)}';
          timeEndStr =
              '${_todayEndTime!.hour.toString().padLeft(2, '0')}:${_todayEndTime!.minute.toString().padLeft(2, '0')}';
        }
        timeStartStr =
            '${_todayStartTime!.hour.toString().padLeft(2, '0')}:${_todayStartTime!.minute.toString().padLeft(2, '0')}';
      } else if (_todayTimeType == 'duration' && _todayDuration != null) {
        durStr = _todayDuration;
      }
      reminderEnabled = _resolvedTimeReminderEnabled(
        _todayTimeType,
        _todayStartTime,
        _todayReminderEnabled,
      );
    }

    final task = TaskItem(
      id:
          DateTime.now().millisecondsSinceEpoch +
          DateTime.now().microsecond % 1000,
      text: finalTitle,
      category: 'today',
      time: timeStr,
      timeStart: timeStartStr,
      timeEnd: timeEndStr,
      duration: durStr,
      done: false,
      createdAt: DateTime.now().toIso8601String(),
      isReminderEnabled: reminderEnabled,
    );
    setState(() {
      tasks.add(task);
      _todayTimeType = 'none';
      _todayReminderEnabled = false;
      _todayStartTime = null;
      _todayEndTime = null;
      _todayDuration = null;
    });
    _saveTasks();
    _todayInputCtrl.clear();
  }

  // ── toggleTask (웹앱 그대로) ──────────────────────────────
  Future<void> _toggleTask(dynamic id) async {
    if (id.toString().startsWith('milestone_')) {
      final idStr = id.toString();
      for (final v in visions) {
        for (final m in v.milestones) {
          final mId = 'milestone_${v.name}_${m.text}';
          if (mId == idStr) {
            setState(() {
              m.done = !m.done;
              if (m.done) {
                final now = DateTime.now();
                m.achievedDate =
                    "${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}";
              } else {
                m.achievedDate = null;
              }
            });
            _saveVisions();
            break;
          }
        }
      }
      return;
    }

    final t = tasks.firstWhere(
      (t) => t.id.toString() == id.toString(),
      orElse: () => tasks.first,
    );
    if (t.done) {
      // 완료 취소
      setState(() {
        t.done = false;
        t.completedAt = null;
        t.achievedCount = null;
        t.achievedDuration = null;
        if (t.habitId != null && habitLogs[t.habitId!] != null) {
          habitLogs[t.habitId!]!.remove(_getTodayStr());
        }
        if (t.category == 'schedule') {
          final today = _getTodayStr();
          final sId = t.id.toString().replaceAll('schedule_', '');
          if (schedules.containsKey(today)) {
            final sItem = schedules[today]!.firstWhere(
              (s) => s.id == sId,
              orElse: () => schedules[today]!.first,
            );
            if (sItem.id == sId) sItem.done = false;
          }
        }
        final coreIdx = coreTasks.indexWhere(
          (ct) => ct.id.toString() == t.id.toString(),
        );
        if (coreIdx >= 0) {
          coreTasks[coreIdx].done = false;
          coreTasks[coreIdx].completedAt = null;
        }
      });
      _saveTasks();
      _saveHabitLogs();
      _saveCoreTasks();
      if (t.category == 'schedule') _saveSchedules();
    } else {
      HabitItem? habitInfo;
      if (t.habitId != null) {
        final hIdx = habits.indexWhere(
          (h) => h.id.toString() == t.habitId.toString(),
        );
        if (hIdx != -1) {
          habitInfo = habits[hIdx];
          if (habitInfo.checkType == 'count' ||
              habitInfo.checkType == 'duration' ||
              habitInfo.checkType == 'both') {
            final result = await _showHabitCompletionDialog(t, habitInfo);
            if (result == null) return; // 사용자가 취소함
            t.achievedCount = result['count'];
            t.achievedDuration = result['duration'];
          }
        }
      }

      // 완료 처리
      setState(() {
        t.done = true;
        t.completedAt = DateTime.now().toIso8601String();
        if (t.habitId != null) {
          habitLogs[t.habitId!] ??= {};
          final logMap = <String, dynamic>{
            'done': true,
            'status': 'done',
            'completedAt': t.completedAt,
          };

          if (habitInfo != null) {
            if (habitInfo.checkType == 'count' ||
                habitInfo.checkType == 'both') {
              logMap['count'] = t.achievedCount ?? habitInfo.countGoal ?? 0;
              logMap['countGoal'] = habitInfo.countGoal ?? 0;
              logMap['unit'] = habitInfo.unit ?? '';
            }
            if (habitInfo.checkType == 'duration' ||
                habitInfo.checkType == 'both') {
              logMap['duration'] =
                  t.achievedDuration ?? habitInfo.durationGoal ?? 0;
              logMap['durationGoal'] = habitInfo.durationGoal ?? 0;
            }
          }
          habitLogs[t.habitId!]![_getTodayStr()] = logMap;
        }
        if (t.category == 'schedule') {
          final today = _getTodayStr();
          final sId = t.id.toString().replaceAll('schedule_', '');
          if (schedules.containsKey(today)) {
            final sItem = schedules[today]!.firstWhere(
              (s) => s.id == sId,
              orElse: () => schedules[today]!.first,
            );
            if (sItem.id == sId) sItem.done = true;
          }
        }
        final coreIdx = coreTasks.indexWhere(
          (ct) => ct.id.toString() == t.id.toString(),
        );
        if (coreIdx >= 0) {
          coreTasks[coreIdx].done = true;
          coreTasks[coreIdx].completedAt = t.completedAt;
        }
      });
      _saveTasks();
      _saveHabitLogs();
      _saveCoreTasks();
      if (t.category == 'schedule') _saveSchedules();
      // 미뤄둔 할일 리마인드 체크 (완료했는지 여부 반환)
      final bool isDeferredResolved = await _checkAndStoreDeferReminder(t.text);
      final bool isCoreTask = coreTasks.any(
        (ct) => ct.id.toString() == t.id.toString(),
      );

      // 로컬 칭찬 팝업 (Flirt)
      final doneCount = tasks.where((ts) => ts.done).length;
      final totalCount = tasks.length;
      final remainingCount = totalCount - doneCount;
      final progressPct = totalCount > 0 ? doneCount / totalCount : 0.0;

      List<String> pool = [];
      if (isCoreTask || isDeferredResolved) {
        pool = _coach.flirtCore;
      }

      if (pool.isEmpty) {
        if (doneCount == totalCount && totalCount > 0) {
          pool = _coach.flirtAll;
        } else if (doneCount >= 3 && remainingCount <= 2) {
          pool = _coach.flirtFew;
        } else if (doneCount >= 3 && progressPct >= 0.5) {
          pool = _coach.flirtHalf.isNotEmpty
              ? _coach.flirtHalf
              : _coach.flirtOne;
        } else {
          pool = _coach.flirtOne;
        }
      }

      if (pool.isNotEmpty) {
        final randomMsg = pool[Random().nextInt(pool.length)];
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Text(
                  _coach.id.contains('female')
                      ? '💼 '
                      : (_coach.id.contains('male') ? '👔 ' : ''),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    randomMsg,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF1F1F1F),
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.white,
            elevation: 4,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.only(bottom: 108, left: 20, right: 20),
          ),
        );
      }
    }
    HapticFeedback.lightImpact();
  }

  Future<bool> _checkAndStoreDeferReminder(String completedTaskText) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pendingDeferTask');
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final deferredTaskName = data['taskName'] as String? ?? '';
      if (deferredTaskName.isNotEmpty) {
        if (completedTaskText == deferredTaskName) {
          // 미루던 일을 마침내 완료함!
          await prefs.remove('pendingDeferTask');
          return true;
        } else {
          // 다른 일을 완료했으므로 리마인더로 남김
          await prefs.setString(
            'pendingDeferReminder',
            jsonEncode({'taskName': deferredTaskName}),
          );
          await prefs.remove('pendingDeferTask');
        }
      }
    } catch (e) {
      await prefs.remove('pendingDeferTask');
    }
    return false;
  }

  Future<void> _showTaskDeleteOptions(TaskItem task) async {
    final isHabitTask = task.isHabit || task.habitId != null;
    final actions = <({String label, String value})>[
      (label: '삭제하기', value: 'delete'),
      (
        label: isHabitTask ? '오늘은 쉬기' : '다른 날짜로 옮기기',
        value: isHabitTask ? 'skip' : 'move',
      ),
      (label: '취소', value: 'cancel'),
    ];
    String selectedAction = actions.first.value;
    final action = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.48),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 56),
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHabitTask ? '이 습관 할 일을 어떻게 할까요?' : '이 일정을 삭제할까요?',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    const SizedBox(height: 18),
                    ...List.generate(actions.length, (index) {
                      final item = actions[index];
                      return Column(
                        children: [
                          _buildTaskDialogOption(
                            label: item.label,
                            isSelected: selectedAction == item.value,
                            onTap: () => setDialogState(
                              () => selectedAction = item.value,
                            ),
                          ),
                          if (index != actions.length - 1)
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFEDEDF4),
                            ),
                        ],
                      );
                    }),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx, 'cancel'),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF4F4F7),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '취소',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF3D3A4E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(ctx, selectedAction),
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _coach.accentColor,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Text(
                                '확인',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (action == 'delete') {
      _deleteTaskPermanently(task);
    } else if (action == 'skip') {
      _skipHabitToday(task);
    } else if (action == 'move') {
      _showMoveTaskModal(task);
    }
  }

  Widget _buildTaskDialogOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: const Color(0xFF8B7CFF),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskActionOption({
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(
          children: [
            const Icon(
              Icons.radio_button_unchecked,
              size: 20,
              color: Color(0xFF8B7CFF),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTaskPermanently(TaskItem task) {
    setState(() {
      tasks.removeWhere((t) => t.id.toString() == task.id.toString());
      coreTasks.removeWhere((t) => t.id.toString() == task.id.toString());

      if (task.category == 'schedule') {
        final today = _getTodayStr();
        final scheduleId = task.id.toString().replaceAll('schedule_', '');
        final daySchedules = schedules[today];
        daySchedules?.removeWhere((s) => s.id == scheduleId);
        if (daySchedules != null && daySchedules.isEmpty) {
          schedules.remove(today);
        }
      }
    });
    _saveTasks();
    _saveCoreTasks();
    if (task.category == 'schedule') _saveSchedules();
  }

  void _skipHabitToday(TaskItem task) {
    if (task.habitId == null) return;

    final today = _getTodayStr();
    setState(() {
      habitLogs[task.habitId!] ??= {};
      habitLogs[task.habitId!]![today] = {
        'done': false,
        'status': 'skipped',
        'skippedAt': DateTime.now().toIso8601String(),
      };
      tasks.removeWhere((t) => t.id.toString() == task.id.toString());
      coreTasks.removeWhere((t) => t.id.toString() == task.id.toString());
    });

    _saveHabitLogs();
    _saveTasks();
    _saveCoreTasks();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('오늘은 쉬기로 표시했어요.')));
  }

  Future<void> _recordDeferredTaskIfLate(TaskItem task) async {
    final now = DateTime.now();
    if (now.hour >= 21) {
      final prefs = await SharedPreferences.getInstance();
      final rawDeferred = prefs.getString('nyang_deferred_tasks_today');
      List<dynamic> deferredList = [];
      if (rawDeferred != null) {
        try {
          deferredList = jsonDecode(rawDeferred);
        } catch (_) {}
      }

      final taskId = task.id.toString();
      if (!deferredList.any((t) => t['id'].toString() == taskId)) {
        deferredList.add({
          'id': taskId,
          'text': task.text,
          'category': task.category,
          'done': false,
          'deferred': true,
        });
        await prefs.setString(
          'nyang_deferred_tasks_today',
          jsonEncode(deferredList),
        );
      }
    }
  }

  void _removeTaskForMove(TaskItem task) {
    _recordDeferredTaskIfLate(task);
    tasks.removeWhere((t) => t.id.toString() == task.id.toString());
    coreTasks.removeWhere((t) => t.id.toString() == task.id.toString());

    if (task.category == 'schedule') {
      final today = _getTodayStr();
      final scheduleId = task.id.toString().replaceAll('schedule_', '');
      final daySchedules = schedules[today];
      daySchedules?.removeWhere((s) => s.id == scheduleId);
      if (daySchedules != null && daySchedules.isEmpty) {
        schedules.remove(today);
      }
    }
  }

  void _showMoveTaskModal(
    TaskItem task, {
    DateTime? fixedDay,
    bool hideCalendar = false,
    String title = '다른 날짜로 옮기기',
    VoidCallback? onMoved,
  }) {
    DateTime selectedDay =
        fixedDay ?? DateTime.now().add(const Duration(days: 1));
    DateTime focusedDay = selectedDay;
    String moveTimeType = _timeTypeFromTask(task);
    TimeOfDay? moveStartTime = _parseStoredTime(task.timeStart);
    TimeOfDay? moveEndTime = _parseStoredTime(task.timeEnd);
    String? moveDuration = task.duration;
    bool moveReminderEnabled =
        _isCoreReminderEnabledGlobally &&
        task.category == 'schedule' &&
        task.isReminderEnabled;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.9,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  22,
                  20,
                  MediaQuery.of(ctx).viewInsets.bottom + 24,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.text,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (!hideCalendar) ...[
                      TableCalendar(
                        locale: 'ko_KR',
                        calendarFormat: CalendarFormat.month,
                        rowHeight: 34,
                        daysOfWeekHeight: 24,
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2050, 12, 31),
                        focusedDay: focusedDay,
                        selectedDayPredicate: (day) =>
                            isSameDay(selectedDay, day),
                        onDaySelected: (day, focused) {
                          setModalState(() {
                            selectedDay = day;
                            focusedDay = focused;
                          });
                        },
                        eventLoader: (day) => schedules[_dateKey(day)] ?? [],
                        calendarStyle: CalendarStyle(
                          markerSize: 4,
                          markerDecoration: BoxDecoration(
                            color: _coach.accentColor,
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: BoxDecoration(
                            color: _coach.accentColor,
                            shape: BoxShape.circle,
                          ),
                          todayDecoration: BoxDecoration(
                            color: _coach.accentColor.withOpacity(0.3),
                            shape: BoxShape.circle,
                          ),
                          defaultTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                          ),
                          weekendTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: const Color(0xFFE05C5C),
                          ),
                          outsideTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: const Color(0xFFCCCCCC),
                          ),
                          selectedTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          todayTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            color: const Color(0xFF3D3A4E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        daysOfWeekStyle: DaysOfWeekStyle(
                          weekdayStyle: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: const Color(0xFF9CA3AF),
                          ),
                          weekendStyle: GoogleFonts.notoSansKr(
                            fontSize: 11,
                            color: const Color(0xFFE05C5C),
                          ),
                        ),
                        headerStyle: HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                          titleTextStyle: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _buildMoveTimeControls(
                      timeType: moveTimeType,
                      startTime: moveStartTime,
                      endTime: moveEndTime,
                      duration: moveDuration,
                      setTimeType: (value) =>
                          setModalState(() => moveTimeType = value),
                      setStartTime: (value) =>
                          setModalState(() => moveStartTime = value),
                      setEndTime: (value) =>
                          setModalState(() => moveEndTime = value),
                      setDuration: (value) =>
                          setModalState(() => moveDuration = value),
                    ),
                    if (moveTimeType == 'single' || moveTimeType == 'range')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () async {
                            final enabled =
                                await _checkCoreReminderEnabledGlobally();
                            if (!enabled) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('설정에서 일정 알람을 켜주세요.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            setModalState(
                              () => moveReminderEnabled = !moveReminderEnabled,
                            );
                          },
                          child: Row(
                            children: [
                              Icon(
                                !_isCoreReminderEnabledGlobally
                                    ? Icons.notifications_off
                                    : (moveReminderEnabled
                                          ? Icons.notifications_active
                                          : Icons.notifications_none_outlined),
                                size: 18,
                                color:
                                    (_isCoreReminderEnabledGlobally &&
                                        moveReminderEnabled)
                                    ? _coach.accentColor
                                    : const Color(0xFFB0B0C8),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                !_isCoreReminderEnabledGlobally
                                    ? '알림 꺼짐'
                                    : (moveReminderEnabled
                                          ? '알림 켜짐 (자동 추가)'
                                          : '알림 끄기'),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  color:
                                      (_isCoreReminderEnabledGlobally &&
                                          moveReminderEnabled)
                                      ? _coach.accentColor
                                      : const Color(0xFFB0B0C8),
                                  fontWeight:
                                      (_isCoreReminderEnabledGlobally &&
                                          moveReminderEnabled)
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        final entry = _scheduleFromMovedTask(
                          task,
                          moveTimeType,
                          moveStartTime,
                          moveEndTime,
                          moveDuration,
                          moveReminderEnabled,
                        );
                        final dateStr = _dateKey(selectedDay);
                        setState(() {
                          _removeTaskForMove(task);
                          schedules.putIfAbsent(dateStr, () => []);
                          schedules[dateStr]!.add(entry);
                          _calSelectedDay = selectedDay;
                          _calFocusedDay = focusedDay;
                        });
                        _saveTasks();
                        _saveCoreTasks();
                        _saveSchedules();
                        AnalyticsService.logFeatureUsage('move_task');
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${selectedDay.month}월 ${selectedDay.day}일 일정으로 옮겼어요.',
                            ),
                          ),
                        );
                        if (onMoved != null) {
                          Future.delayed(const Duration(milliseconds: 220), () {
                            if (mounted) onMoved();
                          });
                        }
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _coach.accentColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          '옮기기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── addGoal (웹앱 그대로) ─────────────────────────────────
  void _addGoal(String type, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final goal = GoalItem(
      id:
          DateTime.now().millisecondsSinceEpoch +
          DateTime.now().microsecond % 1000,
      text: trimmed,
    );
    setState(() {
      if (type == 'week')
        weekGoals.add(goal);
      else
        monthGoals.add(goal);
    });
    _saveGoals(type);
    if (type == 'week')
      _weekInputCtrl.clear();
    else
      _monthInputCtrl.clear();
  }

  // ── toggleGoal (웹앱 그대로) ──────────────────────────────
  void _toggleGoal(String type, int id) {
    final goals = type == 'week' ? weekGoals : monthGoals;
    final g = goals.firstWhere((g) => g.id == id);
    setState(() => g.done = !g.done);
    _saveGoals(type);
    HapticFeedback.lightImpact();
  }

  // ── deleteGoal (웹앱 그대로) ──────────────────────────────
  void _deleteGoal(String type, int id) {
    setState(() {
      if (type == 'week')
        weekGoals.removeWhere((g) => g.id == id);
      else
        monthGoals.removeWhere((g) => g.id == id);
    });
    _saveGoals(type);
  }

  // ── 진행률 계산 ───────────────────────────────────────────
  int get _doneTasks {
    return tasks.where((t) => t.done).length;
  }
  int get _totalTasks {
    return tasks.length;
  }
  double get _progressPct => _totalTasks > 0 ? _doneTasks / _totalTasks : 0.0;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkCoreReminderEnabledGlobally(),
    );
    final bool isVacation = vacationInfo != null;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: isVacation ? Colors.transparent : Colors.white,
      body: Container(
        decoration: isVacation
            ? const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/vacation_bg.jpg'),
                  fit: BoxFit.cover,
                ),
              )
            : null,
        child: Container(
          color: isVacation
              ? Colors.white.withOpacity(0.85)
              : Colors.transparent,
          child: Column(
            children: [
              // 탭바 (오늘 / 목표 / 일정 / 습관)
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildTodayTab(),
                    _buildGoalTab(),
                    _buildScheduleTab(),
                    _buildHabitTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 핵심 할 일 (Core Tasks) 영역 ───────────────────────────
  Widget _buildCoreSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _coach.accentColor.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: _coach.accentColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '오늘의 핵심',
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              GestureDetector(
                onTap: _showCoreSelectionModal,
                child: Text(
                  '설정하기',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _coach.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (coreTasks.isEmpty)
            Text(
              '아직 핵심이 없어요.\n할 일 목록에서 오늘의 핵심을 선택해주세요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: const Color(0xFFA0A0B0),
                height: 1.5,
              ),
            )
          else ...[
            // 항상 1위만 표시
            _buildCoreItem(0),
            // 나머지는 접기/펼치기
            if (coreTasks.length > 1) ...[
              if (_coreExpanded)
                ...List.generate(
                  coreTasks.length - 1,
                  (i) => _buildCoreItem(i + 1),
                )
              else
                GestureDetector(
                  onTap: () => setState(() => _coreExpanded = true),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 28),
                        Text(
                          '+ 핵심 ${coreTasks.length - 1}개 더',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _coach.accentColor.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_coreExpanded)
                GestureDetector(
                  onTap: () => setState(() => _coreExpanded = false),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const SizedBox(width: 28),
                        Text(
                          '접기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _coach.accentColor.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCoreItem(int idx) {
    final c = coreTasks[idx];
    final isDone = tasks.any((t) => t.text == c.text && t.done);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDone ? const Color(0xFFB0B0C0) : _coach.accentColor,
              shape: BoxShape.circle,
            ),
            child: isDone
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : Text(
                    '${idx + 1}',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              c.text,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDone
                    ? const Color(0xFFB0B0C0)
                    : const Color(0xFF3D3A4E),
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final enabled = await _checkCoreReminderEnabledGlobally();
              if (!enabled || c.time == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      enabled
                          ? '시간이 지정된 일정만 리마인더를 받을 수 있습니다.'
                          : '설정에서 일정 알람을 켜주세요.',
                    ),
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF1A1A2E),
                  ),
                );
                return;
              }
              setState(() {
                c.isReminderEnabled = !c.isReminderEnabled;
              });
              _saveCoreTasks();
              _saveTasks();
            },
            child: Icon(
              (c.isReminderEnabled &&
                      _isCoreReminderEnabledGlobally &&
                      c.time != null)
                  ? Icons.notifications_active
                  : Icons.notifications_off,
              size: 18,
              color:
                  (c.isReminderEnabled &&
                      _isCoreReminderEnabledGlobally &&
                      c.time != null)
                  ? _coach.accentColor
                  : const Color(0xFFA0A0B0).withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              setState(() {
                coreTasks.removeAt(idx);
                if (coreTasks.length <= 1) _coreExpanded = false;
              });
              _saveCoreTasks();
            },
            child: const Icon(Icons.close, size: 16, color: Color(0xFFA0A0B0)),
          ),
        ],
      ),
    );
  }

  void _showCoreSelectionModal() {
    List<String> pendingCore = coreTasks.map((e) => e.id.toString()).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            TaskItem? findPendingTask(String taskId) {
              for (final t in tasks) {
                if (t.id.toString() == taskId) return t;
              }
              for (final t in coreTasks) {
                if (t.id.toString() == taskId) return t;
              }
              return null;
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '핵심 설정하기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFFA0A0B0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '오늘의 핵심 목표를 설정해보세요. (최대 3개)',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        if (pendingCore.isNotEmpty) ...[
                          Text(
                            '선택한 핵심 순서',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '끌어서 우선순위를 바꿀 수 있어요.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFA0A0B0),
                            ),
                          ),
                          const SizedBox(height: 10),
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            buildDefaultDragHandles: false,
                            itemCount: pendingCore.length,
                            onReorder: (oldIndex, newIndex) {
                              setModalState(() {
                                if (oldIndex < newIndex) newIndex -= 1;
                                final item = pendingCore.removeAt(oldIndex);
                                pendingCore.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (ctx, i) {
                              final taskId = pendingCore[i];
                              final task = findPendingTask(taskId);
                              return Container(
                                key: ValueKey('pending_core_$taskId'),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _coach.accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _coach.accentColor.withOpacity(0.45),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    ReorderableDragStartListener(
                                      index: i,
                                      child: Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        child: Icon(
                                          Icons.drag_handle,
                                          color: _coach.accentColor,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 24,
                                      height: 24,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _coach.accentColor,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        task?.text ?? taskId,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: const Color(0xFF3D3A4E),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          pendingCore.removeAt(i);
                                        });
                                      },
                                      child: const Icon(
                                        Icons.close,
                                        size: 18,
                                        color: Color(0xFFA0A0B0),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 14),
                        ],
                        ...List.generate(tasks.length, (i) {
                          final t = tasks[i];
                          final isSelected = pendingCore.contains(
                            t.id.toString(),
                          );
                          final coreIdx = pendingCore.indexOf(t.id.toString());
                          return GestureDetector(
                            onTap: () {
                              setModalState(() {
                                if (isSelected) {
                                  pendingCore.remove(t.id.toString());
                                } else {
                                  if (pendingCore.length >= 3) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          '오늘의 핵심은 최대 3개까지만 고를 수 있어요.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  pendingCore.add(t.id.toString());
                                }
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _coach.accentColor.withOpacity(0.1)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? _coach.accentColor
                                      : const Color(0xFFE8E3F8),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 22,
                                    height: 22,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _coach.accentColor
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isSelected
                                            ? _coach.accentColor
                                            : const Color(0xFFDDD6FE),
                                      ),
                                    ),
                                    child: isSelected
                                        ? Text(
                                            '${coreIdx + 1}',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      t.text,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: const Color(0xFF3D3A4E),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    GestureDetector(
                                      onTap: () async {
                                        final enabled =
                                            await _checkCoreReminderEnabledGlobally();
                                        if (!enabled || t.time == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                enabled
                                                    ? '시간이 지정된 일정만 리마인더를 받을 수 있습니다.'
                                                    : '설정에서 일정 알람을 켜주세요.',
                                              ),
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                              backgroundColor: const Color(
                                                0xFF1A1A2E,
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        setModalState(() {
                                          t.isReminderEnabled =
                                              !t.isReminderEnabled;
                                        });
                                        setState(() {});
                                        _saveTasks();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8.0,
                                        ),
                                        child: Icon(
                                          (t.isReminderEnabled &&
                                                  _isCoreReminderEnabledGlobally &&
                                                  t.time != null)
                                              ? Icons.notifications_active
                                              : Icons.notifications_off,
                                          size: 20,
                                          color:
                                              (t.isReminderEnabled &&
                                                  _isCoreReminderEnabledGlobally &&
                                                  t.time != null)
                                              ? _coach.accentColor
                                              : const Color(
                                                  0xFFA0A0B0,
                                                ).withOpacity(0.5),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      setState(() {
                        coreTasks = pendingCore.map((pid) {
                          final existing = coreTasks.firstWhere(
                            (c) => c.id.toString() == pid,
                            orElse: () =>
                                tasks.firstWhere((t) => t.id.toString() == pid),
                          );
                          return TaskItem(
                            id: existing.id,
                            text: existing.text,
                            category: existing.category,
                            time: existing.time,
                            duration: existing.duration,
                            timeStart: existing.timeStart,
                            timeEnd: existing.timeEnd,
                            isHabit: existing.isHabit,
                            habitId: existing.habitId,
                            done: existing.done,
                            isReminderEnabled: existing.isReminderEnabled,
                            createdAt: DateTime.now().toIso8601String(),
                          );
                        }).toList();
                      });
                      _saveCoreTasks();
                      Navigator.pop(ctx);

                      // 비서 코치 전용 반응 메시지 제거됨
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coach.accentColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '핵심으로 설정',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── 탭바 ─────────────────────────────────────────────────
  Widget _buildTabBar() {
    final isVacation = vacationInfo != null;
    const tabs = [
      {'icon': Icons.assignment_outlined, 'label': '오늘'},
      {'icon': Icons.track_changes_outlined, 'label': '목표'},
      {'icon': Icons.calendar_month_outlined, 'label': '일정'},
      {'icon': Icons.wb_sunny_outlined, 'label': '습관'},
    ];
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: _coach.accentColor,
        unselectedLabelColor: const Color(0xFFA0A0B0),
        indicatorColor: _coach.accentColor,
        indicatorWeight: 2.5,
        labelStyle: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelStyle: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        tabs: tabs
            .map(
              (t) => Tab(
                icon: Icon(t['icon'] as IconData, size: 20),
                text: t['label'] as String,
                iconMargin: const EdgeInsets.only(bottom: 2),
              ),
            )
            .toList(),
      ),
    );
  }

  // ── 오늘 탭 ──────────────────────────────────────────────
  Widget _buildTodayTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: Column(
        children: [
          // 헤더 (날짜 + 진행률)
          _buildTodayHeader(),
          if (isVacation)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🌙', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 12),
                    Text(
                      '오늘은 휴무 중이에요.\n푹 쉬고 재충전하세요!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: const Color(0xFFA0A0B0),
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // 핵심 할 일 (Core Tasks)
            _buildCoreSection(),
            // 태스크 목록
            Expanded(child: _buildTaskList()),
            // 입력 영역
            _buildTodayInput(),
          ],
        ],
      ),
    );
  }

  Widget _buildTodayHeader() {
    final now = DateTime.now();
    final months = [
      '1월',
      '2월',
      '3월',
      '4월',
      '5월',
      '6월',
      '7월',
      '8월',
      '9월',
      '10월',
      '11월',
      '12월',
    ];
    final days = ['일', '월', '화', '수', '목', '금', '토'];
    final dateStr =
        '${now.year}년 ${months[now.month - 1]} ${now.day}일 (${days[now.weekday % 7]})';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            dateStr,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFA0A0B0),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // 고양이 아이콘
                  const Icon(Icons.pets, color: Colors.grey, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '오늘의 할 일',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: _showVacationModal,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8E3F8)),
                  ),
                  child: Text(
                    '휴무 설정',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B5EA8),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 진행률 바
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progressPct,
                    backgroundColor: const Color(0xFFE8E3F8),
                    valueColor: AlwaysStoppedAnimation(_coach.accentColor),
                    minHeight: 7,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${(_progressPct * 100).round()}%',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF6B5EA8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 휴무 설정 (Vacation) 모달 ──────────────────────────────
  void _showVacationModal() {
    String currentScreen = 'selection';
    String selectedStyle = vacationInfo?['restType'] ?? 'quiet';

    // Range State
    DateTime? startDate;
    DateTime? endDate;

    // Regular State
    List<int> selectedDays = [];
    if (vacationInfo != null && vacationInfo!['type'] == 'regular') {
      selectedDays = List<int>.from(vacationInfo!['days'] ?? []);
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget content;

            if (currentScreen == 'range') {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setModalState(() => currentScreen = 'selection'),
                        child: const Icon(Icons.arrow_back_ios, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '며칠 동안 쉬기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '휴무 기간을 선택해주세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: startDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null)
                              setModalState(() => startDate = date);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE8E3F8),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              startDate != null
                                  ? '${startDate!.year}-${startDate!.month.toString().padLeft(2, '0')}-${startDate!.day.toString().padLeft(2, '0')}'
                                  : '시작일',
                              style: GoogleFonts.notoSansKr(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('~'),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  endDate ?? startDate ?? DateTime.now(),
                              firstDate: startDate ?? DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null)
                              setModalState(() => endDate = date);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE8E3F8),
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              endDate != null
                                  ? '${endDate!.year}-${endDate!.month.toString().padLeft(2, '0')}-${endDate!.day.toString().padLeft(2, '0')}'
                                  : '종료일',
                              style: GoogleFonts.notoSansKr(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      if (startDate == null || endDate == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('시작일과 종료일을 선택해주세요.')),
                        );
                        return;
                      }
                      if (startDate!.isAfter(endDate!)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('시작일이 종료일보다 늦을 수 없어요.')),
                        );
                        return;
                      }
                      setState(() {
                        vacationInfo = {
                          'restType': selectedStyle,
                          'type': 'range',
                          'start': startDate!.toIso8601String(),
                          'end': endDate!.toIso8601String(),
                        };
                      });
                      _saveVacation();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('휴무 설정이 완료되었습니다.')),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coach.accentColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '기간 설정 완료',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else if (currentScreen == 'regular') {
              final days = ['일', '월', '화', '수', '목', '금', '토'];
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () =>
                            setModalState(() => currentScreen = 'selection'),
                        child: const Icon(Icons.arrow_back_ios, size: 18),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '정기 휴무 설정',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '매주 쉴 요일을 선택해주세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(7, (i) {
                      final isSel = selectedDays.contains(i);
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            if (isSel)
                              selectedDays.remove(i);
                            else
                              selectedDays.add(i);
                          });
                        },
                        child: Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSel ? _coach.accentColor : Colors.white,
                            border: Border.all(
                              color: isSel
                                  ? _coach.accentColor
                                  : const Color(0xFFE8E3F8),
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            days[i],
                            style: TextStyle(
                              color: isSel
                                  ? Colors.white
                                  : const Color(0xFFA0A0B0),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      if (selectedDays.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('최소 하루 이상의 요일을 선택해주세요.'),
                          ),
                        );
                        return;
                      }
                      setState(() {
                        vacationInfo = {
                          'restType': selectedStyle,
                          'type': 'regular',
                          'days': selectedDays,
                        };
                      });
                      _saveVacation();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('휴무 설정이 완료되었습니다.')),
                      );
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coach.accentColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '정기 휴무 설정 완료',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            } else {
              content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🌙 휴무 설정',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '오늘, 나를 위한 휴식을 선택해보세요.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              color: const Color(0xFFA0A0B0),
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: const Icon(
                          Icons.close,
                          color: Color(0xFFA0A0B0),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // 스타일 선택
                  Text(
                    '✨ 쉬는 스타일 선택',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedStyle = 'quiet'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: selectedStyle == 'quiet'
                                  ? const Color(0xFFF5F3FF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedStyle == 'quiet'
                                    ? const Color(0xFF8B7CFF)
                                    : const Color(0xFFE8E3F8),
                              ),
                            ),
                            child: Column(
                              children: [
                                Image.asset(
                                  'assets/images/rest_quiet.png',
                                  width: 48,
                                  height: 48,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '조용히 쉬기',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF3D3A4E),
                                  ),
                                ),
                                Text(
                                  '방해 없이 푹 쉬어요',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: const Color(0xFFA0A0B0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setModalState(() => selectedStyle = 'helper'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            decoration: BoxDecoration(
                              color: selectedStyle == 'helper'
                                  ? const Color(0xFFF5F3FF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: selectedStyle == 'helper'
                                    ? const Color(0xFF8B7CFF)
                                    : const Color(0xFFE8E3F8),
                              ),
                            ),
                            child: Column(
                              children: [
                                Image.asset(
                                  'assets/images/rest_helper.png',
                                  width: 48,
                                  height: 48,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '회복 도우미',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF3D3A4E),
                                  ),
                                ),
                                Text(
                                  '가벼운 힐링 케어',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: const Color(0xFFA0A0B0),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  // 휴식 기간 선택
                  Text(
                    '휴식 기간 선택',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildVacationOption(
                    icon: Icons.nightlight_round,
                    title: '오늘만 쉬기',
                    desc: '하루 동안 모든 알림을 잠시 멈춰요',
                    isPrimary: true,
                    onTap: () {
                      setState(() {
                        vacationInfo = {
                          'restType': selectedStyle,
                          'type': 'today',
                          'date': _getTodayStr(),
                        };
                      });
                      _saveVacation();
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('오늘 휴무가 설정되었습니다.')),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildVacationOption(
                    icon: Icons.calendar_today_outlined,
                    title: '며칠 동안 쉬기',
                    desc: '연속으로 며칠간 휴무를 설정해요',
                    isPrimary: false,
                    onTap: () {
                      setModalState(() => currentScreen = 'range');
                    },
                  ),
                  const SizedBox(height: 8),
                  _buildVacationOption(
                    icon: Icons.autorenew_outlined,
                    title: '정기 휴무 (특정 요일마다)',
                    desc: '매주 정해진 요일에 자동으로 쉬어요',
                    isPrimary: false,
                    onTap: () {
                      setModalState(() => currentScreen = 'regular');
                    },
                  ),
                  const SizedBox(height: 24),
                  if (vacationInfo != null) ...[
                    GestureDetector(
                      onTap: () {
                        setState(() => vacationInfo = null);
                        _saveVacation();
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('휴무 설정이 해제되었습니다.')),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.5),
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '휴무 설정 해제',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '취소',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFA0A0B0),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  child: content,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVacationOption({
    required IconData icon,
    required String title,
    required String desc,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF8B7CFF) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isPrimary ? null : Border.all(color: const Color(0xFFE8E3F8)),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: isPrimary ? Colors.white : const Color(0xFFA0A0B0),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isPrimary ? Colors.white : const Color(0xFF3D3A4E),
                    ),
                  ),
                  Text(
                    desc,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      color: isPrimary
                          ? Colors.white.withOpacity(0.8)
                          : const Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isPrimary ? Colors.white : const Color(0xFFA0A0B0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList() {
    final todayMilestones = _getMilestonesForDay(DateTime.now());
    final milestoneTasks = todayMilestones.map((mv) {
      final m = mv.milestone;
      final v = mv.vision;
      final id = 'milestone_${v.name}_${m.text}';
      return TaskItem(
        id: id,
        text: m.text,
        category: 'today',
        done: m.done,
        createdAt: m.date ?? DateTime.now().toIso8601String(),
      );
    }).toList();

    final combinedTasks = [...tasks, ...milestoneTasks];

    if (combinedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets, color: Colors.grey, size: 40),
            const SizedBox(height: 12),
            Text(
              '코치와 대화하면\n여기에 할 일이 추가돼요!',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: const Color(0xFFA0A0B0),
                height: 1.6,
              ),
            ),
          ],
        ),
      );
    }

    final sortedTasks = List<TaskItem>.from(combinedTasks)
      ..sort((a, b) {
        if (a.done && !b.done) return 1;
        if (!a.done && b.done) return -1;

        final aIsMilestone = a.id.toString().startsWith('milestone_');
        final bIsMilestone = b.id.toString().startsWith('milestone_');
        if (aIsMilestone && !bIsMilestone) return -1;
        if (!aIsMilestone && bIsMilestone) return 1;

        return 0;
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      itemCount: sortedTasks.length,
      itemBuilder: (ctx, i) => _buildTaskItem(sortedTasks[i]),
    );
  }

  void _showEditItemModal(dynamic item, VoidCallback onSave) {
    final textCtrl = TextEditingController(text: item.text);

    String mTimeType = 'none';
    TimeOfDay? mStartTime;
    TimeOfDay? mEndTime;
    String? mDuration;
    bool mReminderEnabled =
        _isCoreReminderEnabledGlobally &&
        ((item is ScheduleItem)
            ? item.isReminderEnabled
            : (item is TaskItem)
            ? item.isReminderEnabled
            : false);
    final bool isScheduleItem = item is ScheduleItem;

    if (item.timeStart != null && item.timeEnd != null) {
      mTimeType = 'range';
      final partsS = item.timeStart!.split(':');
      if (partsS.length == 2)
        mStartTime = TimeOfDay(
          hour: int.tryParse(partsS[0]) ?? 0,
          minute: int.tryParse(partsS[1]) ?? 0,
        );
      final partsE = item.timeEnd!.split(':');
      if (partsE.length == 2)
        mEndTime = TimeOfDay(
          hour: int.tryParse(partsE[0]) ?? 0,
          minute: int.tryParse(partsE[1]) ?? 0,
        );
    } else if (item.timeStart != null) {
      mTimeType = 'single';
      final parts = item.timeStart!.split(':');
      if (parts.length == 2)
        mStartTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 0,
          minute: int.tryParse(parts[1]) ?? 0,
        );
    } else if (item.duration != null) {
      mTimeType = 'duration';
      mDuration = item.duration;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '수정하기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  if (item != null) ...[
                    Builder(
                      builder: (context) {
                        final mInfo = _getMilestoneInfoForTask(item);
                        if (mInfo != null) {
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx); // Close edit modal
                              if (mInfo.isMilestoneSelf) {
                                _showVisionModal(mInfo.vision);
                              } else {
                                _showMemoDialog(context, mInfo.milestone, (fn) => setState(fn));
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 8, bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0EFFF),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFD8D0FA),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.flag,
                                    color: Color(0xFF8B7CFF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          color: const Color(0xFF5A50E6),
                                        ),
                                        children: [
                                          TextSpan(
                                            text: mInfo.isMilestoneSelf ? '연동된 마일스톤: ' : '메모장의 실행 목록: ',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          TextSpan(
                                            text: '${mInfo.visionName} > ${mInfo.milestoneText}',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF8B7CFF),
                                    size: 16,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: TextField(
                      controller: textCtrl,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: const Color(0xFF3D3A4E),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: ['single', 'range', 'duration'].map((t) {
                      final labels = {
                        'single': '특정 시간',
                        'range': '시간 범위',
                        'duration': '소요 시간',
                      };
                      final isActive = mTimeType == t;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setModalState(() {
                            mTimeType = mTimeType == t ? 'none' : t;
                            mReminderEnabled = false;
                            mStartTime = null;
                            mEndTime = null;
                            if (t != 'duration') mDuration = null;
                          }),
                          child: Container(
                            margin: EdgeInsets.only(
                              right: t == 'duration' ? 0 : 6,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _coach.accentColor.withOpacity(0.08)
                                  : Colors.white,
                              border: Border.all(
                                color: isActive
                                    ? _coach.accentColor
                                    : const Color(0xFFE5E7EB),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              labels[t]!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? _coach.accentColor
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (mTimeType == 'single' || mTimeType == 'range')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Text(
                            mTimeType == 'range' ? '시작: ' : '시간: ',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: mStartTime ?? TimeOfDay.now(),
                              );
                              if (t != null) {
                                setModalState(() {
                                  mStartTime = t;
                                  mReminderEnabled =
                                      _isCoreReminderEnabledGlobally;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                mStartTime != null
                                    ? _formatTime(mStartTime!)
                                    : '선택',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  color: mStartTime != null
                                      ? _coach.accentColor
                                      : const Color(0xFFA0A0B0),
                                ),
                              ),
                            ),
                          ),
                          if (mTimeType == 'range') ...[
                            const SizedBox(width: 8),
                            Text(
                              '~ 종료: ',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: mEndTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setModalState(() => mEndTime = t);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  mEndTime != null
                                      ? _formatTime(mEndTime!)
                                      : '선택',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: mEndTime != null
                                        ? _coach.accentColor
                                        : const Color(0xFFA0A0B0),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          if (isScheduleItem || item is TaskItem)
                            GestureDetector(
                              onTap: () async {
                                final enabled =
                                    await _checkCoreReminderEnabledGlobally();
                                if (!enabled) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('설정에서 일정 알람을 켜주세요.'),
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                if (mStartTime == null) {
                                  _showSelectTimeBeforeReminderSnackBar();
                                  return;
                                }
                                setModalState(
                                  () => mReminderEnabled = !mReminderEnabled,
                                );
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color:
                                      _resolvedTimeReminderEnabled(
                                        mTimeType,
                                        mStartTime,
                                        mReminderEnabled,
                                      )
                                      ? _coach.accentColor.withOpacity(0.12)
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  !_isCoreReminderEnabledGlobally
                                      ? Icons.notifications_off
                                      : (_resolvedTimeReminderEnabled(
                                              mTimeType,
                                              mStartTime,
                                              mReminderEnabled,
                                            )
                                            ? Icons.notifications_active
                                            : Icons.notifications_off),
                                  size: 18,
                                  color:
                                      _resolvedTimeReminderEnabled(
                                        mTimeType,
                                        mStartTime,
                                        mReminderEnabled,
                                      )
                                      ? _coach.accentColor
                                      : const Color(0xFFB0B0C8),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (mTimeType == 'duration')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            [
                              '10분',
                              '15분',
                              '30분',
                              '1시간',
                              '2시간',
                              '3시간',
                              '4시간+',
                            ].map((d) {
                              final isActive = mDuration == d;
                              return GestureDetector(
                                onTap: () => setModalState(() => mDuration = d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFFFDF2F8)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isActive
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    d,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: isActive
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  const SizedBox(height: 16),
                  // 알림 토글 - ScheduleItem이고, 글로벌 리마인더 ON이고, 시작 시간 있을 때
                  if (isScheduleItem &&
                      _isCoreReminderEnabledGlobally &&
                      (mTimeType == 'single' || mTimeType == 'range') &&
                      mStartTime != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () => setModalState(
                          () => mReminderEnabled = !mReminderEnabled,
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: mReminderEnabled
                                    ? _coach.accentColor.withOpacity(0.12)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                mReminderEnabled
                                    ? Icons.notifications_active
                                    : Icons.notifications_none_outlined,
                                size: 18,
                                color: mReminderEnabled
                                    ? _coach.accentColor
                                    : const Color(0xFFB0B0C8),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              mReminderEnabled ? '알림 켜짐 (핵심에 자동 추가)' : '알림 끄기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                color: mReminderEnabled
                                    ? _coach.accentColor
                                    : const Color(0xFFB0B0C8),
                                fontWeight: mReminderEnabled
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  GestureDetector(
                    onTap: () {
                      final text = textCtrl.text.trim();
                      if (text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('내용을 입력해주세요.')),
                        );
                        return;
                      }

                      item.text = text;
                      item.time = null;
                      item.timeStart = null;
                      item.timeEnd = null;
                      item.duration = null;

                      if (mTimeType == 'single' && mStartTime != null) {
                        item.time = _formatTime(mStartTime!);
                        item.timeStart =
                            '${mStartTime!.hour.toString().padLeft(2, '0')}:${mStartTime!.minute.toString().padLeft(2, '0')}';
                      } else if (mTimeType == 'range' && mStartTime != null) {
                        item.time = _formatTime(mStartTime!);
                        item.timeStart =
                            '${mStartTime!.hour.toString().padLeft(2, '0')}:${mStartTime!.minute.toString().padLeft(2, '0')}';
                        if (mEndTime != null) {
                          item.time += ' ~ ${_formatTime(mEndTime!)}';
                          item.timeEnd =
                              '${mEndTime!.hour.toString().padLeft(2, '0')}:${mEndTime!.minute.toString().padLeft(2, '0')}';
                        }
                      } else if (mTimeType == 'duration' && mDuration != null) {
                        item.duration = mDuration;
                      }

                      if (isScheduleItem) {
                        item.isReminderEnabled = _resolvedTimeReminderEnabled(
                          mTimeType,
                          mStartTime,
                          mReminderEnabled,
                        );
                      } else if (item is TaskItem) {
                        item.isReminderEnabled = _resolvedTimeReminderEnabled(
                          mTimeType,
                          mStartTime,
                          mReminderEnabled,
                        );
                      }

                      onSave();
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coach.accentColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '저장하기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTaskItem(TaskItem t) {
    final milestoneInfo = _getMilestoneInfoForTask(t);
    final isMilestone = milestoneInfo != null;
    final displayTime = _displayTimeFromStored(
      time: t.time,
      timeStart: t.timeStart,
      timeEnd: t.timeEnd,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: t.done ? Border.all(color: const Color(0xFFE8E3F8)) : null,
        boxShadow: t.done
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 체크버튼
          GestureDetector(
            onTap: () => _toggleTask(t.id),
            child: Container(
              width: 48,
              height: 52,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: t.done
                      ? (isMilestone ? const Color(0xFF5AD7B0) : _coach.accentColor)
                      : Colors.transparent,
                  border: Border.all(
                    color: t.done
                        ? (isMilestone ? const Color(0xFF5AD7B0) : _coach.accentColor)
                        : (isMilestone ? const Color(0xFF8B7CFF) : const Color(0xFFD1D5DB)),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: t.done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : (isMilestone
                        ? const Icon(Icons.flag, color: Color(0xFF8B7CFF), size: 12)
                        : null),
              ),
            ),
          ),
          // 텍스트와 메타데이터 (Column으로 세로 배치)
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (t.done) return;
                if (isMilestone) {
                  if (milestoneInfo.isMilestoneSelf) {
                    _showVisionModal(milestoneInfo.vision);
                  } else {
                    _showMemoDialog(context, milestoneInfo.milestone, (fn) => setState(fn));
                  }
                  return;
                }
                _showEditItemModal(t, () {
                  setState(() {
                    final cIdx = coreTasks.indexWhere((ct) => ct.id == t.id);
                    if (cIdx != -1) {
                      coreTasks[cIdx].time = t.time;
                      coreTasks[cIdx].timeStart = t.timeStart;
                      coreTasks[cIdx].timeEnd = t.timeEnd;
                      coreTasks[cIdx].duration = t.duration;
                      coreTasks[cIdx].text = t.text;
                    }
                  });
                  _saveTasks();
                  _saveCoreTasks();
                });
              },
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 마일스톤 태그 및 비전명 표시
                    if (isMilestone) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E0FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              milestoneInfo.isMilestoneSelf ? '마일스톤' : '메모장의 실행 목록',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF5A50E6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              milestoneInfo.visionName,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                color: const Color(0xFF7C6EFA),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    // 할 일 텍스트
                    Text(
                      t.text,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: t.done
                            ? const Color(0xFFA0A0B0)
                            : const Color(0xFF3D3A4E),
                        decoration: t.done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    // 알림 종 아이콘, 시간/소요시간 뱃지, 습관 뱃지 표시
                    if (displayTime != null ||
                        t.duration != null ||
                        t.isHabit ||
                        (t.isReminderEnabled &&
                            _isCoreReminderEnabledGlobally &&
                            displayTime != null)) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 깨끗한 보라색 종 아이콘
                          if (t.isReminderEnabled &&
                              _isCoreReminderEnabledGlobally &&
                              displayTime != null)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.notifications_active,
                                size: 14,
                                color: Color(0xFF8B7CFF),
                              ),
                            ),
                          // 시간/소요시간 뱃지
                          if (displayTime != null || t.duration != null)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: displayTime != null
                                    ? const Color(0xFFF5F3FF)
                                    : const Color(0xFFFDF2F8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                displayTime ?? '⏱ ${t.duration}',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: displayTime != null
                                      ? const Color(0xFF8B7CFF)
                                      : const Color(0xFFDB2777),
                                ),
                              ),
                            ),
                          // 습관 뱃지
                          if (t.isHabit)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _coach.accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '습관',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _coach.accentColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // 삭제 버튼
          GestureDetector(
            onTap: () {
              if (isMilestone && milestoneInfo.isMilestoneSelf) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '마일스톤 일정은 목표 탭의 비전 관리에서 관리할 수 있습니다.',
                    ),
                  ),
                );
                return;
              }
              _showTaskDeleteOptions(t);
            },
            child: Container(
              width: 40,
              height: 52,
              alignment: Alignment.center,
              child: const Icon(
                Icons.close,
                size: 16,
                color: Color(0xFFD1D5DB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayInput() {
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final bottomPadding = keyboardInset > 0
        ? keyboardInset + 18.0
        : max(safeBottom + 16.0, 48.0);

    return Container(
      color: Colors.white,
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(16, 10, 16, bottomPadding),
        child: Column(
          children: [
            // 시간 설정 UI
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: ['single', 'range', 'duration'].map((t) {
                      final labels = {
                        'single': '특정 시간',
                        'range': '시간 범위',
                        'duration': '소요 시간',
                      };
                      final isActive = _todayTimeType == t;
                      final isLast = t == 'duration';
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _todayTimeType = _todayTimeType == t ? 'none' : t;
                            _todayReminderEnabled = false;
                            _todayStartTime = null;
                            _todayEndTime = null;
                            if (t != 'duration') _todayDuration = null;
                          }),
                          child: Container(
                            margin: EdgeInsets.only(right: isLast ? 0 : 6),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? _coach.accentColor.withOpacity(0.08)
                                  : Colors.white,
                              border: Border.all(
                                color: isActive
                                    ? _coach.accentColor
                                    : const Color(0xFFE5E7EB),
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              labels[t]!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive
                                    ? _coach.accentColor
                                    : const Color(0xFF9CA3AF),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_todayTimeType == 'single' || _todayTimeType == 'range')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          Text(
                            _todayTimeType == 'range' ? '시작: ' : '시간: ',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                          GestureDetector(
                            onTap: () async {
                              final t = await showTimePicker(
                                context: context,
                                initialTime: _todayStartTime ?? TimeOfDay.now(),
                              );
                              if (t != null) {
                                setState(() {
                                  _todayStartTime = t;
                                  _todayReminderEnabled =
                                      _isCoreReminderEnabledGlobally;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: const Color(0xFFE5E7EB),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _todayStartTime != null
                                    ? _formatTime(_todayStartTime!)
                                    : '선택',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  color: _todayStartTime != null
                                      ? _coach.accentColor
                                      : const Color(0xFFA0A0B0),
                                ),
                              ),
                            ),
                          ),
                          if (_todayTimeType == 'range') ...[
                            const SizedBox(width: 8),
                            Text(
                              '~',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '종료: ',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final t = await showTimePicker(
                                  context: context,
                                  initialTime: _todayEndTime ?? TimeOfDay.now(),
                                );
                                if (t != null)
                                  setState(() => _todayEndTime = t);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  _todayEndTime != null
                                      ? _formatTime(_todayEndTime!)
                                      : '선택',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: _todayEndTime != null
                                        ? _coach.accentColor
                                        : const Color(0xFFA0A0B0),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final enabled =
                                  await _checkCoreReminderEnabledGlobally();
                              if (!enabled) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('설정에서 일정 알람을 켜주세요.'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              if (_todayStartTime == null) {
                                _showSelectTimeBeforeReminderSnackBar();
                                return;
                              }
                              setState(
                                () => _todayReminderEnabled =
                                    !_todayReminderEnabled,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color:
                                    _resolvedTimeReminderEnabled(
                                      _todayTimeType,
                                      _todayStartTime,
                                      _todayReminderEnabled,
                                    )
                                    ? _coach.accentColor.withOpacity(0.12)
                                    : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                !_isCoreReminderEnabledGlobally
                                    ? Icons.notifications_off
                                    : (_resolvedTimeReminderEnabled(
                                            _todayTimeType,
                                            _todayStartTime,
                                            _todayReminderEnabled,
                                          )
                                          ? Icons.notifications_active
                                          : Icons.notifications_off),
                                size: 18,
                                color:
                                    _resolvedTimeReminderEnabled(
                                      _todayTimeType,
                                      _todayStartTime,
                                      _todayReminderEnabled,
                                    )
                                    ? _coach.accentColor
                                    : const Color(0xFFB0B0C8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_todayTimeType == 'duration')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children:
                            [
                              '10분',
                              '15분',
                              '30분',
                              '1시간',
                              '2시간',
                              '3시간',
                              '4시간+',
                            ].map((d) {
                              final isActive = _todayDuration == d;
                              return GestureDetector(
                                onTap: () => setState(() => _todayDuration = d),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? const Color(0xFFFDF2F8)
                                        : Colors.white,
                                    border: Border.all(
                                      color: isActive
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    d,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: isActive
                                          ? const Color(0xFFDB2777)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                ],
              ),
            ),
            // 직접 추가 입력창
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Material(
                            type: MaterialType.transparency,
                            child: TextField(
                              controller: _todayInputCtrl,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                color: const Color(0xFF3D3A4E),
                              ),
                              decoration: InputDecoration(
                                hintText: '오늘 할 일 직접 추가...',
                                hintStyle: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  color: const Color(0xFFA0A0B0),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (v) => _addTodayTask(v),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (_isListeningToday) {
                              _stopListening();
                            } else {
                              _startListening(isToday: true);
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _isListeningToday
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isListeningToday ? Icons.mic : Icons.mic_none,
                              size: 18,
                              color: _isListeningToday
                                  ? Colors.red
                                  : const Color(0xFF8B7CFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _addTodayTask(_todayInputCtrl.text),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _coach.accentColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── 목표 탭 ──────────────────────────────────────────────
  Widget _buildGoalTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: Column(
        children: [
          // 주간/월간 서브탭
          _buildGoalSubTab(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGoalList(_goalTab),
                  _buildGoalInput(_goalTab),
                  const SizedBox(height: 24),
                  _buildVisionSection(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSubTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: isVacation
              ? Colors.white.withOpacity(0.5)
              : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(24),
          border: isVacation
              ? null
              : Border.all(color: const Color(0xFFF3F4F6)),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _goalSubTabBtn('week', '주간', Icons.spa_outlined),
            Container(
              width: 1,
              height: 14,
              color: const Color(0xFFE5E7EB),
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            _goalSubTabBtn('month', '월간', Icons.landscape_outlined),
          ],
        ),
      ),
    );
  }

  Widget _goalSubTabBtn(String type, String label, IconData icon) {
    final isActive = _goalTab == type;
    return GestureDetector(
      onTap: () => setState(() => _goalTab = type),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Colors.black.withOpacity(0.02),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? _coach.accentColor
                      : const Color(0xFFA0A0B0).withOpacity(0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: isActive
                        ? _coach.accentColor
                        : const Color(0xFFA0A0B0),
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Positioned(
              bottom: 4,
              child: Container(
                width: 12,
                height: 2,
                decoration: BoxDecoration(
                  color: _coach.accentColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoalList(String type) {
    final goals = type == 'week' ? weekGoals : monthGoals;
    final title = type == 'week' ? '이번 주 목표' : '이번 달 목표';
    final emptyEmoji = type == 'week' ? '📅' : '🎯';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: GoogleFonts.notoSansKr(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF3D3A4E),
            ),
          ),
        ),
        if (goals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emptyEmoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    type == 'week' ? '이번 주 목표를\n추가해봐요!' : '이번 달 목표를\n추가해봐요!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: const Color(0xFFA0A0B0),
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            itemCount: goals.length,
            itemBuilder: (ctx, i) => _buildGoalItem(type, goals[i], i + 1),
          ),
      ],
    );
  }

  Widget _buildGoalItem(String type, GoalItem g, int num) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: g.done ? Border.all(color: const Color(0xFFE8E3F8)) : null,
        boxShadow: g.done
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: GestureDetector(
        onTap: () => _toggleGoal(type, g.id),
        child: Row(
          children: [
            // 번호/체크
            Container(
              width: 48,
              height: 52,
              alignment: Alignment.center,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: g.done
                      ? _coach.accentColor
                      : _coach.accentColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: g.done
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : Text(
                          '$num',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _coach.accentColor,
                          ),
                        ),
                ),
              ),
            ),
            Expanded(
              child: Text(
                g.text,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: g.done
                      ? const Color(0xFFA0A0B0)
                      : const Color(0xFF3D3A4E),
                  decoration: g.done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _deleteGoal(type, g.id),
              child: Container(
                width: 40,
                height: 52,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGoalInput(String type) {
    final ctrl = type == 'week' ? _weekInputCtrl : _monthInputCtrl;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFDDD6FE)),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: TextField(
                  controller: ctrl,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: const Color(0xFF3D3A4E),
                  ),
                  decoration: InputDecoration(
                    hintText: type == 'week' ? '주간 목표 추가...' : '월간 목표 추가...',
                    hintStyle: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: const Color(0xFFA0A0B0),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onSubmitted: (v) => _addGoal(type, v),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _addGoal(type, ctrl.text),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _coach.accentColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
    );
  }

  // ── 장기 비전 영역 ──────────────────────────────────────────
  Widget _buildVisionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.star_border,
                    color: Color(0xFF8B7CFF),
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '장기 비전',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                ],
              ),
              GestureDetector(
                onTap: () {
                if (_planType != 'master') {
                  _showMasterOnlyDialog();
                  return;
                }
                if (visions.length >= 3) {
                  _showVisionLimitDialog();
                  return;
                }
                _showVisionModal();
              },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8E3F8)),
                  ),
                  child: Text(
                    '+ 장기 비전 추가',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (visions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE8E3F8),
                  style: BorderStyle.none,
                ),
              ),
              child: Text(
                '아직 설정된 비전이 없어요.\n나만의 장기 목표를 추가해보세요!',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: const Color(0xFFA0A0B0),
                  height: 1.6,
                ),
              ),
            ),
          )
        else
        ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visions.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = visions.removeAt(oldIndex);
                visions.insert(newIndex, item);
              });
              _saveVisions();
            },
            itemBuilder: (ctx, i) {
              final v = visions[i];
              return GestureDetector(
                key: ValueKey(v.id),
                onTap: () {
                if (_planType != 'master') {
                  _showMasterOnlyDialog();
                  return;
                }
                _showVisionModal(v);
              },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              v.name,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF3D3A4E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: Color(0xFFA0A0B0),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF5F3FF),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${v.deadline.year}년 ${v.deadline.month}월 ${v.deadline.period}까지',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF8B7CFF),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // 드래그 핸들
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.drag_handle,
                            color: Color(0xFFD1D5DB),
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  // ── 마스터 전용 기능 잠금 팝업 ───────────────────────────────
  void _showMasterOnlyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_outline_rounded,
                  color: Color(0xFF8B7CFF),
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '마스터 플랜 전용 기능',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '장기 비전 기능은 마스터 플랜\n구독자만 이용할 수 있어요.\n마스터 플랜으로 업그레이드하면\n장기 비전·마일스톤 기능을 모두 활용할 수 있습니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: const Color(0xFF8E8A9E),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B7CFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text(
                    '확인',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 장기 비전 개수 제한 팝업 ─────────────────────────────
  void _showVisionLimitDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF8E1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF59E0B),
                  size: 32,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '장기 비전은 최대 3개까지\n생성 가능합니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D3A4E),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '정말 중요한 목표에 집중할 수 있도록\n개수를 제한하고 있습니다.\n\n새로운 비전을 추가하려면\n기존 비전 중 하나를 삭제해주세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: const Color(0xFF8E8A9E),
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B7CFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                  child: Text(
                    '확인',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMemoDialog(
    BuildContext context,
    MilestoneItem milestone,
    StateSetter setModalState,
  ) {
    final coach = CoachConfigs.get(widget.coachId);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return MilestoneMemoDialog(
          milestone: milestone,
          coach: coach,
          onSave: (newMemo) {
            setModalState(() {
              milestone.memo = newMemo;
            });
            _saveVisions();
          },
          onConvertAction: (action, type) {
            if (type == 'task_today') {
              final String todayStr = DateFormat(
                'yyyy-MM-dd',
              ).format(DateTime.now());
              final newTask = TaskItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                text: action.title,
                category: 'schedule',
                done: false,
                createdAt: todayStr,
              );
              setState(() {
                tasks.add(newTask);
              });
              _saveTasks();
              action.convertedTaskId = newTask.id;
              action.convertedType = 'task_today';
              action.convertedDate = DateFormat(
                'yyyy.MM.dd',
              ).format(DateTime.now());
            } else if (type == 'task_date') {
              // Show date picker
              showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              ).then((picked) {
                if (picked != null) {
                  final String dateStr = DateFormat(
                    'yyyy-MM-dd',
                  ).format(picked);
                  final newSchedule = ScheduleItem(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    text: action.title,
                    done: false,
                    createdAt: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  );
                  setState(() {
                    schedules.putIfAbsent(dateStr, () => []);
                    schedules[dateStr]!.add(newSchedule);
                  });
                  _saveSchedules();
                  action.convertedTaskId = newSchedule.id;
                  action.convertedType = 'task_date';
                  action.convertedDate = DateFormat(
                    'yyyy.MM.dd',
                  ).format(picked);
                  _saveVisions(); // Save milestone to persist conversion status
                }
              });
            } else if (type == 'habit') {
              final newHabit = HabitItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: action.title,
                createdAt: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                freq: 'daily',
              );
              setState(() {
                habits.add(newHabit);
              });
              _saveHabits();
              action.convertedHabitId = newHabit.id;
              action.convertedType = 'habit';
              action.convertedDate = DateFormat(
                'yyyy.MM.dd',
              ).format(DateTime.now());
            }
            _saveVisions(); // Save the updated milestone actions
          },
        );
      },
    );
  }

  void _showVisionModal([VisionItem? vision]) {
    final isNew = vision == null;
    final nameCtrl = TextEditingController(text: vision?.name ?? '');
    final descCtrl = TextEditingController(text: vision?.desc ?? '');
    String selectedYear = vision?.deadline.year ?? '${DateTime.now().year + 1}';
    String selectedMonth = vision?.deadline.month ?? '1';
    String selectedPeriod = vision?.deadline.period ?? '말';
    List<MilestoneItem> milestones =
        vision?.milestones
            .map((e) => MilestoneItem.fromJson(e.toJson()))
            .toList() ??
        [
          MilestoneItem(text: ''),
          MilestoneItem(text: ''),
          MilestoneItem(text: ''),
        ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: DraggableScrollableSheet(
                initialChildSize: 0.9,
                maxChildSize: 0.9,
                minChildSize: 0.5,
                expand: false,
                builder: (_, scrollCtrl) => Column(
                  children: [
                    // 상단 헤더
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      decoration: const BoxDecoration(
                        color: Color(0xFF8B7CFF),
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                      ),
                      child: Stack(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isNew ? '새 장기 비전' : '장기 비전 수정',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isNew
                                    ? '새로운 미래를 설계해보세요.'
                                    : '미래의 나를 이끌 비전을 관리해요.',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 본문
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 비전 목표
                            Row(
                              children: [
                                const Icon(
                                  Icons.ads_click,
                                  color: Color(0xFFE53E3E),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '비전 목표',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF3D3A4E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE8E3F8),
                                ),
                              ),
                              child: TextField(
                                controller: nameCtrl,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF3D3A4E),
                                ),
                                decoration: InputDecoration(
                                  hintText: '예: 소설 완결 및 출판',
                                  hintStyle: GoogleFonts.notoSansKr(
                                    color: const Color(0xFFA0A0B0),
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE8E3F8),
                                ),
                              ),
                              child: TextField(
                                controller: descCtrl,
                                maxLines: 2,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  color: const Color(0xFF3D3A4E),
                                ),
                                decoration: InputDecoration(
                                  hintText: '비전에 대한 짧은 설명을 적어주세요.',
                                  hintStyle: GoogleFonts.notoSansKr(
                                    color: const Color(0xFFA0A0B0),
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            // 목표 기한
                            Row(
                              children: [
                                const Icon(
                                  Icons.calendar_month,
                                  color: Color(0xFF8B7CFF),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '목표 기한',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: const Color(0xFF3D3A4E),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  flex: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE8E3F8),
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedYear,
                                        isExpanded: true,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Color(0xFFA0A0B0),
                                        ),
                                        items: List.generate(10, (i) {
                                          final y = (DateTime.now().year + i)
                                              .toString();
                                          return DropdownMenuItem(
                                            value: y,
                                            child: Text('$y년'),
                                          );
                                        }),
                                        onChanged: (v) => setModalState(
                                          () => selectedYear = v!,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE8E3F8),
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedMonth,
                                        isExpanded: true,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Color(0xFFA0A0B0),
                                        ),
                                        items: List.generate(12, (i) {
                                          final m = (i + 1).toString();
                                          return DropdownMenuItem(
                                            value: m,
                                            child: Text('$m월'),
                                          );
                                        }),
                                        onChanged: (v) => setModalState(
                                          () => selectedMonth = v!,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE8E3F8),
                                      ),
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: selectedPeriod,
                                        isExpanded: true,
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down,
                                          color: Color(0xFFA0A0B0),
                                        ),
                                        items: ['초', '중', '말']
                                            .map(
                                              (p) => DropdownMenuItem(
                                                value: p,
                                                child: Text(p),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (v) => setModalState(
                                          () => selectedPeriod = v!,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            // 마일스톤 관리
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.flag,
                                      color: Color(0xFFD4A017),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '마일스톤 관리',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF3D3A4E),
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () {
                                    setModalState(() {
                                      milestones.add(MilestoneItem(text: ''));
                                    });
                                  },
                                  child: Text(
                                    '+ 추가',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF3D3A4E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: milestones.length,
                              onReorder: (oldIndex, newIndex) {
                                setModalState(() {
                                  if (oldIndex < newIndex) {
                                    newIndex -= 1;
                                  }
                                  final item = milestones.removeAt(oldIndex);
                                  milestones.insert(newIndex, item);
                                });
                              },
                              itemBuilder: (ctx, i) {
                                final m = milestones[i];
                                return Container(
                                  key: ObjectKey(m),
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: m.done
                                        ? const Color(0xFFF8FCFA)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: m.done
                                          ? const Color(0xFFDFF8EE)
                                          : const Color(0xFFE8E3F8),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          alignment: Alignment.center,
                                          margin: const EdgeInsets.only(top: 2),
                                          decoration: BoxDecoration(
                                            color: m.done
                                                ? const Color(0xFF5AD7B0)
                                                : const Color(0xFFF5F3FF),
                                            borderRadius: BorderRadius.circular(
                                              m.done ? 14 : 8,
                                            ),
                                          ),
                                          child: m.done
                                              ? const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 16,
                                                )
                                              : Text(
                                                  '${i + 1}',
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: const Color(
                                                      0xFFA0A0B0,
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        TextEditingController(
                                                            text: m.text,
                                                          )
                                                          ..selection =
                                                              TextSelection.collapsed(
                                                                offset: m
                                                                    .text
                                                                    .length,
                                                              ),
                                                    onChanged: (val) =>
                                                        m.text = val,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: const Color(
                                                            0xFF3D3A4E,
                                                          ),
                                                          decoration:
                                                              TextDecoration
                                                                  .none,
                                                        ),
                                                    decoration: InputDecoration(
                                                      hintText: '단계 목표 입력...',
                                                      hintStyle:
                                                          GoogleFonts.notoSansKr(
                                                            color: const Color(
                                                              0xFFA0A0B0,
                                                            ),
                                                          ),
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding:
                                                          EdgeInsets.zero,
                                                    ),
                                                  ),
                                                ),
                                                if (m.done) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 8,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: const Color(
                                                        0xFFDFF8EE,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons.check,
                                                          size: 12,
                                                          color: Color(
                                                            0xFF33A883,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 2,
                                                        ),
                                                        Text(
                                                          '완료',
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    const Color(
                                                                      0xFF33A883,
                                                                    ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(width: 8),
                                                GestureDetector(
                                                  onTap: () {
                                                    _showMemoDialog(
                                                      context,
                                                      m,
                                                      setModalState,
                                                    );
                                                  },
                                                  child: const Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 4.0,
                                                      right: 10.0,
                                                    ),
                                                    child: Icon(
                                                      Icons.note_alt_outlined,
                                                      color: Color(0xFF8B7CFF),
                                                      size: 20,
                                                    ),
                                                  ),
                                                ),
                                                GestureDetector(
                                                  onTap: () async {
                                                    final confirm = await _showConfirmDeleteDialog('마일스톤 삭제', '이 마일스톤을 정말 삭제하시겠습니까?\n삭제된 내용은 복구할 수 없습니다.');
                                                    if (!confirm) return;
                                                    setModalState(() {
                                                      milestones.removeAt(i);
                                                    });
                                                  },
                                                  child: const Padding(
                                                    padding: EdgeInsets.only(
                                                      top: 5.0,
                                                    ),
                                                    child: Icon(
                                                      Icons.close,
                                                      color: Color(0xFFD1D5DB),
                                                      size: 18,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            if (!m.done)
                                              GestureDetector(
                                                onTap: () async {
                                                  final picked = await showDatePicker(
                                                    context: context,
                                                    initialDate:
                                                        m.date != null &&
                                                            m.date!.isNotEmpty
                                                        ? DateTime.tryParse(
                                                                m.date!,
                                                              ) ??
                                                              DateTime.now()
                                                        : DateTime.now(),
                                                    firstDate: DateTime(2000),
                                                    lastDate: DateTime(2050),
                                                    builder: (context, child) {
                                                      return Theme(
                                                        data: Theme.of(context).copyWith(
                                                          colorScheme:
                                                              ColorScheme.light(
                                                                primary: _coach
                                                                    .accentColor,
                                                                onPrimary:
                                                                    Colors
                                                                        .white,
                                                                onSurface:
                                                                    const Color(
                                                                      0xFF3D3A4E,
                                                                    ),
                                                              ),
                                                          textButtonTheme:
                                                              TextButtonThemeData(
                                                                style: TextButton.styleFrom(
                                                                  foregroundColor:
                                                                      _coach
                                                                          .accentColor,
                                                                ),
                                                              ),
                                                        ),
                                                        child: child!,
                                                      );
                                                    },
                                                  );
                                                  if (picked != null) {
                                                    setModalState(() {
                                                      m.date =
                                                          "${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                                    });
                                                  }
                                                },
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 10,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFFE8E3F8,
                                                      ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      const Icon(
                                                        Icons.calendar_month,
                                                        color: Color(
                                                          0xFF8B7CFF,
                                                        ),
                                                        size: 14,
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                        m.date != null &&
                                                                m
                                                                    .date!
                                                                    .isNotEmpty
                                                            ? m.date!
                                                            : '기한 선택',
                                                        style: GoogleFonts.notoSansKr(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color:
                                                              m.date != null &&
                                                                  m
                                                                      .date!
                                                                      .isNotEmpty
                                                              ? const Color(
                                                                  0xFF8B7CFF,
                                                                )
                                                              : const Color(
                                                                  0xFFA0A0B0,
                                                                ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              )
                                            else if (m.achievedDate != null)
                                              Row(
                                                children: [
                                                  const Icon(
                                                    Icons.calendar_month,
                                                    size: 14,
                                                    color: Color(0xFF5AD7B0),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${m.achievedDate} 달성 완료',
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 12,
                                                          color: const Color(
                                                            0xFF6B7280,
                                                          ),
                                                        ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.pets,
                                                    size: 12,
                                                    color: Color(0xFF8B7CFF),
                                                  ),
                                                ],
                                              ),
                                            if ((m.memo != null &&
                                                    m.memo!.isNotEmpty) ||
                                                (m.memoSections != null &&
                                                    m
                                                        .memoSections!
                                                        .isNotEmpty) ||
                                                (m.actionCandidates != null &&
                                                    m
                                                        .actionCandidates!
                                                        .isNotEmpty)) ...[
                                              const SizedBox(height: 8),
                                              GestureDetector(
                                                onTap: () {
                                                  _showMemoDialog(
                                                    context,
                                                    m,
                                                    setModalState,
                                                  );
                                                },
                                                child: Container(
                                                  width: double.infinity,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 12,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFF3F4F6,
                                                    ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                  ),
                                                  child: MilestoneMemoDisplayWidget(
                                                    milestone: m,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: const Color(
                                                            0xFF4B5563,
                                                          ),
                                                          height: 1.5,
                                                        ),
                                                    maxLines: 1,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (m.done) ...[
                                              const SizedBox(height: 12),
                                              const Divider(
                                                color: Color(0xFFDFF8EE),
                                                height: 1,
                                                thickness: 1,
                                              ),
                                              const SizedBox(height: 12),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    '🎉',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          '목표 달성을 축하해요!',
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                color:
                                                                    const Color(
                                                                      0xFF3D3A4E,
                                                                    ),
                                                              ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          '오늘의 작은 성취가 미래의 큰 변화를 만들어요.',
                                                          style:
                                                              GoogleFonts.notoSansKr(
                                                                fontSize: 12,
                                                                color:
                                                                    const Color(
                                                                      0xFF6B7280,
                                                                    ),
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                            ],
                                            if (!m.done)
                                              const SizedBox(height: 8),

                                            GestureDetector(
                                              onTap: () {
                                                setModalState(() {
                                                  m.done = !m.done;
                                                  if (m.done) {
                                                    final now = DateTime.now();
                                                    m.achievedDate =
                                                        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
                                                  } else {
                                                    m.achievedDate = null;
                                                  }
                                                });
                                              },
                                              child: Container(
                                                width: double.infinity,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      vertical: 8,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: m.done
                                                      ? Colors.transparent
                                                      : const Color(0xFFF9FAFB),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: m.done
                                                        ? const Color(
                                                            0xFF5AD7B0,
                                                          )
                                                        : const Color(
                                                            0xFFE5E7EB,
                                                          ),
                                                    width: m.done ? 1.0 : 1.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      m.done
                                                          ? Icons.refresh
                                                          : Icons
                                                                .radio_button_unchecked,
                                                      size: 16,
                                                      color: m.done
                                                          ? const Color(
                                                              0xFF33A883,
                                                            )
                                                          : const Color(
                                                              0xFF9CA3AF,
                                                            ),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      m.done
                                                          ? '완료 취소 (다시 진행 중으로)'
                                                          : '완료 표시',
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: m.done
                                                                ? 12
                                                                : 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: m.done
                                                                ? const Color(
                                                                    0xFF33A883,
                                                                  )
                                                                : const Color(
                                                                    0xFF9CA3AF,
                                                                  ),
                                                          ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // 하단 버튼
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          if (!isNew)
                            Expanded(
                              flex: 1,
                              child: GestureDetector(
                                onTap: () async {
                                  final confirm = await _showConfirmDeleteDialog('장기 비전 삭제', '이 비전을 정말 삭제하시겠습니까?\\n하위 마일스톤들도 모두 함께 삭제됩니다.');
                                  if (!confirm) return;
                                  setState(() {
                                    visions.removeWhere(
                                      (v) => v.id == vision.id,
                                    );
                                  });
                                  _saveVisions();
                                  if (context.mounted) Navigator.pop(ctx);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFFE8E3F8),
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '삭제',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFFE53E3E),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (!isNew) const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () {
                                if (nameCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('비전 목표를 입력해주세요.'),
                                    ),
                                  );
                                  return;
                                }
                                final newMilestones = milestones
                                    .where((m) => m.text.trim().isNotEmpty)
                                    .toList();

                                setState(() {
                                  if (isNew) {
                                    visions.add(
                                      VisionItem(
                                        id: DateTime.now()
                                            .millisecondsSinceEpoch
                                            .toString(),
                                        name: nameCtrl.text.trim(),
                                        desc: descCtrl.text.trim(),
                                        coachId: _coach.id,
                                        deadline: VisionDeadline(
                                          year: selectedYear,
                                          month: selectedMonth,
                                          period: selectedPeriod,
                                        ),
                                        milestones: newMilestones,
                                        updatedAt: DateTime.now()
                                            .toIso8601String(),
                                      ),
                                    );
                                  } else {
                                    final idx = visions.indexWhere(
                                      (v) => v.id == vision.id,
                                    );
                                    if (idx != -1) {
                                      visions[idx] = VisionItem(
                                        id: vision.id,
                                        name: nameCtrl.text.trim(),
                                        desc: descCtrl.text.trim(),
                                        coachId: vision.coachId,
                                        deadline: VisionDeadline(
                                          year: selectedYear,
                                          month: selectedMonth,
                                          period: selectedPeriod,
                                        ),
                                        milestones: newMilestones,
                                        updatedAt: DateTime.now()
                                            .toIso8601String(),
                                      );
                                    }
                                  }
                                });
                                _saveVisions();
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B7CFF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '저장',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  DateTime get _nextDayDate {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day + 1);
  }

  List<TaskItem> _movableBedtimeTasks() {
    return tasks.where((task) {
      if (task.done) return false;
      if (task.isHabit || task.habitId != null) return false;
      return task.category == 'today' || task.category == 'schedule';
    }).toList();
  }

  void _openBedtimeMoveFlow({bool nextDay = false}) {
    final movableTasks = _movableBedtimeTasks();

    if (movableTasks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('다른 날짜로 옮길 남은 할 일이 없어요.')));
      return;
    }

    if (movableTasks.length == 1) {
      _openBedtimeMoveTaskModal(movableTasks.first, nextDay: nextDay);
      return;
    }

    _showBedtimeTaskPicker(movableTasks, nextDay: nextDay);
  }

  void _showBedtimeTaskPicker(
    List<TaskItem> movableTasks, {
    required bool nextDay,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nextDay ? '다음 날로 옮길 일을 선택해주세요' : '옮길 할 일을 선택해주세요',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 14),
              ...movableTasks.map(
                (task) => GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    _openBedtimeMoveTaskModal(task, nextDay: nextDay);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.radio_button_unchecked,
                          size: 20,
                          color: Color(0xFF8B7CFF),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            task.text,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openBedtimeMoveTaskModal(TaskItem task, {required bool nextDay}) {
    _showMoveTaskModal(
      task,
      fixedDay: nextDay ? _nextDayDate : null,
      hideCalendar: nextDay,
      title: nextDay ? '다음 날로 옮기기' : '다른 날짜로 옮기기',
      onMoved: nextDay ? _showBedtimeMoveFollowUp : null,
    );
  }

  void _showBedtimeMoveFollowUp() {
    final remainingTasks = _movableBedtimeTasks();
    if (remainingTasks.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '남은 일정도 옮길까요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 14),
              _buildTaskActionOption(
                label: '다음 날로 계속 옮기기',
                onTap: () {
                  Navigator.pop(ctx);
                  _openBedtimeMoveFlow(nextDay: true);
                },
              ),
              _buildTaskActionOption(
                label: '다른 날짜로 옮기기',
                onTap: () {
                  Navigator.pop(ctx);
                  _openBedtimeMoveFlow();
                },
              ),
              _buildTaskActionOption(
                label: '그만하기',
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── 일정 탭 ────────────────────────────────
  String _dateKey(DateTime day) {
    return "${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}";
  }

  String _formatTime(TimeOfDay t) {
    final ap = t.hour >= 12 ? '오후' : '오전';
    final h = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    final m = t.minute.toString().padLeft(2, '0');
    return "$ap $h:$m";
  }

  String? _displayTimeFromStored({
    String? time,
    String? timeStart,
    String? timeEnd,
  }) {
    if (time != null && time.trim().isNotEmpty) return time;

    final start = _parseStoredTime(timeStart);
    if (start == null) return null;

    final end = _parseStoredTime(timeEnd);
    if (end == null) return _formatTime(start);

    return '${_formatTime(start)} ~ ${_formatTime(end)}';
  }

  TimeOfDay? _parseStoredTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _storedTime(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  bool _canEnableTimeReminder(String timeType, TimeOfDay? startTime) {
    return _isCoreReminderEnabledGlobally &&
        (timeType == 'single' || timeType == 'range') &&
        startTime != null;
  }

  bool _resolvedTimeReminderEnabled(
    String timeType,
    TimeOfDay? startTime,
    bool requested,
  ) {
    return requested && _canEnableTimeReminder(timeType, startTime);
  }

  void _showSelectTimeBeforeReminderSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('알람을 켜려면 시간을 먼저 선택해주세요.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _timeTypeFromTask(TaskItem task) {
    if (task.timeStart != null && task.timeEnd != null) return 'range';
    if (task.timeStart != null) return 'single';
    if (task.duration != null) return 'duration';
    return 'none';
  }

  ScheduleItem _scheduleFromMovedTask(
    TaskItem task,
    String timeType,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? duration,
    bool reminderEnabled,
  ) {
    final entry = ScheduleItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: task.text,
      done: false,
      createdAt: DateTime.now().toIso8601String(),
      isReminderEnabled: _resolvedTimeReminderEnabled(
        timeType,
        startTime,
        reminderEnabled,
      ),
      deferredCount: task.deferredCount + 1,
    );

    if (timeType == 'single' && startTime != null) {
      entry.timeStart = _storedTime(startTime);
      entry.time = _formatTime(startTime);
    } else if (timeType == 'range' && startTime != null) {
      entry.timeStart = _storedTime(startTime);
      entry.time = _formatTime(startTime);
      if (endTime != null) {
        entry.timeEnd = _storedTime(endTime);
        entry.time = '${_formatTime(startTime)} ~ ${_formatTime(endTime)}';
      }
    } else if (timeType == 'duration' && duration != null) {
      entry.duration = duration;
    }

    return entry;
  }

  Widget _buildMoveTimeControls({
    required String timeType,
    required TimeOfDay? startTime,
    required TimeOfDay? endTime,
    required String? duration,
    required void Function(String value) setTimeType,
    required void Function(TimeOfDay? value) setStartTime,
    required void Function(TimeOfDay? value) setEndTime,
    required void Function(String? value) setDuration,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: ['single', 'range', 'duration'].map((t) {
            final labels = {
              'single': '특정 시간',
              'range': '시간 범위',
              'duration': '소요 시간',
            };
            final isActive = timeType == t;
            final isLast = t == 'duration';
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  setTimeType(timeType == t ? 'none' : t);
                  if (t != 'duration') setDuration(null);
                },
                child: Container(
                  margin: EdgeInsets.only(right: isLast ? 0 : 6),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: isActive
                        ? _coach.accentColor.withOpacity(0.08)
                        : Colors.white,
                    border: Border.all(
                      color: isActive
                          ? _coach.accentColor
                          : const Color(0xFFE5E7EB),
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    labels[t]!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? _coach.accentColor
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        if (timeType == 'single' || timeType == 'range')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                Text(
                  timeType == 'range' ? '시작: ' : '시간: ',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    color: const Color(0xFF6B7280),
                  ),
                ),
                GestureDetector(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: startTime ?? TimeOfDay.now(),
                    );
                    if (t != null) setStartTime(t);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      startTime != null ? _formatTime(startTime) : '선택',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: startTime != null
                            ? _coach.accentColor
                            : const Color(0xFFA0A0B0),
                      ),
                    ),
                  ),
                ),
                if (timeType == 'range') ...[
                  const SizedBox(width: 8),
                  Text(
                    '~ 종료: ',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: endTime ?? TimeOfDay.now(),
                      );
                      if (t != null) setEndTime(t);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        endTime != null ? _formatTime(endTime) : '선택',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: endTime != null
                              ? _coach.accentColor
                              : const Color(0xFFA0A0B0),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (timeType == 'duration')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ['10분', '15분', '30분', '1시간', '2시간', '3시간', '4시간+'].map((
                d,
              ) {
                final isActive = duration == d;
                return GestureDetector(
                  onTap: () => setDuration(d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFFFDF2F8) : Colors.white,
                      border: Border.all(
                        color: isActive
                            ? const Color(0xFFDB2777)
                            : const Color(0xFFE5E7EB),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      d,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: isActive
                            ? const Color(0xFFDB2777)
                            : const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }

  List<DateTime> _datesForScheduleRepeat(
    DateTime startDate,
    Map<String, dynamic> rule,
  ) {
    final normalizedStart = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
    );
    final endType = rule['endType']?.toString() ?? 'never';
    final endDate = DateTime.tryParse(rule['endDate']?.toString() ?? '');
    final repeatCount = int.tryParse(rule['count']?.toString() ?? '');
    final hardEnd = endType == 'date' && endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : normalizedStart.add(const Duration(days: 365));
    final maxCount = endType == 'count'
        ? (repeatCount == null || repeatCount < 1 ? 1 : repeatCount)
        : 370;
    final dates = <DateTime>[];
    final type = rule['type']?.toString() ?? 'daily';

    bool canAdd(DateTime day) {
      if (day.isBefore(normalizedStart)) return false;
      if (day.isAfter(hardEnd)) return false;
      return dates.length < maxCount;
    }

    if (type == 'daily') {
      var day = normalizedStart;
      while (canAdd(day)) {
        dates.add(day);
        day = day.add(const Duration(days: 1));
      }
      return dates;
    }

    if (type == 'weekly') {
      final weekdays =
          (rule['weekdays'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toSet() ??
          {normalizedStart.weekday};
      var day = normalizedStart;
      while (canAdd(day)) {
        if (weekdays.contains(day.weekday)) dates.add(day);
        day = day.add(const Duration(days: 1));
      }
      return dates;
    }

    if (type == 'monthly') {
      final monthlyMode = rule['monthlyMode']?.toString() ?? 'date';
      var cursor = DateTime(normalizedStart.year, normalizedStart.month);
      while (dates.length < maxCount && !cursor.isAfter(hardEnd)) {
        DateTime? candidate;
        if (monthlyMode == 'nthWeekday') {
          candidate = _nthWeekdayOfMonth(
            cursor.year,
            cursor.month,
            int.tryParse(rule['nth']?.toString() ?? '') ?? 1,
            int.tryParse(rule['weekday']?.toString() ?? '') ??
                normalizedStart.weekday,
          );
        } else {
          final dayOfMonth =
              int.tryParse(rule['dayOfMonth']?.toString() ?? '') ??
              normalizedStart.day;
          final lastDay = DateTime(cursor.year, cursor.month + 1, 0).day;
          candidate = DateTime(
            cursor.year,
            cursor.month,
            dayOfMonth.clamp(1, lastDay),
          );
        }
        if (candidate != null && canAdd(candidate)) dates.add(candidate);
        cursor = DateTime(cursor.year, cursor.month + 1);
      }
      return dates;
    }

    return [normalizedStart];
  }

  DateTime? _nthWeekdayOfMonth(int year, int month, int nth, int weekday) {
    final matches = <DateTime>[];
    final lastDay = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday == weekday) matches.add(date);
    }
    if (matches.isEmpty) return null;
    final index = nth.clamp(1, matches.length) - 1;
    return matches[index];
  }

  String _weekdayLabel(int weekday) {
    const labels = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    return labels[weekday] ?? '';
  }

  String _repeatRuleLabel(Map<String, dynamic>? rule) {
    if (rule == null) return '';
    final type = rule['type']?.toString() ?? 'daily';
    if (type == 'daily') return '매일';
    if (type == 'weekly') {
      final weekdays =
          (rule['weekdays'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          [];
      final ordered = [
        7,
        1,
        2,
        3,
        4,
        5,
        6,
      ].where(weekdays.contains).map(_weekdayLabel).join(' · ');
      return ordered.isEmpty ? '매주' : '매주 $ordered';
    }
    if (type == 'monthly') {
      if (rule['monthlyMode'] == 'nthWeekday') {
        final nth = int.tryParse(rule['nth']?.toString() ?? '') ?? 1;
        final weekday =
            int.tryParse(rule['weekday']?.toString() ?? '') ?? DateTime.monday;
        return '매월 ${nth}째주 ${_weekdayLabel(weekday)}요일';
      }
      final day = int.tryParse(rule['dayOfMonth']?.toString() ?? '') ?? 1;
      return '매월 $day일';
    }
    return '반복';
  }

  void _addSchedule() {
    final text = _schInputCtrl.text.trim();
    if (text.isEmpty) return;
    final cleaned = text.replaceAll(RegExp(r'[.\s]+$'), '');
    final commandSuffixRegex = RegExp(r'\s*(등록해줘|추가해줘|넣어줘)$');
    if (commandSuffixRegex.hasMatch(cleaned)) {
      _showVoiceRegistrationConfirmDialog(text, isToday: false);
      return;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdAt = DateTime.now().toIso8601String();
    final repeatRule = _schRepeatEnabled ? _schRepeatRule : null;
    final repeatDates = repeatRule == null
        ? [_calSelectedDay]
        : _datesForScheduleRepeat(_calSelectedDay, repeatRule);
    final recurrenceGroupId = repeatRule == null ? null : 'repeat_$nowMs';

    ScheduleItem buildEntry(DateTime date, int index) {
      final entry = ScheduleItem(
        id: repeatRule == null ? nowMs.toString() : '${nowMs}_$index',
        text: text,
        createdAt: createdAt,
        isReminderEnabled: _resolvedTimeReminderEnabled(
          _schTimeType,
          _schStartTime,
          _schReminderEnabled,
        ),
        isRecurring: repeatRule != null,
        recurrenceGroupId: recurrenceGroupId,
        recurrenceRule: repeatRule == null
            ? null
            : {...repeatRule, 'startDate': _dateKey(_calSelectedDay)},
      );

      if (_schTimeType == 'single' && _schStartTime != null) {
        entry.timeStart = "${_schStartTime!.hour}:${_schStartTime!.minute}";
        entry.time = _formatTime(_schStartTime!);
      } else if (_schTimeType == 'range' && _schStartTime != null) {
        entry.timeStart = "${_schStartTime!.hour}:${_schStartTime!.minute}";
        if (_schEndTime != null) {
          entry.timeEnd = "${_schEndTime!.hour}:${_schEndTime!.minute}";
          entry.time =
              "${_formatTime(_schStartTime!)} ~ ${_formatTime(_schEndTime!)}";
        } else {
          entry.time = _formatTime(_schStartTime!);
        }
      } else if (_schTimeType == 'duration' && _schDuration != null) {
        entry.duration = _schDuration;
      }
      return entry;
    }

    setState(() {
      for (var i = 0; i < repeatDates.length; i++) {
        final dateStr = _dateKey(repeatDates[i]);
        schedules.putIfAbsent(dateStr, () => []);
        schedules[dateStr]!.add(buildEntry(repeatDates[i], i));
      }
    });
    _schInputCtrl.clear();
    setState(() {
      _schReminderEnabled = false;
      _schRepeatEnabled = false;
      _schRepeatRule = null;
    });
    _saveSchedules();
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) {
              setState(() {
                _isListeningToday = false;
                _isListeningSchedule = false;
              });
            }
          }
        },
        onError: (error) {
          debugPrint("Speech error: $error");
          if (mounted) {
            setState(() {
              _isListeningToday = false;
              _isListeningSchedule = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('음성 인식 오류: ${error.errorMsg}')),
            );
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Speech init error: $e");
    }
  }

  void _startListening({required bool isToday}) async {
    if (!_speechEnabled) {
      _initSpeech();
      return;
    }
    final controller = isToday ? _todayInputCtrl : _schInputCtrl;
    final baseText = controller.text;
    final baseSelection = controller.selection;

    setState(() {
      if (isToday) {
        _isListeningToday = true;
        _isListeningSchedule = false;
      } else {
        _isListeningToday = false;
        _isListeningSchedule = true;
      }
    });

    await _speechToText.listen(
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      onResult: (result) {
        if (mounted) {
          setState(() {
            final spoken = result.recognizedWords;
            int start = baseSelection.start;
            int end = baseSelection.end;
            if (start < 0) {
              start = baseText.length;
              end = baseText.length;
            }
            final insertText =
                (baseText.isNotEmpty && start > 0 && baseText[start - 1] != ' '
                    ? ' '
                    : '') +
                spoken;
            controller.text = baseText.replaceRange(start, end, insertText);
            controller.selection = TextSelection.collapsed(
              offset: start + insertText.length,
            );
          });

          if (result.finalResult) {
            _handleSpeechFinished(controller.text.trim(), isToday: isToday);
          }
        }
      },
      localeId: 'ko_KR',
      cancelOnError: false,
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    final wasListeningToday = _isListeningToday;
    final wasListeningSchedule = _isListeningSchedule;
    await _speechToText.stop();
    if (mounted) {
      setState(() {
        _isListeningToday = false;
        _isListeningSchedule = false;
      });
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted) {
          if (wasListeningToday) {
            _handleSpeechFinished(_todayInputCtrl.text.trim(), isToday: true);
          } else if (wasListeningSchedule) {
            _handleSpeechFinished(_schInputCtrl.text.trim(), isToday: false);
          }
        }
      });
    }
  }

  void _handleSpeechFinished(String spokenText, {required bool isToday}) {
    if (_isConfirmDialogShowing) return;
    final cleaned = spokenText.replaceAll(RegExp(r'[.\s]+$'), '');
    final suffixRegex = RegExp(r'\s*(등록해줘|추가해줘|넣어줘)$');
    if (suffixRegex.hasMatch(cleaned)) {
      _showVoiceRegistrationConfirmDialog(spokenText, isToday: isToday);
    }
  }

  int _weekdayFromKorean(String value) {
    if (value.contains('월')) return DateTime.monday;
    if (value.contains('화')) return DateTime.tuesday;
    if (value.contains('수')) return DateTime.wednesday;
    if (value.contains('목')) return DateTime.thursday;
    if (value.contains('금')) return DateTime.friday;
    if (value.contains('토')) return DateTime.saturday;
    if (value.contains('일')) return DateTime.sunday;
    return -1;
  }

  String _normalizeKoreanTimeWords(String input) {
    const hourWords = {
      '한': '1',
      '하나': '1',
      '두': '2',
      '둘': '2',
      '세': '3',
      '셋': '3',
      '네': '4',
      '넷': '4',
      '다섯': '5',
      '여섯': '6',
      '일곱': '7',
      '여덟': '8',
      '아홉': '9',
      '열': '10',
      '열한': '11',
      '열하나': '11',
      '열두': '12',
      '열둘': '12',
    };
    var normalized = input;
    final keys = hourWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final word in keys) {
      normalized = normalized.replaceAllMapped(
        RegExp('$word\\s*시'),
        (_) => '${hourWords[word]}시',
      );
    }
    return normalized;
  }

  ({String text, Map<String, dynamic>? rule}) _parseNaturalLanguageRepeat(
    String input,
    DateTime defaultDate,
  ) {
    var cleaned = input;
    final rule = <String, dynamic>{'endType': 'never'};

    final monthlyNthRegex = RegExp(
      r'(?:매월|매달)\s*(첫째|첫|둘째|두번째|셋째|세번째|넷째|네번째|다섯째|마지막|1째|1번째|2째|2번째|3째|3번째|4째|4번째|5째|5번째)\s*주\s*([월화수목금토일])(?:요일)?',
    );
    final monthlyNthMatch = monthlyNthRegex.firstMatch(cleaned);
    if (monthlyNthMatch != null) {
      final nthText = monthlyNthMatch.group(1)!;
      final weekday = _weekdayFromKorean(monthlyNthMatch.group(2)!);
      final nth = switch (nthText) {
        '첫째' || '첫' || '1째' || '1번째' => 1,
        '둘째' || '두번째' || '2째' || '2번째' => 2,
        '셋째' || '세번째' || '3째' || '3번째' => 3,
        '넷째' || '네번째' || '4째' || '4번째' => 4,
        _ => 5,
      };
      rule
        ..['type'] = 'monthly'
        ..['monthlyMode'] = 'nthWeekday'
        ..['nth'] = nth
        ..['weekday'] = weekday == -1 ? defaultDate.weekday : weekday;
      cleaned = cleaned.replaceFirst(monthlyNthMatch.group(0)!, '').trim();
      return (text: cleaned, rule: rule);
    }

    final monthlyDateRegex = RegExp(r'(?:매월|매달)\s*(\d{1,2})\s*일');
    final monthlyDateMatch = monthlyDateRegex.firstMatch(cleaned);
    if (monthlyDateMatch != null) {
      final day = int.tryParse(monthlyDateMatch.group(1)!) ?? defaultDate.day;
      rule
        ..['type'] = 'monthly'
        ..['monthlyMode'] = 'date'
        ..['dayOfMonth'] = day.clamp(1, 31);
      cleaned = cleaned.replaceFirst(monthlyDateMatch.group(0)!, '').trim();
      return (text: cleaned, rule: rule);
    }

    final weeklyRegex = RegExp(
      r'매주\s*((?:[월화수목금토일](?:요일)?(?:\s*(?:,|과|와|랑|하고|및)?\s*)?)+)',
    );
    final weeklyMatch = weeklyRegex.firstMatch(cleaned);
    if (weeklyMatch != null) {
      final weekdays = <int>[];
      final weekdaysText = weeklyMatch.group(1)!;
      for (final match in RegExp(
        r'[월화수목금토일](?:요일)?',
      ).allMatches(weekdaysText)) {
        final weekday = _weekdayFromKorean(match.group(0)!);
        if (weekday != -1 && !weekdays.contains(weekday)) {
          weekdays.add(weekday);
        }
      }
      if (weekdays.isNotEmpty) {
        rule
          ..['type'] = 'weekly'
          ..['weekdays'] = weekdays;
        cleaned = cleaned.replaceFirst(weeklyMatch.group(0)!, '').trim();
        return (text: cleaned, rule: rule);
      }
    }

    final dailyRegex = RegExp(r'(?:매일|매일마다|날마다|매일\s*매일)');
    final dailyMatch = dailyRegex.firstMatch(cleaned);
    if (dailyMatch != null) {
      rule['type'] = 'daily';
      cleaned = cleaned.replaceFirst(dailyMatch.group(0)!, '').trim();
      return (text: cleaned, rule: rule);
    }

    return (text: input, rule: null);
  }

  ParsedVoiceRegistration _parseNaturalLanguageVoice(
    String input,
    DateTime defaultDate,
  ) {
    String cleaned = input.trim();
    cleaned = cleaned.replaceAll(RegExp(r'[.\s]+$'), '');
    final suffixRegex = RegExp(r'\s*(등록해줘|추가해줘|넣어줘)$');
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();
    cleaned = _normalizeKoreanTimeWords(cleaned);

    final repeatParse = _parseNaturalLanguageRepeat(cleaned, defaultDate);
    cleaned = repeatParse.text;
    final repeatRule = repeatParse.rule;

    DateTime parsedDate = defaultDate;
    bool hasDate = repeatRule != null;

    // 1. Check "이번달 마지막 [요일]"
    final lastWeekdayRegex = RegExp(r'이번달\s+마지막\s+([월화수목금토일])(?:요일)?');
    final lastWeekdayMatch = lastWeekdayRegex.firstMatch(cleaned);
    if (lastWeekdayMatch != null) {
      final weekdayStr = lastWeekdayMatch.group(1)!;
      final targetWeekday = _weekdayFromKorean(weekdayStr);
      if (targetWeekday != -1) {
        final now = DateTime.now();
        var tempDate = DateTime(now.year, now.month + 1, 0);
        while (tempDate.weekday != targetWeekday) {
          tempDate = tempDate.subtract(const Duration(days: 1));
        }
        parsedDate = tempDate;
        hasDate = true;
        cleaned = cleaned.replaceFirst(lastWeekdayMatch.group(0)!, '').trim();
      }
    }

    // 2. Check "이번주/다음주/다다음주 [요일]"
    if (!hasDate) {
      final weekRelRegex = RegExp(r'(이번주|다음주|다다음주)\s+([월화수목금토일])(?:요일)?');
      final weekRelMatch = weekRelRegex.firstMatch(cleaned);
      if (weekRelMatch != null) {
        final rel = weekRelMatch.group(1)!;
        final weekdayStr = weekRelMatch.group(2)!;
        final targetWeekday = _weekdayFromKorean(weekdayStr);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          int diff = targetWeekday - now.weekday;
          int weeksAdd = 0;
          if (rel == '다음주') weeksAdd = 7;
          if (rel == '다다음주') weeksAdd = 14;
          parsedDate = now.add(Duration(days: diff + weeksAdd));
          hasDate = true;
          cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
        }
      }
    }

    // 3. Check "오늘", "내일", "모레"
    if (!hasDate) {
      if (cleaned.contains('오늘')) {
        parsedDate = DateTime.now();
        hasDate = true;
        cleaned = cleaned.replaceAll('오늘', '').trim();
      } else if (cleaned.contains('내일')) {
        parsedDate = DateTime.now().add(const Duration(days: 1));
        hasDate = true;
        cleaned = cleaned.replaceAll('내일', '').trim();
      } else if (cleaned.contains('모레')) {
        parsedDate = DateTime.now().add(const Duration(days: 2));
        hasDate = true;
        cleaned = cleaned.replaceAll('모레', '').trim();
      }
    }

    // 4. Check bare "[요일]요일" or "[요일]"
    if (!hasDate) {
      final bareWeekdayRegex = RegExp(r'([월화수목금토일])요일');
      final bareWeekdayMatch = bareWeekdayRegex.firstMatch(cleaned);
      if (bareWeekdayMatch != null) {
        final weekdayStr = bareWeekdayMatch.group(1)!;
        final targetWeekday = _weekdayFromKorean(weekdayStr);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          int diff = targetWeekday - now.weekday;
          if (diff < 0) diff += 7;
          parsedDate = now.add(Duration(days: diff));
          hasDate = true;
          cleaned = cleaned.replaceFirst(bareWeekdayMatch.group(0)!, '').trim();
        }
      }
    }

    // Parse Time: e.g. "3시", "오후 3시 반", "오전 11시 10분"
    TimeOfDay? parsedTime;
    bool hasTime = false;
    final timeRegex = RegExp(
      r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?(?:\s*(?:에|쯤|경|까지))?',
    );
    final timeMatch = timeRegex.firstMatch(cleaned);
    if (timeMatch != null) {
      final prefix = (timeMatch.group(1) ?? '').replaceAll(RegExp(r'\s'), '');
      final rawHour = int.tryParse(timeMatch.group(2)!) ?? 0;
      int minute = 0;
      if (timeMatch.group(3) != null) {
        minute = int.tryParse(timeMatch.group(3)!) ?? 0;
      } else if (timeMatch.group(0)!.contains('반')) {
        minute = 30;
      }

      if (rawHour >= 1 && rawHour <= 24) {
        int hour24 = rawHour;
        if (prefix == '오전' || prefix == '아침') {
          hour24 = rawHour == 12 ? 0 : rawHour;
        } else if (prefix == '오후' || prefix == '저녁' || prefix == '밤') {
          hour24 = rawHour == 12 ? 12 : rawHour + 12;
        } else {
          if (rawHour < 12) {
            final now = DateTime.now();
            if (now.hour > rawHour ||
                (now.hour == rawHour && now.minute >= minute)) {
              hour24 = rawHour + 12;
            }
          }
        }
        parsedTime = TimeOfDay(hour: hour24, minute: minute);
        hasTime = true;
        cleaned = cleaned.replaceFirst(timeMatch.group(0)!, '').trim();
      }
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    return ParsedVoiceRegistration(
      title: cleaned.isEmpty ? "새 일정" : cleaned,
      date: parsedDate,
      time: parsedTime,
      hasDate: hasDate,
      hasTime: hasTime,
      repeatRule: repeatRule,
      rawSpeech: input,
    );
  }

  void _showVoiceRegistrationConfirmDialog(
    String speechText, {
    required bool isToday,
  }) {
    if (_isConfirmDialogShowing) return;
    _isConfirmDialogShowing = true;

    final defaultDate = isToday ? DateTime.now() : _calSelectedDay;
    final parsed = _parseNaturalLanguageVoice(speechText, defaultDate);

    final titleCtrl = TextEditingController(text: parsed.title);
    DateTime confirmedDate = parsed.date;
    TimeOfDay? confirmedTime = parsed.time;
    Map<String, dynamic>? confirmedRepeatRule = parsed.repeatRule;
    bool isReminderEnabled =
        _isCoreReminderEnabledGlobally && confirmedTime != null;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text('📌', style: TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              '일정 등록 제안',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1E2D),
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(ctx),
                          child: const Icon(
                            Icons.close,
                            color: Color(0xFF9CA3AF),
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    // Editable Title
                    TextField(
                      controller: titleCtrl,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1E1E2D),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 18),
                    // Date and Time Badges (Row or Wrap)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        // Date Badge
                        GestureDetector(
                          onTap: () async {
                            final d = await showDatePicker(
                              context: context,
                              initialDate: confirmedDate,
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 365),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365 * 2),
                              ),
                            );
                            if (d != null) {
                              setDialogState(() => confirmedDate = d);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '📅',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getVoiceDateLabel(confirmedDate),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF4B5563),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Time Badge
                        GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: confirmedTime ?? TimeOfDay.now(),
                            );
                            if (t != null) {
                              setDialogState(() {
                                confirmedTime = t;
                                isReminderEnabled =
                                    _isCoreReminderEnabledGlobally;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '🕒',
                                  style: TextStyle(fontSize: 13),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  confirmedTime != null
                                      ? _getVoiceTimeLabel(confirmedTime!)
                                      : "시간 설정 안 함",
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF8B7CFF),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: Color(0xFF8B7CFF),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (confirmedRepeatRule != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F3FF),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFFD9D0FF),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.repeat_rounded,
                                  size: 15,
                                  color: _coach.accentColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _repeatRuleLabel(confirmedRepeatRule),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setDialogState(
                                    () => confirmedRepeatRule = null,
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Alarm Toggle Button
                    GestureDetector(
                      onTap: () async {
                        if (!isReminderEnabled) {
                          final globalEnabled =
                              await _checkCoreReminderEnabledGlobally();
                          if (!globalEnabled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('설정에서 일정 알람을 먼저 켜주세요.'),
                              ),
                            );
                            return;
                          }
                        }
                        if (confirmedTime == null) {
                          _showSelectTimeBeforeReminderSnackBar();
                          return;
                        }
                        setDialogState(
                          () => isReminderEnabled = !isReminderEnabled,
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFF1E1E2D),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🔔', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 6),
                            Text(
                              isReminderEnabled ? '알람 ON' : '알람 OFF',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1E2D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Bottom Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E1E2D),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () {
                              final finalTitle = titleCtrl.text.trim();
                              if (finalTitle.isEmpty) return;

                              final nowMs =
                                  DateTime.now().millisecondsSinceEpoch;
                              final createdAt = DateTime.now()
                                  .toIso8601String();
                              final repeatRule = confirmedRepeatRule;
                              final repeatDates = repeatRule == null
                                  ? [confirmedDate]
                                  : _datesForScheduleRepeat(
                                      confirmedDate,
                                      repeatRule,
                                    );
                              final recurrenceGroupId = repeatRule == null
                                  ? null
                                  : 'repeat_$nowMs';

                              setState(() {
                                for (var i = 0; i < repeatDates.length; i++) {
                                  final dateStr = _dateKey(repeatDates[i]);
                                  final entry = ScheduleItem(
                                    id: repeatRule == null
                                        ? nowMs.toString()
                                        : '${nowMs}_$i',
                                    text: finalTitle,
                                    createdAt: createdAt,
                                    isReminderEnabled:
                                        isReminderEnabled &&
                                        _isCoreReminderEnabledGlobally &&
                                        confirmedTime != null,
                                    isRecurring: repeatRule != null,
                                    recurrenceGroupId: recurrenceGroupId,
                                    recurrenceRule: repeatRule == null
                                        ? null
                                        : {
                                            ...repeatRule,
                                            'startDate': _dateKey(
                                              confirmedDate,
                                            ),
                                          },
                                  );

                                  if (confirmedTime != null) {
                                    entry.timeStart =
                                        "${confirmedTime!.hour}:${confirmedTime!.minute}";
                                    entry.time = _formatTime(confirmedTime!);
                                  }

                                  schedules.putIfAbsent(dateStr, () => []);
                                  schedules[dateStr]!.add(entry);
                                }
                              });

                              if (isToday) {
                                _todayInputCtrl.clear();
                              } else {
                                _schInputCtrl.clear();
                              }

                              _saveSchedules();
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '"${finalTitle}" 일정을 추가했다냥! 🐾',
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Text(
                              '추가하기 ✓',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFF3F4F6),
                              foregroundColor: const Color(0xFF4B5563),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              '괜찮아',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      _isConfirmDialogShowing = false;
    });
  }

  String _getVoiceDateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    final ymd =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    if (diff == 0) return "오늘 ($ymd)";
    if (diff == 1) return "내일 ($ymd)";
    if (diff == 2) return "모레 ($ymd)";

    final weekdays = ["월요일", "화요일", "수요일", "목요일", "금요일", "토요일", "일요일"];
    final w = weekdays[date.weekday - 1];
    return "$w ($ymd)";
  }

  String _getVoiceTimeLabel(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    final isPm = hour >= 12;
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');
    final ampm = isPm ? "오후" : "오전";
    return "$ampm $displayHour:$displayMinute";
  }

  List<MilestoneWithVision> _getMilestonesForDay(DateTime day) {
    final list = <MilestoneWithVision>[];
    final dateStr = _dateKey(day);
    for (final v in visions) {
      for (final m in v.milestones) {
        if (m.date == dateStr) {
          list.add(MilestoneWithVision(m, v));
        }
      }
    }
    return list;
  }

  MilestoneInfo? _getMilestoneInfoForTask(dynamic item) {
    if (item == null) return null;
    final tIdStr = item.id.toString();

    // Check if it is a virtual milestone task itself
    if (tIdStr.startsWith('milestone_')) {
      for (final v in visions) {
        for (final m in v.milestones) {
          final mId = 'milestone_${v.name}_${m.text}';
          if (mId == tIdStr) {
            return MilestoneInfo(
              visionName: v.name,
              milestoneText: m.text,
              isMilestoneSelf: true,
              vision: v,
              milestone: m,
            );
          }
        }
      }
    }

    // Check if it is a converted action candidate task
    final schedIdStr = tIdStr.startsWith('schedule_')
        ? tIdStr.replaceAll('schedule_', '')
        : null;

    for (final v in visions) {
      for (final m in v.milestones) {
        if (m.actionCandidates != null) {
          for (final action in m.actionCandidates!) {
            final actTaskIdStr = action.convertedTaskId?.toString();
            if (actTaskIdStr != null) {
              if (actTaskIdStr == tIdStr ||
                  actTaskIdStr == schedIdStr ||
                  (schedIdStr != null && actTaskIdStr == schedIdStr) ||
                  (item is ScheduleItem && actTaskIdStr == item.id.toString())) {
                return MilestoneInfo(
                  visionName: v.name,
                  milestoneText: m.text,
                  isMilestoneSelf: false,
                  vision: v,
                  milestone: m,
                );
              }
            }
          }
        }
      }
    }
    return null;
  }

  Widget _buildCalendarCell(
    DateTime day, {
    required bool isSelected,
    required bool isToday,
    required bool isOutside,
  }) {
    final dateStr = _dateKey(day);
    final hasEvents = schedules[dateStr]?.isNotEmpty ?? false;
    final dayMilestones = _getMilestonesForDay(day);
    final hasMilestones = dayMilestones.isNotEmpty;

    // Style text
    TextStyle textStyle;
    if (isSelected) {
      textStyle = GoogleFonts.notoSansKr(
        fontSize: 12,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      );
    } else if (isToday) {
      textStyle = GoogleFonts.notoSansKr(
        fontSize: 12,
        color: const Color(0xFF3D3A4E),
        fontWeight: FontWeight.w700,
      );
    } else if (isOutside) {
      textStyle = GoogleFonts.notoSansKr(
        fontSize: 12,
        color: const Color(0xFFCCCCCC),
      );
    } else if (day.weekday == DateTime.saturday ||
        day.weekday == DateTime.sunday) {
      textStyle = GoogleFonts.notoSansKr(
        fontSize: 12,
        color: const Color(0xFFE05C5C),
      );
    } else {
      textStyle = GoogleFonts.notoSansKr(
        fontSize: 12,
        color: const Color(0xFF3D3A4E),
      );
    }

    // Decoration
    BoxDecoration? decoration;
    if (isSelected) {
      decoration = BoxDecoration(
        color: _coach.accentColor,
        shape: BoxShape.circle,
      );
    } else if (isToday) {
      decoration = BoxDecoration(
        color: _coach.accentColor.withOpacity(0.3),
        shape: BoxShape.circle,
      );
    }

    return Container(
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: decoration,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text('${day.day}', style: textStyle),
          if (hasMilestones)
            Positioned(
              top: -6,
              right: -6,
              child: Icon(
                dayMilestones.every((m) => m.milestone.done)
                    ? Icons.diamond
                    : Icons.flag,
                size: 10,
                color: const Color(0xFFC084FC), // 연보라색
              ),
            ),
          if (hasEvents)
            Positioned(
              bottom: -4,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : _coach.accentColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScheduleTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: Column(
        children: [
          // 상단: 달력
          Container(
            color: Colors.white,
            padding: const EdgeInsets.only(bottom: 8),
            child: TableCalendar(
              locale: 'ko_KR',
              calendarFormat: CalendarFormat.month,
              rowHeight: 28,
              daysOfWeekHeight: 24,
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2050, 12, 31),
              focusedDay: _calFocusedDay,
              selectedDayPredicate: (day) => isSameDay(_calSelectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _calSelectedDay = selectedDay;
                  _calFocusedDay = focusedDay;
                });
              },
              eventLoader: (day) {
                return schedules[_dateKey(day)] ?? [];
              },
              calendarBuilders: CalendarBuilders(
                defaultBuilder: (context, day, focusedDay) =>
                    _buildCalendarCell(
                      day,
                      isSelected: false,
                      isToday: false,
                      isOutside: false,
                    ),
                selectedBuilder: (context, day, focusedDay) =>
                    _buildCalendarCell(
                      day,
                      isSelected: true,
                      isToday: false,
                      isOutside: false,
                    ),
                todayBuilder: (context, day, focusedDay) => _buildCalendarCell(
                  day,
                  isSelected: false,
                  isToday: true,
                  isOutside: false,
                ),
                outsideBuilder: (context, day, focusedDay) =>
                    _buildCalendarCell(
                      day,
                      isSelected: false,
                      isToday: false,
                      isOutside: true,
                    ),
              ),
              calendarStyle: CalendarStyle(
                cellMargin: const EdgeInsets.all(2),
                markerSize: 4,
                markerDecoration: BoxDecoration(
                  color: _coach.accentColor,
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: _coach.accentColor,
                  shape: BoxShape.circle,
                ),
                todayDecoration: BoxDecoration(
                  color: _coach.accentColor.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                defaultTextStyle: GoogleFonts.notoSansKr(fontSize: 12),
                weekendTextStyle: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: const Color(0xFFE05C5C),
                ),
                outsideTextStyle: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: const Color(0xFFCCCCCC),
                ),
                selectedTextStyle: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                todayTextStyle: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: const Color(0xFF3D3A4E),
                  fontWeight: FontWeight.w700,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: const Color(0xFF9CA3AF),
                ),
                weekendStyle: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  color: const Color(0xFFE05C5C),
                ),
              ),
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: const EdgeInsets.symmetric(vertical: 6),
                titleTextStyle: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D3A4E),
                ),
                leftChevronIcon: const Icon(
                  Icons.chevron_left,
                  size: 20,
                  color: Color(0xFF6B7280),
                ),
                rightChevronIcon: const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ),
          // 중단: 일정 목록 (스크롤)
          Expanded(
            child: SingleChildScrollView(child: _buildScheduleListOnly()),
          ),
          // 하단: 일정 등록 영역 (고정)
          _buildScheduleInputArea(),
        ],
      ),
    );
  }

  Widget _buildScheduleListOnly() {
    final dateStr = _dateKey(_calSelectedDay);
    final daySch = schedules[dateStr] ?? [];
    final dayMilestones = _getMilestonesForDay(_calSelectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_calSelectedDay.year}년 ${_calSelectedDay.month}월 ${_calSelectedDay.day}일 스케줄',
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ],
          ),
        ),

        // 마일스톤들 (맨 위에 렌더링)
        if (dayMilestones.isNotEmpty) ...[
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dayMilestones.length,
            itemBuilder: (ctx, i) {
              final m = dayMilestones[i];
              final isDone = m.milestone.done;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFF8FCFA)
                      : const Color(0xFFF3F0FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFFDFF8EE)
                        : const Color(0xFFD8D0FA),
                  ),
                ),
                child: Stack(
                  children: [
                    Row(
                      children: [
                        // 마일스톤 완료 체크 박스
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              m.milestone.done = !m.milestone.done;
                              if (m.milestone.done) {
                                final now = DateTime.now();
                                m.milestone.achievedDate =
                                    "${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}";
                              } else {
                                m.milestone.achievedDate = null;
                              }
                            });
                            _saveVisions();
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDone
                                  ? const Color(0xFF5AD7B0)
                                  : Colors.white,
                              border: Border.all(
                                color: isDone
                                    ? const Color(0xFF5AD7B0)
                                    : const Color(0xFF8B7CFF),
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: isDone
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : const Icon(
                                    Icons.flag,
                                    color: Color(0xFF8B7CFF),
                                    size: 16,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 마일스톤 텍스트
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _showVisionModal(m.vision);
                            },
                            child: Container(
                              color: Colors.transparent,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0E0FF),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          '마일스톤',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF5A50E6),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          m.vision.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            color: const Color(0xFF7C6EFA),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    m.milestone.text.isNotEmpty
                                        ? m.milestone.text
                                        : '단계 목표 없음',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF3D3A4E),
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  if ((m.milestone.memo != null &&
                                          m.milestone.memo!.isNotEmpty) ||
                                      (m.milestone.memoSections != null &&
                                          m
                                              .milestone
                                              .memoSections!
                                              .isNotEmpty) ||
                                      (m.milestone.actionCandidates != null &&
                                          m
                                              .milestone
                                              .actionCandidates!
                                              .isNotEmpty)) ...[
                                    const SizedBox(height: 6),
                                    MilestoneMemoDisplayWidget(
                                      milestone: m.milestone,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        color: const Color(0xFF6B7280),
                                        height: 1.5,
                                      ),
                                      maxLines: 1,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isDone) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDFF8EE),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.check,
                                  size: 12,
                                  color: Color(0xFF33A883),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '완료',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF33A883),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right,
                          color: Color(0xFFCCCCCC),
                          size: 20,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],

        // 일반 일정 목록
        if (daySch.isEmpty && dayMilestones.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '등록된 일정이 없습니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: const Color(0xFFA0A0B0),
                ),
              ),
            ),
          )
        else if (daySch.isNotEmpty)
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: daySch.length,
            itemBuilder: (ctx, i) {
              final s = daySch[i];
              final milestoneInfo = _getMilestoneInfoForTask(s);
              final isMilestone = milestoneInfo != null;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE8E3F8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isMilestone) ...[
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0E0FF),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              milestoneInfo.isMilestoneSelf ? '마일스톤' : '메모장의 실행 목록',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF5A50E6),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              milestoneInfo.visionName,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                color: const Color(0xFF7C6EFA),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              if (isMilestone) {
                                _showMemoDialog(context, milestoneInfo.milestone, (fn) => setState(fn));
                              } else {
                                _showEditItemModal(s, () {
                                  setState(() {});
                                  _saveSchedules();
                                });
                              }
                            },
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                s.text,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF3D3A4E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (s.isReminderEnabled)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.notifications_active,
                              size: 16,
                              color: _coach.accentColor.withOpacity(0.7),
                            ),
                          ),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              daySch.removeAt(i);
                              if (daySch.isEmpty) {
                                schedules.remove(dateStr);
                              }
                            });
                            _saveSchedules();
                          },
                          child: const Icon(
                            Icons.close,
                            color: Color(0xFFD1D5DB),
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        if (isMilestone) {
                          _showMemoDialog(context, milestoneInfo.milestone, (fn) => setState(fn));
                        } else {
                          _showEditItemModal(s, () {
                            setState(() {});
                            _saveSchedules();
                          });
                        }
                      },
                      child:
                          (s.time != null ||
                              s.duration != null ||
                              s.isRecurring)
                          ? Row(
                              children: [
                                if (s.time != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF5F3FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      s.time!,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF8B7CFF),
                                      ),
                                    ),
                                  ),
                                if (s.duration != null)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFDF2F8),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '⏱ ${s.duration}',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFFDB2777),
                                      ),
                                    ),
                                  ),
                                if (s.isRecurring)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: BoxDecoration(
                                      color: _coach.accentColor.withOpacity(
                                        0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.repeat_rounded,
                                          size: 12,
                                          color: _coach.accentColor,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          _repeatRuleLabel(s.recurrenceRule),
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800,
                                            color: _coach.accentColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            )
                          : Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    Icons.access_time,
                                    size: 16,
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Future<void> _showScheduleRepeatDialog() async {
    String repeatType = _schRepeatRule?['type']?.toString() ?? 'weekly';
    String monthlyMode = _schRepeatRule?['monthlyMode']?.toString() ?? 'date';
    final selectedWeekdays =
        ((_schRepeatRule?['weekdays'] as List?)
            ?.map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toSet() ??
        {_calSelectedDay.weekday});
    int dayOfMonth =
        int.tryParse(_schRepeatRule?['dayOfMonth']?.toString() ?? '') ??
        _calSelectedDay.day;
    int nth = int.tryParse(_schRepeatRule?['nth']?.toString() ?? '') ?? 1;
    int monthlyWeekday =
        int.tryParse(_schRepeatRule?['weekday']?.toString() ?? '') ??
        _calSelectedDay.weekday;
    String endType = _schRepeatRule?['endType']?.toString() ?? 'never';
    DateTime? endDate = DateTime.tryParse(
      _schRepeatRule?['endDate']?.toString() ?? '',
    );
    final countCtrl = TextEditingController(
      text: _schRepeatRule?['count']?.toString() ?? '10',
    );
    final dayCtrl = TextEditingController(text: dayOfMonth.toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Widget weekdayChip(int weekday) {
              final active = selectedWeekdays.contains(weekday);
              return GestureDetector(
                onTap: () {
                  setDialogState(() {
                    if (active && selectedWeekdays.length > 1) {
                      selectedWeekdays.remove(weekday);
                    } else {
                      selectedWeekdays.add(weekday);
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? _coach.accentColor : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active
                          ? _coach.accentColor
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Text(
                    _weekdayLabel(weekday),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: active ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              );
            }

            InputDecoration inputDecoration(String hint) => InputDecoration(
              hintText: hint,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _coach.accentColor, width: 1.5),
              ),
            );

            Widget radioRow({
              required String value,
              required String label,
              required Widget trailing,
            }) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Radio<String>(
                      value: value,
                      groupValue: endType,
                      activeColor: _coach.accentColor,
                      onChanged: (v) => setDialogState(() => endType = v!),
                    ),
                    SizedBox(
                      width: 72,
                      child: Text(
                        label,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                    ),
                    Expanded(child: trailing),
                  ],
                ),
              );
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 28),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '사용자 지정',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(dialogContext),
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFFB8B5C8),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          SizedBox(
                            width: 92,
                            child: Text(
                              '반복 주기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF3D3A4E),
                              ),
                            ),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: repeatType,
                              decoration: inputDecoration('반복 주기'),
                              items: const [
                                DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('매일'),
                                ),
                                DropdownMenuItem(
                                  value: 'weekly',
                                  child: Text('매주'),
                                ),
                                DropdownMenuItem(
                                  value: 'monthly',
                                  child: Text('매월'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setDialogState(() => repeatType = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      if (repeatType == 'weekly') ...[
                        const SizedBox(height: 18),
                        Text(
                          '반복 요일',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            7,
                            1,
                            2,
                            3,
                            4,
                            5,
                            6,
                          ].map(weekdayChip).toList(),
                        ),
                      ],
                      if (repeatType == 'monthly') ...[
                        const SizedBox(height: 18),
                        Text(
                          '매월 반복 방식',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'date', label: Text('날짜')),
                            ButtonSegment(
                              value: 'nthWeekday',
                              label: Text('몇째주 요일'),
                            ),
                          ],
                          selected: {monthlyMode},
                          onSelectionChanged: (set) =>
                              setDialogState(() => monthlyMode = set.first),
                        ),
                        const SizedBox(height: 12),
                        if (monthlyMode == 'date')
                          TextField(
                            controller: dayCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: inputDecoration(
                              '예: 11',
                            ).copyWith(suffixText: '일'),
                          )
                        else
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: nth,
                                  decoration: inputDecoration('몇째주'),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 1,
                                      child: Text('1째주'),
                                    ),
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2째주'),
                                    ),
                                    DropdownMenuItem(
                                      value: 3,
                                      child: Text('3째주'),
                                    ),
                                    DropdownMenuItem(
                                      value: 4,
                                      child: Text('4째주'),
                                    ),
                                    DropdownMenuItem(
                                      value: 5,
                                      child: Text('5째주'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setDialogState(() => nth = v);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: monthlyWeekday,
                                  decoration: inputDecoration('요일'),
                                  items: [7, 1, 2, 3, 4, 5, 6]
                                      .map(
                                        (w) => DropdownMenuItem(
                                          value: w,
                                          child: Text('${_weekdayLabel(w)}요일'),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) {
                                    if (v != null) {
                                      setDialogState(() => monthlyWeekday = v);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                      ],
                      const SizedBox(height: 18),
                      Text(
                        '종료',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                      const SizedBox(height: 8),
                      radioRow(
                        value: 'never',
                        label: '종료 안함',
                        trailing: const SizedBox.shrink(),
                      ),
                      radioRow(
                        value: 'date',
                        label: '날짜 지정',
                        trailing: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate:
                                  endDate ??
                                  _calSelectedDay.add(const Duration(days: 30)),
                              firstDate: _calSelectedDay,
                              lastDate: DateTime(_calSelectedDay.year + 5),
                            );
                            if (picked != null) {
                              setDialogState(() {
                                endDate = picked;
                                endType = 'date';
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 11,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  endDate == null
                                      ? '날짜 선택'
                                      : '${endDate!.year}. ${endDate!.month.toString().padLeft(2, '0')}. ${endDate!.day.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                                const Icon(
                                  Icons.calendar_today_rounded,
                                  size: 16,
                                  color: Color(0xFF8B7CFF),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      radioRow(
                        value: 'count',
                        label: '반복 횟수',
                        trailing: TextField(
                          controller: countCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: inputDecoration(
                            '10',
                          ).copyWith(suffixText: '회'),
                          onTap: () => setDialogState(() => endType = 'count'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: () {
                            final rule = <String, dynamic>{
                              'type': repeatType,
                              'endType': endType,
                            };
                            if (repeatType == 'weekly') {
                              rule['weekdays'] = selectedWeekdays.toList();
                            } else if (repeatType == 'monthly') {
                              rule['monthlyMode'] = monthlyMode;
                              if (monthlyMode == 'date') {
                                rule['dayOfMonth'] =
                                    int.tryParse(dayCtrl.text) ??
                                    _calSelectedDay.day;
                              } else {
                                rule['nth'] = nth;
                                rule['weekday'] = monthlyWeekday;
                              }
                            }
                            if (endType == 'date' && endDate != null) {
                              rule['endDate'] = _dateKey(endDate!);
                            }
                            if (endType == 'count') {
                              rule['count'] =
                                  int.tryParse(countCtrl.text) ?? 10;
                            }
                            setState(() {
                              _schRepeatEnabled = true;
                              _schRepeatRule = rule;
                            });
                            Navigator.pop(dialogContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _coach.accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '적용',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    countCtrl.dispose();
    dayCtrl.dispose();
  }

  Widget _buildScheduleInputArea() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;

    // Bottom padding: when keyboard is open, pad by bottomInset.
    // When keyboard is closed, pad by SafeArea bottom padding + some default padding (e.g. 16).
    final double paddingBottom = isKeyboardOpen
        ? bottomInset + 16
        : (16.0 + MediaQuery.of(context).padding.bottom);

    Widget scheduleModeButton(String type, {bool isLast = false}) {
      const labels = {
        'single': '특정 시간',
        'range': '시간 범위',
        'duration': '소요 시간',
        'repeat': '반복',
      };
      final isRepeat = type == 'repeat';
      final isActive = isRepeat ? _schRepeatEnabled : _schTimeType == type;

      return Expanded(
        child: GestureDetector(
          onTap: () async {
            if (isRepeat) {
              await _showScheduleRepeatDialog();
              return;
            }
            setState(() {
              _schTimeType = _schTimeType == type ? 'none' : type;
              _schReminderEnabled = false;
              _schStartTime = null;
              _schEndTime = null;
              if (type != 'duration') _schDuration = null;
            });
          },
          child: Container(
            margin: EdgeInsets.only(right: isLast ? 0 : 6),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: isActive
                  ? _coach.accentColor.withOpacity(0.08)
                  : Colors.white,
              border: Border.all(
                color: isActive ? _coach.accentColor : const Color(0xFFE5E7EB),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isRepeat) ...[
                  Icon(
                    Icons.repeat_rounded,
                    size: 16,
                    color: isActive
                        ? _coach.accentColor
                        : const Color(0xFF9CA3AF),
                  ),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    labels[type]!,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isActive
                          ? _coach.accentColor
                          : const Color(0xFF9CA3AF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, paddingBottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 시간 설정 UI
          Row(
            children: [
              scheduleModeButton('single'),
              scheduleModeButton('range'),
              scheduleModeButton('duration'),
              scheduleModeButton('repeat', isLast: true),
            ],
          ),
          if (_schTimeType == 'single' || _schTimeType == 'range')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Text(
                    _schTimeType == 'range' ? '시작: ' : '시간: ',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: _schStartTime ?? TimeOfDay.now(),
                      );
                      if (t != null) {
                        setState(() {
                          _schStartTime = t;
                          _schReminderEnabled = _isCoreReminderEnabledGlobally;
                        });
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _schStartTime != null
                            ? _formatTime(_schStartTime!)
                            : '선택',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          color: _schStartTime != null
                              ? _coach.accentColor
                              : const Color(0xFFA0A0B0),
                        ),
                      ),
                    ),
                  ),
                  if (_schTimeType == 'range') ...[
                    const SizedBox(width: 8),
                    Text(
                      '~',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '종료: ',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: _schEndTime ?? TimeOfDay.now(),
                        );
                        if (t != null) setState(() => _schEndTime = t);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _schEndTime != null
                              ? _formatTime(_schEndTime!)
                              : '선택',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: _schEndTime != null
                                ? _coach.accentColor
                                : const Color(0xFFA0A0B0),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () async {
                      final enabled = await _checkCoreReminderEnabledGlobally();
                      if (!enabled) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('설정에서 일정 알람을 켜주세요.'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        return;
                      }
                      if (_schStartTime == null) {
                        _showSelectTimeBeforeReminderSnackBar();
                        return;
                      }
                      setState(
                        () => _schReminderEnabled = !_schReminderEnabled,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color:
                            _resolvedTimeReminderEnabled(
                              _schTimeType,
                              _schStartTime,
                              _schReminderEnabled,
                            )
                            ? _coach.accentColor.withOpacity(0.12)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        !_isCoreReminderEnabledGlobally
                            ? Icons.notifications_off
                            : (_resolvedTimeReminderEnabled(
                                    _schTimeType,
                                    _schStartTime,
                                    _schReminderEnabled,
                                  )
                                  ? Icons.notifications_active
                                  : Icons.notifications_off),
                        size: 18,
                        color:
                            _resolvedTimeReminderEnabled(
                              _schTimeType,
                              _schStartTime,
                              _schReminderEnabled,
                            )
                            ? _coach.accentColor
                            : const Color(0xFFB0B0C8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_schTimeType == 'duration')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['10분', '15분', '30분', '1시간', '2시간', '3시간', '4시간+']
                    .map((d) {
                      final isActive = _schDuration == d;
                      return GestureDetector(
                        onTap: () => setState(() => _schDuration = d),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFFFDF2F8)
                                : Colors.white,
                            border: Border.all(
                              color: isActive
                                  ? const Color(0xFFDB2777)
                                  : const Color(0xFFE5E7EB),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            d,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              color: isActive
                                  ? const Color(0xFFDB2777)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFDDD6FE)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _schInputCtrl,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              color: const Color(0xFF3D3A4E),
                            ),
                            decoration: InputDecoration(
                              hintText: '일정 입력...',
                              hintStyle: GoogleFonts.notoSansKr(
                                color: const Color(0xFFA0A0B0),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (v) => _addSchedule(),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            if (_isListeningSchedule) {
                              _stopListening();
                            } else {
                              _startListening(isToday: false);
                            }
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _isListeningSchedule
                                  ? Colors.red.withOpacity(0.1)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isListeningSchedule ? Icons.mic : Icons.mic_none,
                              size: 18,
                              color: _isListeningSchedule
                                  ? Colors.red
                                  : const Color(0xFF8B7CFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _addSchedule,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _coach.accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 습관 탭 ──────────────────────────────────────────────
  Widget _buildHabitTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: Column(
        children: [
          Expanded(
            child: habits.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🌱', style: TextStyle(fontSize: 40)),
                        const SizedBox(height: 12),
                        Text(
                          '습관을 추가해봐요!',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            color: const Color(0xFFA0A0B0),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: habits.length,
                    itemBuilder: (ctx, i) => _buildHabitItem(habits[i]),
                  ),
          ),
          // 습관 추가 버튼
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 64),
            color: Colors.white,
            child: GestureDetector(
              onTap: () => _showHabitModal(context),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _coach.accentColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '새 습관 추가',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitItem(HabitItem h) {
    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    final freqLabel = h.freq == 'daily'
        ? '매일'
        : h.days.map((d) => dayNames[d]).join('/');
    String checkLabel = '체크';
    if (h.checkType == 'count') {
      checkLabel = '${h.countGoal ?? 0}${h.unit ?? '번'}';
    } else if (h.checkType == 'duration') {
      checkLabel = '${h.durationGoal ?? 0}분';
    } else if (h.checkType == 'both') {
      checkLabel =
          '${h.countGoal ?? 0}${h.unit ?? '번'} + ${h.durationGoal ?? 0}분';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE8E4F0)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                h.name,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _showHabitModal(context, editHabit: h),
                    child: const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      color: Color(0xFFA0A0B0),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _deleteHabit(h.id),
                    child: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: [
              _habitTag(
                freqLabel,
                _coach.accentColor,
                _coach.accentColor.withOpacity(0.1),
              ),
              _habitTag(
                checkLabel,
                const Color(0xFF6B7280),
                const Color(0xFFF3F4F6),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _habitTag(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Future<void> _deleteHabit(dynamic id) async {
    final confirm = await _showConfirmDeleteDialog('습관 항목 삭제', '이 습관을 정말 삭제하시겠습니까?\\n연결된 오늘의 할 일도 함께 삭제됩니다.');
    if (!confirm) return;
    setState(() => habits.removeWhere((h) => h.id.toString() == id.toString()));
    _saveHabits();
    _injectTodayHabits();
  }

  // ── 습관 추가 모달 (웹앱 openHabitModal 이식) ────────────
  void _showHabitModal(BuildContext context, {HabitItem? editHabit}) {
    final nameCtrl = TextEditingController(text: editHabit?.name ?? '');
    String freq = editHabit?.freq ?? 'daily';
    List<int> days = List.from(editHabit?.days ?? []);
    String checkType = editHabit?.checkType ?? 'check';
    bool tracking = editHabit?.tracking ?? true;
    String timeType = editHabit?.timeType ?? 'none';
    TimeOfDay? mStartTime;
    TimeOfDay? mEndTime;
    if (editHabit?.timeStart != null) {
      final parts = editHabit!.timeStart!.split(':');
      mStartTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
    if (editHabit?.timeEnd != null) {
      final parts = editHabit!.timeEnd!.split(':');
      mEndTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    }
    String? mDuration = editHabit?.habitDuration;
    bool mReminderEnabled =
        _isCoreReminderEnabledGlobally &&
        (editHabit?.isReminderEnabled ?? true);

    final countCtrl = TextEditingController(
      text: editHabit?.countGoal?.toString() ?? '',
    );
    final unitCtrl = TextEditingController(text: editHabit?.unit ?? '');
    final durationCtrl = TextEditingController(
      text: editHabit?.durationGoal?.toString() ?? '',
    );

    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // 핸들
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      editHabit != null ? '습관 수정' : '새 습관 추가',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(Icons.close, color: Color(0xFFA0A0B0)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 습관 이름
                      _modalLabel('습관 이름'),
                      Material(
                        type: MaterialType.transparency,
                        child: TextField(
                          controller: nameCtrl,
                          decoration: _modalInputDeco('예: 운동하기, 독서 30분'),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 빈도
                      _modalLabel('빈도'),
                      Row(
                        children: [
                          _freqBtn(
                            'daily',
                            '매일',
                            freq,
                            (v) => setModalState(() => freq = v),
                          ),
                          const SizedBox(width: 8),
                          _freqBtn(
                            'weekly',
                            '요일 선택',
                            freq,
                            (v) => setModalState(() => freq = v),
                          ),
                        ],
                      ),
                      if (freq == 'weekly') ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          children: List.generate(7, (i) {
                            final isSelected = days.contains(i);
                            return GestureDetector(
                              onTap: () => setModalState(() {
                                if (isSelected)
                                  days.remove(i);
                                else
                                  days.add(i);
                              }),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? _coach.accentColor
                                      : Colors.white,
                                  border: Border.all(
                                    color: isSelected
                                        ? _coach.accentColor
                                        : const Color(0xFFE5E7EB),
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    dayNames[i],
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ],
                      const SizedBox(height: 20),
                      // 체크 방식
                      _modalLabel('체크 방식'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _checkBtn(
                            'count',
                            '수량',
                            checkType,
                            (v) => setModalState(
                              () => checkType = checkType == v ? 'check' : v,
                            ),
                          ),
                          _checkBtn(
                            'duration',
                            '시간',
                            checkType,
                            (v) => setModalState(
                              () => checkType = checkType == v ? 'check' : v,
                            ),
                          ),
                          _checkBtn(
                            'both',
                            '수량+시간',
                            checkType,
                            (v) => setModalState(
                              () => checkType = checkType == v ? 'check' : v,
                            ),
                          ),
                        ],
                      ),
                      if (checkType == 'count' || checkType == 'both') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Material(
                                type: MaterialType.transparency,
                                child: TextField(
                                  controller: countCtrl,
                                  keyboardType: TextInputType.number,
                                  decoration: _modalInputDeco(
                                    '목표 수량 (예: 5000)',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Material(
                                type: MaterialType.transparency,
                                child: TextField(
                                  controller: unitCtrl,
                                  decoration: _modalInputDeco('단위 (예: 보)'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (checkType == 'duration' || checkType == 'both') ...[
                        const SizedBox(height: 12),
                        Material(
                          type: MaterialType.transparency,
                          child: TextField(
                            controller: durationCtrl,
                            keyboardType: TextInputType.number,
                            decoration: _modalInputDeco('목표 시간 (분)'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      // 시간 설정
                      _modalLabel('시간 설정'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _checkBtn(
                            'single',
                            '특정 시간',
                            timeType,
                            (v) => setModalState(
                              () => timeType = timeType == v ? 'none' : v,
                            ),
                          ),
                          _checkBtn(
                            'range',
                            '시간 범위',
                            timeType,
                            (v) => setModalState(
                              () => timeType = timeType == v ? 'none' : v,
                            ),
                          ),
                          _checkBtn(
                            'duration',
                            '소요 시간',
                            timeType,
                            (v) => setModalState(
                              () => timeType = timeType == v ? 'none' : v,
                            ),
                          ),
                        ],
                      ),
                      if (timeType == 'single' || timeType == 'range')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () async {
                                  final t = await showTimePicker(
                                    context: context,
                                    initialTime: mStartTime ?? TimeOfDay.now(),
                                  );
                                  if (t != null)
                                    setModalState(() => mStartTime = t);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFE5E7EB),
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    mStartTime != null
                                        ? _formatTime(mStartTime!)
                                        : '시작 시간 선택',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: mStartTime != null
                                          ? _coach.accentColor
                                          : const Color(0xFFA0A0B0),
                                    ),
                                  ),
                                ),
                              ),
                              if (timeType == 'range') ...[
                                const SizedBox(width: 8),
                                Text(
                                  '~',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () async {
                                    final t = await showTimePicker(
                                      context: context,
                                      initialTime: mEndTime ?? TimeOfDay.now(),
                                    );
                                    if (t != null)
                                      setModalState(() => mEndTime = t);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      mEndTime != null
                                          ? _formatTime(mEndTime!)
                                          : '종료 시간 선택',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        color: mEndTime != null
                                            ? _coach.accentColor
                                            : const Color(0xFFA0A0B0),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  final enabled =
                                      await _checkCoreReminderEnabledGlobally();
                                  if (!enabled) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('설정에서 일정 알람을 켜주세요.'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                    return;
                                  }
                                  setModalState(
                                    () => mReminderEnabled = !mReminderEnabled,
                                  );
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color:
                                        (_isCoreReminderEnabledGlobally &&
                                            mReminderEnabled)
                                        ? _coach.accentColor.withOpacity(0.12)
                                        : Colors.transparent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    !_isCoreReminderEnabledGlobally
                                        ? Icons.notifications_off
                                        : (mReminderEnabled
                                              ? Icons.notifications_active
                                              : Icons.notifications_off),
                                    size: 18,
                                    color:
                                        (_isCoreReminderEnabledGlobally &&
                                            mReminderEnabled)
                                        ? _coach.accentColor
                                        : const Color(0xFFB0B0C8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (timeType == 'duration')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                [
                                  '10분',
                                  '15분',
                                  '30분',
                                  '1시간',
                                  '2시간',
                                  '3시간',
                                  '4시간+',
                                ].map((d) {
                                  final isActive = mDuration == d;
                                  return GestureDetector(
                                    onTap: () =>
                                        setModalState(() => mDuration = d),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFFFDF2F8)
                                            : Colors.white,
                                        border: Border.all(
                                          color: isActive
                                              ? const Color(0xFFDB2777)
                                              : const Color(0xFFE5E7EB),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        d,
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          color: isActive
                                              ? const Color(0xFFDB2777)
                                              : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                          ),
                        ),
                      const SizedBox(height: 20),
                      // 습관 트래킹
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '습관 트래킹',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3D3A4E),
                                ),
                              ),
                              Text(
                                '매일 습관 달성률을 추적할까요?',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  color: const Color(0xFFA0A0B0),
                                ),
                              ),
                            ],
                          ),
                          Switch(
                            value: tracking,
                            onChanged: (v) => setModalState(() => tracking = v),
                            activeColor: _coach.accentColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // 저장 버튼
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: GestureDetector(
                  onTap: () async {
                    // 구독 체크
                    final userData = await UserDataService.load();
                    if (!userData.isPlanActive) {
                      Navigator.pop(ctx); // 모달 닫기
                      if (context.mounted) {
                        _showSubscriptionNotice(context);
                      }
                      return;
                    }

                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    if (freq == 'weekly' && days.isEmpty) return;

                    final habit = HabitItem(
                      id:
                          editHabit?.id ??
                          DateTime.now().millisecondsSinceEpoch,
                      name: name,
                      freq: freq,
                      days: List.from(days),
                      checkType: checkType,
                      timeType: timeType,
                      tracking: tracking,
                      countGoal: (checkType == 'count' || checkType == 'both')
                          ? int.tryParse(countCtrl.text)
                          : null,
                      unit: unitCtrl.text.trim().isEmpty
                          ? null
                          : unitCtrl.text.trim(),
                      durationGoal:
                          (checkType == 'duration' || checkType == 'both')
                          ? int.tryParse(durationCtrl.text)
                          : null,
                      timeStart:
                          (timeType == 'single' || timeType == 'range') &&
                              mStartTime != null
                          ? "${mStartTime!.hour}:${mStartTime!.minute}"
                          : null,
                      timeEnd: timeType == 'range' && mEndTime != null
                          ? "${mEndTime!.hour}:${mEndTime!.minute}"
                          : null,
                      habitDuration: timeType == 'duration' ? mDuration : null,
                      createdAt:
                          editHabit?.createdAt ??
                          DateTime.now().toIso8601String(),
                      isReminderEnabled: mReminderEnabled,
                    );

                    setState(() {
                      if (editHabit != null) {
                        final idx = habits.indexWhere(
                          (h) => h.id.toString() == editHabit.id.toString(),
                        );
                        if (idx >= 0) habits[idx] = habit;
                      } else {
                        habits.add(habit);
                      }
                    });
                    _saveHabits();
                    _injectTodayHabits();
                    Navigator.pop(ctx);
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _coach.accentColor,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        '저장',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSubscriptionNotice(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '⚠️ 구독 플랜 필요',
            style: GoogleFonts.notoSansKr(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          content: Text(
            '습관 등록 및 트래킹은 Friends 또는 Master 플랜 구독자만 이용할 수 있다냥!',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF4B5563),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                '확인',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  color: _coach.accentColor,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _modalLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: GoogleFonts.notoSansKr(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF6B7280),
      ),
    ),
  );

  InputDecoration _modalInputDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.notoSansKr(
      fontSize: 14,
      color: const Color(0xFFA0A0B0),
    ),
    filled: true,
    fillColor: const Color(0xFFF5F3FF),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDD6FE)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDDD6FE)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _coach.accentColor),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  Widget _freqBtn(
    String value,
    String label,
    String current,
    Function(String) onTap,
  ) {
    final isActive = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? _coach.accentColor.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isActive ? _coach.accentColor : const Color(0xFFE5E7EB),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isActive ? _coach.accentColor : const Color(0xFFA0A0B0),
          ),
        ),
      ),
    );
  }

  Widget _checkBtn(
    String value,
    String label,
    String current,
    Function(String) onTap,
  ) {
    final isActive = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? _coach.accentColor.withOpacity(0.1) : Colors.white,
          border: Border.all(
            color: isActive ? _coach.accentColor : const Color(0xFFE5E7EB),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isActive ? _coach.accentColor : const Color(0xFFA0A0B0),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 마일스톤 메모 프리미엄 다이얼로그
// ─────────────────────────────────────────────────────────────
class MilestoneMemoDialog extends StatefulWidget {
  final MilestoneItem milestone;
  final CoachConfig coach;
  final Function(String?) onSave;
  final void Function(ActionCandidate action, String convertType)?
  onConvertAction;

  const MilestoneMemoDialog({
    super.key,
    required this.milestone,
    required this.coach,
    required this.onSave,
    this.onConvertAction,
  });

  @override
  State<MilestoneMemoDialog> createState() => _MilestoneMemoDialogState();
}

class _MilestoneMemoDialogState extends State<MilestoneMemoDialog> {
  static const int _sectionContentMaxLength = 1000;
  static final _memoSummaryProxy =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
        'chatProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

  // --- Phase 1: 다중 섹션 데이터 및 컨트롤러 ---
  List<MemoSection> _sections = [];
  final List<TextEditingController> _titleCtrls = [];
  final List<TextEditingController> _contentCtrls = [];
  final List<FocusNode> _titleFocusNodes = [];
  final List<FocusNode> _contentFocusNodes = [];
  final Set<int> _editingSectionIndexes = {};

  // --- Phase 2: 실행 아이템 데이터 및 컨트롤러 ---
  List<ActionCandidate> _actions = [];
  final List<TextEditingController> _actionCtrls = [];
  final List<FocusNode> _actionFocusNodes = [];

  TextEditingController? _focusedCtrl;
  TextSelection _baseSelection = const TextSelection.collapsed(offset: 0);
  String _baseText = '';

  // --- 음성 인식 ---
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;
  int? _summarizingSectionIndex;

  @override
  void initState() {
    super.initState();
    _migrateAndInitData();
    _initSpeech();
  }

  void _migrateAndInitData() {
    // 1. Sections
    if (widget.milestone.memoSections != null &&
        widget.milestone.memoSections!.isNotEmpty) {
      _sections = List.from(widget.milestone.memoSections!);
    } else {
      String oldMemo = widget.milestone.memo ?? '';
      if (oldMemo.trim().isNotEmpty) {
        _sections.add(MemoSection(title: '기본 메모', content: oldMemo));
      } else {
        _sections.add(MemoSection(title: '', content: ''));
      }
    }

    for (var section in _sections) {
      _addSectionControllers(section.title, section.content);
    }

    // 2. Actions
    if (widget.milestone.actionCandidates != null) {
      _actions = List.from(widget.milestone.actionCandidates!);
    }
    for (var action in _actions) {
      _addActionControllers(action.title);
    }
  }

  void _updateFocus(TextEditingController ctrl, FocusNode node) {
    if (node.hasFocus) {
      _focusedCtrl = ctrl;
      if (mounted) setState(() {});
    }
  }

  void _addSectionControllers(String title, String content) {
    final tCtrl = TextEditingController(text: title);
    final cCtrl = TextEditingController(text: content);
    final tNode = FocusNode();
    final cNode = FocusNode();

    tNode.addListener(() => _updateFocus(tCtrl, tNode));
    cNode.addListener(() => _updateFocus(cCtrl, cNode));

    _titleCtrls.add(tCtrl);
    _contentCtrls.add(cCtrl);
    _titleFocusNodes.add(tNode);
    _contentFocusNodes.add(cNode);
  }

  void _addActionControllers(String title) {
    final aCtrl = TextEditingController(text: title);
    final aNode = FocusNode();

    aNode.addListener(() => _updateFocus(aCtrl, aNode));

    _actionCtrls.add(aCtrl);
    _actionFocusNodes.add(aNode);
  }

  void _addNewSection() {
    setState(() {
      _sections.add(MemoSection(title: '', content: ''));
      _addSectionControllers('', '');
      _editingSectionIndexes.add(_sections.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _titleFocusNodes.last.requestFocus();
    });
  }

  void _removeSection(int index) {
    setState(() {
      _sections.removeAt(index);
      _titleCtrls[index].dispose();
      _contentCtrls[index].dispose();
      _titleFocusNodes[index].dispose();
      _contentFocusNodes[index].dispose();
      _titleCtrls.removeAt(index);
      _contentCtrls.removeAt(index);
      _titleFocusNodes.removeAt(index);
      _contentFocusNodes.removeAt(index);
      final updatedEditingIndexes = _editingSectionIndexes
          .where((editingIndex) => editingIndex != index)
          .map(
            (editingIndex) =>
                editingIndex > index ? editingIndex - 1 : editingIndex,
          )
          .toSet();
      _editingSectionIndexes
        ..clear()
        ..addAll(updatedEditingIndexes);

      if (_sections.isEmpty) {
        _addNewSection();
      }
    });
  }

  void _onReorderSections(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }
      final section = _sections.removeAt(oldIndex);
      _sections.insert(newIndex, section);

      final titleCtrl = _titleCtrls.removeAt(oldIndex);
      _titleCtrls.insert(newIndex, titleCtrl);

      final contentCtrl = _contentCtrls.removeAt(oldIndex);
      _contentCtrls.insert(newIndex, contentCtrl);

      final titleFocus = _titleFocusNodes.removeAt(oldIndex);
      _titleFocusNodes.insert(newIndex, titleFocus);

      final contentFocus = _contentFocusNodes.removeAt(oldIndex);
      _contentFocusNodes.insert(newIndex, contentFocus);

      final wasEditing = _editingSectionIndexes.remove(oldIndex);
      final updatedEditingIndexes = _editingSectionIndexes.map((editingIndex) {
        if (oldIndex < newIndex) {
          if (editingIndex > oldIndex && editingIndex <= newIndex) {
            return editingIndex - 1;
          }
        } else if (newIndex < oldIndex) {
          if (editingIndex >= newIndex && editingIndex < oldIndex) {
            return editingIndex + 1;
          }
        }
        return editingIndex;
      }).toSet();
      _editingSectionIndexes
        ..clear()
        ..addAll(updatedEditingIndexes);
      if (wasEditing) {
        _editingSectionIndexes.add(newIndex);
      }
    });
  }

  void _startEditingSection(int index, {bool focusContent = true}) {
    setState(() {
      _editingSectionIndexes.add(index);
    });
    if (focusContent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _contentFocusNodes[index].requestFocus();
      });
    }
  }

  void _addNewAction() {
    setState(() {
      _actions.add(
        ActionCandidate(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: '',
        ),
      );
      _addActionControllers('');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _actionFocusNodes.last.requestFocus();
    });
  }

  void _removeAction(int index) {
    setState(() {
      _actions.removeAt(index);
      _actionCtrls[index].dispose();
      _actionFocusNodes[index].dispose();
      _actionCtrls.removeAt(index);
      _actionFocusNodes.removeAt(index);
    });
  }

  Future<void> _summarizeSection(int index) async {
    final content = _contentCtrls[index].text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('정리할 내용을 먼저 입력해 주세요.')));
      return;
    }

    final limit = await ApiUsageLimitService.checkOrganizeAllowance();
    if (!limit.allowed) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(limit.message)));
      return;
    }

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _summarizingSectionIndex = index);

    try {
      final title = _titleCtrls[index].text.trim();
      final summary = await _requestMemoSummary(title: title, content: content);

      AnalyticsService.logFeatureUsage('milestone_memo_organize');

      if (!mounted) return;
      await _showSummaryPreviewSheet(
        sectionIndex: index,
        originalContent: content,
        summary: summary,
      );
    } catch (e) {
      debugPrint('Memo summary error: $e');
      if (!mounted) return;
      if (e is ApiUsageLimitException) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() => _summarizingSectionIndex = null);
      }
    }
  }

  Future<String> _requestMemoSummary({
    required String title,
    required String content,
  }) async {
    final prompt =
        '''아래는 장기 목표 마일스톤 메모의 한 섹션입니다. 본문을 사용자가 다시 읽기 쉽게 정리하세요.

[섹션 제목]
${title.isEmpty ? '제목 없음' : title}

[본문]
$content

[정리 규칙]
- 중복 표현을 제거하세요.
- 핵심 항목을 추출하세요.
- 실행 가능한 문장은 더 명확한 행동 문장으로 정리하세요.
- 링크(URL)는 절대 삭제하거나 바꾸지 마세요.
- 링크에 대한 설명이 본문에 있다면 링크와 설명을 함께 보존하세요.
- 사용자의 의도를 과하게 미화하거나 새로운 내용을 지어내지 마세요.
- 꼭 1~3줄로 제한하지 말고, 필요한 만큼만 간결하게 정리하세요.
- 마크다운 헤딩(#)은 쓰지 마세요.
- 결과 본문만 출력하세요.''';

    final messages = [
      {
        'role': 'system',
        'content':
            '당신은 장기 목표 플래너의 메모를 정리하는 편집 AI입니다. 원문 의도와 링크를 보존하면서 중복을 줄이고 핵심과 실행 문장을 명확히 정리합니다.',
      },
      {'role': 'user', 'content': prompt},
    ];

    final estimatedPromptTokens = AnalyticsService.estimateChatTokens(
      messages,
      '',
    );
    await ApiUsageLimitService.ensureChatAllowed(
      estimatedTokens: estimatedPromptTokens,
    );

    final response = await _memoSummaryProxy.call({
      'messages': messages,
      'temperature': 0.2,
    });

    final raw = response.data['content'].toString().trim();
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
    final estimatedTokens = AnalyticsService.estimateChatTokens(messages, raw);

    AnalyticsService.logApiUsage(
      coachId: 'system',
      estimatedTokens: estimatedTokens,
      actualTokens: actualTokens,
      actualCostWon: actualCostWon,
    );

    return raw.replaceAll('```', '').trim();
  }

  Future<void> _showSummaryPreviewSheet({
    required int sectionIndex,
    required String originalContent,
    required String summary,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '핵심 정리 미리보기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Icon(
                        Icons.close,
                        color: Color(0xFFA0A0B0),
                        size: 22,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                  ),
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F5FF),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE5E0FF)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      summary,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        height: 1.55,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _contentCtrls[sectionIndex].text =
                                _limitSectionContent(
                                  _buildContentWithSummary(
                                    summary: summary,
                                    originalContent: originalContent,
                                  ),
                                );
                          });
                          Navigator.pop(ctx);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: widget.coach.accentColor,
                          side: BorderSide(color: widget.coach.accentColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          '요약 추가',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _contentCtrls[sectionIndex].text =
                                _limitSectionContent(summary);
                          });
                          Navigator.pop(ctx);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: widget.coach.accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          '본문 대체',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildContentWithSummary({
    required String summary,
    required String originalContent,
  }) {
    return '[핵심 요약]\n$summary\n\n[원문]\n$originalContent';
  }

  String _limitSectionContent(String content) {
    if (content.length <= _sectionContentMaxLength) {
      return content;
    }
    return content.substring(0, _sectionContentMaxLength);
  }

  // --- 음성 인식 로직 ---
  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint("Speech error: $error");
          if (mounted) {
            setState(() => _isListening = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('음성 인식 오류: ${error.errorMsg}')),
            );
          }
        },
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint("Speech init error: $e");
    }
  }

  void _startListening() async {
    if (!_speechEnabled) {
      _initSpeech();
      return;
    }
    if (_focusedCtrl == null) {
      if (_contentFocusNodes.isNotEmpty) {
        _editingSectionIndexes.add(0);
        if (mounted) setState(() {});
        _contentFocusNodes.first.requestFocus();
        _focusedCtrl = _contentCtrls.first;
      } else {
        return;
      }
    }

    _baseText = _focusedCtrl!.text;
    _baseSelection = _focusedCtrl!.selection;
    await _speechToText.listen(
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      onResult: (result) {
        if (mounted && _focusedCtrl != null) {
          setState(() {
            final spoken = result.recognizedWords;
            int start = _baseSelection.start;
            int end = _baseSelection.end;
            if (start < 0) {
              start = _baseText.length;
              end = _baseText.length;
            }
            final insertText =
                (_baseText.isNotEmpty &&
                        start > 0 &&
                        _baseText[start - 1] != ' '
                    ? ' '
                    : '') +
                spoken;
            _focusedCtrl!.text = _baseText.replaceRange(start, end, insertText);
            _focusedCtrl!.selection = TextSelection.collapsed(
              offset: start + insertText.length,
            );
          });
        }
      },
      localeId: 'ko_KR',
      cancelOnError: false,
      partialResults: true,
    );
    setState(() => _isListening = true);
  }

  Future<void> _stopListening() async {
    await _speechToText.stop();
    if (mounted) setState(() => _isListening = false);
  }

  // --- 저장 로직 ---
  void _saveDataAndClose() {
    // 1. Sections
    for (int i = 0; i < _sections.length; i++) {
      _sections[i].title = _titleCtrls[i].text.trim();
      _sections[i].content = _contentCtrls[i].text.trim();
    }
    _sections.removeWhere((s) => s.title.isEmpty && s.content.isEmpty);
    widget.milestone.memoSections = _sections;

    if (_sections.isNotEmpty) {
      widget.milestone.memo = _sections.first.content;
    } else {
      widget.milestone.memo = '';
    }

    // 2. Actions
    for (int i = 0; i < _actions.length; i++) {
      _actions[i].title = _actionCtrls[i].text.trim();
    }
    _actions.removeWhere((a) => a.title.isEmpty);
    widget.milestone.actionCandidates = _actions;

    widget.onSave('saved');
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _speechToText.stop();
    for (var ctrl in _titleCtrls) ctrl.dispose();
    for (var ctrl in _contentCtrls) ctrl.dispose();
    for (var node in _titleFocusNodes) node.dispose();
    for (var node in _contentFocusNodes) node.dispose();

    for (var ctrl in _actionCtrls) ctrl.dispose();
    for (var node in _actionFocusNodes) node.dispose();

    super.dispose();
  }

  // --- 위젯 빌드 ---
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.milestone.text.isNotEmpty
                            ? widget.milestone.text
                            : '마일스톤 메모',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3D3A4E),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: Color(0xFF8B7CFF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.milestone.date ?? '기한 없음',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8B7CFF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _saveDataAndClose,
                  child: const Icon(
                    Icons.close,
                    color: Color(0xFFA0A0B0),
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Sections ---
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _sections.length,
                    onReorder: _onReorderSections,
                    itemBuilder: (context, index) {
                      return Container(
                        key: ObjectKey(_sections[index]),
                        child: _buildSectionCard(index),
                      );
                    },
                  ),

                  GestureDetector(
                    onTap: _addNewSection,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F5FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF8B7CFF).withOpacity(0.3),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add,
                            size: 16,
                            color: Color(0xFF8B7CFF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '섹션 추가',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF8B7CFF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_sections.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '✨ 섹션 순서를 변경하려면 길게 눌러 이동하세요',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFFA0A0B0),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    const SizedBox(height: 16),

                  const Divider(
                    color: Color(0xFFE5E7EB),
                    height: 32,
                    thickness: 1,
                  ),

                  // --- Action Items ---
                  Row(
                    children: [
                      const Text('⚡️', style: TextStyle(fontSize: 18)),
                      const SizedBox(width: 6),
                      Text(
                        '실행 아이템 (행동 후보)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  ...List.generate(
                    _actions.length,
                    (index) => _buildActionCard(index),
                  ),

                  GestureDetector(
                    onTap: _addNewAction,
                    child: Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 40),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.add,
                            size: 16,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '실행 아이템 추가',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(24),
                bottomRight: Radius.circular(24),
              ),
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_isListening) {
                      _stopListening();
                    } else {
                      _startListening();
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? Colors.red.withOpacity(0.1)
                          : const Color(0xFFF5F3FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      size: 20,
                      color: _isListening
                          ? Colors.red
                          : const Color(0xFF8B7CFF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isListening ? '말씀하세요. 듣고 있습니다...' : '음성으로 내용을 입력해보세요!',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      color: _isListening
                          ? Colors.red
                          : const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: _saveDataAndClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: widget.coach.accentColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '저장',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
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

  Widget _buildSectionCard(int index) {
    final isSummarizing = _summarizingSectionIndex == index;
    final isEditingContent =
        _editingSectionIndexes.contains(index) ||
        _contentCtrls[index].text.trim().isEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F5FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleCtrls[index],
                  focusNode: _titleFocusNodes[index],
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3D3A4E),
                  ),
                  decoration: InputDecoration(
                    hintText: '섹션 제목 (예: 성장 고민)',
                    hintStyle: GoogleFonts.notoSansKr(
                      color: const Color(0xFFA0A0B0),
                      fontWeight: FontWeight.w500,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (!isEditingContent)
                GestureDetector(
                  onTap: () => _startEditingSection(index),
                  child: const Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Color(0xFF8B7CFF),
                  ),
                ),
              if (!isEditingContent) const SizedBox(width: 8),
              GestureDetector(
                onTap: isSummarizing ? null : () => _summarizeSection(index),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.68),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFFE5E0FF)),
                  ),
                  alignment: Alignment.center,
                  child: isSummarizing
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              widget.coach.accentColor,
                            ),
                          ),
                        )
                      : Text(
                          '✨ 정리',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: widget.coach.accentColor,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _removeSection(index),
                child: const Icon(
                  Icons.close,
                  size: 16,
                  color: Color(0xFFA0A0B0),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFE5E7EB), height: 20),
          if (isEditingContent)
            TextField(
              controller: _contentCtrls[index],
              focusNode: _contentFocusNodes[index],
              maxLines: null,
              maxLength: _sectionContentMaxLength,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              keyboardType: TextInputType.multiline,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                color: const Color(0xFF3D3A4E),
                height: 1.5,
              ),
              decoration: InputDecoration(
                hintText: '실행에 필요한 핵심 위주로 글이나 링크를 적어두세요(최대 1000자)',
                hintStyle: GoogleFonts.notoSansKr(
                  color: const Color(0xFFA0A0B0),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                counterText: '',
              ),
            )
          else
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _startEditingSection(index),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: MemoDisplayWidget(
                  text: _contentCtrls[index].text,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: const Color(0xFF3D3A4E),
                    height: 1.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showConversionBottomSheet(
    BuildContext context,
    ActionCandidate action,
    int index,
  ) {
    if (widget.onConvertAction == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '어떤 일정으로 전환할까요?',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF3D3A4E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '"${action.title}"',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    color: const Color(0xFF8B7CFF),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),

                _buildConversionOption(
                  icon: Icons.today,
                  title: '오늘 할 일로 추가',
                  subtitle: '오늘 일정에 즉시 추가됩니다.',
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onConvertAction!(action, 'task_today');
                    setState(() {});
                  },
                ),
                _buildConversionOption(
                  icon: Icons.calendar_month,
                  title: '특정 날짜 일정으로 추가',
                  subtitle: '원하는 날짜를 선택하여 추가합니다.',
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onConvertAction!(action, 'task_date');
                    // Date picker will trigger a rebuild in the callback if needed
                    // But we might want to manually refresh Dialog if callback does not
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) setState(() {});
                    });
                  },
                ),
                _buildConversionOption(
                  icon: Icons.repeat,
                  title: '습관 트래커로 추가',
                  subtitle: '매일 실천하는 습관 목록에 추가합니다.',
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.onConvertAction!(action, 'habit');
                    setState(() {});
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversionOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F5FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF8B7CFF), size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFD1D5DB)),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showDeleteConfirmation() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFFEF2F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Color(0xFFEF4444),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '이 실행 아이템을 삭제할까요?',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '삭제된 내용은 되돌릴 수 없어요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: const Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: Color(0xFFD1D5DB)),
                      ),
                    ),
                    child: Text(
                      '취소',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF4B5563),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '삭제',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(int index) {
    final action = _actions[index];
    final isConverted =
        action.convertedTaskId != null || action.convertedHabitId != null;

    IconData stateIcon;
    Color iconColor;
    Widget stateBadge;

    if (isConverted) {
      if (action.convertedType == 'habit') {
        stateIcon = Icons.autorenew;
        iconColor = const Color(0xFF3B82F6);
        stateBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '습관으로 전환됨',
            style: GoogleFonts.notoSansKr(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF3B82F6),
            ),
          ),
        );
      } else {
        stateIcon = Icons.check_circle;
        iconColor = const Color(0xFF10B981);
        stateBadge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2FF),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            action.convertedType == 'task_today' ? '할 일로 전환됨' : '일정으로 전환됨',
            style: GoogleFonts.notoSansKr(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6366F1),
            ),
          ),
        );
      }
    } else {
      stateIcon = Icons.radio_button_unchecked;
      iconColor = const Color(0xFFD1D5DB);
      stateBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '대기 중',
          style: GoogleFonts.notoSansKr(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B7280),
          ),
        ),
      );
    }

    return Dismissible(
      key: ObjectKey(action),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await _showDeleteConfirmation();
      },
      onDismissed: (direction) {
        _removeAction(index);
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(stateIcon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _actionCtrls[index],
                    focusNode: _actionFocusNodes[index],
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: const Color(0xFF3D3A4E),
                    ),
                    decoration: InputDecoration(
                      hintText: '구체적인 행동 입력 (예: 개발 컨퍼런스 등록하기)',
                      hintStyle: GoogleFonts.notoSansKr(
                        color: const Color(0xFFA0A0B0),
                        fontSize: 13,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (val) {
                      action.title = val;
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      stateBadge,
                      if (isConverted && action.convertedDate != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          action.convertedDate!,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 10,
                            color: const Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (!isConverted) ...[
              GestureDetector(
                onTap: () {
                  if (action.title.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('실행 아이템 내용을 먼저 입력해주세요!')),
                    );
                    return;
                  }
                  _showConversionBottomSheet(context, action, index);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Text(
                    '전환',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFD97706),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert,
                color: Color(0xFFA0A0B0),
                size: 20,
              ),
              padding: EdgeInsets.zero,
              onSelected: (val) async {
                if (val == 'edit') {
                  _actionFocusNodes[index].requestFocus();
                } else if (val == 'delete') {
                  final confirm = await _showDeleteConfirmation();
                  if (confirm == true) {
                    _removeAction(index);
                  }
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'edit', child: Text('수정하기')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('삭제하기', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class MilestoneMemoDisplayWidget extends StatelessWidget {
  final MilestoneItem milestone;
  final TextStyle style;
  final int? maxLines;

  const MilestoneMemoDisplayWidget({
    super.key,
    required this.milestone,
    required this.style,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final sections = milestone.memoSections ?? [];
    final actions = milestone.actionCandidates ?? [];

    if (maxLines != null) {
      final previewText = _buildPreviewText(sections, actions);
      if (previewText.isNotEmpty) {
        return MemoDisplayWidget(
          text: previewText,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
      }
    }

    if (sections.isEmpty && actions.isEmpty) {
      if (milestone.memo != null && milestone.memo!.isNotEmpty) {
        return MemoDisplayWidget(
          text: milestone.memo!,
          style: style,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (sections.isNotEmpty)
          ...sections.map((section) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (section.title.isNotEmpty)
                    Text(
                      '[${section.title}]',
                      style: style.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  if (section.content.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        top: section.title.isNotEmpty ? 4.0 : 0,
                      ),
                      child: MemoDisplayWidget(
                        text: section.content,
                        style: style,
                      ),
                    ),
                ],
              ),
            );
          }),
        if (actions.isNotEmpty) ...[
          if (sections.isNotEmpty) const SizedBox(height: 4),
          Text(
            '⚡️ 실행 아이템',
            style: style.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFFD97706),
            ),
          ),
          const SizedBox(height: 4),
          ...actions.map((action) {
            final isConverted =
                action.convertedTaskId != null ||
                action.convertedHabitId != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Icon(
                      isConverted
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 14,
                      color: isConverted
                          ? const Color(0xFF10B981)
                          : const Color(0xFFD1D5DB),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      action.title,
                      style: style.copyWith(
                        color: isConverted
                            ? const Color(0xFF9CA3AF)
                            : style.color,
                        decoration: isConverted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  String _buildPreviewText(
    List<MemoSection> sections,
    List<ActionCandidate> actions,
  ) {
    final parts = <String>[];

    if (sections.isEmpty && actions.isEmpty) {
      final memo = milestone.memo?.trim();
      if (memo != null && memo.isNotEmpty) {
        parts.add(memo);
      }
    }

    for (final section in sections) {
      final sectionParts = <String>[];
      final title = section.title.trim();
      final content = section.content.trim();

      if (title.isNotEmpty) {
        sectionParts.add('[$title]');
      }
      if (content.isNotEmpty) {
        sectionParts.add(content);
      }
      if (sectionParts.isNotEmpty) {
        parts.add(sectionParts.join(' '));
      }
    }

    if (actions.isNotEmpty) {
      parts.add(
        '실행 아이템 ${actions.map((action) => action.title.trim()).where((title) => title.isNotEmpty).join(', ')}',
      );
    }

    return parts.join('  ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class MemoDisplayWidget extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;

  const MemoDisplayWidget({
    super.key,
    required this.text,
    required this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final RegExp urlRegex = RegExp(
      r'(https?:\/\/[^\s]+)',
      caseSensitive: false,
    );
    final Iterable<RegExpMatch> matches = urlRegex.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: style, maxLines: maxLines, overflow: overflow);
    }

    final List<TextSpan> spans = [];
    int currentPosition = 0;

    for (final match in matches) {
      if (match.start > currentPosition) {
        spans.add(
          TextSpan(
            text: text.substring(currentPosition, match.start),
            style: style,
          ),
        );
      }
      final String url = match.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: style.copyWith(
            color: const Color(0xFF3B82F6),
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              try {
                final uri = WebUri(url);
                await InAppBrowser.openWithSystemBrowser(url: uri);
              } catch (e) {
                debugPrint('Error launching url: $e');
              }
            },
        ),
      );
      currentPosition = match.end;
    }

    if (currentPosition < text.length) {
      spans.add(TextSpan(text: text.substring(currentPosition), style: style));
    }

    return Text.rich(
      TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
}
