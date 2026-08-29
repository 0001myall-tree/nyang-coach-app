import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'coach_config.dart';
import '../services/memory_service.dart';
import '../services/task_resistance_service.dart';
import '../models/user_data.dart';
import '../services/notification_service.dart';
import '../services/plan_feedback_service.dart';
import '../services/tasks_sync_service.dart';
import '../services/analytics_service.dart';
import '../services/api_usage_limit_service.dart';
import '../services/widget_sync_service.dart';
import '../services/daily_reset_service.dart';
import '../services/free_access_service.dart';
import '../services/purchase_service.dart';
import '../services/nyang_banner_nudge.dart';
import '../services/distraction_coach_quota.dart';
import '../services/ongoing_task_nudge_service.dart';
import '../services/task_completion_service.dart';
import '../services/apple_calendar_sync_service.dart';
import '../services/routine_schedule.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/alarm_permission_notice.dart';
import '../widgets/core_reminder_settings_sheet.dart';

// ─────────────────────────────────────────────────────────────
// 데이터 모델 (웹앱 그대로)
// ─────────────────────────────────────────────────────────────
class TaskItem {
  final dynamic id; // int or String (habit_xxx)
  String text;
  String category; // 'today' | 'habit'
  bool done;
  bool inProgress;
  String? inProgressAt;
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
  String? source;
  String? memo;

  /// 일시정지까지 쌓인 실행 시간. 멈춘 동안에도 이 값은 그대로 남는다.
  int elapsedSeconds;

  /// 지금 돌고 있는 구간이 시작된 시각. 진행 중일 때만 값이 있다.
  ///
  /// [inProgressAt]과 나눠 둔다. 그쪽은 이 할 일을 맨 처음 시작한 시각이고
  /// 저녁에 "시작해두고 멈춘 것 같은데"를 물을 때 쓰인다. 일시정지·재시작을
  /// 할 때마다 덮어쓰면 그 질문이 방금 누른 시각을 보게 된다.
  String? runStartedAt;

  /// 완료 시점에 굳힌 최종 실행 시간. 완료 뒤에는 이 값만 보여준다.
  int? actualSeconds;

  /// 마지막으로 일시정지한 시각. 재시작하거나 완료하면 지운다.
  ///
  /// "멈춘 지 3시간 지난 일정" 냥냥이 카드가 이 값 하나로 판단한다. 시작 시각과
  /// 달리 멈출 때마다 새로 적어야, 두 번째로 멈췄을 때 첫 번째 멈춘 시각을 보고
  /// 이미 지난 일로 착각하지 않는다.
  String? pausedAt;

  TaskItem({
    required this.id,
    required this.text,
    required this.category,
    this.done = false,
    this.inProgress = false,
    this.inProgressAt,
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
    this.source,
    this.memo,
    this.elapsedSeconds = 0,
    this.runStartedAt,
    this.actualSeconds,
    this.pausedAt,
  });

  /// 이 할 일이 시작·일시정지·밀어서 완료 흐름을 타는지.
  ///
  /// 처음에는 소요시간을 정한 할 일에만 붙였다가 전부로 넓혔다. 카드마다
  /// 완료하는 법이 다르면 손이 기억할 동작이 둘이 되는데, 사용자는 그 차이를
  /// 알아보려고 시간 표시를 확인하지 않는다.
  ///
  /// 목표의 이정표만 뺀다. 그건 오늘 하는 일이 아니라 달성 여부라서 잴 것이 없다.
  bool get hasTimer => !id.toString().startsWith('milestone_');

  /// 지금 화면에 보여줄 실행 시간. 진행 중이면 흐르는 구간까지 더한다.
  int elapsedSecondsAt(DateTime now) {
    if (actualSeconds != null) return actualSeconds!;
    if (!inProgress || runStartedAt == null) return elapsedSeconds;
    final started = DateTime.tryParse(runStartedAt!);
    if (started == null) return elapsedSeconds;
    final running = now.difference(started).inSeconds;
    return elapsedSeconds + (running > 0 ? running : 0);
  }

  /// 시작한 적은 있으나 지금은 멈춰 있는 상태.
  bool get isPaused => !done && !inProgress && elapsedSeconds > 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'category': category,
    'done': done,
    if (inProgress) 'inProgress': inProgress,
    // 습관이 아니어도 시작 시각을 남긴다. 저녁에 "시작해두고 멈춘 것 같은데"를
    // 물으려면 언제 눌렀는지가 필요한데, 예전엔 여기서 버려져서 물을 수가 없었다.
    if (inProgressAt != null) 'inProgressAt': inProgressAt,
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
    if (source != null) 'source': source,
    if (memo != null && memo!.isNotEmpty) 'memo': memo,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    if (runStartedAt != null) 'runStartedAt': runStartedAt,
    if (actualSeconds != null) 'actualSeconds': actualSeconds,
    if (pausedAt != null) 'pausedAt': pausedAt,
  };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'],
    text: j['text'],
    category: j['category'] ?? 'today',
    done: j['done'] ?? false,
    inProgress: j['inProgress'] ?? false,
    inProgressAt: j['inProgressAt'],
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
    source: j['source']?.toString(),
    memo: j['memo']?.toString(),
    elapsedSeconds: (j['elapsedSeconds'] as num?)?.toInt() ?? 0,
    runStartedAt: j['runStartedAt']?.toString(),
    actualSeconds: (j['actualSeconds'] as num?)?.toInt(),
    pausedAt: j['pausedAt']?.toString(),
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
  String freq; // 'daily' | 'weekly' | 'weekly_count'
  List<int> days; // 0=월~6=일
  int? weeklyTargetCount;
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
    this.weeklyTargetCount,
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
    if (weeklyTargetCount != null) 'weeklyTargetCount': weeklyTargetCount,
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
    weeklyTargetCount: j['weeklyTargetCount'] is num
        ? (j['weeklyTargetCount'] as num).toInt()
        : int.tryParse('${j['weeklyTargetCount']}'),
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
  String? memo;

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
    this.memo,
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
    if (memo != null && memo!.isNotEmpty) 'memo': memo,
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
    memo: j['memo']?.toString(),
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
  factory VisionDeadline.fromJson(Map<String, dynamic>? j) {
    final now = DateTime.now();
    return VisionDeadline(
      year: (j?['year'] ?? now.year + 1).toString(),
      month: (j?['month'] ?? 1).toString(),
      period: (j?['period'] ?? '말').toString(),
    );
  }
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
    name: (j['name'] ?? j['text'] ?? '').toString(),
    desc: j['desc']?.toString(),
    coachId: j['coachId'] ?? 'self',
    deadline: VisionDeadline.fromJson(
      j['deadline'] is Map ? Map<String, dynamic>.from(j['deadline']) : null,
    ),
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
/// 진행 중인 카드의 가장자리.
///
/// 색만 바꿔 두면 목록을 훑을 때 어느 게 도는지 안 보인다. 그렇다고 진하게
/// 칠하면 카드가 시끄러워져서, 테두리 바로 바깥에만 아주 옅게 번지는 빛을
/// 두고 그것만 느리게 오르내리게 한다. 색이 아니라 움직임이 신호가 된다.
///
/// 처음 켜질 때는 빛이 가장자리를 한 바퀴 돈다. 시작을 눌렀을 때 일어나는 일이
/// 색 바뀜 하나뿐이라 누른 맛이 없었다 — 이 앱이 제일 원하는 동작인데도.
class _ActiveCardEdge extends StatefulWidget {
  const _ActiveCardEdge({required this.accent, required this.radius});

  final Color accent;
  final double radius;

  @override
  State<_ActiveCardEdge> createState() => _ActiveCardEdgeState();
}

class _ActiveCardEdgeState extends State<_ActiveCardEdge>
    with TickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _sweep.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_sweep, _pulse]),
      builder: (context, _) => CustomPaint(
        painter: _ActiveCardEdgePainter(
          accent: widget.accent,
          radius: widget.radius,
          pulse: Curves.easeInOut.transform(_pulse.value),
          // 한 바퀴 돌고 나면 다시 그리지 않는다.
          sweep: _sweep.isCompleted ? null : _sweep.value,
        ),
      ),
    );
  }
}

class _ActiveCardEdgePainter extends CustomPainter {
  const _ActiveCardEdgePainter({
    required this.accent,
    required this.radius,
    required this.pulse,
    required this.sweep,
  });

  final Color accent;
  final double radius;

  /// 0~1. 옅은 빛이 오르내리는 정도.
  final double pulse;

  /// 0~1. 한 바퀴 도는 빛의 위치. 다 돌았으면 null.
  final double? sweep;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(0.5),
      Radius.circular(radius),
    );

    // BlurStyle.outer라 선 바깥쪽으로만 번진다. 카드 안쪽은 그대로 깨끗하다.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: 0.10 + 0.12 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.outer, 3 + 2.5 * pulse),
    );

    final at = sweep;
    if (at == null) return;
    // 밝은 구간 하나를 가진 원형 그라데이션을 돌린다. 나머지는 투명해서
    // 짧은 빛줄기가 가장자리를 따라 흐르는 것처럼 보인다.
    final head = Curves.easeInOut.transform(at);
    // 끝에서 빛이 툭 끊기지 않게 마지막 구간에서 잦아들게 한다.
    final fade = at < 0.75 ? 1.0 : 1 - (at - 0.75) / 0.25;
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..shader = SweepGradient(
          transform: GradientRotation(2 * pi * head - pi / 2),
          colors: [
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0),
            accent.withValues(alpha: 0.75 * fade),
            accent.withValues(alpha: 0),
          ],
          stops: const [0, 0.7, 0.86, 1],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(_ActiveCardEdgePainter old) =>
      old.pulse != pulse || old.sweep != sweep || old.accent != accent;
}

