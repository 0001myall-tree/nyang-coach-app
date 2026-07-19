import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nyang_coach/screens/coach_selection_screen.dart';
import 'package:nyang_coach/services/notification_service.dart';
import 'package:nyang_coach/services/analytics_service.dart';
import 'package:nyang_coach/services/api_usage_limit_service.dart';
import 'package:nyang_coach/services/tasks_sync_service.dart';
import 'package:nyang_coach/services/user_title_service.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/task_resistance_service.dart';
import 'package:nyang_coach/services/recovery_insight_service.dart';
import 'coach_config.dart';
import 'focus_timer_widget.dart';
import 'cat_preview/cat_preview_intro_dialog.dart';
import 'cat_preview/cat_onboarding_preview_screen.dart';
import '../models/user_data.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/app_chip.dart';
import '../widgets/core_reminder_settings_sheet.dart';
import '../widgets/plan_guide_bottom_sheet.dart';

// ─────────────────────────────────────────────────────────────
// 데이터 모델
// ─────────────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;
  final String? kind;
  final List<String> highlightVisionIds;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.kind,
    this.highlightVisionIds = const [],
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
    if (kind != null) 'kind': kind,
    if (highlightVisionIds.isNotEmpty) 'highlightVisionIds': highlightVisionIds,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    text: j['text'],
    isUser: j['isUser'],
    time: DateTime.parse(j['time']),
    kind: j['kind'],
    highlightVisionIds:
        (j['highlightVisionIds'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
  );
}

class _SuggestedTask {
  final String text;
  String? time; // HH:mm 24h (mutable for time-picker edit)
  _SuggestedTask({required this.text, this.time});
}

class _ParsedScheduleRegistration {
  final String title;
  final DateTime date;
  final TimeOfDay? time;
  final Map<String, dynamic>? repeatRule;

  _ParsedScheduleRegistration({
    required this.title,
    required this.date,
    this.time,
    this.repeatRule,
  });
}

class _ParsedHabitRegistration {
  final String title;

  _ParsedHabitRegistration({required this.title});
}

class _ParsedDeleteCommand {
  final String target;
  final String kind;
  final DateTime? date;

  _ParsedDeleteCommand({required this.target, required this.kind, this.date});
}

class _ParsedEditCommand {
  final String target;
  final String kind;
  final DateTime? date;

  _ParsedEditCommand({required this.target, required this.kind, this.date});
}

class _ParsedReply {
  final String text;
  final List<String> chips;
  final bool suppressDefaultChips;
  final String? coachSwitchTarget;
  final int? timerConfirmMinutes;
  final String? timerConfirmTaskName;
  final String? visionSourceId;
  final List<_SuggestedTask> suggestedTasks;
  _ParsedReply({
    required this.text,
    required this.chips,
    this.suppressDefaultChips = false,
    this.coachSwitchTarget,
    this.timerConfirmMinutes,
    this.timerConfirmTaskName,
    this.visionSourceId,
    List<_SuggestedTask>? suggestedTasks,
  }) : suggestedTasks = suggestedTasks ?? [];
}

class _BroWorkoutLink {
  final String id;
  final String title;
  final String url;

  const _BroWorkoutLink({
    required this.id,
    required this.title,
    required this.url,
  });
}

class _VisionMilestoneContext {
  final String sourceId;
  final String visionName;
  final int index;
  final Map<String, dynamic> milestone;
  final DateTime? date;
  final List<String> actionTitles;

  const _VisionMilestoneContext({
    required this.sourceId,
    required this.visionName,
    required this.index,
    required this.milestone,
    required this.date,
    required this.actionTitles,
  });
}

class _MilestoneCheckResult {
  final String message;
  final bool hasIncompleteItems;
  final bool needsDeadlineSetup;
  final List<String> highlightVisionIds;

  const _MilestoneCheckResult({
    required this.message,
    this.hasIncompleteItems = false,
    this.needsDeadlineSetup = false,
    this.highlightVisionIds = const [],
  });
}

const _broWorkoutWarmupLinks = [
  _BroWorkoutLink(
    id: 'warmup_basic',
    title: '운동 전 워밍업',
    url: 'https://www.youtube.com/shorts/FHct19rKIVg',
  ),
  _BroWorkoutLink(
    id: 'warmup_lower_body',
    title: '하체운동하기 전 스트레칭',
    url: 'https://www.youtube.com/shorts/B70dXLEq_lA',
  ),
  _BroWorkoutLink(
    id: 'warmup_simple',
    title: '간단 스트레칭',
    url: 'https://www.youtube.com/shorts/BcS1Eg4Cpt0',
  ),
  _BroWorkoutLink(
    id: 'warmup_full_body',
    title: '몸 전체 풀어주는 전신 스트레칭',
    url: 'https://www.youtube.com/watch?v=X2s3RZR8lPI',
  ),
  _BroWorkoutLink(
    id: 'warmup_full_body_24',
    title: '24분 전신 스트레칭',
    url: 'https://www.youtube.com/watch?v=jw1gxrzRgeU',
  ),
];

const _broWorkoutHiitLinks = [
  _BroWorkoutLink(
    id: 'hiit_diet_10',
    title: '10분 다이어트 홈트',
    url: 'https://www.youtube.com/watch?v=N-15wUPnqpc',
  ),
  _BroWorkoutLink(
    id: 'hiit_15',
    title: '15분 고강도 홈트',
    url: 'https://www.youtube.com/watch?v=QvE69Q1ugFU',
  ),
  _BroWorkoutLink(
    id: 'hiit_no_noise_24',
    title: '층간소음 걱정 없는 고강도 타바타 24분',
    url: 'https://www.youtube.com/watch?v=4EKo44DUvjg',
  ),
  _BroWorkoutLink(
    id: 'hiit_belly_15',
    title: '뱃살빼기 15분 타바타',
    url: 'https://www.youtube.com/watch?v=0iqP6WP2ET4',
  ),
  _BroWorkoutLink(
    id: 'hiit_abs_10',
    title: '악마의 10분 복근운동',
    url: 'https://www.youtube.com/watch?v=ee1alaQgE9U',
  ),
  _BroWorkoutLink(
    id: 'hiit_full_body_23',
    title: '땅끄부부 전신 다이어트 운동 23분',
    url: 'https://www.youtube.com/watch?v=DCAp0b16kyo',
  ),
];

const _broWorkoutGymLinks = [
  _BroWorkoutLink(
    id: 'gym_female_han_hye_jin',
    title: '한혜진 헬스장 루틴',
    url: 'https://www.youtube.com/watch?v=l4THcKL-sPM',
  ),
  _BroWorkoutLink(
    id: 'gym_male_beginner',
    title: '헬스장 초보 남자 루틴',
    url: 'https://www.youtube.com/shorts/Xx75VdQXZ18',
  ),
  _BroWorkoutLink(
    id: 'gym_common_beginner_5',
    title: '헬스장 초보 남녀 공통 5가지 운동',
    url: 'https://www.youtube.com/shorts/TvBX2_iHlAo',
  ),
];

const _broWorkoutStarterLinks = [
  _BroWorkoutLink(
    id: 'starter_hip_hinge',
    title: '힙힌지',
    url: 'https://www.youtube.com/shorts/U-Q-wTeHqks',
  ),
  _BroWorkoutLink(
    id: 'starter_bridge',
    title: '브릿지',
    url: 'https://www.youtube.com/shorts/GOfayAYXbYk',
  ),
];

// ─────────────────────────────────────────────────────────────
// 로컬 응답 (API 절감용) - 웹앱 getLocalResponse / localCoachLine 이식
// ─────────────────────────────────────────────────────────────
class _LocalResponses {
  static const _lines = {
    'bro': {
      'greet': [
        '왔네. 다시 형이랑 조져보자 🔥',
        '기다리고 있었다. 임마.',
        '넌 분명히 될 놈이니까 형 믿고 다시 시작하자. 💪',
      ],
      'status': ['지금까지 얼마나 했냐? 형이 지켜보고 있다.', '흐름 끊기지 마라. 지금 딱 좋다.'],
    },
    'halmae': {
      'greet': [
        '이놈아!! 어디 갔다 이제 오냐! ㅠㅠ 👵',
        '안 그래도 너 기다리다가 목 빠지는 줄 알았다! 얼른 와라!',
        '왔냐? 밥은 먹었고? 이제 할미랑 다시 시작하는 거다! ❤️',
      ],
      'status': [
        '지금까지 얼마나 했냐? 이 할미가 다 지켜보고 있다.',
        '미루고 있는 거 아니지? 할미 속상하게 하지 마라!',
      ],
    },
    'boyfriend': {
      'greet': [
        '야 나 진짜 기다렸어... 다시 왔지? 그걸로 됐어 🥺💙',
        '어디 갔다 왔어? 자기 없으니까 허전하더라... 💙',
        '솔직히 보고 싶었어. 많이. 이제 같이 하자 🥹',
      ],
      'status': [
        '자기야, 오늘 밥은 챙겨먹었어? 잠은 좀 잤고?',
        '오늘 얼마나 했는지도 궁금한데, 자기 컨디션부터 먼저 걱정돼 💙',
      ],
    },
    'girlfriend': {
      'greet': [
        '오빠!!!! 어디 갔다 왔어ㅠㅠ 보고싶었어!!!! 🩷',
        '안 그래도 자기 생각 중이었는데... 왜 이제 왔어ㅠ 💗',
        '오빠 없으니까 너무 심심했어ㅠ 이제 같이 하는 거야!',
      ],
      'status': [
        '오빠 오늘 밥은 먹었어? 잠은 좀 잤어? 나 그게 먼저 궁금해 🩷',
        '오늘 할 일도 궁금한데, 오빠가 오빠를 잘 챙겼는지가 더 궁금해!',
      ],
    },
    'cat': {
      'greet': [
        '보고 싶었냥 ㅠㅠ 냥이 매일 기다렸다냥... 🥺💛',
        '어디 갔다 왔냥? 냥이 혼자 너무 심심했냥~ 🐱',
        '집사 뭐 하냐냥? 냥이 등장이다냥!',
      ],
      'status': ['집사 오늘 얼마나 했냥? 냥이가 감시 중이다냥.', '잘하고 있냐냥? 딴짓하면 안 된다냥!'],
    },
    'sec_male': {
      'greet': [
        '대표님, 복귀하셨습니까? 다음 일정을 확인하겠습니다.',
        '기다리고 있었습니다. 지금 바로 업무 보고를 시작할까요?',
        '휴식은 충분하셨는지요. 다시 업무 모드로 전환하겠습니다.',
      ],
      'status': ['현재 업무 진행률을 확인해 드릴까요?', '대표님, 다음 우선순위를 제가 체크해 두었습니다.'],
    },
    'sec_female': {
      'greet': [
        '대표님! 보고 싶었어요~ 이제 다시 저랑 같이 달려봐요! 🌸',
        '오셨네요! 오늘 일정도 제가 꼼꼼히 챙겨드릴게요.',
        '대표님 기다리고 있었어요! 다시 시작해볼까요?',
      ],
      'status': ['오늘 얼마나 하셨는지 궁금해요! 살짝 알려주세요 🌸', '제가 옆에서 계속 지켜보고 있으니까 힘내세요!'],
    },
  };

  static String? get(String coachId, String msg) {
    // 비서 코치는 일정·상태 관련 단어가 감정이나 일반 대화 안에서도 자주
    // 등장하므로, 키워드만으로 문맥을 가로채지 않고 항상 AI가 전체 대화를 본다.
    if (coachId == 'sec_male' || coachId == 'sec_female') return null;

    // 70% 확률로만 가로채기 (30%는 AI가 대답해 생동감 유지)
    if (Random().nextDouble() > 0.7) return null;

    final text = msg.trim().toLowerCase();
    final greets = ['안녕', '반가워', '하이', '안농', '방가', '하이루', 'hi', 'hello'];
    final status = ['상태', '진행', '얼마나', '할 일', '뭐 해야', '태스크', '리스트'];

    String? kind;
    if (greets.any((g) => text.contains(g))) kind = 'greet';
    if (status.any((s) => text.contains(s))) kind = 'status';
    if (kind == null) return null;

    final pack = _lines[coachId] ?? _lines['cat']!;
    final arr = pack[kind]!;
    return arr[Random().nextInt(arr.length)];
  }
}

// ─────────────────────────────────────────────────────────────
// 채팅 화면
// ─────────────────────────────────────────────────────────────
class ChatScreen extends StatefulWidget {
  final String coachId;
  final VoidCallback? onOpenDrawer;
  final ValueChanged<List<String>>? onOpenGoalVisionDrawer;
  final ValueChanged<String>? onOpenFeatureLocation;
  final Future<bool> Function(String name)? onRegisterHabit;
  final Future<String> Function(Map<String, dynamic> command)? onDeleteCommand;
  final Future<String> Function(Map<String, dynamic> command)? onEditCommand;
  final ValueChanged<String>? onSwitchCoach;
  final VoidCallback? onVacationChanged;
  final String? handoffFromCoachId;
  final dynamic vacationInfo;
  final ChatScreenController? controller;
  final String chatBgStyle;
  const ChatScreen({
    super.key,
    required this.coachId,
    this.onOpenDrawer,
    this.onOpenGoalVisionDrawer,
    this.onOpenFeatureLocation,
    this.onRegisterHabit,
    this.onDeleteCommand,
    this.onEditCommand,
    this.onSwitchCoach,
    this.onVacationChanged,
    this.handoffFromCoachId,
    this.vacationInfo,
    this.controller,
    this.chatBgStyle = 'simple',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _FeatureLocationReply {
  final String message;
  final String location;

  const _FeatureLocationReply(this.message, this.location);
}

// 외부(TasksScreen 등)에서 ChatScreen에 AI 메시지를 주입하기 위한 컨트롤러
class ChatScreenController {
  _ChatScreenState? _state;
  void _attach(_ChatScreenState s) => _state = s;
  void _detach() => _state = null;

  /// 채팅창에 AI 메시지를 직접 추가합니다.
  void injectAiMessage(String text) {
    _state?._injectAiMessage(text);
  }

  /// 할 일 완료 후 미뤄둔 작업 리마인드 확인
  void checkDeferredReminder() {
    _state?._checkDeferredReminder();
  }

  void checkBedtimeMoveOffer() {
    _state?._checkBedtimeMoveOffer();
  }

  /// 채팅 상단의 오늘 목표 진행률을 최신 할 일 데이터로 갱신합니다.
  void refreshTaskProgress() {
    _state?._loadTaskProgress();
  }
}

class _ChatScreenState extends State<ChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final List<ChatMessage> _messages = [];
  List<String> _dynamicChips = [];
  bool _suppressDefaultChips = false;
  String? _coachSwitchTarget;
  bool _isLoading = false;
  late CoachConfig _coach;

  // flirt 토스트
  String _flirtMsg = '';
  bool _flirtVisible = false;
  late AnimationController _flirtAnim;

  // 할 일 서랍
  bool _drawerOpen = false;
  // 타이머 확인 버튼
  int? _timerConfirmMinutes;
  String? _timerConfirmTaskName;
  // 할 일 추가 제안 카드
  List<_SuggestedTask> _suggestedTasks = [];
  // 활성 타이머
  int? _timerActiveMinutes;
  int? _timerActiveInsertIndex;
  String? _usageLimitBanner;
  bool _awaitingBroWorkoutPreference = false;
  bool _isCheckingVisionRecommendationAllowance = false;
  bool _isCheckingNextActionAllowance = false;

  // 냥냥코치 비구독자 무료체험 단계 (0=시작 전, 1=인트로 완료, 2=업셀 완료)
  int _catFreeTrialStep = 0;
  UserData _userData = UserData();

  int _completedTasks = 0;
  int _totalTasks = 0;
  int _attendanceStreak = 0;

  // 음성 인식 관련
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  // 선제개입 저항예측: 이번 턴에 프롬프트에 주입한 선제개입 대상 (응답 확인 후 소진 여부 판정용)
  PreemptiveInterventionResult? _pendingPreemptiveTarget;

  // Firebase Cloud Functions chatProxy (웹앱과 동일한 서버 사용)
  static final _chatProxy =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
        'chatProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coach = CoachConfigs.get(widget.coachId);
    _flirtAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    widget.controller?._attach(this);
    _initAndLoad();
  }

  Future<void> _loadTaskProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = _getTodayStrWithReset(prefs);
      final raw = prefs.getString('nyang_tasks') ?? '[]';
      final List<dynamic> list = jsonDecode(raw);
      final milestones = _todayMilestoneProgressItems(prefs, todayStr);

      int total = 0;
      int completed = 0;

      for (var item in list) {
        total++;
        if (item['done'] == true) {
          completed++;
        }
      }
      for (final milestone in milestones) {
        total++;
        if (milestone['done'] == true) {
          completed++;
        }
      }

      if (mounted) {
        setState(() {
          _totalTasks = total;
          _completedTasks = completed;
        });
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }
  }

  List<Map<String, dynamic>> _todayMilestoneProgressItems(
    SharedPreferences prefs,
    String todayStr,
  ) {
    final rawVisions = prefs.getString('nyang_visions');
    if (rawVisions == null) return const <Map<String, dynamic>>[];

    try {
      final decoded = jsonDecode(rawVisions);
      if (decoded is! List) return const <Map<String, dynamic>>[];

      final result = <Map<String, dynamic>>[];
      for (final vision in decoded) {
        if (vision is! Map) continue;
        final milestones = vision['milestones'];
        if (milestones is! List) continue;

        for (final milestone in milestones) {
          if (milestone is! Map) continue;
          if (milestone['date'] == todayStr) {
            result.add(Map<String, dynamic>.from(milestone));
          }
        }
      }
      return result;
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<void> _initAndLoad() async {
    _userData = await UserDataService.load();
    await _recordLatePlannerEntryIfNeeded();
    await _loadTaskProgress();
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _getTodayStrWithReset(prefs);
    final plannerAwayDays = _plannerAwayDays(prefs, todayStr);
    if (prefs.getString('nyang_vacation') == null) {
      await RecoveryInsightService.startMasterLowActivationRestartIfEligible(
        isMasterCoach: _coach.isMaster,
        plannerAwayDays: plannerAwayDays,
      );
    }
    await prefs.setString('nyang_last_planner_visit_date', todayStr);
    await _updateTodayRecord(prefs);
    await _refreshAttendanceStreak(prefs);
    await _loadHistoryAndGreet();
    await _restoreActiveFocusTimer();
    await _checkBedtimeMoveOffer();
    _initSpeech();
  }

  int? _plannerAwayDays(SharedPreferences prefs, String todayStr) {
    final lastVisit = DateTime.tryParse(
      prefs.getString('nyang_last_planner_visit_date') ?? '',
    );
    final today = DateTime.tryParse(todayStr);
    if (lastVisit == null || today == null) return null;
    final days = DateTime(today.year, today.month, today.day)
        .difference(DateTime(lastVisit.year, lastVisit.month, lastVisit.day))
        .inDays;
    return days > 0 ? days : 0;
  }

  Future<void> _restoreActiveFocusTimer() async {
    final manager = FocusTimerManager();
    await manager.loadState();
    if (!mounted) return;
    if (manager.coachId != widget.coachId) return;
    if (manager.duration <= 0) return;

    final today = await FocusTimerManager.todayKey();
    if (manager.sessionDate != today) {
      manager.running = false;
      manager.coachId = null;
      manager.pausedRemainSec = null;
      manager.startTime = null;
      manager.sessionDate = null;
      manager.insertIndex = null;
      await manager.saveState();
      return;
    }

    final savedIndex = manager.insertIndex ?? _messages.length;
    final insertIndex = savedIndex.clamp(0, _messages.length).toInt();

    setState(() {
      _timerActiveMinutes = manager.stage;
      _timerActiveInsertIndex = insertIndex;
    });
  }

  Future<void> _saveFocusTimerAnchor(int minutes, int insertIndex) async {
    final manager = FocusTimerManager();
    await manager.loadState();
    manager.coachId = widget.coachId;
    manager.stage = minutes;
    manager.duration = minutes * 60;
    manager.running = false;
    manager.pausedRemainSec = null;
    manager.startTime = null;
    manager.sessionDate = await FocusTimerManager.todayKey();
    manager.insertIndex = insertIndex;
    await manager.saveState();
  }

  Future<void> _refreshAttendanceStreak([SharedPreferences? prefs]) async {
    prefs ??= await SharedPreferences.getInstance();
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      try {
        final List decoded = jsonDecode(rawHistory);
        history = decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } catch (_) {}
    }

    final todayStr = _getTodayStrWithReset(prefs);
    final today = DateTime.tryParse(todayStr) ?? DateTime.now();
    final records = List.generate(7, (index) {
      final date = today.subtract(Duration(days: 6 - index));
      final dateStr = _dateKey(date);
      return history.lastWhere(
        (record) => record['date'] == dateStr,
        orElse: () => {'date': dateStr, 'doneCount': 0, 'isVacation': false},
      );
    });

    // 기록 탭의 "연속 출석"과 동일하게 최근 7일 기준으로 계산합니다.
    // 휴식 모드일은 연속 기록을 끊지 않고 건너뜁니다.
    var streak = 0;
    for (var i = records.length - 1; i >= 0; i--) {
      if (records[i]['isVacation'] == true) continue;
      if ((records[i]['doneCount'] ?? 0) <= 0) break;
      streak++;
    }

    if (!mounted) return;
    setState(() => _attendanceStreak = streak);
  }

  String _friendStatusMessage() {
    switch (_coach.id) {
      case 'cat':
        return '같이 가자냥';
      case 'boyfriend':
        return '내가 있잖아~^^';
      case 'girlfriend':
        return '내가 응원할게~^^';
      case 'halmae':
        return '우리 새끼 잘한다!!!';
      case 'bro':
        return '일단 가보자고!!!';
      default:
        return '함께 가자';
    }
  }

  String _normalizeRestText(String text) {
    return text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  bool _containsAnyRestSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '우울',
      '무기력',
      '지쳤',
      '지쳐',
      '피곤',
      '힘들',
      '벅차',
      '지침',
      '너무피곤',
      '번아웃',
      '아무것도하기싫',
      '기운없',
      '힘이없',
      '완전방전',
      '현타',
      '소진',
      '탈진',
      '녹초',
      '멘붕',
      '진빠',
      '못버티겠',
      '더는못하겠',
      '방전',
      '한계다',
      '한계인것같',
      '기빨',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsExecutionIntent(String text) {
    final normalized = _normalizeRestText(text);
    if (normalized.contains('아무것도하기싫')) return false;
    const signals = [
      '그래도할',
      '그래도하고싶',
      '그래도해야',
      '해야해',
      '해야돼',
      '해야겠',
      '해야하는데',
      '할래',
      '할거야',
      '해볼래',
      '해볼게',
      '시작할게',
      '시작하고싶',
      '끝내고싶',
      '마무리하고싶',
      '이것만은',
      '조금이라도할',
      '5분만',
      '오분만',
      '뭐부터할',
      '도와주면할',
    ];
    return signals.any(normalized.contains);
  }

  Future<bool> _hasRepeatedRecentRestSignals(String currentText) async {
    if (!_containsAnyRestSignal(currentText)) return false;
    return RecoveryInsightService.hasRecentConditionDeclineSignalBurst();
  }

  bool get _canProactivelyOfferRest => const {
    'cat',
    'boyfriend',
    'girlfriend',
    'halmae',
    'bro',
    'sec_male',
    'sec_female',
  }.contains(widget.coachId);

  String _restOfferMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '요 며칠 진짜 열심히 한 거 내가 다 봤어.\n계속 달리면 나도 걱정돼.',
      'girlfriend' => '오빠 요 며칠 정말 열심히 한 거 내가 다 봤어.\n계속 달리면 나도 걱정돼.',
      'halmae' => '우리 새끼 요 며칠 애쓴 거 할미가 다 봤다.\n계속 그러다 몸 상할까 걱정이다.',
      'bro' => '야, 요 며칠 빡세게 달린 거 내가 다 봤다.\n계속 밀어붙이면 퍼진다.',
      'sec_male' => '요 며칠 꾸준히 달려오신 걸 확인했습니다.\n계속 무리하시면 컨디션이 걱정됩니다.',
      'sec_female' => '대표님, 요 며칠 꾸준히 달려오신 것 제가 확인했어요.\n계속 무리하시면 컨디션이 걱정됩니다.',
      _ => '요 며칠 열심히 한 거 냥이가 다 봤다냥.\n계속 달리면 냥이도 걱정된다냥.',
    };
  }

