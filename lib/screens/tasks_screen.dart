import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'coach_config.dart';
import '../services/memory_service.dart';
import '../models/user_data.dart';
import '../services/notification_service.dart';
import '../services/tasks_sync_service.dart';
import '../services/user_title_service.dart';

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
    this.completedAt,
    this.isReminderEnabled = true,
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
    if (completedAt != null) 'completedAt': completedAt,
    'isReminderEnabled': isReminderEnabled,
    if (achievedCount != null) 'achievedCount': achievedCount,
    if (achievedDuration != null) 'achievedDuration': achievedDuration,
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
    completedAt: j['completedAt'],
    isReminderEnabled: j['isReminderEnabled'] ?? true,
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
    'isReminderEnabled': isReminderEnabled,
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

class MilestoneItem {
  String text;
  bool done;
  String? date;

  MilestoneItem({required this.text, this.done = false, this.date});

  Map<String, dynamic> toJson() => {'text': text, 'done': done, 'date': date};
  factory MilestoneItem.fromJson(Map<String, dynamic> j) =>
      MilestoneItem(text: j['text'], done: j['done'] ?? false, date: j['date']);
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
  const TasksScreen({
    super.key,
    required this.coachId,
    this.onCoreTaskSet,
    this.controller,
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
  Map<String, Map<String, dynamic>> habitLogs = {};
  Map<String, List<ScheduleItem>> schedules = {};
  Map<String, dynamic>? vacationInfo;
  double _resetHour = 3.0;

  DateTime _calFocusedDay = DateTime.now();
  DateTime _calSelectedDay = DateTime.now();
  final _schInputCtrl = TextEditingController();

  String _schTimeType = 'none'; // 'none', 'single', 'range', 'duration'
  TimeOfDay? _schStartTime;
  TimeOfDay? _schEndTime;
  String? _schDuration;
  bool _schReminderEnabled = false;

  String _todayTimeType = 'none'; // 'none', 'single', 'range', 'duration'
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
        await prefs.remove('nyang_chat_history_$id');
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
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
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
    final record = {
      'date': todayStr,
      'totalCount': tasks.length,
      'doneCount': doneTasks.length,
      'success': doneTasks.isNotEmpty,
      'isVacation': vacationInfo != null,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': tasks
          .map((t) => {'text': t.text, 'done': t.done, 'category': t.category})
          .toList(),
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
        existingTask.time = s.time;
        existingTask.timeStart = s.timeStart;
        existingTask.timeEnd = s.timeEnd;
        existingTask.duration = s.duration;
        existingTask.done = s.done;

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
            coreTasks[coreIndex].time = s.time;
            coreTasks[coreIndex].timeStart = s.timeStart;
            coreTasks[coreIndex].timeEnd = s.timeEnd;
            coreTasks[coreIndex].duration = s.duration;
            coreTasks[coreIndex].done = s.done;
            coreTasksChanged = true;
          }
        }
      } else {
        final newTask = TaskItem(
          id: taskId,
          text: s.text,
          category: 'schedule',
          done: s.done,
          time: s.time,
          duration: s.duration,
          timeStart: s.timeStart,
          timeEnd: s.timeEnd,
          createdAt: s.createdAt,
          isReminderEnabled: s.isReminderEnabled,
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

  // ── addTask (웹앱 그대로) ─────────────────────────────────
  void _addTodayTask(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    String? timeStr;
    String? timeEndStr;
    String? durStr;
    String? timeStartStr;

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

    final task = TaskItem(
      id:
          DateTime.now().millisecondsSinceEpoch +
          DateTime.now().microsecond % 1000,
      text: trimmed,
      category: 'today',
      time: timeStr,
      timeStart: timeStartStr,
      timeEnd: timeEndStr,
      duration: durStr,
      done: false,
      createdAt: DateTime.now().toIso8601String(),
    );
    setState(() {
      tasks.add(task);
      _todayTimeType = 'none';
      _todayStartTime = null;
      _todayEndTime = null;
      _todayDuration = null;
    });
    _saveTasks();
    _todayInputCtrl.clear();
  }

  // ── toggleTask (웹앱 그대로) ──────────────────────────────
  Future<void> _toggleTask(dynamic id) async {
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
      });
      _saveTasks();
      _saveHabitLogs();
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
      });
      _saveTasks();
      _saveHabitLogs();
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
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF3D3A4E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
            margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
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

  void _removeTaskForMove(TaskItem task) {
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
        task.category == 'schedule' && task.isReminderEnabled;

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
                    if (_isCoreReminderEnabledGlobally &&
                        (moveTimeType == 'single' || moveTimeType == 'range') &&
                        moveStartTime != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: GestureDetector(
                          onTap: () => setModalState(
                            () => moveReminderEnabled = !moveReminderEnabled,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                moveReminderEnabled
                                    ? Icons.notifications_active
                                    : Icons.notifications_none_outlined,
                                size: 18,
                                color: moveReminderEnabled
                                    ? _coach.accentColor
                                    : const Color(0xFFB0B0C8),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                moveReminderEnabled
                                    ? '알림 켜짐 (핵심에 자동 추가)'
                                    : '알림 끄기',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  color: moveReminderEnabled
                                      ? _coach.accentColor
                                      : const Color(0xFFB0B0C8),
                                  fontWeight: moveReminderEnabled
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
  int get _doneTasks => tasks.where((t) => t.done).length;
  int get _totalTasks => tasks.length;
  double get _progressPct => _totalTasks > 0 ? _doneTasks / _totalTasks : 0.0;

  @override
  Widget build(BuildContext context) {
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
            onTap: () {
              if (!_isCoreReminderEnabledGlobally || c.time == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isCoreReminderEnabledGlobally
                          ? '시간이 지정된 일정만 리마인더를 받을 수 있습니다.'
                          : '설정에서 코치의 핵심 리마인더를 켜주세요.',
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
                                      onTap: () {
                                        if (!_isCoreReminderEnabledGlobally ||
                                            t.time == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                _isCoreReminderEnabledGlobally
                                                    ? '시간이 지정된 일정만 리마인더를 받을 수 있습니다.'
                                                    : '설정에서 코치의 핵심 리마인더를 켜주세요.',
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

                      // 비서 코치 전용: 핵심 설정 완료 반응 메시지
                      if (widget.onCoreTaskSet != null &&
                          pendingCore.isNotEmpty) {
                        final addedTexts = pendingCore
                            .map((pid) {
                              final t = tasks.firstWhere(
                                (t) => t.id.toString() == pid,
                                orElse: () => TaskItem(
                                  id: 0,
                                  text: pid,
                                  category: 'direct',
                                  createdAt: DateTime.now().toIso8601String(),
                                ),
                              );
                              return t.text;
                            })
                            .join(', ');

                        final String rawConfirmMsg;
                        if (widget.coachId == 'sec_male') {
                          rawConfirmMsg =
                              '알겠습니다, 대표님. 오늘 집중하실 핵심 과제는 "$addedTexts"입니다. 차질 없이 성공적으로 완수하실 수 있도록 돕겠습니다.';
                        } else if (widget.coachId == 'sec_female') {
                          rawConfirmMsg =
                              '네, 대표님! 오늘 정해주신 소중한 핵심 목표는 "$addedTexts"이네요. 지치지 않고 차근차근 이루어내실 수 있도록 곁에서 정성껏 서포트할게요.';
                        } else {
                          rawConfirmMsg = '';
                        }

                        if (rawConfirmMsg.isNotEmpty) {
                          final confirmMsg =
                              await UserTitleService.applyForCoach(
                                rawConfirmMsg,
                                widget.coachId,
                              );
                          widget.onCoreTaskSet!(confirmMsg);
                        }
                      }
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
    if (tasks.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      itemCount: tasks.length,
      itemBuilder: (ctx, i) => _buildTaskItem(tasks[i]),
    );
  }

  void _showEditItemModal(dynamic item, VoidCallback onSave) {
    final textCtrl = TextEditingController(text: item.text);

    String mTimeType = 'none';
    TimeOfDay? mStartTime;
    TimeOfDay? mEndTime;
    String? mDuration;
    bool mReminderEnabled = (item is ScheduleItem)
        ? item.isReminderEnabled
        : false;
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
                              if (t != null)
                                setModalState(() => mStartTime = t);
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
                        item.isReminderEnabled = mReminderEnabled;
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
                  color: t.done ? _coach.accentColor : Colors.transparent,
                  border: Border.all(
                    color: t.done
                        ? _coach.accentColor
                        : const Color(0xFFD1D5DB),
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: t.done
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
            ),
          ),
          // 텍스트
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (t.done) return;
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
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
              ),
            ),
          ),
          // 시간/소요시간 표시
          GestureDetector(
            onTap: () {
              if (t.done) return;
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
            child: (t.time != null || t.duration != null)
                ? Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: t.time != null
                          ? const Color(0xFFF5F3FF)
                          : const Color(0xFFFDF2F8),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      t.time != null ? t.time! : '⏱ ${t.duration}',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: t.time != null
                            ? const Color(0xFF8B7CFF)
                            : const Color(0xFFDB2777),
                      ),
                    ),
                  )
                : Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(
                      Icons.access_time,
                      size: 16,
                      color: Color(0xFFD1D5DB),
                    ),
                  ),
          ),
          // 습관 뱃지
          if (t.isHabit)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          // 삭제 버튼
          GestureDetector(
            onTap: () => _showTaskDeleteOptions(t),
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
                              if (t != null)
                                setState(() => _todayStartTime = t);
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
                onTap: () => _showVisionModal(),
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
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visions.length,
            itemBuilder: (ctx, i) {
              final v = visions[i];
              return GestureDetector(
                onTap: () => _showVisionModal(v),
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
                                fontSize: 18,
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
                      const Icon(Icons.more_vert, color: Color(0xFFA0A0B0)),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
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
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE8E3F8),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      ReorderableDragStartListener(
                                        index: i,
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: m.done
                                                ? const Color(0xFF8B7CFF)
                                                : const Color(0xFFF5F3FF),
                                            borderRadius: BorderRadius.circular(
                                              8,
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
                                            TextField(
                                              controller:
                                                  TextEditingController(
                                                      text: m.text,
                                                    )
                                                    ..selection =
                                                        TextSelection.collapsed(
                                                          offset: m.text.length,
                                                        ),
                                              onChanged: (val) => m.text = val,
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: m.done
                                                    ? const Color(0xFFA0A0B0)
                                                    : const Color(0xFF3D3A4E),
                                                decoration: m.done
                                                    ? TextDecoration.lineThrough
                                                    : null,
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
                                                contentPadding: EdgeInsets.zero,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
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
                                                                  Colors.white,
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
                                                      BorderRadius.circular(12),
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
                                                      color: Color(0xFF8B7CFF),
                                                      size: 14,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      m.date != null &&
                                                              m.date!.isNotEmpty
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
                                            ),
                                            const SizedBox(height: 8),
                                            // 완료 토글 버튼
                                            GestureDetector(
                                              onTap: () {
                                                setModalState(() {
                                                  m.done = !m.done;
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
                                                      ? const Color(0xFFF5F0FF)
                                                      : const Color(0xFFF9FAFB),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: m.done
                                                        ? const Color(
                                                            0xFF8B5CF6,
                                                          )
                                                        : const Color(
                                                            0xFFE5E7EB,
                                                          ),
                                                    width: 1.5,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      m.done
                                                          ? '✅ 완료됨'
                                                          : '○ 완료 표시',
                                                      style:
                                                          GoogleFonts.notoSansKr(
                                                            fontSize: 13,
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            color: m.done
                                                                ? const Color(
                                                                    0xFF7C3AED,
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
                                      GestureDetector(
                                        onTap: () {
                                          setModalState(() {
                                            milestones.removeAt(i);
                                          });
                                        },
                                        child: const Icon(
                                          Icons.close,
                                          color: Color(0xFFD1D5DB),
                                          size: 18,
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
                                onTap: () {
                                  setState(() {
                                    visions.removeWhere(
                                      (v) => v.id == vision.id,
                                    );
                                  });
                                  _saveVisions();
                                  Navigator.pop(ctx);
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
      isReminderEnabled: reminderEnabled,
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

  void _addSchedule() {
    final text = _schInputCtrl.text.trim();
    if (text.isEmpty) return;

    final dateStr = _dateKey(_calSelectedDay);
    final entry = ScheduleItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      createdAt: DateTime.now().toIso8601String(),
      isReminderEnabled: _schReminderEnabled,
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

    setState(() {
      if (!schedules.containsKey(dateStr)) schedules[dateStr] = [];
      schedules[dateStr]!.add(entry);
    });
    _schInputCtrl.clear();
    setState(() => _schReminderEnabled = false);
    _saveSchedules();
  }

  Widget _buildScheduleTab() {
    final isVacation = vacationInfo != null;
    return Container(
      color: isVacation ? Colors.transparent : Colors.white,
      child: SingleChildScrollView(
        child: Column(
          children: [
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
            _buildScheduleList(),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleList() {
    final dateStr = _dateKey(_calSelectedDay);
    final daySch = schedules[dateStr] ?? [];

    return Column(
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
        if (daySch.isEmpty)
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
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: daySch.length,
            itemBuilder: (ctx, i) {
              final s = daySch[i];
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
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _showEditItemModal(s, () {
                                setState(() {});
                                _saveSchedules();
                              });
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
                        _showEditItemModal(s, () {
                          setState(() {});
                          _saveSchedules();
                        });
                      },
                      child: (s.time != null || s.duration != null)
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
        // 시간 설정 UI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  final isActive = _schTimeType == t;
                  final isLast = t == 'duration';
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() {
                        _schTimeType = _schTimeType == t ? 'none' : t;
                        if (t != 'duration') _schDuration = null;
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
                          if (t != null) setState(() => _schStartTime = t);
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
                              border: Border.all(
                                color: const Color(0xFFE5E7EB),
                              ),
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
            ],
          ),
        ),
        // 알림 토글 + 입력부
        if (_isCoreReminderEnabledGlobally &&
            (_schTimeType == 'single' || _schTimeType == 'range') &&
            _schStartTime != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: GestureDetector(
              onTap: () =>
                  setState(() => _schReminderEnabled = !_schReminderEnabled),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _schReminderEnabled
                          ? _coach.accentColor.withOpacity(0.12)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _schReminderEnabled
                          ? Icons.notifications_active
                          : Icons.notifications_none_outlined,
                      size: 18,
                      color: _schReminderEnabled
                          ? _coach.accentColor
                          : const Color(0xFFB0B0C8),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _schReminderEnabled ? '알림 켜짐 (핵심에 자동 추가)' : '알림 끄기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      color: _schReminderEnabled
                          ? _coach.accentColor
                          : const Color(0xFFB0B0C8),
                      fontWeight: _schReminderEnabled
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Container(
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onSubmitted: (v) => _addSchedule(),
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

  void _deleteHabit(dynamic id) {
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