class TasksScreen extends StatefulWidget {
  final String coachId;
  final void Function(String message)? onCoreTaskSet;
  final VoidCallback? onProgressChanged;
  final TasksScreenController? controller;
  final String? initialBottomSheet;
  final int initialTabIndex;
  final String? initialPlannerDateKey;
  final String? initialPlannerItemId;
  const TasksScreen({
    super.key,
    required this.coachId,
    this.onCoreTaskSet,
    this.onProgressChanged,
    this.controller,
    this.initialBottomSheet,
    this.initialTabIndex = 0,
    this.initialPlannerDateKey,
    this.initialPlannerItemId,
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

  void openGoalVision({List<String> highlightVisionIds = const []}) {
    _state?._openGoalVision(highlightVisionIds: highlightVisionIds);
  }

  void openTab(int index) {
    _state?._openTab(index);
  }

  Future<bool> addGoalFromChat(String type, String text) async {
    return await _state?._addGoalFromChat(type, text) ?? false;
  }

  Future<bool> addHabitFromChat(
    String name, {
    String freq = 'daily',
    List<int> days = const [],
    int? weeklyTargetCount,
    int? countGoal,
    String? unit,
    TimeOfDay? time,
    TimeOfDay? endTime,
    String? habitDuration,
  }) async {
    return await _state?._addHabitFromChat(
          name,
          freq: freq,
          days: days,
          weeklyTargetCount: weeklyTargetCount,
          countGoal: countGoal,
          unit: unit,
          time: time,
          endTime: endTime,
          habitDuration: habitDuration,
        ) ??
        false;
  }

  Future<String> handleDeleteCommand(Map<String, dynamic> command) async {
    return await _state?._handleDeleteCommandFromChat(command) ??
        '삭제할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
  }

  /// 채팅에서 짚어준 할 일을 찾아 그 칸을 번쩍인다.
  Future<String> handleEditCommand(Map<String, dynamic> command) async {
    return await _state?._handleEditCommandFromChat(command) ??
        '수정할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
  }

  void resetTodayDateSelection() {
    _state?._resetTodayDateSelection();
  }

  void refresh() {
    _state?._loadAll();
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const int _maxMilestonesPerVision = 10;

  late TabController _tabCtrl;
  late CoachConfig _coach;

  Color get _accentButtonTextColor =>
      _coach.id == 'nyang_halbae' ? const Color(0xFF173A63) : Colors.white;

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
  Map<String, List<TaskItem>> plannedTodayTasksByDate = {};
  DateTime? _selectedTodayDate;

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
  bool _showTodayTimeOptions = false;
  bool _todayReminderEnabled = false;
  TimeOfDay? _todayStartTime;
  TimeOfDay? _todayEndTime;
  String? _todayDuration;
  static const _taskCheckboxHintSeenKey = 'nyang_hint_seen_task_checkbox';
  static const _taskStatusGuideNeverShowKey =
      'nyang_task_status_guide_never_show';
  static const _lightenPlanCardDismissedDateKey =
      'nyang_lighten_plan_card_dismissed_date';

  /// 할 일이 세 개가 됐을 때 핵심을 골라보자고 얹어두는 카드.
  static const _corePickCardDismissedDateKey =
      'nyang_core_pick_card_dismissed_date';
  bool _taskCheckboxHintSeen = false;
  bool _taskStatusGuideNeverShow = false;
  bool _taskStatusGuideDismissed = false;
  String? _lightenPlanCardDismissedDate;
  String? _corePickCardDismissedDate;
  bool _corePickCardBounced = false;
  late final AnimationController _corePickBounceCtrl;
  bool _taskCheckboxHintPulseStarted = false;
  late final AnimationController _taskCheckboxHintPulseCtrl;

  // 오늘 탭 입력
  final _todayInputCtrl = TextEditingController();
  final _todayInputFocusNode = FocusNode();
  // 주간 목표 입력
  final _weekInputCtrl = TextEditingController();
  // 월간 목표 입력
  final _monthInputCtrl = TextEditingController();

  // 목표 서브탭
  String _goalTab = 'week'; // 'week' | 'month'
  final _visionSectionKey = GlobalKey();
  final _addVisionButtonKey = GlobalKey();
  final Map<String, GlobalKey> _visionCardKeys = {};
  Set<String> _highlightedVisionIds = {};

  /// 배너를 눌러 들어왔을 때 번쩍일 할 일.
  ///
  /// 배너에는 버튼이 없다. 눌러서 앱에 오는 것이 전부라, 들어온 사람이 어느 칸을
  /// 보라고 부른 것인지 알 수 있어야 한다.
  final Map<String, GlobalKey> _bannerFocusKeys = {};
  String? _bannerFocusTaskId;
  bool _bannerFocusOn = false;
  Timer? _bannerFocusTimer;
  bool _highlightAddVisionButton = false;
  bool _highlightPulseOn = false;
  Timer? _visionHighlightTimer;
  bool _handledInitialPlannerTarget = false;

  @override
  void initState() {
    super.initState();
    _taskCheckboxHintPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _corePickBounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _swipeHintCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _coach = CoachConfigs.get(widget.coachId);
    final initialPlannerDate = DateTime.tryParse(
      widget.initialPlannerDateKey ?? '',
    );
    if (initialPlannerDate != null && widget.initialTabIndex == 1) {
      _calSelectedDay = DateTime(
        initialPlannerDate.year,
        initialPlannerDate.month,
        initialPlannerDate.day,
      );
      _calFocusedDay = _calSelectedDay;
    }
    _tabCtrl = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
    _tabCtrl.addListener(_handleTaskTabChanged);
    widget.controller?._attach(this);
    WidgetsBinding.instance.addObserver(this);
    NotificationService().recordPlannerOpened();
    _loadAll().then((_) {
      _handleInitialPlannerTarget();
      // 앱을 껐다 켠 사이에도 진행 중이던 할 일이 있으면 시계를 다시 돌린다.
      _syncTaskTicker();
      // 배너를 눌러 앱이 처음 켜진 경우다. 목록을 읽은 뒤라야 칸을 찾을 수 있다.
      _consumeBannerFocus();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reloadIfStoreChanged();
      _consumeBannerFocus();
    }
  }

  /// 배너가 남겨둔 자리를 보고 그 칸을 번쩍인다.
  ///
  /// 한 번 쓰면 지운다. 남겨두면 다음에 앱을 열 때마다 엉뚱한 칸이 번쩍인다.
  Future<void> _consumeBannerFocus() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final taskId = prefs.getString(NyangBannerNudge.focusTaskKey);
    if (taskId == null || taskId.isEmpty) return;
    await prefs.remove(NyangBannerNudge.focusTaskKey);
    if (!mounted) return;
    // 화면이 자리를 잡은 뒤에 움직인다. 그리기가 끝나기 전에는 칸의 자리를
    // 알 수 없어서 스크롤이 엉뚱한 데로 간다.
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _pulseBannerFocus(taskId);
  }

  Future<void> _pulseBannerFocus(String taskId) async {
    // 먼저 지목해두고 한 프레임 기다린다. 그 칸에 자리표가 달려야 어디 있는지
    // 찾을 수 있는데, 자리표는 지목된 칸에만 붙기 때문이다.
    setState(() {
      _bannerFocusTaskId = taskId;
      _bannerFocusOn = false;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final key = _bannerFocusKeys[taskId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
    }
    if (!mounted) return;

    _bannerFocusTimer?.cancel();
    var tick = 0;
    setState(() => _bannerFocusOn = true);
    // 켜고 끄기를 네 번. 두 번 번쩍이고 원래대로 돌아온다.
    _bannerFocusTimer = Timer.periodic(const Duration(milliseconds: 420), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick += 1;
      if (tick >= 4) {
        timer.cancel();
        setState(() {
          _bannerFocusTaskId = null;
          _bannerFocusOn = false;
        });
        _bannerFocusKeys.clear();
        return;
      }
      setState(() => _bannerFocusOn = !_bannerFocusOn);
    });
  }

  /// 켜둔 채 잠든 할 일을 자정에 멈춰 세운다.
  ///
  /// 밤 11시에 시작하고 그대로 자면 아침에 "600:00 / 30분"이 뜬다. 시계는
  /// 맞지만 그 사람이 열 시간을 한 건 아니다.
  ///
  /// 자정에 멈춘 것으로 치는 건, 할 일이 그날의 것이기 때문이다. 어차피 어느
  /// 쪽으로 잡아도 짐작이라면 하루 경계에서 끊는 편이 설명하기 쉽다.
  void _closeOvernightRuns(List<TaskItem> list) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    for (final t in list) {
      if (!t.inProgress || t.runStartedAt == null) continue;
      final started = DateTime.tryParse(t.runStartedAt!);
      if (started == null || !started.isBefore(todayStart)) continue;
      final dayEnd = DateTime(started.year, started.month, started.day + 1);
      final ran = dayEnd.difference(started).inSeconds;
      t.elapsedSeconds += ran > 0 ? ran : 0;
      t.inProgress = false;
      t.runStartedAt = null;
    }
  }

  /// 카드에 흐르는 시간을 보여줄지. 재는 것은 계속하고 표시만 감춘다.
  ///
  /// 끄면서 재는 것까지 멈추면 껐다 켠 사이가 비어서, 나중에 나오는 숫자가
  /// 실제보다 적어진다. 믿을 수 없는 값이 되느니 계속 세고 감추기만 한다.
  static const String _showTaskTimerKey = 'nyang_show_task_timer';
  bool _showTaskTimer = true;

  Future<void> _setShowTaskTimer(bool value) async {
    setState(() => _showTaskTimer = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showTaskTimerKey, value);
  }

  /// 길게 눌렀을 때 카드를 살짝 밀어 보이는 시늉.
  ///
  /// "밀어서 완료"라고 적어두어도 글자는 잘 안 읽힌다. 한 번 밀렸다 돌아오는
  /// 것을 보면 손이 따라 한다. 완료시키지는 않고 방법만 보여준다.
  late final AnimationController _swipeHintCtrl;
  dynamic _swipeHintTaskId;

  void _showSwipeHint(dynamic id) {
    if (_swipeHintCtrl.isAnimating) return;
    HapticFeedback.selectionClick();
    setState(() => _swipeHintTaskId = id);
    _swipeHintCtrl.forward(from: 0).then((_) async {
      await _swipeHintCtrl.reverse();
      if (mounted) setState(() => _swipeHintTaskId = null);
    });
  }

  /// 진행 중인 할 일의 초를 화면에서만 올리는 시계.
  ///
  /// 1초마다 서버에 쓰면 하루에 수천 번을 쓰게 된다. 흐르는 숫자는 기기에서
  /// 계산하고, 저장은 시작·일시정지·재시작·완료처럼 상태가 바뀔 때만 한다.
  /// 돌고 있는 할 일이 하나도 없으면 시계도 멈춰 둔다.
  Timer? _taskTicker;

  void _syncTaskTicker() {
    final running = _activeTodayTasksWithSchedules.any(
      (t) => t.hasTimer && t.inProgress && !t.done,
    );
    if (running) {
      _taskTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
      });
    } else {
      _taskTicker?.cancel();
      _taskTicker = null;
    }
  }

  @override
  void dispose() {
    widget.controller?._detach();
    WidgetsBinding.instance.removeObserver(this);
    _taskTicker?.cancel();
    _bannerFocusTimer?.cancel();
    _visionHighlightTimer?.cancel();
    _swipeHintCtrl.dispose();
    _taskCheckboxHintPulseCtrl.dispose();
    _corePickBounceCtrl.dispose();
    _tabCtrl.removeListener(_handleTaskTabChanged);
    _tabCtrl.dispose();
    _todayInputCtrl.dispose();
    _todayInputFocusNode.dispose();
    _weekInputCtrl.dispose();
    _monthInputCtrl.dispose();
    super.dispose();
  }

  /// 저장소를 마지막으로 읽어 온 시각. 밖에서 바뀐 게 있는지 이걸로 잰다.
  DateTime _lastStoreLoadAt = DateTime.fromMillisecondsSinceEpoch(0);

  // ── 데이터 로드 ──────────────────────────────────────────
  /// 첫 읽기가 끝났는지. 채팅에서 데려올 때 이걸 기다린다.
  ///
  /// 서랍이 열리자마자 부르는데, 그때는 목록이 아직 비어 있다. 그 상태에서
  /// 찾으면 있는 할 일도 "없다"가 되고, 사용자는 방금 적은 것을 못 찾는다는
  /// 말을 듣는다.
  bool _initialLoadDone = false;

  Future<void> _waitForInitialLoad() async {
    for (var i = 0; i < 20 && !_initialLoadDone; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // 앱이 열려 있는 동안 밖에서(냥냥이 오버레이 등) 고친 값도 함께 읽는다.
    await prefs.reload();
    _lastStoreLoadAt = DateTime.now();

    _showTaskTimer = prefs.getBool(_showTaskTimerKey) ?? true;
    final rawTasks = prefs.getString('nyang_tasks');
    final rawCore = prefs.getString('nyang_core_tasks');
    final rawWeek = prefs.getString('nyang_week_goals');
    final rawMonth = prefs.getString('nyang_month_goals');
    final rawHabits = prefs.getString('nyang_habits');
    final rawVisions = prefs.getString('nyang_visions');
    final rawSchedules = prefs.getString('nyang_schedules');
    final rawPlannedTodayTasks = prefs.getString('nyang_today_tasks_by_date');
    final rawLogs = prefs.getString('nyang_habit_logs');
    final taskCheckboxHintSeen =
        prefs.getBool(_taskCheckboxHintSeenKey) ?? false;
    final taskStatusGuideNeverShow =
        prefs.getBool(_taskStatusGuideNeverShowKey) ?? false;
    final lightenPlanCardDismissedDate = prefs.getString(
      _lightenPlanCardDismissedDateKey,
    );
    final corePickCardDismissedDate = prefs.getString(
      _corePickCardDismissedDateKey,
    );
    final hasActivePlan = await _hasActivePlan();
    if (!hasActivePlan) {
      await prefs.setBool('nyang_core_reminder_enabled', false);
    }
    final coreEnabled =
        hasActivePlan &&
        (prefs.getBool('nyang_core_reminder_enabled') ?? false);

    setState(() {
      _isCoreReminderEnabledGlobally = coreEnabled;
      _taskCheckboxHintSeen = taskCheckboxHintSeen;
      _taskStatusGuideNeverShow = taskStatusGuideNeverShow;
      _lightenPlanCardDismissedDate = lightenPlanCardDismissedDate;
      _corePickCardDismissedDate = corePickCardDismissedDate;
      _todayReminderEnabled = false;
      if (rawTasks != null) {
        tasks = (jsonDecode(rawTasks) as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
        _closeOvernightRuns(tasks);
      }
      if (rawCore != null) {
        coreTasks = (jsonDecode(rawCore) as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
        _closeOvernightRuns(coreTasks);
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
      if (rawPlannedTodayTasks != null) {
        final Map<String, dynamic> decodedMap = jsonDecode(
          rawPlannedTodayTasks,
        );
        plannedTodayTasksByDate = decodedMap.map((key, value) {
          final list = (value as List)
              .map((e) => TaskItem.fromJson(e))
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
    });

    if (!hasActivePlan) {
      var changed = false;
      for (final task in tasks) {
        if (task.isReminderEnabled) {
          task.isReminderEnabled = false;
          changed = true;
        }
      }
      schedules.forEach((_, items) {
        for (final item in items) {
          if (item.isReminderEnabled) {
            item.isReminderEnabled = false;
            changed = true;
          }
        }
      });
      if (changed) {
        await prefs.setString(
          'nyang_tasks',
          jsonEncode(tasks.map((t) => t.toJson()).toList()),
        );
        final Map<String, dynamic> toEncode = {};
        schedules.forEach((k, v) {
          if (v.isNotEmpty) {
            toEncode[k] = v.map((e) => e.toJson()).toList();
          }
        });
        await prefs.setString('nyang_schedules', jsonEncode(toEncode));
        TasksSyncService.scheduleSyncToCloud();
      }
    }

    await _checkReset(prefs);
    await _checkWeekMonthReset(prefs);
    await _promoteAndPrunePlannedTasks();
    _injectTodayHabits();
    _injectTodaySchedules();
    final coreMilestonesChanged = _syncTodayMilestonesIntoCoreTasks();
    if (coreMilestonesChanged) {
      if (mounted) setState(() {});
      await _saveCoreTasks();
    }

    _initialLoadDone = true;

    if (widget.initialBottomSheet != null) {
      _openBottomSheet(widget.initialBottomSheet!);
    }
  }

  void _handleInitialPlannerTarget() {
    if (_handledInitialPlannerTarget || !mounted) return;
    _handledInitialPlannerTarget = true;

    if (widget.initialTabIndex == 2) {
      final visionId = _visionIdFromPlannerItemId(widget.initialPlannerItemId);
      if (visionId != null) {
        _openGoalVision(highlightVisionIds: [visionId]);
      }
    }
  }

  String? _visionIdFromPlannerItemId(String? id) {
    if (id == null) return null;
    final parts = id.split(':');
    if (parts.length >= 4 && parts.first == 'milestone') return parts[2];
    if (parts.length >= 2 && parts.first == 'vision') return parts[1];
    return null;
  }

  Future<bool> _checkCoreReminderEnabledGlobally() async {
    final prefs = await SharedPreferences.getInstance();
    final hasActivePlan = await _hasActivePlan();
    if (!hasActivePlan) {
      await prefs.setBool('nyang_core_reminder_enabled', false);
    }
    final enabled =
        hasActivePlan &&
        (prefs.getBool('nyang_core_reminder_enabled') ?? false);
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

  Future<bool> _ensureCoreReminderEnabledFromHere() async {
    final enabled = await _checkCoreReminderEnabledGlobally();
    if (enabled) return true;
    final savedEnabled = await showCoreReminderSettingsSheet(context);
    if (!savedEnabled) return false;
    return _checkCoreReminderEnabledGlobally();
  }

  Future<bool> _prepareTimedScheduleStartReminder() async {
    if (!OngoingTaskNudgeService.isSupported) return false;

    var enabledPushReminder = false;
    if (await _hasActivePlan()) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('nyang_core_reminder_enabled', true);
      await prefs.setString('nyang_core_reminder_coach', 'push');
      if (prefs.getInt('nyang_core_reminder_advance') == null) {
        await prefs.setInt('nyang_core_reminder_advance', 10);
      }
      TasksSyncService.scheduleSyncToCloud();
      enabledPushReminder = true;
      if (mounted && !_isCoreReminderEnabledGlobally) {
        setState(() => _isCoreReminderEnabledGlobally = true);
      }
    }

    await NotificationService().requestNotificationPermissions();
    final issue = await NotificationService().checkCoreReminderPermission();
    if (!mounted) return enabledPushReminder;
    if (issue != AlarmPermissionIssue.none) {
      // 일정을 저장하다 곁다리로 걸리는 자리라, 권한 종류마다 한 번만 보여준다.
      if (await shouldAutoShowAlarmPermissionNotice(
        'timed_schedule_${issue.name}',
      )) {
        if (!mounted) return enabledPushReminder;
        await showAlarmPermissionDialog(
          context,
          issue,
          alarmLabel: '시간 냥냥이',
          emoji: '🐾',
        );
      }
      return enabledPushReminder;
    }

    await NotificationService().syncCoreReminders();

    if (_onAndroid && !await OngoingTaskNudgeService.isAvailable()) {
      if (!mounted) return enabledPushReminder;
      // 일정을 저장하다 곁다리로 걸리는 자리라, 한 번 보여줬으면 충분하다.
      // 안 고친 사람이 시간 있는 일정을 저장할 때마다 또 뜨면 안 된다.
      if (await shouldAutoShowAlarmPermissionNotice('timed_schedule_overlay')) {
        if (!mounted) return enabledPushReminder;
        final tapped = await _showOngoingNudgeNotice(
          title: '🐾 시간 냥냥이를 켜주세요',
          message:
              '시간이 있는 일정은 시작 시간에 냥냥이가 화면에 살짝 나와 알려드려요.\n'
              '설정에서 냥냥코치의 "다른 앱 위에 표시"를 켜주세요.',
          actionLabel: '설정 열기',
        );
        if (tapped) await OngoingTaskNudgeService.openSystemSettings();
      }
      return enabledPushReminder;
    }

    await OngoingTaskNudgeService.reconcile();
    return enabledPushReminder;
  }

  void _openBottomSheet(String type) {
    if (type == 'done') {
      _showTasksBottomSheet(title: '오늘 완료한 할 일', showDone: true);
    } else if (type == 'remaining') {
      _showTasksBottomSheet(
        title: '오늘 남은 할 일',
        showDone: false,
        fullScreen: true,
      );
    }
  }

  void _openTab(int index) {
    if (!mounted || index < 0 || index >= _tabCtrl.length) return;
    if (index == 0) _resetTodayDateSelection();
    if (_tabCtrl.index != index) {
      _tabCtrl.animateTo(index);
    }
  }

  Future<bool> _addHabitFromChat(
    String name, {
    String freq = 'daily',
    List<int> days = const [],
    int? weeklyTargetCount,
    int? countGoal,
    String? unit,
    TimeOfDay? time,
    TimeOfDay? endTime,
    String? habitDuration,
  }) async {
    if (!await _canInputTasks()) return false;
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;

    final habit = HabitItem(
      id: DateTime.now().millisecondsSinceEpoch,
      name: trimmedName,
      freq: freq,
      days: freq == 'weekly' ? List.from(days) : const [],
      weeklyTargetCount: freq == 'weekly_count'
          ? (weeklyTargetCount ?? 5)
          : null,
      checkType: countGoal != null ? 'count' : 'check',
      timeType: time == null
          ? 'duration'
          : (endTime == null ? 'single' : 'range'),
      tracking: true,
      countGoal: countGoal,
      unit: countGoal != null ? (unit ?? '번') : null,
      timeStart: time == null ? null : _storedTime(time),
      timeEnd: endTime == null ? null : _storedTime(endTime),
      habitDuration: time == null ? (habitDuration ?? '30분') : null,
      createdAt: DateTime.now().toIso8601String(),
      isReminderEnabled: time != null && _isCoreReminderEnabledGlobally,
    );

    setState(() {
      habits.add(habit);
    });
    _openTab(3);
    await _saveHabits();
    _injectTodayHabits();
    if (!mounted) return true;
    Future.delayed(const Duration(milliseconds: 360), () {
      if (!mounted) return;
      _showHabitModal(
        context,
        editHabit: habit,
        guideText: _habitRegistrationGuideText(),
      );
    });
    return true;
  }

  Future<String> _handleDeleteCommandFromChat(
    Map<String, dynamic> command,
  ) async {
    if (!await _canInputTasks()) {
      return PurchaseService.storeCheckoutEnabled
          ? '할 일, 일정, 루틴 관리는 Friends 또는 Master 플랜에서 이용할 수 있어요.'
          : '무료로 써볼 수 있는 기간이 끝났어요. 적어둔 것은 그대로 볼 수 있어요.';
    }
    final target = (command['target'] ?? '').toString().trim();
    final kind = (command['kind'] ?? 'task_or_schedule').toString();
    final dateKey = command['date']?.toString();
    final targetDate = dateKey == null ? null : DateTime.tryParse(dateKey);
    if (target.isEmpty) {
      return _deleteCommandReply('emptyTarget', target);
    }

    if (kind == 'habit') {
      _openTab(3);
      final found = habits.where((h) => _titleMatches(h.name, target)).toList();
      if (found.isEmpty) {
        return _deleteCommandReply('habitNotFound', target);
      }
      if (found.length > 1) {
        return _deleteCommandReply('habitMultiple', target);
      }
      return _deleteCommandReply('habitOpened', target);
    }

    if (kind == 'recurring_schedule') {
      final matches = _findScheduleMatches(
        target,
        dateKey: dateKey,
        recurringOnly: true,
      );
      if (matches.isEmpty) {
        _openTab(1);
        return _deleteCommandReply(
          'recurringNotFound',
          target,
          date: targetDate,
        );
      }
      if (matches.length > 1) {
        return _deleteCommandReply('recurringMultiple', target);
      }
      await _openScheduleDeleteMatch(matches.first, recurring: true);
      return _deleteCommandReply('recurringOpened', target);
    }

    final matches = _findTaskAndScheduleMatches(target, dateKey: dateKey);
    if (matches.isEmpty) {
      return _deleteCommandReply('notFound', target, date: targetDate);
    }
    if (matches.length > 1) {
      return _deleteCommandReply('multiple', target);
    }

    final match = matches.first;
    if (match['type'] == 'task') {
      await _openTaskDeleteMatch(
        match['task'] as TaskItem,
        dateKey: match['dateKey'] as String?,
      );
    } else {
      await _openScheduleDeleteMatch(match, recurring: false);
    }
    return _deleteCommandReply('opened', target);
  }

  /// 채팅에서 짚어준 할 일로 데려간다.
  ///
  /// 배너를 눌러 들어왔을 때 쓰는 길을 그대로 탄다 — 그 칸까지 스크롤하고
  /// 테두리를 두 번 번쩍인다. 체크는 사용자가 누른다.
  Future<String> _handleEditCommandFromChat(
    Map<String, dynamic> command,
  ) async {
    if (!await _canInputTasks()) {
      return PurchaseService.storeCheckoutEnabled
          ? '할 일, 일정 관리는 Friends 또는 Master 플랜에서 이용할 수 있어요.'
          : '무료로 써볼 수 있는 기간이 끝났어요. 적어둔 것은 그대로 볼 수 있어요.';
    }
    final target = (command['target'] ?? '').toString().trim();
    final kind = (command['kind'] ?? 'task_or_schedule').toString();
    final dateKey = command['date']?.toString();
    final targetDate = dateKey == null ? null : DateTime.tryParse(dateKey);

    // 루틴은 이름을 못 알아내도 탭까지는 데려간다.
    //
    // "주5일 하던 거 월수금으로 바꿔줘"에는 루틴 이름이 없다. 앞 턴에 있어서
    // 이 문장만으로는 무엇인지 알 수 없는데, 그렇다고 "이름을 말해달라"고 되묻는
    // 것보다 반복 요일을 고칠 수 있는 자리로 데려다주는 편이 빠르다.
    if (kind == 'habit') {
      _openTab(3);
      final found = habits.where((h) => _titleMatches(h.name, target)).toList();
      if (found.length == 1) {
        await Future.delayed(const Duration(milliseconds: 360));
        if (!mounted) return _editCommandReply('habitOpened', target);
        _showHabitModal(context, editHabit: found.first);
      }
      return _editCommandReply('habitOpened', found.length == 1 ? target : '');
    }

    if (target.isEmpty) {
      return _editCommandReply('emptyTarget', target);
    }

    final matches = kind == 'recurring_schedule'
        ? _findScheduleMatches(target, dateKey: dateKey, recurringOnly: true)
        : _findTaskAndScheduleMatches(target, dateKey: dateKey);
    if (matches.isEmpty) {
      _openTab(1);
      return _editCommandReply(
        kind == 'recurring_schedule' ? 'recurringNotFound' : 'notFound',
        target,
        date: targetDate,
      );
    }
    if (matches.length > 1) {
      return _editCommandReply(
        kind == 'recurring_schedule' ? 'recurringMultiple' : 'multiple',
        target,
      );
    }

    // 알람 이야기로 데려온 경우다. 알람 스위치는 시간 칸 안에 있어서, 접힌
    // 채로 열면 부탁한 것이 어디 있는지 찾아야 한다.
    final expandTime = command['focus'] == 'reminder';

    final match = matches.first;
    if (match['type'] == 'task') {
      await _openTaskEditMatch(
        match['task'] as TaskItem,
        dateKey: match['dateKey'] as String?,
        expandTimeOptions: expandTime,
      );
    } else {
      await _openScheduleEditMatch(match, expandTimeOptions: expandTime);
    }
    return _editCommandReply(
      expandTime
          ? 'reminderOpened'
          : kind == 'recurring_schedule'
          ? 'recurringOpened'
          : 'opened',
      target,
    );
  }

  String _deleteCommandReply(String key, String target, {DateTime? date}) {
    final quoted = target.isEmpty ? '항목' : '"$target"';
    final datePrefix = date == null ? '' : '${date.month}월 ${date.day}일에 ';
    switch (widget.coachId) {
      case 'boyfriend':
        return switch (key) {
          'emptyTarget' => '어떤 걸 삭제할지 이름까지 같이 말해줘.',
          'habitNotFound' => '루틴 탭은 열어둘게. $quoted 루틴은 못 찾았으니까 이름 한번만 확인해줘.',
          'habitMultiple' => '루틴 탭은 열어둘게. $quoted 비슷한 게 여러 개라 직접 보고 지워줘.',
          'habitOpened' => '루틴 탭 열어둘게. $quoted 옆 휴지통 버튼으로 확인하고 삭제해줘.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았어. 날짜나 이름 한번만 확인해줘.',
          'recurringMultiple' =>
            '$quoted 비슷한 반복 일정이 여러 개야. 날짜나 이름을 조금만 더 정확히 말해줘.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창 열어둘게. 마지막으로 확인만 해줘.',
          'notFound' => '$datePrefix$quoted로 등록된 할 일이나 일정은 못 찾았어. 이름 한번만 확인해줘.',
          'multiple' => '$quoted 비슷한 항목이 여러 개야. 날짜나 이름을 조금만 더 정확히 말해줘.',
          _ => '$quoted 찾아뒀어. 확인하고 삭제하거나 날짜를 바꿔줘.',
        };
      case 'bro':
        return switch (key) {
          'emptyTarget' => '뭘 삭제할지 이름까지 같이 말해라.',
          'habitNotFound' => '루틴 탭은 열어둔다. $quoted 루틴은 안 보이니까 이름 확인해라.',
          'habitMultiple' => '루틴 탭은 열어둔다. $quoted 비슷한 게 여러 개니까 직접 보고 지워라.',
          'habitOpened' => '루틴 탭 열어둔다. $quoted 옆 휴지통 눌러서 확인하고 삭제해라.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 안 보인다. 날짜나 이름 확인해라.',
          'recurringMultiple' => '$quoted 비슷한 반복 일정이 여러 개다. 날짜나 이름 더 정확히 말해라.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창 열어뒀다. 확인하고 지워라.',
          'notFound' => '$datePrefix$quoted로 등록된 할 일이나 일정은 안 보인다. 이름 확인해라.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다. 날짜나 이름 더 정확히 말해라.',
          _ => '$quoted 찾아뒀다. 확인하고 삭제하거나 날짜 바꿔라.',
        };
      case 'halmae':
        return switch (key) {
          'emptyTarget' => '뭘 지울지 이름까지 말해줘야 한다, 우리 새끼.',
          'habitNotFound' => '루틴 탭은 열어둘게. $quoted 루틴은 못 찾았으니 이름을 다시 봐라.',
          'habitMultiple' => '루틴 탭은 열어둘게. $quoted 비슷한 게 여러 개니 네가 보고 지워라.',
          'habitOpened' => '루틴 탭 열어둘게. $quoted 옆 휴지통 버튼 눌러서 확인하고 지워라.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았다. 날짜나 이름을 다시 봐라.',
          'recurringMultiple' => '$quoted 비슷한 반복 일정이 여러 개다. 조금 더 똑바로 말해줘야 한다.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창 열어뒀다. 마지막으로 보고 지워라.',
          'notFound' => '$datePrefix$quoted로 등록된 할 일이나 일정은 못 찾았다. 이름을 다시 봐라.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다. 조금 더 자세히 말해줘라.',
          _ => '$quoted 찾아뒀다. 확인하고 지우든 날짜를 바꾸든 해라.',
        };
      case 'nyang_halbae':
        return switch (key) {
          'emptyTarget' => '삭제할 항목명을 함께 말씀해 주세요.',
          'habitNotFound' =>
            '루틴 탭을 열어두겠습니다. $quoted 루틴은 찾지 못했습니다. 항목명을 확인해 주세요.',
          'habitMultiple' =>
            '루틴 탭을 열어두겠습니다. $quoted와 유사한 루틴이 여러 개라 직접 확인 후 삭제해 주세요.',
          'habitOpened' => '루틴 탭을 열어두겠습니다. $quoted 항목의 휴지통 버튼으로 확인 후 삭제해 주세요.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 찾지 못했습니다. 날짜나 항목명을 확인해 주세요.',
          'recurringMultiple' =>
            '$quoted와 유사한 반복 일정이 여러 개입니다. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창을 열어두겠습니다. 최종 확인을 부탁드립니다.',
          'notFound' =>
            '$datePrefix$quoted로 등록된 할 일이나 일정은 찾지 못했습니다. 항목명을 확인해 주세요.',
          'multiple' => '$quoted와 유사한 항목이 여러 개입니다. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          _ => '$quoted 항목을 찾아두었습니다. 확인 후 삭제하거나 날짜를 변경해 주세요.',
        };
      case 'sec_female':
        return switch (key) {
          'emptyTarget' => '삭제할 항목명을 함께 말씀해 주세요.',
          'habitNotFound' => '루틴 탭을 열어둘게요. $quoted 루틴은 찾지 못했어요. 항목명을 확인해 주세요.',
          'habitMultiple' =>
            '루틴 탭을 열어둘게요. $quoted와 비슷한 루틴이 여러 개라 직접 확인 후 삭제해 주세요.',
          'habitOpened' => '루틴 탭을 열어둘게요. $quoted 항목의 휴지통 버튼으로 확인 후 삭제해 주세요.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 찾지 못했어요. 날짜나 항목명을 확인해 주세요.',
          'recurringMultiple' =>
            '$quoted와 비슷한 반복 일정이 여러 개예요. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창을 열어둘게요. 최종 확인을 부탁드려요.',
          'notFound' =>
            '$datePrefix$quoted로 등록된 할 일이나 일정은 찾지 못했어요. 항목명을 확인해 주세요.',
          'multiple' => '$quoted와 비슷한 항목이 여러 개예요. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          _ => '$quoted 항목을 찾아두었어요. 확인 후 삭제하거나 날짜를 변경해 주세요.',
        };
      default:
        return switch (key) {
          'emptyTarget' => '어떤 걸 삭제할지 이름까지 같이 말해달라냥.',
          'habitNotFound' => '루틴 탭을 열어둘게냥. $quoted 루틴은 못 찾았다냥. 이름을 확인해달라냥.',
          'habitMultiple' => '루틴 탭을 열어둘게냥. $quoted 비슷한 게 여러 개라 직접 보고 삭제해달라냥.',
          'habitOpened' => '루틴 탭 열어둘게냥. $quoted 옆 휴지통 버튼으로 확인하고 삭제해달라냥.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았다냥. 날짜나 이름을 확인해달라냥.',
          'recurringMultiple' =>
            '$quoted 비슷한 반복 일정이 여러 개다냥. 날짜나 이름을 더 정확히 말해달라냥.',
          'recurringOpened' => '$quoted 반복 일정 삭제 확인창을 열어둘게냥. 마지막으로 확인해달라냥.',
          'notFound' => '$datePrefix$quoted로 등록된 할 일이나 일정은 못 찾았다냥. 이름을 확인해달라냥.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다냥. 날짜나 이름을 더 정확히 말해달라냥.',
          _ => '$quoted 항목을 찾아뒀다냥. 확인 후 삭제하거나 날짜를 바꿔달라냥.',
        };
    }
  }

  String _editCommandReply(String key, String target, {DateTime? date}) {
    final quoted = target.isEmpty ? '항목' : '"$target"';
    final datePrefix = date == null ? '' : '${date.month}월 ${date.day}일에 ';
    switch (widget.coachId) {
      case 'boyfriend':
        return switch (key) {
          'habitOpened' => '루틴 탭 열어뒀어. 반복 요일은 거기서 바꾸면 돼.',
          'reminderOpened' => '$quoted 수정창 열어뒀어. 시간 옆 "알림 켜기"를 누르면 돼.',
          'emptyTarget' => '어떤 일정을 수정할지 이름까지 같이 말해줘.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았어. 캘린더에서 한번 확인해줘.',
          'recurringMultiple' =>
            '$quoted 비슷한 반복 일정이 여러 개야. 날짜나 이름을 조금만 더 정확히 말해줘.',
          'recurringOpened' => '$quoted 반복 일정 수정창 열어둘게. 바꿀 내용은 확인해서 직접 조정해줘.',
          'notFound' => '$datePrefix$quoted 항목은 못 찾았어. 캘린더에서 한번 확인해줘.',
          'multiple' => '$quoted 비슷한 항목이 여러 개야. 날짜나 이름을 조금만 더 정확히 말해줘.',
          _ => '$quoted 수정창 열어둘게. 바꿀 내용은 확인해서 직접 조정해줘.',
        };
      case 'bro':
        return switch (key) {
          'habitOpened' => '루틴 탭 열어뒀다. 반복 요일은 거기서 바꿔라.',
          'reminderOpened' => '$quoted 수정창 열어뒀다. 시간 옆 "알림 켜기" 눌러라.',
          'emptyTarget' => '뭘 수정할지 이름까지 같이 말해라.',
          'recurringNotFound' => '$datePrefix$quoted 반복 일정은 안 보인다. 캘린더에서 확인해라.',
          'recurringMultiple' => '$quoted 비슷한 반복 일정이 여러 개다. 날짜나 이름 더 정확히 말해라.',
          'recurringOpened' => '$quoted 반복 일정 수정창 열어뒀다. 바꿀 건 직접 보고 조정해라.',
          'notFound' => '$datePrefix$quoted 항목은 안 보인다. 캘린더에서 확인해라.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다. 날짜나 이름 더 정확히 말해라.',
          _ => '$quoted 수정창 열어뒀다. 바꿀 건 직접 보고 조정해라.',
        };
      case 'halmae':
        return switch (key) {
          'habitOpened' => '루틴 탭 열어뒀다. 반복 요일은 거기서 고치면 된다.',
          'reminderOpened' => '$quoted 수정창 열어뒀다. 시간 옆 "알림 켜기"를 누르면 된다.',
          'emptyTarget' => '뭘 고칠지 이름까지 말해줘야 한다, 우리 새끼.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았다. 캘린더에서 다시 봐라.',
          'recurringMultiple' => '$quoted 비슷한 반복 일정이 여러 개다. 조금 더 자세히 말해줘라.',
          'recurringOpened' => '$quoted 반복 일정 수정창 열어뒀다. 바꿀 건 네가 보고 고쳐라.',
          'notFound' => '$datePrefix$quoted 항목은 못 찾았다. 캘린더에서 다시 봐라.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다. 조금 더 자세히 말해줘라.',
          _ => '$quoted 수정창 열어뒀다. 바꿀 건 네가 보고 고쳐라.',
        };
      case 'nyang_halbae':
        return switch (key) {
          'habitOpened' => '루틴 탭 열어뒀다냥. 반복 요일은 거기서 바꾸면 된다냥.',
          'reminderOpened' => '$quoted 수정창 열어뒀다냥. 시간 옆 "알림 켜기"를 누르면 된다냥.',
          'emptyTarget' => '수정할 항목명을 함께 말씀해 주세요.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 찾지 못했습니다. 캘린더에서 확인해 주세요.',
          'recurringMultiple' =>
            '$quoted와 유사한 반복 일정이 여러 개입니다. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          'recurringOpened' =>
            '$quoted 반복 일정 수정창을 열어두었습니다. 변경 내용은 확인 후 조정해 주세요.',
          'notFound' => '$datePrefix$quoted 항목은 찾지 못했습니다. 캘린더에서 확인해 주세요.',
          'multiple' => '$quoted와 유사한 항목이 여러 개입니다. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          _ => '$quoted 수정창을 열어두었습니다. 변경 내용은 확인 후 조정해 주세요.',
        };
      case 'sec_female':
        return switch (key) {
          'habitOpened' => '루틴 탭을 열어뒀어요. 반복 요일은 거기서 바꾸시면 돼요.',
          'reminderOpened' => '$quoted 수정창을 열어뒀어요. 시간 옆 "알림 켜기"를 눌러주세요.',
          'emptyTarget' => '수정할 항목명을 함께 말씀해 주세요.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 찾지 못했어요. 캘린더에서 확인해 주세요.',
          'recurringMultiple' =>
            '$quoted와 비슷한 반복 일정이 여러 개예요. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          'recurringOpened' =>
            '$quoted 반복 일정 수정창을 열어두었어요. 변경 내용은 확인 후 조정해 주세요.',
          'notFound' => '$datePrefix$quoted 항목은 찾지 못했어요. 캘린더에서 확인해 주세요.',
          'multiple' => '$quoted와 비슷한 항목이 여러 개예요. 날짜나 항목명을 더 구체적으로 말씀해 주세요.',
          _ => '$quoted 수정창을 열어두었어요. 변경 내용은 확인 후 조정해 주세요.',
        };
      default:
        return switch (key) {
          'habitOpened' => '루틴 탭 열어뒀다냥. 반복 요일은 거기서 바꾸면 된다냥.',
          'reminderOpened' => '$quoted 수정창 열어뒀다냥. 시간 옆 "알림 켜기"를 누르면 된다냥.',
          'emptyTarget' => '어떤 일정을 수정할지 이름까지 같이 말해달라냥.',
          'recurringNotFound' =>
            '$datePrefix$quoted 반복 일정은 못 찾았다냥. 캘린더에서 확인해달라냥.',
          'recurringMultiple' =>
            '$quoted 비슷한 반복 일정이 여러 개다냥. 날짜나 이름을 더 정확히 말해달라냥.',
          'recurringOpened' => '$quoted 반복 일정 수정창 열어둘게냥. 바꿀 내용은 확인해서 조정해달라냥.',
          'notFound' => '$datePrefix$quoted 항목은 못 찾았다냥. 캘린더에서 확인해달라냥.',
          'multiple' => '$quoted 비슷한 항목이 여러 개다냥. 날짜나 이름을 더 정확히 말해달라냥.',
          _ => '$quoted 수정창 열어둘게냥. 바꿀 내용은 확인해서 조정해달라냥.',
        };
    }
  }

  String _normalizeDeleteMatchText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'(?:약속|일정|할일|항목)$'), '')
        .replaceAll(RegExp(r'(?:을|를|은|는|이|가)$'), '')
        .toLowerCase();
  }

  bool _titleMatches(String title, String target) {
    final normalizedTitle = _normalizeDeleteMatchText(title);
    final normalizedTarget = _normalizeDeleteMatchText(target);
    if (normalizedTarget.isEmpty) return false;
    return normalizedTitle == normalizedTarget ||
        normalizedTitle.contains(normalizedTarget) ||
        normalizedTarget.contains(normalizedTitle);
  }

  List<Map<String, dynamic>> _findScheduleMatches(
    String target, {
    String? dateKey,
    bool recurringOnly = false,
  }) {
    final matches = <Map<String, dynamic>>[];
    final seenRecurringGroups = <String>{};
    schedules.forEach((key, daySchedules) {
      if (dateKey != null && key != dateKey) return;
      for (var i = 0; i < daySchedules.length; i++) {
        final schedule = daySchedules[i];
        if (recurringOnly && !schedule.isRecurring) continue;
        if (!_titleMatches(schedule.text, target)) continue;
        if (recurringOnly) {
          final groupKey = schedule.recurrenceGroupId ?? schedule.id;
          if (!seenRecurringGroups.add(groupKey)) continue;
        }
        matches.add({
          'type': 'schedule',
          'schedule': schedule,
          'dateKey': key,
          'index': i,
        });
      }
    });
    return matches;
  }

  List<Map<String, dynamic>> _findTaskAndScheduleMatches(
    String target, {
    String? dateKey,
  }) {
    final matches = <Map<String, dynamic>>[];
    final todayKey = _getTodayStr();
    if (dateKey == null || dateKey == todayKey) {
      for (final task in tasks) {
        if (_titleMatches(task.text, target)) {
          matches.add({'type': 'task', 'task': task, 'dateKey': todayKey});
        }
      }
    }
    if (dateKey != null && dateKey != todayKey) {
      for (final task in plannedTodayTasksByDate[dateKey] ?? <TaskItem>[]) {
        if (_titleMatches(task.text, target)) {
          matches.add({'type': 'task', 'task': task, 'dateKey': dateKey});
        }
      }
    }
    matches.addAll(_findScheduleMatches(target, dateKey: dateKey));
    return matches;
  }

  Future<void> _openTaskDeleteMatch(TaskItem task, {String? dateKey}) async {
    final targetDate = dateKey == null ? null : DateTime.tryParse(dateKey);
    _openTab(0);
    if (targetDate != null) {
      setState(() {
        _selectedTodayDate = targetDate;
      });
    }
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    if (task.category == 'schedule' && _isRecurringScheduleTask(task)) {
      await _deleteRecurringScheduleItem(task);
      return;
    }
    await _showTaskDeleteOptions(task);
  }

  Future<void> _openTaskEditMatch(
    TaskItem task, {
    String? dateKey,
    bool expandTimeOptions = false,
  }) async {
    final targetDate = dateKey == null ? null : DateTime.tryParse(dateKey);
    _openTab(0);
    if (targetDate != null) {
      setState(() {
        _selectedTodayDate = targetDate;
      });
    }
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    _showEditItemModal(task, expandTimeOptions: expandTimeOptions, () {
      setState(() {
        final cIdx = coreTasks.indexWhere((ct) => ct.id == task.id);
        if (cIdx != -1) {
          coreTasks[cIdx].time = task.time;
          coreTasks[cIdx].timeStart = task.timeStart;
          coreTasks[cIdx].timeEnd = task.timeEnd;
          coreTasks[cIdx].duration = task.duration;
          coreTasks[cIdx].text = task.text;
          coreTasks[cIdx].isReminderEnabled = task.isReminderEnabled;
          coreTasks[cIdx].memo = task.memo;
        }
      });
      _saveTasks();
      _saveCoreTasks();
      if (task.category == 'schedule') _saveSchedules();
    });
  }

  Future<void> _openScheduleDeleteMatch(
    Map<String, dynamic> match, {
    required bool recurring,
  }) async {
    final schedule = match['schedule'] as ScheduleItem;
    final dateKey = match['dateKey'] as String;
    final targetDate = DateTime.tryParse(dateKey) ?? DateTime.now();
    setState(() {
      _calSelectedDay = targetDate;
      _calFocusedDay = targetDate;
    });
    _openTab(1);
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    if (recurring || schedule.isRecurring) {
      await _deleteRecurringScheduleItem(schedule);
      return;
    }
    _showEditItemModal(
      schedule,
      () {
        setState(() {});
        _saveSchedules();
      },
      onDelete: () {
        setState(() {
          final daySchedules = schedules[dateKey];
          daySchedules?.removeWhere((s) => s.id == schedule.id);
          if (daySchedules != null && daySchedules.isEmpty) {
            schedules.remove(dateKey);
          }
        });
        _saveSchedules();
      },
    );
  }

  Future<void> _openScheduleEditMatch(
    Map<String, dynamic> match, {
    bool expandTimeOptions = false,
  }) async {
    final schedule = match['schedule'] as ScheduleItem;
    final dateKey = match['dateKey'] as String;
    final targetDate = DateTime.tryParse(dateKey) ?? DateTime.now();
    setState(() {
      _calSelectedDay = targetDate;
      _calFocusedDay = targetDate;
    });
    _openTab(1);
    await Future.delayed(const Duration(milliseconds: 360));
    if (!mounted) return;
    _showEditItemModal(
      schedule,
      expandTimeOptions: expandTimeOptions,
      () {
        setState(() {});
        _saveSchedules();
      },
      onDelete: () {
        setState(() {
          final daySchedules = schedules[dateKey];
          daySchedules?.removeWhere((s) => s.id == schedule.id);
          if (daySchedules != null && daySchedules.isEmpty) {
            schedules.remove(dateKey);
          }
        });
        _saveSchedules();
      },
    );
  }

  void _handleTaskTabChanged() {
    if (!mounted || _tabCtrl.index == 0 || _selectedTodayDate == null) return;
    setState(() => _selectedTodayDate = null);
  }

  void _openGoalVision({List<String> highlightVisionIds = const []}) {
    if (!mounted) return;
    if (_tabCtrl.index != 2) {
      _tabCtrl.animateTo(2);
    }

    Future.delayed(const Duration(milliseconds: 280), () async {
      if (!mounted) return;
      final visionContext = _visionSectionKey.currentContext;
      if (visionContext == null) return;
      await Scrollable.ensureVisible(
        visionContext,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
      final targetVisionId = highlightVisionIds.firstWhere(
        (id) => _visionCardKeys[id]?.currentContext != null,
        orElse: () => '',
      );
      if (targetVisionId.isNotEmpty) {
        final targetContext = _visionCardKeys[targetVisionId]?.currentContext;
        if (targetContext != null) {
          await Scrollable.ensureVisible(
            targetContext,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            alignment: 0.22,
          );
        }
      }
      if (highlightVisionIds.isEmpty) {
        final addButtonContext = _addVisionButtonKey.currentContext;
        if (addButtonContext != null) {
          await Scrollable.ensureVisible(
            addButtonContext,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: 0.18,
          );
        }
        _pulseAddVisionButton();
        return;
      }
      _pulseVisionHighlights(highlightVisionIds);
    });
  }

  void _pulseVisionHighlights(List<String> visionIds) {
    final ids = visionIds.toSet()..removeWhere((id) => id.trim().isEmpty);
    if (ids.isEmpty || !mounted) return;

    _visionHighlightTimer?.cancel();
    var tick = 0;
    setState(() {
      _highlightedVisionIds = ids;
      _highlightAddVisionButton = false;
      _highlightPulseOn = true;
    });

    _visionHighlightTimer = Timer.periodic(const Duration(milliseconds: 420), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick += 1;
      if (tick >= 4) {
        timer.cancel();
        setState(() {
          _highlightedVisionIds = {};
          _highlightAddVisionButton = false;
          _highlightPulseOn = false;
        });
        return;
      }
      setState(() {
        _highlightPulseOn = !_highlightPulseOn;
      });
    });
  }

  void _pulseAddVisionButton() {
    if (!mounted) return;

    _visionHighlightTimer?.cancel();
    var tick = 0;
    setState(() {
      _highlightedVisionIds = {};
      _highlightAddVisionButton = true;
      _highlightPulseOn = true;
    });

    _visionHighlightTimer = Timer.periodic(const Duration(milliseconds: 420), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick += 1;
      if (tick >= 4) {
        timer.cancel();
        setState(() {
          _highlightAddVisionButton = false;
          _highlightPulseOn = false;
        });
        return;
      }
      setState(() {
        _highlightPulseOn = !_highlightPulseOn;
      });
    });
  }

  GlobalKey _visionCardKey(String visionId) {
    return _visionCardKeys.putIfAbsent(visionId, () => GlobalKey());
  }

  void _showTasksBottomSheet({
    required String title,
    required bool showDone,
    bool fullScreen = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: fullScreen,
      builder: (ctx) {
        final filteredTasks = tasks.where((t) => t.done == showDone).toList();
        final sheetHeight = MediaQuery.of(context).size.height * 0.9;
        return Container(
          height: fullScreen ? sheetHeight : null,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: fullScreen ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (fullScreen) ...[
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
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
                Flexible(
                  fit: fullScreen ? FlexFit.tight : FlexFit.loose,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: fullScreen
                          ? sheetHeight
                          : MediaQuery.of(context).size.height * 0.4,
                    ),
                    child: ListView.builder(
                      shrinkWrap: !fullScreen,
                      padding: EdgeInsets.zero,
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
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkReset(SharedPreferences prefs) async {
    // 첫 클라우드 복원 전에는 리셋하지 않는다 (재설치 직후 데이터 유실 방지).
    if (DailyResetService.isCloudRestorePending(prefs)) return;
    final today = _getTodayStr();
    final lastDate = prefs.getString('nyang_last_date');

    if (lastDate == null) {
      await prefs.setString('nyang_last_date', today);
      return;
    }

    if (lastDate != today) {
      final previousDayHadTasks = tasks.isNotEmpty;
      final previousDayAllDone =
          previousDayHadTasks && tasks.every((task) => task.done);
      await DailyResetService.recordDayTransition(
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
      final yStr =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      int streak = prefs.getInt('nyang_streak') ?? 0;

      if (lastDate == yStr) {
        if (prev.isNotEmpty && prev['success'] == true) {
          streak += 1;
        } else {
          streak = 0;
        }
      } else {
        if (prev.isNotEmpty && prev['success'] == true) {
          streak = 1;
        } else {
          streak = 0;
        }
      }

      await prefs.setInt('nyang_streak', streak);

      // 2. Clear tasks — 어제 목록은 하루만 보관함에 남긴다.
      // 전날 완료 표시를 깜빡했거나 자정을 넘겨 끝낸 일을 어제 화면에서 채울 수 있게.
      await DailyResetService.archivePreviousDayTasks(
        prefs: prefs,
        fromDate: lastDate,
        today: today,
        tasksJson: tasks.map((t) => t.toJson()).toList(),
      );
      await _loadPlannedTodayTasks(prefs);
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
      try {
        final oldChatHistory =
            DailyResetService.collectChatHistoryForDailySummary(prefs);
        if (oldChatHistory.isNotEmpty) {
          await MemoryService().loadMemoryData();
          await MemoryService().generateDailySummary(lastDate, oldChatHistory);
        }
      } catch (e) {
        print('Failed to generate daily summary: $e');
      }

      // 4. Clear all chat histories
      for (final id in DailyResetService.coachIds) {
        await prefs.setString('nyang_chat_history_$id', '[]');
      }

      await prefs.setString('nyang_last_date', today);
    }
  }

  // ── checkWeekMonthReset ───────────────────────────────────
  Future<void> _checkWeekMonthReset(SharedPreferences prefs) async {
    if (DailyResetService.isCloudRestorePending(prefs)) return;
    final thisWeek = _getWeekMondayStr();
    final todayStr = _getTodayStr();
    final parts = todayStr.split('-');
    final y = parts.length > 0 ? parts[0] : DateTime.now().year.toString();
    final m = parts.length > 1
        ? parts[1].padLeft(2, '0')
        : DateTime.now().month.toString().padLeft(2, '0');
    final thisMonth = '$y-$m';

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

  /// 이 화면의 확인창은 전부 이 모양이다 — 제목, 설명 한 줄, 취소와 실행 버튼.
  /// 삭제가 아닌 확인도 여기를 쓰고 버튼 글자와 색만 바꾼다.
  Future<bool> _showConfirmDialog(
    String title,
    String message, {
    String confirmLabel = '삭제',
    Color confirmColor = Colors.red,
  }) async {
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
          // 제목만으로 충분한 확인은 설명을 비워 부른다.
          content: message.isEmpty
              ? null
              : Text(
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
                confirmLabel,
                style: GoogleFonts.notoSansKr(
                  color: confirmColor,
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
    if (!_isViewingActualToday) {
      await _savePlannedTodayTasks();
      // 지난 날에 채운 완료 표시는 그날 기록에도 반영해야 기록 탭과 어긋나지 않는다.
      if (_isViewingArchivedPastDate) {
        await _saveRecordForPastDate(_activeTodayDateKey);
      }
      return;
    }
    await _persistTodayTasks();
  }

  Future<void> _persistTodayTasks() async {
    if (!await _hasActivePlan()) {
      for (final task in tasks) {
        task.isReminderEnabled = false;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_tasks',
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
    await _saveTodayRecord();
    await WidgetSyncService.syncFromStoredTasks();
    // 낮에 부를지 말지는 지금 상태로 정해진다. 일을 시작했거나 계획을 세운
    // 순간 예약을 다시 계산해야, 이미 움직인 사람에게 12시에 "슬슬 시작해볼까"가
    // 울리는 일이 없다.
    unawaited(NotificationService().syncDailyPlannerNudge());
    // 일정 알람을 실제로 거는 자리다. "오늘 할 일 직접 추가"처럼 이 저장 함수
    // 하나만 타고 끝나는 길에서는 이걸 부르지 않으면, 알림 벨을 켜서 등록해도
    // 실제 예약은 한 번도 안 걸린 채로 남는다.
    unawaited(NotificationService().syncCoreReminders());
    unawaited(_syncOngoingNudge());
    // 다이내믹 아일랜드가 없는 아이폰은 냥냥이 대신 배너가 찾아간다.
    unawaited(NyangBannerNudge.sync());
    widget.onProgressChanged?.call();
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 진행 중인 일정 하나를 냥냥이에게 맡기거나 거둬들인다.
  ///
  /// 저장이 일어나는 자리에서만 부른다. 시작·일시정지·완료가 전부 여기를 지나기
  /// 때문에, 상태가 바뀐 순간마다 정확히 한 번씩 맞춰진다.
  Future<void> _syncOngoingNudge() async {
    if (!OngoingTaskNudgeService.isSupported) return;
    TaskItem? running;
    for (final task in tasks) {
      if (task.inProgress && !task.done) {
        running = task;
        break;
      }
    }
    if (running == null) {
      await OngoingTaskNudgeService.stopPreservingNextTask();
    } else {
      await OngoingTaskNudgeService.start(
        taskId: running.id.toString(),
        taskText: running.text,
        elapsedSeconds: running.elapsedSecondsAt(DateTime.now()),
      );
      await _tellQuotaSpentIfNeeded(running.id.toString());
    }

    // 시작 시각 알림은 도는 일정이 있는지와 무관한 별도 자리다. 시작한 일을
    // 잊는 것보다 시작 자체를 안 하는 쪽이 훨씬 흔해서, 진행 중인 일정이 있어도
    // 매번 다시 본다.
    final next = OngoingTaskNudgeService.nextUnstartedTask(
      tasks.map((t) => t.toJson()).toList(),
      DateTime.now(),
    );
    if (next != null) {
      await OngoingTaskNudgeService.remindStart(
        taskId: next['id'].toString(),
        taskText: next['text']?.toString() ?? '',
        startAt: next['_startAt'] as DateTime,
      );
    } else {
      await OngoingTaskNudgeService.clearStart();
    }
  }

  /// 시작해뒀다 방금 멈춘 일이, 3시간이 지나도 여전히 멈춰 있고 다른 무엇도
  /// 도는 게 없으면 한 번 물어보게 걸어둔다. 마스터 플랜 전용.
  ///
  /// 트리거만 여기서 건다. 22시까지 이어지는 반복과 조건 재검사(그 사이 다시
  /// 시작했거나, 다른 일을 손댔거나)는 [_maybeScheduleNextTaskNudge]와 같은
  /// 방식으로 안드로이드는 네이티브가, 아이폰은 [NyangBannerNudge.sync]가 잇는다.
  Future<void> _maybeScheduleResumeNudge(TaskItem t) async {
    if (!OngoingTaskNudgeService.isSupported) return;
    if (!t.isPaused) return;
    final userData = await UserDataService.load();
    if (!userData.isPlanActive || userData.planType != 'master') return;

    await OngoingTaskNudgeService.remindResume(
      taskId: t.id.toString(),
      taskText: t.text,
      fireAt: DateTime.now().add(const Duration(hours: 3)),
    );
  }

  /// 방금 하나를 끝냈고, 시간이 정해지지 않은 다음 일이 남아 있으면 3시간 뒤
  /// 한 번 물어보게 걸어둔다. 마스터 플랜 전용.
  ///
  /// 여기서는 처음 한 번만 건다. 그 뒤 22시까지 이어지는 반복과, "이미 다른 걸
  /// 시작했다"/"남은 일이 없어졌다" 같은 조건 재검사는 안드로이드는 네이티브가,
  /// 아이폰은 [NyangBannerNudge.sync]가 저장이 일어날 때마다 스스로 잇는다.
  Future<void> _maybeScheduleNextTaskNudge() async {
    if (!OngoingTaskNudgeService.isSupported) return;
    final userData = await UserDataService.load();
    if (!userData.isPlanActive || userData.planType != 'master') return;

    // 안 끝난 일 중에 시간이 정해진 게 하나라도 있으면 걸지 않는다. 곧 있을
    // 약속을 앞두고 다른 것도 시작할지 물으면, 정작 지켜야 할 시각에 마음을
    // 못 쓰게 만든다.
    final hasTimedRemaining = _activeTodayTasksWithSchedules.any(
      (ts) => !ts.done && ts.timeStart != null && ts.timeStart!.isNotEmpty,
    );
    if (hasTimedRemaining) return;

    // 안드로이드 쪽 재검사는 'nyang_tasks'에 저장된 것만 직접 읽는다. 그
    // 목록에 없는 것(마일스톤·일정)을 여기서 고르면, 처음 걸 때만 그 이름이
    // 보이고 첫 재검사에서 곧장 조건 미달로 접혀 나오지 않는다.
    final candidates = _activeTodayTasksWithSchedules.where(
      (ts) =>
          ts.hasTimer &&
          ts.category != 'schedule' &&
          !ts.done &&
          !ts.inProgress &&
          ts.elapsedSeconds == 0 &&
          (ts.timeStart == null || ts.timeStart!.isEmpty),
    );
    if (candidates.isEmpty) return;
    final candidate = candidates.first;

    await OngoingTaskNudgeService.remindNextTask(
      taskId: candidate.id.toString(),
      taskText: candidate.text,
      fireAt: DateTime.now().add(const Duration(hours: 3)),
    );
  }

  /// 오늘치 딴짓 방지 코칭이 이미 다른 일정에 쓰였다고 알려준다.
  ///
  /// 아무 말 없이 안 나오면 고장과 구별되지 않는다. 그렇다고 ▶를 누를 때마다
  /// 말하면 잔소리라, 하루 한 번만 말한다. 그 판단은 저장소가 들고 있으므로
  /// 여기서는 물어보기만 한다.
  Future<void> _tellQuotaSpentIfNeeded(String taskId) async {
    if (!await DistractionCoachQuota.shouldTellQuotaSpent(taskId)) return;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: const Color(0xFF3D3A4E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text(
          DistractionCoachQuota.quotaSpentMessage,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// 딴짓 방지 코치를 켤지 딱 한 번 물어본다.
  ///
  /// 설정 안의 스위치는 아무도 찾지 못한다. 대신 방금 ▶를 누른 자리에서 묻는다 —
  /// 이 기능이 무엇을 해주는지 설명할 필요가 없는 유일한 순간이라, 여기서 물으면
  /// 기능 소개가 아니라 지금 상황에 대한 제안이 된다.
  ///
  /// 답이 무엇이든 다시 묻지 않는다. 두 번 권하면 그때부터는 재촉이다. 물어본
  /// 표시는 대화 쪽과 같은 키를 쓰므로, 한쪽에서 거절하면 다른 쪽도 조용해진다.
  Future<void> _maybeOfferOngoingNudge() async {
    if (!OngoingTaskNudgeService.isSupported) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(OngoingTaskNudgeService.offerShownKey) == true) return;

    if (await OngoingTaskNudgeService.isEnabled()) {
      // 아이폰은 처음부터 켜져 있다. 물어볼 것은 없지만, 시스템에서 실시간
      // 활동이 꺼져 있으면 켜져 있어도 아무것도 뜨지 않는다. 그 한 가지만
      // 짚어준다 — 켜졌다고 적힌 채 영영 안 뜨는 게 제일 나쁘다.
      //
      // 다이내믹 아일랜드가 없는 기종은 라이브 액티비티를 쓰지 않는다. 배너가
      // 대신하므로 실시간 활동을 켜달라고 할 이유가 없다.
      if (_onAndroid) return;
      if (!await OngoingTaskNudgeService.showsOverOtherApps()) return;
      if (await OngoingTaskNudgeService.isAvailable()) return;
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return;
      await prefs.setBool(OngoingTaskNudgeService.offerShownKey, true);
      final tapped = await _showOngoingNudgeNotice(
        title: '🐾 실시간 활동을 켜주세요',
        message:
            '일정이 도는 동안 잠금화면에 냥냥이가 조용히 남아 있게 하려면 '
            '실시간 활동이 필요해요.\n'
            '설정에서 냥냥코치를 찾아 켜주세요.',
        actionLabel: '설정 열기',
      );
      if (tapped) await OngoingTaskNudgeService.openSystemSettings();
      return;
    }

    // 누르자마자 팝업이 튀어나오면 놀란다. 카드가 진행 중으로 바뀌는 것과
    // 밀어보기 시늉이 끝난 뒤에 뜬다.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    await prefs.setBool(OngoingTaskNudgeService.offerShownKey, true);
    unawaited(AnalyticsService.logFeatureUsage('ongoing_nudge_offer'));

    final accepted = await _showOngoingNudgeOfferDialog();
    if (accepted != true) {
      unawaited(AnalyticsService.logFeatureUsage('ongoing_nudge_offer_no'));
      return;
    }

    unawaited(AnalyticsService.logFeatureUsage('ongoing_nudge_offer_yes'));
    await OngoingTaskNudgeService.setEnabled(true);
    // 방금 시작한 일정을 바로 맡긴다. 다음 저장까지 기다리면 첫 일정만 빈다.
    await _syncOngoingNudge();

    if (_onAndroid) {
      // 여기가 가장 먼저, 가장 확실히 뜨는 자리다. 나올지(오버레이)와
      // 제시간에 나올지(정확한 알람)는 서로 다른 권한이라, 오버레이만 받고
      // 정확한 알람 쪽을 놓치면 나중에 아무 말 없이 늦게 뜨는 채로 남는다.
      // 두 개 다 여기서 한 번에 물어본다.
      final needsOverlay = !await OngoingTaskNudgeService.isAvailable();
      final needsExactAlarm =
          !await NotificationService().canScheduleExactAlarms();
      if (!mounted) return;
      if (needsOverlay || needsExactAlarm) {
        final title = needsOverlay && needsExactAlarm
            ? '🐾 두 가지만 켜주세요'
            : '🐾 한 가지만 켜주세요';
        final message = switch ((needsOverlay, needsExactAlarm)) {
          (true, true) =>
            '설정에서 냥냥코치를 찾아 "다른 앱 위에 표시"와 "알람 및 리마인더"를 '
                '함께 켜주세요.\n'
                '하나는 냥냥이가 나오게, 하나는 정해진 시간에 정확히 나오게 해줘요.',
          (true, false) =>
            '설정에서 냥냥코치를 찾아 "다른 앱 위에 표시"를 켜주세요.\n'
                '이게 없으면 냥냥이가 다른 앱 위로 나올 수 없어요.',
          (false, true) =>
            '설정에서 "알람 및 리마인더"를 허용해주세요.\n'
                '이게 없으면 냥냥이가 정해진 시간보다 늦게 나올 수 있어요.',
          (false, false) => '',
        };
        final tapped = await _showOngoingNudgeNotice(
          title: title,
          message: message,
          actionLabel: '설정 열기',
        );
        if (tapped) {
          if (needsOverlay) await OngoingTaskNudgeService.openSystemSettings();
          if (needsExactAlarm) {
            await NotificationService().openAlarmPermissionSettings(
              AlarmPermissionIssue.exactAlarm,
            );
          }
        }
        return;
      }
    } else {
      final needsLiveActivity = await OngoingTaskNudgeService.showsOverOtherApps();
      final available =
          !needsLiveActivity || await OngoingTaskNudgeService.isAvailable();
      if (!mounted) return;
      if (!available) {
        // 권한이 없으면 켜도 아무것도 나오지 않는다. 설정으로 데려다준다.
        final tapped = await _showOngoingNudgeNotice(
          title: '🐾 실시간 활동을 켜주세요',
          message:
              '설정에서 냥냥코치를 찾아 "실시간 활동"을 켜주세요.\n'
              '이게 꺼져 있으면 잠금화면에 아무것도 뜨지 않아요.',
          actionLabel: '설정 열기',
        );
        if (tapped) await OngoingTaskNudgeService.openSystemSettings();
        return;
      }
    }

    // 알림이 꺼져 있으면 냥냥이는 나올 수 없다(안드로이드는 조용한 한 줄이
    // 함께 있어야 하고, 아이폰 배너는 알림 그 자체다). 켜졌다고 해놓고 아무것도
    // 오지 않는 상태로 두지 않는다.
    if (!await NotificationService().areNotificationsEnabled()) {
      if (!mounted) return;
      final tapped = await _showOngoingNudgeNotice(
        title: '🔔 알림도 켜주세요',
        message:
            '냥냥코치 알림이 꺼져 있어서, 지금은 냥냥이가 나올 수 없어요.\n'
            '설정에서 켜주시면 바로 챙겨드릴게요.',
        actionLabel: '설정 열기',
      );
      if (tapped) await OngoingTaskNudgeService.openSystemSettings();
      return;
    }

    // 아이폰은 기종에 따라 하는 일이 다르다. 다이내믹 아일랜드가 없으면 딴짓
    // 중에는 보이지 않으니, 막아준다고 말하면 지키지 못할 약속이 된다.
    final overOtherApps = await OngoingTaskNudgeService.showsOverOtherApps();
    // 아이폰은 배너로 찾아가는데, 몇 초 뒤 사라지는지는 앱이 아니라 배너
    // 스타일 설정이 정한다. 여기서 같이 안 물어보면, 딴짓 방지 스위치를
    // 켠 사람 중 설정 화면을 따로 열어보지 않는 사람은 이 얘기를 영영 못 듣는다.
    final needsPersistentBanner =
        !_onAndroid && !await OngoingTaskNudgeService.isBannerPersistent();
    if (!mounted) return;

    final tapped = await _showOngoingNudgeNotice(
      title: '🐾 이제 챙겨줄게요',
      message:
          (_onAndroid
              ? '30분쯤 지나서 폰으로 다른 걸 보고 있으면 화면 가장자리에 잠깐 나타나요.\n'
                    '소리도 진동도 없으니 그냥 둬도 돼요.'
              : overOtherApps
              ? '일정이 도는 동안 다른 앱을 봐도 화면 맨 위에 냥냥이가 작게 남아 있어요.\n'
                    '완료하거나 멈추면 사라져요.'
              : '일정이 도는 동안 잠금화면에 조용히 남아 있어요.\n'
                    '이 아이폰은 다른 앱 위에는 띄울 수 없어서, 폰을 집어 들 때 보여요.') +
          (needsPersistentBanner
              ? '\n\n배너가 금방 사라지지 않게 하려면 배너 스타일을 "지속"으로 바꿔주세요.'
              : ''),
      actionLabel: needsPersistentBanner ? '배너 설정 열기' : '확인',
    );
    if (needsPersistentBanner && tapped) {
      await OngoingTaskNudgeService.openNotificationSettings();
    }
  }

  bool get _onAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// 코치마다 자기 말로 묻는다. 앱 안에서 말을 거는 건 늘 이 사람이기 때문이다.
  String get _ongoingNudgeOfferText {
    switch (widget.coachId) {
      case 'nyang_halbae':
        return '자네, 시작해두고 딴 데로 새는 날이 있지냥.\n'
            '앱 밖에 있을 때도 부담 안 되게 슬쩍 챙겨줄까냥?';
      case 'sec_female':
        return '시작해두고 다른 데로 새는 날이 있으시죠.\n'
            '앱 밖에 계실 때도 부담 없이 살짝 챙겨드릴까요?';
      case 'boyfriend':
        return '시작해놓고 딴 데 새는 날 있잖아.\n'
            '앱 밖에 있을 때도 부담 안 주게 살짝 챙겨줄까?';
      case 'halmae':
        return '시작해놓고 딴 데로 새는 날 있제?\n'
            '앱 밖에 있을 때도 부담 없이 슬쩍 챙겨줄까잉?';
      case 'bro':
        return '시작해놓고 딴 데 새는 날 있지?\n'
            '앱 밖에 있을 때도 부담 안 주게 살짝 챙겨줄까?';
      default:
        return '집사, 일 시작해두고 딴 데 새는 날 있지냥?\n'
            '앱 밖에 있을 때도 부담 안 주게 살짝 챙겨줄까냥?';
    }
  }

  Future<bool?> _showOngoingNudgeOfferDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '🐾 딴짓 방지 코치',
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3D3A4E),
          ),
        ),
        content: Text(
          _ongoingNudgeOfferText,
          style: GoogleFonts.notoSansKr(
            fontSize: 13.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B6676),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              '괜찮아',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF9B96A8),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B7CFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '좋아, 챙겨줘',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 버튼을 눌러야만 닫히고, 그때만 true를 돌려준다.
  ///
  /// 바깥을 눌러 닫는 것도 기본값으로는 닫힘으로 쳐서, 호출한 쪽이 "닫혔으니
  /// 설정으로 보내자"라고 무조건 이어가면 거절하려고 바깥을 누른 사람까지
  /// 시스템 설정으로 끌려간다. 그래서 여기서는 바깥 탭을 막고, 버튼을 눌렀을
  /// 때만 true를 돌려준다 — 다음 동작은 호출한 쪽이 그 값을 보고 정한다.
  Future<bool> _showOngoingNudgeNotice({
    required String title,
    required String message,
    String actionLabel = '확인',
  }) async {
    final tapped = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3D3A4E),
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.notoSansKr(
            fontSize: 13.5,
            height: 1.55,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B6676),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B7CFF),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              actionLabel,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
    return tapped ?? false;
  }

  /// 앱 밖에서 데이터가 바뀌었으면 다시 읽는다.
  ///
  /// 냥냥이 카드로 고른 답은 [TaskCompletionService]가 저장소에 바로 반영한다.
  /// 이 화면은 그 사실을 모른 채 열려 있을 수 있는데, 그대로 두면 메모리에 든
  /// 옛 목록을 다음 저장 때 덮어써서 방금 한 완료가 사라진다.
  Future<void> _reloadIfStoreChanged() async {
    if (await TaskCompletionService.changedSince(_lastStoreLoadAt)) {
      await _loadAll();
      if (mounted) _syncTaskTicker();
    }
  }

  /// 저장소의 날짜별 계획을 메모리로 다시 읽는다.
  /// 자정 정리가 어제 목록을 보관함에 넣은 직후처럼, 저장소만 바뀐 경우에 쓴다.
  Future<void> _loadPlannedTodayTasks(SharedPreferences prefs) async {
    final raw = prefs.getString(DailyResetService.plannedTasksByDateKey);
    if (raw == null || raw.isEmpty) {
      plannedTodayTasksByDate = {};
      return;
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      plannedTodayTasksByDate = decoded.map(
        (key, value) => MapEntry(
          key,
          (value as List).map((e) => TaskItem.fromJson(e)).toList(),
        ),
      );
    } catch (_) {}
  }

  Future<void> _savePlannedTodayTasks() async {
    final prefs = await SharedPreferences.getInstance();
    // 이 화면이 표를 읽어둔 사이에 자정 정리가 저장소에만 어제 목록을 넣어둘 수
    // 있다. 그대로 덮으면 방금 보관된 어제가 사라지므로, 저장 직전에 다시 본다.
    await prefs.reload();

    final encoded = <String, dynamic>{};
    plannedTodayTasksByDate.forEach((key, value) {
      if (value.isNotEmpty) {
        encoded[key] = value.map((t) => t.toJson()).toList();
      }
    });

    Map<String, dynamic> stored = {};
    try {
      final raw = prefs.getString(DailyResetService.plannedTasksByDateKey);
      if (raw != null && raw.isNotEmpty) {
        stored = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}

    final merged = DailyResetService.mergePlannedTasksForSave(
      stored: stored,
      encoded: encoded,
      knownKeys: plannedTodayTasksByDate.keys.toSet(),
    );

    // 저장소에만 있던 날짜는 화면도 알고 있어야 한다. 그래야 어제를 열었을 때
    // 다시 읽지 않고도 목록이 보인다.
    merged.forEach((key, value) {
      if (plannedTodayTasksByDate.containsKey(key)) return;
      try {
        plannedTodayTasksByDate[key] = (value as List)
            .map((e) => TaskItem.fromJson(e))
            .toList();
      } catch (_) {}
    });

    await prefs.setString(
      DailyResetService.plannedTasksByDateKey,
      jsonEncode(merged),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 미리 세워둔 계획 중 날짜가 오늘이 된 것은 오늘 할 일로 승격하고,
  /// 너무 오래된 날짜의 계획은 정리한다. 지난 며칠은 남긴다 —
  /// 뒤늦게 도착한 완료 표시를 채울 자리다.
  Future<void> _promoteAndPrunePlannedTasks() async {
    final todayKey = _getTodayStr();

    final promoted = plannedTodayTasksByDate.remove(todayKey);
    final staleKeys = plannedTodayTasksByDate.keys
        .where((key) => _dateFromKey(key).isBefore(_archiveFloorDate))
        .toList();
    for (final key in staleKeys) {
      plannedTodayTasksByDate.remove(key);
    }
    if (promoted == null && staleKeys.isEmpty) return;

    if (promoted != null) {
      final existingIds = tasks.map((t) => t.id.toString()).toSet();
      for (final task in promoted) {
        if (existingIds.add(task.id.toString())) tasks.add(task);
      }
    }
    if (mounted) setState(() {});

    await _savePlannedTodayTasks();
    if (promoted != null && promoted.isNotEmpty) {
      await _persistTodayTasks();
    }
  }

  Future<void> _saveTodayRecord() async {
    final prefs = await SharedPreferences.getInstance();
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      history = List<Map<String, dynamic>>.from(jsonDecode(rawHistory));
    }

    final todayStr = _getTodayStr();
    final countableTasks = tasks.where(_countsTowardDailyCompletion).toList();
    final doneTasks = countableTasks.where((t) => t.done).toList();
    final todayMilestones = _todayMilestoneItems;
    final doneMilestones = todayMilestones.where((m) => m.done).toList();

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
          'inProgress': t.inProgress,
          if (t.inProgressAt != null) 'startedAt': t.inProgressAt,
          if (t.completedAt != null) 'completedAt': t.completedAt,
          'category': t.category,
          'deferred': false,
        },
      ),
      ...todayMilestones.map(
        (m) => {
          'text': m.text,
          'done': m.done,
          'category': 'milestone',
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
      'totalCount': countableTasks.length + todayMilestones.length,
      'doneCount': doneTasks.length + doneMilestones.length,
      'success': doneTasks.isNotEmpty || doneMilestones.isNotEmpty,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': mergedTasks,
    };

    final idx = history.indexWhere((h) => h['date'] == todayStr);
    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
    }

    // Keep last 30 days of raw task history.
    history.sort((a, b) => a['date'].compareTo(b['date']));
    if (history.length > 30) history = history.sublist(history.length - 30);

    await prefs.setString('nyang_history', jsonEncode(history));
  }

  /// 지난 날 화면에서 바뀐 완료 표시를 그날 기록에 다시 쓴다.
  ///
  /// 기록 탭과 코치가 보는 "연속 달성"은 이 기록에서 바로 계산되므로,
  /// 여기만 고치면 깜빡했던 하루가 제자리를 찾는다. 자정에 정리되어 목록에는
  /// 없는 이월 항목은 기록에 있던 그대로 둔다.
  Future<void> _saveRecordForPastDate(String dateKey) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> history = [];
    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory != null) {
      try {
        history = List<Map<String, dynamic>>.from(jsonDecode(rawHistory));
      } catch (_) {}
    }

    final idx = history.indexWhere((h) => h['date'] == dateKey);
    final previous = idx >= 0 ? history[idx] : <String, dynamic>{};

    final dayTasks = plannedTodayTasksByDate[dateKey] ?? <TaskItem>[];
    final countableTasks = dayTasks
        .where(_countsTowardDailyCompletion)
        .toList();
    final doneTasks = countableTasks.where((t) => t.done).toList();
    final dayMilestones = _todayMilestoneItems;
    final doneMilestones = dayMilestones.where((m) => m.done).toList();

    final listEntries = <Map<String, dynamic>>[
      ...dayTasks.map(
        (t) => {
          'text': t.text,
          'done': t.done,
          'inProgress': t.inProgress,
          if (t.inProgressAt != null) 'startedAt': t.inProgressAt,
          if (t.completedAt != null) 'completedAt': t.completedAt,
          'category': t.category,
          'deferred': false,
        },
      ),
      ...dayMilestones.map(
        (m) => {
          'text': m.text,
          'done': m.done,
          'category': 'milestone',
          'deferred': false,
        },
      ),
    ];

    // 지난 날 기록은 줄어들 수 없다.
    //
    // 여기 쓰는 목록은 자정에 남겨둔 보관본이라 어떤 이유로든 모자랄 수 있는데,
    // 그것으로 기록을 통째로 덮으면 그날 해낸 것이 사라진다. 실제로 하루치가
    // 0이 된 적이 있다. 목록에 없는 옛 항목은 그대로 남긴다.
    final kept = TaskCompletionService.preservedRecordEntries(
      previous: ((previous['tasks'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      fromList: listEntries,
    );
    // 이월 항목은 그날 계획이 아니라 넘어온 것이라 분모에 넣지 않는다.
    final countedKept = kept
        .where((entry) => entry['deferred'] != true)
        .toList(growable: false);
    final keptDone = countedKept.where((entry) => entry['done'] == true).length;

    final record = {
      'date': dateKey,
      'totalCount':
          countableTasks.length + dayMilestones.length + countedKept.length,
      'doneCount': doneTasks.length + doneMilestones.length + keptDone,
      'success':
          doneTasks.isNotEmpty || doneMilestones.isNotEmpty || keptDone > 0,
      'isVacation': previous['isVacation'] ?? false,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': [...listEntries, ...kept],
    };

    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
      history.sort((a, b) => a['date'].compareTo(b['date']));
    }
    await prefs.setString('nyang_history', jsonEncode(history));

    // 연속 달성은 어제까지 이어진 줄로 센다. 그보다 앞선 날을 고쳐도
    // 저장된 숫자는 어제를 기준으로 다시 확인하면 된다.
    await _syncStreakWithHistory(prefs, history);
    widget.onProgressChanged?.call();
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 어제 기록이 바뀌면 저장된 연속 일수도 다시 본다.
  ///
  /// 어제가 빈 하루로 남으면 연속은 끊긴 것이고, 하나라도 해냈으면 기록을
  /// 거슬러 올라가 다시 센다. 기록은 30일치만 남기 때문에 세어본 값이 저장된
  /// 값보다 작게 나올 수 있는데, 그때는 저장된 값을 믿는다.
  Future<void> _syncStreakWithHistory(
    SharedPreferences prefs,
    List<Map<String, dynamic>> history,
  ) async {
    final byDate = {for (final h in history) h['date'].toString(): h};
    bool succeeded(String key) {
      final record = byDate[key];
      if (record == null) return false;
      return record['success'] == true || record['isVacation'] == true;
    }

    final stored = prefs.getInt('nyang_streak') ?? 0;
    if (!succeeded(_yesterdayKey)) {
      if (stored != 0) await prefs.setInt('nyang_streak', 0);
      return;
    }

    var counted = 0;
    var cursor = _yesterdayDate;
    while (succeeded(_dateKey(cursor))) {
      counted++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    if (counted > stored) await prefs.setInt('nyang_streak', counted);
  }

  Future<void> _saveCoreTasks() async {
    _syncTodayMilestonesIntoCoreTasks();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_core_tasks',
      jsonEncode(coreTasks.map((t) => t.toJson()).toList()),
    );
    NotificationService().syncCoreReminders();
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 휴식 모드를 저장한다.
  ///
  /// 어떤 종류로 쉬는지까지 남긴다. 하루만 멈추는 것과 매주 무슨 요일마다 쉬는
  /// 것은 쓰는 사람도 쓰는 이유도 달라서, 하나로 세면 어느 쪽이 쓰이는지 알 수 없다.
  /// 채팅에서 말로 등록하는 주간·월간 목표.
  ///
  /// 장기 비전은 마일스톤과 기한이 함께 있어야 뜻이 서기 때문에 여기로 받지
  /// 않는다. 비전은 목표 탭에서 직접 만든다.
  Future<bool> _addGoalFromChat(String type, String text) async {
    if (!await _canInputTasks()) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (type != 'week' && type != 'month') return false;

    final goal = GoalItem(
      id:
          DateTime.now().millisecondsSinceEpoch +
          DateTime.now().microsecond % 1000,
      text: trimmed,
    );
    setState(() {
      if (type == 'week') {
        weekGoals.add(goal);
      } else {
        monthGoals.add(goal);
      }
    });
    await _saveGoals(type);
    return true;
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
    if (!await _canInputTasks()) return;
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
    final coreChanged = _syncTodayMilestonesIntoCoreTasks();
    if (coreChanged) await _saveCoreTasks();
    TasksSyncService.scheduleSyncToCloud();
    await WidgetSyncService.syncFromStoredTasks();
    widget.onProgressChanged?.call();
  }

  String _formatAchievedDate([DateTime? value]) {
    final date = value ?? DateTime.now();
    return "${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}";
  }

  bool _setMilestoneCompletion(
    MilestoneItem milestone,
    bool isDone, {
    DateTime? completedAt,
  }) {
    final changed = milestone.done != isDone;
    milestone.done = isDone;
    milestone.achievedDate = isDone ? _formatAchievedDate(completedAt) : null;
    return changed;
  }

  Future<void> _saveSchedules() async {
    final hasActivePlan = await _hasActivePlan();
    if (!hasActivePlan) {
      schedules.forEach((_, items) {
        for (final item in items) {
          item.isReminderEnabled = false;
        }
      });
      _schReminderEnabled = false;
      _todayReminderEnabled = false;
    }
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> toEncode = {};
    schedules.forEach((k, v) {
      if (v.isNotEmpty) toEncode[k] = v.map((e) => e.toJson()).toList();
    });
    await prefs.setString('nyang_schedules', jsonEncode(toEncode));
    TasksSyncService.scheduleSyncToCloud();

    // 일정 변경 시 오늘의 할 일 탭에도 즉시 반영
    _injectTodaySchedules();
    await NotificationService().syncCoreReminders();
    widget.onProgressChanged?.call();
    // 애플 캘린더 연동(iOS)이 켜져 있으면 변경을 미러링. 실패해도 앱 흐름엔 영향 없음.
    unawaited(
      AppleCalendarSyncService.instance.syncAll(pullExternalChanges: false),
    );
  }

  Future<bool> _hasActivePlan() async {
    final userData = await UserDataService.load();
    return userData.isPlanActive;
  }

  /// 적어 넣을 수 있는지. 플랜이 있으면 언제든 되고, 없으면 무료로 열린
  /// 며칠 동안만 된다. 알림처럼 돈이 드는 기능은 여기에 딸려오지 않는다.
  Future<bool> _canInputTasks() async {
    if (await _hasActivePlan()) return true;
    return FreeAccessService.instance.canInput();
  }

  Future<bool> _ensurePlanForTaskInput() async {
    if (await _canInputTasks()) return true;
    if (mounted) _showSubscriptionNotice(context);
    return false;
  }

  Future<void> _saveHabitLogs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_habit_logs', jsonEncode(habitLogs));
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 시작 시각을 못 믿을 때 대신 쓸 값. 완료 30분 전으로 잡되 그날을 넘지 않는다.
  String _fallbackStartedAt(DateTime completedAt) {
    final fallback = completedAt.subtract(const Duration(minutes: 30));
    final dayStart = DateTime(
      completedAt.year,
      completedAt.month,
      completedAt.day,
    );
    return (fallback.isBefore(dayStart) ? dayStart : fallback)
        .toIso8601String();
  }

  /// 기록에 남길 시작 시각.
  ///
  /// 누르자마자 완료한 건 진짜 시작이 아니다. 시작 버튼을 거치지 않고 체크만
  /// 한 경우와 다를 게 없어서, 1분도 안 걸린 시각은 버리고 대신 값을 넣는다.
  ///
  /// 원래 습관에만 걸던 방어막인데 일반 할 일에도 건다. 하루 시작 패턴이 그날
  /// 가장 이른 시작 시각을 쓰기 때문에, 심심해서 눌러본 한 번이 그날 전체의
  /// 시작으로 잡히면 없는 리듬을 만들어 낸다.
  String? _startedAtForCompletion({
    required String? currentStartedAt,
    required DateTime completedAt,
  }) {
    if (currentStartedAt == null) return _fallbackStartedAt(completedAt);
    final parsedStartedAt = DateTime.tryParse(currentStartedAt);
    if (parsedStartedAt == null) return _fallbackStartedAt(completedAt);
    final elapsed = completedAt.difference(parsedStartedAt).abs();
    if (elapsed < const Duration(minutes: 1)) {
      return _fallbackStartedAt(completedAt);
    }
    return currentStartedAt;
  }

  /// 완료를 되돌리기 전에 한 번 묻는다.
  ///
  /// 시작과 완료는 하루에도 여러 번 누르는 동작이라 한 번 터치 그대로 둔다.
  /// 되돌리기만 막는 건 실수로 눌렸을 때 잃는 게 있어서다 — 완료 표시뿐 아니라
  /// 완료 시각과 시작 시각이 함께 지워지고, 습관이면 그날 기록도 빠진다.
  ///
  /// 삭제와 달리 되돌릴 수 있는 일이라 빨간색을 쓰지 않는다. 방금 누른 체크
  /// 버튼과 같은 코치 색을 써서 무엇에 대한 확인인지 눈으로 이어지게 한다.
  Future<bool> _confirmUncomplete() async {
    final confirmed = await _showConfirmDialog(
      '완료를 취소할까요?',
      '',
      confirmLabel: '완료 취소',
      confirmColor: _coach.accentColor,
    );
    return mounted && confirmed;
  }

  // ── getTodayStr ───────────────────────────────────────────
  String _getTodayStr() {
    final n = DateTime.now();
    final base = DateTime(n.year, n.month, n.day);
    return '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
  }

  DateTime _dateFromKey(String key) {
    final parts = key.split('-');
    if (parts.length < 3) return DateTime.now();
    return DateTime(
      int.tryParse(parts[0]) ?? DateTime.now().year,
      int.tryParse(parts[1]) ?? DateTime.now().month,
      int.tryParse(parts[2]) ?? DateTime.now().day,
    );
  }

  DateTime get _activeTodayDate =>
      _selectedTodayDate ?? _dateFromKey(_getTodayStr());

  String get _activeTodayDateKey => _dateKey(_activeTodayDate);

  bool get _isViewingActualToday => _activeTodayDateKey == _getTodayStr();

  DateTime get _yesterdayDate =>
      _dateFromKey(_getTodayStr()).subtract(const Duration(days: 1));

  String get _yesterdayKey => _dateKey(_yesterdayDate);

  /// 어제까지는 열어둔다. 전날 완료 표시를 깜빡했거나 자정을 넘겨 끝낸 일이 있다.
  bool get _isViewingYesterday => _activeTodayDateKey == _yesterdayKey;

  /// 목록을 아직 들고 있는 지난 날의 첫날.
  ///
  /// 달력으로 직접 열 수 있는 건 어제까지지만, 그보다 앞선 며칠도 자리는 남아 있다.
  /// 뒤늦게 도착한 완료 표시를 채워 넣을 때 쓴다.
  DateTime get _archiveFloorDate => _dateFromKey(
    _getTodayStr(),
  ).subtract(const Duration(days: DailyResetService.archivedPastDays));

  bool get _isViewingArchivedPastDate =>
      !_isViewingActualToday &&
      _activeTodayDate.isBefore(_dateFromKey(_getTodayStr())) &&
      !_activeTodayDate.isBefore(_archiveFloorDate);

  /// 습관 도장은 지나간 날에도 찍을 수 있다. 목록이 남아 있는 날까지만, 미래에는 찍지 않는다.
  bool get _canWriteHabitLogForActiveDate =>
      _isViewingActualToday || _isViewingArchivedPastDate;

  bool get _isViewingPastDate => _activeTodayDate.isBefore(_yesterdayDate);

  List<TaskItem> get _activeTodayTasks {
    if (_isViewingActualToday) return tasks;
    return plannedTodayTasksByDate.putIfAbsent(_activeTodayDateKey, () => []);
  }

  List<TaskItem> _plannedTodayTasksForDate(DateTime day) {
    final key = _dateKey(day);
    final source = key == _getTodayStr()
        ? tasks
        : (plannedTodayTasksByDate[key] ?? <TaskItem>[]);
    return source.where((task) => task.category == 'today').toList();
  }

  List<TaskItem> _todayTaskStoreForDateKey(String dateKey) {
    return dateKey == _getTodayStr()
        ? tasks
        : plannedTodayTasksByDate.putIfAbsent(dateKey, () => []);
  }

  void _syncCoreTaskFromTask(TaskItem task) {
    final coreIndex = coreTasks.indexWhere(
      (coreTask) => coreTask.id.toString() == task.id.toString(),
    );
    if (coreIndex != -1) {
      _copyTaskEdits(coreTasks[coreIndex], task);
      coreTasks[coreIndex].done = task.done;
      coreTasks[coreIndex].completedAt = task.completedAt;
      coreTasks[coreIndex].inProgress = task.inProgress;
      coreTasks[coreIndex].inProgressAt = task.inProgressAt;
    } else if (task.isReminderEnabled) {
      coreTasks.add(task);
    }
  }

  Future<void> _saveScheduleTabTaskEdit(String dateKey, TaskItem task) async {
    setState(() {
      final store = _todayTaskStoreForDateKey(dateKey);
      final index = store.indexWhere(
        (item) => item.id.toString() == task.id.toString(),
      );
      if (index != -1) {
        _copyTaskEdits(store[index], task);
        store[index].done = task.done;
        store[index].completedAt = task.completedAt;
        store[index].inProgress = task.inProgress;
        store[index].inProgressAt = task.inProgressAt;
      }
      _syncCoreTaskFromTask(task);
    });

    if (dateKey == _getTodayStr()) {
      await _persistTodayTasks();
      await _saveCoreTasks();
    } else {
      await _savePlannedTodayTasks();
      await _saveCoreTasks();
    }
  }

  Future<void> _deleteScheduleTabTask(String dateKey, TaskItem task) async {
    setState(() {
      final store = _todayTaskStoreForDateKey(dateKey);
      store.removeWhere((item) => item.id.toString() == task.id.toString());
      if (dateKey != _getTodayStr() && store.isEmpty) {
        plannedTodayTasksByDate.remove(dateKey);
      }
      coreTasks.removeWhere(
        (coreTask) => coreTask.id.toString() == task.id.toString(),
      );
    });

    if (dateKey == _getTodayStr()) {
      await _persistTodayTasks();
      await _saveCoreTasks();
    } else {
      await _savePlannedTodayTasks();
      await _saveCoreTasks();
    }
  }

  List<TaskItem> _scheduleTaskItemsForDate(String dateKey) {
    return (schedules[dateKey] ?? []).map((schedule) {
      return TaskItem(
        id: 'schedule_${schedule.id}',
        text: schedule.text,
        category: 'schedule',
        done: schedule.done,
        time: schedule.time,
        duration: schedule.duration,
        timeStart: schedule.timeStart,
        timeEnd: schedule.timeEnd,
        createdAt: schedule.createdAt,
        isReminderEnabled: schedule.isReminderEnabled,
        deferredCount: schedule.deferredCount,
        memo: schedule.memo,
      );
    }).toList();
  }

  bool _isInsightTask(TaskItem task) =>
      task.source == 'insight' || _hasNyangInsightMarker(task.text);

  bool _hasNyangInsightMarker(String text) {
    return RegExp(
      r'[\(\[]\s*냥\s*인사이트\s*[\)\]]',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String _cleanInsightTaskTitle(String text) {
    return text
        .replaceAll(
          RegExp(r'[\(\[]\s*냥\s*인사이트\s*[\)\]]', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<TaskItem> get _activeTodayTasksWithSchedules {
    final currentTasks = List<TaskItem>.from(_activeTodayTasks);
    final currentIds = currentTasks.map((t) => t.id.toString()).toSet();
    for (final scheduleTask in _scheduleTaskItemsForDate(_activeTodayDateKey)) {
      if (currentIds.add(scheduleTask.id.toString())) {
        currentTasks.add(scheduleTask);
      }
    }
    return currentTasks;
  }

  bool _hasScheduleTabEvents(DateTime day) {
    final key = _dateKey(day);
    return (schedules[key]?.isNotEmpty ?? false) ||
        _plannedTodayTasksForDate(day).isNotEmpty;
  }

  void _resetTodayDateSelection() {
    if (!mounted) return;
    if (_selectedTodayDate == null) return;
    setState(() => _selectedTodayDate = null);
  }

  // ── injectTodayHabits (웹앱 그대로) ──────────────────────
  void _injectTodayHabits() {
    final today = _getTodayStr();
    final parts = today.split('-');
    int todayDow = DateTime.now().weekday;
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final d = int.tryParse(parts[2]) ?? DateTime.now().day;
      todayDow = DateTime(y, m, d).weekday;
    }
    // 웹앱 dbDow: 0=월~6=일
    final dbDow = todayDow - 1;

    final todayHabits = habits.where((h) {
      if (h.freq == 'daily') return true;
      if (h.freq == 'weekly_count') {
        return _shouldShowWeeklyCountHabitOnDate(h, DateTime.now());
      }
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
      String? tTime;
      if (h.timeType == 'single' && h.timeStart != null) {
        tTime = _displayTimeFromStored(timeStart: h.timeStart);
      }
      if (h.timeType == 'range' && h.timeStart != null) {
        tTime = _displayTimeFromStored(
          timeStart: h.timeStart,
          timeEnd: h.timeEnd,
        );
      }

      final existingIndex = tasks.indexWhere(
        (t) => t.habitId?.toString() == h.id.toString(),
      );
      if (existingIndex != -1) {
        // 습관 이름/시간이 수정됐을 수 있으니 오늘 이미 주입된 항목에도 반영한다.
        tasks[existingIndex].text = h.name;
        tasks[existingIndex].time = tTime;
        tasks[existingIndex].duration = h.habitDuration;
        tasks[existingIndex].timeStart = h.timeStart;
        tasks[existingIndex].timeEnd = h.timeEnd;
        continue;
      }

      final log = (habitLogs[h.id.toString()] ?? {})[today];
      final isSkipped = log != null && log['status'] == 'skipped';
      if (isSkipped) continue;

      final isDone = log != null && log['done'] == true;

      final taskId = 'habit_${h.id.toString().replaceAll('.', '_')}_$today';

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
          inProgressAt: isDone ? log!['startedAt'] as String? : null,
        ),
      );
    }

    setState(() {});
    _saveTasks();
  }

  DateTime? _createdDateOfHabit(HabitItem habit) =>
      RoutineSchedule.createdDate(habit.createdAt);

  int _weeklyTargetForHabit(HabitItem habit) =>
      RoutineSchedule.weeklyTarget(habit.weeklyTargetCount);

  int _weeklyVisibleTargetForDate(HabitItem habit, DateTime date) {
    return RoutineSchedule.visibleWeeklyTarget(
      target: _weeklyTargetForHabit(habit),
      createdDate: _createdDateOfHabit(habit),
      date: date,
    );
  }

  String _habitTaskBadgeLabel(TaskItem task) {
    if (task.habitId == null) return '루틴';
    final habitIndex = habits.indexWhere(
      (h) => h.id.toString() == task.habitId.toString(),
    );
    if (habitIndex < 0) return '루틴';

    final habit = habits[habitIndex];
    if (habit.freq != 'weekly_count') return '루틴';

    final today = DateTime.now();
    final target = _weeklyTargetForHabit(habit);
    final logs = habitLogs[habit.id.toString()] ?? {};
    // 배지는 오늘까지 포함해 센다. 목록에 올릴지 정할 때(어제까지)와 세는
    // 범위가 다르다 — 이쪽은 "오늘 이걸 하면 몇 번째"를 보여주는 자리다.
    final doneCount = RoutineSchedule.doneCount(
      logs: logs,
      createdDate: _createdDateOfHabit(habit),
      date: today,
      includeDate: true,
    );

    final todayDone = RoutineSchedule.isDoneOn(logs, today) || task.done;
    final displayCount = todayDone ? doneCount : doneCount + 1;
    final roundedDisplayCount = displayCount.round();
    final safeDisplayCount = roundedDisplayCount < 1
        ? 1
        : (roundedDisplayCount > target ? target : roundedDisplayCount);
    return '루틴 $safeDisplayCount/$target';
  }

  bool _countsTowardDailyCompletion(TaskItem task) {
    if (task.habitId == null) return true;
    final habitIndex = habits.indexWhere(
      (h) => h.id.toString() == task.habitId.toString(),
    );
    if (habitIndex < 0) return true;
    final habit = habits[habitIndex];
    return habit.freq != 'weekly_count' || task.done;
  }

  bool _shouldShowWeeklyCountHabitOnDate(HabitItem habit, DateTime date) {
    return RoutineSchedule.shouldShowWeeklyCountOnDate(
      rawWeeklyTargetCount: habit.weeklyTargetCount,
      rawCreatedAt: habit.createdAt,
      logs: habitLogs[habit.id.toString()] ?? const {},
      date: date,
    );
  }

  Future<({String label, double ratio})?> _pickHabitCompletionRatio(
    HabitItem habit,
  ) {
    final options = [
      (label: '조금 했어', ratio: 0.25),
      (label: '절반쯤 했어', ratio: 0.5),
      (label: '목표만큼 했어', ratio: 1.0),
    ];

    return showModalBottomSheet<({String label, double ratio})>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
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
                '오늘 얼마나 했나요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '정확하지 않아도 돼요. 준비, 정리, 수정처럼 이어지는 작업도 포함해도 돼요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFA0A0B0),
                ),
              ),
              const SizedBox(height: 12),
              ...options.map(
                (option) => GestureDetector(
                  onTap: () => Navigator.pop(ctx, option),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 13,
                    ),
                    decoration: BoxDecoration(
                      color: _coach.accentColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _coach.accentColor.withOpacity(0.18),
                      ),
                    ),
                    child: Text(
                      option.label,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _coach.accentColor,
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

  // ── injectTodaySchedules ──────────────────────────────
  void _injectTodaySchedules() {
    final today = _getTodayStr();
    final todaySchedules = schedules[today] ?? [];
    final todayScheduleIds = todaySchedules.map((s) => s.id).toList();

    // 오늘 날짜가 아니게 된 (혹은 삭제된) 일정 태스크 제거
    tasks.removeWhere((t) {
      if (t.category != 'schedule') return false;
      if (!t.id.toString().startsWith('schedule_')) return true;
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
        existingTask.memo = s.memo;

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
            coreTasks[coreIndex].memo = s.memo;
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
          memo: s.memo,
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
  Future<void> _addTodayTask(String text) async {
    if (!await _ensurePlanForTaskInput()) return;
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
      final effectiveTimeType = _effectiveClockTimeType(
        _todayTimeType,
        _todayEndTime,
      );
      if (effectiveTimeType == 'single' && _todayStartTime != null) {
        timeStr = _formatTime(_todayStartTime!);
        timeStartStr =
            '${_todayStartTime!.hour.toString().padLeft(2, '0')}:${_todayStartTime!.minute.toString().padLeft(2, '0')}';
      } else if (effectiveTimeType == 'range' && _todayStartTime != null) {
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
        effectiveTimeType,
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
      _activeTodayTasks.add(task);
      _todayTimeType = 'none';
      _todayReminderEnabled = false;
      _todayStartTime = null;
      _todayEndTime = null;
      _todayDuration = null;
      _showTodayTimeOptions = false;
    });
    _saveTasks();
    _todayInputCtrl.clear();

    // 방금 적은 계획을 두고 코치가 한 마디 건넬 자리인지 본다. 대개는 아무
    // 일도 일어나지 않는다 — 이틀에 한 번까지고, 짚을 것이 있는지는 코치가
    // 다시 판단한다.
    unawaited(
      PlanFeedbackService.onTaskSaved(
        coachId: widget.coachId,
        taskText: finalTitle,
        hasTime: timeStartStr != null,
      ),
    );
  }

  // ── toggleTask (웹앱 그대로) ──────────────────────────────
  /// 카드 왼쪽 버튼과 밀어서 완료가 함께 쓰는 자리.
  ///
  /// [forceComplete]는 밀어서 완료가 켠다. 타이머형 할 일에서는 왼쪽 버튼이
  /// 완료를 하지 않기 때문에, 완료로 곧장 가는 길이 따로 필요하다.
  /// 시트나 다이얼로그를 기다린 뒤 같은 할 일을 다시 잡는다.
  ///
  /// 기다리는 동안 클라우드 동기화가 목록을 통째로 새로 읽어오면 항목이 전부
  /// 새 객체로 갈린다. 그때까지 들고 있던 것은 화면에 없는 옛 객체라, 거기에
  /// 완료를 적으면 화면에도 저장에도 남지 않는다. 사라진 항목이면 null.
  TaskItem? _reacquireTask(TaskItem stale) {
    final latest = _activeTodayTasksWithSchedules;
    final idx = latest.indexWhere(
      (item) => item.id.toString() == stale.id.toString(),
    );
    return idx < 0 ? null : latest[idx];
  }

  Future<void> _toggleTask(dynamic id, {bool forceComplete = false}) async {
    if (id.toString().startsWith('milestone_')) {
      final idStr = id.toString();
      for (final v in visions) {
        for (final m in v.milestones) {
          final mId = _milestoneTaskId(v, m);
          if (mId == idStr) {
            if (m.done && !await _confirmUncomplete()) return;
            setState(() {
              _setMilestoneCompletion(m, !m.done);
            });
            _saveVisions();
            _saveTasks();
            break;
          }
        }
      }
      return;
    }

    final currentTasks = _activeTodayTasksWithSchedules;
    var t = currentTasks.firstWhere(
      (t) => t.id.toString() == id.toString(),
      orElse: () => currentTasks.first,
    );
    if (!_isViewingActualToday && t.category == 'schedule') {
      final scheduleId = t.id.toString().replaceAll('schedule_', '');
      final daySchedules = schedules[_activeTodayDateKey];
      final idx =
          daySchedules?.indexWhere((schedule) => schedule.id == scheduleId) ??
          -1;
      if (daySchedules == null || idx < 0) return;
      if (daySchedules[idx].done && !await _confirmUncomplete()) return;
      setState(() {
        daySchedules[idx].done = !daySchedules[idx].done;
      });
      _saveSchedules();
      return;
    }
    final milestoneInfo = _getMilestoneInfoForTask(t);
    if (t.done) {
      // 완료 취소 — 시작·완료와 달리 여기만 한 번 묻는다.
      if (!await _confirmUncomplete()) return;
      // 묻는 동안 목록이 새로 읽혔을 수 있다. 옛 객체를 되돌려봐야 화면은
      // 그대로다.
      final reacquired = _reacquireTask(t);
      if (reacquired == null) return;
      t = reacquired;
      setState(() {
        t.done = false;
        t.completedAt = null;
        t.achievedCount = null;
        t.achievedDuration = null;
        t.inProgressAt = null;
        // 되돌리면 실행 시간도 처음으로. 남겨두면 다시 시작할 때 이어져서,
        // 다시 한 시간이 지난 번 기록 위에 얹힌다.
        t.actualSeconds = null;
        t.elapsedSeconds = 0;
        t.runStartedAt = null;
        // 어제 화면에서 되돌린 것도 습관 도장에서 같이 지운다.
        if (_canWriteHabitLogForActiveDate &&
            t.habitId != null &&
            habitLogs[t.habitId!] != null) {
          habitLogs[t.habitId!]!.remove(_activeTodayDateKey);
        }
        if (_isViewingActualToday && t.category == 'schedule') {
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
        if (milestoneInfo != null && milestoneInfo.isMilestoneSelf) {
          _setMilestoneCompletion(milestoneInfo.milestone, false);
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
      if (_canWriteHabitLogForActiveDate) _saveHabitLogs();
      if (_isViewingActualToday) {
        _saveCoreTasks();
        if (t.category == 'schedule') _saveSchedules();
        await TaskResistanceService.onTaskUncompleted(
          taskId: t.id.toString(),
          taskText: t.text,
          date: _getTodayStr(),
        );
      }
      if (milestoneInfo != null && milestoneInfo.isMilestoneSelf) {
        _saveVisions();
      }
    } else if (!forceComplete && t.hasTimer) {
      // 타이머형은 왼쪽 버튼이 시작·일시정지·재시작만 한다. 완료는 밀어야 한다.
      //
      // 한 버튼이 셋을 다 하면 마지막 한 번이 완료가 되어서, 잠깐 쉬려고 누른
      // 것이 끝낸 것으로 기록된다. 그래서 완료를 다른 동작으로 떼어냈다.
      final now = DateTime.now();
      setState(() {
        if (t.inProgress) {
          // 일시정지: 흘러간 만큼만 누적에 얹고 구간을 닫는다.
          t.elapsedSeconds = t.elapsedSecondsAt(now);
          t.inProgress = false;
          t.runStartedAt = null;
          t.pausedAt = now.toIso8601String();
        } else {
          // 시작 또는 재시작. 누적은 건드리지 않아 이어서 흐른다.
          final firstStart = t.elapsedSeconds == 0;
          t.inProgress = true;
          t.runStartedAt = now.toIso8601String();
          t.inProgressAt ??= now.toIso8601String();
          t.pausedAt = null;
          // 완료하려고 이 버튼을 누른 사람은 여기서 "왜 안 끝나지"를 만난다.
          // 그 자리에서 카드를 한 번 밀어 보여주면 답을 찾으러 다니지 않는다.
          if (firstStart) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _showSwipeHint(t.id);
            });
          }
        }
      });
      _syncTaskTicker();
      // 저장은 상태가 바뀌는 이 순간에만 한다. 화면의 초는 기기에서 센다.
      _saveTasks();
      if (t.inProgress) {
        unawaited(_maybeOfferOngoingNudge());
      } else if (_isViewingActualToday) {
        unawaited(_maybeScheduleResumeNudge(t));
      }
    } else if (!forceComplete && !t.inProgress) {
      // 1단계: 진행 중으로 전환 (한 번 더 누르면 완료)
      setState(() {
        t.inProgress = true;
        // 예전에는 습관만 시각을 남겼다. 이제 전부 남긴다 — 저녁에 "시작해두고
        // 멈춘 것 같은데 괜찮으신가요"를 물으려면 언제 시작했는지 알아야 한다.
        t.inProgressAt = DateTime.now().toIso8601String();
      });
      _saveTasks();
      unawaited(_maybeOfferOngoingNudge());
    } else {
      HabitItem? habitInfo;
      double habitCompletionRatio = 1.0;
      String? habitCompletionLabel;
      if (t.habitId != null) {
        final hIdx = habits.indexWhere(
          (h) => h.id.toString() == t.habitId.toString(),
        );
        if (hIdx != -1) {
          habitInfo = habits[hIdx];
          if (habitInfo.checkType == 'count' || habitInfo.checkType == 'both') {
            final selection = await _pickHabitCompletionRatio(habitInfo);
            if (selection == null) return;
            if (!mounted) return;
            // 시트를 읽고 고르는 몇 초 사이에 목록이 통째로 새로 읽혀올 수 있다.
            // 그러면 손에 든 t는 화면에 없는 옛 객체라, 여기에 완료를 적어봐야
            // 화면도 저장도 그대로다. 민 것이 없던 일이 되는 자리가 여기였다.
            final reacquired = _reacquireTask(t);
            if (reacquired == null) return;
            t = reacquired;
            habitCompletionRatio = selection.ratio;
            habitCompletionLabel = selection.label;
            final countGoal = habitInfo.countGoal ?? 0;
            t.achievedCount = (countGoal * habitCompletionRatio).round();
          }
          if (habitInfo.checkType == 'duration' ||
              habitInfo.checkType == 'both') {
            t.achievedDuration = habitInfo.durationGoal ?? 0;
          }
        }
      }

      final completedAtTime = DateTime.now();
      final completedAtIso = completedAtTime.toIso8601String();
      final recordedStartedAt = _startedAtForCompletion(
        currentStartedAt: t.inProgressAt,
        completedAt: completedAtTime,
      );

      // 완료 처리
      setState(() {
        t.done = true;
        // 여기서 실행 시간을 굳힌다. 돌고 있던 구간까지 더한 뒤 멈춘다.
        t.actualSeconds = t.elapsedSecondsAt(completedAtTime);
        t.elapsedSeconds = t.actualSeconds!;
        t.runStartedAt = null;
        t.inProgress = false;
        t.inProgressAt = recordedStartedAt;
        t.pausedAt = null;
        t.completedAt = completedAtIso;
        final completedAt = DateTime.tryParse(t.completedAt!);
        // 어제 화면에서 채운 것도 그날 도장으로 남긴다.
        if (_canWriteHabitLogForActiveDate && t.habitId != null) {
          habitLogs[t.habitId!] ??= <String, dynamic>{};
          final logMap = <String, dynamic>{
            'done': true,
            'status': 'done',
            'completedAt': t.completedAt,
            if (t.inProgressAt != null) 'startedAt': t.inProgressAt,
          };

          if (habitInfo != null) {
            if (habitInfo.checkType == 'count' ||
                habitInfo.checkType == 'both') {
              logMap['count'] = t.achievedCount ?? habitInfo.countGoal ?? 0;
              logMap['countGoal'] = habitInfo.countGoal ?? 0;
              logMap['unit'] = habitInfo.unit ?? '';
              logMap['progressRatio'] = habitCompletionRatio;
              if (habitCompletionLabel != null) {
                logMap['progressLabel'] = habitCompletionLabel;
              }
            }
            if (habitInfo.checkType == 'duration' ||
                habitInfo.checkType == 'both') {
              logMap['duration'] =
                  t.achievedDuration ?? habitInfo.durationGoal ?? 0;
              logMap['durationGoal'] = habitInfo.durationGoal ?? 0;
            }
          }
          habitLogs[t.habitId!]![_activeTodayDateKey] = logMap;
        }
        if (_isViewingActualToday && t.category == 'schedule') {
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
        if (milestoneInfo != null && milestoneInfo.isMilestoneSelf) {
          _setMilestoneCompletion(
            milestoneInfo.milestone,
            true,
            completedAt: completedAt,
          );
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
      if (_canWriteHabitLogForActiveDate) _saveHabitLogs();
      if (_isViewingActualToday) {
        _saveCoreTasks();
        if (t.category == 'schedule') _saveSchedules();
      }
      if (milestoneInfo != null && milestoneInfo.isMilestoneSelf) {
        _saveVisions();
      }
      // 미뤄둔 할일 리마인드 체크 (완료했는지 여부 반환)
      final bool isDeferredResolved = _isViewingActualToday
          ? await _checkAndStoreDeferReminder(t.text)
          : false;
      final bool isCoreTask =
          _isViewingActualToday &&
          coreTasks.any((ct) => ct.id.toString() == t.id.toString());

      // 로컬 칭찬 팝업 (Flirt)
      // 목록이 새로 읽혔을 수 있으니 진행률도 지금 목록으로 센다.
      final countableCurrentTasks = _activeTodayTasksWithSchedules
          .where(_countsTowardDailyCompletion)
          .toList();
      final doneCount = countableCurrentTasks.where((ts) => ts.done).length;
      final totalCount = countableCurrentTasks.length;

      // 선제개입 저항예측 4일차: 완료 결과를 이벤트/상태머신에 반영 (6장 폐루프)
      if (_isViewingActualToday) {
        TaskResistanceService.onTaskCompleted(
          taskId: t.id.toString(),
          taskText: t.text,
          date: _getTodayStr(),
          completionOrder: doneCount,
          totalTasksThatDay: totalCount,
        );
        unawaited(_maybeScheduleNextTaskNudge());
      }

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
    final action = await _showDeleteOptionsDialog(
      title: isHabitTask ? '이 루틴 할 일을 어떻게 할까요?' : '이 일정을 삭제할까요?',
      actions: actions,
    );

    if (action == 'delete') {
      _deleteTaskPermanently(task);
    } else if (action == 'skip') {
      _skipHabitToday(task);
    } else if (action == 'move') {
      _showMoveTaskModal(task);
    }
  }

  /// 캘린더 탭에서 등록된 일정(ScheduleItem)을 지우거나 다른 날짜로 옮길 때,
  /// 오늘 탭과 동일하게 확인 다이얼로그를 먼저 띄운다.
  Future<void> _showScheduleDeleteOptions(
    ScheduleItem item,
    VoidCallback onDelete,
  ) async {
    final action = await _showDeleteOptionsDialog(
      title: '이 일정을 삭제할까요?',
      actions: const <({String label, String value})>[
        (label: '삭제하기', value: 'delete'),
        (label: '다른 날짜로 옮기기', value: 'move'),
        (label: '취소', value: 'cancel'),
      ],
    );

    if (action == 'delete') {
      onDelete();
    } else if (action == 'move') {
      _moveScheduleToAnotherDate(item);
    }
  }

  /// schedules 맵에서 해당 일정이 걸려 있는 날짜 키를 찾는다. (없으면 null)
  String? _dateKeyForScheduleItem(ScheduleItem item) {
    for (final entry in schedules.entries) {
      if (entry.value.any((s) => s.id == item.id)) return entry.key;
    }
    return null;
  }

  /// 캘린더 탭의 일정을 다른 날짜로 옮긴다. 오늘 탭의 이동 모달을 재사용하고,
  /// 이동이 끝나면 원래 날짜에서 id로 안전하게 제거한다.
  void _moveScheduleToAnotherDate(ScheduleItem item) {
    final dateKey = _dateKeyForScheduleItem(item);
    final movedTask = TaskItem(
      id: 'schedule_${item.id}',
      text: item.text,
      category: 'schedule',
      done: item.done,
      time: item.time,
      duration: item.duration,
      timeStart: item.timeStart,
      timeEnd: item.timeEnd,
      createdAt: item.createdAt,
      isReminderEnabled: item.isReminderEnabled,
      deferredCount: item.deferredCount,
      memo: item.memo,
    );
    _showMoveTaskModal(
      movedTask,
      onMoved: () {
        if (dateKey == null) return;
        setState(() {
          final list = schedules[dateKey];
          list?.removeWhere((s) => s.id == item.id);
          if (list != null && list.isEmpty) schedules.remove(dateKey);
        });
        _saveSchedules();
      },
    );
  }

  /// 삭제/이동 선택 다이얼로그 공용 UI. 선택한 action 값을 돌려준다.
  Future<String?> _showDeleteOptionsDialog({
    required String title,
    required List<({String label, String value})> actions,
  }) {
    String selectedAction = actions.first.value;
    return showDialog<String>(
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
                      title,
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
      _activeTodayTasks.removeWhere(
        (t) => t.id.toString() == task.id.toString(),
      );
      if (_isViewingActualToday) {
        coreTasks.removeWhere((t) => t.id.toString() == task.id.toString());
      }

      if (task.category == 'schedule') {
        final dateKey = _activeTodayDateKey;
        final scheduleId = task.id.toString().replaceAll('schedule_', '');
        final daySchedules = schedules[dateKey];
        daySchedules?.removeWhere((s) => s.id == scheduleId);
        if (daySchedules != null && daySchedules.isEmpty) {
          schedules.remove(dateKey);
        }
      }
    });
    _saveTasks();
    if (_isViewingActualToday) {
      _saveCoreTasks();
    }
    if (task.category == 'schedule') _saveSchedules();
  }

  void _skipHabitToday(TaskItem task) {
    if (task.habitId == null) return;

    final today = _getTodayStr();
    setState(() {
      habitLogs[task.habitId!] ??= <String, dynamic>{};
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
          // 손을 댔다가 다음 날로 넘긴 일은 시작 기록을 데려가야 한다.
          // 안 그러면 주간 회고에서 펼쳐보지도 않은 일과 같아진다.
          if (task.inProgressAt != null) 'startedAt': task.inProgressAt,
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
    _activeTodayTasks.removeWhere((t) => t.id.toString() == task.id.toString());
    if (_isViewingActualToday) {
      coreTasks.removeWhere((t) => t.id.toString() == task.id.toString());
    }

    if (_isViewingActualToday && task.category == 'schedule') {
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
                  MediaQuery.of(ctx).viewInsets.bottom +
                      MediaQuery.of(ctx).viewPadding.bottom +
                      24,
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
                        eventLoader: (day) {
                          final key = _dateKey(day);
                          return <Object>[
                            ...?schedules[key],
                            ..._plannedTodayTasksForDate(day),
                          ];
                        },
                        calendarStyle: CalendarStyle(
                          markerSize: 4,
                          markersMaxCount: 1,
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
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _timeReminderButton(
                            active:
                                _isCoreReminderEnabledGlobally &&
                                moveReminderEnabled,
                            onTap: () async {
                              final enabled =
                                  await _ensureCoreReminderEnabledFromHere();
                              if (!enabled) return;
                              setModalState(
                                () =>
                                    moveReminderEnabled = !moveReminderEnabled,
                              );
                            },
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
  Future<void> _addGoal(String type, String text) async {
    if (!await _ensurePlanForTaskInput()) return;
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
  List<MilestoneItem> get _todayMilestoneItems {
    final todayStr = _activeTodayDateKey;
    final parts = todayStr.split('-');
    if (parts.length < 3) return [];

    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final day = int.tryParse(parts[2]) ?? DateTime.now().day;
    return _getMilestonesForDay(
      DateTime(year, month, day),
    ).map((mv) => mv.milestone).toList();
  }

  String _milestoneTaskId(VisionItem vision, MilestoneItem milestone) =>
      'milestone_${vision.name}_${milestone.text}';

  TaskItem _milestoneTaskItem(VisionItem vision, MilestoneItem milestone) =>
      TaskItem(
        id: _milestoneTaskId(vision, milestone),
        text: milestone.text,
        category: 'today',
        done: milestone.done,
        createdAt: milestone.date ?? DateTime.now().toIso8601String(),
        completedAt: milestone.done ? milestone.achievedDate : null,
        isReminderEnabled: false,
      );

  List<TaskItem> _todayMilestoneTaskItemsForActualToday() {
    final todayStr = _getTodayStr();
    final parts = todayStr.split('-');
    if (parts.length < 3) return [];
    final year = int.tryParse(parts[0]) ?? DateTime.now().year;
    final month = int.tryParse(parts[1]) ?? DateTime.now().month;
    final day = int.tryParse(parts[2]) ?? DateTime.now().day;
    return _getMilestonesForDay(
      DateTime(year, month, day),
    ).map((mv) => _milestoneTaskItem(mv.vision, mv.milestone)).toList();
  }

  bool _syncTodayMilestonesIntoCoreTasks() {
    final milestoneTasks = _todayMilestoneTaskItemsForActualToday();
    final milestoneIds = milestoneTasks.map((t) => t.id.toString()).toSet();
    var changed = false;

    final beforeRemove = coreTasks.length;
    coreTasks.removeWhere(
      (task) =>
          task.id.toString().startsWith('milestone_') &&
          !milestoneIds.contains(task.id.toString()),
    );
    if (coreTasks.length != beforeRemove) changed = true;

    for (final milestoneTask in milestoneTasks) {
      final index = coreTasks.indexWhere(
        (task) => task.id.toString() == milestoneTask.id.toString(),
      );
      if (index < 0) {
        coreTasks.add(milestoneTask);
        changed = true;
        continue;
      }

      final existing = coreTasks[index];
      if (existing.text != milestoneTask.text ||
          existing.done != milestoneTask.done ||
          existing.createdAt != milestoneTask.createdAt ||
          existing.completedAt != milestoneTask.completedAt ||
          existing.category != milestoneTask.category ||
          existing.isReminderEnabled != false) {
        existing.text = milestoneTask.text;
        existing.category = milestoneTask.category;
        existing.done = milestoneTask.done;
        existing.createdAt = milestoneTask.createdAt;
        existing.completedAt = milestoneTask.completedAt;
        existing.isReminderEnabled = false;
        changed = true;
      }
    }

    return changed;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _checkCoreReminderEnabledGlobally(),
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Container(
            child: Container(
              color: Colors.transparent,
              child: Column(
                children: [
                  // 탭바 (오늘 / 일정 / 목표 / 습관)
                  _buildTabBar(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildTodayTab(),
                        _buildScheduleTab(),
                        _buildGoalTab(),
                        _buildHabitTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 핵심 할 일 (Core Tasks) 영역 ───────────────────────────
  Widget _buildCoreSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 14),
      padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
      decoration: BoxDecoration(
        color: _coach.accentColor.withValues(alpha: 0.055),
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
              '선택된 핵심이 없어요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                color: const Color(0xFFA0A0B0),
                height: 1.5,
              ),
            )
          else ...[
            if (_coreExpanded)
              ...List.generate(coreTasks.length, (i) => _buildCoreItem(i))
            else
              _buildCoreSummary(),
            if (coreTasks.length > 1 && !_coreExpanded)
              GestureDetector(
                onTap: () => setState(() => _coreExpanded = true),
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      const SizedBox(width: 28),
                      Text(
                        _nextPendingCoreIndex() == -1
                            ? '완료한 핵심 보기'
                            : '+ 핵심 ${coreTasks.length - 1}개 더',
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
      ),
    );
  }

  bool _shouldShowTaskStatusGuide() {
    return _isViewingActualToday &&
        !_taskStatusGuideNeverShow &&
        !_taskStatusGuideDismissed;
  }

  Widget _buildTaskStatusGuideCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _coach.accentColor.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/planner-lightbulb-regular.svg',
                width: 16,
                height: 16,
                colorFilter: ColorFilter.mode(
                  _coach.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '상태 안내',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8F8C9E),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _dismissTaskStatusGuide,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Color(0xFFA4A2B2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildStatusGuideStep(Icons.play_arrow_rounded, '시작 전'),
              _buildStatusGuideArrow(),
              _buildStatusGuideStep(Icons.pause_rounded, '진행 중', lit: true),
              _buildStatusGuideArrow(),
              _buildStatusGuideStep(
                Icons.play_arrow_rounded,
                '일시정지',
                paused: true,
              ),
              _buildStatusGuideArrow(),
              _buildStatusGuideStep(Icons.check_rounded, '완료', filled: true),
            ],
          ),
          const SizedBox(height: 9),
          // 왼쪽 버튼이 완료를 하지 않게 되면서, 완료하는 법을 따로 말해줘야
          // 한다. 그림만으로는 마지막 칸으로 어떻게 넘어가는지 알 수 없다.
          Text(
            '완료는 카드를 오른쪽으로 미세요',
            style: GoogleFonts.notoSansKr(
              fontSize: 11.5,
              height: 1.3,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8F8C9E),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () =>
                _setTaskStatusGuideNeverShow(!_taskStatusGuideNeverShow),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _taskStatusGuideNeverShow
                        ? _coach.accentColor
                        : Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _taskStatusGuideNeverShow
                          ? _coach.accentColor
                          : const Color(0xFFA4A2B2),
                      width: 1.4,
                    ),
                  ),
                  child: _taskStatusGuideNeverShow
                      ? const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  '다시 보지 않기',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF8F8C9E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [filled]는 완료, [lit]은 진행 중, [paused]는 일시정지.
  /// 셋 다 아니면 아직 시작 전이다.
  /// 실제 버튼과 같은 색을 써야 안내가 안내 노릇을 한다.
  Widget _buildStatusGuideStep(
    IconData icon,
    String label, {
    bool filled = false,
    bool lit = false,
    bool paused = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled
                ? _coach.accentColor.withValues(alpha: 0.34)
                : paused
                ? _coach.accentColor
                : lit
                ? _coach.accentColor.withValues(alpha: 0.14)
                : const Color(0xFFF4F4F7),
            borderRadius: BorderRadius.circular(filled ? 999 : 12),
            border: filled || paused || !lit
                ? null
                : Border.all(color: _coach.accentColor.withValues(alpha: 0.38)),
          ),
          child: Icon(
            icon,
            size: filled ? 22 : 20,
            color: filled || paused
                ? Colors.white
                : lit
                ? _coach.accentColor
                : const Color(0xFFB4B7C4),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 11,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFA0A0B0),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusGuideArrow() {
    // 칸이 셋에서 넷으로 늘어서 화살표 여백을 줄였다. 좁은 화면에서 넘친다.
    return const Padding(
      padding: EdgeInsets.fromLTRB(9, 0, 9, 17),
      child: Icon(
        Icons.arrow_forward_rounded,
        size: 16,
        color: Color(0xFFA4A2B2),
      ),
    );
  }

  Future<void> _dismissTaskStatusGuide() async {
    if (!mounted) return;
    setState(() => _taskStatusGuideDismissed = true);
  }

  Future<void> _setTaskStatusGuideNeverShow(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_taskStatusGuideNeverShowKey, value);
    if (!mounted) return;
    setState(() {
      _taskStatusGuideNeverShow = value;
      if (value) _taskStatusGuideDismissed = true;
    });
  }

  bool _isCoreTaskDone(TaskItem coreTask) {
    final coreId = coreTask.id.toString();
    if (coreId.startsWith('milestone_')) return coreTask.done;
    return tasks.any(
      (t) => (t.id.toString() == coreId || t.text == coreTask.text) && t.done,
    );
  }

  int _nextPendingCoreIndex() {
    return coreTasks.indexWhere((coreTask) => !_isCoreTaskDone(coreTask));
  }

  Widget _buildCoreSummary() {
    final pendingIndex = _nextPendingCoreIndex();
    if (pendingIndex != -1) return _buildCoreItem(pendingIndex);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _coach.accentColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '모두 완료',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _coach.accentColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoreItem(int idx) {
    final c = coreTasks[idx];
    final isDone = _isCoreTaskDone(c);
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
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              if (c.time == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('시간이 지정된 일정만 리마인더를 받을 수 있습니다.'),
                    duration: const Duration(seconds: 2),
                    backgroundColor: const Color(0xFF1A1A2E),
                  ),
                );
                return;
              }
              final enabled = await _ensureCoreReminderEnabledFromHere();
              if (!enabled) return;
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
                                        if (t.time == null) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                '시간이 지정된 일정만 리마인더를 받을 수 있습니다.',
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
                                        final enabled =
                                            await _ensureCoreReminderEnabledFromHere();
                                        if (!enabled) return;
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
                            source: existing.source,
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
    const tabs = [
      {'icon': Icons.assignment_outlined, 'label': '오늘'},
      {'icon': Icons.calendar_month_outlined, 'label': '캘린더'},
      {'icon': Icons.track_changes_outlined, 'label': '목표'},
      {'icon': Icons.wb_sunny_outlined, 'label': '루틴'},
    ];
    return Container(
      color: Colors.white,
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
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // 헤더 (날짜 + 진행률)
          _buildTodayHeader(),
          if (_isViewingPastDate)
            Expanded(
              child: Align(
                alignment: const Alignment(0, -0.55),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/clock-rotate-left.svg',
                      width: 40,
                      height: 40,
                      colorFilter: ColorFilter.mode(
                        _coach.accentColor,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '오늘 탭은 오늘의 실행과\n미래 계획을 위한 공간입니다.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          color: const Color(0xFFA0A0B0),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // 핵심 할 일 (Core Tasks)
            if (_isViewingActualToday) _buildCoreSection(),
            if (_shouldShowTaskStatusGuide()) _buildTaskStatusGuideCard(),
            // 태스크 목록
            Expanded(child: _buildTaskList()),
            // 입력 영역
            _buildTodayInput(),
          ],
        ],
      ),
    );
  }

  Future<void> _pickDateFromTodayHeader(DateTime initialDate) async {
    final firstDate = _yesterdayDate;
    final selected = await showDatePicker(
      context: context,
      // 다른 화면에서 더 지난 날짜를 열어둔 채 들어올 수 있다. 달력은 첫날부터 연다.
      initialDate: initialDate.isBefore(firstDate) ? firstDate : initialDate,
      // 어제까지만 연다. 그보다 앞은 기록 탭이 보여주는 지난 이야기다.
      firstDate: firstDate,
      lastDate: DateTime(2050, 12, 31),
      locale: const Locale('ko', 'KR'),
    );
    if (selected == null || !mounted) return;

    setState(() {
      _selectedTodayDate = DateTime(
        selected.year,
        selected.month,
        selected.day,
      );
    });
  }

  Widget _buildTodayHeader() {
    final targetDate = _activeTodayDate;
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
        '${targetDate.year}년 ${months[targetDate.month - 1]} ${targetDate.day}일 (${days[targetDate.weekday % 7]})';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pickDateFromTodayHeader(targetDate),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateStr,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: Color(0xFF8B7CFF),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskList() {
    final todayStr = _activeTodayDateKey;
    final parts = todayStr.split('-');
    int y = DateTime.now().year;
    int m = DateTime.now().month;
    int d = DateTime.now().day;
    if (parts.length >= 3) {
      y = int.tryParse(parts[0]) ?? y;
      m = int.tryParse(parts[1]) ?? m;
      d = int.tryParse(parts[2]) ?? d;
    }
    final targetDate = DateTime(y, m, d);
    final todayMilestones = _getMilestonesForDay(targetDate);
    final milestoneTasks = todayMilestones.map((mv) {
      return _milestoneTaskItem(mv.vision, mv.milestone);
    }).toList();

    final currentTasks = _activeTodayTasksWithSchedules;
    final currentIds = currentTasks.map((t) => t.id.toString()).toSet();
    final combinedTasks = [
      ...currentTasks,
      // 선택한 날짜(targetDate)에 걸린 마일스톤은 실제 오늘이든 다른 날짜든
      // 항상 함께 보여준다. milestoneTasks는 이미 그 날짜 기준으로 계산돼 있다.
      ...milestoneTasks.where(
        (task) => !currentIds.contains(task.id.toString()),
      ),
    ];

    if (combinedTasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets, color: Colors.grey, size: 40),
            const SizedBox(height: 12),
            Text(
              _isViewingActualToday
                  ? '코치와 대화하면\n여기에 할 일이 추가돼요!'
                  : (_isViewingYesterday
                        ? '어제 남은 할 일이 없어요.'
                        : '이 날짜에 계획된 할 일이 없어요.'),
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

    final remainingTasks = sortedTasks.where((task) => !task.done).toList();
    final doneTasks = sortedTasks.where((task) => task.done).toList();
    final showLightenPlanCard = _shouldShowLightenPlanCard(
      remainingTasks: remainingTasks,
      doneTasks: doneTasks,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      children: [
        if (showLightenPlanCard) _buildLightenPlanCard(),
        if (!showLightenPlanCard && _shouldShowCorePickCard(remainingTasks))
          _buildCorePickCard(),
        if (remainingTasks.isNotEmpty)
          _buildRemainingTaskGroup(remainingTasks)
        else
          ...doneTasks.map(_buildTaskItem),
        if (remainingTasks.isNotEmpty) ...doneTasks.map(_buildTaskItem),
      ],
    );
  }

  bool _shouldShowLightenPlanCard({
    required List<TaskItem> remainingTasks,
    required List<TaskItem> doneTasks,
  }) {
    final now = DateTime.now();
    return _isViewingActualToday &&
        now.hour >= 15 &&
        remainingTasks.length >= 3 &&
        doneTasks.isEmpty &&
        // 이미 핵심을 골라둔 사람에게 골라보자고 할 것은 없다.
        coreTasks.isEmpty &&
        _lightenPlanCardDismissedDate != _getTodayStr();
  }

  /// 할 일이 세 개가 됐는데 아직 핵심을 안 골랐을 때.
  ///
  /// 오후 3시 카드와 자리는 같지만 하는 말이 다르다. 그쪽은 하루가 반이 지나도록
  /// 하나도 못 한 사람에게 줄이자고 하는 것이고, 이쪽은 지금 막 목록이 길어진
  /// 사람에게 그중 중요한 것을 골라두자고 하는 것이다.
  ///
  /// 등록하는 손을 막지 않는다. 세 개째에서 창이 뜨면 네 개를 넣으려던 사람은
  /// 중간에 끊긴다. 카드는 목록 위에 얹혀 있기만 하고, 처음 생길 때 한 번
  /// 튀어서 눈에 들어온다. 그 뒤로는 몇 개를 더 넣어도 다시 튀지 않는다.
  bool _shouldShowCorePickCard(List<TaskItem> remainingTasks) {
    return _isViewingActualToday &&
        remainingTasks.length >= 3 &&
        coreTasks.isEmpty &&
        _corePickCardDismissedDate != _getTodayStr();
  }

  /// 순서를 정하자는 말이 아니다. 오늘 목록에서 중요한 것을 골라두자는 말이다.
  String get _corePickCardMessage => switch (_coach.id) {
    'bro' => '할 일이 늘었다. 이 중에 중요한 거 한두 개만 골라두자.',
    'halmae' => '할 일이 늘었구나. 이 중에 중요한 거 한두 가지만 골라두자.',
    'boyfriend' => '할 일이 늘었네. 이 중에 중요한 거 한두 개만 골라둘까?',
    'nyang_halbae' => '할 일이 늘었다냥. 이 중에 중요한 거 한두 개만 골라두자냥.',
    'sec_female' => '할 일이 늘었어요. 이 중에 중요한 것 한두 가지만 골라둘까요?',
    _ => '할 일이 늘었다냥. 이 중에 중요한 거 한두 개만 골라둘까냥?',
  };

  Future<void> _dismissCorePickCardForToday() async {
    final today = _getTodayStr();
    setState(() => _corePickCardDismissedDate = today);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_corePickCardDismissedDateKey, today);
  }

  Widget _buildCorePickCard() {
    // 처음 생길 때 한 번만 튄다. 다음 build마다 다시 튀면 할 일을 넣을 때마다
    // 카드가 들썩여서, 막지 않겠다고 해놓고 계속 끼어드는 셈이 된다.
    if (!_corePickCardBounced) {
      _corePickCardBounced = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _corePickBounceCtrl.forward(from: 0);
      });
    }

    return AnimatedBuilder(
      animation: _corePickBounceCtrl,
      builder: (context, child) {
        // 두 번 튀고 멈춘다.
        final dy = TweenSequence<double>([
          TweenSequenceItem(tween: ConstantTween<double>(0), weight: 10),
          TweenSequenceItem(
            tween: Tween<double>(begin: 0, end: -10),
            weight: 12,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: -10, end: 0),
            weight: 16,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: 0, end: -6),
            weight: 10,
          ),
          TweenSequenceItem(
            tween: Tween<double>(begin: -6, end: 0),
            weight: 14,
          ),
          TweenSequenceItem(tween: ConstantTween<double>(0), weight: 38),
        ]).evaluate(_corePickBounceCtrl);
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
        decoration: BoxDecoration(
          color: _coach.accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _coach.accentColor.withValues(alpha: 0.28)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _corePickCardMessage,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      height: 1.45,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () async {
                      await _dismissCorePickCardForToday();
                      if (!mounted) return;
                      _showCoreSelectionModal();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _coach.accentColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '오늘의 핵심 고르기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _dismissCorePickCardForToday,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: Color(0xFFA0A0B0)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _lightenPlanCardMessage {
    switch (_coach.id) {
      case 'cat':
        return '오늘은 하나만 해도 충분하다냥. 남겨둘 일 한두 가지만 골라볼까냥?';
      case 'boyfriend':
        return '오늘은 하나만 해도 충분해. 남겨둘 일 한두 가지만 같이 골라볼까?';
      case 'halmae':
        return '오늘은 하나만 해도 충분혀. 남겨둘 일 한두 가지만 골라보자.';
      case 'bro':
        return '오늘은 하나만 해도 충분하다. 남겨둘 거 한두 개만 딱 골라보자.';
      case 'nyang_halbae':
      case 'sec_female':
      default:
        return '오늘은 하나만 해도 충분해요. 남겨둘 일 한두 가지만 골라볼까요?';
    }
  }

  Widget _buildLightenPlanCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF8FF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _coach.accentColor.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: _coach.accentColor.withValues(alpha: 0.13),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _coach.accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.filter_alt_outlined,
              size: 17,
              color: _coach.accentColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _lightenPlanCardMessage,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF3D3A4E),
                  ),
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: () async {
                    await _dismissLightenPlanCardForToday();
                    if (!mounted) return;
                    _showCoreSelectionModal();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _coach.accentColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '오늘의 핵심 고르기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _dismissLightenPlanCardForToday,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 18, color: Color(0xFFA0A0B0)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dismissLightenPlanCardForToday() async {
    final today = _getTodayStr();
    if (_lightenPlanCardDismissedDate == today) return;
    setState(() {
      _lightenPlanCardDismissedDate = today;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lightenPlanCardDismissedDateKey, today);
  }

  Widget _buildRemainingTaskGroup(List<TaskItem> remainingTasks) {
    final showCheckboxHint =
        !_taskCheckboxHintSeen && remainingTasks.any((task) => !task.done);
    if (showCheckboxHint && !_taskCheckboxHintPulseStarted) {
      _taskCheckboxHintPulseStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _taskCheckboxHintPulseCtrl.forward(from: 0);
        }
      });
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 여기 있던 "한 번 더 누르면 완료돼요" 말풍선은 걷어냈다. 완료는 이제
        // 카드를 미는 쪽이라 설명이 틀렸고, ▶를 처음 누르면 카드가 한 번 밀려
        // 보이는 안내가 따로 나온다. 처음 쓰는 사람에게 설명이 둘 뜨던 자리다.
        _buildTaskTimerToggle(remainingTasks),
        ...remainingTasks.asMap().entries.map(
          (entry) => _buildTaskItem(
            entry.value,
            showCheckboxTapHint: showCheckboxHint && entry.key == 0,
          ),
        ),
      ],
    );
  }

  /// 흐르는 시간을 감추는 스위치. 목록 바로 위 오른쪽에 붙는다.
  ///
  /// 아무것도 시작하지 않은 아침에는 할 일이 없는 스위치라 감춘다. 진행 중인
  /// 카드가 생기면 그 위에 나타나고, 다 끝나면 사라진다.
  ///
  /// 자리를 '오늘의 핵심' 줄이 아니라 목록 머리로 잡은 것은, 거기 붙이면
  /// 핵심 일정에만 적용되는 것처럼 읽히기 때문이다.
  Widget _buildTaskTimerToggle(List<TaskItem> tasks) {
    final anyRunning = tasks.any((t) => t.hasTimer && t.inProgress && !t.done);
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !anyRunning
          ? const SizedBox(width: double.infinity)
          : Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _setShowTaskTimer(!_showTaskTimer),
                behavior: HitTestBehavior.opaque,
                // 글자 자체가 상태이자 버튼이다. 옆에 스위치까지 두면 같은 말을
                // 두 번 하는 셈이라, 한 줄뿐인 자리가 번잡해진다.
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 6, 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 15,
                        color: _showTaskTimer
                            ? _coach.accentColor
                            : const Color(0xFFB4B7C4),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _showTaskTimer ? '타이머 ON' : '타이머 OFF',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _showTaskTimer
                              ? _coach.accentColor
                              : const Color(0xFFB4B7C4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildCheckboxTapHintDot({double size = 7}) {
    return AnimatedBuilder(
      animation: _taskCheckboxHintPulseCtrl,
      builder: (context, child) {
        final opacity = TweenSequence<double>([
          TweenSequenceItem(tween: ConstantTween<double>(0), weight: 8),
          TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 14),
          TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 18),
          TweenSequenceItem(tween: Tween<double>(begin: 0, end: 1), weight: 14),
          TweenSequenceItem(tween: Tween<double>(begin: 1, end: 0), weight: 18),
          TweenSequenceItem(tween: ConstantTween<double>(0), weight: 8),
        ]).evaluate(_taskCheckboxHintPulseCtrl);
        final scale = 0.85 + (opacity * 0.25);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: _coach.accentColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _coach.accentColor.withValues(alpha: 0.35),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markTaskCheckboxHintSeen() async {
    if (_taskCheckboxHintSeen) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_taskCheckboxHintSeenKey, true);
    if (!mounted) return;
    setState(() {
      _taskCheckboxHintSeen = true;
    });
  }

  void _copyTaskEdits(TaskItem target, TaskItem source) {
    target.text = source.text;
    target.time = source.time;
    target.timeStart = source.timeStart;
    target.timeEnd = source.timeEnd;
    target.duration = source.duration;
    target.isReminderEnabled = source.isReminderEnabled;
    target.source = source.source;
    target.memo = source.memo;
  }

  void _copyTaskEditsToSchedule(ScheduleItem target, TaskItem source) {
    target.text = source.text;
    target.time = _displayTimeFromStored(
      time: source.time,
      timeStart: source.timeStart,
      timeEnd: source.timeEnd,
    );
    target.timeStart = source.timeStart;
    target.timeEnd = source.timeEnd;
    target.duration = source.duration;
    target.isReminderEnabled = source.isReminderEnabled;
    target.memo = source.memo;
  }

  void _copyScheduleEditsToTask(TaskItem target, ScheduleItem source) {
    target.text = source.text;
    target.time = _displayTimeFromStored(
      time: source.time,
      timeStart: source.timeStart,
      timeEnd: source.timeEnd,
    );
    target.timeStart = source.timeStart;
    target.timeEnd = source.timeEnd;
    target.duration = source.duration;
    target.done = source.done;
    target.isReminderEnabled = source.isReminderEnabled;
    target.deferredCount = source.deferredCount;
    target.memo = source.memo;
  }

  Future<void> _saveScheduleTabScheduleEdit(
    String dateKey,
    ScheduleItem schedule,
  ) async {
    setState(() {
      final scheduleId = 'schedule_${schedule.id}';
      for (final task in tasks) {
        if (task.id.toString() == scheduleId) {
          _copyScheduleEditsToTask(task, schedule);
        }
      }
      for (final dayTasks in plannedTodayTasksByDate.values) {
        for (final task in dayTasks) {
          if (task.id.toString() == scheduleId) {
            _copyScheduleEditsToTask(task, schedule);
          }
        }
      }
      final coreIndex = coreTasks.indexWhere(
        (task) => task.id.toString() == scheduleId,
      );
      if (coreIndex != -1) {
        _copyScheduleEditsToTask(coreTasks[coreIndex], schedule);
      } else if (schedule.isReminderEnabled) {
        coreTasks.add(
          TaskItem(
            id: scheduleId,
            text: schedule.text,
            category: 'schedule',
            done: schedule.done,
            time: _displayTimeFromStored(
              time: schedule.time,
              timeStart: schedule.timeStart,
              timeEnd: schedule.timeEnd,
            ),
            duration: schedule.duration,
            timeStart: schedule.timeStart,
            timeEnd: schedule.timeEnd,
            createdAt: schedule.createdAt,
            isReminderEnabled: schedule.isReminderEnabled,
            deferredCount: schedule.deferredCount,
            memo: schedule.memo,
          ),
        );
      }
    });
    await _saveSchedules();
    if (dateKey == _getTodayStr()) {
      await _persistTodayTasks();
    } else {
      await _savePlannedTodayTasks();
    }
    await _saveCoreTasks();
  }

  /// [expandTimeOptions]면 시간 칸을 펼친 채로 연다.
  ///
  /// 알람은 그 칸을 펼쳐야 보인다. 채팅에서 "알람 켜줘"라고 해서 데려왔는데
  /// 접힌 채로 열리면, 부탁한 것이 어디 있는지 찾아야 한다.
  void _showEditItemModal(
    dynamic item,
    VoidCallback onSave, {
    VoidCallback? onDelete,
    bool expandTimeOptions = false,
  }) {
    final wasInsightTask = item is TaskItem && _isInsightTask(item);
    final initialText = wasInsightTask
        ? _cleanInsightTaskTitle(item.text)
        : item.text;
    final textCtrl = TextEditingController(text: initialText);

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
    bool mRepeatEnabled = isScheduleItem && item.isRecurring;
    Map<String, dynamic>? mRepeatRule = isScheduleItem
        ? (item.recurrenceRule == null
              ? null
              : Map<String, dynamic>.from(item.recurrenceRule!))
        : null;
    bool timeOptionsExpanded = expandTimeOptions;
    // 메모(선택): 기본 접힘. 값이 있어도 눌러야 펼쳐진다.
    final memoCtrl = TextEditingController(text: item.memo ?? '');
    bool memoExpanded = false;
    // 메모는 사용자가 직접 만든 할 일·일정에만 지원한다.
    // 습관/마일스톤 연동/메모장 실행목록 항목은 원본에 맥락이 있어 제외한다.
    final bool memoAllowed =
        _getMilestoneInfoForTask(item) == null &&
        !wasInsightTask &&
        !(item is TaskItem && (item.category == 'habit' || item.isHabit));
    // "메모 보기"/활성색은 실제로 저장된 메모가 있을 때만 (입력 중에는 바뀌지 않음).
    final bool hadSavedMemo =
        item.memo != null && (item.memo as String).trim().isNotEmpty;

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
                // 키보드(viewInsets)뿐 아니라 기기별 하단 안전영역(제스처바/내비게이션
                // 버튼, viewPadding)까지 더해야 "저장하기" 버튼이 기종과 무관하게
                // 항상 화면 안에 안정적으로 보인다.
                bottom:
                    MediaQuery.of(ctx).viewInsets.bottom +
                    MediaQuery.of(ctx).viewPadding.bottom +
                    24,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                _showMemoDialog(
                                  context,
                                  mInfo.milestone,
                                  (fn) => setState(fn),
                                );
                              }
                            },
                            child: Container(
                              margin: const EdgeInsets.only(top: 8, bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: _coach.accentColor.withValues(
                                  alpha: 0.10,
                                ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: _coach.accentColor.withValues(
                                    alpha: 0.25,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.flag,
                                    color: _coach.accentColor,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: RichText(
                                      text: TextSpan(
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          color: _coach.accentColor,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: mInfo.isMilestoneSelf
                                                ? '연동된 마일스톤: '
                                                : '메모장의 실행 목록',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (mInfo.isMilestoneSelf)
                                            TextSpan(
                                              text:
                                                  '${mInfo.visionName} > ${mInfo.milestoneText}',
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right,
                                    color: _coach.accentColor,
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
                  GestureDetector(
                    onTap: () => setModalState(
                      () => timeOptionsExpanded = !timeOptionsExpanded,
                    ),
                    child: Builder(
                      builder: (context) {
                        final effectiveTimeType = _effectiveClockTimeType(
                          mTimeType,
                          mEndTime,
                        );
                        final hasClockTime =
                            (effectiveTimeType == 'single' ||
                                effectiveTimeType == 'range') &&
                            mStartTime != null;
                        final hasDuration =
                            effectiveTimeType == 'duration' &&
                            mDuration != null;
                        final reminderActive = _resolvedTimeReminderEnabled(
                          effectiveTimeType,
                          mStartTime,
                          mReminderEnabled,
                        );
                        final summary = hasClockTime
                            ? (mEndTime != null
                                  ? '${_formatTime(mStartTime!)} ~ ${_formatTime(mEndTime!)}'
                                  : _formatTime(mStartTime!))
                            : (hasDuration ? mDuration! : null);

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8F7FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE8E3F8)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 20,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SvgPicture.asset(
                                    'assets/icons/fa-clock-regular.svg',
                                    height: 18,
                                    colorFilter: ColorFilter.mode(
                                      summary == null
                                          ? const Color(0xFFB0B0C8)
                                          : _coach.accentColor,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  summary ?? '시간 미정',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: summary == null
                                        ? const Color(0xFF9CA3AF)
                                        : const Color(0xFF3D3A4E),
                                  ),
                                ),
                              ),
                              if (summary != null &&
                                  hasClockTime &&
                                  reminderActive) ...[
                                _timeReminderActiveBadge(),
                                const SizedBox(width: 8),
                              ],
                              Icon(
                                timeOptionsExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.chevron_right_rounded,
                                size: 20,
                                color: const Color(0xFFC4C0D8),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  if (timeOptionsExpanded) ...[
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final modeTypes = isScheduleItem
                            ? ['single', 'duration', 'repeat']
                            : ['single', 'duration'];
                        const labels = {
                          'single': '특정 시간',
                          'duration': '소요 시간',
                          'repeat': '반복',
                        };

                        return Row(
                          children: modeTypes.map((t) {
                            final isRepeat = t == 'repeat';
                            final isClockType =
                                t == 'single' &&
                                (mTimeType == 'single' || mTimeType == 'range');
                            final isActive = isRepeat
                                ? mRepeatEnabled
                                : (isClockType || mTimeType == t);
                            final isLast = t == modeTypes.last;

                            return Expanded(
                              child: GestureDetector(
                                onTap: () async {
                                  if (isRepeat) {
                                    final rule =
                                        await _showScheduleRepeatDialog(
                                          initialRule: mRepeatRule,
                                          baseDate: _calSelectedDay,
                                        );
                                    if (rule != null) {
                                      setModalState(() {
                                        mRepeatEnabled = true;
                                        mRepeatRule = rule;
                                      });
                                    }
                                    return;
                                  }

                                  setModalState(() {
                                    mReminderEnabled = false;
                                    if (t == 'single') {
                                      mTimeType = isClockType
                                          ? 'none'
                                          : 'single';
                                      mDuration = null;
                                      if (isClockType) {
                                        mStartTime = null;
                                        mEndTime = null;
                                      }
                                    } else {
                                      mTimeType = mTimeType == t ? 'none' : t;
                                      mStartTime = null;
                                      mEndTime = null;
                                    }
                                  });
                                },
                                child: Container(
                                  margin: EdgeInsets.only(
                                    right: isLast ? 0 : 6,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 9,
                                  ),
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
                                          labels[t]!,
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
                          }).toList(),
                        );
                      },
                    ),
                    if (mTimeType == 'single' || mTimeType == 'range')
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
                                if (t != null) {
                                  final enabled =
                                      await _checkCoreReminderEnabledGlobally();
                                  setModalState(() {
                                    mStartTime = t;
                                    mReminderEnabled = enabled;
                                  });
                                }
                              },
                              child: _timeValueChip(
                                mStartTime != null
                                    ? _formatTime(mStartTime!)
                                    : '시작 시간',
                                active: mStartTime != null,
                              ),
                            ),
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
                              child: _timeValueChip(
                                mEndTime != null
                                    ? _formatTime(mEndTime!)
                                    : '종료 시간',
                                active: mEndTime != null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (isScheduleItem || item is TaskItem)
                              _timeReminderButton(
                                active: _resolvedTimeReminderEnabled(
                                  mTimeType,
                                  mStartTime,
                                  mReminderEnabled,
                                ),
                                onTap: () async {
                                  if (mStartTime == null) {
                                    _showSelectTimeBeforeReminderSnackBar();
                                    return;
                                  }
                                  final enabled =
                                      await _ensureCoreReminderEnabledFromHere();
                                  if (!enabled) return;
                                  setModalState(
                                    () => mReminderEnabled = !mReminderEnabled,
                                  );
                                },
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
                  ],
                  if (memoAllowed) ...[
                    const SizedBox(height: 12),
                    // 메모(선택). 저장된 메모가 없으면 "메모 추가"(회색),
                    // 있으면 "메모 보기"(연보라·활성). 눌러야 펼쳐진다.
                    GestureDetector(
                      onTap: () =>
                          setModalState(() => memoExpanded = !memoExpanded),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F7FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE8E3F8)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 20,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SvgPicture.asset(
                                  'assets/icons/fa-file-lines-regular.svg',
                                  height: 18,
                                  colorFilter: ColorFilter.mode(
                                    hadSavedMemo
                                        ? _coach.accentColor
                                        : const Color(0xFFB0B0C8),
                                    BlendMode.srcIn,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                hadSavedMemo ? '메모 보기' : '메모 추가',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: hadSavedMemo
                                      ? const Color(0xFF3D3A4E)
                                      : const Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                            Icon(
                              memoExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.chevron_right_rounded,
                              size: 20,
                              color: const Color(0xFFC4C0D8),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (memoExpanded) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFDDD6FE)),
                        ),
                        child: TextField(
                          controller: memoCtrl,
                          maxLength: 100,
                          minLines: 2,
                          maxLines: 4,
                          onChanged: (_) => setModalState(() {}),
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            color: const Color(0xFF3D3A4E),
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 12,
                            ),
                            counterStyle: GoogleFonts.notoSansKr(
                              fontSize: 11,
                              color: const Color(0xFFA7A2BE),
                            ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setModalState(() {
                          memoCtrl.clear();
                          memoExpanded = false;
                        }),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '메모 삭제',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            await _checkCoreReminderEnabledGlobally();
                            final text = textCtrl.text.trim();
                            if (text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('내용을 입력해주세요.')),
                              );
                              return;
                            }

                            item.text = text;
                            if (wasInsightTask) {
                              item.source = 'insight';
                            }
                            if (memoAllowed) {
                              final memoText = memoCtrl.text.trim();
                              item.memo = memoText.isEmpty ? null : memoText;
                            }
                            item.time = null;
                            item.timeStart = null;
                            item.timeEnd = null;
                            item.duration = null;

                            final effectiveTimeType = _effectiveClockTimeType(
                              mTimeType,
                              mEndTime,
                            );

                            if (effectiveTimeType == 'single' &&
                                mStartTime != null) {
                              item.time = _formatTime(mStartTime!);
                              item.timeStart =
                                  '${mStartTime!.hour.toString().padLeft(2, '0')}:${mStartTime!.minute.toString().padLeft(2, '0')}';
                            } else if (effectiveTimeType == 'range' &&
                                mStartTime != null) {
                              item.time = _formatTime(mStartTime!);
                              item.timeStart =
                                  '${mStartTime!.hour.toString().padLeft(2, '0')}:${mStartTime!.minute.toString().padLeft(2, '0')}';
                              if (mEndTime != null) {
                                item.time += ' ~ ${_formatTime(mEndTime!)}';
                                item.timeEnd =
                                    '${mEndTime!.hour.toString().padLeft(2, '0')}:${mEndTime!.minute.toString().padLeft(2, '0')}';
                              }
                            } else if (mTimeType == 'duration' &&
                                mDuration != null) {
                              item.duration = mDuration;
                            }

                            if (isScheduleItem) {
                              item.isReminderEnabled =
                                  _resolvedTimeReminderEnabled(
                                    effectiveTimeType,
                                    mStartTime,
                                    mReminderEnabled,
                                  );
                              item.isRecurring = mRepeatEnabled;
                              item.recurrenceRule = mRepeatEnabled
                                  ? (mRepeatRule ?? item.recurrenceRule)
                                  : null;
                              if (item.isRecurring &&
                                  item.recurrenceRule != null) {
                                _replaceFutureRecurringSchedules(
                                  item,
                                  item.recurrenceRule!,
                                );
                              }
                            } else if (item is TaskItem) {
                              item.isReminderEnabled =
                                  _resolvedTimeReminderEnabled(
                                    effectiveTimeType,
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
                              '수정완료',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (onDelete != null || item is TaskItem) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              final shouldDeleteRecurring =
                                  isScheduleItem && item.isRecurring ||
                                  item is TaskItem &&
                                      _isRecurringScheduleTask(item);
                              if (shouldDeleteRecurring) {
                                Future.microtask(() {
                                  if (mounted) {
                                    _deleteRecurringScheduleItem(item);
                                  }
                                });
                                return;
                              }
                              if (onDelete != null) {
                                // 캘린더 탭의 일정은 바로 지우지 않고 오늘 탭과 동일한
                                // 확인 다이얼로그(삭제 / 다른 날짜로 옮기기)를 먼저 띄운다.
                                if (isScheduleItem) {
                                  final deleteCallback = onDelete;
                                  Future.microtask(() {
                                    if (mounted) {
                                      _showScheduleDeleteOptions(
                                        item,
                                        deleteCallback,
                                      );
                                    }
                                  });
                                  return;
                                }
                                onDelete();
                                return;
                              }
                              Future.microtask(() {
                                if (mounted) _showTaskDeleteOptions(item);
                              });
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _coach.accentColor.withOpacity(0.45),
                                  width: 1.5,
                                ),
                              ),
                              child: Text(
                                (isScheduleItem && item.isRecurring ||
                                        item is TaskItem &&
                                            _isRecurringScheduleTask(item))
                                    ? '삭제하기'
                                    : '삭제 / 날짜 ↻',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: _coach.accentColor.withOpacity(0.82),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  bool _isRecurringScheduleTask(TaskItem task) {
    if (task.category != 'schedule') return false;
    final scheduleId = task.id.toString().replaceAll('schedule_', '');
    final daySchedules = schedules[_activeTodayDateKey] ?? [];
    return daySchedules.any((s) => s.id == scheduleId && s.isRecurring);
  }

  ScheduleItem? _scheduleItemForTask(TaskItem task) {
    if (task.category != 'schedule') return null;
    final scheduleId = task.id.toString().replaceAll('schedule_', '');
    final activeDayMatch = schedules[_activeTodayDateKey]?.where(
      (s) => s.id == scheduleId,
    );
    if (activeDayMatch != null && activeDayMatch.isNotEmpty) {
      return activeDayMatch.first;
    }
    for (final daySchedules in schedules.values) {
      for (final schedule in daySchedules) {
        if (schedule.id == scheduleId) return schedule;
      }
    }
    return null;
  }

  Future<void> _deleteRecurringScheduleItem(dynamic item) async {
    final ScheduleItem? source = item is ScheduleItem
        ? item
        : item is TaskItem
        ? _scheduleItemForTask(item)
        : null;
    if (source == null || !source.isRecurring) return;

    final confirm =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: Text(
                '반복 일정 삭제',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              content: Text(
                '정말 삭제하시겠습니까?\n반복으로 등록된 같은 일정이 모두 삭제됩니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: const Color(0xFF6B7280),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    '아니오',
                    style: GoogleFonts.notoSansKr(
                      color: const Color(0xFF9593A5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    '예',
                    style: GoogleFonts.notoSansKr(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!confirm) return;

    final recurrenceGroupId = source.recurrenceGroupId;
    final removedScheduleIds = <String>{};

    setState(() {
      final emptyDateKeys = <String>[];
      schedules.forEach((dateKey, daySchedules) {
        daySchedules.removeWhere((schedule) {
          final shouldRemove = recurrenceGroupId != null
              ? schedule.recurrenceGroupId == recurrenceGroupId
              : schedule.id == source.id;
          if (shouldRemove) removedScheduleIds.add(schedule.id);
          return shouldRemove;
        });
        if (daySchedules.isEmpty) emptyDateKeys.add(dateKey);
      });
      for (final dateKey in emptyDateKeys) {
        schedules.remove(dateKey);
      }

      bool isRemovedScheduleTask(TaskItem task) =>
          task.category == 'schedule' &&
          removedScheduleIds.contains(
            task.id.toString().replaceAll('schedule_', ''),
          );

      tasks.removeWhere(isRemovedScheduleTask);
      coreTasks.removeWhere(isRemovedScheduleTask);
      _activeTodayTasks.removeWhere(isRemovedScheduleTask);
    });

    await _saveSchedules();
    await _persistTaskCollectionsAfterScheduleDelete();
  }

  Future<void> _persistTaskCollectionsAfterScheduleDelete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'nyang_tasks',
      jsonEncode(tasks.map((t) => t.toJson()).toList()),
    );
    await prefs.setString(
      'nyang_core_tasks',
      jsonEncode(coreTasks.map((t) => t.toJson()).toList()),
    );
    if (_isViewingActualToday) {
      await _saveTodayRecord();
      await WidgetSyncService.syncFromStoredTasks();
    }
    NotificationService().syncCoreReminders();
    widget.onProgressChanged?.call();
    TasksSyncService.scheduleSyncToCloud();
  }

  Widget _buildTaskStatusButton({
    required TaskItem task,
    required bool isMilestone,
    required bool showTapHint,
  }) {
    final isDone = task.done;
    final isActive = task.inProgress && !isDone;
    // 잠깐 멈춘 것과 아직 시작도 안 한 것은 눈으로 갈라져야 한다. 둘 다 재생
    // 모양이라, 색까지 같으면 어디까지 했는지 알 수 없다.
    final isPaused = task.hasTimer && task.isPaused;
    final accent = isMilestone ? const Color(0xFF5AD7B0) : _coach.accentColor;
    // 타이머가 없는 할 일은 예전 그대로다. 시작 전과 진행 중을 재생/일시정지로
    // 나누면 버튼이 상태를 말하는지 할 일을 말하는지 헷갈려서, 모양은 재생으로
    // 두고 불이 들어오는 것으로만 구분한다.
    //
    // 타이머가 붙은 할 일은 다르다. 누르면 멈춘다는 걸 미리 알려줘야 잠깐
    // 쉬려는 사람이 마음 놓고 누른다. 그래서 진행 중에는 일시정지 모양을 낸다.
    final icon = isDone
        ? Icons.check_rounded
        : (task.hasTimer && isActive)
        ? Icons.pause_rounded
        : Icons.play_arrow_rounded;
    final foreground = isDone
        ? Colors.white
        : isPaused
        ? Colors.white
        : isActive
        ? accent
        : const Color(0xFFB4B7C4);
    final background = isDone
        ? accent.withValues(alpha: 0.34)
        : isPaused
        ? accent
        : isActive
        ? accent.withValues(alpha: 0.14)
        : const Color(0xFFF4F4F7);
    final borderColor = isDone || isPaused
        ? Colors.transparent
        : isActive
        ? accent.withValues(alpha: 0.38)
        : Colors.transparent;

    // 아직 안 누른 버튼에만 그림자를 깐다. 눌러야 할 것이 튀어나와 보이는 게
    // 이 화면에서 제일 자주 하는 동작이다. 진행 중과 완료는 이미 끝난 조작이라
    // 평평하게 두어 눌러야 할 것과 구분한다.
    final shadow = isDone || isActive || isPaused
        ? null
        : const [
            BoxShadow(
              color: Color(0x1F9A9AB5),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(isDone ? 12 : 10),
        border: Border.all(color: borderColor),
        boxShadow: shadow,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(icon, size: 27, color: foreground),
          if (showTapHint && !isDone && !isActive)
            Positioned(
              right: 7,
              top: 7,
              child: _buildCheckboxTapHintDot(size: 5),
            ),
        ],
      ),
    );
  }

  /// 흐르는 동안에는 분:초로, 끝난 뒤에는 사람이 말하듯 적는다.
  ///
  /// 진행 중에 "24분"만 보이면 초가 멈춘 것처럼 보여서 재고 있는지 알 수 없다.
  /// 반대로 끝난 뒤의 "24:13"은 시각처럼 읽혀서, 그때는 말로 풀어 쓴다.
  String _formatElapsed(int seconds, {bool spelled = false}) {
    final safe = seconds < 0 ? 0 : seconds;
    if (spelled) {
      final m = safe ~/ 60;
      final s = safe % 60;
      if (m == 0) return '$s초';
      if (s == 0) return '$m분';
      return '$m분 $s초';
    }
    final m = safe ~/ 60;
    final s = safe % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Widget _buildTaskItem(TaskItem t, {bool showCheckboxTapHint = false}) {
    final milestoneInfo = _getMilestoneInfoForTask(t);
    final isMilestone = milestoneInfo != null;
    final isInsightTask = _isInsightTask(t);
    final displayTitle = isInsightTask
        ? _cleanInsightTaskTitle(t.text)
        : t.text;
    final displayTime = _displayTimeFromStored(
      time: t.time,
      timeStart: t.timeStart,
      timeEnd: t.timeEnd,
    );
    final timeInfo = displayTime ?? t.duration;
    final hasReminder =
        t.isReminderEnabled &&
        _isCoreReminderEnabledGlobally &&
        displayTime != null;
    final isRecurringSchedule = _isRecurringScheduleTask(t);
    // 시간 자리에 "실행 / 예정"을 보여준다. 아직 한 번도 누르지 않았으면 예정만
    // 두어, 시작 전 카드가 예전과 똑같아 보이게 한다.
    final showElapsed =
        _showTaskTimer &&
        t.hasTimer &&
        (t.done || t.inProgress || t.elapsedSeconds > 0);
    final elapsedLabel = showElapsed
        ? _formatElapsed(t.elapsedSecondsAt(DateTime.now()))
        : null;

    // 배너를 눌러 들어온 사람에게 어느 칸인지 알려주는 동안만 켜진다.
    //
    // id는 숫자일 때도 있고 'habit_' 같은 문자열일 때도 있다. 문자열로 맞춰
    // 다룬다 — 배너가 남겨두는 값도, 자리표를 담는 곳도 문자열이다.
    final taskKey = t.id.toString();
    final isBannerFocused = _bannerFocusTaskId == taskKey && _bannerFocusOn;

    final card = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          // 번쩍일 칸에만 자리표를 단다. 모든 칸에 상시로 달아두면 화면이
          // 넘어가는 동안 같은 자리표가 두 곳에 있게 되어 그리기가 통째로 멈춘다.
          key: _bannerFocusTaskId == taskKey
              ? _bannerFocusKeys.putIfAbsent(taskKey, GlobalKey.new)
              : null,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: isBannerFocused
                ? Border.all(color: const Color(0xFFB9A7FF), width: 2)
                : (t.done || t.inProgress)
                ? Border.all(
                    color: t.inProgress
                        ? _coach.accentColor.withOpacity(0.5)
                        : const Color(0xFFE8E3F8),
                  )
                : null,
            // 진행 중일 때 깔던 진한 glow는 걷었다. 가장자리 빛은 이제
            // [_ActiveCardEdge]가 그리고, 그쪽은 훨씬 옅게 번진다.
            boxShadow: (t.inProgress || t.done)
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
              // 상태 버튼: 시작 전 -> 진행 중 -> 완료를 한 자리에서 처리한다.
              GestureDetector(
                onTap: () {
                  _markTaskCheckboxHintSeen();
                  _toggleTask(t.id);
                },
                child: SizedBox(
                  width: 72,
                  height: 58,
                  child: Center(
                    child: _buildTaskStatusButton(
                      task: t,
                      isMilestone: isMilestone,
                      showTapHint: showCheckboxTapHint,
                    ),
                  ),
                ),
              ),
              // 텍스트와 메타데이터
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (isMilestone) {
                      if (milestoneInfo.isMilestoneSelf) {
                        _showVisionModal(milestoneInfo.vision);
                      } else {
                        _showMemoDialog(
                          context,
                          milestoneInfo.milestone,
                          (fn) => setState(fn),
                        );
                      }
                      return;
                    }
                    _showEditItemModal(t, () {
                      setState(() {
                        final cIdx = coreTasks.indexWhere(
                          (ct) => ct.id == t.id,
                        );
                        if (cIdx != -1) {
                          _copyTaskEdits(coreTasks[cIdx], t);
                        }

                        final activeTaskIdx = _activeTodayTasks.indexWhere(
                          (task) => task.id.toString() == t.id.toString(),
                        );
                        if (activeTaskIdx != -1) {
                          _copyTaskEdits(_activeTodayTasks[activeTaskIdx], t);
                        }

                        // 오늘 탭에 주입된 일정 카드를 수정한 경우, 원본 ScheduleItem에도
                        // 반영해야 _injectTodaySchedules()가 다시 실행될 때 수정 내용이
                        // 덮어써지지 않는다.
                        if (t.category == 'schedule') {
                          final scheduleItem = _scheduleItemForTask(t);
                          if (scheduleItem != null) {
                            _copyTaskEditsToSchedule(scheduleItem, t);
                          }
                        }

                        // 오늘 탭에 주입된 습관 카드를 수정한 경우도 마찬가지로 원본
                        // HabitItem에 반영해야 _injectTodayHabits()가 다시 실행될 때
                        // 수정 내용이 덮어써지지 않는다.
                        if (t.category == 'habit' && t.habitId != null) {
                          final hIdx = habits.indexWhere(
                            (h) => h.id.toString() == t.habitId.toString(),
                          );
                          if (hIdx != -1) {
                            habits[hIdx].name = t.text;
                            habits[hIdx].timeStart = t.timeStart;
                            habits[hIdx].timeEnd = t.timeEnd;
                            habits[hIdx].habitDuration = t.duration;
                            habits[hIdx].timeType = t.timeStart != null
                                ? (t.timeEnd != null ? 'range' : 'single')
                                : (t.duration != null ? 'duration' : 'none');
                          }
                        }
                      });
                      _saveTasks();
                      _saveCoreTasks();
                      if (t.category == 'schedule') _saveSchedules();
                      if (t.category == 'habit') _saveHabits();
                    });
                  },
                  child: Container(
                    color: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment:
                              (timeInfo != null || elapsedLabel != null)
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    displayTitle,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: t.done
                                          ? const Color(0xFFA0A0B0)
                                          : const Color(0xFF3D3A4E),
                                      decoration: null,
                                    ),
                                  ),
                                  if (timeInfo != null ||
                                      elapsedLabel != null) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (hasReminder) ...[
                                          Icon(
                                            Icons.notifications_active,
                                            size: 13,
                                            color: _coach.accentColor,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        const Icon(
                                          Icons.access_time_rounded,
                                          size: 14,
                                          color: Color(0xFFA0A0B0),
                                        ),
                                        const SizedBox(width: 4),
                                        if (elapsedLabel != null && t.done) ...[
                                          Text(
                                            '실행 ${_formatElapsed(t.actualSeconds ?? 0, spelled: true)}',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFFA0A0B0),
                                            ),
                                          ),
                                        ] else ...[
                                          if (elapsedLabel != null)
                                            Text(
                                              elapsedLabel,
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: _coach.accentColor,
                                              ),
                                            ),
                                          // 예정시간이 없으면 흐르는 시간만 둔다.
                                          // 빈 자리에 사선만 남으면 뭘 빼먹은
                                          // 것처럼 보인다.
                                          if (elapsedLabel != null &&
                                              timeInfo != null)
                                            Text(
                                              ' / ',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFFC4C4CE),
                                              ),
                                            ),
                                          if (timeInfo != null)
                                            Text(
                                              timeInfo,
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: const Color(0xFFA0A0B0),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (t.isHabit ||
                                isInsightTask ||
                                isRecurringSchedule ||
                                (isMilestone &&
                                    !milestoneInfo.isMilestoneSelf)) ...[
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: t.isHabit
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _coach.accentColor
                                                .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            _habitTaskBadgeLabel(t),
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _coach.accentColor,
                                            ),
                                          ),
                                        )
                                      : isRecurringSchedule
                                      ? const Icon(
                                          Icons.repeat_rounded,
                                          size: 19,
                                          color: Color(0xFFA0A0B0),
                                        )
                                      : isInsightTask
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _coach.accentColor
                                                .withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'insight',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _coach.accentColor,
                                            ),
                                          ),
                                        )
                                      : isMilestone &&
                                            !milestoneInfo.isMilestoneSelf
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3F4F6),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            '메모장',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: const Color(0xFF8B8A96),
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 카드 아래 8은 여백이라 빛이 거기까지 내려오면 안 된다.
        if (t.inProgress)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: 8,
            child: IgnorePointer(
              child: _ActiveCardEdge(accent: _coach.accentColor, radius: 14),
            ),
          ),
      ],
    );

    if (!t.hasTimer || t.done) return card;
    return _buildSwipeToCompleteCard(task: t, card: card);
  }

  /// 타이머형 카드를 오른쪽으로 밀면 완료되게 감싼다.
  ///
  /// 왼쪽 버튼이 시작·일시정지만 하게 되면서 완료할 자리가 없어졌다. 완료를
  /// 버튼 하나 더로 두지 않고 밀기로 뺀 것은, 잠깐 멈추려다 끝내버리는 실수를
  /// 없애려는 것이다. 두 동작이 손끝에서 완전히 다르면 헷갈리지 않는다.
  Widget _buildSwipeToCompleteCard({
    required TaskItem task,
    required Widget card,
  }) {
    final accent = _coach.accentColor;
    // 카드에 "밀어서 완료"를 상시로 붙여두면 목록이 안내문으로 지저분해진다.
    // 그 말은 밀 때 드러나는 이 패널로 옮겼다. 처음 시작을 누르면 카드가 한 번
    // 저절로 밀려서 이 패널을 보여주므로, 한 번은 반드시 읽히게 된다.
    Widget completePanel() => Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 6),
          Text(
            '완료',
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );

    final isHinting = _swipeHintTaskId?.toString() == task.id.toString();

    return Dismissible(
      key: ValueKey('task-swipe-${task.id}'),
      direction: DismissDirection.startToEnd,
      // 끝까지 밀어야 완료된다. 스치듯 지나간 손짓으로 끝나버리면, 멈추려다
      // 완료시키는 실수를 막으려고 밀기로 뺀 뜻이 없어진다.
      dismissThresholds: const {DismissDirection.startToEnd: 0.55},
      background: completePanel(),
      confirmDismiss: (_) async {
        await _toggleTask(task.id, forceComplete: true);
        // 카드는 그 자리에 남고 완료 모양으로 바뀐다. 목록에서 사라지는 건
        // 완료 목록으로 옮기는 쪽이 정하지, 이 제스처가 정하지 않는다.
        return false;
      },
      child: GestureDetector(
        onLongPress: () => _showSwipeHint(task.id),
        child: AnimatedBuilder(
          animation: _swipeHintCtrl,
          builder: (context, child) {
            final dx = isHinting
                ? 54 * Curves.easeOutCubic.transform(_swipeHintCtrl.value)
                : 0.0;
            return Stack(
              children: [
                if (dx > 0) Positioned.fill(child: completePanel()),
                Transform.translate(offset: Offset(dx, 0), child: child),
              ],
            );
          },
          child: card,
        ),
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
            // 시간 설정 UI: 기본은 접고, 입력창의 시계 버튼을 눌렀을 때만 표시한다.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: !_showTodayTimeOptions
                  ? const SizedBox.shrink()
                  : Container(
                      key: const ValueKey('today-time-options'),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: ['single', 'duration'].map((t) {
                              final labels = {
                                'single': '특정 시간',
                                'duration': '소요 시간',
                              };
                              final isClockType =
                                  t == 'single' &&
                                  (_todayTimeType == 'single' ||
                                      _todayTimeType == 'range');
                              final isActive =
                                  isClockType || _todayTimeType == t;
                              final isLast = t == 'duration';
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    _todayReminderEnabled = false;
                                    if (t == 'single') {
                                      _todayTimeType = isClockType
                                          ? 'none'
                                          : 'single';
                                      _todayDuration = null;
                                      if (isClockType) {
                                        _todayStartTime = null;
                                        _todayEndTime = null;
                                      }
                                    } else {
                                      _todayTimeType = _todayTimeType == t
                                          ? 'none'
                                          : t;
                                      _todayStartTime = null;
                                      _todayEndTime = null;
                                    }
                                  }),
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      right: isLast ? 0 : 6,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 9,
                                    ),
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
                          if (_todayTimeType == 'single' ||
                              _todayTimeType == 'range')
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: () async {
                                      final t = await showTimePicker(
                                        context: context,
                                        initialTime:
                                            _todayStartTime ?? TimeOfDay.now(),
                                      );
                                      if (t != null) {
                                        setState(() {
                                          _todayStartTime = t;
                                          _todayReminderEnabled =
                                              _isCoreReminderEnabledGlobally;
                                        });
                                      }
                                    },
                                    child: _timeValueChip(
                                      _todayStartTime != null
                                          ? _formatTime(_todayStartTime!)
                                          : '시작 시간',
                                      active: _todayStartTime != null,
                                    ),
                                  ),
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
                                        initialTime:
                                            _todayEndTime ?? TimeOfDay.now(),
                                      );
                                      if (t != null)
                                        setState(() => _todayEndTime = t);
                                    },
                                    child: _timeValueChip(
                                      _todayEndTime != null
                                          ? _formatTime(_todayEndTime!)
                                          : '종료 시간',
                                      active: _todayEndTime != null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _timeReminderButton(
                                    active: _resolvedTimeReminderEnabled(
                                      _todayTimeType,
                                      _todayStartTime,
                                      _todayReminderEnabled,
                                    ),
                                    onTap: () async {
                                      if (_todayStartTime == null) {
                                        _showSelectTimeBeforeReminderSnackBar();
                                        return;
                                      }
                                      final enabled =
                                          await _ensureCoreReminderEnabledFromHere();
                                      if (!enabled) return;
                                      setState(
                                        () => _todayReminderEnabled =
                                            !_todayReminderEnabled,
                                      );
                                    },
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
                                        onTap: () =>
                                            setState(() => _todayDuration = d),
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                              focusNode: _todayInputFocusNode,
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
                          onTap: () => setState(
                            () =>
                                _showTodayTimeOptions = !_showTodayTimeOptions,
                          ),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _showTodayTimeOptions
                                  ? _coach.accentColor.withOpacity(0.10)
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: SvgPicture.asset(
                                'assets/icons/fa-clock-regular.svg',
                                width: 18,
                                height: 18,
                                colorFilter: ColorFilter.mode(
                                  _showTodayTimeOptions
                                      ? _coach.accentColor
                                      : const Color(0xFF8B7CFF),
                                  BlendMode.srcIn,
                                ),
                              ),
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
    return Container(
      color: Colors.white,
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
                  KeyedSubtree(
                    key: _visionSectionKey,
                    child: _buildVisionSection(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoalSubTab() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFF3F4F6)),
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
    final emptyIcon = type == 'week'
        ? 'assets/icons/calendar-week.svg'
        : 'assets/icons/bullseye.svg';
    final emptyIconColor = _coach.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        if (goals.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: emptyIconColor.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: emptyIconColor.withValues(alpha: 0.18),
                      ),
                    ),
                    child: SvgPicture.asset(
                      emptyIcon,
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        emptyIconColor,
                        BlendMode.srcIn,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
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
    final isAddVisionHighlighted =
        _highlightAddVisionButton && _highlightPulseOn;
    final visionColor = _coach.accentColor;
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
                  Icon(Icons.star_border, color: visionColor, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '장기 비전',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: visionColor,
                    ),
                  ),
                ],
              ),
              GestureDetector(
                key: _addVisionButtonKey,
                onTap: () {
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
                    color: isAddVisionHighlighted
                        ? visionColor.withValues(alpha: 0.10)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isAddVisionHighlighted
                          ? visionColor
                          : const Color(0xFFE8E3F8),
                      width: isAddVisionHighlighted ? 1.6 : 1,
                    ),
                    boxShadow: [
                      if (isAddVisionHighlighted)
                        BoxShadow(
                          color: visionColor.withValues(alpha: 0.22),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                    ],
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
              final isHighlighted =
                  _highlightedVisionIds.contains(v.id) && _highlightPulseOn;
              return GestureDetector(
                key: _visionCardKey(v.id),
                onTap: () {
                  _showVisionModal(v);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isHighlighted
                        ? visionColor.withValues(alpha: 0.10)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isHighlighted ? visionColor : Colors.transparent,
                      width: 1.6,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isHighlighted
                            ? visionColor.withValues(alpha: 0.26)
                            : Colors.black.withOpacity(0.03),
                        blurRadius: isHighlighted ? 18 : 10,
                        offset: Offset(0, isHighlighted ? 6 : 4),
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
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF3D3A4E),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: visionColor,
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: visionColor.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${v.deadline.year}년 ${v.deadline.month}월 ${v.deadline.period}까지',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: visionColor,
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

  void _showMilestoneLimitDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '마일스톤이 10개에 도달했습니다.',
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3D3A4E),
          ),
        ),
        content: Text(
          '새로운 마일스톤을 추가하려면 사용하지 않는 마일스톤을 정리해 주세요.',
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            height: 1.55,
            color: const Color(0xFF6B7280),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '확인',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF8B7CFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMemoDialog(
    BuildContext context,
    MilestoneItem milestone,
    StateSetter setModalState, {
    VoidCallback? onPersist,
  }) {
    final coach = CoachConfigs.get(widget.coachId);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return MilestoneMemoDialog(
          milestone: milestone,
          coach: coach,
          onSave: (_) {
            setModalState(() {});
            if (onPersist != null) {
              onPersist();
            } else {
              _saveVisions();
            }
          },
          onConvertAction: (action, type) {
            if (type == 'task_today') {
              final String todayStr = DateFormat(
                'yyyy-MM-dd',
              ).format(DateTime.now());
              final newTask = TaskItem(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                text: _cleanInsightTaskTitle(action.title),
                category: 'today',
                done: false,
                createdAt: todayStr,
                source: 'insight',
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
              _injectTodayHabits();
              action.convertedHabitId = newHabit.id;
              action.convertedType = 'habit';
              action.convertedDate = DateFormat(
                'yyyy.MM.dd',
              ).format(DateTime.now());
            }
            if (onPersist != null) {
              onPersist();
            } else {
              _saveVisions(); // Save the updated milestone actions
            }
          },
        );
      },
    );
  }

  void _showVisionModal([VisionItem? vision]) {
    final isNew = vision == null;
    final nameCtrl = TextEditingController(text: vision?.name ?? '');
    String selectedYear = vision?.deadline.year ?? '${DateTime.now().year + 1}';
    String selectedMonth = vision?.deadline.month ?? '1';
    String selectedPeriod = vision?.deadline.period ?? '말';
    final draftToPersistedMilestone = <MilestoneItem, MilestoneItem>{};
    final List<MilestoneItem> milestones;
    if (vision != null) {
      milestones = vision.milestones.map((persistedMilestone) {
        final draft = MilestoneItem.fromJson(persistedMilestone.toJson());
        draftToPersistedMilestone[draft] = persistedMilestone;
        return draft;
      }).toList();
    } else {
      milestones = [
        MilestoneItem(text: ''),
        MilestoneItem(text: ''),
        MilestoneItem(text: ''),
      ];
    }

    void persistMilestoneMemo(MilestoneItem draft) {
      final persisted = draftToPersistedMilestone[draft];
      if (persisted == null) return;
      setState(() {
        persisted.memo = draft.memo;
        persisted.memoSections = draft.memoSections
            ?.map((section) => MemoSection.fromJson(section.toJson()))
            .toList();
        persisted.actionCandidates = draft.actionCandidates
            ?.map((action) => ActionCandidate.fromJson(action.toJson()))
            .toList();
        vision!.updatedAt = DateTime.now().toIso8601String();
      });
      _saveVisions();
    }

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
            final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + safeBottom,
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
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
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
                            const SizedBox(height: 28),
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
                                    if (milestones.length >=
                                        _maxMilestonesPerVision) {
                                      _showMilestoneLimitDialog();
                                      return;
                                    }
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
                                                      onPersist: () =>
                                                          persistMilestoneMemo(
                                                            m,
                                                          ),
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
                                                    final confirm =
                                                        await _showConfirmDialog(
                                                          '마일스톤 삭제',
                                                          '이 마일스톤을 정말 삭제하시겠습니까?\n삭제된 내용은 복구할 수 없습니다.',
                                                        );
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
                                                    onPersist: () =>
                                                        persistMilestoneMemo(m),
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
                                                          ? '완료 취소 (시작 전으로)'
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
                      padding: EdgeInsets.fromLTRB(24, 20, 24, 20 + safeBottom),
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
                                  final confirm = await _showConfirmDialog(
                                    '장기 비전 삭제',
                                    '이 비전을 정말 삭제하시겠습니까?\\n하위 마일스톤들도 모두 함께 삭제됩니다.',
                                  );
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
                                if (milestones.length >
                                    _maxMilestonesPerVision) {
                                  _showMilestoneLimitDialog();
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
                                        desc: '',
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
                                        desc: '',
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

  // ── 캘린더 탭 ───────────────────────────────
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
    final rawTime = time?.trim();
    if (rawTime != null && rawTime.isNotEmpty) {
      final rangeParts = rawTime.split('~').map((part) => part.trim()).toList();
      if (rangeParts.length == 2) {
        final start = _parseStoredTime(rangeParts[0]);
        final end = _parseStoredTime(rangeParts[1]);
        if (start != null && end != null) {
          return '${_formatTime(start)} ~ ${_formatTime(end)}';
        }
      }
      final parsed = _parseStoredTime(rawTime);
      if (parsed != null) return _formatTime(parsed);
      return rawTime;
    }

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

  Widget _timeValueChip(String label, {required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.notoSansKr(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: active ? _coach.accentColor : const Color(0xFFA0A0B0),
        ),
      ),
    );
  }

  Widget _timeReminderButton({
    required bool active,
    Future<void> Function()? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? _coach.accentColor.withValues(alpha: 0.12)
              : const Color(0xFFF8F7FF),
          border: Border.all(
            color: active ? _coach.accentColor : const Color(0xFFE5E7EB),
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.notifications_active : Icons.notifications_off,
              size: 16,
              color: active ? _coach.accentColor : const Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 4),
            Text(
              active ? '알림 켜짐' : '알림 켜기',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: active ? _coach.accentColor : const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeReminderActiveBadge() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: _coach.accentColor.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _coach.accentColor.withValues(alpha: 0.18),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        Icons.notifications_active,
        size: 17,
        color: _coach.accentColor,
      ),
    );
  }

  void _showSelectTimeBeforeReminderSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('알림을 켜려면 시간을 먼저 선택해주세요.'),
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

  String _effectiveClockTimeType(String timeType, TimeOfDay? endTime) {
    if (timeType == 'single' || timeType == 'range') {
      return endTime != null ? 'range' : 'single';
    }
    return timeType;
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

    final effectiveTimeType = _effectiveClockTimeType(timeType, endTime);

    if (effectiveTimeType == 'single' && startTime != null) {
      entry.timeStart = _storedTime(startTime);
      entry.time = _formatTime(startTime);
    } else if (effectiveTimeType == 'range' && startTime != null) {
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
          children: ['single', 'duration'].map((t) {
            final labels = {'single': '특정 시간', 'duration': '소요 시간'};
            final isClockType =
                t == 'single' && (timeType == 'single' || timeType == 'range');
            final isActive = isClockType || timeType == t;
            final isLast = t == 'duration';
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  if (t == 'single') {
                    setTimeType(isClockType ? 'none' : 'single');
                    setDuration(null);
                    if (isClockType) {
                      setStartTime(null);
                      setEndTime(null);
                    }
                  } else {
                    setTimeType(timeType == t ? 'none' : t);
                    setStartTime(null);
                    setEndTime(null);
                  }
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
                GestureDetector(
                  onTap: () async {
                    final t = await showTimePicker(
                      context: context,
                      initialTime: startTime ?? TimeOfDay.now(),
                    );
                    if (t != null) setStartTime(t);
                  },
                  child: _timeValueChip(
                    startTime != null ? _formatTime(startTime) : '시작 시간',
                    active: startTime != null,
                  ),
                ),
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
                      initialTime: endTime ?? TimeOfDay.now(),
                    );
                    if (t != null) setEndTime(t);
                  },
                  child: _timeValueChip(
                    endTime != null ? _formatTime(endTime) : '종료 시간',
                    active: endTime != null,
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

  void _replaceFutureRecurringSchedules(
    ScheduleItem source,
    Map<String, dynamic> rule,
  ) {
    String? currentDateKey;
    schedules.forEach((dateKey, items) {
      if (currentDateKey != null) return;
      if (items.any((item) => item.id == source.id)) {
        currentDateKey = dateKey;
      }
    });
    if (currentDateKey == null) return;

    final currentDate = DateTime.tryParse(currentDateKey!);
    if (currentDate == null) return;

    final recurrenceGroupId =
        source.recurrenceGroupId ??
        'repeat_${DateTime.now().millisecondsSinceEpoch}';
    final repeatRule = {...rule, 'startDate': currentDateKey};

    final emptyDateKeys = <String>[];
    schedules.forEach((dateKey, items) {
      if (dateKey.compareTo(currentDateKey!) < 0) return;
      items.removeWhere(
        (item) =>
            item.id == source.id ||
            (item.recurrenceGroupId != null &&
                item.recurrenceGroupId == recurrenceGroupId),
      );
      if (items.isEmpty) emptyDateKeys.add(dateKey);
    });
    for (final dateKey in emptyDateKeys) {
      schedules.remove(dateKey);
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final repeatDates = _datesForScheduleRepeat(currentDate, rule);
    for (var i = 0; i < repeatDates.length; i++) {
      final dateKey = _dateKey(repeatDates[i]);
      schedules.putIfAbsent(dateKey, () => []);
      schedules[dateKey]!.add(
        ScheduleItem(
          id: i == 0 ? source.id : '${nowMs}_edit_$i',
          text: source.text,
          time: source.time,
          timeStart: source.timeStart,
          timeEnd: source.timeEnd,
          duration: source.duration,
          done: i == 0 ? source.done : false,
          createdAt: source.createdAt,
          isReminderEnabled: source.isReminderEnabled,
          deferredCount: i == 0 ? source.deferredCount : 0,
          isRecurring: true,
          recurrenceGroupId: recurrenceGroupId,
          recurrenceRule: repeatRule,
        ),
      );
    }
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

  Future<void> _addSchedule() async {
    if (!await _ensurePlanForTaskInput()) return;
    final text = _schInputCtrl.text.trim();
    if (text.isEmpty) return;
    final cleaned = text.replaceAll(RegExp(r'[.\s]+$'), '');
    final commandSuffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요)|추가해\s*(?:줘요?|주세요)|넣어\s*(?:줘요?|주세요))$',
    );
    if (commandSuffixRegex.hasMatch(cleaned)) {
      _showVoiceRegistrationConfirmDialog(text, isToday: false);
      return;
    }

    final effectiveScheduleTimeType = _effectiveClockTimeType(
      _schTimeType,
      _schEndTime,
    );
    final hasClockTime =
        (effectiveScheduleTimeType == 'single' ||
            effectiveScheduleTimeType == 'range') &&
        _schStartTime != null;
    final autoEnabledTimedReminder = hasClockTime
        ? await _prepareTimedScheduleStartReminder()
        : false;
    final reminderGloballyEnabled =
        autoEnabledTimedReminder || await _checkCoreReminderEnabledGlobally();
    final shouldEnableReminder =
        reminderGloballyEnabled &&
        hasClockTime &&
        (_schReminderEnabled || autoEnabledTimedReminder);

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
        isReminderEnabled: shouldEnableReminder,
        isRecurring: repeatRule != null,
        recurrenceGroupId: recurrenceGroupId,
        recurrenceRule: repeatRule == null
            ? null
            : {...repeatRule, 'startDate': _dateKey(_calSelectedDay)},
      );

      if (effectiveScheduleTimeType == 'single' && _schStartTime != null) {
        entry.timeStart = _storedTime(_schStartTime!);
        entry.time = _formatTime(_schStartTime!);
      } else if (effectiveScheduleTimeType == 'range' &&
          _schStartTime != null) {
        entry.timeStart = _storedTime(_schStartTime!);
        if (_schEndTime != null) {
          entry.timeEnd = _storedTime(_schEndTime!);
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

  String _cleanRegistrationTitle(String input) {
    var cleaned = input.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceAll(RegExp(r'^(?:나|나는|내가|저|저는)\s+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^(?:앞으로|이제)\s+'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(?:할\s*건데|할건데|할\s*건대|할\s*거야|할거야|할게|하려고|하려구|할래|할\s*래|하기)$'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s*(?:일정|스케줄)$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = cleaned.replaceFirst(RegExp(r'(?:을|를|은|는|이|가)$'), '').trim();
    return cleaned;
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
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요)|추가해\s*(?:줘요?|주세요)|넣어\s*(?:줘요?|주세요))$',
    );
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

    // 2. Check "이번주/다음주/담주/다다음주 [요일]"
    if (!hasDate) {
      final weekRelRegex = RegExp(r'(이번주|다음주|담주|다다음주)\s+([월화수목금토일])(?:요일)?');
      final weekRelMatch = weekRelRegex.firstMatch(cleaned);
      if (weekRelMatch != null) {
        final rel = weekRelMatch.group(1)!;
        final weekdayStr = weekRelMatch.group(2)!;
        final targetWeekday = _weekdayFromKorean(weekdayStr);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          int diff = targetWeekday - now.weekday;
          int weeksAdd = 0;
          if (rel == '다음주' || rel == '담주') weeksAdd = 7;
          if (rel == '다다음주') weeksAdd = 14;
          parsedDate = now.add(Duration(days: diff + weeksAdd));
          hasDate = true;
          cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
        }
      }
    }

    // 3. Check "오늘", "내일", "모레", "내일모레", "글피", "그글피"
    if (!hasDate) {
      final dayAfterTomorrowRegex = RegExp(r'(?:내일\s*모레|내일모레|낼\s*모레|낼모레)');
      if (cleaned.contains('그글피')) {
        parsedDate = DateTime.now().add(const Duration(days: 4));
        hasDate = true;
        cleaned = cleaned.replaceAll('그글피', '').trim();
      } else if (cleaned.contains('글피')) {
        parsedDate = DateTime.now().add(const Duration(days: 3));
        hasDate = true;
        cleaned = cleaned.replaceAll('글피', '').trim();
      } else if (dayAfterTomorrowRegex.hasMatch(cleaned)) {
        parsedDate = DateTime.now().add(const Duration(days: 2));
        hasDate = true;
        cleaned = cleaned.replaceFirst(dayAfterTomorrowRegex, '').trim();
      } else if (cleaned.contains('오늘')) {
        parsedDate = DateTime.now();
        hasDate = true;
        cleaned = cleaned.replaceAll('오늘', '').trim();
      } else if (cleaned.contains('모레')) {
        parsedDate = DateTime.now().add(const Duration(days: 2));
        hasDate = true;
        cleaned = cleaned.replaceAll('모레', '').trim();
      } else if (cleaned.contains('내일')) {
        parsedDate = DateTime.now().add(const Duration(days: 1));
        hasDate = true;
        cleaned = cleaned.replaceAll('내일', '').trim();
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

    cleaned = _cleanRegistrationTitle(cleaned);

    return ParsedVoiceRegistration(
      title: cleaned.isEmpty ? "새 캘린더 일정" : cleaned,
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
                            SvgPicture.asset(
                              'assets/icons/thumbtack.svg',
                              width: 15,
                              height: 15,
                              colorFilter: ColorFilter.mode(
                                _coach.accentColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '캘린더 일정 등록 제안',
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
                              color: _coach.accentColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/planner-calendar-days.svg',
                                  width: 13,
                                  height: 13,
                                  colorFilter: ColorFilter.mode(
                                    _coach.accentColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _getVoiceDateLabel(confirmedDate),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
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
                              final enabled =
                                  await _checkCoreReminderEnabledGlobally();
                              setDialogState(() {
                                confirmedTime = t;
                                isReminderEnabled = enabled;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: _coach.accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/fa-clock-regular.svg',
                                  width: 13,
                                  height: 13,
                                  colorFilter: ColorFilter.mode(
                                    _coach.accentColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  confirmedTime != null
                                      ? _getVoiceTimeLabel(confirmedTime!)
                                      : "시간 설정 안 함",
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: _coach.accentColor,
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
                              color: _coach.accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _coach.accentColor.withValues(
                                  alpha: 0.25,
                                ),
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
                        if (confirmedTime == null) {
                          _showSelectTimeBeforeReminderSnackBar();
                          return;
                        }
                        if (!isReminderEnabled) {
                          final globalEnabled =
                              await _ensureCoreReminderEnabledFromHere();
                          if (!globalEnabled) return;
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
                            color: _coach.accentColor,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              isReminderEnabled
                                  ? 'assets/icons/bell.svg'
                                  : 'assets/icons/bell-slash.svg',
                              width: 13,
                              height: 13,
                              colorFilter: ColorFilter.mode(
                                _coach.accentColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isReminderEnabled ? '알람 ON' : '알람 OFF',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _coach.accentColor,
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
                              backgroundColor: _coach.accentColor,
                              foregroundColor: _accentButtonTextColor,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () async {
                              final finalTitle = titleCtrl.text.trim();
                              if (finalTitle.isEmpty) return;
                              final navigator = Navigator.of(ctx);
                              final messenger = ScaffoldMessenger.of(context);
                              final autoEnabledTimedReminder =
                                  confirmedTime != null
                                  ? await _prepareTimedScheduleStartReminder()
                                  : false;
                              final reminderGloballyEnabled =
                                  autoEnabledTimedReminder ||
                                  await _checkCoreReminderEnabledGlobally();

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
                                        (isReminderEnabled ||
                                            autoEnabledTimedReminder) &&
                                        reminderGloballyEnabled &&
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
                                    entry.timeStart = _storedTime(
                                      confirmedTime!,
                                    );
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
                              navigator.pop();
                              messenger.showSnackBar(
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
          final mId = _milestoneTaskId(v, m);
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
                  (item is ScheduleItem &&
                      actTaskIdStr == item.id.toString())) {
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
    final hasEvents = _hasScheduleTabEvents(day);
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
                color: _coach.accentColor,
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
    return Container(
      color: Colors.white,
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
                final key = _dateKey(day);
                return <Object>[
                  ...?schedules[key],
                  ..._plannedTodayTasksForDate(day),
                ];
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
                markerBuilder: (context, day, events) =>
                    const SizedBox.shrink(),
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

  Widget _scheduleItemTrailingIcons({
    required bool isRecurring,
    required bool isReminderEnabled,
    Map<String, dynamic>? recurrenceRule,
  }) {
    final children = <Widget>[];
    if (isRecurring) {
      children.add(
        Tooltip(
          message: _repeatRuleLabel(recurrenceRule),
          child: Icon(
            Icons.repeat_rounded,
            size: 17,
            color: _coach.accentColor.withOpacity(0.72),
          ),
        ),
      );
    }
    if (isReminderEnabled) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 7));
      children.add(
        Icon(
          Icons.notifications_active,
          size: 17,
          color: _coach.accentColor.withOpacity(0.72),
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  Widget _scheduleMetaInfoRow({
    String? displayTime,
    String? duration,
    EdgeInsets padding = const EdgeInsets.only(top: 6),
  }) {
    final hasDisplayTime = displayTime != null && displayTime.trim().isNotEmpty;
    final hasDuration = duration != null && duration.trim().isNotEmpty;
    if (!hasDisplayTime && !hasDuration) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (hasDisplayTime) ...[
            const Icon(Icons.access_time, size: 16, color: Color(0xFF9CA3AF)),
            const SizedBox(width: 4),
            Text(
              displayTime,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
          if (hasDisplayTime && hasDuration) const SizedBox(width: 10),
          if (hasDuration) ...[
            const Icon(
              Icons.timer_outlined,
              size: 16,
              color: Color(0xFF9CA3AF),
            ),
            const SizedBox(width: 4),
            Text(
              duration,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9CA3AF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 일정 항목 사이를 노골적인 카드 테두리 대신 은은한 그라데이션으로 구분한다.
  Widget _scheduleGradientDivider() {
    return Container(
      height: 1.2,
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0x00B9A9F0), Color(0x4DB9A9F0), Color(0x00B9A9F0)],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
    );
  }

  Widget _buildScheduleListOnly() {
    final dateStr = _dateKey(_calSelectedDay);
    final daySch = schedules[dateStr] ?? [];
    final dayPlannedTasks = _plannedTodayTasksForDate(_calSelectedDay);
    final dayMilestones = _getMilestonesForDay(_calSelectedDay);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),

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
              final milestoneColor = _coach.accentColor;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: milestoneColor.withValues(alpha: isDone ? 0.06 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: milestoneColor.withValues(
                      alpha: isDone ? 0.18 : 0.28,
                    ),
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
                              color: isDone ? milestoneColor : Colors.white,
                              border: Border.all(
                                color: milestoneColor,
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
                                : Icon(
                                    Icons.flag,
                                    color: milestoneColor,
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
        if (daySch.isEmpty && dayPlannedTasks.isEmpty && dayMilestones.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                '등록된 캘린더 일정이 없습니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  color: const Color(0xFFA0A0B0),
                ),
              ),
            ),
          )
        else if (daySch.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: daySch.length,
            separatorBuilder: (_, __) => _scheduleGradientDivider(),
            itemBuilder: (ctx, i) {
              final s = daySch[i];
              final milestoneInfo = _getMilestoneInfoForTask(s);
              final isMilestone = milestoneInfo != null;
              final displayTime = _displayTimeFromStored(
                time: s.time,
                timeStart: s.timeStart,
                timeEnd: s.timeEnd,
              );
              return Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: 4,
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
                              color: _coach.accentColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              milestoneInfo.isMilestoneSelf
                                  ? '마일스톤'
                                  : '메모장의 실행 목록',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: _coach.accentColor,
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
                                _showMemoDialog(
                                  context,
                                  milestoneInfo.milestone,
                                  (fn) => setState(fn),
                                );
                              } else {
                                _showEditItemModal(
                                  s,
                                  () {
                                    _saveScheduleTabScheduleEdit(dateStr, s);
                                  },
                                  onDelete: () {
                                    setState(() {
                                      daySch.removeAt(i);
                                      if (daySch.isEmpty) {
                                        schedules.remove(dateStr);
                                      }
                                    });
                                    _saveSchedules();
                                  },
                                );
                              }
                            },
                            child: Container(
                              color: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                s.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF3D3A4E),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _scheduleItemTrailingIcons(
                          isRecurring: s.isRecurring,
                          isReminderEnabled: s.isReminderEnabled,
                          recurrenceRule: s.recurrenceRule,
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () {
                        if (isMilestone) {
                          _showMemoDialog(
                            context,
                            milestoneInfo.milestone,
                            (fn) => setState(fn),
                          );
                        } else {
                          _showEditItemModal(
                            s,
                            () {
                              _saveScheduleTabScheduleEdit(dateStr, s);
                            },
                            onDelete: () {
                              setState(() {
                                daySch.removeAt(i);
                                if (daySch.isEmpty) {
                                  schedules.remove(dateStr);
                                }
                              });
                              _saveSchedules();
                            },
                          );
                        }
                      },
                      child: _scheduleMetaInfoRow(
                        displayTime: displayTime,
                        duration: s.duration,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

        if (dayPlannedTasks.isNotEmpty && daySch.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _scheduleGradientDivider(),
          ),
        if (dayPlannedTasks.isNotEmpty)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16, daySch.isEmpty ? 0 : 0, 16, 0),
            itemCount: dayPlannedTasks.length,
            separatorBuilder: (_, __) => _scheduleGradientDivider(),
            itemBuilder: (ctx, i) {
              final task = dayPlannedTasks[i];
              final displayTime = _displayTimeFromStored(
                time: task.time,
                timeStart: task.timeStart,
                timeEnd: task.timeEnd,
              );
              return GestureDetector(
                onTap: () {
                  _showEditItemModal(
                    task,
                    () {
                      _saveScheduleTabTaskEdit(dateStr, task);
                    },
                    onDelete: () {
                      _deleteScheduleTabTask(dateStr, task);
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.text,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF3D3A4E),
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          _scheduleItemTrailingIcons(
                            isRecurring: false,
                            isReminderEnabled: task.isReminderEnabled,
                          ),
                        ],
                      ),
                      _scheduleMetaInfoRow(
                        displayTime: displayTime,
                        duration: task.duration,
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

  Future<Map<String, dynamic>?> _showScheduleRepeatDialog({
    Map<String, dynamic>? initialRule,
    DateTime? baseDate,
  }) async {
    final sourceRule = initialRule ?? _schRepeatRule;
    final repeatBaseDate = baseDate ?? _calSelectedDay;
    Map<String, dynamic>? appliedRule;
    String repeatType = sourceRule?['type']?.toString() ?? 'weekly';
    String monthlyMode = sourceRule?['monthlyMode']?.toString() ?? 'date';
    final selectedWeekdays =
        ((sourceRule?['weekdays'] as List?)
            ?.map((e) => int.tryParse(e.toString()))
            .whereType<int>()
            .toSet() ??
        {repeatBaseDate.weekday});
    int dayOfMonth =
        int.tryParse(sourceRule?['dayOfMonth']?.toString() ?? '') ??
        repeatBaseDate.day;
    int nth = int.tryParse(sourceRule?['nth']?.toString() ?? '') ?? 1;
    int monthlyWeekday =
        int.tryParse(sourceRule?['weekday']?.toString() ?? '') ??
        repeatBaseDate.weekday;
    String endType = sourceRule?['endType']?.toString() ?? 'never';
    DateTime? endDate = DateTime.tryParse(
      sourceRule?['endDate']?.toString() ?? '',
    );
    final countCtrl = TextEditingController(
      text: sourceRule?['count']?.toString() ?? '10',
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
                                  repeatBaseDate.add(const Duration(days: 30)),
                              firstDate: repeatBaseDate,
                              lastDate: DateTime(repeatBaseDate.year + 5),
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
                                    repeatBaseDate.day;
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
                            appliedRule = rule;
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
    return appliedRule;
  }

  void _showScheduleOptionsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateOptions(VoidCallback update) {
              setState(update);
              setSheetState(() {});
            }

            Widget modeButton(String type) {
              const labels = {
                'single': '특정 시간',
                'duration': '소요 시간',
                'repeat': '반복',
              };
              final isRepeat = type == 'repeat';
              final isClockType =
                  type == 'single' &&
                  (_schTimeType == 'single' || _schTimeType == 'range');
              final isActive = isRepeat
                  ? _schRepeatEnabled
                  : (isClockType || _schTimeType == type);

              return Expanded(
                child: GestureDetector(
                  onTap: () async {
                    if (isRepeat) {
                      final rule = await _showScheduleRepeatDialog();
                      if (rule != null) {
                        updateOptions(() {
                          _schRepeatEnabled = true;
                          _schRepeatRule = rule;
                        });
                      }
                      return;
                    }

                    updateOptions(() {
                      _schReminderEnabled = false;
                      if (type == 'single') {
                        _schTimeType = isClockType ? 'none' : 'single';
                        _schDuration = null;
                        if (isClockType) {
                          _schStartTime = null;
                          _schEndTime = null;
                        }
                      } else {
                        _schTimeType = _schTimeType == type ? 'none' : type;
                        _schStartTime = null;
                        _schEndTime = null;
                      }
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: type == 'repeat' ? 0 : 6),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: isActive
                          ? _coach.accentColor.withValues(alpha: 0.08)
                          : Colors.white,
                      border: Border.all(
                        color: isActive
                            ? _coach.accentColor
                            : const Color(0xFFE5E7EB),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isRepeat) ...[
                          Icon(
                            Icons.repeat_rounded,
                            size: 16,
                            color: isActive
                                ? _coach.accentColor
                                : const Color(0xFF9CA3AF),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            labels[type]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.82,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  20,
                  20,
                  MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).viewPadding.bottom +
                      20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '캘린더 일정 옵션',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.pop(sheetContext),
                          child: const Icon(
                            Icons.close,
                            size: 22,
                            color: Color(0xFFA0A0B0),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        modeButton('single'),
                        modeButton('duration'),
                        modeButton('repeat'),
                      ],
                    ),
                    if (_schTimeType == 'single' || _schTimeType == 'range')
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _schStartTime ?? TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  final enabled =
                                      await _checkCoreReminderEnabledGlobally();
                                  updateOptions(() {
                                    _schStartTime = picked;
                                    _schReminderEnabled = enabled;
                                  });
                                }
                              },
                              child: _scheduleOptionValueChip(
                                _schStartTime != null
                                    ? _formatTime(_schStartTime!)
                                    : '시작 시간',
                                active: _schStartTime != null,
                              ),
                            ),
                            Text(
                              ' ~ ',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF6B7280),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _schEndTime ?? TimeOfDay.now(),
                                );
                                if (picked != null) {
                                  updateOptions(() => _schEndTime = picked);
                                }
                              },
                              child: _scheduleOptionValueChip(
                                _schEndTime != null
                                    ? _formatTime(_schEndTime!)
                                    : '종료 시간',
                                active: _schEndTime != null,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _timeReminderButton(
                              active: _resolvedTimeReminderEnabled(
                                _schTimeType,
                                _schStartTime,
                                _schReminderEnabled,
                              ),
                              onTap: () async {
                                if (_schStartTime == null) {
                                  _showSelectTimeBeforeReminderSnackBar();
                                  return;
                                }
                                final enabled =
                                    await _ensureCoreReminderEnabledFromHere();
                                if (!enabled) return;
                                updateOptions(
                                  () => _schReminderEnabled =
                                      !_schReminderEnabled,
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    if (_schTimeType == 'duration')
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
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
                              ].map((duration) {
                                final active = _schDuration == duration;
                                return GestureDetector(
                                  onTap: () => updateOptions(
                                    () => _schDuration = duration,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? const Color(0xFFFDF2F8)
                                          : Colors.white,
                                      border: Border.all(
                                        color: active
                                            ? const Color(0xFFDB2777)
                                            : const Color(0xFFE5E7EB),
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      duration,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: active
                                            ? const Color(0xFFDB2777)
                                            : const Color(0xFF6B7280),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    if (_schRepeatEnabled) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(
                            Icons.repeat_rounded,
                            size: 16,
                            color: _coach.accentColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _repeatRuleLabel(_schRepeatRule),
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _coach.accentColor,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => updateOptions(() {
                              _schRepeatEnabled = false;
                              _schRepeatRule = null;
                            }),
                            child: Text(
                              '해제',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFA0A0B0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () => Navigator.pop(sheetContext),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _coach.accentColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '완료',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
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

  Widget _scheduleOptionValueChip(String label, {required bool active}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? _coach.accentColor.withValues(alpha: 0.08)
            : Colors.white,
        border: Border.all(
          color: active ? _coach.accentColor : const Color(0xFFE5E7EB),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: active ? _coach.accentColor : const Color(0xFFA0A0B0),
        ),
      ),
    );
  }

  Widget _buildScheduleInputArea() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = bottomInset > 0;
    final paddingBottom = isKeyboardOpen
        ? bottomInset + 16.0
        : (16.0 + MediaQuery.of(context).padding.bottom);
    final hasScheduleOptions =
        _schTimeType != 'none' || _schRepeatEnabled || _schRepeatRule != null;

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
      child: Row(
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
                    child: TextField(
                      controller: _schInputCtrl,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: const Color(0xFF3D3A4E),
                      ),
                      decoration: InputDecoration(
                        hintText: '캘린더 일정 입력...',
                        hintStyle: GoogleFonts.notoSansKr(
                          fontSize: 14,
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
                    onTap: _showScheduleOptionsSheet,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: hasScheduleOptions
                            ? _coach.accentColor.withValues(alpha: 0.10)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/fa-clock-regular.svg',
                          width: 18,
                          height: 18,
                          colorFilter: ColorFilter.mode(
                            hasScheduleOptions
                                ? _coach.accentColor
                                : const Color(0xFF8B7CFF),
                            BlendMode.srcIn,
                          ),
                        ),
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
    );
  }

  // ── 습관 탭 ──────────────────────────────────────────────
  Widget _buildHabitTab() {
    return Container(
      color: Colors.white,
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
                          '루틴을 추가해봐요!',
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
                      '새 루틴 추가',
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
        : h.freq == 'weekly_count'
        ? '주 ${h.weeklyTargetCount ?? 5}일'
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
    final confirm = await _showConfirmDialog(
      '루틴 항목 삭제',
      '이 루틴을 정말 삭제하시겠습니까?\\n연결된 오늘의 할 일도 함께 삭제됩니다.',
    );
    if (!confirm) return;
    setState(() => habits.removeWhere((h) => h.id.toString() == id.toString()));
    _saveHabits();
    _injectTodayHabits();
  }

  String _habitRegistrationGuideText() {
    switch (widget.coachId) {
      case 'boyfriend':
        return '루틴 탭에 추가해뒀어. 세부 설정은 한번 확인하고 너한테 맞게 조정해줘.';
      case 'bro':
        return '루틴 탭에 추가해뒀다. 세부 설정은 한번 보고 너한테 맞게 손봐라.';
      case 'halmae':
        return '루틴 탭에 추가해뒀다. 세부 설정은 잘 보고 네 생활에 맞게 고쳐라.';
      case 'nyang_halbae':
        return '루틴 탭에 추가해두었습니다. 세부 설정을 확인하신 뒤 필요에 맞게 조정해 주세요.';
      case 'sec_female':
        return '루틴 탭에 추가해두었어요. 세부 설정을 확인하신 뒤 편하신 방식으로 조정해 주세요.';
      default:
        return '루틴 탭에 추가해뒀다냥. 세부 설정은 잘 보고 맞게 조정해달라냥.';
    }
  }

  // ── 습관 추가 모달 (웹앱 openHabitModal 이식) ────────────
  Future<void> _showHabitModal(
    BuildContext context, {
    HabitItem? editHabit,
    String? guideText,
  }) async {
    if (!await _ensurePlanForTaskInput()) return;
    final nameCtrl = TextEditingController(text: editHabit?.name ?? '');
    String freq = editHabit?.freq ?? 'daily';
    List<int> days = List.from(editHabit?.days ?? []);
    int weeklyTargetCount = editHabit?.weeklyTargetCount ?? 5;
    bool countSettingEnabled =
        editHabit?.checkType == 'count' || editHabit?.checkType == 'both';
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

    const dayNames = ['월', '화', '수', '목', '금', '토', '일'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).viewPadding.bottom,
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
                      editHabit != null ? '루틴 수정' : '새 루틴 추가',
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
                      if (guideText != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: _coach.accentColor.withOpacity(0.08),
                            border: Border.all(
                              color: _coach.accentColor.withOpacity(0.18),
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            guideText,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              height: 1.45,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                      // 습관 이름
                      _modalLabel('루틴 이름'),
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
                          const SizedBox(width: 8),
                          _freqBtn(
                            'weekly_count',
                            '주 n일',
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
                      if (freq == 'weekly_count') ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(6, (i) {
                            final value = i + 1;
                            final isSelected = weeklyTargetCount == value;
                            return GestureDetector(
                              onTap: () => setModalState(
                                () => weeklyTargetCount = value,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
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
                                child: Text(
                                  '주 $value일',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            );
                          }),
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
                            timeType == 'range' ? 'single' : timeType,
                            (v) => setModalState(() {
                              final isClockType =
                                  timeType == 'single' || timeType == 'range';
                              timeType = isClockType ? 'none' : v;
                              mDuration = null;
                              if (isClockType) {
                                mStartTime = null;
                                mEndTime = null;
                              }
                            }),
                          ),
                          _checkBtn(
                            'duration',
                            '소요 시간',
                            timeType,
                            (v) => setModalState(() {
                              timeType = timeType == v ? 'none' : v;
                              mStartTime = null;
                              mEndTime = null;
                            }),
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
                                        : '시작 시간',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: mStartTime != null
                                          ? _coach.accentColor
                                          : const Color(0xFFA0A0B0),
                                    ),
                                  ),
                                ),
                              ),
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
                                        : '종료 시간',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      color: mEndTime != null
                                          ? _coach.accentColor
                                          : const Color(0xFFA0A0B0),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _timeReminderButton(
                                active:
                                    _isCoreReminderEnabledGlobally &&
                                    mReminderEnabled,
                                onTap: () async {
                                  final enabled =
                                      await _ensureCoreReminderEnabledFromHere();
                                  if (!enabled) return;
                                  setModalState(
                                    () => mReminderEnabled = !mReminderEnabled,
                                  );
                                },
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
                      _modalLabel('수량 설정'),
                      Wrap(
                        spacing: 8,
                        children: [
                          _checkBtn(
                            'none',
                            '없음',
                            countSettingEnabled ? 'enabled' : 'none',
                            (_) => setModalState(
                              () => countSettingEnabled = false,
                            ),
                          ),
                          _checkBtn(
                            'enabled',
                            '있음',
                            countSettingEnabled ? 'enabled' : 'none',
                            (_) =>
                                setModalState(() => countSettingEnabled = true),
                          ),
                        ],
                      ),
                      if (countSettingEnabled) ...[
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
                      const SizedBox(height: 20),
                      // 습관 트래킹
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '루틴 트래킹',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3D3A4E),
                                ),
                              ),
                              Text(
                                '매일 루틴 달성률을 추적할까요?',
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
                    // 적어 넣을 수 있는 기간인지
                    final canInput = await _canInputTasks();
                    if (!mounted || !ctx.mounted) return;
                    if (!canInput) {
                      Navigator.pop(ctx); // 모달 닫기
                      _showSubscriptionNotice(context);
                      return;
                    }

                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    if (freq == 'weekly' && days.isEmpty) return;
                    final effectiveHabitTimeType = _effectiveClockTimeType(
                      timeType,
                      mEndTime,
                    );

                    final habit = HabitItem(
                      id:
                          editHabit?.id ??
                          DateTime.now().millisecondsSinceEpoch,
                      name: name,
                      freq: freq,
                      days: freq == 'weekly' ? List.from(days) : const [],
                      weeklyTargetCount: freq == 'weekly_count'
                          ? weeklyTargetCount
                          : null,
                      checkType: countSettingEnabled ? 'count' : 'check',
                      timeType: effectiveHabitTimeType,
                      tracking: tracking,
                      countGoal: countSettingEnabled
                          ? int.tryParse(countCtrl.text)
                          : null,
                      unit:
                          countSettingEnabled && unitCtrl.text.trim().isNotEmpty
                          ? unitCtrl.text.trim()
                          : null,
                      durationGoal: null,
                      timeStart:
                          (effectiveHabitTimeType == 'single' ||
                                  effectiveHabitTimeType == 'range') &&
                              mStartTime != null
                          ? _storedTime(mStartTime!)
                          : null,
                      timeEnd:
                          effectiveHabitTimeType == 'range' && mEndTime != null
                          ? _storedTime(mEndTime!)
                          : null,
                      habitDuration: effectiveHabitTimeType == 'duration'
                          ? mDuration
                          : null,
                      createdAt:
                          editHabit?.createdAt ??
                          DateTime.now().toIso8601String(),
                      isReminderEnabled: mReminderEnabled,
                    );
                    final showCreationWeekNotice =
                        editHabit == null &&
                        habit.freq == 'weekly_count' &&
                        _weeklyVisibleTargetForDate(habit, DateTime.now()) <
                            _weeklyTargetForHabit(habit);

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
                    if (showCreationWeekNotice && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '이번 주는 남은 날짜에 맞춰 보여주고, 다음 주부터 주 ${_weeklyTargetForHabit(habit)}일로 진행돼요.',
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
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
            PurchaseService.storeCheckoutEnabled
                ? '⚠️ 구독 플랜 필요'
                : '⚠️ 체험 기간 종료',
            style: GoogleFonts.notoSansKr(
              fontWeight: FontWeight.w900,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          content: Text(
            // 살 수 없는 동안에는 구독하라고 하지 않는다. 갈 수 없는 곳을
            // 가리키면 앱이 고장난 것처럼 보인다.
            PurchaseService.storeCheckoutEnabled
                ? '할 일, 일정, 루틴 등록은 Friends 또는 Master 플랜 구독자만 이용할 수 있다냥!'
                : '무료로 써볼 수 있는 기간이 끝났다냥.\n지금까지 적어둔 것은 그대로 볼 수 있어!',
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
  static const int _maxMemoSections = 3;
  static const int _sectionContentMaxLength = 500;
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
    final cCtrl = TextEditingController(text: _limitSectionContent(content));
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
    if (_sections.length >= _maxMemoSections) {
      _showInlineNoticeDialog(
        '메모 묶음이 3개에 도달했습니다.\n\n새로운 메모 묶음을 추가하려면 사용하지 않는 메모 묶음을 정리해 주세요.',
      );
      return;
    }

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

  void _showInlineNoticeDialog(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Text(
          '알림',
          style: GoogleFonts.notoSansKr(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2E2A3D),
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF4F4A60),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B6CFF),
              textStyle: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
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
      _showInlineNoticeDialog('정리할 내용을 먼저 입력해 주세요.');
      return;
    }

    final limit = await ApiUsageLimitService.checkOrganizeAllowance();
    if (!limit.allowed) {
      if (!mounted) return;
      _showInlineNoticeDialog(limit.message);
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
        _showInlineNoticeDialog(e.message);
        return;
      }
      _showInlineNoticeDialog('정리 중 오류가 발생했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) {
        setState(() => _summarizingSectionIndex = null);
      }
    }
  }

  // chatProxy 호출 + 사용량 체크 + 토큰/비용 로깅을 공용화한 헬퍼.
  // 대화가 아닌 단발성 분석/정리 요청(메모 요약 등)에서 재사용한다.
  Future<String> _callLlmJson(
    String systemPrompt,
    String userPrompt, {
    double temperature = 0.2,
  }) async {
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      {'role': 'user', 'content': userPrompt},
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
      'temperature': temperature,
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
      usageSource: 'memo_summary',
      countAsUserUsage: false,
    );

    return raw.replaceAll('```json', '').replaceAll('```', '').trim();
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

    return _callLlmJson(
      '당신은 장기 목표 플래너의 메모를 정리하는 편집 AI입니다. 원문 의도와 링크를 보존하면서 중복을 줄이고 핵심과 실행 문장을 명확히 정리합니다.',
      prompt,
      temperature: 0.2,
    );
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
            final replacedText = _baseText.replaceRange(start, end, insertText);
            final isMemoContentController = _contentCtrls.contains(
              _focusedCtrl,
            );
            _focusedCtrl!.text = isMemoContentController
                ? _limitSectionContent(replacedText)
                : replacedText;
            _focusedCtrl!.selection = TextSelection.collapsed(
              offset: (start + insertText.length).clamp(
                0,
                _focusedCtrl!.text.length,
              ),
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
      _sections[i].content = _limitSectionContent(_contentCtrls[i].text.trim());
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
                            '메모 묶음 추가',
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
                hintText: '실행에 필요한 핵심 위주로 글이나 링크를 적어두세요(최대 500자)',
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
                  subtitle: '오늘 캘린더에 즉시 추가됩니다.',
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
                  title: '루틴 트래커로 추가',
                  subtitle: '매일 실천하는 루틴 목록에 추가합니다.',
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
            '루틴으로 전환됨',
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
      final bool isLocalNote = url.startsWith('http://localhost:8000/?id=');
      spans.add(
        TextSpan(
          text: isLocalNote ? ' 🔗지식노트 ' : url,
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