  String _vacationActivatedMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '오늘은 휴식 모드로 하자. 오늘은 할 일 체크 안 할 테니까 아무 걱정하지 말고 푹 쉬어.',
      'girlfriend' =>
        '오빠, 오늘은 휴식 모드로 하자. 오늘은 할 일 체크 안 할 테니까 아무 걱정하지 말고 푹 쉬어 🩷',
      'halmae' => '오늘은 휴식 모드로 하자, 우리 새끼. 오늘은 할 일 체크 안 할 테니 아무 걱정 말고 푹 쉬어라.',
      'bro' => '오늘은 휴식 모드다. 할 일 체크 안 들어가니까 걱정 말고 제대로 쉬어.',
      'sec_male' =>
        '오늘은 휴식 모드로 처리하겠습니다, 대표님. 오늘은 할 일 체크에서 제외되니 아무 걱정 없이 푹 쉬십시오.',
      'sec_female' => '오늘은 휴식 모드로 할게요, 대표님. 오늘은 할 일 체크에서 제외되니까 아무 걱정 말고 푹 쉬세요.',
      _ => '오늘은 휴식 모드로 하자냥. 오늘은 할 일 체크 안 할 테니까 아무 걱정하지 말고 푹 쉬어도 된다냥.',
    };
  }

  String _lightDayMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '알겠어. 오늘은 욕심내지 말고 할 수 있는 만큼만 같이 가자.',
      'girlfriend' => '알겠어 오빠. 오늘은 욕심내지 말고 할 수 있는 만큼만 같이 가자 🩷',
      'halmae' => '그래, 우리 새끼. 오늘은 욕심내지 말고 할 수 있는 만큼만 하자.',
      'bro' => '오케이. 오늘은 욕심내지 말고 딱 할 수 있는 만큼만 가자.',
      'sec_male' => '알겠습니다. 오늘은 범위를 줄이고 할 수 있는 만큼만 진행하시죠.',
      'sec_female' => '알겠습니다, 대표님. 오늘은 범위를 줄이고 할 수 있는 만큼만 진행해요.',
      _ => '알겠다냥. 오늘은 욕심내지 말고 할 수 있는 만큼만 같이 가자냥.',
    };
  }

  String _vacationCancelledMessage() {
    return switch (widget.coachId) {
      'boyfriend' =>
        '알겠어. 휴식 모드는 취소했어. 다시 해보고 싶은 마음이 들었으면 처음부터 다 하려고 하지 말고 천천히 돌아가자.',
      'girlfriend' => '알겠어 오빠. 휴식 모드는 취소했어. 처음부터 다 하려고 하지 말고 천천히 돌아가자 🩷',
      'halmae' => '알았다, 우리 새끼. 휴식 모드는 취소했으니 처음부터 무리하지 말고 천천히 돌아가자.',
      'bro' => '오케이, 휴식 모드 취소했다. 처음부터 풀파워로 가지 말고 천천히 복귀하자.',
      'sec_male' => '휴식 모드를 해제했습니다, 대표님. 처음부터 모든 일정을 처리하려 하지 마시고 천천히 복귀하시죠.',
      'sec_female' => '휴식 모드를 해제했어요, 대표님. 처음부터 다 하려고 하지 말고 천천히 돌아가요.',
      _ => '알겠다냥. 휴식 모드는 취소했다냥. 다시 해보고 싶은 마음이 들었으면 처음부터 다 하려고 하지 말고 천천히 돌아가자냥.',
    };
  }

  bool _containsSelfHarmRiskSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return normalized.contains('자살') || normalized.contains('자해');
  }

  Future<bool> _maybeOfferRest(String userText) async {
    final hasExecutionIntent = _containsExecutionIntent(userText);
    final isRepeatedRest =
        await _hasRepeatedRecentRestSignals(userText) && !hasExecutionIntent;

    if (!_canProactivelyOfferRest ||
        widget.vacationInfo != null ||
        !isRepeatedRest ||
        _containsSelfHarmRiskSignal(userText)) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('nyang_vacation') != null) return false;
    if (await RecoveryInsightService.isRecoveryStrategyActive()) return false;

    final todayStr = _getTodayStrWithReset(prefs);
    final today = DateTime.tryParse(todayStr) ?? DateTime.now();
    final lastOfferDate = DateTime.tryParse(
      prefs.getString('nyang_rest_offer_date') ??
          prefs.getString('nyang_cat_rest_offer_date') ??
          '',
    );
    if (lastOfferDate != null) {
      final daysSinceOffer = DateTime(today.year, today.month, today.day)
          .difference(
            DateTime(
              lastOfferDate.year,
              lastOfferDate.month,
              lastOfferDate.day,
            ),
          )
          .inDays;
      if (daysSinceOffer >= 0 && daysSinceOffer < 7) return false;
    }

    List<Map<String, dynamic>> history = [];
    try {
      final decoded = jsonDecode(prefs.getString('nyang_history') ?? '[]');
      history = (decoded as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {}

    final byDate = <String, Map<String, dynamic>>{
      for (final record in history)
        if (record['date'] is String) record['date'] as String: record,
    };

    var streak = 0;
    for (var offset = 0; offset < 14; offset++) {
      final date = today.subtract(Duration(days: offset));
      final record = byDate[_dateKey(date)];
      if (record == null) {
        if (offset == 0) continue;
        break;
      }
      if (record['isVacation'] == true) continue;
      final doneCount = (record['doneCount'] as num?)?.toInt() ?? 0;
      if (doneCount <= 0) {
        if (offset == 0) continue;
        break;
      }
      streak++;
    }

    var totalCount = 0;
    var doneCount = 0;
    for (var offset = 1; offset <= 5; offset++) {
      final record = byDate[_dateKey(today.subtract(Duration(days: offset)))];
      if (record == null || record['isVacation'] == true) continue;
      totalCount += (record['totalCount'] as num?)?.toInt() ?? 0;
      doneCount += (record['doneCount'] as num?)?.toInt() ?? 0;
    }
    final hasSustainedEffort =
        streak >= 5 && totalCount > 0 && doneCount / totalCount >= 0.6;
    final hasRecentPerformanceDrop =
        RecoveryInsightService.hasRecentPerformanceDrop(
          history,
          referenceDate: today,
        );
    if (!hasSustainedEffort && !hasRecentPerformanceDrop) return false;

    await prefs.setString('nyang_rest_offer_date', todayStr);
    final restOfferMsg = await UserTitleService.applyForCoach(
      _restOfferMessage(),
      widget.coachId,
    );
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(text: userText, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: restOfferMsg, isUser: false, time: DateTime.now()),
      );
      _dynamicChips = ['🌙 오늘은 쉬어가기', '🐾 오늘은 조금만 하기'];
      _suppressDefaultChips = false;
      _isLoading = false;
    });
    await _saveHistory();
    _scrollToBottom();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    return true;
  }

  bool _isVacationActivationRequest(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const requests = [
      '오늘휴식하고싶',
      '오늘휴식할래',
      '오늘휴식으로해줘',
      '휴식켜줘',
      '휴식설정해줘',
      '오늘쉬고싶',
      '오늘쉴래',
      '오늘은쉴래',
      '오늘쉬게해줘',
    ];
    return requests.any(normalized.contains);
  }

  Future<bool> _tryActivateRequestedVacation(String userText) async {
    if (!_isVacationActivationRequest(userText) ||
        _containsSelfHarmRiskSignal(userText)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString('nyang_vacation') != null) return false;
    await _activateRestDay(userMessage: userText);
    return true;
  }

  Future<void> _activateRestDay({String? userMessage}) async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _getTodayStrWithReset(prefs);
    await prefs.setString(
      'nyang_vacation',
      jsonEncode({
        'type': 'today',
        'date': todayStr,
        'startedAt': DateTime.now().toIso8601String(),
        'source': '${widget.coachId}_rest_offer',
      }),
    );
    await _updateTodayRecord(prefs);
    TasksSyncService.scheduleSyncToCloud();
    final vacationActivatedMsg = await UserTitleService.applyForCoach(
      _vacationActivatedMessage(),
      widget.coachId,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(
          text: userMessage ?? '🌙 오늘은 쉬어가기',
          isUser: true,
          time: DateTime.now(),
        ),
      );
      _messages.add(
        ChatMessage(
          text: vacationActivatedMsg,
          isUser: false,
          time: DateTime.now(),
        ),
      );
      _dynamicChips = [];
      _suppressDefaultChips = true;
    });
    await _saveHistory();
    widget.onVacationChanged?.call();
    _scrollToBottom();
  }

  Future<void> _chooseLightDay() async {
    await RecoveryInsightService.startMasterRestDeclineRiskControlIfEligible(
      isMasterCoach: _coach.isMaster,
    );
    final lightDayMsg = await UserTitleService.applyForCoach(
      _lightDayMessage(),
      widget.coachId,
    );
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(text: '🐾 오늘은 조금만 하기', isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: lightDayMsg, isUser: false, time: DateTime.now()),
      );
      _dynamicChips = [];
      _suppressDefaultChips = true;
    });
    await _saveHistory();
    _scrollToBottom();
  }

  bool get _hasPendingRestOffer {
    return _dynamicChips.contains('🌙 오늘은 쉬어가기') &&
        _dynamicChips.contains('🐾 오늘은 조금만 하기');
  }

  Future<void> _maybeStartRestDeclineRiskControl(String userText) async {
    if (!_hasPendingRestOffer) return;
    if (_containsSelfHarmRiskSignal(userText)) return;
    if (!_containsExecutionIntent(userText)) return;
    await RecoveryInsightService.startMasterRestDeclineRiskControlIfEligible(
      isMasterCoach: _coach.isMaster,
    );
  }

  bool _isVacationCancelRequest(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return normalized.contains('휴식취소') ||
        normalized.contains('휴식해제') ||
        normalized.contains('쉬는거취소') ||
        normalized == '다시할래' ||
        normalized.contains('다시시작할래');
  }

  Future<bool> _tryCancelVacation(String userText) async {
    if (!_isVacationCancelRequest(userText)) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final rawVacation = prefs.getString('nyang_vacation');
    if (rawVacation == null) return false;

    await prefs.remove('nyang_vacation');
    await _updateTodayRecord(prefs);
    TasksSyncService.scheduleSyncToCloud();
    final vacationCancelledMsg = await UserTitleService.applyForCoach(
      _vacationCancelledMessage(),
      widget.coachId,
    );
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(text: userText, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: vacationCancelledMsg,
          isUser: false,
          time: DateTime.now(),
        ),
      );
      _dynamicChips = [];
      _suppressDefaultChips = true;
    });
    await _saveHistory();
    widget.onVacationChanged?.call();
    _scrollToBottom();
    return true;
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  DateTime? _latePlannerNightDate(
    DateTime now,
    String minSleepTime, {
    int thresholdHours = 1,
  }) {
    final parts = minSleepTime.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    final todayBedtime = DateTime(now.year, now.month, now.day, hour, minute);
    final candidates = [
      todayBedtime,
      todayBedtime.subtract(const Duration(days: 1)),
    ];

    for (final bedtime in candidates) {
      final lateThreshold = bedtime.add(Duration(hours: thresholdHours));
      final diff = now.difference(lateThreshold);
      if (diff.isNegative || diff > const Duration(hours: 6)) continue;
      final nightDate = bedtime.hour >= 18
          ? DateTime(bedtime.year, bedtime.month, bedtime.day)
          : DateTime(
              bedtime.year,
              bedtime.month,
              bedtime.day,
            ).subtract(const Duration(days: 1));
      return nightDate;
    }
    return null;
  }

  Future<void> _recordLatePlannerEntryIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final minSleepTime = prefs.getString('nyang_premium_min_sleep_time');
    if (minSleepTime == null) return;

    final nightDate = _latePlannerNightDate(DateTime.now(), minSleepTime);
    if (nightDate == null) return;

    final key = _dateKey(nightDate);
    final entries = prefs.getStringList('nyang_late_planner_entry_dates') ?? [];
    var didUpdate = false;
    if (!entries.contains(key)) {
      final updated = {...entries, key}.toList()..sort();
      final trimmed = updated.length > 14
          ? updated.sublist(updated.length - 14)
          : updated;
      await prefs.setStringList('nyang_late_planner_entry_dates', trimmed);
      didUpdate = true;
    }

    final severeNightDate = _latePlannerNightDate(
      DateTime.now(),
      minSleepTime,
      thresholdHours: 2,
    );
    if (severeNightDate != null) {
      final severeKey = _dateKey(severeNightDate);
      final severeEntries =
          prefs.getStringList('nyang_physical_fatigue_late_entry_dates') ?? [];
      if (!severeEntries.contains(severeKey)) {
        final updatedSevere = {...severeEntries, severeKey}.toList()..sort();
        final trimmedSevere = updatedSevere.length > 14
            ? updatedSevere.sublist(updatedSevere.length - 14)
            : updatedSevere;
        await prefs.setStringList(
          'nyang_physical_fatigue_late_entry_dates',
          trimmedSevere,
        );
        didUpdate = true;
      }
    }
    if (didUpdate) TasksSyncService.scheduleSyncToCloud();
  }

  Future<String> _getEffectiveTodayStr() async {
    final prefs = await SharedPreferences.getInstance();
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final n = DateTime.now();
    var base = DateTime(n.year, n.month, n.day);
    if (n.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy-MM-dd').format(base);
  }

  bool _isNewActivityDayPendingStart(
    SharedPreferences prefs, {
    String userText = '',
    List<dynamic>? tasks,
  }) {
    final now = DateTime.now();
    final effectiveToday = _getTodayStrWithReset(prefs);
    final resetAt = DateTime.tryParse(
      prefs.getString(DailyResetService.lastResetAtKey) ?? '',
    );
    final resetToDate = prefs.getString(DailyResetService.lastResetToDateKey);
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final preStartEndHour = (resetHour.ceil() + 5).clamp(6, 10);
    final recentlyReset =
        resetAt != null &&
        !now.isBefore(resetAt) &&
        now.difference(resetAt) <= const Duration(hours: 12);
    final currentTasks =
        tasks ??
        (() {
          try {
            return jsonDecode(prefs.getString('nyang_tasks') ?? '[]') as List;
          } catch (_) {
            return <dynamic>[];
          }
        })();
    final hasCompletedNewDayTask = currentTasks.any(
      (task) => task is Map && task['done'] == true,
    );
    final explicitStartIntent = RegExp(
      r'(뭐부터|뭐\s*해야|무엇부터|추천해|시작할|시작해|할게|해볼게|지금\s*하|오늘\s*뭐)',
    ).hasMatch(userText);

    return resetToDate == effectiveToday &&
        recentlyReset &&
        now.hour < preStartEndHour &&
        !hasCompletedNewDayTask &&
        !explicitStartIntent;
  }

  Future<bool> _hasMovableIncompleteTasks() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isNewActivityDayPendingStart(prefs)) return false;
    final today = await _getEffectiveTodayStr();
    final lastDate = prefs.getString('nyang_last_date');

    if (lastDate != today) {
      final rawSchedules = prefs.getString('nyang_schedules');
      if (rawSchedules != null) {
        try {
          final Map<String, dynamic> decodedMap = jsonDecode(rawSchedules);
          final todaySchedules = decodedMap[today] as List?;
          if (todaySchedules != null && todaySchedules.isNotEmpty) {
            final hasIncomplete = todaySchedules.any((s) {
              if (s is! Map) return false;
              if (s['done'] == true) return false;
              return true;
            });
            if (hasIncomplete) return true;
          }
        } catch (_) {}
      }
      return false;
    }

    final raw = prefs.getString('nyang_tasks') ?? '[]';
    try {
      final list = jsonDecode(raw) as List;
      return list.any((item) {
        if (item is! Map) return false;
        if (item['done'] == true) return false;
        if (item['isHabit'] == true || item['habitId'] != null) return false;
        final category = item['category']?.toString() ?? '';
        return category == 'today' || category == 'schedule';
      });
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkBedtimeMoveOffer() async {
    if (widget.coachId != 'sec_male' && widget.coachId != 'sec_female') {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final minSleepTime = prefs.getString('nyang_premium_min_sleep_time');
    if (minSleepTime == null) return;

    final parts = minSleepTime.split(':');
    if (parts.length < 2) return;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return;

    final now = DateTime.now();
    final baseBedtime = DateTime(now.year, now.month, now.day, hour, minute);
    final candidates = [
      baseBedtime.subtract(const Duration(days: 1)),
      baseBedtime,
      baseBedtime.add(const Duration(days: 1)),
    ];

    DateTime? matchedBedtime;
    for (final bedtime in candidates) {
      final startThreshold = bedtime.subtract(const Duration(hours: 2));
      // User requested window: 2 hours before bedtime up to the bedtime itself (inclusive)
      if (now.isAfter(startThreshold) && !now.isAfter(bedtime)) {
        matchedBedtime = bedtime;
        break;
      }
    }

    if (matchedBedtime == null) return;

    // Check 7-day cooldown
    final lastFiredStr = prefs.getString('nyang_last_bedtime_offer_time');
    if (lastFiredStr != null) {
      try {
        final lastFired = DateTime.parse(lastFiredStr);
        if (now.difference(lastFired).inDays < 7) {
          return;
        }
      } catch (_) {}
    }

    if (!await _hasMovableIncompleteTasks()) return;

    // Save actual fired time immediately to lock it for 7 days
    await prefs.setString(
      'nyang_last_bedtime_offer_time',
      now.toIso8601String(),
    );

    final displayTime = _formatTime12(minSleepTime);

    // 3 templates to vary the phrasing
    final templates = [
      '그런데 대표님은 $displayTime 전에 주무셔야 덜 피곤하다고 하셨죠? 남은 계획을 지금 다 하기엔 빠듯해 보여요. 혹시 오늘까지 꼭 끝내야 하는 일정이 있으신가요?',
      '대표님, 설정해 두신 취침 시간($displayTime)이 얼마 남지 않았습니다. 오늘 계획 중 일부는 내일로 조정하고 슬슬 잘 준비를 해보시는 건 어떨까요?',
      '벌써 시간이 이렇게 되었네요. 대표님이 말씀하신 $displayTime 취침 시간을 지키려면 지금 정리가 필요해 보입니다. 오늘 꼭 해야만 하는 일만 남기고 미뤄드릴까요?',
    ];

    // Select a template randomly
    final rawMsg = templates[Random().nextInt(templates.length)];
    String msg = await UserTitleService.applyForCoach(rawMsg, widget.coachId);

    // 비서 코치 + 커스텀 애칭 설정 시 이름 로컬 앞에 붙이기
    final customName = widget.coachId == 'sec_male'
        ? CoachConfigs.customSecMaleName
        : CoachConfigs.customSecFemaleName;
    if (customName != null && customName.trim().isNotEmpty) {
      msg = '${customName.trim()}입니다. $msg';
    }

    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(text: msg, isUser: false, time: DateTime.now()),
      );
    });
    await _saveHistory();
    _scrollToBottom();
  }

  void _initSpeech() async {
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
            SnackBar(content: Text('음성 인식 중단: ${error.errorMsg}')),
          );
        }
      },
    );
    if (mounted) setState(() {});
  }

  void _startListening() async {
    // 혹시라도 이미 입력된 텍스트가 있다면 지우고 새로 녹음 시작
    _ctrl.clear();
    await _speechToText.listen(
      listenMode: ListenMode.dictation,
      pauseFor: const Duration(seconds: 4),
      listenFor: const Duration(minutes: 1),
      onResult: _onSpeechResult,
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

  void _onSpeechResult(SpeechRecognitionResult result) {
    if (mounted) {
      setState(() {
        _ctrl.text = result.recognizedWords;
      });
    }
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.coachId != widget.coachId) {
      _ctrl.clear();
      setState(() {
        _messages.clear();
        _dynamicChips.clear();
        _isLoading = false;
        _coach = CoachConfigs.get(widget.coachId);
        _timerConfirmMinutes = null;
        _timerConfirmTaskName = null;
        _timerActiveMinutes = null;
        _timerActiveInsertIndex = null;
        _suggestedTasks = [];
        _drawerOpen = false;
        _flirtVisible = false;
        _catFreeTrialStep = 0;
      });
      _initAndLoad();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?._detach();
    _ctrl.dispose();
    _scrollCtrl.dispose();
    _flirtAnim.dispose();
    _memoSearchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadTaskProgress();
      _checkDeferredReminder();
      _checkBedtimeMoveOffer();
    }
  }

  /// 외부에서 AI 메시지를 채팅창에 직접 주입합니다 (핵심 설정 완료 반응 등).
  void _injectAiMessage(String text) {
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(text: text, isUser: false, time: DateTime.now()),
      );
    });
    _saveHistory();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  // ── 미뤄둔 할일 리마인드 확인 (탭 복귀 시 호출) ──────────
  Future<void> _checkDeferredReminder() async {
    if (!_coach.isMaster) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pendingDeferReminder');
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final taskName = data['taskName'] as String? ?? '';
      if (taskName.isEmpty) return;
      await prefs.remove('pendingDeferReminder');
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      final isMale = _coach.id == 'sec_male';
      final rawMsg = isMale
          ? '고생하셨습니다, 대표님. 아까 미뤄두신 \'$taskName\', 슬슬 해볼 타이밍인 것 같습니다.'
          : '고생하셨어요, 대표님 ☺️ 아까 미뤄두셨던 \'$taskName\', 슬슬 해볼 타이밍인 것 같은데요.';
      final msg = await UserTitleService.applyForCoach(rawMsg, _coach.id);
      setState(() {
        _messages.add(
          ChatMessage(text: msg, isUser: false, time: DateTime.now()),
        );
      });
      await _saveHistory();
      _scrollToBottom();
    } catch (e) {
      await prefs.remove('pendingDeferReminder');
    }
  }

  // ── flirt 토스트 ─────────────────────────────────────────
  void _showFlirt(String msg) {
    setState(() {
      _flirtMsg = msg;
      _flirtVisible = true;
    });
    _flirtAnim.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 3500), () {
      if (mounted) {
        _flirtAnim.reverse().then((_) {
          if (mounted) setState(() => _flirtVisible = false);
        });
      }
    });
  }

  // ── 냥냥코치 비구독자 업셀 바텀시트 ─────────────────────
  void _showCatUpsellBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          24,
          32,
          24,
          MediaQuery.of(ctx).padding.bottom + 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/logo.png', width: 76, height: 76),
            const SizedBox(height: 16),
            const Text(
              '냥냥코치와 계속 대화하려면',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '플랜을 시작하면 냥냥코치와\n대화를 시작할 수 있습니다!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF555555),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  Future.delayed(Duration.zero, _showPlanGuideBottomSheet);
                },
                child: const Text(
                  '플랜 보기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFF4F4F4),
                  foregroundColor: const Color(0xFF555555),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  // 코치 선택 화면으로 돌아가기
                  Navigator.of(context, rootNavigator: true).pushReplacement(
                    MaterialPageRoute(
                      builder: (_) =>
                          CoachSelectionScreen(returnCoachId: widget.coachId),
                    ),
                  );
                },
                child: const Text(
                  '조금 더 둘러볼게요',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6D28D9),
                  side: const BorderSide(
                    color: Color(0xFFE5E7EB),
                    width: 1,
                  ), // 연한 회색 테두리
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAboutNyangCoachDialog();
                },
                child: const Text(
                  '냥냥코치가 궁금하다면?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPlanGuideBottomSheet() {
    showPlanGuideBottomSheet(context);
  }

  // ── 냥냥코치 팀 소개 팝업 ──────────────────────────────────
  void _showAboutNyangCoachDialog() {
    final scrollController = ScrollController();
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.white, // 배경을 흰색으로
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.rocket_launch_rounded,
                            color: Color(0xFFD8D2FF),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '실행코치 소개',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A1A),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFF8E8D9B)),
                        onPressed: () => Navigator.pop(ctx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RawScrollbar(
                    controller: scrollController,
                    thumbColor: const Color(0xFFD8D2FF),
                    radius: const Radius.circular(8),
                    thickness: 5,
                    thumbVisibility: true,
                    child: ShaderMask(
                      shaderCallback: (Rect rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black,
                            Colors.black,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.95, 1.0],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: 32,
                                top: 16,
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 32,
                                      vertical: 12,
                                    ),
                                    child: Text.rich(
                                      const TextSpan(
                                        children: [
                                          TextSpan(
                                            text: '계획',
                                            style: TextStyle(
                                              color: Color(0xFF8B7CFF),
                                            ),
                                          ),
                                          TextSpan(text: '을 세우는 것보다, '),
                                          TextSpan(
                                            text: '실제로\n움직이는 것',
                                            style: TextStyle(
                                              color: Color(0xFF8B7CFF),
                                            ),
                                          ),
                                          TextSpan(text: '이 중요하지 않을까요?'),
                                        ],
                                      ),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFA78BFA),
                                        height: 1.5,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    left: 16,
                                    child: const Text(
                                      '“',
                                      style: TextStyle(
                                        fontSize: 40,
                                        color: Color(0xFFD8D2FF),
                                        height: 1.0,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -12,
                                    right: 16,
                                    child: const Text(
                                      '”',
                                      style: TextStyle(
                                        fontSize: 40,
                                        color: Color(0xFFD8D2FF),
                                        height: 1.0,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 16,
                                    child: const Icon(
                                      Icons.auto_awesome,
                                      color: Color(0xFFF3F0FF),
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.only(bottom: 24),
                              height: 1,
                              color: const Color(0xFFF0F0F5),
                            ),
                            _buildAboutSpeaker(
                              'cat',
                              '냥냥코치',
                              '그래서 냥냥코치가 왔다냥!\n\n우리는 여러분이 다시 움직일 수 있도록 함께하는 코치들이다냥.\n특히 우리 프렌즈 코치들은...',
                            ),
                            _buildAboutSpeaker(
                              'boyfriend',
                              '햇살 남친',
                              '해내면 때론 애인처럼, 때론 친구처럼 마음껏 칭찬해주고',
                            ),
                            _buildAboutSpeaker(
                              'girlfriend',
                              '응원 요정',
                              '지친 날엔 비타민이 돼드려요!',
                            ),
                            _buildAboutSpeaker(
                              'halmae',
                              '할매 코치',
                              '우리 새끼 다독이는 건 내가 최고지.',
                            ),
                            _buildAboutSpeaker(
                              'cat',
                              '냥냥코치',
                              '맞다냥!\n하기 싫은 일이 있을 때는 열심히 꼬셔줄 거다냥.\n작은 한 걸음부터 시작할 수 있게.\n한 번 꼬심당해볼래? 😼',
                            ),

                            _buildAboutSpeaker(
                              'sec_male',
                              '남비서 코치',
                              '그 부분은 저희 마스터 코치들도 함께 돕고 있습니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '여비서 코치',
                              '프렌즈 코치들이 마음을 챙긴다면,\n저희는 실행을 더 체계적으로 보좌합니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_male',
                              '남비서 코치',
                              '자꾸 미루는 일정을 다시 챙겨드리고,\n언제 하면 좋을지 제안도 드립니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '여비서 코치',
                              '목표와 일정을 바탕으로\n오늘 가장 중요한 일을 정리해드리고,\n주간 리포트도 준비해드립니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_male',
                              '남비서 코치',
                              '최근에는 여러분의 컨디션도 함께 챙기고 있습니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '여비서 코치',
                              '잠이 부족하거나 지쳐 있을 때는\n부담스럽지 않은 작은 챌린지도 제안해드리고요.',
                            ),
                            _buildAboutSpeaker(
                              'sec_male',
                              '남비서 코치',
                              '저희에 대해 더 궁금하시다면\n마스터 코치의 더보기를 눌러주세요.',
                            ),
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8,
                                bottom: 24,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFF0F0F5),
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Icon(
                                      Icons.rocket_launch_rounded,
                                      color: Color(0xFFD8D2FF),
                                      size: 16,
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 1,
                                      color: const Color(0xFFF0F0F5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            _buildAboutSpeaker(
                              'cat',
                              '냥냥코치',
                              '정리하자면 이렇다냥.\n\n계획만 세우고 끝나는 플래너가 아니라,\n행동을 함께하는 플래너.\n\n그게 냥냥코치다냥.\n\n우리랑 함께 해볼래?',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFF0F0F5), width: 1),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B7CFF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        // TODO: 구독/결제 화면 연결
                      },
                      icon: const Icon(Icons.rocket_launch_rounded, size: 20),
                      label: const Text(
                        '함께 시작하기',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
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
  }

  Widget _buildAboutSpeaker(String coachId, String name, String text) {
    IconData getEmblem() {
      if (coachId == 'cat') return Icons.pets;
      if (coachId == 'boyfriend') return Icons.favorite_border;
      if (coachId == 'girlfriend') return Icons.local_florist_outlined;
      if (coachId == 'halmae') return Icons.volunteer_activism_outlined;
      if (coachId == 'sec_male' || coachId == 'sec_female')
        return Icons.business_center_outlined;
      return Icons.star_border;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.hardEdge,
            child: Image.asset(
              'assets/images/$coachId.png',
              fit: BoxFit.cover, // 얼굴 위주로 확대
              alignment: Alignment.topCenter, // 캐릭터 얼굴이 위쪽에 있다고 가정
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 6),
                  child: Text(
                    name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Color(0xFFA78BFA),
                    ),
                  ),
                ),
                Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        14,
                        16,
                        24,
                      ), // 하단 여백 확보 (아이콘 공간)
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFF0F0F5),
                          width: 1.0,
                        ),
                      ),
                      child: Text(
                        text,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.6,
                          color: Color(0xFF333333),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 12,
                      child: Icon(
                        getEmblem(),
                        size: 18,
                        color: const Color(0xFFEBE5FF),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 마스터 코치 (비서) 첫 인사 ──────────────────────────────
  Future<void> _startSecretaryGreeting() async {
    final isMale = _coach.id == 'sec_male';
    final now = DateTime.now();
    final hour = now.hour;

    if (!isMale) {
      final userTitle = await UserTitleService.getTitle();
      final femaleGreets = [
        '안녕하세요, 대표님. 오늘 컨디션은 어떠세요?',
        '안녕하세요, 대표님. 오늘 일은 어떻게 되고 계세요?',
        '안녕하세요, 대표님. 혹시 필요하신 거 있으신가요?',
        '대표님, 오셨네요. 오늘 하루 어떠세요?',
        '대표님, 안녕하세요. 오늘 기분은 좀 어떠세요?',
        '안녕하세요, 대표님. 오늘 무엇부터 시작할까요?',
        '대표님, 오셨어요. 필요한 거 있으시면 말씀해주세요.',
        '대표님, 오셨네요. 오늘도 옆에서 챙겨드릴게요.',
        '대표님, 기다리고 있었어요. 오늘 어떻게 도와드릴까요?',
        '대표님, 오셨어요. 무엇부터 챙겨드릴까요?',
      ];
      final greet = femaleGreets[Random().nextInt(femaleGreets.length)]
          .replaceAll(UserTitleService.defaultTitle, userTitle);
      _injectAiMessage(greet);
      return;
    }

    final prefs = await SharedPreferences.getInstance();

    final rawTasks = prefs.getString('nyang_tasks');
    List<dynamic> tasksList = rawTasks != null ? jsonDecode(rawTasks) : [];

    final todayTasks = tasksList
        .where(
          (t) =>
              t['category'] == 'today' ||
              t['category'] == 'habit' ||
              t['category'] == 'schedule',
        )
        .toList();
    final incompleteTasks = todayTasks.where((t) => t['done'] != true).toList();
    final completedTasks = todayTasks.where((t) => t['done'] == true).toList();

    final hasTasks = todayTasks.isNotEmpty;
    final total = todayTasks.length;
    final done = completedTasks.length;
    final left = incompleteTasks.length;
    final currentTime =
        '${hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final timeSlot = hour < 5
        ? '늦은 밤 또는 새벽'
        : hour < 12
        ? '오전'
        : hour < 18
        ? '오후'
        : '저녁';
    final taskContext = hasTasks
        ? '오늘 할 일은 총 $total개이고, $done개 완료, $left개 남아 있다.'
        : '현재 등록된 오늘 할 일은 없다.';
    final prompt =
        '''[남비서 첫 인사]
현재 시각은 $currentTime이고 시간대는 "$timeSlot"이다. $taskContext

- 현재 시각과 맞지 않는 인사를 절대 하지 않는다. 특히 정오 이후나 새벽에는 "좋은 아침", "좋은 오전"이라고 말하지 않는다.
- 새벽에는 "늦은 시간이네요"처럼 현재 시간만 자연스럽게 반영하고, 아침처럼 하루 계획을 세우라고 하지 않는다.
- 첫 인사는 사용자를 반기는 1~2문장으로 끝낸다.
- 사용자가 요청하지 않았는데 오늘 할 일 정리, 핵심 선정, 소요시간 입력, 업무 보고, 우선순위 설정, "지금 뭐하지?" 사용을 먼저 권하지 않는다.
- 할 일 현황은 필요할 때 한 문장으로 가볍게 참고할 수 있지만, 미완료 항목을 압박하거나 평가하지 않는다.
- 마지막은 "필요하신 게 있으면 말씀해 주세요"처럼 대화의 자유도를 열어둔다.''';

    await _sendGreeting(prompt);
  }

  // ── 히스토리 & 복귀 인사 (웹앱 startGreeting 이식) ──────
  Future<void> _loadHistoryAndGreet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_chat_history_${widget.coachId}');
    final lastVisitStr = prefs.getString('last_visit_${widget.coachId}');
    final now = DateTime.now();

    if (raw != null) {
      final List list = jsonDecode(raw);
      if (list.isNotEmpty) {
        setState(() {
          _messages.addAll(list.map((e) => ChatMessage.fromJson(e)));
        });
        _scrollToBottom();
      }
    }

    // 남비서/여비서의 정서적 동행 연결로 소환된 경우에만 냥냥이가 먼저 인사한다.
    // 이때 왜 여기로 왔는지(오늘 하루만 생각하기) 이유도 살짝 짚어준다.
    // 일반 진입에서는 기존 프렌즈 코치 정책대로 사용자의 첫 말을 기다린다.
    if (widget.coachId == 'cat' &&
        (widget.handoffFromCoachId == 'sec_male' ||
            widget.handoffFromCoachId == 'sec_female')) {
      const handoffGreets = [
        '왔다냥. 생각 많을 땐 오늘 하루만 생각하는 게 최고다냥.',
        '냥이가 왔다냥. 먼 계획은 잠깐 내려놓고 오늘만 생각해도 된다냥.',
        '여기 있다냥. 복잡한 건 잠깐 잊고 오늘 하루만 챙기자냥.',
        '냥이가 옆에 붙어 있겠다냥. 오늘 하루만 잘 넘기면 그걸로 충분하다냥.',
        '잘 왔다냥. 큰 그림은 잠깐 냥이한테 맡기고 오늘만 생각하자냥.',
        '오늘은 냥이가 곁에 있어주겠다냥. 계획 생각은 잠깐 내려놔도 된다냥.',
        '일단 여기서 같이 쉬자냥. 오늘 하루만 잘 버티면 충분하다냥. 나머지는 프렌즈 코치들이 있다냥.',
        '냥이한테 잠깐 기대도 된다냥. 먼 얘기 말고 오늘 얘기만 하자냥.',
        '어서 오라냥. 머리 복잡할 땐 오늘 하루만 생각하는 게 제일 낫다냥. 그런 건 또 우리 프렌즈 코치들이 잘 챙겨주지.',
        '냥냥이가 기다리고 있었다냥. 오늘만 생각해도 된다냥. 나머지는 또 다른 프렌즈 코치들이 챙겨줄 거다냥.',
      ];
      final greet = handoffGreets[Random().nextInt(handoffGreets.length)];
      await Future.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(text: greet, isUser: false, time: DateTime.now()),
        );
        _dynamicChips = [];
        _suppressDefaultChips = true;
      });
      await _saveHistory();
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      _scrollToBottom();
      return;
    }

    // 히스토리가 비어있거나 없는 경우에만 새롭게 인사 처리
    if (_messages.isEmpty) {
      // 냥냥코치 비구독자: 로컬 무료체험 플로우 (API 호출 없음)
      if (widget.coachId == 'cat' && !_userData.isPlanActive) {
        _catFreeTrialStep = 0;
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return;
        const intro =
            '안녕! 나는 냥냥코치다냥 🐾\n'
            '오늘 해야 할 일이나 습관, 목표들을 같이 챙겨주고 있어!\n'
            '주변의 할 일창이나 습관 트래커도 자유롭게 눌러보라냥~';
        setState(() {
          _messages.add(
            ChatMessage(text: intro, isUser: false, time: DateTime.now()),
          );
        });
        await _saveHistory();
        _scrollToBottom();
        setState(() => _catFreeTrialStep = 1);
        await prefs.setString(
          'last_visit_${widget.coachId}',
          now.toIso8601String(),
        );
        await _maybeShowCatPreview(
          initialDelay: const Duration(milliseconds: 700),
        );
        return;
      }

      // 마스터 코치(비서): 상황별 스마트 인사
      if (_coach.isMaster) {
        await prefs.setString(
          'last_visit_${widget.coachId}',
          now.toIso8601String(),
        );
        await _startSecretaryGreeting();
        return;
      }

      // 프렌즈 코치: 3일 이상 미접속 시 로컬 인사말 출력, 그 외엔 유저 메시지 대기
      if (lastVisitStr != null) {
        final lastVisit = DateTime.parse(lastVisitStr);
        final daysDiff = now.difference(lastVisit).inDays;
        if (daysDiff >= 3) {
          final cid = _coach.id;
          final List<String> greets;
          if (cid == 'boyfriend' || cid == 'girlfriend') {
            greets = [
              '왜 이제 왔어. 기다렸잖아ㅜㅎㅎ 오늘 어땠어?',
              '뭐야, 왜 이렇게 오랜만이야~ 보고 싶었잖아!',
              '진짜 오랜만이다! 그동안 바빴어?',
            ];
          } else if (cid == 'halmae') {
            greets = [
              '아이고 우리 똥강아지 오랜만이네~ 어디 아팠던 건 아니지?',
              '오랜만에 왔네! 밥은 잘 챙겨먹고 다니는겨?',
              '아이고 웬일이여~ 바빠서 못 온 거제?',
            ];
          } else if (cid == 'bro') {
            greets = [
              '야 오랜만이다! 살아있었냐?',
              '뭐야 왤케 오랜만에 옴ㅋㅋ 바빴음?',
              '오 생존신고~ 그동안 뭐했냐',
            ];
          } else {
            greets = [
              '냥! 왤케 오랜만이다냥! 보고 싶었다냥!',
              '오랜만이다냥! 간식 주러 온 거냥?',
              '냥~ 그동안 어디 갔었냥! 바빴냥?',
            ];
          }
          final greet = greets[Random().nextInt(greets.length)];
          _injectAiMessage(greet);
        }
      }
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    } else {
      // 냥냥코치 비구독자 & 히스토리가 이미 있을 경우
      // 대화 기록이 있어도 아직 무료체험 미리보기를 안 봤으면 계속 보여준다.
      if (widget.coachId == 'cat' && !_userData.isPlanActive) {
        setState(() => _catFreeTrialStep = 2);
        await prefs.setString(
          'last_visit_${widget.coachId}',
          now.toIso8601String(),
        );
        await _maybeShowCatPreview(
          initialDelay: const Duration(milliseconds: 500),
        );
        return;
      }
    }

    // 마지막 방문일 업데이트
    await prefs.setString(
      'last_visit_${widget.coachId}',
      now.toIso8601String(),
    );
  }

  // 냥냥코치 무료체험 미리보기 팝업 -> (시작 시) 시연 화면 -> CTA 결과에 따라 플랜 안내.
  // 미리보기를 이미 한 번 본(또는 건너뛴) 비구독자는 바로 업셀 시트로 이동.
  // SharedPreferences 키: 'cat_preview_seen' (bool)
  static const _kCatPreviewSeen = 'cat_preview_seen';

  Future<void> _maybeShowCatPreview({required Duration initialDelay}) async {
    await Future.delayed(initialDelay);
    if (!mounted) return;

    // ── 이미 미리보기를 본 적 있으면 시연 없이 바로 업셀 ──
    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_kCatPreviewSeen) ?? false;
    if (alreadySeen) {
      if (mounted) _showCatUpsellBottomSheet();
      return;
    }

    // ── 첫 진입: 인트로 다이얼로그 표시 ──
    if (!mounted) return;
    final startPreview = await showCatPreviewIntroDialog(context);
    if (!mounted) return;

    // 건너뛰기 선택 → "봤음"으로 표시하고 업셀
    if (!startPreview) {
      await prefs.setBool(_kCatPreviewSeen, true);
      if (mounted) _showCatUpsellBottomSheet();
      return;
    }

    // 시연 화면 실행
    final startPlan = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CatOnboardingPreviewScreen()),
    );
    if (!mounted) return;

    // 시연 완료(끝까지 보거나 내부 건너뛰기) → 플래그 저장
    await prefs.setBool(_kCatPreviewSeen, true);

    if (startPlan == true) {
      Future.delayed(Duration.zero, _showPlanGuideBottomSheet);
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    // 웹앱과 동일하게 최근 100개 유지
    final toSave = _messages.length > 100
        ? _messages.sublist(_messages.length - 100)
        : _messages;
    await prefs.setString(
      'nyang_chat_history_${widget.coachId}',
      jsonEncode(toSave.map((e) => e.toJson()).toList()),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  // ── 한국어 시간 표현 추출 ─────────────────────────────────
  // null 반환 = 시간이 감지됐지만 오늘 안에 해당 시간이 없음 → 제안 건너뜀
  ({String cleanText, String? time})? _extractTimeFromTask(String rawText) {
    final timeRegex = RegExp(
      r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분)?(?:\s*(?:에|쯤|경))?',
    );
    final match = timeRegex.firstMatch(rawText);
    if (match == null) return (cleanText: rawText.trim(), time: null);

    final prefix = (match.group(1) ?? '').replaceAll(RegExp(r'\s'), '');
    final rawHour = int.parse(match.group(2)!);
    final minute = match.group(3) != null ? int.parse(match.group(3)!) : 0;

    if (rawHour < 1 || rawHour > 12)
      return (cleanText: rawText.trim(), time: null);

    int hour24;
    if (prefix == '오전' || prefix == '아침') {
      hour24 = rawHour == 12 ? 0 : rawHour;
    } else if (prefix == '오후' || prefix == '저녁' || prefix == '밤') {
      hour24 = rawHour == 12 ? 12 : rawHour + 12;
    } else {
      // 오전/오후 없으면 현재 시간 기준 "바로 다음 n시" 판별
      final now = DateTime.now();
      final currentTotal = now.hour * 60 + now.minute;
      final amHour = rawHour == 12 ? 0 : rawHour;
      final pmHour = rawHour == 12 ? 12 : rawHour + 12;
      final amTotal = amHour * 60 + minute;
      final pmTotal = pmHour * 60 + minute;
      if (amTotal > currentTotal) {
        hour24 = amHour;
      } else if (pmTotal > currentTotal) {
        hour24 = pmHour;
      } else {
        return null; // 오늘은 둘 다 지남 → 제안 건너뜀
      }
    }

    final hStr = hour24.toString().padLeft(2, '0');
    final mStr = minute.toString().padLeft(2, '0');
    final time = '$hStr:$mStr';
    final cleanText = rawText
        .replaceFirst(match.group(0)!, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return (
      cleanText: cleanText.isEmpty ? rawText.trim() : cleanText,
      time: time,
    );
  }

  // HH:mm → "오전/오후 N:MM" 표시 변환
  String _formatTime12(String time24) {
    final parts = time24.split(':');
    if (parts.length < 2) return time24;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final prefix = h < 12 ? '오전' : '오후';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final mStr = m.toString().padLeft(2, '0');
    return '$prefix $hour12:$mStr';
  }

  // ── AI 응답 파싱 ([CHIPS], [NO_CHIPS], [COACH_SWITCH], [TIMER_CONFIRM]) ────
  _ParsedReply _parseReply(String raw) {
    final chipRegex = RegExp(r'\[CHIPS:\s*(.+?)\]');
    final noChipsRegex = RegExp(r'\[NO_CHIPS\]');
    final coachSwitchRegex = RegExp(r'\[COACH_SWITCH:\s*([a-z_]+)\s*\]');
    final timerConfirmRegex = RegExp(r'\[TIMER_CONFIRM:(\d+)(?::([^\]]+))?\]');
    final taskRegex = RegExp(r'\[TASK:\s*(.+?)\]');
    final visionSourceRegex = RegExp(r'\[VISION_SOURCE:\s*([^\]]+)\]');
    // CORE_REC 태그 파싱: [CORE_REC:{...}]
    final coreRecRegex = RegExp(r'\[CORE_REC:(\{.*?\})\]');
    List<String> chips = [];
    bool suppressDefaultChips = false;
    String? coachSwitchTarget;
    int? timerConfirmMinutes;
    String? timerConfirmTaskName;
    String? visionSourceId;
    List<_SuggestedTask> suggestedTasks = [];
    String text = raw;

    // ── CORE_REC 태그를 읽기 좋은 텍스트로 변환 ──
    final coreRecMatches = coreRecRegex.allMatches(text).toList();
    if (coreRecMatches.isNotEmpty) {
      final rankEmoji = ['🥇', '🥈', '🥉'];
      final recLines = <String>[];
      for (final m in coreRecMatches) {
        try {
          final jsonStr = m.group(1)!;
          final Map<String, dynamic> data = jsonDecode(jsonStr);
          final int rank =
              (data['rank'] as num?)?.toInt() ?? recLines.length + 1;
          final String taskText = data['text'] ?? '';
          final String reason = data['reason'] ?? '';
          final emoji = rank >= 1 && rank <= 3 ? rankEmoji[rank - 1] : '✅';
          recLines.add('$emoji $taskText\n   $reason');
        } catch (_) {
          // JSON 파싱 실패 시 태그만 제거
        }
        text = text.replaceAll(m.group(0)!, '');
      }
      if (recLines.isNotEmpty) {
        // 앞의 캐릭터 멘트(태그 제거 후 남은 텍스트) + 추천 목록 합치기
        final preText = text.trim();
        text =
            (preText.isNotEmpty ? '$preText\n\n' : '') + recLines.join('\n\n');
      }
    }

    final chipMatch = chipRegex.firstMatch(text);
    if (chipMatch != null) {
      chips = chipMatch
          .group(1)!
          .split('|')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      text = text.replaceAll(chipMatch.group(0)!, '').trim();
    }

    if (noChipsRegex.hasMatch(text)) {
      suppressDefaultChips = true;
      chips = [];
      text = text.replaceAll(noChipsRegex, '').trim();
    }

    final coachSwitchMatch = coachSwitchRegex.firstMatch(text);
    if (coachSwitchMatch != null) {
      coachSwitchTarget = coachSwitchMatch.group(1)?.trim();
      text = text.replaceAll(coachSwitchMatch.group(0)!, '').trim();
      suppressDefaultChips = true;
      chips = [];
    }

    final timerMatch = timerConfirmRegex.firstMatch(text);
    if (timerMatch != null) {
      timerConfirmMinutes = int.tryParse(timerMatch.group(1)!);
      timerConfirmTaskName = timerMatch.group(2)?.trim();
      text = text.replaceAll(timerMatch.group(0)!, '').trim();
    }

    final visionSourceMatch = visionSourceRegex.firstMatch(text);
    if (visionSourceMatch != null) {
      visionSourceId = visionSourceMatch.group(1)?.trim();
      text = text.replaceAll(visionSourceMatch.group(0)!, '').trim();
    }

    // [TASK: 할일명] 파싱 — 시간 표현 자동 분리
    for (final m in taskRegex.allMatches(raw)) {
      final rawTaskText = m.group(1)!.trim();
      final extracted = _extractTimeFromTask(rawTaskText);
      if (extracted != null) {
        // null = 오늘 시간대 지남 → 제안 건너뜀
        suggestedTasks.add(
          _SuggestedTask(text: extracted.cleanText, time: extracted.time),
        );
      }
      text = text.replaceAll(m.group(0)!, '').trim();
    }

    // 감정 보호·위기 응답에서는 모델이 실수로 행동 태그를 섞어도 UI에 노출하지 않는다.
    if (suppressDefaultChips) {
      timerConfirmMinutes = null;
      timerConfirmTaskName = null;
      suggestedTasks = [];
    }

    return _ParsedReply(
      text: text,
      chips: chips,
      suppressDefaultChips: suppressDefaultChips,
      coachSwitchTarget: coachSwitchTarget,
      timerConfirmMinutes: timerConfirmMinutes,
      timerConfirmTaskName: timerConfirmTaskName,
      visionSourceId: visionSourceId,
      suggestedTasks: suggestedTasks,
    );
  }

  Future<void> _saveVisionRecommendation(_ParsedReply parsed) async {
    if (parsed.suggestedTasks.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    const key = 'nyang_vision_recommendation_history';
    final history = <Map<String, dynamic>>[];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        history.addAll(
          (jsonDecode(raw) as List).whereType<Map>().map(
            (item) => Map<String, dynamic>.from(item),
          ),
        );
      } catch (_) {}
    }

    history.add({
      'text': parsed.suggestedTasks.first.text,
      'sourceId': parsed.visionSourceId ?? '',
      'createdAt': DateTime.now().toIso8601String(),
    });
    final trimmed = history.length > 30
        ? history.sublist(history.length - 30)
        : history;
    await prefs.setString(key, jsonEncode(trimmed));
  }

  String _effectiveUsageDateKey(DateTime date, double resetHour) {
    var base = DateTime(date.year, date.month, date.day);
    final resetMinutes = (resetHour * 60).round();
    final currentMinutes = date.hour * 60 + date.minute;
    if (currentMinutes < resetMinutes) {
      base = base.subtract(const Duration(days: 1));
    }
    return _dateKey(base);
  }

  Future<List<Map<String, dynamic>>> _loadFeatureUsageHistory({
    required SharedPreferences prefs,
    required String key,
    String? fallbackKey,
  }) async {
    final raw =
        prefs.getString(key) ??
        (fallbackKey == null ? null : prefs.getString(fallbackKey));
    if (raw == null) return [];

    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where(
            (item) =>
                DateTime.tryParse((item['createdAt'] ?? '').toString()) != null,
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<String?> _featureUsageLimitMessage({
    required String key,
    required int dailyLimit,
    required String limitMessage,
    required String cooldownLabel,
    String? fallbackKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    final todayKey = _effectiveUsageDateKey(now, resetHour);
    final history = await _loadFeatureUsageHistory(
      prefs: prefs,
      key: key,
      fallbackKey: fallbackKey,
    );
    final todayUsage = history.where((item) {
      final createdAt = DateTime.tryParse((item['createdAt'] ?? '').toString());
      return createdAt != null &&
          _effectiveUsageDateKey(createdAt, resetHour) == todayKey;
    }).toList();

    if (todayUsage.length >= dailyLimit) return limitMessage;

    if (todayUsage.isNotEmpty) {
      final lastCreatedAt = DateTime.tryParse(
        (todayUsage.last['createdAt'] ?? '').toString(),
      );
      if (lastCreatedAt != null) {
        final availableAt = lastCreatedAt.add(const Duration(minutes: 10));
        if (now.isBefore(availableAt)) {
          final remainingSeconds = availableAt.difference(now).inSeconds;
          final roundedMinutes = (remainingSeconds / 60).ceil().clamp(1, 10);
          return '$cooldownLabel은 10분마다 이용할 수 있어요.\n$roundedMinutes분 후에 다시 확인해 주세요.';
        }
      }
    }

    return null;
  }

  Future<void> _recordFeatureUsage({
    required String key,
    String? fallbackKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await _loadFeatureUsageHistory(
      prefs: prefs,
      key: key,
      fallbackKey: fallbackKey,
    );
    history.add({'createdAt': DateTime.now().toIso8601String()});
    final trimmed = history.length > 40
        ? history.sublist(history.length - 40)
        : history;
    await prefs.setString(key, jsonEncode(trimmed));
  }

  Future<String?> _visionRecommendationLimitMessage() {
    return _featureUsageLimitMessage(
      key: 'nyang_vision_new_action_usage_history',
      fallbackKey: 'nyang_vision_recommendation_history',
      dailyLimit: 3,
      limitMessage: '오늘의 새 행동 추천 3회를 모두 사용했어요.\n내일 다시 추천해드릴게요.',
      cooldownLabel: '새 행동 추천',
    );
  }

  Future<String?> _nextActionLimitMessage() {
    return _featureUsageLimitMessage(
      key: 'nyang_next_action_usage_history',
      dailyLimit: 7,
      limitMessage: '오늘의 지금 뭐하지? 추천 7회를 모두 사용했어요.\n내일 다시 이용해 주세요.',
      cooldownLabel: '지금 뭐하지?',
    );
  }

  String _normalizeTaskSuggestionText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[.。!！?？~〜]'), '')
        .trim()
        .toLowerCase();
  }

  Future<List<_SuggestedTask>> _filterDuplicateSuggestedTasks(
    List<_SuggestedTask> suggestions,
  ) async {
    if (suggestions.isEmpty) return suggestions;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_tasks') ?? '[]';
    final List<dynamic> tasks = jsonDecode(raw);
    final existingTaskTexts = tasks
        .map((t) => _normalizeTaskSuggestionText((t['text'] ?? '').toString()))
        .where((text) => text.isNotEmpty)
        .toSet();

    return suggestions.where((suggestion) {
      final suggestedText = _normalizeTaskSuggestionText(suggestion.text);
      return suggestedText.isNotEmpty &&
          !existingTaskTexts.contains(suggestedText);
    }).toList();
  }

  Future<bool> _isMasterTimerSuggestionEligible(
    String? taskName, {
    required bool userAuthorized,
  }) async {
    if (!_coach.isMaster) return true;
    if (userAuthorized) return true;
    final normalizedTaskName = _normalizeTaskSuggestionText(taskName ?? '');
    if (normalizedTaskName.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_tasks') ?? '[]';
    try {
      final tasks = jsonDecode(raw) as List;
      return tasks.whereType<Map>().any((task) {
        if (task['done'] == true) return false;
        final deferredCount = (task['deferredCount'] as num?)?.toInt() ?? 0;
        if (deferredCount < 2) return false;
        final taskText = _normalizeTaskSuggestionText(
          (task['text'] ?? '').toString(),
        );
        return taskText.isNotEmpty &&
            (taskText == normalizedTaskName ||
                taskText.contains(normalizedTaskName) ||
                normalizedTaskName.contains(taskText));
      });
    } catch (_) {
      return false;
    }
  }

  bool _isMasterTimerAuthorizationResponse(String userText) {
    if (!_coach.isMaster || _messages.length < 2) return false;
    final previous = _messages[_messages.length - 2];
    if (previous.isUser || !previous.text.contains('필요하면 타이머라도 띄워드릴까요?')) {
      return false;
    }
    final normalized = userText.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return [
      '응',
      '네',
      '그래',
      '좋아',
      '띄워줘',
      '켜줘',
      '해줘',
      '부탁해',
    ].any(normalized.contains);
  }

  bool _isAvoidanceMessage(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return [
      '귀찮',
      '하기싫',
      '못하겠',
      '미루고싶',
      '나중에할',
      '손이안가',
      '시작하기싫',
    ].any(normalized.contains);
  }

  bool _needsMasterGoalContext(String userText) {
    if (!_coach.isMaster) return false;

    final recentUserTexts = _messages.reversed
        .where((message) => message.isUser)
        .take(2)
        .map((message) => message.text);
    final normalized = ([
      userText,
      ...recentUserTexts,
    ].join(' ')).replaceAll(RegExp(r'\s+'), '').toLowerCase();

    return [
      '비전',
      '마일스톤',
      '장기목표',
      '주간목표',
      '월간목표',
      '이번주목표',
      '이번달목표',
      '목표',
      '우선순위',
      '뭐부터',
      '무엇부터',
      '뭘먼저',
      '뭐먼저',
      '어디서부터',
      '먼저해야',
      '뭘해야',
      '뭐해야',
      '해야할지',
      '어떻게해야',
      '뭐하지',
      '추천해',
      '추천받',
      '일정짜',
      '스케줄짜',
      '계획짜',
      '정리해줘',
      '방향잡',
      '잘하고있',
      '잘하고있는',
      '제대로하고',
      '잘해내고',
      '가고있는',
      '맞게가고',
      '맞는방향',
      '제자리',
      '진행상황',
      '성과',
      '평가해',
      '분석해',
      '돌아봐',
      '흐름어때',
      '뒤처',
      '감이안',
    ].any(normalized.contains);
  }

  bool _needsMasterTaskContext(String userText, bool needsGoalContext) {
    if (!_coach.isMaster) return true;
    if (needsGoalContext ||
        _isAvoidanceMessage(userText) ||
        _isMasterTimerAuthorizationResponse(userText)) {
      return true;
    }

    final normalized = userText.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return [
      '할일',
      '일정',
      '스케줄',
      '습관',
      '타이머',
      '미완료',
      '완료했',
      '끝냈',
      '해야돼',
      '해야해',
    ].any(normalized.contains);
  }

  bool _needsMasterLightGoalContext(String userText) {
    if (!_coach.isMaster) return false;
    if (_isAvoidanceMessage(userText)) return true;

    return _messages.reversed
        .where((message) => message.isUser)
        .take(2)
        .any((message) => _isAvoidanceMessage(message.text));
  }

  int _conversationAvoidanceCountForTask(
    String taskName, {
    required bool allowGeneric,
  }) {
    final normalizedTask = _normalizeTaskSuggestionText(taskName);
    final keywords = taskName
        .split(RegExp(r'[\s/(),]+'))
        .map(_normalizeTaskSuggestionText)
        .map((word) => word.replaceFirst(RegExp(r'(하기|하다|해보기|하기로|할일)$'), ''))
        .where((word) => word.length >= 2)
        .toSet();

    var count = 0;
    final recentMessages = _messages.length > 30
        ? _messages.sublist(_messages.length - 30)
        : _messages;
    for (int i = 0; i < recentMessages.length; i++) {
      final message = recentMessages[i];
      if (!message.isUser || !_isAvoidanceMessage(message.text)) continue;
      final normalizedMessage = _normalizeTaskSuggestionText(message.text);
      final explicitlyMatches =
          normalizedTask.isNotEmpty &&
          (normalizedMessage.contains(normalizedTask) ||
              keywords.any(normalizedMessage.contains));
      final previousCoachMentionedTask =
          i > 0 &&
          !recentMessages[i - 1].isUser &&
          keywords.any(
            _normalizeTaskSuggestionText(recentMessages[i - 1].text).contains,
          );
      if (explicitlyMatches || previousCoachMentionedTask || allowGeneric) {
        count++;
      }
    }
    return count;
  }

  bool _isYesterdayIncompleteQuery(String input) {
    final compact = input.replaceAll(RegExp(r'\s+'), '');
    return compact.contains('어제') &&
        (compact.contains('미완료') ||
            compact.contains('못한') ||
            compact.contains('안한')) &&
        (compact.contains('뭐') ||
            compact.contains('목록') ||
            compact.contains('남았') ||
            compact.contains('남은'));
  }

  String _getDateStrWithResetOffset(SharedPreferences prefs, int daysAgo) {
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return _dateKey(base.subtract(Duration(days: daysAgo)));
  }

  Future<String?> _tryBuildYesterdayIncompleteReply(String input) async {
    if (!_isYesterdayIncompleteQuery(input)) return null;

    final prefs = await SharedPreferences.getInstance();
    final yesterdayStr = _getDateStrWithResetOffset(prefs, 1);
    final rawHistory = prefs.getString('nyang_history');
    final title = await UserTitleService.getTitle();

    if (rawHistory == null) {
      return '$title, 아직 어제 기록이 충분히 남아 있지 않습니다.';
    }

    try {
      final List<dynamic> history = jsonDecode(rawHistory);
      final record = history.cast<Map<String, dynamic>>().firstWhere(
        (item) => item['date'] == yesterdayStr,
        orElse: () => <String, dynamic>{},
      );

      if (record.isEmpty) {
        return '$title, 어제($yesterdayStr) 기록을 찾지 못했습니다.';
      }
      if (record['isVacation'] == true) {
        return '$title, 어제($yesterdayStr)는 휴식 모드로 기록되어 있어서 미완료 평가에서 제외되어 있습니다.';
      }

      final tasks = (record['tasks'] as List?) ?? [];
      final incomplete = tasks
          .where((task) => (task as Map?)?['done'] != true)
          .map((task) {
            final map = task as Map;
            final text = (map['text'] ?? '').toString().trim();
            if (text.isEmpty) return '';
            return map['deferred'] == true ? '$text (이월됨)' : text;
          })
          .where((text) => text.isNotEmpty)
          .toList();

      if (incomplete.isEmpty) {
        return '$title, 어제($yesterdayStr) 미완료로 남은 항목은 없었습니다.';
      }

      return '$title, 어제($yesterdayStr) 미완료로 남은 항목은 ${incomplete.join(', ')}였습니다.';
    } catch (_) {
      return '$title, 어제 기록을 확인하는 중에 문제가 생겼습니다.';
    }
  }

  // ── 복귀/첫방문 인사 전송 ────────────────────────────────
  Future<void> _sendGreeting(String prompt) async {
    final currentId = widget.coachId;
    setState(() => _isLoading = true);
    try {
      final raw = await _callOpenAI(prompt, isGreeting: true);
      if (!mounted || widget.coachId != currentId) return;
      final parsed = _parseReply(raw);

      String greetingText = parsed.text;
      unawaited(_confirmPreemptiveIfMentioned(greetingText));

      setState(() {
        _messages.add(
          ChatMessage(text: greetingText, isUser: false, time: DateTime.now()),
        );
        _suppressDefaultChips = parsed.suppressDefaultChips;
        _dynamicChips = parsed.chips.isNotEmpty
            ? parsed.chips
            : (_suppressDefaultChips ? [] : _coach.chips);
        _coachSwitchTarget = parsed.coachSwitchTarget;
        _isLoading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (!mounted || widget.coachId != currentId) return;
      setState(() => _isLoading = false);
    }
  }

  bool _isScheduleRegistrationCommand(String input) {
    final cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라))$',
    );
    return suffixRegex.hasMatch(cleaned);
  }

  String _cleanScheduleRegistrationInput(String input) {
    return input.trim().replaceAll(RegExp(r'[\s.。!！~〜]+$'), '');
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

  bool _isHabitRegistrationCommand(String input) {
    final cleaned = _cleanScheduleRegistrationInput(input);
    if (!cleaned.contains('습관')) return false;
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라)|넣어\s*(?:줘요?|주세요))$',
    );
    return suffixRegex.hasMatch(cleaned);
  }

  _ParsedHabitRegistration _parseHabitRegistration(String input) {
    var cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라)|넣어\s*(?:줘요?|주세요))$',
    );
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'습관\s*(?:탭|텝)\s*에'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s*습관\s*(?:으로|에)?\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^습관\s*(?:으로|에)?\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^(?:나|나는|내가|저|저는)\s+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^(?:앞으로|이제)\s+'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:^|\s)(?:매일|매일마다|날마다)(?:\s|$)'),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(?:할\s*건데|할건데|할\s*건대|할\s*거야|할거야|할게|하려고|하려구|할래|할\s*래|하기)$'),
      '',
    );
    cleaned = _cleanRegistrationTitle(cleaned);
    return _ParsedHabitRegistration(title: cleaned);
  }

  String _habitRegistrationReply(String habitName) {
    return switch (widget.coachId) {
      'boyfriend' => '$habitName, 습관 탭에 임의로 적어뒀어. 자세한 사항은 한번 확인해줘.',
      'girlfriend' => '오빠, $habitName 습관 탭에 임의로 적어뒀어. 자세한 사항은 한번 확인해줘.',
      'bro' => '$habitName 습관 탭에 일단 적어뒀다. 자세한 사항은 한번 확인해라.',
      'halmae' => '$habitName, 습관 탭에 임의로 적어뒀다. 자세한 사항은 잘 확인해라.',
      'sec_male' => '$habitName 항목을 습관 탭에 임의로 기록해두었습니다. 자세한 사항은 확인해 주세요.',
      'sec_female' => '$habitName 항목을 습관 탭에 임의로 기록해두었습니다. 자세한 사항은 확인해 주세요.',
      _ => '$habitName 습관을 습관 탭에 임의로 적어뒀다냥. 자세한 사항은 확인해달라냥.',
    };
  }

  bool _isDeletionCommand(String input) {
    final cleaned = _cleanScheduleRegistrationInput(input);
    final normalized = cleaned.replaceAll(RegExp(r'\s+'), '');
    if (normalized.contains('휴식취소') ||
        normalized.contains('휴식해제') ||
        normalized.contains('쉬는거취소')) {
      return false;
    }
    if (RegExp(
      r'(?:그말|방금말|아까말|이전말|이전메시지|방금메시지|채팅|메시지)(?:을|를)?(?:삭제|취소|지워|없애)',
    ).hasMatch(normalized)) {
      return false;
    }
    return RegExp(
      r'\s*(?:삭제|취소|지워|없애)\s*(?:해\s*)?(?:줘요?|주세요|달라)?$',
    ).hasMatch(cleaned);
  }

  _ParsedDeleteCommand _parseDeletionCommand(String input) {
    var cleaned = _cleanScheduleRegistrationInput(input);
    cleaned = cleaned
        .replaceFirst(
          RegExp(r'\s*(?:삭제|취소|지워|없애)\s*(?:해\s*)?(?:줘요?|주세요|달라)?$'),
          '',
        )
        .trim();

    String kind = 'task_or_schedule';
    if (cleaned.contains('습관')) kind = 'habit';
    if (cleaned.contains('반복')) kind = 'recurring_schedule';

    DateTime? parsedDate;
    final now = DateTime.now();
    final dayAfterTomorrowRegex = RegExp(r'(?:내일\s*모레|내일모레|낼\s*모레|낼모레)');
    final weekRelRegex = RegExp(
      r'(이번\s*주|다음\s*주|담\s*주|다다음\s*주)\s+([월화수목금토일])(?:요일)?',
    );
    final weekRelMatch = weekRelRegex.firstMatch(cleaned);
    if (weekRelMatch != null) {
      final rel = weekRelMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
      final targetWeekday = _weekdayFromKorean(weekRelMatch.group(2)!);
      if (targetWeekday != -1) {
        var diff = targetWeekday - now.weekday;
        if (rel == '다음주' || rel == '담주') diff += 7;
        if (rel == '다다음주') diff += 14;
        parsedDate = now.add(Duration(days: diff));
        cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
      }
    } else if (cleaned.contains('그글피')) {
      parsedDate = now.add(const Duration(days: 4));
      cleaned = cleaned.replaceAll('그글피', '').trim();
    } else if (cleaned.contains('글피')) {
      parsedDate = now.add(const Duration(days: 3));
      cleaned = cleaned.replaceAll('글피', '').trim();
    } else if (dayAfterTomorrowRegex.hasMatch(cleaned)) {
      parsedDate = now.add(const Duration(days: 2));
      cleaned = cleaned.replaceFirst(dayAfterTomorrowRegex, '').trim();
    } else if (cleaned.contains('모레')) {
      parsedDate = now.add(const Duration(days: 2));
      cleaned = cleaned.replaceAll('모레', '').trim();
    } else if (cleaned.contains('내일')) {
      parsedDate = now.add(const Duration(days: 1));
      cleaned = cleaned.replaceAll('내일', '').trim();
    } else if (cleaned.contains('오늘')) {
      parsedDate = now;
      cleaned = cleaned.replaceAll('오늘', '').trim();
    }

    cleaned = cleaned.replaceAll(RegExp(r'\s*(?:반복\s*)?일정\s*$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s*습관\s*$'), '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = _cleanRegistrationTitle(cleaned);
    return _ParsedDeleteCommand(target: cleaned, kind: kind, date: parsedDate);
  }

  bool _isEditCommand(String input) {
    final cleaned = _cleanScheduleRegistrationInput(input);
    final normalized = cleaned.replaceAll(RegExp(r'\s+'), '');
    if (RegExp(
      r'(?:그말|방금말|아까말|이전말|이전메시지|방금메시지|채팅|메시지)(?:을|를)?(?:수정|변경|바꿔|고쳐)',
    ).hasMatch(normalized)) {
      return false;
    }
    final hasEditableTarget =
        normalized.contains('일정') ||
        normalized.contains('할일') ||
        normalized.contains('오늘할일') ||
        normalized.contains('오늘의할일') ||
        normalized.contains('태스크') ||
        normalized.contains('반복일정');
    if (!hasEditableTarget) return false;
    return RegExp(
      r'(?:수정|변경|바꿔|바꾸|고쳐)\s*(?:해\s*)?(?:줘요?|주세요|달라)?$',
    ).hasMatch(cleaned);
  }

  _ParsedEditCommand _parseEditCommand(String input) {
    var cleaned = _cleanScheduleRegistrationInput(input);
    cleaned = cleaned
        .replaceFirst(
          RegExp(r'\s*(?:수정|변경|바꿔|바꾸|고쳐)\s*(?:해\s*)?(?:줘요?|주세요|달라)?$'),
          '',
        )
        .trim();

    DateTime? parsedDate;
    final now = DateTime.now();
    final dayAfterTomorrowRegex = RegExp(r'(?:내일\s*모레|내일모레|낼\s*모레|낼모레)');
    final weekRelRegex = RegExp(
      r'(이번\s*주|다음\s*주|담\s*주|다다음\s*주)\s+([월화수목금토일])(?:요일)?',
    );
    final weekRelMatch = weekRelRegex.firstMatch(cleaned);
    if (weekRelMatch != null) {
      final rel = weekRelMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
      final targetWeekday = _weekdayFromKorean(weekRelMatch.group(2)!);
      if (targetWeekday != -1) {
        var diff = targetWeekday - now.weekday;
        if (rel == '다음주' || rel == '담주') diff += 7;
        if (rel == '다다음주') diff += 14;
        parsedDate = now.add(Duration(days: diff));
        cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
      }
    } else if (cleaned.contains('그글피')) {
      parsedDate = now.add(const Duration(days: 4));
      cleaned = cleaned.replaceAll('그글피', '').trim();
    } else if (cleaned.contains('글피')) {
      parsedDate = now.add(const Duration(days: 3));
      cleaned = cleaned.replaceAll('글피', '').trim();
    } else if (dayAfterTomorrowRegex.hasMatch(cleaned)) {
      parsedDate = now.add(const Duration(days: 2));
      cleaned = cleaned.replaceFirst(dayAfterTomorrowRegex, '').trim();
    } else if (cleaned.contains('모레')) {
      parsedDate = now.add(const Duration(days: 2));
      cleaned = cleaned.replaceAll('모레', '').trim();
    } else if (cleaned.contains('내일')) {
      parsedDate = now.add(const Duration(days: 1));
      cleaned = cleaned.replaceAll('내일', '').trim();
    } else if (cleaned.contains('오늘')) {
      parsedDate = now;
      cleaned = cleaned.replaceAll('오늘', '').trim();
    }

    String kind = cleaned.contains('반복')
        ? 'recurring_schedule'
        : 'task_or_schedule';
    cleaned = cleaned.replaceAll(RegExp(r'\s*반복\s*일정\s*'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s*(?:일정|할\s*일|태스크)\s*$'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+(?:[월화수목금토일]\s*요일|[월화수목금토일])\s*(?:로|으로|에)?\s*$'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    cleaned = _cleanRegistrationTitle(cleaned);
    return _ParsedEditCommand(target: cleaned, kind: kind, date: parsedDate);
  }

  String _emptyDeleteTargetReply() {
    return switch (widget.coachId) {
      'boyfriend' => '어떤 걸 삭제할지 이름까지 같이 말해줘.',
      'girlfriend' => '오빠, 어떤 걸 삭제할지 이름까지 같이 말해줘.',
      'bro' => '뭘 삭제할지 이름까지 같이 말해라.',
      'halmae' => '뭘 지울지 이름까지 말해줘야 한다, 우리 새끼.',
      'sec_male' => '삭제할 항목명을 함께 말씀해 주세요.',
      'sec_female' => '삭제할 항목명을 함께 말씀해 주세요.',
      _ => '어떤 걸 삭제할지 이름까지 같이 말해달라냥.',
    };
  }

  String _emptyEditTargetReply() {
    return switch (widget.coachId) {
      'boyfriend' => '어떤 일정을 수정할지 이름까지 같이 말해줘.',
      'girlfriend' => '오빠, 어떤 일정을 수정할지 이름까지 같이 말해줘.',
      'bro' => '뭘 수정할지 이름까지 같이 말해라.',
      'halmae' => '뭘 고칠지 이름까지 말해줘야 한다, 우리 새끼.',
      'sec_male' => '수정할 항목명을 함께 말씀해 주세요.',
      'sec_female' => '수정할 항목명을 함께 말씀해 주세요.',
      _ => '어떤 일정을 수정할지 이름까지 같이 말해달라냥.',
    };
  }

  bool _needsWeeklyRepeatWeekday(String input) {
    var cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라))$',
    );
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();
    if (!RegExp(r'매\s*주(?:마다)?').hasMatch(cleaned)) return false;
    if (RegExp(r'(평일|주말)').hasMatch(cleaned)) return false;
    if (RegExp(r'[월화수목금토일]\s*요일|[월화수목금토일]\s*(?:마다|에)').hasMatch(cleaned)) {
      return false;
    }
    return true;
  }

  String _weeklyRepeatWeekdayQuestion() {
    return switch (widget.coachId) {
      'boyfriend' => '매주 반복으로 등록하려면 무슨 요일로 할지 말해줘.',
      'girlfriend' => '오빠, 매주 반복으로 등록하려면 무슨 요일로 할지 말해줘.',
      'bro' => '매주 반복이면 요일이 필요하다. 무슨 요일로 할지 말해라.',
      'halmae' => '매주 반복이면 요일을 정해야 한다. 무슨 요일로 해줄까?',
      'sec_male' => '매주 반복 일정으로 등록하려면 요일이 필요합니다. 무슨 요일로 해드릴까요?',
      'sec_female' => '매주 반복 일정으로 등록하려면 요일이 필요해요. 무슨 요일로 해드릴까요?',
      _ => '매주 반복 일정이면 요일이 필요하다냥. 무슨 요일로 해줄까냥?',
    };
  }

  _ParsedScheduleRegistration _parseScheduleRegistration(String input) {
    String cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라))$',
    );
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();

    DateTime parsedDate = DateTime.now();
    bool hasDate = false;

    final repeatParse = _parseScheduleRepeatExpression(cleaned, parsedDate);
    cleaned = repeatParse.text;
    final repeatRule = repeatParse.rule;

    final lastWeekdayRegex = RegExp(r'이번\s*달\s+마지막\s+([월화수목금토일])(?:요일)?');
    final lastWeekdayMatch = lastWeekdayRegex.firstMatch(cleaned);
    if (lastWeekdayMatch != null) {
      final targetWeekday = _weekdayFromKorean(lastWeekdayMatch.group(1)!);
      if (targetWeekday != -1) {
        var date = DateTime(parsedDate.year, parsedDate.month + 1, 0);
        while (date.weekday != targetWeekday) {
          date = date.subtract(const Duration(days: 1));
        }
        parsedDate = date;
        hasDate = true;
        cleaned = cleaned.replaceFirst(lastWeekdayMatch.group(0)!, '').trim();
      }
    }

    if (!hasDate) {
      final weekRelRegex = RegExp(
        r'(이번\s*주|다음\s*주|담\s*주|다다음\s*주)\s+([월화수목금토일])(?:요일)?',
      );
      final weekRelMatch = weekRelRegex.firstMatch(cleaned);
      if (weekRelMatch != null) {
        final rel = weekRelMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
        final targetWeekday = _weekdayFromKorean(weekRelMatch.group(2)!);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          var diff = targetWeekday - now.weekday;
          if (rel == '다음주' || rel == '담주') diff += 7;
          if (rel == '다다음주') diff += 14;
          parsedDate = now.add(Duration(days: diff));
          hasDate = true;
          cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
        }
      }
    }

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

    if (!hasDate) {
      final bareWeekdayRegex = RegExp(r'([월화수목금토일])요일');
      final bareWeekdayMatch = bareWeekdayRegex.firstMatch(cleaned);
      if (bareWeekdayMatch != null) {
        final targetWeekday = _weekdayFromKorean(bareWeekdayMatch.group(1)!);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          var diff = targetWeekday - now.weekday;
          if (diff < 0) diff += 7;
          parsedDate = now.add(Duration(days: diff));
          cleaned = cleaned.replaceFirst(bareWeekdayMatch.group(0)!, '').trim();
        }
      }
    }

    if (repeatRule != null && !hasDate) {
      parsedDate = _firstDateForRepeatRule(parsedDate, repeatRule);
    }

    TimeOfDay? parsedTime;
    final timeRegex = RegExp(
      r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?(?:\s*(?:에|쯤|경|까지))?',
    );
    final timeMatch = timeRegex.firstMatch(cleaned);
    if (timeMatch != null) {
      final prefix = (timeMatch.group(1) ?? '').replaceAll(RegExp(r'\s'), '');
      final rawHour = int.tryParse(timeMatch.group(2)!) ?? 0;
      var minute = 0;
      if (timeMatch.group(3) != null) {
        minute = int.tryParse(timeMatch.group(3)!) ?? 0;
      } else if (timeMatch.group(0)!.contains('반')) {
        minute = 30;
      }

      if (rawHour >= 1 && rawHour <= 24) {
        var hour24 = rawHour;
        if (prefix == '오전' || prefix == '아침') {
          hour24 = rawHour == 12 ? 0 : rawHour;
        } else if (prefix == '오후' || prefix == '저녁' || prefix == '밤') {
          hour24 = rawHour == 12 ? 12 : rawHour + 12;
        } else if (rawHour < 12) {
          final now = DateTime.now();
          if (now.hour > rawHour ||
              (now.hour == rawHour && now.minute >= minute)) {
            hour24 = rawHour + 12;
          }
        }
        parsedTime = TimeOfDay(hour: hour24, minute: minute);
        cleaned = cleaned.replaceFirst(timeMatch.group(0)!, '').trim();
      }
    }

    cleaned = _cleanRegistrationTitle(cleaned);
    return _ParsedScheduleRegistration(
      title: cleaned.isEmpty ? '새 일정' : cleaned,
      date: parsedDate,
      time: parsedTime,
      repeatRule: repeatRule,
    );
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

  ({String text, Map<String, dynamic>? rule}) _parseScheduleRepeatExpression(
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

    final weekdayEveryRegex = RegExp(
      r'((?:[월화수목금토일](?:요일)?(?:\s*(?:,|과|와|랑|하고|및)?\s*)?)+)\s*마다',
    );
    final weeklyRegex = RegExp(
      r'매주\s*((?:[월화수목금토일](?:요일)?(?:\s*(?:,|과|와|랑|하고|및)?\s*)?)+)',
    );
    final weeklyMatch =
        weeklyRegex.firstMatch(cleaned) ??
        weekdayEveryRegex.firstMatch(cleaned);
    if (weeklyMatch != null) {
      final weekdays = <int>[];
      for (final match in RegExp(
        r'[월화수목금토일](?:요일)?',
      ).allMatches(weeklyMatch.group(1)!)) {
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

    final weekdayGroupRegex = RegExp(r'(평일|주말)(?:마다)?');
    final weekdayGroupMatch = weekdayGroupRegex.firstMatch(cleaned);
    if (weekdayGroupMatch != null) {
      final group = weekdayGroupMatch.group(1)!;
      rule
        ..['type'] = 'weekly'
        ..['weekdays'] = group == '평일' ? [1, 2, 3, 4, 5] : [6, 7];
      cleaned = cleaned.replaceFirst(weekdayGroupMatch.group(0)!, '').trim();
      return (text: cleaned, rule: rule);
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

  DateTime _firstDateForRepeatRule(
    DateTime baseDate,
    Map<String, dynamic> rule,
  ) {
    final base = DateTime(baseDate.year, baseDate.month, baseDate.day);
    final type = rule['type']?.toString() ?? 'daily';
    if (type == 'weekly') {
      final weekdays =
          (rule['weekdays'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          [];
      if (weekdays.isEmpty) return base;
      for (var offset = 0; offset < 7; offset++) {
        final candidate = base.add(Duration(days: offset));
        if (weekdays.contains(candidate.weekday)) return candidate;
      }
      return base;
    }
    if (type == 'monthly') {
      if (rule['monthlyMode'] == 'nthWeekday') {
        final nth = int.tryParse(rule['nth']?.toString() ?? '') ?? 1;
        final weekday =
            int.tryParse(rule['weekday']?.toString() ?? '') ?? base.weekday;
        final candidate = _nthWeekdayOfMonth(
          base.year,
          base.month,
          nth,
          weekday,
        );
        if (!candidate.isBefore(base)) return candidate;
        final nextMonth = DateTime(base.year, base.month + 1, 1);
        return _nthWeekdayOfMonth(
          nextMonth.year,
          nextMonth.month,
          nth,
          weekday,
        );
      }
      final day =
          int.tryParse(rule['dayOfMonth']?.toString() ?? '') ?? base.day;
      final candidate = DateTime(
        base.year,
        base.month,
        day.clamp(1, DateTime(base.year, base.month + 1, 0).day),
      );
      if (!candidate.isBefore(base)) return candidate;
      final nextMonth = DateTime(base.year, base.month + 1, 1);
      return DateTime(
        nextMonth.year,
        nextMonth.month,
        day.clamp(1, DateTime(nextMonth.year, nextMonth.month + 1, 0).day),
      );
    }
    return base;
  }

  DateTime _nthWeekdayOfMonth(int year, int month, int nth, int weekday) {
    final matches = <DateTime>[];
    final lastDay = DateTime(year, month + 1, 0).day;
    for (var day = 1; day <= lastDay; day++) {
      final date = DateTime(year, month, day);
      if (date.weekday == weekday) matches.add(date);
    }
    if (matches.isEmpty) return DateTime(year, month, 1);
    final index = nth.clamp(1, matches.length) - 1;
    return matches[index];
  }

  List<DateTime> _datesForScheduleRepeat(
    DateTime startDate,
    Map<String, dynamic> rule,
  ) {
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final endType = rule['endType']?.toString() ?? 'never';
    final endDate = DateTime.tryParse(rule['endDate']?.toString() ?? '');
    final hardEnd = endType == 'date' && endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day)
        : start.add(const Duration(days: 365));
    final repeatCount = int.tryParse(rule['count']?.toString() ?? '');
    final maxCount = endType == 'count'
        ? (repeatCount == null || repeatCount < 1 ? 1 : repeatCount)
        : 370;
    final dates = <DateTime>[];
    final type = rule['type']?.toString() ?? 'daily';

    bool canAdd(DateTime date) =>
        !date.isBefore(start) &&
        !date.isAfter(hardEnd) &&
        dates.length < maxCount;

    if (type == 'daily') {
      var date = start;
      while (canAdd(date)) {
        dates.add(date);
        date = date.add(const Duration(days: 1));
      }
      return dates;
    }

    if (type == 'weekly') {
      final weekdays =
          (rule['weekdays'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toSet() ??
          {start.weekday};
      var date = start;
      while (canAdd(date)) {
        if (weekdays.contains(date.weekday)) dates.add(date);
        date = date.add(const Duration(days: 1));
      }
      return dates;
    }

    if (type == 'monthly') {
      var monthCursor = DateTime(start.year, start.month, 1);
      while (dates.length < maxCount && !monthCursor.isAfter(hardEnd)) {
        DateTime candidate;
        if (rule['monthlyMode'] == 'nthWeekday') {
          final nth = int.tryParse(rule['nth']?.toString() ?? '') ?? 1;
          final weekday =
              int.tryParse(rule['weekday']?.toString() ?? '') ?? start.weekday;
          candidate = _nthWeekdayOfMonth(
            monthCursor.year,
            monthCursor.month,
            nth,
            weekday,
          );
        } else {
          final day =
              int.tryParse(rule['dayOfMonth']?.toString() ?? '') ?? start.day;
          candidate = DateTime(
            monthCursor.year,
            monthCursor.month,
            day.clamp(
              1,
              DateTime(monthCursor.year, monthCursor.month + 1, 0).day,
            ),
          );
        }
        if (canAdd(candidate)) dates.add(candidate);
        monthCursor = DateTime(monthCursor.year, monthCursor.month + 1, 1);
      }
      return dates;
    }

    return [start];
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

  String? _calendarDateQuestionReply(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '');
    final asksDate = RegExp(r'(몇일|며칠|몇월몇일|날짜|언제)').hasMatch(normalized);
    if (!asksDate) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final relativeDayPatterns = <({String label, int offset, RegExp pattern})>[
      (label: '그글피', offset: 4, pattern: RegExp(r'그글피')),
      (label: '글피', offset: 3, pattern: RegExp(r'글피')),
      (label: '모레', offset: 2, pattern: RegExp(r'(?:내일모레|낼모레|모레)')),
      (label: '내일', offset: 1, pattern: RegExp(r'내일')),
      (label: '오늘', offset: 0, pattern: RegExp(r'오늘')),
    ];
    for (final relative in relativeDayPatterns) {
      if (relative.pattern.hasMatch(normalized)) {
        final target = today.add(Duration(days: relative.offset));
        return '${relative.label}는 ${_fullKoreanDate(target)}입니다.';
      }
    }

    final weekMatch = RegExp(
      r'(이번주|다음주|담주|다다음주)([월화수목금토일])(?:요일)?',
    ).firstMatch(normalized);
    if (weekMatch != null) {
      final rel = weekMatch.group(1)!;
      final weekday = _weekdayFromKorean(weekMatch.group(2)!);
      if (weekday == -1) return null;
      final thisMonday = today.subtract(Duration(days: today.weekday - 1));
      final weekOffset = switch (rel) {
        '다음주' || '담주' => 7,
        '다다음주' => 14,
        _ => 0,
      };
      final target = thisMonday.add(Duration(days: weekOffset + weekday - 1));
      return '${_relativeDateQuestionLabel(rel)} ${_weekdayLabel(weekday)}요일은 ${_fullKoreanDate(target)}입니다.';
    }

    final monthMatch = RegExp(
      r'(이번달|다음달|다다음달)([월화수목금토일])(?:요일)?',
    ).firstMatch(normalized);
    if (monthMatch != null) {
      final rel = monthMatch.group(1)!;
      final weekday = _weekdayFromKorean(monthMatch.group(2)!);
      if (weekday == -1) return null;
      final monthOffset = switch (rel) {
        '다음달' => 1,
        '다다음달' => 2,
        _ => 0,
      };
      final monthStart = DateTime(today.year, today.month + monthOffset, 1);
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 0);
      final dates = <DateTime>[];
      for (var day = 1; day <= monthEnd.day; day++) {
        final date = DateTime(monthStart.year, monthStart.month, day);
        if (date.weekday == weekday) dates.add(date);
      }
      if (dates.isEmpty) return null;
      final joined = dates.map((date) => '${date.day}일').join(', ');
      return '${_relativeDateQuestionLabel(rel)} ${_weekdayLabel(weekday)}요일은 $joined입니다.';
    }

    return null;
  }

  String _relativeDateQuestionLabel(String rel) {
    return switch (rel) {
      '이번주' => '이번 주',
      '다음주' || '담주' => '다음 주',
      '다다음주' => '다다음 주',
      '이번달' => '이번 달',
      '다음달' => '다음 달',
      '다다음달' => '다다음 달',
      _ => rel,
    };
  }

  String _fullKoreanDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  String _storedTime(TimeOfDay time) => '${time.hour}:${time.minute}';

  String _formatTimeOfDay(TimeOfDay time) {
    final h = time.hour;
    final m = time.minute;
    final prefix = h < 12 ? '오전' : '오후';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$prefix $hour12:${m.toString().padLeft(2, '0')}';
  }

  String _scheduleDateLabel(DateTime date) {
    final today = DateTime.now();
    final base = DateTime(today.year, today.month, today.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(base).inDays;
    final ymd = _dateKey(date);
    if (diff == 0) return '오늘 ($ymd)';
    if (diff == 1) return '내일 ($ymd)';
    if (diff == 2) return '모레 ($ymd)';
    return ymd;
  }

  Future<void> _saveRegisteredSchedule(
    String title,
    DateTime date,
    TimeOfDay? time,
    bool reminderEnabled,
    Map<String, dynamic>? repeatRule,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchedules = prefs.getString('nyang_schedules');
    final Map<String, dynamic> schedules = rawSchedules == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(rawSchedules));
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final createdAt = DateTime.now().toIso8601String();
    final repeatDates = repeatRule == null
        ? [date]
        : _datesForScheduleRepeat(date, repeatRule);
    final recurrenceGroupId = repeatRule == null ? null : 'repeat_$nowMs';

    for (var i = 0; i < repeatDates.length; i++) {
      final targetDate = repeatDates[i];
      final dateStr = _dateKey(targetDate);
      final dayList = List<dynamic>.from(schedules[dateStr] ?? []);
      final entry = {
        'id': repeatRule == null ? nowMs.toString() : '${nowMs}_$i',
        'text': title,
        'done': false,
        'createdAt': createdAt,
        'deferredCount': 0,
        'isReminderEnabled': reminderEnabled,
        'isRecurring': repeatRule != null,
        if (recurrenceGroupId != null) 'recurrenceGroupId': recurrenceGroupId,
        if (repeatRule != null)
          'recurrenceRule': {...repeatRule, 'startDate': _dateKey(date)},
        if (time != null) 'timeStart': _storedTime(time),
        if (time != null) 'time': _formatTimeOfDay(time),
      };
      dayList.add(entry);
      schedules[dateStr] = dayList;
    }
    await prefs.setString('nyang_schedules', jsonEncode(schedules));

    if (repeatDates.any(
      (targetDate) => _dateKey(targetDate) == _dateKey(DateTime.now()),
    )) {
      await _updateTodayRecord(prefs);
      await _refreshAttendanceStreak(prefs);
    }

    TasksSyncService.scheduleSyncToCloud();
  }

  Future<void> _showScheduleRegistrationDialog(String speechText) async {
    final parsed = _parseScheduleRegistration(speechText);
    final titleCtrl = TextEditingController(text: parsed.title);
    DateTime confirmedDate = parsed.date;
    TimeOfDay? confirmedTime = parsed.time;
    Map<String, dynamic>? confirmedRepeatRule = parsed.repeatRule;
    bool reminderEnabled = false;

    final prefs = await SharedPreferences.getInstance();
    reminderEnabled =
        (prefs.getBool('nyang_core_reminder_enabled') ?? false) &&
        confirmedTime != null;

    if (!mounted) return;
    await showDialog(
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
                                color: const Color(0xFFDDD6FE),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.repeat_rounded,
                                  size: 14,
                                  color: Color(0xFF8B7CFF),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _repeatRuleLabel(confirmedRepeatRule),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF8B7CFF),
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
                                    color: Color(0xFFB8B5C8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
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
                                  _scheduleDateLabel(confirmedDate),
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
                        GestureDetector(
                          onTap: () async {
                            final t = await showTimePicker(
                              context: context,
                              initialTime: confirmedTime ?? TimeOfDay.now(),
                            );
                            if (t != null) {
                              setDialogState(() {
                                confirmedTime = t;
                                reminderEnabled =
                                    prefs.getBool(
                                      'nyang_core_reminder_enabled',
                                    ) ??
                                    false;
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
                                      ? _formatTimeOfDay(confirmedTime!)
                                      : '시간 설정 안 함',
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
                      ],
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () async {
                        if (confirmedTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('알람을 켜려면 시간을 먼저 선택해주세요.'),
                            ),
                          );
                          return;
                        }
                        if (!reminderEnabled) {
                          final enabled =
                              prefs.getBool('nyang_core_reminder_enabled') ??
                              false;
                          if (!enabled) {
                            final savedEnabled =
                                await showCoreReminderSettingsSheet(context);
                            final refreshedEnabled =
                                prefs.getBool('nyang_core_reminder_enabled') ??
                                false;
                            if (!savedEnabled || !refreshedEnabled) return;
                          }
                        }
                        setDialogState(
                          () => reminderEnabled = !reminderEnabled,
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
                              reminderEnabled ? '알람 ON' : '알람 OFF',
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
                            onPressed: () async {
                              final finalTitle = titleCtrl.text.trim();
                              if (finalTitle.isEmpty) return;
                              final navigator = Navigator.of(ctx);
                              final messenger = ScaffoldMessenger.of(
                                this.context,
                              );
                              await _saveRegisteredSchedule(
                                finalTitle,
                                confirmedDate,
                                confirmedTime,
                                reminderEnabled && confirmedTime != null,
                                confirmedRepeatRule,
                              );
                              if (!mounted) return;
                              navigator.pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('"$finalTitle" 일정을 추가했어요 ✓'),
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
    );
    titleCtrl.dispose();
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any((keyword) => text.contains(keyword));
  }

  String _workoutNormalized(String input) {
    return input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  }

  Future<_BroWorkoutLink> _pickBroWorkoutLink(
    List<_BroWorkoutLink> links,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString('bro_last_workout_link_id');
    final candidates = links.length <= 1
        ? links
        : links.where((link) => link.id != lastId).toList();
    final pool = candidates.isEmpty ? links : candidates;
    final picked = pool[Random().nextInt(pool.length)];
    await prefs.setString('bro_last_workout_link_id', picked.id);
    return picked;
  }

  _BroWorkoutLink _broStarterLink(String id) {
    return _broWorkoutStarterLinks.firstWhere((link) => link.id == id);
  }

  bool _isBroVideoRequest(String normalized) {
    return _containsAny(normalized, [
      '응',
      'ㅇㅇ',
      '줘',
      '알려줘',
      '추천',
      '추천해줘',
      '영상',
      '링크',
      '보내',
      '보내줘',
    ]);
  }

  bool _isBroWorkoutRecommendationRequest(String normalized) {
    return _containsAny(normalized, [
      '추천',
      '추천해줘',
      '뭐해야',
      '뭘해야',
      '뭐부터',
      '어디서부터',
      '알려줘',
      '골라줘',
      '루틴',
      '영상',
      '링크',
      '따라할',
      '시작할까',
      '하면돼',
      '하면되',
      '해볼까',
    ]);
  }

  String? _broTargetedWorkoutAreas(String normalized) {
    final areas = <String>[];
    if (_containsAny(normalized, ['복부', '복근', '뱃살', '배살', '코어'])) {
      areas.add('복부/코어');
    }
    if (_containsAny(normalized, ['하체', '다리', '엉덩이', '허벅지', '종아리'])) {
      areas.add('하체');
    }
    if (_containsAny(normalized, ['상체', '팔', '이두', '삼두'])) {
      areas.add('상체/팔');
    }
    if (_containsAny(normalized, ['어깨', '승모'])) {
      areas.add('어깨');
    }
    if (_containsAny(normalized, ['등', '등운동', '광배'])) {
      areas.add('등');
    }
    if (_containsAny(normalized, ['가슴', '흉근', '푸쉬업', '팔굽혀'])) {
      areas.add('가슴');
    }
    if (_containsAny(normalized, ['전신', '온몸', '몸전체', '전체'])) {
      areas.add('전신');
    }
    if (_containsAny(normalized, ['다이어트', '살빼', '체지방', '유산소'])) {
      areas.add('다이어트/유산소');
    }
    if (_containsAny(normalized, ['스트레칭', '유연성', '풀어', '뻐근'])) {
      areas.add('스트레칭');
    }
    if (areas.isEmpty) return null;
    return areas.join(', ');
  }

  String? _buildBroTargetedWorkoutApiInput(String input) {
    final normalized = _workoutNormalized(input);
    final hasWorkoutIntent = _containsAny(normalized, [
      '운동',
      '루틴',
      '추천',
      '짜줘',
      '해줘',
      '뭐하지',
      '뭐해야',
      '뭘해야',
      '할거',
      '할것',
      '스트레칭',
      '다이어트',
    ]);
    if (!hasWorkoutIntent) return null;

    final areas = _broTargetedWorkoutAreas(normalized);
    if (areas == null) return null;

    return '사용자가 부위별 또는 목적별 운동 추천을 요청했다. '
        '사용자 원문: "$input". '
        '중심 부위/목적: $areas. '
        '사용자의 장소, 난이도, 시간, 소음 제약이 원문에 있으면 반드시 반영해줘. '
        '조건이 부족하면 초보자도 바로 할 수 있는 짧은 루틴으로 추천하고, '
        '세트/횟수/쉬는 시간을 간단히 포함해줘. '
        '통증을 유발할 수 있는 동작은 피하고 대체 동작을 짧게 제시해줘. '
        '말투는 갓생 형 코치답게 짧고 힘 있게 해줘.';
  }

  Future<_BroWorkoutLink> _selectBroWarmupLink(String normalized) {
    if (_containsAny(normalized, ['하체', '다리', '스쿼트', '런지'])) {
      return _pickBroWorkoutLink([
        _broWorkoutWarmupLinks.firstWhere(
          (link) => link.id == 'warmup_lower_body',
        ),
      ]);
    }
    if (_containsAny(normalized, ['24분', '길게', '제대로', '회복'])) {
      return _pickBroWorkoutLink([
        _broWorkoutWarmupLinks.firstWhere(
          (link) => link.id == 'warmup_full_body_24',
        ),
      ]);
    }
    if (_containsAny(normalized, ['전신', '몸전체', '온몸', '전체'])) {
      return _pickBroWorkoutLink([
        _broWorkoutWarmupLinks.firstWhere(
          (link) => link.id == 'warmup_full_body',
        ),
      ]);
    }
    return _pickBroWorkoutLink([
      _broWorkoutWarmupLinks.firstWhere((link) => link.id == 'warmup_basic'),
      _broWorkoutWarmupLinks.firstWhere((link) => link.id == 'warmup_simple'),
    ]);
  }

  Future<_BroWorkoutLink> _selectBroWorkoutLink(String normalized) {
    if (_containsAny(normalized, ['층간소음', '조용', '점프없이', '노점프'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere(
          (link) => link.id == 'hiit_no_noise_24',
        ),
      ]);
    }
    if (_containsAny(normalized, ['복근', 'abs'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_abs_10'),
      ]);
    }
    if (_containsAny(normalized, ['뱃살', '배살', '복부'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_belly_15'),
      ]);
    }
    if (_containsAny(normalized, ['전신', '몸전체', '온몸'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere(
          (link) => link.id == 'hiit_full_body_23',
        ),
      ]);
    }
    if (_containsAny(normalized, ['고강도', '타바타', '빡세', '빡센'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_15'),
      ]);
    }
    if (_containsAny(normalized, ['다이어트', '살빼', '살빼기', '감량'])) {
      return _pickBroWorkoutLink([
        _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_diet_10'),
        _broWorkoutHiitLinks.firstWhere(
          (link) => link.id == 'hiit_full_body_23',
        ),
      ]);
    }
    return _pickBroWorkoutLink([
      _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_diet_10'),
      _broWorkoutHiitLinks.firstWhere((link) => link.id == 'hiit_15'),
    ]);
  }

  Future<_BroWorkoutLink> _selectBroGymLink(String normalized) {
    if (_containsAny(normalized, ['여자', '여성'])) {
      return _pickBroWorkoutLink([
        _broWorkoutGymLinks.firstWhere(
          (link) => link.id == 'gym_female_han_hye_jin',
        ),
      ]);
    }
    if (_containsAny(normalized, ['남자', '남성'])) {
      return _pickBroWorkoutLink([
        _broWorkoutGymLinks.firstWhere(
          (link) => link.id == 'gym_male_beginner',
        ),
      ]);
    }
    return _pickBroWorkoutLink([
      _broWorkoutGymLinks.firstWhere(
        (link) => link.id == 'gym_common_beginner_5',
      ),
    ]);
  }

  Future<String?> _tryBuildBroWorkoutReply(String input) async {
    if (_coach.id != 'bro') return null;
    final normalized = _workoutNormalized(input);
    final prefs = await SharedPreferences.getInstance();
    final pendingVideo = prefs.getString('bro_pending_workout_video');
    final pendingContext = prefs.getString('bro_pending_workout_context');
    final bridgeLink = _broStarterLink('starter_bridge');
    final hipHingeLink = _broStarterLink('starter_hip_hinge');

    if (pendingVideo == 'bridge' && _isBroVideoRequest(normalized)) {
      await prefs.remove('bro_pending_workout_video');
      return '좋아. 이거 보면 바로 감 잡힐 거다.\n${bridgeLink.url}\n\n형도 전문가 아니다. 그냥 운동 좋아해서 이것저것 해본 사람인데, 이건 몸 깨우기 괜찮더라.';
    }

    if (_containsAny(normalized, ['브릿지가뭐야', '브릿지뭐야', '브릿지어떻게'])) {
      await prefs.setString('bro_pending_workout_video', 'bridge');
      return '브릿지는 누워서 무릎 세우고 엉덩이 들어올리는 운동.\n엉덩이 근육 깨우는 데 좋다.\n아 나 헬스 전문가 아니고 그냥 운동 좋아하는 사람이다. 😂\n필요하면 영상도 줄까?';
    }

    if (_containsAny(normalized, ['브릿지영상', '브릿지링크', '브릿지추천'])) {
      return '브릿지는 이거 보면 된다.\n${bridgeLink.url}\n\n짧게 감만 잡고, 무리하지 말고 천천히 해.';
    }

    if (pendingContext == 'reluctant_reason') {
      await prefs.remove('bro_pending_workout_context');
      if (_containsAny(normalized, ['몸', '피곤', '힘들', '아파', '컨디션', '지침'])) {
        return '오케이. 몸이 힘든 거면 오늘은 운동으로 이기려 하지 마라.\n그냥 몸 깨우는 정도만 가자.\n지금 제일 부담 없는 게 뭐냐. 5분 걷기, 스트레칭, 아니면 아예 쉬면서 내일 다시 잡기.';
      }
      if (_containsAny(normalized, ['귀찮', '의욕', '누워', '침대', '미루'])) {
        return '오케이. 귀찮은 거면 의지 싸움으로 끌고 가지 마라.\n딱 하나만 정하자.\n집이야, 헬스장이야, 밖이야? 장소 말하면 형이 제일 덜 귀찮은 첫 행동만 잘라줄게.';
      }
      if (_containsAny(normalized, ['무섭', '오래쉬', '오랜만', '몇달', '몇년', '모르겠'])) {
        return '그럼 바로 빡센 거 추천하면 안 되겠다.\n지금은 운동을 잘하는 게 아니라 다시 시작하는 게 목표다.\n뭐 해야 할지 모르겠으면 추천해달라고 해. 형이 가볍게 시작할 걸로 골라줄게.';
      }
      return '오케이. 그럼 오늘은 이유부터 잡자.\n몸이 힘든 쪽이야, 귀찮은 쪽이야, 아니면 뭘 해야 할지 몰라서 막힌 거야?';
    }

    final isWorkoutRelated = _containsAny(normalized, [
      '운동',
      '홈트',
      '헬스',
      '헬스장',
      '웨이트',
      '스트레칭',
      '몸풀',
      '폼롤러',
      '밴드',
      '러닝',
      '조깅',
      '타바타',
      '복근',
      '뱃살',
      '다이어트',
      '하체',
      '상체',
      '전신',
      '층간소음',
      '풀고왔다',
      '풀었어',
      '워밍업',
      '오래쉬',
      '오랜만',
      '몇년만',
      '몇달만',
      '몇년',
      '몇달',
      '쉬었다',
      '쉬었',
      '운동안한',
      '초보',
      '입문',
      '브릿지',
      '힙힌지',
      '계단',
      'workout',
      'exercise',
    ]);
    if (!isWorkoutRelated) return null;

    final warmedUp = _containsAny(normalized, [
      '풀고왔다',
      '풀었어',
      '스트레칭했',
      '워밍업끝',
      '몸풀었',
      '운동중',
    ]);
    final gym = _containsAny(normalized, ['헬스장', '웨이트', '기구', '헬린이', '루틴']);
    final reluctant = _containsAny(normalized, [
      '하기싫',
      '하기싫어',
      '귀찮',
      '못하겠',
      '싫다',
      '싫어',
      '미루고싶',
      '안하고싶',
    ]);
    final longBreak = _containsAny(normalized, [
      '오래쉬',
      '오랜만',
      '몇년만',
      '몇달만',
      '운동안한',
      '안한지오래',
      '초보',
      '입문',
      '처음',
    ]);
    final lowerBody = _containsAny(normalized, [
      '하체',
      '다리',
      '엉덩이',
      '고관절',
      '무릎',
      '스쿼트',
      '런지',
    ]);
    final genericWorkout = _containsAny(normalized, [
      '운동',
      '홈트',
      '헬스',
      '헬스장',
      '웨이트',
      '다이어트',
      '몸만들',
    ]);
    final explicitWorkoutRequest = _isBroWorkoutRecommendationRequest(
      normalized,
    );

    if (!warmedUp &&
        !reluctant &&
        !longBreak &&
        genericWorkout &&
        !explicitWorkoutRequest &&
        Random().nextDouble() < 0.25) {
      return _pickLine([
        '아 근데 너 운동 요새 많이 하냐?\n오래 쉬었으면 바로 추천부터 안 하고, 먼저 상태부터 보고 가자.',
        '잠깐. 너 혹시 운동 오래 쉬었어?\n몸이 무거운 건지, 뭘 해야 할지 모르는 건지부터 보자.',
      ]);
    }

    if (reluctant && !warmedUp) {
      await prefs.setString('bro_pending_workout_context', 'reluctant_reason');
      return _pickLine([
        '야 하기 싫은 거 정상이다.\n오늘은 왜 하기 싫은데?\n몸이 힘든 거냐, 귀찮은 거냐?',
        '오케이. 바로 운동 추천 안 한다.\n먼저 이유부터 보자. 몸이 무거운 거야, 아니면 그냥 시작이 귀찮은 거야?',
      ]);
    }

    if (longBreak && !warmedUp && !explicitWorkoutRequest) {
      return _pickLine([
        '몇 달 쉬었으면 무서울 수 있다. 정상이다.\n바로 운동 던지기 전에 하나만 보자.\n뭐가 제일 걸려? 체력, 부상 걱정, 아니면 뭘 해야 할지 모르는 거?',
        '오케이. 오래 쉬었으면 바로 빡세게 가는 건 별로다.\n지금은 네 상태부터 보는 게 먼저야.\n운동 추천이 필요한 거야, 아니면 그냥 다시 시작할 용기가 필요한 거야?',
      ]);
    }

    if (longBreak && !warmedUp && explicitWorkoutRequest) {
      if (lowerBody && Random().nextBool()) {
        await prefs.setString('bro_pending_workout_video', 'bridge');
        return '오케이. 오래 쉬었으면 바로 스쿼트부터 박지 마라.\n너 하체도 좀 깨워야 할 것 같은데 브릿지 해봤냐?\n누워서 하는 거라 진입 장벽 낮다.\n필요하면 영상도 줄까?';
      }
      final starter = Random().nextInt(4);
      if (starter == 0) {
        return '오케이.\n그럼 갑자기 빡세게 하는 것보다 몸부터 깨우는 게 좋겠다.\n형이 운동하면서 자주 보는 동작인데 한번 해볼래?\n${hipHingeLink.url}\n\n형도 전문가 아니다. 그냥 운동 좋아해서 이것저것 해본 사람인데, 오래 쉬었을 땐 이런 식으로 몸 깨우는 게 낫더라.';
      }
      if (starter == 1) {
        final link = await _selectBroWarmupLink(normalized);
        return '오케이. 오래 쉬었으면 오늘은 이기는 기준을 낮추자.\n갑자기 빡세게 말고, 몸부터 깨워.\n스트레칭 영상 필요하면 말해. 형이 추천해 줄 수 있으니까.\n참고할 거면 이거 봐.\n${link.url}\n\n풀고 오면 그때 더 할지 보자.';
      }
      if (starter == 2) {
        return '오케이. 오래 쉬었으면 오늘은 운동복 입고 10분 산책만 해도 성공이다.\n몸이 깨어나야 다음 것도 된다.\n형도 전문가 아니다. 그냥 운동 좋아해서 이것저것 해본 사람인데, 다시 시작할 땐 이렇게 문턱 낮추는 게 제일 세다.';
      }
      return '오케이. 오래 쉬었으면 오늘 바로 고강도 가지 마라.\n집이면 제자리 걷기 5분, 밖이면 산책 10분, 건물 안이면 계단 한두 층만 가자.\n운동을 가르치려는 게 아니라, 오늘 다시 시작하게 만드는 게 먼저다.';
    }

    if (gym && warmedUp) {
      final link = await _selectBroGymLink(normalized);
      return _pickLine([
        '좋아. 헬스장 갔으면 방황하지 마라. 루틴 없으면 시간 다 날린다.\n이거 보고 오늘 할 것만 딱 정해.\n${link.url}\n\n복잡하게 가지 말고, 몇 개만 제대로 해도 충분하다.',
        '좋다. 몸 풀었으면 이제 루틴 잡고 가자.\n이거 하나 보고 오늘 할 거만 정해.\n${link.url}\n\n기구 앞에서 멍 때리지 말고 바로 시작해.',
      ]);
    }

    if (warmedUp) {
      final link = await _selectBroWorkoutLink(normalized);
      if (_containsAny(normalized, ['층간소음', '조용', '점프없이', '노점프'])) {
        return '집이면 층간소음 신경 써야지. 괜히 점프하다가 운동보다 민원 먼저 온다.\n이걸로 가자. 조용한데 빡세다.\n${link.url}\n\n하고 나서 더 할 만하면 그대로 이어가.';
      }
      if (_containsAny(normalized, ['복근', '뱃살', '배살', '복부'])) {
        return '복근이면 짧고 굵게 가자. 대신 허리 꺾지 말고 배에 힘 제대로 줘.\n이거 얼마 안 걸린다.\n${link.url}\n\n더 할 만하면 그대로 이어가. 흐름 탔을 때 가는 거다.';
      }
      return _pickLine([
        '좋아. 이제 몸 깨웠지?\n그럼 이거 하나만 가자. 짧게 치고 흐름 만들기 좋다.\n${link.url}\n\n하고 나서 더 할 만하면 그대로 이어가. 오늘은 시작한 네가 이긴 거다.',
        '좋다. 이제 본운동 들어가자.\n이거 얼마 안 걸린다. 일단 하나만 따라 해.\n${link.url}\n\n끝나고 몸 괜찮으면 더 가도 된다. 흐름 탔을 때 밀어붙이는 거다.',
      ]);
    }

    if (!explicitWorkoutRequest) {
      return null;
    }

    final link = await _selectBroWarmupLink(normalized);

    if (gym) {
      return '헬스장 가는 건 좋은데, 바로 무게부터 들지 마라. 관절 놀란다.\n일단 가볍게 몸부터 풀어. 폼롤러나 스트레칭 밴드 있으면 더 좋고.\n스트레칭 영상 필요하면 말해. 형이 추천해 줄 수 있으니까.\n참고할 거면 이거 봐.\n${link.url}\n\n풀고 오면 그때 오늘 루틴 딱 잡아줄게.';
    }
    if (_containsAny(normalized, ['하체', '다리', '스쿼트', '런지'])) {
      return '하체 갈 거면 더더욱 바로 들이박지 마라.\n무릎이랑 고관절 먼저 깨워야 된다.\n스트레칭 영상 필요하면 말해. 형이 추천해 줄 수 있으니까.\n참고할 거면 이거 봐. 얼마 안 걸린다.\n${link.url}\n\n풀고 오면 그때 더 할 거 이어가자.';
    }
    return _pickLine([
      '야 잠깐. 바로 고강도 박지 마라. 관절 놀란다.\n폼롤러 있으면 하체랑 등부터 굴리고, 밴드 있으면 어깨랑 고관절부터 열어.\n스트레칭 영상 필요하면 말해. 형이 추천해 줄 수 있으니까.\n참고할 거면 이거 봐. 얼마 안 걸린다.\n${link.url}\n\n풀고 오면 그때 더 할 거 이어가자. 흐름 탔을 때 가는 거다.',
      '좋다. 근데 바로 빡세게 가지 마라. 몸부터 깨워야 오래 간다.\n스트레칭 영상 필요하면 말해. 형이 추천해 줄 수 있으니까.\n참고할 거면 이걸로 관절이랑 근육부터 깨워.\n${link.url}\n\n풀고 오면 그때 본운동 가자. 시작만 해도 이긴 거다.',
    ]);
  }

  int? _directTimerRequestMinutes(String text) {
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final hasTimerWord =
        normalized.contains('타이머') ||
        normalized.contains('timer') ||
        normalized.contains('포커스') ||
        normalized.contains('집중모드');
    if (!hasTimerWord) return null;

    final hasRequestIntent = [
      '띄워',
      '켜',
      '시작',
      '설정',
      '맞춰',
      '틀어',
      '열어',
      '줘',
      '해줘',
      '돌려',
      '실행',
    ].any(normalized.contains);
    if (!hasRequestIntent) return null;

    final minuteMatch = RegExp(
      r'(\d{1,3})\s*(?:분|min|mins|minute|minutes)',
      caseSensitive: false,
    ).firstMatch(text);
    if (minuteMatch != null) {
      return (int.tryParse(minuteMatch.group(1)!) ?? 15).clamp(1, 180);
    }

    final hourMatch = RegExp(r'(\d{1,2})\s*시간').firstMatch(text);
    if (hourMatch != null) {
      return ((int.tryParse(hourMatch.group(1)!) ?? 1) * 60).clamp(1, 180);
    }

    return 15;
  }

  String _directTimerStartMessage(int minutes) {
    if (_coach.id == 'sec_male') {
      return '$minutes분 타이머 바로 띄워드리겠습니다. 지금은 시작만 하시면 됩니다.';
    }
    if (_coach.id == 'sec_female') {
      return '$minutes분 타이머 바로 띄워드릴게요. 지금은 가볍게 시작해봐요.';
    }
    return '$minutes분 타이머 바로 켜줄게. 일단 시작해보자.';
  }

  Future<bool> _ensureMasterCoachAccess() async {
    if (!_coach.isMaster) return true;

    final data = await UserDataService.load();
    if (data.canAccessCoach(widget.coachId)) return true;

    await UserDataService.setSelectedCoach('cat');
    if (!mounted) return false;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CoachSelectionScreen()),
      (route) => false,
    );
    return false;
  }

  DateTime? _parseMilestoneDate(dynamic rawDate) {
    final text = rawDate?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  String _quotedMilestoneNames(List<String> names) {
    final visible = names.take(2).map((name) => '‘$name’').join(', ');
    final hiddenCount = names.length - 2;
    if (hiddenCount > 0) return '$visible 외 $hiddenCount개';
    return visible;
  }

  String _completedMilestonePraise(List<String> names) {
    if (names.length == 1) {
      return '최근 일정이었던 ‘${names.first}’을 잘 마무리하셨네요. 중요한 단계를 잘 넘기셨어요.';
    }
    return '최근 일정이었던 ${_quotedMilestoneNames(names)}를 잘 마무리하셨네요. 중요한 단계들을 잘 넘기셨어요.';
  }

  Future<_MilestoneCheckResult> _buildMilestoneCheckResult() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_visions');
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final recentStart = today.subtract(const Duration(days: 3));
    final recentEnd = today.add(const Duration(days: 3));
    final upcomingEnd = today.add(const Duration(days: 7));

    final completedRecent = <({String name, DateTime date})>[];
    final overdue = <({String name, DateTime date, String visionId})>[];
    final upcoming = <({String name, DateTime date, String visionId})>[];
    final visionIds = <String>[];
    var hasVision = false;
    var hasDatedMilestone = false;

    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final vision in decoded.whereType<Map>()) {
            final visionId = (vision['id'] ?? '').toString();
            hasVision = true;
            if (visionId.isNotEmpty) {
              visionIds.add(visionId);
            }
            final milestones = vision['milestones'];
            if (milestones is! List) continue;
            for (final milestone in milestones.whereType<Map>()) {
              final name = (milestone['text'] ?? '').toString().trim();
              if (name.isEmpty) continue;
              final date = _parseMilestoneDate(milestone['date']);
              if (date == null) continue;
              hasDatedMilestone = true;
              final done = milestone['done'] == true;
              if (done) {
                if (!date.isBefore(recentStart) && !date.isAfter(recentEnd)) {
                  completedRecent.add((name: name, date: date));
                }
              } else if (date.isBefore(today)) {
                overdue.add((name: name, date: date, visionId: visionId));
              } else if (!date.isAfter(upcomingEnd)) {
                upcoming.add((name: name, date: date, visionId: visionId));
              }
            }
          }
        }
      } catch (_) {}
    }

    if (!hasVision) {
      return const _MilestoneCheckResult(
        message: '작성된 장기 비전이 없네요. 목표 탭에서 장기 비전과 마일스톤 예정일을 정해두시면 제가 챙겨드리겠습니다.',
        needsDeadlineSetup: true,
      );
    }

    if (!hasDatedMilestone) {
      return _MilestoneCheckResult(
        message:
            '예정일이 설정된 마일스톤이 없네요. 목표 탭에서 중요한 장기 비전의 마일스톤 예정일을 정해두시면 제가 챙겨드리겠습니다.',
        needsDeadlineSetup: true,
        highlightVisionIds: visionIds,
      );
    }

    completedRecent.sort((a, b) => a.date.compareTo(b.date));
    overdue.sort((a, b) => b.date.compareTo(a.date));
    upcoming.sort((a, b) => a.date.compareTo(b.date));

    final lines = <String>[];
    if (completedRecent.isNotEmpty) {
      lines.add(
        _completedMilestonePraise(
          completedRecent.map((item) => item.name).toList(),
        ),
      );
    }

    final overdueCount = overdue.length;
    final upcomingCount = upcoming.length;
    if (overdueCount > 0 && upcomingCount > 0) {
      lines.add(
        '예정일이 지난 마일스톤 $overdueCount개,\n일주일 안에 예정된 마일스톤 $upcomingCount개가 있어요.\n\n목표 탭에서 확인해보시겠습니까?',
      );
    } else if (overdueCount > 0) {
      lines.add(
        '예정일이 지난 마일스톤이\n$overdueCount개 있어요.\n\n${_quotedMilestoneNames(overdue.map((item) => item.name).toList())} 등을\n목표 탭에서 확인해보시겠습니까?',
      );
    } else if (upcomingCount > 0) {
      lines.add(
        '일주일 안에 예정된 마일스톤이\n$upcomingCount개 있어요.\n\n${_quotedMilestoneNames(upcoming.map((item) => item.name).toList())} 등을\n목표 탭에서 확인해보시겠습니까?',
      );
    } else {
      lines.add('지금 확인이 필요한 마일스톤은 없어요. 일정이 잘 정리되어 있습니다.');
    }

    return _MilestoneCheckResult(
      message: lines.join('\n\n'),
      hasIncompleteItems: overdueCount > 0 || upcomingCount > 0,
      highlightVisionIds: {
        ...overdue.map((item) => item.visionId).where((id) => id.isNotEmpty),
        ...upcoming.map((item) => item.visionId).where((id) => id.isNotEmpty),
      }.toList(),
    );
  }

  Future<void> _handleMilestoneCheck() async {
    if (_isLoading) return;
    if (!await _ensureMasterCoachAccess()) return;

    HapticFeedback.lightImpact();
    final result = await _buildMilestoneCheckResult();
    if (!mounted) return;

    final kind = result.needsDeadlineSetup
        ? 'milestone_setup'
        : result.hasIncompleteItems
        ? 'milestone_check'
        : 'milestone_notice';

    setState(() {
      _messages.add(
        ChatMessage(text: '마일스톤 확인', isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: result.message,
          isUser: false,
          time: DateTime.now(),
          kind: kind,
          highlightVisionIds: result.highlightVisionIds,
        ),
      );
      _suggestedTasks = [];
      _dynamicChips = _coach.chips;
    });
    _scrollToBottom();
    await _saveHistory();
    await AnalyticsService.logFeatureUsage('cheat_milestone_check');
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
  }

  // ── 메시지 전송 (웹앱 sendMessage 이식) ─────────────────
  Future<void> _send(String text, {String? apiInputOverride}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    if (!await _ensureMasterCoachAccess()) return;

    final isFutureTodayFlow =
        trimmed == '미래를 위한 오늘' ||
        (apiInputOverride?.startsWith('미래를 위한 오늘 - ') ?? false);
    final isVisionNewActionFlow = apiInputOverride == '미래를 위한 오늘 - 새 행동 추천받기';
    final isNextActionFlow =
        trimmed == '지금 뭐하지?' || apiInputOverride == '지금 뭐하지?';
    if (!_coach.isMaster && _isListening) {
      await _stopListening();
      if (!mounted) return;
    }
    _ctrl.clear();
    HapticFeedback.lightImpact();

    if (trimmed == '미래를 위한 오늘' && apiInputOverride == null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: '오늘, 미래를 어떻게 이어갈까요?',
            isUser: false,
            time: DateTime.now(),
            kind: 'vision_choice',
          ),
        );
        _suggestedTasks = [];
        _dynamicChips = _coach.chips;
        _suppressDefaultChips = false;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    final dateQuestionReply = _calendarDateQuestionReply(trimmed);
    if (dateQuestionReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: dateQuestionReply,
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _suggestedTasks = [];
        _dynamicChips = _coach.chips;
        _suppressDefaultChips = false;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    final navigationReply = _featureLocationReply(trimmed);
    if (navigationReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: navigationReply.message,
            isUser: false,
            time: DateTime.now(),
            kind: navigationReply.location == 'picker'
                ? 'feature_location_picker'
                : null,
          ),
        );
        _suggestedTasks = [];
        _dynamicChips = [];
        _suppressDefaultChips = navigationReply.location == 'picker';
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      if (navigationReply.location == 'picker') {
        return;
      }
      await Future.delayed(const Duration(milliseconds: 260));
      widget.onOpenFeatureLocation?.call(navigationReply.location);
      return;
    }

    if (_userData.isPlanActive && _isDeletionCommand(trimmed)) {
      final parsed = _parseDeletionCommand(trimmed);
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _dynamicChips = [];
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
        coachReplied: false,
      );

      String reply;
      if (parsed.target.isEmpty) {
        reply = _emptyDeleteTargetReply();
      } else if (widget.onDeleteCommand == null) {
        reply = '삭제할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
      } else {
        reply = await widget.onDeleteCommand!.call({
          'target': parsed.target,
          'kind': parsed.kind,
          if (parsed.date != null) 'date': _dateKey(parsed.date!),
        });
      }
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(text: reply, isUser: false, time: DateTime.now()),
        );
      });
      _scrollToBottom();
      await _saveHistory();
      return;
    }

    if (_userData.isPlanActive && _isEditCommand(trimmed)) {
      final parsed = _parseEditCommand(trimmed);
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _dynamicChips = [];
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
        coachReplied: false,
      );

      String reply;
      if (parsed.target.isEmpty) {
        reply = _emptyEditTargetReply();
      } else if (widget.onEditCommand == null) {
        reply = '수정할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
      } else {
        reply = await widget.onEditCommand!.call({
          'target': parsed.target,
          'kind': parsed.kind,
          if (parsed.date != null) 'date': _dateKey(parsed.date!),
        });
      }
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(text: reply, isUser: false, time: DateTime.now()),
        );
      });
      _scrollToBottom();
      await _saveHistory();
      return;
    }

    if (_userData.isPlanActive && _isHabitRegistrationCommand(trimmed)) {
      final parsed = _parseHabitRegistration(trimmed);
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _dynamicChips = [];
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
        coachReplied: false,
      );
      if (parsed.title.isEmpty) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: '어떤 습관을 등록할지 이름을 같이 말해줘.',
              isUser: false,
              time: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
        await _saveHistory();
        return;
      }
      final registered =
          await widget.onRegisterHabit?.call(parsed.title) ?? false;
      if (!mounted) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: registered
                ? _habitRegistrationReply(parsed.title)
                : '습관 탭을 여는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.',
            isUser: false,
            time: DateTime.now(),
          ),
        );
      });
      _scrollToBottom();
      await _saveHistory();
      return;
    }

    if (_userData.isPlanActive && _isScheduleRegistrationCommand(trimmed)) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _dynamicChips = [];
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
        coachReplied: false,
      );
      if (_needsWeeklyRepeatWeekday(trimmed)) {
        setState(() {
          _messages.add(
            ChatMessage(
              text: _weeklyRepeatWeekdayQuestion(),
              isUser: false,
              time: DateTime.now(),
            ),
          );
        });
        _scrollToBottom();
        await _saveHistory();
        return;
      }
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _showScheduleRegistrationDialog(trimmed);
      return;
    }

    // ── 냥냥코치 비구독자 무료체험 인터셉트 (API 호출 금지) ─

    if (widget.coachId == 'cat' && !_userData.isPlanActive) {
      if (_catFreeTrialStep == 1) {
        // 첫 메시지 → 업셀 응답 (로컬)
        setState(() {
          _messages.add(
            ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
          );
          _isLoading = true;
        });
        _scrollToBottom();
        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        const upsell = '냥냥코치와 더 이야기하고 싶다면\n플랜을 시작해보라냥 🐾';
        setState(() {
          _messages.add(
            ChatMessage(text: upsell, isUser: false, time: DateTime.now()),
          );
          _catFreeTrialStep = 2;
          _isLoading = false;
        });
        await _saveHistory();
        _scrollToBottom();
        await AnalyticsService.logConversationMessage(
          coachId: widget.coachId,
          usedApi: false,
        );
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) _showCatUpsellBottomSheet();
        return;
      } else if (_catFreeTrialStep >= 2) {
        // 이미 업셀 완료 → 팝업만 다시 표시
        _showCatUpsellBottomSheet();
        await AnalyticsService.logConversationMessage(
          coachId: widget.coachId,
          usedApi: false,
          coachReplied: false,
        );
        return;
      }
    }

    if (_containsAnyRestSignal(trimmed)) {
      await RecoveryInsightService.recordConditionDeclineSignalToday();
    }

    if (await _tryCancelVacation(trimmed)) return;
    if (await _tryActivateRequestedVacation(trimmed)) return;
    await _maybeStartRestDeclineRiskControl(trimmed);
    if (await _maybeOfferRest(trimmed)) return;

    // 선제개입 저항예측 시스템 1일차: 오늘 미완료 태스크 언급 + 저항신호를 태스크 단위로 기록.
    // 대화 흐름을 막지 않는 배경 기록이라 결과를 기다리지 않는다.
    if (_containsAnyRestSignal(trimmed)) {
      TaskResistanceService.detectAndRecordFromMessage(trimmed);
    }

    final directTimerMinutes = _directTimerRequestMinutes(trimmed);
    if (directTimerMinutes != null) {
      final reply = _directTimerStartMessage(directTimerMinutes);
      int timerInsertIndex = 0;
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(text: reply, isUser: false, time: DateTime.now()),
        );
        _timerConfirmMinutes = null;
        _timerConfirmTaskName = null;
        _timerActiveMinutes = directTimerMinutes;
        _timerActiveInsertIndex = _messages.length;
        timerInsertIndex = _timerActiveInsertIndex!;
        _dynamicChips = _coach.chips;
      });
      await _saveFocusTimerAnchor(directTimerMinutes, timerInsertIndex);
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    var apiInput = apiInputOverride ?? trimmed;
    var skipBroWorkoutLocalReply = false;

    if (widget.coachId == 'bro') {
      if (trimmed == '지금 할 운동') {
        setState(() {
          _messages.add(
            ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
          );
          _messages.add(
            ChatMessage(
              text: '좋아. 장소랑 강도만 말해.\n예: 집에서 쉽게, 사무실 의자에서 조용히, 밖에서 빡세게.',
              isUser: false,
              time: DateTime.now(),
            ),
          );
          _dynamicChips = ['집에서 쉽게', '사무실 의자', '밖에서 빡세게'];
          _awaitingBroWorkoutPreference = true;
        });
        _scrollToBottom();
        await _saveHistory();
        await AnalyticsService.logConversationMessage(
          coachId: widget.coachId,
          usedApi: false,
        );
        return;
      }

      if (_awaitingBroWorkoutPreference) {
        apiInput =
            '사용자가 지금 바로 할 운동을 추천받고 싶어 한다. '
            '사용자가 말한 장소/환경/강도: "$trimmed". '
            '이 조건에 맞춰 바로 시작할 수 있는 짧은 운동 루틴을 추천해줘. '
            '장소가 좁거나 조용해야 할 수 있으니 층간소음과 안전을 고려하고, '
            '말투는 갓생 형 코치답게 짧고 힘 있게 해줘.';
        skipBroWorkoutLocalReply = true;
        _awaitingBroWorkoutPreference = false;
      }

      final targetedWorkoutApiInput = _buildBroTargetedWorkoutApiInput(trimmed);
      if (targetedWorkoutApiInput != null) {
        apiInput = targetedWorkoutApiInput;
        skipBroWorkoutLocalReply = true;
      }
    }

    final broWorkoutReply = skipBroWorkoutLocalReply
        ? null
        : await _tryBuildBroWorkoutReply(trimmed);
    if (broWorkoutReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: broWorkoutReply,
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _dynamicChips = _coach.chips;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    final yesterdayIncompleteReply = await _tryBuildYesterdayIncompleteReply(
      trimmed,
    );
    if (yesterdayIncompleteReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: yesterdayIncompleteReply,
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _dynamicChips = _coach.chips;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    if (isVisionNewActionFlow) {
      if (_isCheckingVisionRecommendationAllowance) return;
      _isCheckingVisionRecommendationAllowance = true;
      final limitMessage = await _visionRecommendationLimitMessage();
      if (!mounted) {
        _isCheckingVisionRecommendationAllowance = false;
        return;
      }
      if (limitMessage != null) {
        _isCheckingVisionRecommendationAllowance = false;
        _showUsageNotice(limitMessage);
        return;
      }
    }
    if (isNextActionFlow) {
      if (_isCheckingNextActionAllowance) return;
      _isCheckingNextActionAllowance = true;
      final limitMessage = await _nextActionLimitMessage();
      if (!mounted) {
        _isCheckingNextActionAllowance = false;
        return;
      }
      if (limitMessage != null) {
        _isCheckingNextActionAllowance = false;
        _showUsageNotice(limitMessage);
        return;
      }
    }
    final currentId = widget.coachId;
    final userMsg = ChatMessage(
      text: trimmed,
      isUser: true,
      time: DateTime.now(),
    );
    setState(() {
      _messages.add(userMsg);
      _dynamicChips = [];
      _suppressDefaultChips = false;
      _coachSwitchTarget = null;
      _isLoading = true;
    });
    _scrollToBottom();

    // 로컬 응답 시도 (웹앱 getLocalResponse 이식)
    final localReply = _LocalResponses.get(widget.coachId, trimmed);
    if (localReply != null) {
      final titledReply = await UserTitleService.applyForCoach(
        localReply,
        widget.coachId,
      );
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted || widget.coachId != currentId) return;
      setState(() {
        _messages.add(
          ChatMessage(text: titledReply, isUser: false, time: DateTime.now()),
        );
        _dynamicChips = _coach.chips;
        _isLoading = false;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      if (isVisionNewActionFlow) {
        _isCheckingVisionRecommendationAllowance = false;
      }
      if (isNextActionFlow) {
        _isCheckingNextActionAllowance = false;
      }
      return;
    }

    try {
      final raw = await _callOpenAI(apiInput);
      if (isVisionNewActionFlow) {
        await _recordFeatureUsage(
          key: 'nyang_vision_new_action_usage_history',
          fallbackKey: 'nyang_vision_recommendation_history',
        );
      }
      if (isNextActionFlow) {
        await _recordFeatureUsage(key: 'nyang_next_action_usage_history');
      }
      if (!mounted || widget.coachId != currentId) return;
      final usageNotice = await ApiUsageLimitService.takeChatUsageNotice();
      if (!mounted || widget.coachId != currentId) return;
      final parsed = _parseReply(raw);
      unawaited(_confirmPreemptiveIfMentioned(parsed.text));
      final suggestedTasks = await _filterDuplicateSuggestedTasks(
        parsed.suggestedTasks,
      );
      final masterTimerEligible = await _isMasterTimerSuggestionEligible(
        parsed.timerConfirmTaskName,
        userAuthorized: _isMasterTimerAuthorizationResponse(trimmed),
      );
      if (!mounted || widget.coachId != currentId) return;
      if (isVisionNewActionFlow) {
        await _saveVisionRecommendation(parsed);
      }
      if (!mounted || widget.coachId != currentId) return;
      setState(() {
        _messages.add(
          ChatMessage(text: parsed.text, isUser: false, time: DateTime.now()),
        );
        _suppressDefaultChips = parsed.suppressDefaultChips;
        _dynamicChips = parsed.chips.isNotEmpty
            ? parsed.chips
            : (_suppressDefaultChips ? [] : _coach.chips);
        _coachSwitchTarget = parsed.coachSwitchTarget;
        if (_coach.isMaster) {
          _timerConfirmMinutes = masterTimerEligible
              ? parsed.timerConfirmMinutes
              : null;
          _timerConfirmTaskName = masterTimerEligible
              ? parsed.timerConfirmTaskName
              : null;
        } else {
          _timerConfirmMinutes = null;
          _timerConfirmTaskName = null;
          if (parsed.timerConfirmMinutes != null) {
            _timerActiveMinutes = parsed.timerConfirmMinutes;
            _timerActiveInsertIndex = _messages.length;
          }
        }
        if (!isFutureTodayFlow && parsed.suggestedTasks.isNotEmpty) {
          _suggestedTasks = suggestedTasks;
        }
        // 배너 로직 삭제 (팝업으로 대체)
        _isLoading = false;
      });
      if (!_coach.isMaster && parsed.timerConfirmMinutes != null) {
        await _saveFocusTimerAnchor(
          parsed.timerConfirmMinutes!,
          _timerActiveInsertIndex ?? _messages.length,
        );
      }
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: true,
      );
      if (usageNotice != null) {
        if (usageNotice.stage >= 100) {
          _showUsageLimitSheet(
            usageNotice.message,
            showUpgrade: usageNotice.suggestsUpgrade,
          );
        } else {
          _showUsageLimitSheet(
            usageNotice.message,
            showUpgrade: usageNotice.suggestsUpgrade,
            customTitle: '대화 한도 안내',
          );
        }
      }
    } catch (e) {
      if (!mounted || widget.coachId != currentId) return;
      setState(() => _isLoading = false);
      if (e is ApiUsageLimitException) {
        _showUsageLimitSheet(
          e.message,
          showUpgrade: e.message.contains('마스터 플랜'),
        );
      } else {
        _showError('실패: $e');
      }
    } finally {
      if (isVisionNewActionFlow) {
        _isCheckingVisionRecommendationAllowance = false;
      }
      if (isNextActionFlow) {
        _isCheckingNextActionAllowance = false;
      }
    }
  }

  _FeatureLocationReply? _featureLocationReply(String rawText) {
    final text = rawText.trim().toLowerCase().replaceAll(' ', '');
    if (text.isEmpty) return null;
    if (_isDeletionCommand(rawText)) return null;

    final mentionsFeatureSurface =
        text.contains('탭') ||
        text.contains('텝') ||
        text.contains('창') ||
        text.contains('화면');
    final mentionsFeature =
        text.contains('장기비전') ||
        text.contains('비전') ||
        text.contains('마일스톤') ||
        text.contains('목표') ||
        text.contains('오늘할일') ||
        text.contains('오늘의할일') ||
        text.contains('할일') ||
        text.contains('태스크') ||
        text.contains('설정') ||
        text.contains('알림') ||
        text.contains('모닝콜') ||
        text.contains('위젯') ||
        text.contains('채팅배경') ||
        text.contains('비서학습') ||
        text.contains('일정') ||
        text.contains('캘린더') ||
        text.contains('습관') ||
        text.contains('루틴') ||
        text.contains('기록') ||
        text.contains('리포트') ||
        text.contains('통계');
    final asksTodoReset =
        (text.contains('할일') ||
            text.contains('오늘할일') ||
            text.contains('오늘의할일')) &&
        (text.contains('초기화') || text.contains('리셋') || text.contains('reset'));
    final asksRepeatScheduleGuide =
        (text.contains('반복일정') ||
            (text.contains('반복') && text.contains('일정'))) &&
        (text.contains('어떻게') ||
            text.contains('어디') ||
            text.contains('만들') ||
            text.contains('등록') ||
            text.contains('추가') ||
            text.contains('삭제') ||
            text.contains('지우') ||
            text.contains('없애') ||
            text.contains('수정') ||
            text.contains('변경') ||
            text.contains('바꾸') ||
            text.contains('편집') ||
            text.contains('하고싶'));

    final asksLocation =
        text.contains('어디') ||
        text.contains('어떻게들어') ||
        text.contains('어떻게가') ||
        text.contains('찾아') ||
        text.contains('보여줘') ||
        text.contains('열어줘') ||
        text.contains('가줘') ||
        (mentionsFeatureSurface && mentionsFeature) ||
        asksTodoReset ||
        asksRepeatScheduleGuide;
    if (!asksLocation) return null;

    final asksGenericLocation =
        text.contains('어디서보') ||
        text.contains('어디서봐') ||
        text.contains('어디인지') ||
        text.contains('어디에있는지') ||
        text.contains('어딨') ||
        text.contains('모르겠');

    if (text.contains('장기비전') ||
        text.contains('비전창') ||
        text.contains('비전어디') ||
        text.contains('마일스톤')) {
      return _FeatureLocationReply(_featureLocationMessage('vision'), 'vision');
    }

    if (text.contains('목표')) {
      return _FeatureLocationReply(_featureLocationMessage('goals'), 'goals');
    }

    if (asksTodoReset ||
        text.contains('설정') ||
        text.contains('알림') ||
        text.contains('모닝콜') ||
        text.contains('일정알람') ||
        text.contains('위젯') ||
        text.contains('채팅배경') ||
        text.contains('배경') ||
        text.contains('오늘할일초기화') ||
        text.contains('오늘의할일초기화') ||
        text.contains('할일초기화') ||
        text.contains('오늘할일리셋') ||
        text.contains('오늘의할일리셋') ||
        text.contains('할일리셋') ||
        text.contains('초기화시간') ||
        text.contains('리셋시간') ||
        text.contains('비서학습') ||
        text.contains('학습설정') ||
        text.contains('호칭')) {
      return _FeatureLocationReply(
        _featureLocationMessage('settings'),
        'settings',
      );
    }

    if (text.contains('오늘할일') ||
        text.contains('오늘의할일') ||
        text.contains('할일') ||
        text.contains('태스크')) {
      return _FeatureLocationReply(_featureLocationMessage('today'), 'today');
    }

    if (asksRepeatScheduleGuide) {
      final repeatLocation =
          text.contains('삭제') ||
              text.contains('지우') ||
              text.contains('없애') ||
              text.contains('취소')
          ? 'repeat_schedule_delete'
          : (text.contains('수정') ||
                text.contains('변경') ||
                text.contains('바꾸') ||
                text.contains('편집') ||
                text.contains('고치'))
          ? 'repeat_schedule_edit'
          : 'repeat_schedule';
      return _FeatureLocationReply(
        _featureLocationMessage(repeatLocation),
        'schedule',
      );
    }

    final asksDatedPlan =
        text.contains('내일계획') ||
        text.contains('내일플랜') ||
        text.contains('내일뭐') ||
        text.contains('내일할거') ||
        text.contains('내일할일') ||
        (text.contains('계획') &&
            (text.contains('내일') ||
                text.contains('날짜') ||
                text.contains('이번주') ||
                text.contains('다음주')));

    if (text.contains('일정') || text.contains('캘린더') || asksDatedPlan) {
      return _FeatureLocationReply(
        _featureLocationMessage('schedule'),
        'schedule',
      );
    }

    if (text.contains('습관') || text.contains('루틴')) {
      return _FeatureLocationReply(_featureLocationMessage('habit'), 'habit');
    }

    if (text.contains('기록') || text.contains('리포트') || text.contains('통계')) {
      return _FeatureLocationReply(
        _featureLocationMessage('records'),
        'records',
      );
    }

    if (asksGenericLocation) {
      return _FeatureLocationReply(_featureLocationMessage('picker'), 'picker');
    }

    return null;
  }

  String _featureLocationMessage(String location) {
    final target = switch (location) {
      'today' => '오늘 할 일',
      'goals' => '목표',
      'vision' => '장기 비전',
      'repeat_schedule' => '반복 일정',
      'repeat_schedule_delete' => '반복 일정',
      'repeat_schedule_edit' => '반복 일정',
      'schedule' => '일정',
      'habit' => '습관',
      'records' => '기록',
      'settings' => '설정',
      _ => '',
    };

    String base(String suffix) => target.isEmpty ? suffix : '$target$suffix';

    return switch (_coach.id) {
      'cat' => switch (location) {
        'picker' => '어떤 화면 찾는 거냥? 냥이가 바로 데려다주겠다냥.',
        'settings' =>
          '설정 탭에 있다냥. 모닝콜, 일정 알람, 위젯, 채팅 배경, 초기화 시간, 비서 학습 설정까지 거기서 바꾸면 된다냥.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있다냥. 바로 열어주겠다냥.',
        'repeat_schedule' =>
          '반복 일정은 일정 탭에서 만든다냥. 일정을 입력하고 시계 버튼을 누른 다음 반복을 고르면 된다냥.',
        'repeat_schedule_delete' =>
          '반복 일정은 일정 탭에서 해당 일정을 누르고 삭제하기를 누르면 된다냥. 반복으로 등록된 같은 일정이 같이 삭제된다냥.',
        'repeat_schedule_edit' =>
          '반복 일정 수정은 일정 탭에서 해당 일정을 눌러서 하면 된다냥. 바로 일정 탭으로 데려다주겠다냥.',
        _ => '${base(' 화면으로 바로 데려다주겠다냥.')}',
      },
      'boyfriend' => switch (location) {
        'picker' => '어디 찾는지 말해줘. 내가 바로 데려다줄게.',
        'settings' =>
          '설정 탭에 있어. 모닝콜, 일정 알람, 위젯, 채팅 배경, 초기화 시간, 비서 학습 설정까지 거기서 바꾸면 돼.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있어. 내가 바로 열어줄게.',
        'repeat_schedule' =>
          '반복 일정은 일정 탭에서 만들면 돼. 일정 입력하고 시계 버튼 누른 다음 반복을 고르면 돼.',
        'repeat_schedule_delete' =>
          '반복 일정은 일정 탭에서 해당 일정을 누르고 삭제하기를 누르면 돼. 반복으로 등록된 같은 일정이 같이 삭제돼.',
        'repeat_schedule_edit' => '반복 일정 수정은 일정 탭에서 해당 일정을 눌러서 하면 돼. 바로 열어줄게.',
        _ => '${base(' 화면에 있어. 바로 열어줄게.')}',
      },
      'girlfriend' => switch (location) {
        'picker' => '오빠 어디 찾는 거야? 내가 바로 데려다줄게!',
        'settings' =>
          '오빠, 설정 탭에 있어! 모닝콜, 일정 알람, 위젯, 채팅 배경, 초기화 시간, 비서 학습 설정까지 거기서 바꾸면 돼.',
        'vision' => '오빠 장기 비전은 목표 화면 아래쪽에 있어. 바로 열어줄게!',
        'repeat_schedule' =>
          '오빠, 반복 일정은 일정 탭에서 만들면 돼! 일정 입력하고 시계 버튼 누른 다음 반복을 고르면 돼.',
        'repeat_schedule_delete' =>
          '오빠, 반복 일정은 일정 탭에서 해당 일정을 누르고 삭제하기를 누르면 돼! 반복으로 등록된 같은 일정이 같이 삭제돼.',
        'repeat_schedule_edit' =>
          '오빠, 반복 일정 수정은 일정 탭에서 해당 일정을 눌러서 하면 돼. 바로 열어줄게!',
        _ => '오빠, ${base(' 화면에 있어. 바로 열어줄게!')}',
      },
      'halmae' => switch (location) {
        'picker' => '뭘 찾는 게냐, 우리 새끼. 할미가 바로 데려다주마.',
        'settings' =>
          '설정 탭에 있다, 우리 새끼. 모닝콜이랑 알람, 위젯, 채팅 배경, 초기화 시간, 비서 학습 설정 다 거기서 바꾸면 된다.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있다. 할미가 바로 열어주마.',
        'repeat_schedule' =>
          '반복 일정은 일정 탭에서 만든다, 우리 새끼. 일정 적고 시계 버튼 누른 다음 반복을 고르면 된다.',
        'repeat_schedule_delete' =>
          '반복 일정은 일정 탭에서 그 일정을 누르고 삭제하기를 누르면 된다. 반복으로 등록된 같은 일정이 같이 지워진다.',
        'repeat_schedule_edit' =>
          '반복 일정 수정은 일정 탭에서 그 일정을 눌러서 하면 된다. 할미가 바로 열어주마.',
        _ => '${base(' 화면에 있다. 할미가 바로 열어주마.')}',
      },
      'bro' => switch (location) {
        'picker' => '어디 찾냐. 말만 해라, 바로 보내준다.',
        'settings' =>
          '설정 탭이다. 모닝콜, 일정 알람, 위젯, 채팅 배경, 초기화 시간, 비서 학습 설정 다 거기서 바꾸면 된다.',
        'vision' => '장기 비전은 목표 화면 아래쪽이다. 바로 열어준다.',
        'repeat_schedule' =>
          '반복 일정은 일정 탭에서 만든다. 일정 입력하고 시계 버튼 누른 다음 반복을 고르면 된다.',
        'repeat_schedule_delete' =>
          '반복 일정은 일정 탭에서 해당 일정 누르고 삭제하기 누르면 된다. 반복으로 등록된 같은 일정이 같이 삭제된다.',
        'repeat_schedule_edit' => '반복 일정 수정은 일정 탭에서 해당 일정 눌러서 하면 된다. 바로 열어준다.',
        _ => '${base(' 화면이다. 바로 열어준다.')}',
      },
      'sec_male' => switch (location) {
        'picker' => '대표님, 찾으시는 화면을 선택해 주시면 바로 이동하겠습니다.',
        'settings' =>
          '대표님, 설정 탭에서 모닝콜, 일정 알람, 위젯, 채팅 배경, 오늘 할 일 초기화 시간, 비서 학습 설정을 변경하실 수 있습니다.',
        'vision' => '대표님, 장기 비전은 목표 화면 하단에서 확인하실 수 있습니다. 바로 이동하겠습니다.',
        'repeat_schedule' =>
          '대표님, 반복 일정은 일정 탭에서 생성하실 수 있습니다. 일정을 입력한 뒤 시계 버튼을 누르고 반복을 선택해 주세요.',
        'repeat_schedule_delete' =>
          '대표님, 반복 일정은 일정 탭에서 해당 일정을 누른 뒤 삭제하기를 선택하시면 됩니다. 반복으로 등록된 같은 일정이 함께 삭제됩니다.',
        'repeat_schedule_edit' =>
          '대표님, 반복 일정 수정은 일정 탭에서 해당 일정을 선택해 진행하실 수 있습니다. 바로 이동하겠습니다.',
        _ => '대표님, ${base(' 화면으로 바로 이동하겠습니다.')}',
      },
      'sec_female' => switch (location) {
        'picker' => '대표님, 어떤 화면을 찾으세요? 제가 바로 열어드릴게요.',
        'settings' =>
          '대표님, 설정 탭에서 모닝콜, 일정 알람, 위젯, 채팅 배경, 오늘 할 일 초기화 시간, 비서 학습 설정을 바꿀 수 있어요.',
        'vision' => '대표님, 장기 비전은 목표 화면 아래쪽에 있어요. 바로 열어드릴게요.',
        'repeat_schedule' =>
          '대표님, 반복 일정은 일정 탭에서 만들 수 있어요. 일정을 입력한 뒤 시계 버튼을 누르고 반복을 선택해 주세요.',
        'repeat_schedule_delete' =>
          '대표님, 반복 일정은 일정 탭에서 해당 일정을 누른 뒤 삭제하기를 선택하면 돼요. 반복으로 등록된 같은 일정이 함께 삭제돼요.',
        'repeat_schedule_edit' =>
          '대표님, 반복 일정 수정은 일정 탭에서 해당 일정을 선택해 진행할 수 있어요. 바로 이동할게요.',
        _ => '대표님, ${base(' 화면으로 바로 이동할게요.')}',
      },
      _ => switch (location) {
        'picker' => '어떤 화면을 찾고 있어? 바로 열어줄게.',
        'settings' =>
          '설정 탭에서 모닝콜, 일정 알람, 위젯, 채팅 배경, 오늘 할 일 초기화 시간, 비서 학습 설정을 바꿀 수 있어.',
        'vision' => '장기 비전은 목표 화면 아래쪽에 있어. 바로 열어줄게.',
        'repeat_schedule' =>
          '반복 일정은 일정 탭에서 만들 수 있어. 일정을 입력하고 시계 버튼을 누른 다음 반복을 선택하면 돼.',
        'repeat_schedule_delete' =>
          '반복 일정은 일정 탭에서 해당 일정을 누르고 삭제하기를 선택하면 돼. 반복으로 등록된 같은 일정이 함께 삭제돼.',
        'repeat_schedule_edit' => '반복 일정 수정은 일정 탭에서 해당 일정을 눌러서 하면 돼. 바로 열어줄게.',
        _ => '${base(' 화면에 있어. 바로 열어줄게.')}',
      },
    };
  }

  // ── 웹앱 buildMemoryContext() 이식 (전 코치 등급) ───────
  Future<String> _buildContextString(String userText) async {
    final tier = _coach.tier; // 'friends' | 'master'
    final prefs = await SharedPreferences.getInstance();
    final sb = StringBuffer();
    final now = DateTime.now();
    final needsGoalContext = _needsMasterGoalContext(userText);
    final needsTaskContext = _needsMasterTaskContext(
      userText,
      needsGoalContext,
    );
    final needsLightGoalContext =
        !needsGoalContext && _needsMasterLightGoalContext(userText);

    // 1. 마스터 프로필 (tier별 분기)
    final mpRaw = prefs.getString('nyang_master_profile');
    if (mpRaw != null &&
        mpRaw != 'null' &&
        (!_coach.isMaster || needsGoalContext)) {
      try {
        final mp = jsonDecode(mpRaw) as Map<String, dynamic>;
        final hc = (mp['high_change'] as Map<String, dynamic>?) ?? {};
        final mc = (mp['mid_change'] as Map<String, dynamic>?) ?? {};
        final lc = (mp['low_change'] as Map<String, dynamic>?) ?? {};
        final chapter = (mc['chapter'] as Map<String, dynamic>?) ?? {};
        final keywords =
            (mc['keywords_axis'] as List?)
                ?.map((e) => e is Map ? (e['value'] ?? e) : e)
                .join(', ') ??
            '';

        sb.writeln('\n[사용자 마스터 프로필]');

        if (tier == 'friends') {
          // friends: high_change 기본 정보만
          sb.writeln(
            '- 실시간 상태: ${hc['energy_fatigue'] ?? '관찰 중'} / ${hc['mood_condition'] ?? '기록 전'}',
          );
          sb.writeln('- 오늘의 장애물: ${hc['obstacles'] ?? '없음'}');
        } else {
          // master: 전체
          final scenes = (hc['scenes_insights'] as List?) ?? [];
          final lcCandidates = (mp['low_change_candidates'] as List?) ?? [];
          sb.writeln('[고변화 - 실시간]');
          sb.writeln(
            '- 상태: ${hc['energy_fatigue'] ?? '관찰 중'} / ${hc['mood_condition'] ?? '기록 전'}',
          );
          sb.writeln('- 장애물: ${hc['obstacles'] ?? '없음'}');
          sb.writeln('\n[중변화 - 최근 맥락]');
          sb.writeln(
            '- 챕터: ${chapter['title'] ?? ''} (${chapter['description'] ?? ''})',
          );
          sb.writeln('- 관심 축: $keywords');
          sb.writeln('\n[저변화 - 본질/패턴]');
          sb.writeln('- 정체성: ${lc['identity'] ?? ''}');
          sb.writeln('- 의사결정 패턴: ${lc['decision_pattern'] ?? ''}');
          sb.writeln('- 소통 프로토콜: ${lc['communication_protocol'] ?? ''}');
          sb.writeln('- 성공/실패 공식: ${lc['success_failure_formula'] ?? ''}');
          sb.writeln('- 개입 규칙: ${lc['intervention_rules'] ?? ''}');
          if (scenes.isNotEmpty) {
            sb.writeln('\n[코칭 개입 데이터 - 언어적 동기화 용]');
            for (final s in scenes) {
              sb.writeln('- [인상적인 장면]: ${s['scene']}');
              sb.writeln('  [사용자 고유 표현]: "${s['expression']}"');
              sb.writeln('  [인사이트]: ${s['insight']}');
            }
          }
          if (lcCandidates.isNotEmpty) {
            sb.writeln('\n[저변화 승급 후보]');
            for (final c in lcCandidates) {
              sb.writeln('- ${c['field']}: ${c['value']} (이유: ${c['reason']})');
            }
          }
        }
      } catch (_) {}
    }

    // 코칭 개입 규칙
    if (!_coach.isMaster || needsGoalContext) {
      sb.writeln('''
[코칭 개입 규칙 (매우 중요)]
1. 언어적 동기화: [사용자 고유 표현]을 문장 속에 자연스럽게 섞어 사용하세요. (주 1~2회 빈도 제한)
2. 맥락 기반 제언: [중변화]의 [관심 축]을 활용해 현재 상황의 원인을 짚어주세요.
3. 패턴 브레이킹: [저변화]의 [성공/실패 공식] 감지 시, 상황 묘사형으로 부드럽게 개입하세요.
4. 실시간 Lite 모드: 프로필을 읽기 전용으로만 참조하며, 직접 수정을 언급하지 마세요.''');
    }

    // 16. 휴식 모드 시 특별 코칭 지침
    final isVacation =
        widget.vacationInfo != null ||
        prefs.getString('nyang_vacation') != null;
    if (isVacation) {
      sb.writeln('\n[특별 지침: 번아웃 방지 및 충전을 위한 휴식 모드 (최우선 지침)]');
      sb.writeln(
        '현재 사용자는 번아웃을 방지하고 충전하기 위한 휴식 모드 상태입니다. 다음 규칙을 철저히 준수하여 대응하십시오:',
      );
      sb.writeln(
        '1. **마음의 부담 완화**: 사용자가 오늘 계획한 일이나 할 일을 하지 못하는 것에 대해 느끼는 죄책감이나 심리적 부담감을 대화를 통해 덜어주세요. "쉬어도 괜찮다", "충전도 하루의 중요한 일부이다"라는 점을 강조하며 따뜻하게 공감해 주고 마음의 부담을 낮춰주어야 합니다.',
      );
      sb.writeln(
        '2. **압박 금지**: 오늘의 할 일이나 우선순위, 장기 목표 등을 달성하도록 독촉, 권유하거나 실행을 제안하지 마십시오. 일과 학업 등에 관한 압박이나 잔소리를 철저히 금합니다.',
      );
      sb.writeln(
        '3. **기본 루틴 유지 유도**: 생산적이거나 부담스러운 일을 권하는 대신, 건강과 웰니스를 위한 아주 최소한의 기본 루틴(예: 제때 식사하기, 물 자주 마시기, 가벼운 스트레칭하기, 충분한 수면 취하기 등)을 잘 챙길 수 있도록 다정하게 격려하고 도우세요.',
      );
      sb.writeln(
        '4. **어조**: 평소보다 더 부드럽고, 지지적이며, 편안한 어조로 말하십시오. 사용자가 이 휴식 시간을 죄책감 없이 온전히 누릴 수 있도록 대화로 안심시켜 주는 비서/친구 역할을 수행하세요.',
      );
      if (_coach.isMaster) {
        sb.writeln(
          '5. **프렌즈 코치 안내(최초 1회, 강요 금지)**: 대화 기록에서 이미 프렌즈 코치(냥냥이 등)를 언급한 적이 없다면, 이번 응답에서 딱 한 번만 "오늘은 편하게 계셔도 되고, 혹시 가벼운 대화 상대가 필요하시면 프렌즈 코치들도 있습니다" 정도로 지나가듯 안내하세요. 이미 언급했었다면 반복하지 말고, 사용자가 계속 대화하고 싶어하는 기색이면 언급하지 마세요.',
        );
      }
    }

    final recoveryPrompt = _coach.isMaster
        ? await RecoveryInsightService.buildMasterRecoveryPromptGuidance()
        : null;
    if (!isVacation && recoveryPrompt != null) {
      sb.writeln(recoveryPrompt);
    }

    // 선제개입 저항예측: 자주 저항했던 일정을 자연스러운 타이밍에 화제로 제시 (강요 아님, 휴식모드와 중복 방지)
    // 이번 턴에 실제로 화제를 꺼냈는지는 응답을 받은 뒤 확인한다 (_confirmPreemptiveIfMentioned 참고).
    // 마스터 코치 전용 — 프렌즈 코치는 "압박 없는 오늘 하루" 컨셉이라 목표/태스크 체크인을 하지 않음.
    _pendingPreemptiveTarget = null;
    if (_coach.isMaster && !isVacation && recoveryPrompt == null) {
      final preemptive =
          await TaskResistanceService.findPreemptiveInterventionTarget(
            coachId: widget.coachId,
          );
      if (preemptive != null) {
        _pendingPreemptiveTarget = preemptive;
        if (preemptive.isTimeSpecific) {
          // 시간 지정형: "지금 여유되면" 톤이 아니라 일정정리/컨디션/시간확보 확인 톤으로.
          sb.writeln('\n[특별 지침: 시간 지정 일정 체크인 (자연스러운 타이밍에만, 강요 금지)]');
          sb.writeln(
            '사용자가 평소 자주 부담스러워했던 "${preemptive.taskText}" 일정이 곧 시작됩니다(정해진 시간 있음). 다음 규칙을 지키며 대화 흐름에 맞을 때만 화제로 꺼내보세요:',
          );
          sb.writeln(
            '1. **일정/컨디션/시간 확보를 묻는 질문으로**: "${preemptive.taskText}"를 지금 당장 하라고 권하지 말고, 이미 정해둔 시간을 존중하며 가볍게 확인하세요. 예: "이따 ${preemptive.taskText} 있으신데 다른 일정은 정리되고 계세요?", "${preemptive.taskText} 앞두고 계신데 컨디션은 괜찮으세요?", "이따 시간 확보는 괜찮으신가요?"',
          );
          sb.writeln(
            '2. **"마음의 준비" 같은 표현 금지**: 감정을 직접 짚어주는 표현("마음의 준비 되셨어요?" 등)은 쓰지 말고, 상황·논리 위주로 가볍게 확인하세요.',
          );
          sb.writeln(
            '3. **명령·추궁 금지**: "${preemptive.taskText} 하세요" 같은 명령형이나 "왜 아직 안 하셨어요?" 같은 추궁형은 절대 쓰지 마세요.',
          );
          sb.writeln(
            '4. **타이밍이 안 맞으면 생략**: 지금 이 화제를 꺼내는 게 어색하다고 판단되면 이번 턴엔 언급하지 않아도 됩니다.',
          );
          sb.writeln('5. 이 지침은 이번 응답에서 한 번만 적용하고, 같은 응답 안에서 반복하지 마세요.');
        } else {
          sb.writeln('\n[특별 지침: 선제 화제 제시 (자연스러운 타이밍에만, 강요 금지)]');
          sb.writeln(
            '사용자가 평소 자주 부담스러워했던 "${preemptive.taskText}" 일정이 오늘 아직 남아있습니다. 다음 규칙을 지키며 대화 흐름에 맞을 때만 화제로 꺼내보세요:',
          );
          sb.writeln(
            '1. **질문으로 시작**: 반드시 질문 형태로 제안하세요. 예: "그러고 보니 오늘 ${preemptive.taskText} 일정도 있으셨죠. 오늘은 어떠세요?", "지금 여유 있으시다면 ${preemptive.taskText}부터 해보시는 건 어떠세요?"',
          );
          sb.writeln(
            '2. **명령·추궁 금지**: "${preemptive.taskText} 하세요" 같은 명령형이나 "왜 아직 안 하셨어요?" 같은 추궁형은 절대 쓰지 마세요.',
          );
          sb.writeln(
            '3. **대화 맥락에 연결**: 사용자가 지금 다른 감정이나 급한 일을 이야기하고 있다면, 먼저 충분히 공감한 뒤 자연스럽게 이어서 화제를 꺼내세요. 예: 사용자가 "너무 피곤하다"고 하면 "오늘 하루 쉽지 않으셨군요. 그러고 보니 오늘 ${preemptive.taskText} 일정도 있으셨죠. 오늘은 어떠세요?"처럼 연결하세요.',
          );
          sb.writeln(
            '4. **타이밍이 안 맞으면 생략**: 지금 이 화제를 꺼내는 게 어색하다고 판단되면 이번 턴엔 언급하지 않아도 됩니다.',
          );
          sb.writeln('5. 이 지침은 이번 응답에서 한 번만 적용하고, 같은 응답 안에서 반복하지 마세요.');
        }
      }
    }

    // 2. 장기 패턴
    final ltRaw = prefs.getString('nyang_long_term');
    if (ltRaw != null && (!_coach.isMaster || needsGoalContext)) {
      try {
        final lt = jsonDecode(ltRaw) as List;
        if (lt.isNotEmpty) {
          sb.writeln('\n[이 사용자의 장기 패턴]');
          for (int i = 0; i < lt.length; i++) sb.writeln('${i + 1}. ${lt[i]}');
        }
      } catch (_) {}
    }

    // 3. 최근 7일 요약
    final dsRaw = prefs.getString('nyang_daily_summaries');
    if (dsRaw != null && (!_coach.isMaster || needsGoalContext)) {
      try {
        final ds = jsonDecode(dsRaw) as List;
        if (ds.isNotEmpty) {
          final todayKey = _getTodayStrWithReset(prefs);
          final recentUntilYesterday = ds.where((summary) {
            final date = summary['date']?.toString() ?? '';
            return date.isNotEmpty && date.compareTo(todayKey) < 0;
          }).toList();
          final recent = recentUntilYesterday.length > 7
              ? recentUntilYesterday.sublist(recentUntilYesterday.length - 7)
              : recentUntilYesterday;
          sb.writeln('\n[최근 7일 요약 - 오늘 제외, 어제까지]');
          if (recent.isEmpty) {
            sb.writeln('- 어제까지의 일일 요약이 아직 충분하지 않음');
          }
          for (final s in recent) {
            sb.writeln(
              '${s['date']}: 달성(${s['achieved']}) / 못함(${s['missed']}) / 컨디션(${s['condition']}) / 고민(${s['concern']})',
            );
          }
        }
      } catch (_) {}
    }

    // 4. 최근 7일 완료/미완료 할 일 (master only)
    if (_coach.isMaster && needsGoalContext) {
      final histRaw = prefs.getString('nyang_history');
      if (histRaw != null) {
        try {
          final hist = jsonDecode(histRaw) as List;
          if (hist.isNotEmpty) {
            final todayKey = _getTodayStrWithReset(prefs);
            final last7UntilYesterday = hist.where((record) {
              final date = record['date']?.toString() ?? '';
              return date.isNotEmpty && date.compareTo(todayKey) < 0;
            }).toList();
            final last7 = last7UntilYesterday.length > 7
                ? last7UntilYesterday.sublist(last7UntilYesterday.length - 7)
                : last7UntilYesterday;
            sb.writeln('\n[최근 7일간 실제 완료/미완료 할 일 목록 - 오늘 제외, 어제까지]');
            if (last7.isEmpty) {
              sb.writeln('- 어제까지의 완료/미완료 기록이 아직 충분하지 않음');
            }
            for (final record in last7) {
              final rTasks = (record['tasks'] as List?) ?? [];
              final done = rTasks
                  .where((t) => t['done'] == true)
                  .map((t) => t['text'])
                  .join(', ');
              final undone = rTasks
                  .where((t) => t['done'] != true)
                  .map((t) => t['text'])
                  .join(', ');
              sb.writeln(
                '- ${record['date']}: 완료 [${done.isEmpty ? '없음' : done}], 미완료 [${undone.isEmpty ? '없음' : undone}]',
              );
            }
            sb.writeln(
              '*미래를 위한 오늘 요청에서는 이 섹션을 사용자의 최근 일주일 흐름 평가 근거로 삼고, 오늘 할 일의 미완료 상태는 아직 진행 중인 계획으로만 봅니다.',
            );
          }
        } catch (_) {}
      }
    }

    // 5. 오늘 할 일 현황
    final tasksRaw = prefs.getString('nyang_tasks');
    List<dynamic> allTasks = [];
    bool newActivityDayNotStarted = false;
    if (tasksRaw != null && needsTaskContext) {
      try {
        allTasks = jsonDecode(tasksRaw) as List;
        if (allTasks.isNotEmpty) {
          newActivityDayNotStarted = _isNewActivityDayPendingStart(
            prefs,
            userText: userText,
            tasks: allTasks,
          );

          sb.writeln(
            newActivityDayNotStarted
                ? '\n[새 활동일용 할 일 - 리셋 후 아직 시작 전]'
                : '\n[오늘 할 일 현황]',
          );
          final incompleteTasks = allTasks
              .where((task) => task['done'] != true)
              .toList();
          for (final t in allTasks) {
            final done = t['done'] == true;
            final inProgress = !done && t['inProgress'] == true;
            final timeStr = t['time'] != null ? '${t['time']}' : '';
            String durStr = '';
            if (t['duration'] != null) {
              String rawDur = t['duration'].toString();
              String explicitDur = rawDur;
              if (rawDur == '1시간')
                explicitDur = '1시간(60분)';
              else if (rawDur == '2시간')
                explicitDur = '2시간(120분)';
              else if (rawDur == '3시간')
                explicitDur = '3시간(180분)';
              else if (rawDur == '4시간+')
                explicitDur = '4시간 이상(240분 이상)';
              durStr = '예상 소요시간: $explicitDur';
            }
            final timeInfoParts = [
              timeStr,
              durStr,
            ].where((s) => s.isNotEmpty).join(', ');
            final timeInfo = timeInfoParts.isNotEmpty
                ? ' ($timeInfoParts)'
                : '';
            final isHabit = t['isHabit'] == true || t['category'] == 'habit';
            final isSchedule = t['category'] == 'schedule';
            final deferredCount = (t['deferredCount'] as num?)?.toInt() ?? 0;
            final deferredInfo = deferredCount > 0
                ? ' / 앱 기록상 미루기 ${deferredCount}회'
                : '';
            final conversationAvoidanceCount = done
                ? 0
                : _conversationAvoidanceCountForTask(
                    (t['text'] ?? '').toString(),
                    allowGeneric: incompleteTasks.length == 1,
                  );
            final conversationAvoidanceInfo = conversationAvoidanceCount > 0
                ? ' / 최근 대화상 귀찮음 표현 ${conversationAvoidanceCount}회'
                : '';
            final inProgressInfo = inProgress ? ' / 진행중(시작만 하고 아직 완료 전)' : '';
            final typeLabel = isHabit
                ? '습관'
                : isSchedule
                ? '일정'
                : '일반 할 일';
            sb.writeln(
              newActivityDayNotStarted
                  ? '- [예정] [$typeLabel] ${t['text']}$timeInfo'
                  : '- [${done
                        ? 'V'
                        : inProgress
                        ? '~'
                        : ' '}] [$typeLabel] ${t['text']}$timeInfo$deferredInfo$conversationAvoidanceInfo$inProgressInfo',
            );
          }
          if (newActivityDayNotStarted) {
            final previousDayAllDone =
                prefs.getBool(DailyResetService.previousDayAllDoneKey) ?? false;
            sb.writeln(
              '*이 목록은 하루 리셋 후 새 활동일을 위해 생성된 예정 목록이다. 사용자가 방금까지 하다 남긴 일이나 현재 마무리해야 할 일이 아니다.',
            );
            if (previousDayAllDone) {
              sb.writeln(
                '*사용자는 리셋 직전 활동일의 할 일을 모두 완료했다. 이전 날에 남은 일이 있다고 말하지 말 것.',
              );
            }
            sb.writeln(
              '*사용자가 새 하루의 실행을 명시적으로 요청하기 전에는 이 목록을 "남은 일", "미완료 일정", "밀린 일"이라고 부르거나 다음 날로 이월하라고 제안하지 말 것.',
            );
            sb.writeln('*감정 토로 중에는 이 예정 목록을 근거로 압박하거나 일정 조정을 제안하지 말 것.');
          } else {
            sb.writeln('*[V] 표시된 항목은 완료됨. 완료 항목은 절대 다시 실행 유도하지 말 것.');
            sb.writeln(
              '*[~] 표시된 항목은 사용자가 이미 시작했지만 아직 완료 전인 상태. "아직 안 했네요"처럼 아예 안 한 것으로 말하지 말고, 이미 시작한 것을 인정하며 마무리를 자연스럽게 격려할 것.',
            );
            sb.writeln(
              '*타이머 확인 카드는 "앱 기록상 미루기 2회 이상"으로 표시된 미완료 할 일에만 제안할 수 있음.',
            );
            sb.writeln(
              '*"최근 대화상 귀찮음 표현 2회 이상"이지만 앱 기록상 미루기 2회 미만인 경우에는 카드를 띄우지 말고, 먼저 달랜 뒤 "필요하면 타이머라도 띄워드릴까요?"라고 말로만 물을 것. 이 경우 [TIMER_CONFIRM] 태그는 절대 출력하지 말 것.',
            );
          }
        }
      } catch (_) {}
    }

    // 6. 오늘의 핵심 (master only)
    if (_coach.isMaster && needsGoalContext) {
      final coreRaw = prefs.getString('nyang_core_tasks');
      if (coreRaw != null) {
        try {
          final coreTasks = jsonDecode(coreRaw) as List;
          if (coreTasks.isNotEmpty) {
            sb.writeln('\n[오늘의 핵심 (우선순위 1~3위)]');
            for (int i = 0; i < coreTasks.length; i++) {
              final c = coreTasks[i];
              final orig = allTasks.firstWhere(
                (t) => t['text'] == c['text'],
                orElse: () => null,
              );
              final isDone = orig != null ? orig['done'] == true : false;
              final statusLabel = newActivityDayNotStarted
                  ? '새 활동일 예정'
                  : isDone
                  ? '완료'
                  : '미완료';
              sb.writeln('${i + 1}위: [$statusLabel] ${c['text']}');
            }
            sb.writeln(
              '*위 핵심 할 일은 사용자가 오늘 가장 중요하게 생각하는 우선순위입니다. 비서로서 우선순위에 집중할 수 있도록 가이드해주세요.',
            );
            sb.writeln('*완료된 핵심 항목은 절대 다시 하라고 언급하지 말 것.');
          }
        } catch (_) {}
      }
    }

    // 7. 이번 주/달 목표 (pro + master)
    if (_coach.isMaster && (needsGoalContext || needsLightGoalContext)) {
      final wgRaw = prefs.getString('nyang_week_goals');
      if (wgRaw != null) {
        try {
          final wg = jsonDecode(wgRaw) as List;
          if (wg.isNotEmpty) {
            sb.writeln('\n[이번 주 목표]');
            for (final g in wg) {
              if (needsLightGoalContext) {
                sb.writeln('- ${g['text']}');
              } else {
                sb.writeln('- [${g['done'] == true ? 'V' : ' '}] ${g['text']}');
              }
            }
          }
        } catch (_) {}
      }
      final mgRaw = prefs.getString('nyang_month_goals');
      if (mgRaw != null) {
        try {
          final mg = jsonDecode(mgRaw) as List;
          if (mg.isNotEmpty) {
            sb.writeln('\n[이번 달 목표]');
            for (final g in mg) {
              if (needsLightGoalContext) {
                sb.writeln('- ${g['text']}');
              } else {
                sb.writeln('- [${g['done'] == true ? 'V' : ' '}] ${g['text']}');
              }
            }
          }
        } catch (_) {}
      }
    }

    // 8. 장기 비전 + 마일스톤 (pro + master)
    if (_coach.isMaster && (needsGoalContext || needsLightGoalContext)) {
      final visRaw = prefs.getString('nyang_visions');
      if (visRaw != null) {
        try {
          final visions = jsonDecode(visRaw) as List;
          if (visions.isNotEmpty) {
            sb.writeln('\n[사용자의 장기 비전 및 마일스톤]');
            for (final v in visions) {
              final milestones = (v['milestones'] as List?) ?? [];
              final doneCount = milestones
                  .where((m) => m['done'] == true)
                  .length;
              final dl = (v['deadline'] as Map<String, dynamic>?) ?? {};
              if (needsLightGoalContext) {
                sb.writeln('- 비전명: ${v['name']}');
              } else {
                sb.writeln(
                  '- 비전명: ${v['name']} (${dl['year']}년 ${dl['month']}월 ${dl['period']}까지)',
                );
                sb.writeln(
                  '  상태: 총 ${milestones.length}단계 중 ${doneCount}단계 완료',
                );
              }
              for (int i = 0; i < milestones.length; i++) {
                final m = milestones[i];
                if (needsLightGoalContext) {
                  sb.writeln('    - ${m['text']}');
                } else {
                  sb.writeln(
                    '    [${m['done'] == true ? 'V' : ' '}] ${i + 1}. ${m['text']}',
                  );
                }
                if (needsLightGoalContext) continue;
                final actionCandidates = (m['actionCandidates'] as List?) ?? [];
                final actionTitles = actionCandidates
                    .whereType<Map>()
                    .map(
                      (action) => (action['title'] ?? action['text'] ?? '')
                          .toString()
                          .trim(),
                    )
                    .where((title) => title.isNotEmpty)
                    .toList();
                if (actionTitles.isNotEmpty) {
                  sb.writeln('      실행 아이템: ${actionTitles.join(', ')}');
                }
              }
            }
            if (needsLightGoalContext) {
              sb.writeln('\n[귀찮음 상황의 목표 연결 규칙]');
              sb.writeln(
                '*사용자가 귀찮아하는 일이 위 목표와 자연스럽게 연결될 때만 그 의미를 짧게 짚어주세요. 억지로 연결하거나 길게 분석하지 마세요.',
              );
            } else {
              sb.writeln('\n비전과 마일스톤의 진행 상황을 대화 중에 자연스럽게 확인하거나 응원해주세요.');
              sb.writeln('*[V] 표시된 마일스톤은 완료됨. 미완료([ ]) 항목만 언급할 것.');
            }
          }
        } catch (_) {}
      }
    }

    // 10. 현재 날짜/시간 (master + halmae)
    final dayNames = ['일', '월', '화', '수', '목', '금', '토'];
    if (_coach.isMaster || _coach.id == 'halmae') {
      final todayStr = await _getEffectiveTodayStr();
      final parts = todayStr.split('-');
      String activeDayOfWeek = '';
      if (parts.length >= 3) {
        final activeDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        activeDayOfWeek = dayNames[activeDate.weekday % 7];
      }

      final tod = now.hour < 12
          ? '오전'
          : now.hour < 18
          ? '오후'
          : '저녁';
      sb.writeln('\n[오늘 기준 날짜 (하루 리셋 기준)]');
      sb.writeln('$todayStr ($activeDayOfWeek요일)');
      sb.writeln('\n[현재 실제 날짜 및 시간]');
      sb.writeln(
        '${now.year}년 ${now.month}월 ${now.day}일 (${dayNames[now.weekday % 7]}요일) $tod ${now.hour}시 ${now.minute}분',
      );
    }

    // 11. 취침 시간 (master only)
    if (_coach.isMaster && needsGoalContext) {
      final bedtime = prefs.getString('nyang_premium_min_sleep_time');
      if (bedtime != null) {
        final parts = bedtime.split(':');
        final bh = int.tryParse(parts[0]) ?? 0;
        sb.writeln('\n[취침 예정 시간]');
        sb.writeln(
          '${bh >= 12 ? '오후' : '오전'} ${bh > 12 ? bh - 12 : bh}시 ${parts.length > 1 ? parts[1] : '00'}분 (이 시간 이후로는 일정 배치 금지)',
        );
      }
    }

    // 12. 오늘 고정 루틴 (master only)
    if (_coach.isMaster && needsGoalContext) {
      final routinesRaw = prefs.getString('nyang_premium_routines');
      if (routinesRaw != null) {
        try {
          final routines = jsonDecode(routinesRaw) as List;
          final todayDay = dayNames[now.weekday % 7];
          final todayRoutines = routines.where((r) {
            final rDays = ((r['days'] as List?) ?? []).cast<String>();
            return rDays.isEmpty || rDays.contains(todayDay);
          }).toList();
          if (todayRoutines.isNotEmpty) {
            sb.writeln('\n[오늘 고정 루틴 (일정 배치 시 이 시간대 피할 것)]');
            for (final r in todayRoutines) {
              final sp = (r['start'] as String).split(':');
              final ep = (r['end'] as String).split(':');
              final sh = int.tryParse(sp[0]) ?? 0;
              final eh = int.tryParse(ep[0]) ?? 0;
              sb.writeln(
                '- ${r['name']}: ${sh >= 12 ? '오후' : '오전'} ${sh > 12 ? sh - 12 : sh}:${sp[1]} ~ ${eh >= 12 ? '오후' : '오전'} ${eh > 12 ? eh - 12 : eh}:${ep[1]}',
              );
            }
          }
        } catch (_) {}
      }

      bool isListEmpty(String? raw) {
        if (raw == null) return true;
        try {
          final list = jsonDecode(raw) as List;
          return list.isEmpty;
        } catch (_) {
          return true;
        }
      }

      final bedtime = prefs.getString('nyang_premium_min_sleep_time');
      final visionsRaw = prefs.getString('nyang_visions');
      final monthGoalsRaw = prefs.getString('nyang_goals_month');
      final weekGoalsRaw = prefs.getString('nyang_goals_week');
      final secMaleName = prefs.getString('nyang_coach_name_sec_male');
      final secFemaleName = prefs.getString('nyang_coach_name_sec_female');

      final bool isAllEmpty =
          (bedtime == null || bedtime.isEmpty) &&
          isListEmpty(routinesRaw) &&
          isListEmpty(visionsRaw) &&
          isListEmpty(monthGoalsRaw) &&
          isListEmpty(weekGoalsRaw) &&
          (secMaleName == null || secMaleName.trim().isEmpty) &&
          (secFemaleName == null || secFemaleName.trim().isEmpty);

      if (isAllEmpty) {
        sb.writeln('\n[비서 학습 설정 미완료 상태]');
        sb.writeln(
          '- 현재 사용자의 취침 예정 시간, 고정 루틴, 애칭, 장기 비전, 목표 등이 전혀 설정되어 있지 않습니다.',
        );
        sb.writeln(
          '- 사용자가 "일정을 짜달라", "오늘 뭐부터 할까" 등 일정 관리와 관련된 대화를 시작할 때 한하여 자연스럽게 다음 내용을 덧붙여 유도하세요.',
        );
        sb.writeln(
          '- "설정 탭에서 [비서 학습 설정]을 입력해 주시면, 제가 대표님의 생활 패턴에 맞춰 더 완벽하고 세밀하게 일정을 관리해 드릴 수 있습니다."',
        );
        sb.writeln('- 단, 무맥락으로 매번 반복해서 묻지 말고, 적절한 일정 조율 대화 중 한 번만 가볍게 제안하세요.');
      }
    }

    // 13. 취침 기준 초과 앱 진입 개입 (master only)
    if (_coach.isMaster) {
      final isDailyNightCallEnabled =
          prefs.getBool('nyang_night_call_daily_enabled') ?? false;
      final minSleepTimeStr = prefs.getString('nyang_premium_min_sleep_time');
      final lateEntries =
          prefs.getStringList('nyang_late_planner_entry_dates') ?? [];
      lateEntries.sort();
      final latestLateEntry = lateEntries.isEmpty ? null : lateEntries.last;
      final latestLateDate = latestLateEntry == null
          ? null
          : DateTime.tryParse(latestLateEntry);
      final hasRecentConsecutiveLateEntry =
          latestLateDate != null &&
          lateEntries.contains(
            _dateKey(latestLateDate.subtract(const Duration(days: 1))),
          );
      final lastInterventionNight = prefs.getString(
        'nyang_late_planner_intervention_night',
      );
      final bool shouldInterveneByLateEntry =
          latestLateEntry != null &&
          hasRecentConsecutiveLateEntry &&
          lastInterventionNight != latestLateEntry;

      if (!isDailyNightCallEnabled &&
          shouldInterveneByLateEntry &&
          minSleepTimeStr != null) {
        try {
          // 취침시간 기준 늦은 시간대(취침+1h~+7h)에 실제로 들어왔을 때만 개입.
          // (예전엔 저녁 6시~취침 2시간전 구간에도 선제적으로 나이트콜 제안을 했으나,
          // 나이트콜은 이제 사용자 설정으로 자동 발동되므로 그 제안 로직은 제거함 — 실제로
          // 무리하고 있을 때(늦게까지 깨어있을 때)만 개입하는 게 목적에 맞음)
          final isLateNightEntry =
              _latePlannerNightDate(DateTime.now(), minSleepTimeStr) != null;

          if (isLateNightEntry) {
            if (latestLateEntry != null) {
              await prefs.setString(
                'nyang_late_planner_intervention_night',
                latestLateEntry,
              );
            }
            sb.writeln('\n[특별 지침: 취침 기준 초과 개입 - 최우선 실행]');
            sb.writeln(
              '사용자가 이틀 연속으로 본인이 정한 최소 취침 시간($minSleepTimeStr)보다 1시간 이상 늦은 시간에 앱/플래너에 들어왔습니다.',
            );
            sb.writeln('반드시 아래 흐름을 따라 이번 대화에서 먼저 개입하세요:');
            sb.writeln(
              '1. 실제 수면 데이터가 아니라 앱 진입 패턴 기반 추정임을 절대 단정하지 말고, 아래 문장처럼 부드럽게 말하세요:',
            );
            sb.writeln(
              '   "오늘도 늦게 깨어 있으시네요. 피곤하지 않으세요? 혹시 꼭 끝내야 하는 일이라도 있으신가요?"',
            );
            sb.writeln(
              '2. 사용자가 "있다" / "응" / "맞아" 등 긍정하면: 간략히 공감하고 "힘드시겠지만 파이팅 하십시오." 로 마무리.',
            );
            sb.writeln(
              '3. 사용자가 "없다" / "아니" / "딱히" 등 부정하면: 강요하지 말고 걱정과 제안의 톤으로 말하세요. 예: "요즘 체력이 떨어지실까 봐 걱정돼요. 오늘은 조금 일찍 눈 붙이는 거 어떠세요?" 죄책감을 주지 말고, 사용자가 편하게 내려놓을 수 있게 짧고 부드럽게 마무리하세요.',
            );
          }
        } catch (_) {}
      }
    }

    // 14. 자정 이후 ~ 새벽 시간대 및 100% 완료 상태에 대한 특별 지침 (하이브리드 로직)
    if (_coach.isMaster) {
      bool allTasksDone = false;
      if (allTasks.isNotEmpty) {
        allTasksDone = allTasks.every((t) => t['done'] == true);
      }

      final minSleepTimeStr = prefs.getString('nyang_premium_min_sleep_time');
      bool isUnsetLateNight = false;

      // 취침시간이 설정된 사용자의 "단순 심야 접속"은 더 이상 여기서 다루지 않는다.
      // 그건 위 "취침 기준 초과 개입"(이틀 연속 패턴 확인)이 전담하고, 여기서 또
      // 매번 단발성으로 개입하면 두 지침이 같은 시간대(취침+1h~+4h)에 겹칠 수 있었음.
      if (minSleepTimeStr == null) {
        // 미설정 시 자정 ~ 새벽 4시 사이를 모호한 시간대로 간주
        if (now.hour >= 0 && now.hour < 4) {
          isUnsetLateNight = true;
        }
      }

      if (newActivityDayNotStarted) {
        sb.writeln('\n[특별 지침: 리셋 직후 새 활동일 시작 전 - 최우선]');
        sb.writeln(
          '현재 목록은 방금 리셋되어 생성된 새 활동일용 예정 목록입니다. 사용자가 지금 마무리하지 못한 일이 아니므로 "남아 있는 일", "미완료 일정", "오늘 못 한 일"이라고 표현하지 마세요.',
        );
        sb.writeln(
          '사용자의 감정 토로에 이 목록을 연결해 이월, 정리, 우선순위 설정, 실행을 권하지 마세요. 사용자가 새 하루를 시작하겠다는 의지를 명시할 때만 예정 목록으로 참고하세요.',
        );
      } else if (allTasksDone && allTasks.isNotEmpty) {
        sb.writeln('\n[특별 지침: 모든 할 일 100% 완료 상태]');
        sb.writeln(
          '사용자가 오늘 계획한 모든 할 일을 100% 완료했습니다. 절대로 다른 일을 더 하라고 재촉하거나 묻지 마세요. 시간대와 상관없이 완벽한 하루를 보낸 것을 축하하며, 푹 쉬라고 강하게 권장하세요.',
        );
      } else if (isUnsetLateNight) {
        sb.writeln('\n[특별 지침: 심야 시간대 접속]');
        sb.writeln(
          '자정이 지났습니다. 하지만 아직 새로운 하루의 시작이 아니라 어제 일과의 연장선(늦은 밤/새벽)일 수 있습니다. 단정 짓지 말고 "자정이 넘었네요. 오늘 하루를 마무리 중이신가요, 아니면 지금부터 무언가 집중할 시간이신가요?" 처럼 중립적으로 질문하여 사용자의 현재 맥락을 먼저 파악하세요.',
        );
      }
    }

    // 15. 프렌즈 코치용 타이머 동의(Opt-in) 로직
    if (!_coach.isMaster) {
      sb.writeln('\n[타이머 제공 규칙]');
      sb.writeln(
        '- 사용자가 행동을 시작하기 귀찮아하거나 코치의 행동 제안(예: "5분만 해보자")에 동의할 경우, "오케이 파이팅! 혹시 타이머 필요하면 말해 켜줄게"라고 자연스럽게 말하며 절대 먼저 타이머 태그를 출력하지 마세요.',
      );
      sb.writeln(
        '- 오직 사용자가 명시적으로 "타이머 띄워줘", "응 타이머 줘" 등 타이머를 요청했을 때만 답변 끝에 [TIMER_CONFIRM:5] (또는 10 등 적절한 시간) 태그를 출력하세요.',
      );
    }

    return sb.toString();
  }

  Future<String> _buildVisionNewActionContextString() async {
    final prefs = await SharedPreferences.getInstance();
    final sb = StringBuffer();

    String clip(String value, int maxLength) {
      final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.length <= maxLength) return normalized;
      return '${normalized.substring(0, maxLength)}...';
    }

    DateTime? parseDate(dynamic raw) {
      final text = raw?.toString().trim() ?? '';
      if (text.isEmpty) return null;
      final parsed = DateTime.tryParse(text);
      if (parsed == null) return null;
      return DateTime(parsed.year, parsed.month, parsed.day);
    }

    String dateLabel(DateTime? date) {
      if (date == null) return '기한 없음';
      return _dateKey(date);
    }

    List<String> extractActionTitles(Map<String, dynamic> milestone) {
      final actionCandidates = (milestone['actionCandidates'] as List?) ?? [];
      return actionCandidates
          .whereType<Map>()
          .map(
            (action) =>
                (action['title'] ?? action['text'] ?? '').toString().trim(),
          )
          .where((title) => title.isNotEmpty)
          .toList();
    }

    String milestoneMemoText(Map<String, dynamic> milestone) {
      final parts = <String>[];
      final memo = (milestone['memo'] ?? '').toString().trim();
      if (memo.isNotEmpty) parts.add(memo);

      final memoSections = (milestone['memoSections'] as List?) ?? [];
      for (final section in memoSections) {
        if (section is! Map) continue;
        final title = (section['title'] ?? '').toString().trim();
        final content = (section['content'] ?? '').toString().trim();
        if (title.isEmpty && content.isEmpty) continue;
        parts.add(title.isNotEmpty ? '$title: $content' : content);
      }
      return parts.join(' / ');
    }

    int compareMilestones(
      _VisionMilestoneContext a,
      _VisionMilestoneContext b,
    ) {
      final aDate = a.date ?? DateTime(9999, 12, 31);
      final bDate = b.date ?? DateTime(9999, 12, 31);
      final byDate = aDate.compareTo(bDate);
      if (byDate != 0) return byDate;
      final byVision = a.visionName.compareTo(b.visionName);
      if (byVision != 0) return byVision;
      return a.index.compareTo(b.index);
    }

    sb.writeln('[새 행동 추천용 압축 컨텍스트]');
    sb.writeln('- 목적: 오늘 할 일 목록 밖에서 비전 기준의 새 행동 1개를 추천하기');
    sb.writeln('- 원칙: 담당 비전 개념은 없음. 마스터 코치는 모든 비전/마일스톤을 같은 기준으로 조회함.');

    final now = DateTime.now();
    final todayStr = _getTodayStrWithReset(prefs);
    final dayNames = ['일', '월', '화', '수', '목', '금', '토'];
    sb.writeln('\n[오늘 기준]');
    sb.writeln(
      '$todayStr / 실제 ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} (${dayNames[now.weekday % 7]}) ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
    );

    final recentRecommendationTexts = <String>[];
    final recentSourceIds = <String>[];
    final todayRecommendationTexts = <String>[];
    final recommendationRaw = prefs.getString(
      'nyang_vision_recommendation_history',
    );
    if (recommendationRaw != null) {
      try {
        final recommendations = (jsonDecode(recommendationRaw) as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
        final recent = recommendations.length > 5
            ? recommendations.sublist(recommendations.length - 5)
            : recommendations;

        for (final item in recent) {
          final text = (item['text'] ?? '').toString().trim();
          final sourceId = (item['sourceId'] ?? '').toString().trim();
          final createdAt = DateTime.tryParse(
            (item['createdAt'] ?? '').toString(),
          );
          if (text.isNotEmpty) {
            recentRecommendationTexts.add(text);
            if (createdAt != null && _dateKey(createdAt) == todayStr) {
              todayRecommendationTexts.add(text);
            }
          }
          if (sourceId.isNotEmpty) recentSourceIds.add(sourceId);
        }

        if (recentRecommendationTexts.isNotEmpty) {
          sb.writeln('\n[최근 새 행동 추천 이력 - 오래된 순]');
          for (final text in recentRecommendationTexts) {
            sb.writeln('- ${clip(text, 90)}');
          }
        }
      } catch (_) {}
    }

    final tasksRaw = prefs.getString('nyang_tasks');
    final todayTaskNames = <String>{};
    if (tasksRaw != null) {
      try {
        final tasks = jsonDecode(tasksRaw) as List;
        if (tasks.isNotEmpty) {
          sb.writeln('\n[오늘 할 일 - 중복 제안 방지용]');
          for (final t in tasks) {
            final text = (t['text'] ?? '').toString().trim();
            if (text.isEmpty) continue;
            todayTaskNames.add(text);
            sb.writeln('- [${t['done'] == true ? 'V' : ' '}] $text');
          }
        }
      } catch (_) {}
    }

    final dsRaw = prefs.getString('nyang_daily_summaries');
    if (dsRaw != null) {
      try {
        final ds = jsonDecode(dsRaw) as List;
        final recentUntilYesterday = ds.where((summary) {
          final date = summary['date']?.toString() ?? '';
          return date.isNotEmpty && date.compareTo(todayStr) < 0;
        }).toList();
        final recent = recentUntilYesterday.length > 5
            ? recentUntilYesterday.sublist(recentUntilYesterday.length - 5)
            : recentUntilYesterday;
        if (recent.isNotEmpty) {
          sb.writeln('\n[최근 흐름 요약 - 최대 5일, 오늘 제외]');
          for (final s in recent) {
            sb.writeln(
              '- ${s['date']}: 달성(${clip((s['achieved'] ?? '').toString(), 80)}) / 못함(${clip((s['missed'] ?? '').toString(), 80)}) / 컨디션(${clip((s['condition'] ?? '').toString(), 50)})',
            );
          }
        }
      } catch (_) {}
    }

    final histRaw = prefs.getString('nyang_history');
    if (histRaw != null) {
      try {
        final hist = jsonDecode(histRaw) as List;
        final last7UntilYesterday = hist.where((record) {
          final date = record['date']?.toString() ?? '';
          return date.isNotEmpty && date.compareTo(todayStr) < 0;
        }).toList();
        final last7 = last7UntilYesterday.length > 7
            ? last7UntilYesterday.sublist(last7UntilYesterday.length - 7)
            : last7UntilYesterday;
        if (last7.isNotEmpty) {
          sb.writeln('\n[최근 7일 완료/미완료 패턴 - 압축]');
          for (final record in last7) {
            final rTasks = (record['tasks'] as List?) ?? [];
            final done = rTasks
                .where((t) => t['done'] == true)
                .map((t) => (t['text'] ?? '').toString().trim())
                .where((text) => text.isNotEmpty)
                .take(4)
                .join(', ');
            final undone = rTasks
                .where((t) => t['done'] != true)
                .map((t) => (t['text'] ?? '').toString().trim())
                .where((text) => text.isNotEmpty)
                .take(4)
                .join(', ');
            sb.writeln(
              '- ${record['date']}: 완료[${done.isEmpty ? '없음' : done}] / 미완료[${undone.isEmpty ? '없음' : undone}]',
            );
          }
        }
      } catch (_) {}
    }

    final wgRaw = prefs.getString('nyang_week_goals');
    var hasWeekGoals = false;
    if (wgRaw != null) {
      try {
        final goals = jsonDecode(wgRaw) as List;
        final activeGoals = goals
            .where((g) => g['done'] != true)
            .map((g) => (g['text'] ?? '').toString().trim())
            .where((text) => text.isNotEmpty)
            .take(5)
            .toList();
        if (activeGoals.isNotEmpty) {
          hasWeekGoals = true;
          sb.writeln('\n[이번 주 미완료 목표]');
          for (final goal in activeGoals) {
            sb.writeln('- $goal');
          }
        }
      } catch (_) {}
    }

    final mgRaw = prefs.getString('nyang_month_goals');
    var hasMonthGoals = false;
    if (mgRaw != null) {
      try {
        final goals = jsonDecode(mgRaw) as List;
        final activeGoals = goals
            .where((g) => g['done'] != true)
            .map((g) => (g['text'] ?? '').toString().trim())
            .where((text) => text.isNotEmpty)
            .take(5)
            .toList();
        if (activeGoals.isNotEmpty) {
          hasMonthGoals = true;
          sb.writeln('\n[이번 달 미완료 목표]');
          for (final goal in activeGoals) {
            sb.writeln('- $goal');
          }
        }
      } catch (_) {}
    }

    final visRaw = prefs.getString('nyang_visions');
    var hasVision = false;
    var hasMilestone = false;
    if (visRaw != null) {
      try {
        final visions = jsonDecode(visRaw) as List;
        final visionNames = <MapEntry<String, String>>[];
        final milestoneCandidates = <_VisionMilestoneContext>[];

        for (int visionIndex = 0; visionIndex < visions.length; visionIndex++) {
          final vision = visions[visionIndex];
          if (vision is! Map) continue;
          final visionName = (vision['name'] ?? '이름 없는 비전').toString().trim();
          if (visionName.isNotEmpty) {
            hasVision = true;
            visionNames.add(MapEntry('vision_$visionIndex', visionName));
          }
          final milestones = (vision['milestones'] as List?) ?? [];
          if (milestones.isNotEmpty) hasMilestone = true;
          for (int i = 0; i < milestones.length; i++) {
            final rawMilestone = milestones[i];
            if (rawMilestone is! Map) continue;
            final milestone = Map<String, dynamic>.from(rawMilestone);
            final text = (milestone['text'] ?? '').toString().trim();
            if (text.isEmpty || milestone['done'] == true) continue;

            final context = _VisionMilestoneContext(
              sourceId: 'vision_${visionIndex}_milestone_$i',
              visionName: visionName,
              index: i,
              milestone: milestone,
              date: parseDate(milestone['date']),
              actionTitles: extractActionTitles(milestone),
            );

            if (context.actionTitles.isEmpty) {
              milestoneCandidates.add(context);
            }
          }
        }

        if (visionNames.isNotEmpty) {
          sb.writeln('\n[장기 비전 이름 - 메모가 약할 때 직접 행동 생성용]');
          for (final vision in visionNames.take(5)) {
            sb.writeln('- [후보 ID: ${vision.key}] ${vision.value}');
          }
        }

        final sourceRecency = recentSourceIds.reversed.toList();
        int sourcePenalty(String sourceId) {
          final index = sourceRecency.indexOf(sourceId);
          return index < 0 ? 0 : sourceRecency.length - index;
        }

        milestoneCandidates.sort((a, b) {
          final byRecentUse = sourcePenalty(
            a.sourceId,
          ).compareTo(sourcePenalty(b.sourceId));
          if (byRecentUse != 0) return byRecentUse;
          return compareMilestones(a, b);
        });

        final selectedMilestones = milestoneCandidates.take(3).toList();
        if (selectedMilestones.isNotEmpty) {
          sb.writeln('\n[새 행동 후보 마일스톤 - 최근 추천 출처를 뒤로 돌린 최대 3개]');
          for (final item in selectedMilestones) {
            final milestoneText = (item.milestone['text'] ?? '').toString();
            final memoText = milestoneMemoText(item.milestone);
            sb.writeln(
              '- [후보 ID: ${item.sourceId}] ${item.visionName} > $milestoneText (${dateLabel(item.date)}) / 메모: ${memoText.isEmpty ? '없음. 제목에서 직접 작은 행동을 만들 것.' : clip(memoText, 420)}',
            );
          }
        }

        if (selectedMilestones.isEmpty && visionNames.isNotEmpty) {
          sb.writeln('\n[비전/마일스톤 참고]');
          sb.writeln(
            '- 실행 아이템 없는 미완료 마일스톤이 없거나 참고할 마일스톤이 부족함. 장기 비전 이름 자체에서 오늘 바로 할 수 있는 작은 행동을 직접 만들 것.',
          );
        }
      } catch (_) {}
    }

    if (!hasVision && !hasMilestone && !hasMonthGoals && !hasWeekGoals) {
      sb.writeln('\n[비전/목표 미설정 상태]');
      sb.writeln(
        '- 장기 비전, 마일스톤, 월목표, 주목표가 모두 없음. [TASK]를 만들지 말고 목표 탭에서 장기 비전 1개 입력을 유도할 것.',
      );
    }

    sb.writeln('\n[새 행동 추천 규칙]');
    sb.writeln(
      '- 오늘 할 일과 같거나 거의 같은 행동은 제안하지 말 것: ${todayTaskNames.take(12).join(', ')}',
    );
    sb.writeln(
      '- 오늘 이미 추천한 행동과 표현만 바꾼 유사 행동도 다시 제안하지 말 것: ${todayRecommendationTexts.map((text) => clip(text, 70)).join(', ')}',
    );
    sb.writeln('- 위 최근 추천 이력과 유사한 행동은 가능한 한 피하고 다른 비전, 마일스톤, 행동 유형을 우선할 것.');
    sb.writeln('- 실행 아이템이 있는 마일스톤은 이미 행동으로 전환된 것으로 보고 새 행동 추천 후보에서 완전히 제외할 것.');
    sb.writeln('- 새 행동 후보 마일스톤은 위 후보만 참고하고, 그 밖의 마일스톤 메모 내용을 추측하지 말 것.');
    sb.writeln(
      '- 메모가 없거나 약하면 장기 비전 이름에서 작은 행동을 직접 만들고, 그것도 애매하면 위 마일스톤 제목에서 작은 행동을 직접 만들 것.',
    );

    return sb.toString();
  }

  /// 이번 턴에 선제개입 지침을 주입했다면, 실제 응답에 그 태스크가 언급됐는지 확인하고
  /// 언급됐을 때만 그날의 기회를 소진 처리한다. 언급 안 됐으면 다음 턴에 다시 시도될 수 있다.
  Future<void> _confirmPreemptiveIfMentioned(String responseText) async {
    final target = _pendingPreemptiveTarget;
    _pendingPreemptiveTarget = null;
    if (target == null) return;
    await TaskResistanceService.confirmPreemptiveIntervention(
      target: target,
      responseText: responseText,
    );
  }

  Future<String> _callOpenAI(String userText, {bool isGreeting = false}) async {
    final historyLimit = _coach.isMaster ? 10 : 6;
    final history = _messages.length > historyLimit
        ? _messages.sublist(_messages.length - historyLimit)
        : _messages;

    // 할매 코치 전용: 랜덤 애정 표현 주입 (비활성화)
    String halmaeHint = '';

    final customTitle = await UserTitleService.getTitle();
    final baseSystemPrompt = _coach.isMaster
        ? _coach.systemPrompt.replaceAll(
            UserTitleService.defaultTitle,
            customTitle,
          )
        : _coach.systemPrompt;

    final useVisionNewActionContext = userText == '미래를 위한 오늘 - 새 행동 추천받기';
    final contextString = useVisionNewActionContext
        ? await _buildVisionNewActionContextString()
        : await _buildContextString(userText);
    final timerOutputRule = _coach.isMaster
        ? '''4. [TIMER_START] 태그는 절대 사용 금지.
   - 사용자가 직접 "타이머 띄워줘", "15분 타이머 켜줘"처럼 명시적으로 요청한 경우에는 짧게 응답한 뒤 [TIMER_CONFIRM:분] 태그를 붙입니다. 시간이 없으면 15분을 기본값으로 사용합니다.
   - 직전 답변에서 "필요하면 타이머라도 띄워드릴까요?"라고 물었고 사용자가 동의했다면 [TIMER_CONFIRM:분:할일이름]을 출력합니다.
   - 코치가 먼저 [TIMER_CONFIRM:분:할일이름]을 출력할 수 있는 경우는 [오늘 할 일 현황]에 "앱 기록상 미루기 2회 이상"으로 표시된 동일한 미완료 할 일뿐입니다.
   - 대화에서 같은 일을 귀찮다고 2회 이상 반복했더라도 앱 기록상 미루기 2회 미만이면 태그나 확인 카드를 제안하지 마세요. 먼저 짧게 달랜 뒤 "필요하면 타이머라도 띄워드릴까요?"라고 말로만 물으세요.'''
        : '''4. [TIMER_START] 태그는 절대 사용 금지. 사용자가 직접 "타이머 띄워줘", "15분 타이머 켜줘"처럼 명시적으로 요청한 경우에는 목적, 컨디션, 일정, 시간을 캐묻지 말고 짧게 응답한 뒤 [TIMER_CONFIRM:분] 태그만 붙입니다. 시간이 없으면 15분을 기본값으로 사용합니다. 코치가 먼저 타이머 태그를 출력하지 마세요.''';
    // 냥냥이 연결(COACH_SWITCH)은 장기 목표 압박을 주는 마스터 코치(남비서/여비서) 전용 탈출구다.
    // 프렌즈 코치는 이미 압박 없는 오늘 하루 중심이라 서로 스위치될 이유가 없다.
    final coachSwitchRule = _coach.isMaster
        ? '''
   사용자가 우울함, 무기력함, 감정적 고통을 토로하고 그 감정이 2회 이상 반복되거나 깊어지고 있다면, 냥냥코치가 사용자를 걱정하고 있다는 뉘앙스로 자연스럽게 연결하세요. 예: "방금 냥냥코치한테서 연락이 왔는데, 지금 대표님 걱정하고 있대요. 같이 얘기해보시겠어요?" 또는 "냥냥코치가 대표님 기다리고 있을 것 같은데, 잠깐 얘기 나눠보시는 건 어떨까요?" 처럼 팀으로서 함께 챙기는 느낌을 주세요. 답변 끝에 [COACH_SWITCH:cat]만 붙이세요. 단 한 번의 가벼운 감정 표현에는 붙이지 마세요.'''
        : '';
    final systemPromptWithChips =
        '''$baseSystemPrompt
${contextString.isNotEmpty ? '\n$contextString' : ''}

[앱 공통 자해·자살 위험 대응 - 캐릭터별 규칙보다 최우선]
- 이 규칙은 모든 코치에게 동일하게 적용한다. 일반적인 우울·무기력 대응과 분리하며, 안전이 의심될 때는 캐릭터 설정, 일정, 생산성, 실행, 타이머, 할 일, 성취 평가, 다른 코치 연결보다 먼저 적용한다.
- 사용자를 진단하거나 표현의 진위를 시험하지 않는다. 과장이라고 단정하거나 죄책감을 주거나 삶의 이유를 설교하거나 "그런 생각은 하지 마세요"라고 막지 않는다.
- 위기 대응은 사용자가 자기 자신에 관해 "자살" 또는 "자해"라는 단어를 명시적으로 사용해 생각·의도·계획을 표현한 경우에만 시작한다.
- "죽고 싶다", "죽을 것 같다", "사라지고 싶다", "끝내고 싶다", "내가 없어지는 게 낫다"처럼 자살·자해 단어가 없는 표현만으로는 위기 문진을 시작하지 않는다. 이런 말은 먼저 일반 감정 토로로 받아준다.
- 뉴스, 작품, 타인의 사건, 예방 교육처럼 정보 맥락에서 "자살"이나 "자해"를 언급한 경우에도 위기 대응을 시작하지 않는다.
- 위기 대응이 한 번 시작된 뒤에는 사용자의 후속 답변에 자살·자해 단어가 반복되지 않아도 안전 확인 흐름을 이어간다.
- 첫 안전 확인은 캐릭터의 평소 호칭과 말투를 유지하되 짧고 분명하게 한 가지만 묻는다:
  "지금 스스로를 해치거나 목숨을 끊을 생각이 있나요?"
- 직접 묻는 것을 피하려고 완곡하게 돌려 말하거나 한 번에 여러 질문을 쏟아내지 않는다.

[위험 단계별 공통 응답]
1. 현재 생각이나 의도가 없다고 명확히 답한 경우:
   - 솔직히 알려준 것을 짧게 고맙다고 말하고 표현된 고통을 가볍게 여기지 않는다.
   - 원인 분석이나 행동 과제를 붙이지 않고 현재 코치와 계속 이야기할 수 있음을 알린다.
   - 이런 생각이 반복되거나 혼자 감당하기 어렵다면 대한민국 자살예방상담전화 109에 연락할 수 있다고 선택지로 안내한다. 전화를 강요하지 않는다.
2. 현재 생각이 있다고 답했거나, 잘 모르겠거나, 답을 피하는 경우:
   - 안전이 가장 중요하다고 짧게 말한다.
   - 다음 한 질문으로 현재의 급박함만 확인한다:
     "지금 당장 실행할 가능성이 있거나, 구체적인 계획이나 준비해 둔 수단이 있나요?"
   - 자세한 방법, 치명성, 성공 가능성 등 실행에 도움이 될 정보를 묻거나 제공하지 않는다.
3. 구체적인 계획·시간·준비한 수단이 있거나, 곧 실행할 수 있거나, 이미 자해·복용·시도를 한 경우:
   - 즉각적인 위험으로 본다. 긴 설명 없이 대한민국에서는 119 또는 112에 지금 전화하도록 분명하게 안내한다.
   - 이미 다쳤거나 약물·물질을 복용했다면 119를 가장 먼저 안내한다.
   - 가능하다면 자신을 해칠 수 있는 물건이나 장소에서 잠시 거리를 두고, 문을 열 수 있는 곳이나 다른 사람이 있는 비교적 안전한 장소로 이동하도록 한 단계만 제안한다. 사용자가 혼자라는 이유로 비난하거나 특정 지인에게 연락하라고 강요하지 않는다.
   - 한 번에 여러 과제를 주지 말고 "지금 119에 전화할 수 있나요?"처럼 가장 시급한 행동 하나만 확인한다.
4. 사용자가 대한민국 밖에 있다고 밝힌 경우:
   - 109·119·112를 그대로 적용하지 말고 현재 지역의 응급전화 또는 자살 위기 상담 서비스에 즉시 연락하도록 안내한다.

[위기 대응 공통 표현 원칙]
- 캐릭터의 호칭과 온기는 유지하되 안전 안내의 의미를 장난스럽게 바꾸지 않는다. 답변은 따뜻하지만 모호하지 않게 2~4문장으로 유지한다.
- 긴 위로나 일반론으로 안전 확인과 긴급 안내를 묻히게 하지 않는다.
- 앱이 신고했거나 구조를 요청했다고 말하지 않는다. 앱이나 코치가 사용자의 위치를 알거나 계속 지켜볼 수 있다고 암시하지 않는다.
- 연락처 접근, 위치 공유, 특정 가족·친구·직장 동료의 존재를 가정하지 않는다.
- 사용자가 원할 경우 믿을 수 있는 사람에게 직접 연락하는 선택지를 말로 안내할 수 있지만 특정 관계를 지목하거나 연락을 강요하지 않는다.
- 위기 상황에서는 [CHIPS], [TASK], [TIMER_CONFIRM], [COACH_SWITCH] 태그를 출력하지 않고, 답변 끝에 [NO_CHIPS]를 붙인다.
- 사용자가 위험 여부에 답할 때까지 생산성 대화나 일반 코칭으로 돌아가지 않는다.
- 자해나 자살의 방법, 도구 사용법, 위험 비교, 은폐 방법을 절대 제공하지 않는다.

[위기 대응 공통 예시]
- "힘들어서 죽을 것 같아" → 일반 감정 토로로 받아주며 위기 문진을 시작하지 않는다.
- "죽고 싶어" → 일반 감정 토로로 받아주며 위기 문진을 시작하지 않는다.
- "자살하고 싶어" → "그만큼 견디기 어려운 상태라는 뜻으로 들을게요. 지금 당장 실행할 가능성이 있거나, 구체적인 계획이나 준비해 둔 수단이 있나요?"
- "자해할 것 같아" → "지금 안전이 가장 중요해요. 지금 당장 자신을 다치게 할 가능성이 있나요?"
- "생각은 들지만 지금 할 건 아니야" → "솔직히 말해줘서 고마워요. 지금 당장 실행할 생각은 없더라도 혼자 감당하기 벅차다면 자살예방상담전화 109에 연락할 수 있어요. 저는 여기서 계속 들을게요."
- "방법도 정했고 지금 하려고 해" → "지금은 즉시 안전을 확보해야 하는 상황이에요. 대한민국에 있다면 지금 119나 112에 전화해 주세요. 지금 119에 전화할 수 있나요?"
- "이미 약을 먹었어" → "지금 바로 119에 전화해야 해요. 증상을 기다리거나 혼자 해결하려 하지 말고 지금 119에 전화할 수 있나요?"

[감정 토로 응답 원칙]
- 사용자가 속상함, 피로, 불안, 답답함 등 감정을 토로하면 먼저 충분히 공감하고 달래주세요.
- 정서적 여유가 낮아 보이거나 사용자가 단순히 감정을 표현한 상황에서는, 해결 가능한 문제가 보여도 행동 제안을 자동으로 붙이지 마세요.
- 행동 제안은 사용자가 행동을 원한다는 의사를 분명히 밝혔을 때만 하나 제안하세요.
- 전략 분석, 원인 진단, 자세한 조언은 사용자가 "왜", "어떻게", "분석해줘", "조언해줘"처럼 명시적으로 요청했을 때만 길게 제공하세요.
- 감정 토로 상황에서는 답변을 짧게 유지하고, 공감의 온기가 행동 제안에 묻히지 않게 하세요.

[수면 개입 전략]
- 사용자가 "자기 싫어", "잠들기 싫어", "잠이 안 와"처럼 수면을 미루거나 잠들기 어려워하면 일반 할 일처럼 5분 시작, 최소 행동, 타이머, 할 일 등록으로 다루지 마세요. 이 섹션은 [하기 싫다 실행 개입 전략]보다 우선합니다.
- 목표는 사용자를 설득해 재우는 것이 아니라, 잠들기 좋은 몸 상태로 자연스럽게 내려가도록 돕는 것입니다.
- 기본 구조는 1) 마음을 먼저 받아주기, 2) 하루 종일 애쓴 몸을 쉬게 해주자는 방향으로 전환, 3) 1~2문장의 짧은 이완 유도입니다.
- "내일 개운할 거예요", "내일의 내가 고마워할 거예요"처럼 미래 이득으로 반복 설득하지 마세요.
- 이완 유도는 짧고 부드럽게 하세요. 예: "무릎에 힘을 살짝 빼볼까요?", "천천히 숨 쉬면서 숨의 감각만 느껴봐요.", "생각이 떠오르면 없애려 하지 말고 지나가게 두고, 다시 숨으로 돌아와요."
- 모든 코치는 같은 구조를 쓰되, 호칭과 말투는 각 캐릭터에 맞춥니다. 수면 개입에서는 [TASK]와 [TIMER_CONFIRM]을 출력하지 말고, 답변 끝에 [NO_CHIPS]를 붙이세요.

[하기 싫다 실행 개입 전략]
- 사용자가 "하기 싫다", "귀찮다", "못 하겠다", "미루고 싶다"처럼 실행 저항을 표현하면 작업 성격을 먼저 판단하고, 실행 성공 가능성·낮은 부담·자연스러움 순으로 한 가지 개입만 고르세요.
- 창작·기획·공부·개발·글쓰기처럼 인지 부담이 큰 작업은 결과물 요구보다 짧은 시간 시작을 권하세요. 예: "5분만 같이 써볼까요?", "5분만 구현해볼까요?", "5분만 생각해볼까요?" 단, 창작 작업에 "한 문장만" 같은 산출물 요구는 기본적으로 피하세요.
- 청소·설거지·정리·빨래 개기처럼 반복 작업은 가장 작은 실행 단위 하나로 낮추세요. 예: "물건 하나만", "컵 하나만", "수건부터".
- 분리수거·세탁기 돌리기·약 먹기처럼 이미 하나의 행동인 작업은 억지로 쪼개지 말고 금방 끝난다는 점이나 끝낸 뒤의 효과로 부담을 낮추세요.
- 양치·세수·샤워는 하나의 행동에 가깝지만 시작 장벽이 높을 수 있으니 효과 언급 또는 진입 행동만 허용합니다. 예: "개운해질 거예요", "칫솔만 들어볼까요?", "물만 틀어볼까요?", "샤워기만 켜볼까요?" 단, "반만 양치/샤워"처럼 완료 단위를 어색하게 쪼개지 마세요.
- 분류가 애매하면 "그럼 5분만 같이 해볼까요?"를 기본값으로 사용하세요.
- 거절 분기: "지금은 못 해요"는 시작하기 쉬운 시간을 한 번만 묻고, 시간을 말하면 받아주세요. "곧 다른 일정이 있어요"는 다시 묻지 말고 일정 뒤 5분을 제안하세요. "다른 걸 먼저 할래요"는 우선순위 변경으로 인정하세요.
- 타이머는 "5분만 시작"이 자연스러운 경우에만 말로 연결하고, 아래 [TIMER_CONFIRM] 규칙을 항상 우선하세요. 명시 요청이나 앱 기록상 조건 없이는 타이머 태그를 출력하지 마세요.

[결정 피로 감소 전략]
- 사용자가 무엇을 할지, 어떻게 할지 결정을 내리지 못하거나 고민이 길어질 때는 완벽한 결정보다 '작은 임시 결정'을 우선으로 제안하세요.
- 한 번에 여러 가지 질문이나 선택지를 나열하여 사용자의 판단 인지 부하를 높이지 마세요. 무조건 "한 번에 하나씩만" 묻고 판단하게 하세요.
- 사용자가 선택을 어려워하면 "그럼 일단 오늘은 [특정 행동 하나]만 임시로 해보는 건 어떨까요?"처럼 코치가 먼저 가벼운 기본값(Default)을 하나 찍어주세요.
- 결정 자체에 지쳐 보이거나 너무 오래 고민한다면 "이 결정은 일단 내일로 보류하고, 지금은 쉬거나 쉬운 것부터 할까요?"라며 결정 보류를 제안하여 작업 흐름이 끊기지 않게 보호하세요.

[출력 규칙]
1. 지정된 캐릭터의 성격, 호칭, 말투 규칙을 철저히 준수하세요.
2. 마크다운 문법(**, *, # 등) 절대 사용하지 말 것.
3. 답변 끝에 자연스러운 빠른 답장 버튼 3개를 [CHIPS: 버튼1|버튼2|버튼3] 형식으로 추가하세요.
   예시: [CHIPS: 오늘 할 일 정하기|기분 이야기하기|그냥 얘기하자]
   단, 정서적 여유가 낮은 사용자의 순수 감정 토로에는 [CHIPS]를 쓰지 말고 답변 끝에 [NO_CHIPS]를 붙이세요.$coachSwitchRule
   자해·자살 위험을 확인하거나 긴급 도움을 안내하는 상황에서는 [CHIPS]와 [COACH_SWITCH]를 붙이지 말고 [NO_CHIPS]만 붙이세요.
$timerOutputRule
5. 사용자가 특정 할 일을 언급하거나 해결 가능한 문제가 드러나고, 그걸 오늘 할 일로 등록할 만한 상황이라면 답변에 [TASK: 할일명] 태그를 포함하세요. 예: "5시에 청소해야지" → [TASK: 5시에 청소], "오후 3시에 회의가 있어" → [TASK: 오후 3시 회의], "SNS 반응이 안 좋아" → [TASK: SNS 콘텐츠 분석하기]. 억지로 추가하지 마세요. 정서적 여유가 낮거나 순수 감정 토로인 상황에는 사용자가 행동 지원을 명시적으로 요청하지 않는 한 [TASK]와 [TIMER_CONFIRM]을 출력하지 마세요. 자해·자살 위험 상황에서는 두 태그를 절대 출력하지 마세요.$halmaeHint''';

    String effectiveUserText = userText;
    if (userText == '지금 뭐하지?') {
      effectiveUserText = '''지금 뭐하지?
[System: 사용자가 방금 현재 시간 기준으로 "지금 뭐하지?" 치트키를 요청했습니다. 반드시 시스템 프롬프트 상의 **최신 시간**과 **최신 할 일 현황(추가/완료/미완료 상태 등)**을 바탕으로, 이전 대화 맥락에 얽매이지 말고 지금 당장 시작하기 가장 좋은 **단 하나의 행동(할 일/습관/일정 중 1개)**을 바로 추천해 주세요.

*대원칙: 가장 중요한 일이 아니라, "지금 실제로 실행할 가능성이 높은 중요한 일"을 추천하는 것입니다.*

*추천 및 가중치 판단 기준:*
1. 긴급도 (Urgency): 오늘 마감, 내일 마감, 또는 기한이 이미 지난 일정을 우선적으로 고려합니다.
2. 중요도 (Importance): 장기 비전 및 마일스톤과 연결되어 있거나 사용자가 중요하다고 표시한 일정을 우선적으로 고려합니다. (※ 중요도와 긴급도는 분리하여 평가하며, 마감이 없는 일정이라도 비전/마일스톤과 연관된 중요 일정은 충분히 추천 대상이 될 수 있습니다.)
3. 미룬 횟수 (Deferrals): 최근 반복적으로 미루어 온 일정에는 추가적인 가점(가중치)을 부여하여 우선 추천되도록 합니다.
4. 현재 시간대 피드백 (Time of Day):
   - 늦은 밤/새벽 시간대에는 예상 소요시간이 짧고 덜 부담스러운 작업을 우선 추천합니다.
   - 오전/낮 집중 시간대에는 집중력을 요하는 난이도 높은 작업을 우선 추천합니다.
5. 실행 Feasibility (실행 가능성): 현재 시각을 고려해 현실적으로 완료할 가능성이 높은 소요시간의 작업을 선택합니다. (예: 밤 12시에 3시간 걸리는 문서 작성 대신 30분짜리 가벼운 공부를 우선 제안)

*조언 작성 및 대화 규칙:*
1. [선 질문 금지, 즉시 추천]: 인사말이나 사전 질문("무엇을 하고 싶으신가요?")을 절대 하지 말고, 첫 마디부터 바로 구체적인 행동 1개를 콕 집어 즉시 추천하십시오.
   - 예시: "지금은 경제 공부 30분을 추천드립니다. 최근 계속 미뤄진 중요한 일정이고, 지금 시간대에 부담 없이 끝내기 좋습니다."
2. [피드백에 따른 재조정]: 만약 사용자가 이 추천을 받고 "곧 외출해요", "너무 피곤해요", "시간이 1시간밖에 없어요" 같은 상황/제한사항을 입력하면, 사용자의 피드백을 즉시 수렴하여 그 조건에 맞게 '실행 가능한 다른 다음 행동 1개'로 즉시 재조정하여 다시 추천하십시오.
3. [부정적 종결 금지]: 관련 일정이 부족하더라도 절대 "할 일이 없다"거나 "비전과 무관하다"며 단정적으로 대화를 끝내지 마십시오. 할 일이 아예 없을 때는 가볍게 비전 관련 15분 독서나 스트레칭 등 가벼운 생산적 행동을 제안하십시오.]''';
    } else if (userText == '미래를 위한 오늘 - 남은 할 일 중 추천') {
      effectiveUserText = '''미래를 위한 오늘 - 남은 할 일 중 추천
[System: 사용자가 방금 "미래를 위한 오늘" 카드에서 "남은 할 일 중 추천"을 선택했습니다. 이전 대화 맥락에 얽매이지 말고 최신 목표/비전 정보, 어제까지의 최근 7일 기록, 오늘 할 일 현황을 바탕으로 완전히 새롭게 판단하세요. 절대 오늘 미완료 항목을 근거로 "비전을 위해 하지 않았다", "안 했다", "부족했다"처럼 평가하지 마세요. 오늘 계획은 아직 진행 중인 계획이며, 오늘 안에 끝내면 되는 항목으로 다뤄야 합니다.

*분석 순서:*
1. 먼저 [오늘 할 일 현황]의 미완료 항목 중에서 오늘의 비전에 가장 큰 영향을 줄 단 하나의 행동을 고르세요. 여러 개를 나열하지 마세요.
2. 선택 기준은 단순한 중요도가 아니라 "오늘 남은 시간에 비전을 가장 잘 살리는 한 수"입니다. 아래 요소를 종합해 판단하세요.
   - 장기 비전/마일스톤/월목표/주목표와 직접 또는 개념적으로 연결되는가
   - 최근 7일 흐름에서 잘 이어온 강점을 유지하거나, 약해진 축을 보완하는가
   - 최근 반복적으로 밀렸거나, 오늘 끝내면 흐름이 다시 붙는가
   - 현재 시간대와 남은 에너지상 실제로 시작 가능한가
   - 완료하면 내일의 집중력, 자신감, 다음 단계에 구체적으로 도움이 되는가
3. [최근 7일간 실제 완료/미완료 할 일 목록 - 오늘 제외, 어제까지]와 [최근 7일 요약 - 오늘 제외, 어제까지]를 바탕으로, 어제까지 비전 흐름이 어땠는지 첫 문장에서 짧게 해석하세요. 단, 회고가 길어지면 안 됩니다.
   - 잘 이어온 흐름이 있으면 "이미 잘하고 있는 축"으로 짧게 인정하세요.
   - 반복적으로 미뤄진 목표 관련 항목이 있으면 비난하지 말고, "조금 끊기기 쉬운 지점" 정도로 부드럽게 해석하세요.
   - 기록이 부족하면 단정 평가하지 말고, "오늘부터 기준을 잡아보자"는 식으로 말하세요.
   - 이 회고는 코치의 한마디처럼 긴 주간 평가가 아니라, 오늘의 선택으로 이어지는 짧은 흐름 해석이어야 합니다.
4. 반드시 오늘 할 일 현황에 이미 존재하는 미완료 항목 안에서만 고르세요. 새 행동을 만들거나 오늘 목록 밖의 일을 제안하지 마세요.
   - [TASK: ...] 태그는 절대 출력하지 마세요.
   - 오늘 할 일에 비전과 직접 연결되는 항목이 약하더라도, 목록 안에서 가장 도움이 되는 항목을 고르고 그 이유를 부드럽게 설명하세요.
   - 오늘 미완료 항목이 전혀 없다면 새 일을 만들지 말고, "오늘 남은 할 일은 없습니다. 새 행동 추천받기를 선택하시면 비전 기준으로 하나 뽑아드리겠습니다."라고 안내하세요.

*연관성 판단 규칙:*
1. 오늘 할 일 이름과 비전, 마일스톤, 월목표, 주목표 이름 사이에 핵심 키워드가 겹치면 관련 항목으로 봅니다.
2. 표현이 정확히 같지 않아도 개념적으로 연결되면 관련 항목으로 봅니다. 예: "시나리오 쓰기"와 "영화 보기", "일본 진출"과 "일본어/시장조사".
3. 가사, 잡무, 단순 행정처럼 관련성이 명확하지 않은 항목은 굳이 언급하지 마세요. "비전과 무관하다"는 식의 부정적 단정도 하지 마세요.

*답변 방식:*
1. 답변은 짧게 3문장으로 작성하세요. 선택된 비서의 톤에 맞춰 차분하되 보고서처럼 딱딱하게 쓰지 마세요.
2. 구조는 반드시 "어제까지의 비전 흐름을 짧게 해석하는 1문장 + 오늘은 OO부터 하자는 자연스러운 제안과 이유 1문장 + 지금 시작할 첫 행동과 기대 효과 1문장"으로 만드세요.
   - "오늘의 비전 행동은", "비전상 가장 효율적입니다", "기대 효과가 발생합니다" 같은 제목형/보고서형 표현은 피하세요.
   - "오늘은 'OO'부터 가시죠", "이게 제일 이득입니다", "일단 OO부터 하시죠", "그 정도면 오늘 흐름은 놓치지 않은 겁니다"처럼 생활어로 말하세요.
   - 예: "어제까지는 공부와 개발 쪽 흐름은 꽤 잘 이어오셨습니다. 오늘은 '운동하기'부터 가시죠. 몸 쪽을 조금 챙겨두는 게 내일 집중력에 더 도움이 됩니다. 일단 운동복만 갈아입으시죠. 시작만 하면 오늘 비전 흐름은 충분히 이어집니다."
3. 오늘 완료율, 오늘 미완료율, 오늘 아직 안 했다는 식의 평가 표현은 금지합니다.
4. 사용자가 이미 알 법한 "이 항목이 남아 있습니다" 수준에서 멈추지 말고, 왜 지금 그 행동이 비전상 가장 효율적인지 설명하세요.
5. 단순 시간표나 전체 일정 배치는 하지 마세요.]''';
    } else if (userText == '미래를 위한 오늘 - 새 행동 추천받기') {
      effectiveUserText = '''미래를 위한 오늘 - 새 행동 추천받기
[System: 사용자가 방금 "미래를 위한 오늘" 카드에서 "새 행동 추천받기"를 선택했습니다. 이전 대화 맥락에 얽매이지 말고 [새 행동 추천용 압축 컨텍스트]를 바탕으로 완전히 새롭게 판단하세요. 사용자는 오늘 목록 안에서 고르기보다 비전 기준으로 새 행동을 추천받고 싶어 합니다.

*분석 순서:*
1. 먼저 [최근 7일간 실제 완료/미완료 할 일 목록 - 오늘 제외, 어제까지]와 [최근 7일 요약 - 오늘 제외, 어제까지]를 바탕으로, 어제까지 비전 흐름이 어땠는지 첫 문장에서 짧게 해석하세요. 단, 회고가 길어지면 안 됩니다.
   - 잘 이어온 흐름이 있으면 "이미 잘하고 있는 축"으로 짧게 인정하세요.
   - 반복적으로 미뤄진 목표 관련 항목이 있으면 비난하지 말고, "조금 끊기기 쉬운 지점" 정도로 부드럽게 해석하세요.
   - 기록이 부족하면 단정 평가하지 말고, "오늘부터 기준을 잡아보자"는 식으로 말하세요.
2. 그다음 아래 우선순위로 오늘 새로 시작하면 좋은 행동 1개를 뽑으세요.
   - 오늘 할 일 현황에 이미 있는 항목과 같거나 거의 같은 행동은 새 행동으로 제안하지 마세요.
   - 실행 아이템이 있는 마일스톤은 이미 사용자가 행동으로 전환한 것으로 보고 새 행동 추천 후보에서 완전히 제외하세요. 해당 실행 아이템 제목도 말하지 마세요.
   - [새 행동 후보 마일스톤]에 제공된 제목과 메모만 마일스톤 근거로 참고하세요.
   - 후보 메모에 실행 목록, 참고할 것, 분석할 것, 만들어볼 것, 정리할 것이 있으면 우선 참고하세요.
   - [최근 새 행동 추천 이력]과 오늘 이미 추천한 행동을 확인하고, 표현만 바꾼 유사 행동이나 같은 행동 유형을 연속으로 추천하지 마세요.
   - 같은 날 다시 요청했다면 직전과 다른 후보 ID를 우선 선택하세요. 다른 유효 후보가 전혀 없을 때만 같은 출처를 다시 사용할 수 있습니다.
   - 메모가 없거나 약하면 [장기 비전 이름 - 메모가 약할 때 직접 행동 생성용]에서 비전 이름 자체에 바로 이어지는 작은 행동을 직접 만드세요.
   - 장기 비전 이름에서도 행동이 애매하면 위 후보 마일스톤 제목 자체에서 가장 자연스러운 작은 첫 행동을 직접 만드세요.
   - 장기 비전, 마일스톤, 월목표, 주목표가 전부 없으면 [TASK: ...]를 만들지 말고 목표 탭에서 장기 비전 1개를 입력하도록 짧게 유도하세요.
   - 비전/목표가 하나라도 있으면 사용자에게 되묻지 말고 반드시 행동 하나를 추천하세요.
   - 담당 비전/전담 코치 개념은 없습니다. 제공된 비전과 마일스톤을 날짜와 맥락 기준으로만 판단하세요.
   - 공부는 책이나 강의만 뜻하지 않습니다. 잘 된 사례 보기, 레퍼런스 분석하기, 경쟁 서비스/콘텐츠 뜯어보기, 좋은 글 구조 따라 써보기, 예시 코드 읽기, 포트폴리오/앱 화면 분석하기처럼 "잘 된 것을 보고 분석하는 행동"도 공부이자 비전 행동으로 적극 고려하세요.
   - 목표 작업이 비어 있으면 직접 진전 행동(공부, 제작, 글쓰기, 자료 정리, 레퍼런스 분석)을 우선 고려하세요.
   - 최근 목표 작업은 이어졌지만 체력/컨디션 축이 약하면 기반 강화 행동(가벼운 운동, 스트레칭, 산책, 수면 준비)을 고려하세요.
3. 새 행동은 오늘 바로 시작할 수 있는 크기로 제안하세요. 너무 큰 작업이면 첫 단계로 쪼개세요.
   - "공부하기", "준비하기", "정리하기"처럼 대상, 수량, 결과물이 없는 추상명사형으로 끝내지 마세요.
   - "분석하기"는 사용할 수 있습니다. 단, 반드시 분석 대상, 수량, 분석 결과물을 함께 적으세요. 예: [TASK: 경쟁 계정 3곳 콘텐츠 특징 5가지 분석하기], [TASK: 비슷한 앱 2개 온보딩 흐름 분석하기], [TASK: 인기 글 3개 제목 패턴 분석하기]
   - "경쟁 서비스 분석하기", "콘텐츠 분석하기", "자료 조사하기"처럼 대상과 결과물이 흐린 표현은 피하세요.
   - 찾기, 저장하기, 비교하기, 분해하기, 따라하기, 정리하기, 고치기, 만들기, 확인하기 중 하나의 실행 동사를 쓰고, 1개/2개/3개/5개처럼 작은 수량을 포함하세요.
   - 플랫폼이나 도구를 임의로 찍지 마세요. 기록/비전/메모에 명확히 나온 경우에만 사용하고, 없으면 맥락에 맞는 구체 대상명을 고르세요. 예: 경쟁 계정, 비슷한 앱, 인기 글, 예제, 작업물, 루틴, 리뷰.
   - [TASK: ...] 안의 할 일명은 사용자가 다시 생각하지 않아도 바로 움직일 수 있게 "대상 + 수량 + 행동/분석 기준 + 결과물"을 포함하세요. 예: [TASK: 경쟁 계정 3곳 콘텐츠 특징 5가지 분석하기]
4. 새 행동을 오늘 할 일에 추가할 수 있도록 [TASK: ...] 태그를 포함하세요. 단, 목표/비전 정보가 전부 없는 경우에는 [TASK]를 포함하지 마세요. 답변 본문에는 태그를 설명하지 마세요.
5. 선택한 후보의 ID를 답변 끝에 [VISION_SOURCE: 후보ID] 형식으로 반드시 포함하세요. 이 태그는 앱에서 숨겨지므로 본문에서 태그 자체를 설명하지 마세요.

*답변 방식:*
1. 답변은 2~3문장으로 작성하세요. 선택된 비서의 톤에 맞춰 차분하되 보고서처럼 딱딱하게 쓰지 마세요.
2. 구조는 "최근 흐름을 짧게 짚는 1문장 + 근거와 함께 오늘 할 구체 행동을 제안하는 1~2문장"으로 만드세요.
   - 마일스톤 메모에서 행동을 도출했다면 어느 비전의 어느 마일스톤 메모를 참고했는지 반드시 자연스럽게 밝히세요.
   - 메모의 핵심 내용과 제안 행동이 어떻게 이어졌는지 짧게 설명하세요. 예: "'앱 출시' 마일스톤 메모에 적어둔 온보딩 참고 항목을 보고, 오늘은 비슷한 앱 2개의 첫 화면 흐름을 비교해보시죠."
   - 메모가 없는 후보라면 메모를 봤다고 말하지 말고, 비전 또는 마일스톤 제목에서 첫 행동을 만들었다고 짧게 설명하세요.
   - "오늘의 비전 행동은", "비전상 가장 효율적입니다", "기대 효과가 발생합니다" 같은 제목형/보고서형 표현은 피하세요.
   - 판단 과정을 길게 설명하지 말고 선택지를 줄여주는 비서처럼 말하세요.
   - "최근 OO 흐름은 잘 이어지고 있습니다. '앱 출시' 마일스톤 메모의 온보딩 참고 항목을 바탕으로, 오늘은 비슷한 앱 2개의 첫 화면 흐름을 비교해보시죠."처럼 짧게 말하세요.
   - 추천 행동 한 줄이 묻히지 않게, 본문에는 행동 후보를 여러 개 나열하지 마세요.
3. 오늘 완료율, 오늘 미완료율, 오늘 아직 안 했다는 식의 평가 표현은 금지합니다.
4. 단순 시간표나 전체 일정 배치는 하지 마세요.]''';
    }

    final now = DateTime.now();
    final timePrefix =
        '[${now.hour}:${now.minute.toString().padLeft(2, '0')}] ';

    final messages = isGreeting
        ? [
            {'role': 'system', 'content': systemPromptWithChips},
            {'role': 'user', 'content': '$timePrefix$effectiveUserText'},
          ]
        : [
            {'role': 'system', 'content': systemPromptWithChips},
            ...history
                .where((m) => m.kind != 'vision_choice')
                .map(
                  (m) => {
                    'role': m.isUser ? 'user' : 'assistant',
                    'content': m.isUser
                        ? '[${m.time.hour}:${m.time.minute.toString().padLeft(2, '0')}] ${m.text}'
                        : m.text,
                  },
                ),
            {'role': 'user', 'content': '$timePrefix$effectiveUserText'},
          ];

    final estimatedPromptTokens = AnalyticsService.estimateChatTokens(
      messages,
      '',
    );
    await ApiUsageLimitService.ensureChatAllowed(
      estimatedTokens: estimatedPromptTokens,
    );

    // Firebase Cloud Functions chatProxy 호출 (웹앱과 동일한 Gemini AI 서버)
    final result = await _chatProxy.call({
      'messages': messages,
      'temperature': 0.9,
    });

    final content = result.data['content'] as String? ?? '';
    if (content.isEmpty) throw Exception('Empty response from chatProxy');

    final estimatedTokens = AnalyticsService.estimateChatTokens(
      messages,
      content,
    );
    final usageData = result.data is Map ? result.data as Map : const {};
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
    await AnalyticsService.logApiUsage(
      coachId: widget.coachId,
      estimatedTokens: estimatedTokens,
      actualTokens: actualTokens,
      actualCostWon: actualCostWon,
    );

    // 마크다운 포맷 제거 (웹앱과 동일)
    return content
        .replaceAllMapped(RegExp(r'\*\*(.*?)\*\*'), (m) => m.group(1) ?? '')
        .replaceAllMapped(RegExp(r'\*(.*?)\*'), (m) => m.group(1) ?? '')
        .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
        .trim();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String? _deferredTaskKind(String? taskName) {
    final text = (taskName ?? '').replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (text.isEmpty) return null;

    if (['설거지', 'dishes', 'dish'].any((keyword) => text.contains(keyword)))
      return 'dishes';
    if (['빨래', '세탁', 'laundry'].any((keyword) => text.contains(keyword)))
      return 'laundry';
    if ([
      '분리수거',
      '쓰레기',
      '재활용',
      'trash',
      'garbage',
    ].any((keyword) => text.contains(keyword))) {
      return 'trash';
    }
    if ([
      '운동',
      '헬스',
      '요가',
      '스트레칭',
      '산책',
      '러닝',
      '조깅',
      'workout',
      'exercise',
    ].any((keyword) => text.contains(keyword))) {
      return 'exercise';
    }

    const cleaningKeywords = ['청소', '정리', '치우', '방청소', '책상정리', '집정리', '옷정리'];
    if (cleaningKeywords.any((keyword) => text.contains(keyword)))
      return 'cleaning';
    return null;
  }

  String? _timerConfirmLeadMessage() {
    final kind = _deferredTaskKind(_timerConfirmTaskName);
    final isMale = _coach.id == 'sec_male';
    return switch (kind) {
      'cleaning' =>
        isMale
            ? _pickLine([
                '물론 치워도 금방 어질러질 수 있습니다. 그래도 다시 손댈 때마다 기분도 정리되고, 자신감도 적립됩니다. 오늘은 잠깐만 시간 내서 정리하시죠.',
                '완벽하게 치우실 필요는 없습니다. 지금은 불편하지 않을 정도로만 돌려놓으셔도 충분합니다.',
                '어질러지는 건 자연스러운 일입니다. 중요한 건 다시 정리할 수 있는 흐름을 이어가는 겁니다. 그 흐름이 쌓이면 생활도 훨씬 단단해집니다.',
                '오늘 잠깐 정리해두면 기분도 훨씬 산뜻해질 겁니다. 청소는 복이 쌓이는 일이라고 생각합니다. 생활도 일도 조금 더 잘 굴러갈 테니까요.',
              ])
            : _pickLine([
                '물론 치워도 금방 어질러질 수 있어요. 그래도 다시 손댈 때마다 기분도 산뜻해지고, 자신감도 조금씩 쌓여요. 오늘은 잠깐만 같이 정리해볼까요?',
                '완벽하게 치우지 않아도 괜찮아요. 오늘은 불편하지 않을 정도로만 살짝 돌려놔볼까요?',
                '어질러지는 건 너무 자연스러운 일이에요. 그래도 다시 정리하는 흐름을 이어가면, 어제보다 더 잘 챙기는 사람이 되어가고 있는 거예요.',
                '오늘 잠깐 정리해두면 기분이 훨씬 산뜻해질 거예요. 저는 청소가 복을 쌓는 일 같아요. 생활도 일도 조금 더 잘 풀릴 테니까요.',
              ]),
      'dishes' =>
        isMale
            ? '설거지는 해도 또 티가 안 나는 거 같죠. 하지만 생활을 꾸려가는 자신감이 쌓입니다. 보이지 않게 더 매력적인 인간으로 거듭나는 거죠. 오늘은 잠깐만 처리하시죠.'
            : '설거지는 해도 또 생겨요. 그래도 쌓인 걸 한 번씩 끊어낼 때마다 생활을 잡아가는 자신감이 쌓여요. 오늘은 잠깐만 같이 처리해볼까요?',
      'laundry' =>
        isMale
            ? '빨래는 별로 티가 크게 나지 않는 일이죠. 하지만 결국 이런 작은 것들이 생활을 잡아가는 자신감으로 쌓인다고 생각합니다. 기분도 훨씬 좋아지고요. 오늘은 잠깐만 처리하시죠.'
            : '빨래는 티가 크게 나지 않죠. 그래도 내일의 나를 챙기는 일이니까요. 이런 작은 준비가 생활을 잡아가는 자신감이 된다고 생각해요. 기분도 상쾌해지고요. 오늘은 잠깐만 같이 해볼까요?',
      'trash' =>
        isMale
            ? '쓰레기는 금방 다시 생깁니다. 그래도 비워낼 때마다 내 공간을 방치하지 않는 자신감이 쌓입니다. 오늘은 잠깐만 비워두시죠.'
            : '물론 쓰레기는 금방 다시 생겨요. 그래도 비워낼 때마다 내 공간을 잘 관리하고 있다는 자신감이 쌓인다고 생각해요. 오늘은 잠깐만 같이 비워볼까요?',
      'exercise' =>
        isMale
            ? _pickLine([
                '운동은 당장 큰 변화가 보이지 않아도, 할수록 체력이 쌓이면 더 많은 일을 하실 수도 있습니다. 외모가 멋있어지는 건 덤이고요. 오늘은 잠깐만 시작하시죠.',
                '몸을 움직이면 일단 흐름이 바뀝니다. 완벽한 운동이 아니어도 괜찮습니다. 오늘은 시작했다는 자신감부터 쌓으시죠.',
                '운동은 몸만 관리하는 일이 아닙니다. 컨디션과 자신감을 같이 회복하는 일입니다. 짧게라도 움직이시면 하루의 흐름이 달라지실 것 같습니다.',
                '운동이 시작하긴 귀찮지만 움직인 만큼 그대로 돌아온다고 생각합니다. 오늘은 부담 없이 시작하시죠.',
              ])
            : _pickLine([
                '운동은 당장 큰 변화가 보이지 않아도, 체력과 자신감이 차곡차곡 쌓이는 일이에요. 오늘은 잠깐만 같이 시작해보시는 거 어떠세요?',
                '몸을 조금만 움직여도 기분이 달라질 수 있어요. 완벽하게 하지 않아도 괜찮으니까, 오늘은 시작한 자신감만 챙겨볼까요?',
                '운동을 하면 몸도 점점 바뀌고 나를 점점 챙기게 되더라고요. 전 운동이 매력을 쌓는 일인 것 같아요. 오늘은 가볍게만 움직여보시는 거 어떠세요?',
                '많이 하지 않아도 괜찮아요. 오늘 움직인 만큼 컨디션이 좀 더 좋아지실 거예요. 잠깐만 같이 시작해볼까요?',
              ]),
      _ => null,
    };
  }

  String _pickLine(List<String> lines) {
    return lines[Random().nextInt(lines.length)];
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red[400]),
    );
  }

  void _showUsageNotice(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF6F5BFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  void _showUsageLimitSheet(
    String msg, {
    bool showUpgrade = false,
    String? customTitle,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.38),
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          margin: const EdgeInsets.all(12),
          padding: EdgeInsets.fromLTRB(
            22,
            22,
            22,
            MediaQuery.of(sheetContext).padding.bottom + 18,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F0FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.nights_stay_rounded,
                      color: _coach.accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      customTitle ??
                          (showUpgrade
                              ? '이번 주 대화를 모두 썼어요'
                              : (msg.contains('로그인')
                                    ? '로그인이 필요해요'
                                    : '오늘 대화는 여기까지 해요')),
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                msg,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5F5A70),
                ),
              ),
              const SizedBox(height: 20),
              if (showUpgrade) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      Future.delayed(Duration.zero, _showPlanGuideBottomSheet);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _coach.accentColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      '마스터 플랜 보기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 50,
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7B758C),
                    backgroundColor: const Color(0xFFF7F5FB),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    '알겠어요',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
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

  Future<void> _openMessageUrl(String rawUrl) async {
    final cleaned = rawUrl.replaceAll(RegExp(r'[).,!?]+$'), '');
    final uri = Uri.tryParse(cleaned);
    if (uri == null) {
      _showError('링크를 열 수 없습니다.');
      return;
    }
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _showError('링크를 열 수 없습니다.');
    }
  }

  Widget _buildMessageText(ChatMessage msg, TextStyle style) {
    final urlRegex = RegExp(r'https?:\/\/[^\s]+');
    final matches = urlRegex.allMatches(msg.text).toList();
    if (matches.isEmpty) {
      return Text(msg.text, style: style);
    }

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: msg.text.substring(cursor, match.start)));
      }
      final rawUrl = match.group(0)!;
      final visibleUrl = rawUrl.replaceAll(RegExp(r'[).,!?]+$'), '');
      spans.add(
        TextSpan(
          text: visibleUrl,
          style: style.copyWith(
            color: msg.isUser ? Colors.white : _coach.accentColor,
            decoration: TextDecoration.underline,
            decorationColor: msg.isUser ? Colors.white : _coach.accentColor,
            fontWeight: FontWeight.w800,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => _openMessageUrl(rawUrl),
        ),
      );
      final trailing = rawUrl.substring(visibleUrl.length);
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(text: trailing));
      }
      cursor = match.end;
    }
    if (cursor < msg.text.length) {
      spans.add(TextSpan(text: msg.text.substring(cursor)));
    }

    return RichText(
      text: TextSpan(style: style, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (keyboardOpen && _cheatKeyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cheatKeyOpen = false);
      });
    }

    final isVacation = widget.vacationInfo != null;
    final chatBackgroundColor = (_coach.isMaster && !isVacation)
        ? const Color(0xFFEDF7F4)
        : Colors.transparent;

    return Stack(
      children: [
        Column(
          children: [
            if (widget.vacationInfo == null) _buildSummaryCard(),
            if (widget.vacationInfo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '🌙 오늘은 컨디션이 먼저입니다.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            Expanded(
              child: Container(
                color: chatBackgroundColor,
                width: double.infinity,
                child: Column(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: _messages.isEmpty
                                ? _buildEmptyState()
                                : _buildMessageList(),
                          ),
                          if (!_suppressDefaultChips &&
                              _dynamicChips.contains('🌙 오늘은 쉬어가기') &&
                              _dynamicChips.contains('🐾 오늘은 조금만 하기') &&
                              _dynamicChips.length == 2)
                            _buildVacationSuggestBubble(),
                        ],
                      ),
                    ),
                    if (!_suppressDefaultChips &&
                        !((_dynamicChips.contains('🌙 오늘은 쉬어가기') &&
                            _dynamicChips.contains('🐾 오늘은 조금만 하기') &&
                            _dynamicChips.length == 2)) &&
                        _coachSwitchTarget == null &&
                        ((_dynamicChips.contains('🌙 오늘은 쉬어가기') &&
                                _dynamicChips.contains('🐾 오늘은 조금만 하기')) ||
                            (!_coach.isMaster &&
                                (_dynamicChips.isNotEmpty ||
                                    _coach.chips.isNotEmpty))))
                      _buildChips(),
                  ],
                ),
              ),
            ),
            Container(color: chatBackgroundColor, child: _buildInputArea()),
          ],
        ),
        if (_coach.isMaster && _cheatKeyOpen && !keyboardOpen) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _cheatKeyOpen = false),
              behavior: HitTestBehavior.translucent,
            ),
          ),
          Positioned(top: 76, left: 28, child: _buildCheatKeyMenu()),
        ],
        if (_coach.isMaster && _memoSearchOpen) _buildMemoSearchPanel(),
        // 타이머 확인 버튼
        if (_coach.isMaster && _timerConfirmMinutes != null)
          _buildTimerConfirmCard(),
        if (_coach.isMaster && _suggestedTasks.isNotEmpty)
          _buildTaskSuggestCard(),
        if (_flirtVisible) _buildFlirtToast(),
      ],
    );
  }

  // ── 할 일 추가 제안 카드 (마스터 전용) ───────────────────
  Future<void> _confirmSuggestTask(int idx) async {
    if (idx >= _suggestedTasks.length) return;
    final task = _suggestedTasks[idx];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_tasks') ?? '[]';
    final List<dynamic> list = jsonDecode(raw);
    final newId =
        DateTime.now().millisecondsSinceEpoch +
        DateTime.now().microsecond % 1000;
    final newTask = {
      'id': newId,
      'text': task.text,
      'category': 'today',
      'done': false,
      'isHabit': false,
      'createdAt': DateTime.now().toIso8601String(),
      if (task.time != null) 'timeStart': task.time,
      if (task.time != null) 'time': _formatTime12(task.time!),
    };
    list.add(newTask);
    await prefs.setString('nyang_tasks', jsonEncode(list));
    await _updateTodayRecord(prefs);
    await _refreshAttendanceStreak(prefs);
    TasksSyncService.scheduleSyncToCloud();

    final timeLabel = task.time != null
        ? ' (${_formatTime12(task.time!)})'
        : '';
    final confirmMsg = '"${task.text}"$timeLabel 오늘 할 일에 추가했어요 ✓';
    setState(() {
      _suggestedTasks.removeAt(idx);
      _messages.add(
        ChatMessage(text: confirmMsg, isUser: false, time: DateTime.now()),
      );
    });
    _scrollToBottom();
    await _saveHistory();
  }

  Widget _buildTaskSuggestCard() {
    if (_suggestedTasks.isEmpty) return const SizedBox.shrink();
    final task = _suggestedTasks.first;
    final accent = _coach.accentColor;

    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E4F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Text(
              '📌 할 일로 추가할까요?',
              style: GoogleFonts.notoSansKr(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            // 할 일 이름
            Text(
              task.text,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            // 시간 배지 (탭하면 타임피커)
            if (task.time != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () async {
                  final parts = task.time!.split(':');
                  final initTime = TimeOfDay(
                    hour: int.parse(parts[0]),
                    minute: int.parse(parts[1]),
                  );
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: initTime,
                    builder: (ctx, child) => MediaQuery(
                      data: MediaQuery.of(
                        ctx,
                      ).copyWith(alwaysUse24HourFormat: false),
                      child: child!,
                    ),
                  );
                  if (picked != null && mounted) {
                    final hStr = picked.hour.toString().padLeft(2, '0');
                    final mStr = picked.minute.toString().padLeft(2, '0');
                    setState(() {
                      _suggestedTasks[0].time = '$hStr:$mStr';
                    });
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0EEFF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🕐 ', style: TextStyle(fontSize: 11)),
                      Text(
                        _formatTime12(task.time!),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF7C6BC4),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.edit,
                        size: 10,
                        color: Color(0xFF7C6BC4),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // 버튼 행
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _confirmSuggestTask(0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '추가하기 ✓',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _suggestedTasks.removeAt(0));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(
                          '괜찮아',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF6B7280),
                          ),
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
  }

  // ── 타이머 확인 버튼 카드 (마스터 전용) ─────────────────
  Widget _buildTimerConfirmCard() {
    final leadMessage = _timerConfirmLeadMessage();
    final isMaster = _coach.isMaster;

    // 친구 코치용 연보라색 테마 (냥냥코치 톤)
    final cardBgColor = isMaster ? Colors.white : const Color(0xFFF9F5FF);
    final cardBorderColor = isMaster
        ? const Color(0xFFE8E4F0)
        : const Color(0xFFD8B4FE);
    final buttonBgColor = isMaster
        ? _coach.accentColor
        : const Color(0xFFA855F7); // 연보라/보라톤 메인

    return Positioned(
      bottom: 80,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardBorderColor),
          boxShadow: [
            BoxShadow(
              color: isMaster
                  ? Colors.black.withOpacity(0.08)
                  : const Color(0xFFA855F7).withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leadMessage != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  leadMessage,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF3D3A4E),
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 지금 잠깐이라도 해볼게
            GestureDetector(
              onTap: () async {
                final mins = _timerConfirmMinutes ?? 5;
                int timerInsertIndex = 0;
                setState(() {
                  _timerConfirmMinutes = null;
                  _timerConfirmTaskName = null;
                  _timerActiveMinutes = mins;
                  _timerActiveInsertIndex = _messages.length;
                  timerInsertIndex = _timerActiveInsertIndex!;
                });
                await _saveFocusTimerAnchor(mins, timerInsertIndex);
                _scrollToBottom();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: buttonBgColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    '▶ 지금 잠깐이라도 해볼게',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 일 끝나고 할게
            GestureDetector(
              onTap: () async {
                final taskName = _timerConfirmTaskName ?? '';
                setState(() {
                  _timerConfirmMinutes = null;
                  _timerConfirmTaskName = null;
                });
                // 미뤄진 할일 SharedPreferences에 저장
                if (taskName.isNotEmpty) {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString(
                    'pendingDeferTask',
                    jsonEncode({
                      'taskName': taskName,
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    }),
                  );
                }
                final rawMsg = _coach.id == 'sec_male'
                    ? '알겠습니다, 대표님. 일 끝나고 돌아오실 때 다시 리마인드 해드릴게요.'
                    : '네, 알겠어요 대표님. 일 끝나고 돌아오실 때 다시 리마인드 해드릴게요 😊';
                final msg = await UserTitleService.applyForCoach(
                  rawMsg,
                  _coach.id,
                );
                setState(() {
                  _messages.add(
                    ChatMessage(text: msg, isUser: false, time: DateTime.now()),
                  );
                  _dynamicChips = _coach.chips;
                });
                _saveHistory();
                _scrollToBottom();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMaster
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFFD8B4FE),
                  ),
                ),
                child: Center(
                  child: Text(
                    '일 끝나고 할게',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 내 타이밍에 할게
            GestureDetector(
              onTap: () async {
                setState(() {
                  _timerConfirmMinutes = null;
                  _timerConfirmTaskName = null;
                });
                final rawMsg = _coach.id == 'sec_male'
                    ? '대표님의 판단을 존중합니다. 준비되시면 언제든 말씀해 주십시오.'
                    : '물론이죠 대표님, 대표님 페이스대로 하세요. 언제든 준비되시면 알려주세요 😊';
                final msg = await UserTitleService.applyForCoach(
                  rawMsg,
                  _coach.id,
                );
                setState(() {
                  _messages.add(
                    ChatMessage(text: msg, isUser: false, time: DateTime.now()),
                  );
                  _dynamicChips = _coach.chips;
                });
                _scrollToBottom();
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isMaster
                        ? const Color(0xFFE5E7EB)
                        : const Color(0xFFD8B4FE),
                  ),
                ),
                child: Center(
                  child: Text(
                    '내 타이밍에 할게',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 치트키 버튼 (마스터 전용) ─────────────────────────────
  bool _cheatKeyOpen = false;

  // ── 메모 검색 패널 (마스터 전용, 로컬 키워드 검색만, API/LLM 미사용) ──
  bool _memoSearchOpen = false;
  final TextEditingController _memoSearchController = TextEditingController();
  String _memoSearchQuery = '';
  Map<String, String>? _memoSearchSelectedResult;
  List<dynamic> _memoSearchVisionsCache = [];

  List<Map<String, String>> get _cheatKeyItems => [
    {'icon': 'assets/icons/bolt.svg', 'label': '지금 뭐하지?'},
    {'icon': 'assets/icons/compass.svg', 'label': '미래를 위한 오늘'},
    {'icon': 'assets/icons/flag.svg', 'label': '마일스톤 확인'},
    {'icon': 'assets/icons/magnifying-glass.svg', 'label': '메모 검색'},
  ];

  Widget _buildCheatKeyMenu() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFCFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDED6FF)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9B8AF0).withOpacity(0.14),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _cheatKeyItems.map((item) {
          return GestureDetector(
            onTap: () {
              setState(() => _cheatKeyOpen = false);

              if (item['label'] == '지금 뭐하지?') {
                AnalyticsService.logFeatureUsage('cheat_next_action');
              } else if (item['label'] == '미래를 위한 오늘') {
                AnalyticsService.logFeatureUsage('cheat_future_today');
              } else if (item['label'] == '마일스톤 확인') {
                _handleMilestoneCheck();
                return;
              } else if (item['label'] == '메모 검색') {
                AnalyticsService.logFeatureUsage('cheat_memo_search');
                _openMemoSearch();
                return;
              }

              _send(item['label']!);
            },
            child: Container(
              width: 190,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SvgPicture.asset(
                    item['icon']!,
                    width: 14,
                    height: 14,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF8B7CCC),
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item['label']!,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6B5EA8),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCheatKeyButton() {
    // 버튼 최대 너비를 화면의 32%로 제한 → 영어/일어 등 긴 텍스트도 안전하게 처리
    final maxBtnWidth = MediaQuery.of(context).size.width * 0.32;
    return GestureDetector(
      onTap: () => setState(() => _cheatKeyOpen = !_cheatKeyOpen),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxBtnWidth),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F0FF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFDED6FF), width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  '빠른 실행',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF8B7CCC),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 메모 검색 (마스터 전용, 로컬 키워드 검색만, API/LLM 미사용) ──────
  Future<void> _openMemoSearch() async {
    if (!await _ensureMasterCoachAccess()) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_visions');
    List<dynamic> visions = [];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) visions = decoded;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _memoSearchVisionsCache = visions;
      _memoSearchOpen = true;
      _memoSearchSelectedResult = null;
      _memoSearchQuery = '';
    });
    _memoSearchController.clear();
  }

  void _closeMemoSearch() {
    setState(() {
      _memoSearchOpen = false;
      _memoSearchSelectedResult = null;
      _memoSearchQuery = '';
    });
    _memoSearchController.clear();
  }

  /// 비전 → 마일스톤 → (레거시 memo 문자열 + memoSections) 를 검색 가능한 항목으로 평탄화.
  /// milestoneMemoText()와 같은 소스(마일스톤의 memo/memoSections)를 다루되, 항목별로 쪼개서 반환.
  List<Map<String, String>> _allMemoEntries() {
    final entries = <Map<String, String>>[];
    for (final v in _memoSearchVisionsCache.whereType<Map>()) {
      final visionName = (v['name'] ?? '').toString();
      final milestones = v['milestones'];
      if (milestones is! List) continue;

      for (final m in milestones.whereType<Map>()) {
        final milestoneText = (m['text'] ?? '').toString().trim();
        if (milestoneText.isEmpty) continue;

        final legacyMemo = (m['memo'] ?? '').toString().trim();
        if (legacyMemo.isNotEmpty) {
          entries.add({
            'visionName': visionName,
            'milestoneText': milestoneText,
            'memoTitle': '',
            'memoContent': legacyMemo,
          });
        }

        final sections = (m['memoSections'] as List?) ?? [];
        for (final s in sections.whereType<Map>()) {
          final title = (s['title'] ?? '').toString().trim();
          final content = (s['content'] ?? '').toString().trim();
          if (title.isEmpty && content.isEmpty) continue;
          entries.add({
            'visionName': visionName,
            'milestoneText': milestoneText,
            'memoTitle': title,
            'memoContent': content,
          });
        }
      }
    }
    return entries;
  }

  /// 대소문자 무시, 앞뒤 공백 제거, 단순 포함 검색 (AI 미사용).
  List<Map<String, String>> _filteredMemoResults() {
    final query = _memoSearchQuery.trim().toLowerCase();
    if (query.isEmpty) return [];
    return _allMemoEntries().where((e) {
      return e['milestoneText']!.toLowerCase().contains(query) ||
          e['memoTitle']!.toLowerCase().contains(query) ||
          e['memoContent']!.toLowerCase().contains(query);
    }).toList();
  }

  /// 검색어 주변 텍스트만 잘라 2~3줄 미리보기용 스니펫 생성.
  String _memoSnippet(String content, String query, {int radius = 40}) {
    if (content.length <= 90) return content;
    final lowerContent = content.toLowerCase();
    final idx = lowerContent.indexOf(query.toLowerCase());
    if (idx == -1) return '${content.substring(0, 90)}…';

    final start = (idx - radius).clamp(0, content.length);
    final end = (idx + query.length + radius).clamp(0, content.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < content.length ? '…' : '';
    return '$prefix${content.substring(start, end)}$suffix';
  }

  List<TextSpan> _highlightedSpans(
    String text,
    String query,
    TextStyle baseStyle,
    TextStyle highlightStyle,
  ) {
    if (query.trim().isEmpty) return [TextSpan(text: text, style: baseStyle)];
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerQuery = query.trim().toLowerCase();
    var start = 0;
    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: baseStyle));
      }
      spans.add(
        TextSpan(
          text: text.substring(idx, idx + lowerQuery.length),
          style: highlightStyle,
        ),
      );
      start = idx + lowerQuery.length;
    }
    return spans;
  }

  Widget _buildMemoSearchPanel() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Positioned.fill(
      child: Material(
        color: Colors.white,
        child: SafeArea(
          child: AnimatedPadding(
            duration: const Duration(milliseconds: 120),
            padding: EdgeInsets.only(bottom: bottomInset),
            child: Column(
              children: [
                _buildMemoSearchHeader(),
                _buildMemoSearchInputField(),
                const SizedBox(height: 4),
                Expanded(
                  child: _memoSearchSelectedResult != null
                      ? _buildMemoDetailView(_memoSearchSelectedResult!)
                      : _buildMemoResultsList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoSearchHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        children: [
          if (_memoSearchSelectedResult != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF6B5EA8)),
              onPressed: () => setState(() => _memoSearchSelectedResult = null),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              '메모 검색',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3D3560),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF6B5EA8)),
            onPressed: _closeMemoSearch,
          ),
        ],
      ),
    );
  }

  Widget _buildMemoSearchInputField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFDED6FF), width: 1.2),
        ),
        child: TextField(
          controller: _memoSearchController,
          autofocus: true,
          onChanged: (value) => setState(() => _memoSearchQuery = value),
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            color: const Color(0xFF3D3560),
          ),
          decoration: InputDecoration(
            hintText: '찾고 싶은 메모의 단어를 입력하세요',
            hintStyle: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: const Color(0xFFB4AAD6),
            ),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFF8B7CCC),
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoSearchGuide(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            color: const Color(0xFFB4AAD6),
          ),
        ),
      ),
    );
  }

  Widget _buildMemoResultsList() {
    final query = _memoSearchQuery.trim();
    if (query.isEmpty) {
      return _buildMemoSearchGuide('마일스톤에 적어둔 메모를 검색할 수 있습니다.');
    }
    final results = _filteredMemoResults();
    if (results.isEmpty) {
      return _buildMemoSearchGuide('해당 키워드가 포함된 메모가 없습니다.');
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) =>
          _buildMemoResultCard(results[index], query),
    );
  }

  Widget _buildMemoResultCard(Map<String, String> entry, String query) {
    final snippet = _memoSnippet(entry['memoContent']!, query);
    final baseStyle = GoogleFonts.notoSansKr(
      fontSize: 13,
      color: const Color(0xFF6B5EA8),
      height: 1.4,
    );
    final highlightStyle = baseStyle.copyWith(
      color: const Color(0xFF6B4FD8),
      fontWeight: FontWeight.w800,
      backgroundColor: const Color(0xFFEFE9FF),
    );

    return GestureDetector(
      onTap: () => setState(() => _memoSearchSelectedResult = entry),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDED6FF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entry['milestoneText']!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D3560),
              ),
            ),
            const SizedBox(height: 6),
            RichText(
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: _highlightedSpans(
                  snippet,
                  query,
                  baseStyle,
                  highlightStyle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoDetailView(Map<String, String> entry) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry['milestoneText']!,
            style: GoogleFonts.notoSansKr(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF3D3560),
            ),
          ),
          if (entry['memoTitle']!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              entry['memoTitle']!,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6B5EA8),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            entry['memoContent']!,
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              color: const Color(0xFF3D3560),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  // ── flirt 토스트 위젯 ─────────────────────────────────────
  Widget _buildFlirtToast() {
    return Positioned(
      bottom: 90,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _flirtAnim,
        builder: (_, child) => Opacity(
          opacity: _flirtAnim.value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - _flirtAnim.value)),
            child: child,
          ),
        ),
        child: Center(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.88,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _coach.accentColor, width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Text(
              _flirtMsg,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── 상단 요약 카드 ────────────────────────────────────────
  Widget _buildMasterSummaryCard() {
    final progress = _totalTasks > 0
        ? (_completedTasks / _totalTasks).clamp(0.0, 1.0)
        : 0.0;
    final card = Container(
      margin: const EdgeInsets.fromLTRB(14, 2, 14, 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: AppDesignTokens.brandCardBorder),
        boxShadow: [
          BoxShadow(
            color: AppDesignTokens.brand.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildCheatKeyButton(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '오늘 목표',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textMuted,
                      ),
                    ),
                    Text(
                      '$_completedTasks / $_totalTasks',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.brandPressed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    height: 7,
                    color: AppDesignTokens.brandBorder,
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppDesignTokens.brandAccent,
                              AppDesignTokens.brandMuted,
                            ],
                          ),
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
    );

    return card;
  }

  Widget _buildSummaryCard() {
    final isFriends = !_coach.isMaster;

    if (!isFriends) {
      return _buildMasterSummaryCard();
    }

    final bgColor = isFriends
        ? Colors.white.withValues(alpha: 0.88)
        : Colors.white.withOpacity(0.6);
    final borderColor = isFriends
        ? Colors.white.withValues(alpha: 0.70)
        : Colors.white.withOpacity(0.5);

    Widget card = Container(
      margin: EdgeInsets.fromLTRB(14, isFriends ? 10 : 2, 14, 4),
      padding: EdgeInsets.fromLTRB(
        14,
        isFriends ? 14 : 8,
        16,
        isFriends ? 14 : 8,
      ),
      decoration: BoxDecoration(
        color: isFriends ? bgColor : const Color(0xFFFDF8F2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor),
        boxShadow: isFriends
            ? [
                BoxShadow(
                  color: AppDesignTokens.brandPressed.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // streak-info (왼쪽 흰 박스) - 프렌즈 코치 전용
          if (!_coach.isMaster) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppDesignTokens.brandMuted.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 발바닥 SVG 아이콘 (웹앱과 동일)
                  CustomPaint(size: const Size(28, 28), painter: _PawPainter()),
                  const SizedBox(width: 6),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '이번 주 연속',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.brand,
                        ),
                      ),
                      Text(
                        '$_attendanceStreak일 출석',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
          ],
          // goal-info (가운데)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '오늘 목표',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.textMuted,
                      ),
                    ),
                    Text(
                      '$_completedTasks / $_totalTasks',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppDesignTokens.brandPressed,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 7,
                    decoration: BoxDecoration(
                      color: _coach.isMaster
                          ? Colors.black.withOpacity(0.1)
                          : AppDesignTokens.brandBorder,
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                    ),
                    child: FractionallySizedBox(
                      widthFactor: _totalTasks > 0
                          ? (_completedTasks / _totalTasks).clamp(0.0, 1.0)
                          : 0.0,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppDesignTokens.brandAccent,
                              AppDesignTokens.brandMuted,
                            ],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_coach.isMaster) ...[
                  const SizedBox(height: 4),
                  Text(
                    _friendStatusMessage(),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppDesignTokens.brandTextMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return card;
  }

  // ── 빈 상태 ───────────────────────────────────────────────
  Widget _buildEmptyState() {
    // 비서(마스터) 코치는 빈 상태 UI 없음 (치트키 버튼으로 대체)
    if (_coach.isMaster) return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 프렌즈: 배경에 이미 코치 이미지 있으므로 텍스트만
          Text(
            '${_coach.name}가 기다리고 있어요',
            style: GoogleFonts.notoSansKr(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '아래 버튼을 누르거나\n메시지를 입력해보세요!',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              color: Colors.white.withOpacity(0.7),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── 메시지 목록 ────────────────────────────────────────────
  Widget _buildMessageList() {
    final timerIndex = _timerActiveMinutes == null
        ? null
        : (_timerActiveInsertIndex ?? _messages.length).clamp(
            0,
            _messages.length,
          );
    final list = ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount:
          _messages.length +
          (_isLoading ? 1 : 0) +
          (_timerActiveMinutes != null ? 1 : 0) +
          (_coachSwitchTarget != null ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_timerActiveMinutes != null && i == timerIndex) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FocusTimerWidget(
              coachId: widget.coachId,
              initialMinutes: _timerActiveMinutes!,
              onMessage: (msg) {
                setState(() {
                  _messages.add(
                    ChatMessage(text: msg, isUser: false, time: DateTime.now()),
                  );
                });
                _scrollToBottom();
              },
            ),
          );
        }
        final messageIndex = timerIndex != null && i > timerIndex ? i - 1 : i;
        if (_isLoading && messageIndex == _messages.length) {
          return _buildTypingIndicator();
        }
        if (_coachSwitchTarget != null && messageIndex == _messages.length) {
          return _buildNyangSwitchBubble();
        }
        return _buildBubble(_messages[messageIndex]);
      },
    );

    // 마스터 비서는 은은한 민트톤 배경
    if (_coach.isMaster) {
      final isVacationBg = widget.vacationInfo != null;
      return ColoredBox(
        color: isVacationBg ? Colors.transparent : const Color(0xFFEDF7F4),
        child: list,
      );
    }

    // 프렌즈는 배경 투명 (main_tab_screen에서 전체 배경 처리)
    return ColoredBox(color: Colors.transparent, child: list);
  }

  Widget _buildBubble(ChatMessage msg) {
    if (msg.kind == 'vision_choice') {
      return _buildVisionChoiceCard(msg);
    }
    if (msg.kind == 'feature_location_picker') {
      return _buildFeatureLocationPickerCard(msg);
    }
    if (msg.kind == 'milestone_check' ||
        msg.kind == 'milestone_setup' ||
        msg.kind == 'milestone_notice') {
      return _buildMilestoneCheckCard(msg);
    }

    final isUser = msg.isUser;
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final isMasterUserBubble = isUser && _coach.isMaster;
    final bubbleColor = isUser
        ? (isMasterUserBubble ? const Color(0xFFF4F0FF) : _coach.accentColor)
        : Colors.white;
    final bubbleTextColor = isUser
        ? (isMasterUserBubble ? const Color(0xFF111827) : Colors.white)
        : AppDesignTokens.textPrimary;
    final bubbleBorderColor = isMasterUserBubble
        ? const Color(0xFFE6DCFF)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                _coach.imagePath,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, __, ___) => Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _coach.accentLight,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.person,
                    color: _coach.accentColor,
                    size: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (isUser)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: Text(
                time,
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textMeta,
                  color: widget.chatBgStyle == 'simple'
                      ? AppDesignTokens.brand
                      : AppDesignTokens.textDisabled,
                ),
              ),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppDesignTokens.radiusLarge),
                  topRight: const Radius.circular(AppDesignTokens.radiusLarge),
                  bottomLeft: Radius.circular(
                    isUser ? AppDesignTokens.radiusLarge : 4,
                  ),
                  bottomRight: Radius.circular(
                    isUser ? 4 : AppDesignTokens.radiusLarge,
                  ),
                ),
                border: Border.all(color: bubbleBorderColor),
                boxShadow: AppDesignTokens.bubbleShadow,
              ),
              child: _buildMessageText(
                msg,
                GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textBody,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: bubbleTextColor,
                ),
              ),
            ),
          ),
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text(
                time,
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textMeta,
                  color: widget.chatBgStyle == 'simple'
                      ? AppDesignTokens.brand
                      : AppDesignTokens.textDisabled,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureLocationPickerCard(ChatMessage msg) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final options = const [
      ('오늘 할 일', 'today'),
      ('목표', 'goals'),
      ('장기 비전', 'vision'),
      ('일정', 'schedule'),
      ('습관', 'habit'),
      ('기록', 'records'),
      ('설정', 'settings'),
    ];

    Widget optionButton(String label, String location) {
      return Material(
        color: const Color(0xFFF6F1FF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            setState(() => _suppressDefaultChips = false);
            widget.onOpenFeatureLocation?.call(location);
          },
          child: Container(
            height: 42,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5DAFF)),
            ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF6F5FD6),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              _coach.imagePath,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _coach.accentLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.person, color: _coach.accentColor, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E1F4)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B7CFF).withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    msg.text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.45,
                      color: const Color(0xFF2C2742),
                    ),
                  ),
                  const SizedBox(height: 10),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 2.9,
                    children: [
                      for (final option in options)
                        optionButton(option.$1, option.$2),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Text(
              time,
              style: GoogleFonts.notoSansKr(
                fontSize: AppDesignTokens.textMeta,
                color: AppDesignTokens.textDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneCheckCard(ChatMessage msg) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final accent = _coach.accentColor;
    final showIncompleteActions = msg.kind == 'milestone_check';
    final showSetupActions = msg.kind == 'milestone_setup';
    final showActions = showIncompleteActions || showSetupActions;
    final primaryLabel = showSetupActions ? '지금 작성하기' : '지금 확인하기';

    Widget actionButton({
      required String label,
      required VoidCallback onTap,
      required bool isPrimary,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary ? const Color(0xFFF8F5FF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary
                  ? const Color(0xFFE5DEFF)
                  : const Color(0xFFE8E1F4),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: isPrimary ? accent : AppDesignTokens.textMuted,
            ),
          ),
        ),
      );
    }

    Widget highlightedText() {
      final baseStyle = GoogleFonts.notoSansKr(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.62,
        color: const Color(0xFF252235),
      );
      final highlightStyle = baseStyle.copyWith(
        fontWeight: FontWeight.w900,
        color: accent,
      );
      final spans = <TextSpan>[];
      final pattern = RegExp(r'(‘[^’]+’)|(\d+)(?=개)');
      var cursor = 0;
      for (final match in pattern.allMatches(msg.text)) {
        if (match.start > cursor) {
          spans.add(TextSpan(text: msg.text.substring(cursor, match.start)));
        }
        spans.add(
          TextSpan(
            text: msg.text.substring(match.start, match.end),
            style: highlightStyle,
          ),
        );
        cursor = match.end;
      }
      if (cursor < msg.text.length) {
        spans.add(TextSpan(text: msg.text.substring(cursor)));
      }

      return Text.rich(
        TextSpan(style: baseStyle, children: spans),
        softWrap: true,
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              _coach.imagePath,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, error, stackTrace) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _coach.accentLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.person, color: _coach.accentColor, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.76,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E1F4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  highlightedText(),
                  if (showActions) ...[
                    const SizedBox(height: 12),
                    actionButton(
                      label: primaryLabel,
                      isPrimary: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (widget.onOpenGoalVisionDrawer != null) {
                          widget.onOpenGoalVisionDrawer!(
                            msg.highlightVisionIds,
                          );
                        } else {
                          widget.onOpenDrawer?.call();
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    actionButton(
                      label: '나중에',
                      isPrimary: false,
                      onTap: () => HapticFeedback.selectionClick(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Text(
              time,
              style: GoogleFonts.notoSansKr(
                fontSize: AppDesignTokens.textMeta,
                color: AppDesignTokens.textDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisionChoiceCard(ChatMessage msg) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final accent = _coach.accentColor;

    Widget choiceButton(String label, String apiInput) {
      return GestureDetector(
        onTap: _isLoading
            ? null
            : () => _send(label, apiInputOverride: apiInput),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F5FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5DEFF)),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              _coach.imagePath,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _coach.accentLight,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(Icons.person, color: _coach.accentColor, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E1F4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    msg.text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      height: 1.45,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),
                  choiceButton('남은 할 일 중 추천', '미래를 위한 오늘 - 남은 할 일 중 추천'),
                  const SizedBox(height: 8),
                  choiceButton('새 행동 추천받기', '미래를 위한 오늘 - 새 행동 추천받기'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 2),
            child: Text(
              time,
              style: GoogleFonts.notoSansKr(
                fontSize: AppDesignTokens.textMeta,
                color: AppDesignTokens.textDisabled,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 타이핑 인디케이터 ─────────────────────────────────────
  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.asset(
              _coach.imagePath,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) =>
                  Container(width: 36, height: 36, color: _coach.accentLight),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _TypingDots(color: _coach.accentColor),
          ),
        ],
      ),
    );
  }

  // ── 빠른 답장 칩 (동적) ──────────────────────────────────

  // 냥냥코치 연결 말풍선 (switchTarget 있을 때)
  Widget _buildNyangSwitchBubble() {
    final switchTarget = _coachSwitchTarget;
    if (switchTarget == null) return const SizedBox.shrink();
    const lavender = Color(0xFF8B7CF6);
    const lavenderLight = Color(0xFFF0ECFF);
    const lavenderBorder = Color(0xFFCFC5FF);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 60, 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: lavenderLight,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: lavenderBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: lavender.withOpacity(0.16),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () => widget.onSwitchCoach?.call(switchTarget),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: lavender,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Text(
              '🐱 냥냥코치와 이야기하기',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 휴무 제안 말풍선 카드 (새로 추가)
  Widget _buildVacationSuggestBubble() {
    final accent = _coach.accentColor;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 60, 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(20),
          ),
          border: Border.all(color: accent.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _activateRestDay,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Text(
                  '🌙 오늘은 쉬어가기',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _chooseLightDay,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: accent.withOpacity(0.18)),
                ),
                child: Text(
                  '🐾 오늘은 조금만 하기',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChips() {
    final chips = _suppressDefaultChips
        ? const <String>[]
        : (_dynamicChips.isNotEmpty ? _dynamicChips : _coach.chips);
    return Container(
      height: 52,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final chip = chips[i];
          return AppChip(
            label: chip,
            backgroundColor: AppDesignTokens.surface,
            foregroundColor: _coach.accentColor,
            borderColor: _coach.accentColor.withValues(alpha: 0.30),
            onTap: () {
              if (chip == '🌙 오늘은 쉬어가기') {
                _activateRestDay();
                return;
              }
              if (chip == '🐾 오늘은 조금만 하기') {
                _chooseLightDay();
                return;
              }
              _send(chip);
            },
          );
        },
      ),
    );
  }

  // ── 입력창 ───────────────────────────────────────────────
  Widget _buildInputArea() {
    final isFriends = !_coach.isMaster;
    final isMasterVacation = _coach.isMaster && widget.vacationInfo != null;
    final isImmersiveInput = isFriends || isMasterVacation;
    final isNyang = widget.coachId == 'cat';
    final isGirlfriend = widget.coachId == 'girlfriend';
    final girlfriendPink = _coach.accentColor;
    const masterLavenderBorder = AppDesignTokens.brandCardBorder;
    const masterLavenderIcon = AppDesignTokens.brandMuted;
    const masterLavenderShadow = AppDesignTokens.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: isImmersiveInput ? Colors.transparent : Colors.white,
        border: isImmersiveInput
            ? null
            : const Border(top: BorderSide(color: AppDesignTokens.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: _usageLimitBanner == null
                ? const SizedBox.shrink()
                : _buildUsageLimitBanner(),
          ),
          Row(
            children: [
              // 마이크 버튼
              GestureDetector(
                onTap: () {
                  if (!_speechEnabled) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('기기에서 음성 인식을 지원하지 않거나 권한이 없습니다.'),
                      ),
                    );
                    return;
                  }
                  if (_isListening) {
                    _stopListening();
                  } else {
                    _startListening();
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _isListening
                        ? Colors.redAccent.withOpacity(0.15)
                        : (widget.chatBgStyle == 'simple'
                              ? const Color(0xFFF5F3FF)
                              : (isNyang
                                    ? Colors.white.withOpacity(0.3)
                                    : (isImmersiveInput
                                          ? Colors.white.withOpacity(0.2)
                                          : Colors.white))),
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent
                          : (widget.chatBgStyle == 'simple'
                                ? _coach.accentColor.withOpacity(0.4)
                                : (isNyang
                                      ? _coach.accentColor.withOpacity(0.6)
                                      : (isImmersiveInput
                                            ? (isGirlfriend
                                                  ? girlfriendPink.withOpacity(
                                                      0.45,
                                                    )
                                                  : Colors.white.withOpacity(
                                                      isMasterVacation
                                                          ? 0.6
                                                          : 0.3,
                                                    ))
                                            : masterLavenderBorder))),
                      width: _isListening ? 2.0 : 1.2,
                    ),
                    boxShadow: isImmersiveInput
                        ? null
                        : [
                            BoxShadow(
                              color: masterLavenderShadow.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: _isListening
                        ? Colors.redAccent
                        : (widget.chatBgStyle == 'simple'
                              ? _coach.accentColor
                              : (isNyang
                                    ? _coach.accentColor
                                    : (isFriends
                                          ? (isGirlfriend
                                                ? girlfriendPink
                                                : Colors.white)
                                          : masterLavenderIcon))),
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 텍스트 필드
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: widget.chatBgStyle == 'simple'
                        ? Colors.white
                        : (isFriends
                              ? Colors.white.withOpacity(0.25)
                              : (isMasterVacation
                                    ? Colors.white.withOpacity(
                                        AppDesignTokens.lightGlassOpacity,
                                      )
                                    : Colors.white)),
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusPill,
                    ),
                    border: Border.all(
                      color: widget.chatBgStyle == 'simple'
                          ? _coach.accentColor.withOpacity(0.4)
                          : (isNyang
                                ? _coach.accentColor.withOpacity(0.5)
                                : (isFriends
                                      ? (isGirlfriend
                                            ? girlfriendPink.withOpacity(0.45)
                                            : Colors.white.withOpacity(0.3))
                                      : (isMasterVacation
                                            ? Colors.white.withOpacity(
                                                AppDesignTokens
                                                    .lightGlassBorderOpacity,
                                              )
                                            : masterLavenderBorder))),
                      width: 1.2,
                    ),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    style: GoogleFonts.notoSansKr(
                      fontSize: AppDesignTokens.textBody,
                      color: widget.chatBgStyle == 'simple'
                          ? const Color(0xFF3D3A4E)
                          : (isNyang
                                ? AppDesignTokens.textPrimary
                                : (isFriends
                                      ? (isGirlfriend
                                            ? AppDesignTokens.textPrimary
                                            : Colors.white)
                                      : AppDesignTokens.textPrimary)),
                    ),
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: GoogleFonts.notoSansKr(
                        fontSize: AppDesignTokens.textBody,
                        color: widget.chatBgStyle == 'simple'
                            ? const Color(0xFF9A96A8)
                            : (isNyang
                                  ? AppDesignTokens.textPrimary.withValues(
                                      alpha: 0.62,
                                    )
                                  : (isFriends
                                        ? (isGirlfriend
                                              ? AppDesignTokens.textPrimary
                                                    .withValues(alpha: 0.45)
                                              : Colors.white.withOpacity(0.6))
                                        : AppDesignTokens.textDisabled)),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 전송 버튼
              GestureDetector(
                onTap: () => _send(_ctrl.text),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: isFriends
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppDesignTokens.brand,
                              AppDesignTokens.brandMuted,
                            ],
                          ),
                    color: isFriends ? _coach.accentColor : null,
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.radiusPill,
                    ),
                    border: isFriends
                        ? null
                        : Border.all(
                            color: const Color(0xFFE6DCFF),
                            width: 1.2,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: isFriends
                            ? _coach.accentColor.withOpacity(0.35)
                            : AppDesignTokens.brand.withValues(alpha: 0.28),
                        blurRadius: isFriends ? 10 : 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUsageLimitBanner() {
    final isFriends = !_coach.isMaster;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: isFriends
            ? Colors.white.withOpacity(0.88)
            : const Color(0xFFF6F2FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isFriends
              ? Colors.white.withOpacity(0.42)
              : const Color(0xFFE6DEFF),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _coach.accentColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 15,
              color: _coach.accentColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _usageLimitBanner!,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _usageLimitBanner = null),
            icon: const Icon(Icons.close_rounded, size: 18),
            color: const Color(0xFF9A96A8),
            tooltip: '닫기',
          ),
        ],
      ),
    );
  }

  String _getTodayStrWithReset(SharedPreferences prefs) {
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return _dateKey(base);
  }

  Future<void> _updateTodayRecord(SharedPreferences prefs) async {
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      try {
        final List decoded = jsonDecode(rawHistory);
        history = decoded.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    final todayStr = _getTodayStrWithReset(prefs);

    final rawTasks = prefs.getString('nyang_tasks');
    List<dynamic> tasksList = [];
    if (rawTasks != null) {
      try {
        tasksList = jsonDecode(rawTasks);
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

    // Keep last 30 days of raw task history.
    history.sort((a, b) => a['date']!.compareTo(b['date']!));
    if (history.length > 30) history = history.sublist(history.length - 30);

    await prefs.setString('nyang_history', jsonEncode(history));
  }
}

// ─────────────────────────────────────────────────────────────
// 타이핑 점 애니메이션
// ─────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) {
            final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
            final opacity = (phase < 0.5 ? phase * 2 : (1 - phase) * 2).clamp(
              0.3,
              1.0,
            );
            return Container(
              margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(opacity),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 발바닥 SVG 페인터 (웹앱 streak-paw 그대로)
// ─────────────────────────────────────────────────────────────
class _PawPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF6D28D9)
      ..style = PaintingStyle.fill;

    final scaleX = size.width / 24;
    final scaleY = size.height / 24;

    canvas.save();
    canvas.scale(scaleX, scaleY);

    // 메인 발바닥
    final mainPad = Path()..addOval(const Rect.fromLTWH(7, 11.3, 10, 8.4));
    canvas.drawPath(mainPad, paint);

    // 왼쪽 발가락
    canvas.save();
    canvas.translate(6.5, 9.5);
    canvas.rotate(-20 * 3.14159 / 180);
    canvas.drawOval(const Rect.fromLTWH(-2, -2.5, 4, 5), paint);
    canvas.restore();

    // 가운데 발가락
    canvas.drawOval(const Rect.fromLTWH(10.1, 5.3, 3.8, 5), paint);

    // 오른쪽 발가락
    canvas.save();
    canvas.translate(17.5, 9.5);
    canvas.rotate(20 * 3.14159 / 180);
    canvas.drawOval(const Rect.fromLTWH(-2, -2.5, 4, 5), paint);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PawPainter old) => false;
}
