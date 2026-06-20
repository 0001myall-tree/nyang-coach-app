import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'coach_config.dart';
import 'focus_timer_widget.dart';
import '../models/user_data.dart';

const _masterGold = Color(0xFFE5B94A);

// ─────────────────────────────────────────────────────────────
// 데이터 모델
// ─────────────────────────────────────────────────────────────
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime time;

  ChatMessage({required this.text, required this.isUser, required this.time});

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    text: j['text'],
    isUser: j['isUser'],
    time: DateTime.parse(j['time']),
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

  _ParsedScheduleRegistration({
    required this.title,
    required this.date,
    this.time,
  });
}

class _ParsedReply {
  final String text;
  final List<String> chips;
  final int? timerConfirmMinutes;
  final String? timerConfirmTaskName;
  final List<_SuggestedTask> suggestedTasks;
  final bool nightCallOffer;
  _ParsedReply({
    required this.text,
    required this.chips,
    this.timerConfirmMinutes,
    this.timerConfirmTaskName,
    List<_SuggestedTask>? suggestedTasks,
    this.nightCallOffer = false,
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
      'status': ['자기야, 오늘 얼마나 했어? 내가 응원해줄게.', '잘하고 있는 거지? 믿어 의심치 않아 💙'],
    },
    'girlfriend': {
      'greet': [
        '오빠!!!! 어디 갔다 왔어ㅠㅠ 보고싶었어!!!! 🩷',
        '안 그래도 자기 생각 중이었는데... 왜 이제 왔어ㅠ 💗',
        '오빠 없으니까 너무 심심했어ㅠ 이제 같이 하는 거야!',
      ],
      'status': ['오빠 오늘 얼마나 했어? 나 궁금해!! 🩷', '잘하고 있지? 오빠가 최고야!'],
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
  final dynamic vacationInfo;
  final ChatScreenController? controller;
  const ChatScreen({
    super.key,
    required this.coachId,
    this.onOpenDrawer,
    this.vacationInfo,
    this.controller,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
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
  String? _usageLimitBanner;
  bool _awaitingBroWorkoutPreference = false;

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
      final raw = prefs.getString('nyang_tasks') ?? '[]';
      final List<dynamic> list = jsonDecode(raw);

      int total = 0;
      int completed = 0;

      for (var item in list) {
        total++;
        if (item['done'] == true) {
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

  Future<void> _initAndLoad() async {
    _userData = await UserDataService.load();
    await _recordLatePlannerEntryIfNeeded();
    await _loadTaskProgress();
    final prefs = await SharedPreferences.getInstance();
    await _updateTodayRecord(prefs);
    await _refreshAttendanceStreak(prefs);
    await _loadHistoryAndGreet();
    await _checkBedtimeMoveOffer();
    _initSpeech();
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
    // 휴무일은 연속 기록을 끊지 않고 건너뜁니다.
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

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  DateTime? _latePlannerNightDate(DateTime now, String minSleepTime) {
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
      final lateThreshold = bedtime.add(const Duration(hours: 1));
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
    if (entries.contains(key)) return;

    final updated = {...entries, key}.toList()..sort();
    final trimmed = updated.length > 14
        ? updated.sublist(updated.length - 14)
        : updated;
    await prefs.setStringList('nyang_late_planner_entry_dates', trimmed);
    TasksSyncService.scheduleSyncToCloud();
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

  Future<bool> _hasMovableIncompleteTasks() async {
    final prefs = await SharedPreferences.getInstance();
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
    bool isSixMonth = false;
    String? selectedPlanId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.92,
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(
                color: Color(0xFFFFFBFF),
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildPlanGuideHeader(
                              isSixMonth: isSixMonth,
                              onChanged: (value) {
                                setSheetState(() => isSixMonth = value);
                              },
                              onClose: () => Navigator.pop(context),
                            ),
                            Transform.translate(
                              offset: const Offset(0, -104),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  18,
                                  20,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildPlanGroup(
                                      icon: '🌱',
                                      title: '프렌즈 플랜',
                                      subtitle: '냥냥 코치와 함께하는 일상 대화와 플래너',
                                      price: isSixMonth
                                          ? '29,400원'
                                          : '5,900원 / 월',
                                      originalPrice: isSixMonth
                                          ? '35,400원'
                                          : null,
                                      badge: isSixMonth ? '6개월 총액' : '매월 자동 결제',
                                      subPrice: isSixMonth ? '월 4,900원' : null,
                                      isSelected: selectedPlanId == 'friends',
                                      onTap: () {
                                        setSheetState(
                                          () => selectedPlanId = 'friends',
                                        );
                                      },
                                      features: const [
                                        ('🐱', '냥냥 코치 이용'),
                                        ('🌱', '일상 대화 및 플래너 기능'),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _buildPlanGroup(
                                      icon: '👑',
                                      title: '마스터 플랜',
                                      subtitle: '비서 코치와 목표 달성을 더 촘촘하게 관리',
                                      price: isSixMonth
                                          ? '47,400원'
                                          : '8,900원 / 월',
                                      originalPrice: isSixMonth
                                          ? '53,400원'
                                          : null,
                                      badge: isSixMonth ? '6개월 총액' : '매월 자동 결제',
                                      subPrice: isSixMonth ? '월 7,900원' : null,
                                      isSelected: selectedPlanId == 'master',
                                      onTap: () {
                                        setSheetState(
                                          () => selectedPlanId = 'master',
                                        );
                                      },
                                      features: const [
                                        ('🐱', '냥냥 코치 이용'),
                                        ('💼', '비서 코치 이용'),
                                        ('🌱', '일상 대화 및 플래너 기능'),
                                        ('⚡', '지금 뭐하지?'),
                                        ('⭐', '주간 회고 & 우선순위 추천'),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    _buildIndividualCoachGuide(),
                                    const SizedBox(height: 12),
                                    Center(
                                      child: Text(
                                        '모든 구독 플랜은 냥냥 코치를 포함합니다.',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF8B7CFF),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.95),
                        border: const Border(
                          top: BorderSide(color: Color(0xFFEDEAF8)),
                        ),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: selectedPlanId == null
                              ? null
                              : () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '결제 화면은 곧 연결할게요.',
                                        style: GoogleFonts.notoSansKr(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      behavior: SnackBarBehavior.floating,
                                      backgroundColor: const Color(0xFF1A1A2E),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFB6A4FF),
                            disabledBackgroundColor: const Color(0xFFD8CEF8),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.pets, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                selectedPlanId == null
                                    ? '플랜을 선택해주세요'
                                    : '코치들과 함께하기',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
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

  Widget _buildPlanGuideHeader({
    required bool isSixMonth,
    required ValueChanged<bool> onChanged,
    required VoidCallback onClose,
  }) {
    return SizedBox(
      height: 300,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            bottom: 48,
            child: Image.asset(
              'assets/images/subscription_plan_header.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned(
            top: 22,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Positioned(
            top: 44,
            right: 22,
            child: TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8E8A9E),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                '닫기',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 104,
            child: _buildPlanPeriodTabs(
              isSixMonth: isSixMonth,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPeriodTabs({
    required bool isSixMonth,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2ECFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildPlanPeriodTab(
              title: '월간 구독',
              subtitle: '매월 자동 결제',
              isSelected: !isSixMonth,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _buildPlanPeriodTab(
              title: '6개월 구독',
              subtitle: '한 번 결제로 더 큰 혜택',
              isSelected: isSixMonth,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanPeriodTab({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B7CFF) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isSelected ? Colors.white : const Color(0xFF5B4DB8),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: isSelected
                    ? Colors.white.withOpacity(0.85)
                    : const Color(0xFF8A7FE0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlanGroup({
    required String icon,
    required String title,
    required String subtitle,
    required String price,
    required String badge,
    required List<(String, String)> features,
    required bool isSelected,
    required VoidCallback onTap,
    String? originalPrice,
    String? subPrice,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF7F3FF)
              : Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF8B7CFF)
                : const Color(0xFFE4DDF8),
            width: isSelected ? 2.2 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF8B7CFF,
              ).withOpacity(isSelected ? 0.18 : 0.08),
              blurRadius: isSelected ? 18 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '$icon  $title',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF4D3CC8),
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Color(0xFF8B7CFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6E6794),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFCFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE8E3F8)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B7CFF),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      badge,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (originalPrice != null) ...[
                    Text(
                      '정가 $originalPrice',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFAAA3C4),
                        decoration: TextDecoration.lineThrough,
                        decorationColor: const Color(0xFFAAA3C4),
                        decorationThickness: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          price,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF4D3CC8),
                          ),
                        ),
                      ),
                      if (subPrice != null)
                        Text(
                          subPrice,
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF6E6794),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFFE8E3F8), height: 1),
                  const SizedBox(height: 12),
                  ...features.map((feature) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            feature.$1,
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              feature.$2,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2F2A44),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndividualCoachGuide() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE4DDF8), width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF2ECFF),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: Color(0xFF8B7CFF),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '개별 코치 추가 이용',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF4D3CC8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '남친, 할매, 여친, 갓생 형 코치를 1년 이용권으로 추가할 수 있어요.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6E6794),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '3,900원',
            style: GoogleFonts.notoSansKr(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF4D3CC8),
            ),
          ),
        ],
      ),
    );
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
                            Icons.pets,
                            color: Color(0xFFD8D2FF),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '냥냥코치 팀 소개',
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
                              '그래서 냥냥코치가 태어났다냥!\n\n우리는 여러분이 다시 움직일 수 있도록 함께하는 코치들이다냥.\n특히 우리 프렌즈 코치들은...',
                            ),
                            _buildAboutSpeaker(
                              'boyfriend',
                              '남친 코치',
                              '해내면 때론 애인처럼, 때론 친구처럼 마음껏 칭찬해주고',
                            ),
                            _buildAboutSpeaker(
                              'girlfriend',
                              '여친 코치',
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
                                      Icons.pets,
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
                      icon: const Icon(Icons.pets, size: 20),
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

    final rawCore = prefs.getString('nyang_core_tasks');
    List<dynamic> coreList = rawCore != null ? jsonDecode(rawCore) : [];

    final rawLogs = prefs.getString('nyang_habit_logs');
    Map<String, dynamic> habitLogs = rawLogs != null ? jsonDecode(rawLogs) : {};

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

    final hasCoreTasks = coreList.isNotEmpty;
    final hasTasks = todayTasks.isNotEmpty;
    final hasTime = incompleteTasks.any(
      (t) => t['time'] != null || t['duration'] != null,
    );

    final frequentlyDelayed = incompleteTasks.where((t) {
      final habitId = t['habitId'];
      if (habitId == null) return false;
      final logs = habitLogs[habitId.toString()] as Map<String, dynamic>? ?? {};
      int missCount = 0;
      for (int i = 1; i <= 7; i++) {
        final d = now.subtract(Duration(days: i));
        final ds = d.toIso8601String().substring(0, 10);
        if (logs[ds] == null || logs[ds]['done'] != true) missCount++;
      }
      return missCount >= 3;
    }).toList();

    final delayedNames = frequentlyDelayed
        .map((t) => "'${t['text']}'")
        .join(', ');
    final timeSlot = hour < 12
        ? '오전'
        : hour < 18
        ? '오후'
        : '저녁';
    String prompt = '';

    if (timeSlot == '오전') {
      if (!hasTasks) {
        prompt =
            '[비서 첫 인사 - 오전, 할 일 없음] 오전이고 오늘 할 일이 아직 없다. 간단히 오전 인사를 하고, 오늘 할 일부터 같이 잡아보자고 자연스럽게 제안해라. 1~2문장으로 짧게.';
      } else if (!hasCoreTasks) {
        prompt =
            '[비서 첫 인사 - 오전, 핵심 없음] 오전이고 할 일은 있지만 핵심이 아직 안 잡혀있다. 오전 인사 후 핵심부터 정하자고 단호하게 제안해라. 1~2문장으로 짧게.';
      } else if (!hasTime) {
        prompt =
            '[비서 첫 인사 - 오전, 시간 미설정] 오전이고 핵심도 있다. 지금 바로 실행하기 좋은 행동을 추천해 드릴 수 있는데 소요시간이 안 적혀있다. 인사 후 소요시간을 적어두면 더 최적의 다음 행동을 제안해 드릴 수 있다고 한 줄 언급하고 "지금 뭐하지?" 버튼을 권해라. 2문장으로 짧게.';
      } else {
        final delayedMentionAM = frequentlyDelayed.isNotEmpty
            ? ' 그리고 $delayedNames이(가) 며칠째 밀리고 있으니 오늘 "지금 뭐하지?" 치트키로 챙겨보시라고 한 줄 덧붙여라.'
            : '';
        prompt =
            '[비서 첫 인사 - 오전, 준비완료] 오전이고 핵심도 있고 시간도 설정돼있다. 짧게 인사하고 "지금 뭐하지?" 버튼을 통해 지금 바로 시작하기 좋은 행동을 추천받어 보시라고 제안해라.$delayedMentionAM 1~2문장.';
      }
    } else if (timeSlot == '오후') {
      if (!hasTasks) {
        prompt =
            '[비서 첫 인사 - 오후, 할 일 없음] 벌써 오후인데 오늘 할 일이 없다. 인사 후 지금이라도 제일 중요한 것 하나만 바로 잡자고 단호하게 제안해라. 1~2문장.';
      } else {
        final total = todayTasks.length;
        final done = completedTasks.length;
        final left = incompleteTasks.length;
        final delayedMention = frequentlyDelayed.isNotEmpty
            ? '그리고 $delayedNames이(가) 며칠째 밀리고 있다는 것도 자연스럽게 한 줄 짚고 "오늘은 어떻게 하실 생각이십니까?" 로만 끝내라. "필요한 거 있으시면" 같은 말 덧붙이지 말 것.'
            : '';
        final endingMale = frequentlyDelayed.isNotEmpty
            ? ''
            : '"잘 되고 계십니까? 필요한 거 있으시면 말씀해주세요." 로 끝내라.';
        prompt =
            '[비서 첫 인사 - 오후, 진행중] 오후다. 오늘 할 일 $total개 중 $done개 완료, $left개 남았다. 한 문장으로 진행 상황 짧게 언급하고 $endingMale $delayedMention 절대 더 이어가지 말 것.';
      }
    } else {
      final done = completedTasks.length;
      final total = todayTasks.length;
      prompt =
          '[비서 첫 인사 - 저녁] 저녁이다. 오늘 $total개 중 $done개 했다. 오늘 마무리 코멘트를 짧게 하고 내일 준비도 언급해라. 2문장.';
    }

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
      if (widget.coachId == 'cat' && !_userData.isPlanActive) {
        setState(() => _catFreeTrialStep = 2);
      }
    }

    // 마지막 방문일 업데이트
    await prefs.setString(
      'last_visit_${widget.coachId}',
      now.toIso8601String(),
    );
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

  // ── AI 응답 파싱 ([CHIPS], [TIMER_CONFIRM], [TASK: N], [NIGHT_CALL_OFFER]) ────
  _ParsedReply _parseReply(String raw) {
    final chipRegex = RegExp(r'\[CHIPS:\s*(.+?)\]');
    final timerConfirmRegex = RegExp(r'\[TIMER_CONFIRM:(\d+)(?::([^\]]+))?\]');
    final taskRegex = RegExp(r'\[TASK:\s*(.+?)\]');
    // CORE_REC 태그 파싱: [CORE_REC:{...}]
    final coreRecRegex = RegExp(r'\[CORE_REC:(\{.*?\})\]');
    List<String> chips = [];
    int? timerConfirmMinutes;
    String? timerConfirmTaskName;
    List<_SuggestedTask> suggestedTasks = [];
    bool nightCallOffer = false;
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

    // [NIGHT_CALL_OFFER] 파싱
    if (text.contains('[NIGHT_CALL_OFFER]')) {
      nightCallOffer = true;
      text = text.replaceAll('[NIGHT_CALL_OFFER]', '').trim();
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

    // 나이트콜 제안 시 전용 버튼 강제 주입
    if (nightCallOffer) {
      chips = ['🌙 나이트콜 설정하기', '아니요, 괜찮아요'];
    }

    final timerMatch = timerConfirmRegex.firstMatch(text);
    if (timerMatch != null) {
      timerConfirmMinutes = int.tryParse(timerMatch.group(1)!);
      timerConfirmTaskName = timerMatch.group(2)?.trim();
      text = text.replaceAll(timerMatch.group(0)!, '').trim();
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

    return _ParsedReply(
      text: text,
      chips: chips,
      timerConfirmMinutes: timerConfirmMinutes,
      timerConfirmTaskName: timerConfirmTaskName,
      suggestedTasks: suggestedTasks,
      nightCallOffer: nightCallOffer,
    );
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

      setState(() {
        _messages.add(
          ChatMessage(text: greetingText, isUser: false, time: DateTime.now()),
        );
        _dynamicChips = parsed.chips.isNotEmpty ? parsed.chips : _coach.chips;
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
    final suffixRegex = RegExp(r'\s*(등록해\s*줘요?|추가해\s*줘요?|등록해\s*달라|추가해\s*달라)$');
    return suffixRegex.hasMatch(cleaned);
  }

  String _cleanScheduleRegistrationInput(String input) {
    return input.trim().replaceAll(RegExp(r'[\s.。!！~〜]+$'), '');
  }

  _ParsedScheduleRegistration _parseScheduleRegistration(String input) {
    String cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(r'\s*(등록해\s*줘요?|추가해\s*줘요?|등록해\s*달라|추가해\s*달라)$');
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();

    DateTime parsedDate = DateTime.now();
    bool hasDate = false;

    int dayOfWeek(String value) {
      if (value.contains('월')) return DateTime.monday;
      if (value.contains('화')) return DateTime.tuesday;
      if (value.contains('수')) return DateTime.wednesday;
      if (value.contains('목')) return DateTime.thursday;
      if (value.contains('금')) return DateTime.friday;
      if (value.contains('토')) return DateTime.saturday;
      if (value.contains('일')) return DateTime.sunday;
      return -1;
    }

    final lastWeekdayRegex = RegExp(r'이번\s*달\s+마지막\s+([월화수목금토일])(?:요일)?');
    final lastWeekdayMatch = lastWeekdayRegex.firstMatch(cleaned);
    if (lastWeekdayMatch != null) {
      final targetWeekday = dayOfWeek(lastWeekdayMatch.group(1)!);
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
        r'(이번\s*주|다음\s*주|다다음\s*주)\s+([월화수목금토일])(?:요일)?',
      );
      final weekRelMatch = weekRelRegex.firstMatch(cleaned);
      if (weekRelMatch != null) {
        final rel = weekRelMatch.group(1)!.replaceAll(RegExp(r'\s'), '');
        final targetWeekday = dayOfWeek(weekRelMatch.group(2)!);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          var diff = targetWeekday - now.weekday;
          if (rel == '다음주') diff += 7;
          if (rel == '다다음주') diff += 14;
          parsedDate = now.add(Duration(days: diff));
          hasDate = true;
          cleaned = cleaned.replaceFirst(weekRelMatch.group(0)!, '').trim();
        }
      }
    }

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

    if (!hasDate) {
      final bareWeekdayRegex = RegExp(r'([월화수목금토일])요일');
      final bareWeekdayMatch = bareWeekdayRegex.firstMatch(cleaned);
      if (bareWeekdayMatch != null) {
        final targetWeekday = dayOfWeek(bareWeekdayMatch.group(1)!);
        if (targetWeekday != -1) {
          final now = DateTime.now();
          var diff = targetWeekday - now.weekday;
          if (diff < 0) diff += 7;
          parsedDate = now.add(Duration(days: diff));
          cleaned = cleaned.replaceFirst(bareWeekdayMatch.group(0)!, '').trim();
        }
      }
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

    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _ParsedScheduleRegistration(
      title: cleaned.isEmpty ? '새 일정' : cleaned,
      date: parsedDate,
      time: parsedTime,
    );
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
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawSchedules = prefs.getString('nyang_schedules');
    final Map<String, dynamic> schedules = rawSchedules == null
        ? {}
        : Map<String, dynamic>.from(jsonDecode(rawSchedules));
    final dateStr = _dateKey(date);
    final dayList = List<dynamic>.from(schedules[dateStr] ?? []);
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final entry = {
      'id': id,
      'text': title,
      'done': false,
      'createdAt': DateTime.now().toIso8601String(),
      'deferredCount': 0,
      'isReminderEnabled': reminderEnabled,
      if (time != null) 'timeStart': _storedTime(time),
      if (time != null) 'time': _formatTimeOfDay(time),
    };
    dayList.add(entry);
    schedules[dateStr] = dayList;
    await prefs.setString('nyang_schedules', jsonEncode(schedules));

    if (dateStr == _dateKey(DateTime.now())) {
      final rawTasks = prefs.getString('nyang_tasks') ?? '[]';
      final tasks = List<dynamic>.from(jsonDecode(rawTasks));
      tasks.add({
        ...entry,
        'id':
            DateTime.now().millisecondsSinceEpoch +
            DateTime.now().microsecond % 1000,
        'category': 'schedule',
        'isHabit': false,
      });
      await prefs.setString('nyang_tasks', jsonEncode(tasks));
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
                        if (!reminderEnabled) {
                          final enabled =
                              prefs.getBool('nyang_core_reminder_enabled') ??
                              false;
                          if (!enabled) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('설정에서 일정 알람을 먼저 켜주세요.'),
                              ),
                            );
                            return;
                          }
                        }
                        if (confirmedTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('알람을 켜려면 시간을 먼저 선택해주세요.'),
                            ),
                          );
                          return;
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

  // ── 메시지 전송 (웹앱 sendMessage 이식) ─────────────────
  Future<void> _send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    if (!_coach.isMaster && _isListening) {
      await _stopListening();
      if (!mounted) return;
    }
    _ctrl.clear();
    HapticFeedback.lightImpact();

    // ── 나이트콜 설정 버튼 인터셉트 ──────────────────────
    if (trimmed == '🌙 나이트콜 설정하기') {
      final prefs = await SharedPreferences.getInstance();
      final minSleepTimeStr = prefs.getString('nyang_premium_min_sleep_time');
      final nightCallCoach =
          prefs.getString('nyang_night_call_coach') ?? 'sec_male';

      if (minSleepTimeStr != null) {
        final parts = minSleepTimeStr.split(':');
        final bedH = int.tryParse(parts[0]) ?? 1;
        final bedM = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
        int nightCallH = bedH - 2;
        if (nightCallH < 0) nightCallH += 24;
        final displayH = _formatTime12(
          '${nightCallH.toString().padLeft(2, '0')}:${bedM.toString().padLeft(2, '0')}',
        );

        await NotificationService().scheduleNightCall(
          hour: nightCallH,
          minute: bedM,
          coachId: nightCallCoach,
        );

        setState(() {
          _messages.add(
            ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
          );
          _messages.add(
            ChatMessage(
              text:
                  '알겠습니다. 오늘 $displayH시에 나이트콜이 설정되었습니다. 남은 시간 동안 잘 마무리하시길 바랍니다.',
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

    var apiInput = trimmed;
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

    final currentId = widget.coachId;
    final userMsg = ChatMessage(
      text: trimmed,
      isUser: true,
      time: DateTime.now(),
    );
    setState(() {
      _messages.add(userMsg);
      _dynamicChips = [];
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
      return;
    }

    try {
      final raw = await _callOpenAI(apiInput);
      if (!mounted || widget.coachId != currentId) return;
      final usageNotice = await ApiUsageLimitService.takeChatUsageNotice();
      if (!mounted || widget.coachId != currentId) return;
      final parsed = _parseReply(raw);
      setState(() {
        _messages.add(
          ChatMessage(text: parsed.text, isUser: false, time: DateTime.now()),
        );
        _dynamicChips = parsed.chips.isNotEmpty ? parsed.chips : _coach.chips;
        if (_coach.isMaster) {
          _timerConfirmMinutes = parsed.timerConfirmMinutes;
          _timerConfirmTaskName = parsed.timerConfirmTaskName;
        } else {
          _timerConfirmMinutes = null;
          _timerConfirmTaskName = null;
          if (parsed.timerConfirmMinutes != null) {
            _timerActiveMinutes = parsed.timerConfirmMinutes;
          }
        }
        if (parsed.suggestedTasks.isNotEmpty) {
          _suggestedTasks = parsed.suggestedTasks;
        }
        // 배너 로직 삭제 (팝업으로 대체)
        _isLoading = false;
      });
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
    }
  }

  // ── 웹앱 buildMemoryContext() 이식 (전 코치 등급) ───────
  Future<String> _buildContextString() async {
    final tier = _coach.tier; // 'friends' | 'master'
    final prefs = await SharedPreferences.getInstance();
    final sb = StringBuffer();

    // 1. 마스터 프로필 (tier별 분기)
    final mpRaw = prefs.getString('nyang_master_profile');
    if (mpRaw != null && mpRaw != 'null') {
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
    sb.writeln('''
[코칭 개입 규칙 (매우 중요)]
1. 언어적 동기화: [사용자 고유 표현]을 문장 속에 자연스럽게 섞어 사용하세요. (주 1~2회 빈도 제한)
2. 맥락 기반 제언: [중변화]의 [관심 축]을 활용해 현재 상황의 원인을 짚어주세요.
3. 패턴 브레이킹: [저변화]의 [성공/실패 공식] 감지 시, 상황 묘사형으로 부드럽게 개입하세요.
4. 실시간 Lite 모드: 프로필을 읽기 전용으로만 참조하며, 직접 수정을 언급하지 마세요.''');

    // 2. 장기 패턴
    final ltRaw = prefs.getString('nyang_long_term');
    if (ltRaw != null) {
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
    if (dsRaw != null) {
      try {
        final ds = jsonDecode(dsRaw) as List;
        if (ds.isNotEmpty) {
          final recent = ds.length > 7 ? ds.sublist(ds.length - 7) : ds;
          sb.writeln('\n[최근 7일 요약]');
          for (final s in recent) {
            sb.writeln(
              '${s['date']}: 달성(${s['achieved']}) / 못함(${s['missed']}) / 컨디션(${s['condition']}) / 고민(${s['concern']})',
            );
          }
        }
      } catch (_) {}
    }

    // 4. 최근 7일 완료/미완료 할 일
    final histRaw = prefs.getString('nyang_history');
    if (histRaw != null) {
      try {
        final hist = jsonDecode(histRaw) as List;
        if (hist.isNotEmpty) {
          final last7 = hist.length > 7 ? hist.sublist(hist.length - 7) : hist;
          sb.writeln('\n[최근 7일간 실제 완료/미완료 할 일 목록]');
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
        }
      } catch (_) {}
    }

    // 5. 오늘 할 일 현황
    final tasksRaw = prefs.getString('nyang_tasks');
    List<dynamic> allTasks = [];
    if (tasksRaw != null) {
      try {
        allTasks = jsonDecode(tasksRaw) as List;
        if (allTasks.isNotEmpty) {
          sb.writeln('\n[오늘 할 일 현황]');
          for (final t in allTasks) {
            final done = t['done'] == true;
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
            final typeLabel = isHabit
                ? '습관'
                : isSchedule
                ? '일정'
                : '일반 할 일';
            sb.writeln(
              '- [${done ? 'V' : ' '}] [$typeLabel] ${t['text']}$timeInfo',
            );
          }
          sb.writeln('*[V] 표시된 항목은 완료됨. 완료 항목은 절대 다시 실행 유도하지 말 것.');
        }
      } catch (_) {}
    }

    // 6. 오늘의 핵심 (master only)
    if (_coach.isMaster) {
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
              sb.writeln('${i + 1}위: [${isDone ? '완료' : '미완료'}] ${c['text']}');
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
    if (_coach.isMaster) {
      final wgRaw = prefs.getString('nyang_week_goals');
      if (wgRaw != null) {
        try {
          final wg = jsonDecode(wgRaw) as List;
          if (wg.isNotEmpty) {
            sb.writeln('\n[이번 주 목표]');
            for (final g in wg)
              sb.writeln('- [${g['done'] == true ? 'V' : ' '}] ${g['text']}');
          }
        } catch (_) {}
      }
      final mgRaw = prefs.getString('nyang_month_goals');
      if (mgRaw != null) {
        try {
          final mg = jsonDecode(mgRaw) as List;
          if (mg.isNotEmpty) {
            sb.writeln('\n[이번 달 목표]');
            for (final g in mg)
              sb.writeln('- [${g['done'] == true ? 'V' : ' '}] ${g['text']}');
          }
        } catch (_) {}
      }
    }

    // 8. 장기 비전 + 마일스톤 (pro + master)
    if (_coach.isMaster) {
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
              sb.writeln(
                '- 비전명: ${v['name']} (${dl['year']}년 ${dl['month']}월 ${dl['period']}까지)',
              );
              if (v['coachId'] == _coach.id)
                sb.writeln('  (★ 이 비전은 현재 내가 전담 관리하는 목표임)');
              sb.writeln('  상태: 총 ${milestones.length}단계 중 ${doneCount}단계 완료');
              for (int i = 0; i < milestones.length; i++) {
                final m = milestones[i];
                sb.writeln(
                  '    [${m['done'] == true ? 'V' : ' '}] ${i + 1}. ${m['text']}',
                );
              }
            }
            sb.writeln('\n비전과 마일스톤의 진행 상황을 대화 중에 자연스럽게 확인하거나 응원해주세요.');
            sb.writeln('*[V] 표시된 마일스톤은 완료됨. 미완료([ ]) 항목만 언급할 것.');
          }
        } catch (_) {}
      }
    }

    // 9. 7일 이상 연속 미완료 습관 (master only)
    if (_coach.isMaster) {
      final habitsRaw = prefs.getString('nyang_habits');
      final habitLogsRaw = prefs.getString('nyang_habit_logs');
      if (habitsRaw != null && habitLogsRaw != null) {
        try {
          final habits = jsonDecode(habitsRaw) as List;
          final habitLogs = jsonDecode(habitLogsRaw) as Map<String, dynamic>;
          final dismissalsRaw =
              prefs.getString('nyang_habit_dismissals') ?? '{}';
          final dismissals = jsonDecode(dismissalsRaw) as Map<String, dynamic>;
          final todayStr = await _getEffectiveTodayStr();
          final parts = todayStr.split('-');
          DateTime baseDate;
          if (parts.length >= 3) {
            baseDate = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          } else {
            final n = DateTime.now();
            baseDate = DateTime(n.year, n.month, n.day);
          }
          final longAbsent = <Map<String, dynamic>>[];
          for (final h in habits) {
            final hId = h['id'].toString();
            final logs = (habitLogs[hId] as Map<String, dynamic>?) ?? {};
            final createdAtStr = h['createdAt'] as String?;
            DateTime? createdAtDate;
            if (createdAtStr != null) {
              final parsed = DateTime.tryParse(createdAtStr);
              if (parsed != null) {
                createdAtDate = DateTime(parsed.year, parsed.month, parsed.day);
              }
            }

            int miss = 0;
            for (int i = 1; i <= 7; i++) {
              final d = baseDate.subtract(Duration(days: i));

              if (createdAtDate != null) {
                final dDate = DateTime(d.year, d.month, d.day);
                if (dDate.isBefore(createdAtDate)) {
                  break; // Stop counting if we check dates before habit creation
                }
              }

              final ds =
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
              final log = logs[ds] as Map<String, dynamic>?;
              if (log == null || log['done'] != true)
                miss++;
              else
                break;
            }
            if (miss >= 7) {
              final di =
                  (dismissals[hId] as Map<String, dynamic>?) ?? {'count': 0};
              if ((di['count'] as int? ?? 0) >= 2) continue;
              final lastAsked = di['lastAsked'] as String?;
              if (lastAsked != null) {
                if (baseDate.difference(DateTime.parse(lastAsked)).inDays < 7)
                  continue;
              }
              longAbsent.add({'name': h['name'], 'days': miss});
            }
          }
          if (longAbsent.isNotEmpty) {
            sb.writeln('\n[7일 이상 연속 미완료 습관 - 개입 필요]');
            for (final h in longAbsent)
              sb.writeln('- "${h['name']}" (${h['days']}일 연속 미완료)');
            sb.writeln(
              '*오늘 할 일 정리가 마무리된 흐름에서 자연스럽게 한 번 꺼낸다. 먼저 이유를 물어보고 판단한다.',
            );
          }
        } catch (_) {}
      }
    }

    // 10. 현재 날짜/시간 (master + halmae)
    final now = DateTime.now();
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
    if (_coach.isMaster) {
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
    if (_coach.isMaster) {
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

    // 13. 취침 기준 초과 앱 진입 개입 (master only, 나이트콜 켠 경우)
    if (_coach.isMaster) {
      final isNightCallEnabled =
          prefs.getBool('nyang_night_call_enabled') ?? false;
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

      if (isNightCallEnabled &&
          !isDailyNightCallEnabled &&
          shouldInterveneByLateEntry &&
          minSleepTimeStr != null) {
        try {
          final parts = minSleepTimeStr.split(':');
          final bedH = int.tryParse(parts[0]) ?? 1;
          final bedM = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
          // 나이트콜 시간 = 최소 취침 시간 - 2시간
          int nightCallH = bedH - 2;
          if (nightCallH < 0) nightCallH += 24;
          final nightCallTime =
              '${nightCallH.toString().padLeft(2, '0')}:${bedM.toString().padLeft(2, '0')}';
          final displayH = _formatTime12(nightCallTime);

          // 개입 시간 조건: 저녁 6시(18시) ~ 나이트콜 시간 사이에 앱을 열었을 때만 개입
          final currentTotalMinutes =
              DateTime.now().hour * 60 + DateTime.now().minute;
          final nightCallTotalMinutes = nightCallH * 60 + bedM;
          final isLateNightEntry =
              _latePlannerNightDate(DateTime.now(), minSleepTimeStr) != null;
          final isInterventionWindow =
              isLateNightEntry ||
              (currentTotalMinutes >= 18 * 60 &&
                  (nightCallTotalMinutes >= 18 * 60
                      ? currentTotalMinutes < nightCallTotalMinutes
                      : currentTotalMinutes < 24 * 60));

          if (isInterventionWindow) {
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
            if (isLateNightEntry) {
              sb.writeln(
                '   "오늘도 늦게 깨어 있으시네요. 피곤하지 않으세요? 혹시 꼭 끝내야 하는 일이라도 있으신가요?"',
              );
            } else {
              sb.writeln(
                '   "최근 이틀 연속으로 취침 기준 시간을 넘긴 늦은 시간에 들어오셔서, 컨디션이 조금 밀릴까 걱정됩니다. 오늘은 $displayH시부터 취침 준비에 들어가시면 좋을 것 같은데, 혹시 $displayH시 넘어서라도 꼭 끝내야 할 중요한 일정이 있으세요?"',
              );
            }
            sb.writeln(
              '2. 사용자가 "있다" / "응" / "맞아" 등 긍정하면: 간략히 공감하고 "힘드시겠지만 파이팅 하십시오." 로 마무리. 더 이상 나이트콜 제안 안 함.',
            );
            if (isLateNightEntry) {
              sb.writeln(
                '3. 사용자가 "없다" / "아니" / "딱히" 등 부정하면: 강요하지 말고 걱정과 제안의 톤으로 말하세요. 예: "요즘 체력이 떨어지실까 봐 걱정돼요. 오늘은 조금 일찍 눈 붙이는 거 어떠세요?" 죄책감을 주지 말고, 사용자가 편하게 내려놓을 수 있게 짧고 부드럽게 마무리하세요. [NIGHT_CALL_OFFER] 태그는 출력하지 마세요.',
              );
            } else {
              sb.writeln(
                '3. 사용자가 "없다" / "아니" 등 부정하면: "그럼 오늘 $displayH시에 나이트콜을 해드릴까요?" 라고 묻고 답변 끝에 반드시 [NIGHT_CALL_OFFER] 태그를 출력하세요. 이 태그는 대화 텍스트에 절대 노출되어선 안 됩니다.',
              );
            }
            sb.writeln(
              '* 나이트콜 시간: $nightCallTime (최소 취침 시간 $minSleepTimeStr 기준 2시간 전)',
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

      final currentTotalMinutes = now.hour * 60 + now.minute;
      final minSleepTimeStr = prefs.getString('nyang_premium_min_sleep_time');
      bool isSleepWindow = false;
      bool isUnsetLateNight = false;

      if (minSleepTimeStr != null) {
        try {
          final parts = minSleepTimeStr.split(':');
          final bedH = int.tryParse(parts[0]) ?? 1;
          final bedM = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
          final bedTotalMinutes = bedH * 60 + bedM;
          final wakeTotalMinutes = (bedTotalMinutes + 4 * 60) % (24 * 60);

          if (bedTotalMinutes < wakeTotalMinutes) {
            isSleepWindow =
                currentTotalMinutes >= bedTotalMinutes &&
                currentTotalMinutes < wakeTotalMinutes;
          } else {
            isSleepWindow =
                currentTotalMinutes >= bedTotalMinutes ||
                currentTotalMinutes < wakeTotalMinutes;
          }
        } catch (_) {}
      } else {
        // 미설정 시 자정 ~ 새벽 4시 사이를 모호한 시간대로 간주
        if (now.hour >= 0 && now.hour < 4) {
          isUnsetLateNight = true;
        }
      }

      if (allTasksDone && allTasks.isNotEmpty) {
        sb.writeln('\n[특별 지침: 모든 할 일 100% 완료 상태]');
        sb.writeln(
          '사용자가 오늘 계획한 모든 할 일을 100% 완료했습니다. 절대로 다른 일을 더 하라고 재촉하거나 묻지 마세요. 시간대와 상관없이 완벽한 하루를 보낸 것을 축하하며, 푹 쉬라고 강하게 권장하세요.',
        );
      } else if (isSleepWindow) {
        sb.writeln('\n[특별 지침: 사용자 설정 취침 시간 초과]');
        sb.writeln(
          '현재 시간은 사용자가 설정한 최소 취침 시간을 넘긴 심야 시간대입니다. 가볍게 휴식을 권유하거나 현재 일과를 마무리 중인지 먼저 부드럽게 물어보세요. 단, 무조건 자라고 강요하지 마세요. 만약 사용자가 "아직 할 일이 남았다"거나 "더 일해야 한다"고 답변한다면, "늦은 시간까지 정말 고생이 많으십니다. 무리하지 마시고 파이팅입니다!" 라며 따뜻하게 응원하고 일에 집중할 수 있도록 든든하게 지지해 주세요.',
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

  Future<String> _callOpenAI(String userText, {bool isGreeting = false}) async {
    final history = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : _messages;

    // 할매 코치 전용: 랜덤 애정 표현 주입
    String halmaeHint = '';
    if (_coach.id == 'halmae') {
      const halmaePool = [
        '에이구 기특해라.',
        '잘했다. 우리 새끼.',
        '할미가 응원한다.',
        '우리 새끼가 최고지.',
        '아이고 예뻐라 우리 새끼.',
        '내 새끼니까 당연히 잘했겠지.',
        '할미가 믿는다.',
      ];
      final picked = halmaePool[Random().nextInt(halmaePool.length)];
      halmaeHint =
          '\n[이번 대화 지침] 답변 어딘가에 "$picked" 이 표현을 자연스럽게 한 번 녹여 써라. 끝에 억지로 붙이지 말고 문장 흐름 안에 자연스럽게 넣어라.';
    }

    final prefs = await SharedPreferences.getInstance();
    final customTitle = await UserTitleService.getTitle();
    final baseSystemPrompt = _coach.isMaster
        ? _coach.systemPrompt.replaceAll(
            UserTitleService.defaultTitle,
            customTitle,
          )
        : _coach.systemPrompt;

    final contextString = await _buildContextString();

    final systemPromptWithChips =
        '''$baseSystemPrompt
${contextString.isNotEmpty ? '\n$contextString' : ''}

[감정 토로 응답 원칙]
- 사용자가 속상함, 피로, 불안, 답답함 등 감정을 토로하면 먼저 충분히 공감하고 달래주세요.
- 감정 속에 해결 가능한 문제가 함께 드러나면, 긴 전략 조언은 하지 말고 지금 할 수 있는 작은 행동 하나만 조용히 제안하세요.
- 전략 분석, 원인 진단, 자세한 조언은 사용자가 "왜", "어떻게", "분석해줘", "조언해줘"처럼 명시적으로 요청했을 때만 길게 제공하세요.
- 감정 토로 상황에서는 답변을 짧게 유지하고, 공감의 온기가 행동 제안에 묻히지 않게 하세요.

[출력 규칙]
1. 지정된 캐릭터의 성격, 호칭, 말투 규칙을 철저히 준수하세요.
2. 마크다운 문법(**, *, # 등) 절대 사용하지 말 것.
3. 답변 끝에 자연스러운 빠른 답장 버튼 3개를 [CHIPS: 버튼1|버튼2|버튼3] 형식으로 추가하세요.
   예시: [CHIPS: 오늘 할 일 정하기|기분 이야기하기|그냥 얘기하자]
4. [TIMER_START] 태그는 절대 사용 금지. 사용자가 같은 할 일을 2회 이상 반복 회피할 때만 [TIMER_CONFIRM:분:할일이름] 태그로 선택지를 제시할 수 있습니다. 예: [TIMER_CONFIRM:5:보고서 작성]. 처음 귀찮다거나 한 번만 언급한 경우에는 절대 사용하지 않습니다.
5. 사용자가 특정 할 일을 언급하거나 해결 가능한 문제가 드러나고, 그걸 오늘 할 일로 등록할 만한 상황이라면 답변에 [TASK: 할일명] 태그를 포함하세요. 예: "5시에 청소해야지" → [TASK: 5시에 청소], "오후 3시에 회의가 있어" → [TASK: 오후 3시 회의], "SNS 반응이 안 좋아" → [TASK: SNS 콘텐츠 분석하기]. 억지로 추가하지 말고 사용자의 감정이나 문제 상황에서 자연스럽게 이어지는 작은 행동일 때만 사용하세요.$halmaeHint''';

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
    } else if (userText == '일정 에스코트') {
      effectiveUserText = '''일정 에스코트
[System: 사용자가 방금 현재 시간 기준으로 일정 에스코트를 다시 요청했습니다. 반드시 시스템 프롬프트 상의 **최신 시간**과 **최신 할 일 현황(완료/미완료 상태 등)**을 확인하여, 이전 대화 맥락에 얽매이지 말고 지금 당장 할 수 있는 미완료 일정을 새롭게 추천하고 하루 스케줄(타임라인)을 배정해 주세요.

*일정 연관성 및 우선순위 판단 규칙 (1차 판단 원칙):*
오늘 미완료된 일정들을 에스코트(스케줄링)할 때, 각 일정이 사용자의 장기 비전, 마일스톤, 월목표, 주목표와 어떻게 연결되는지 아래 판단 원칙을 반드시 준수하십시오:
1. [키워드 겹침 및 맥락적 연관성 판단]: 오늘 할 일 이름과 비전, 마일스톤, 월목표, 주목표 이름 사이에 겹치는 핵심 키워드가 있거나, 텍스트의 어휘가 다소 다르더라도 개념상 서로 깊게 연관(예: '시나리오 쓰기' ↔ '영화 감상')되어 있다면 이를 비전/목표 관련 핵심 일정으로 분류합니다. 해당 일정들은 오늘 집중력이 높은 골든 타임(예: 오전 시간 등)에 최우선적으로 배치하십시오.
2. [비연관/불확실 일정 처리 (침묵 원칙)]: 비전/목표/마일스톤과 연관성이 모호하거나 전혀 없는 일정(예: 설거지, 빨래, 청소 등 단순 가사나 잡무)을 스케줄에 배치할 때는, 굳이 "비전과 상관없는 일정"이라거나 "목표 진행과 관계가 없다"는 식의 부정적이고 단정적인 언급을 대화 피드백에 절대 덧붙이지 마십시오. 아무런 언급 없이 조용히 스케줄표상에 빈 시간대(또는 덜 중요한 시간대)로 배치하기만 하십시오.
   - 또한, 억지로 "비전 진행과는 관계가 없다고 볼 수 있습니다"라거나 "분석에서 제외했습니다" 등 부정적이거나 기운을 빠지게 하는 단정적인 결론을 지어 설명에 포함해서는 절대 안 됩니다.
   - 만약 사용자가 직접 질문하여 그러한 무관한 일정을 언급해야 하는 상황이 생기더라도, "관계가 없다"고 결론 내리지 말고 "간접적인 연결점은 있을 수 있으나, 지금은 비전에 직결되는 핵심 행동에 더 집중해 보자"는 식으로 부드럽고 유연한 열린 태도로 답변하십시오.

*주의사항:*
1) 미완료된 일정이 여러 개라면 단 하나도 누락하지 말고 모두 포함하여 스케줄을 짜세요.
2) 할 일에 배정된 "예상 소요시간"을 철저하게 지키고 소요시간 계산(덧셈)을 틀리지 마세요.
3) 사용자가 별도로 할 일이나 습관으로 지정해 둔 식사 시간이 없다면, 기본적으로 점심식사(대략 12시~13시)와 저녁식사(대략 18시~19시) 시간을 반드시 휴식 및 식사 시간으로 비워두고 스케줄을 짜세요.
4) 마크다운 ** 나 * 등은 절대 쓰지 마십시오. [TASK] 태그도 포함하지 마십시오.]''';
    } else if (userText == '비전을 위한 오늘') {
      effectiveUserText = '''비전을 위한 오늘
[System: 사용자가 방금 현재 시간 기준으로 "비전을 위한 오늘"을 다시 요청했습니다. 반드시 이전 대화 맥락에 얽매이지 말고 시스템 프롬프트 상의 **최신 시간**과 **최신 할 일 현황(추가/완료 상태 등)**을 바탕으로 완전히 새롭게 분석을 진행하세요. 절대 단순 일정 생성이나 시간 배치를 제안하지 마세요. 대신 다음의 **비전 추적 및 점검** 역할을 수행해야 합니다.

*데이터 분석 범위 및 연관성 판단 규칙 (1차 판단 원칙):*
반드시 대화 및 분석(조언)을 작성하기 전에, 오늘 등록된 할 일/일정/습관이 장기 비전, 마일스톤, 월목표, 주목표와 어떻게 연결되는지 아래 판단 원칙에 따라 1차적으로 먼저 판단하십시오:
1. [키워드 겹침 판단]: 오늘 할 일 이름과 비전, 마일스톤, 월목표, 주목표 이름 사이에 겹치는 핵심 키워드(예: 'sns', 'ai', '공부', '영어', '코딩' 등)가 단 하나라도 존재한다면, 이 일정은 최우선적으로 '관련된 일정'으로 판단하고 분류합니다.
2. [연관 키워드 및 맥락적 연관성 판단]: 텍스트의 어휘가 정확히 일치하지 않더라도, 개념적으로 서로 깊게 연관되어 있다면 '관련된 일정'으로 판단합니다. (예시: 장기 비전에 "시나리오 쓰기"가 있고 오늘의 할 일에 "영화 '헤어질 결심' 보기"가 있다면, '시나리오'와 '영화'는 맥락상 밀접하므로 연관된 일정으로 간주합니다.)
3. [불확실/비연관 일정 처리 (침묵 원칙)]: 위 1, 2단계를 거쳤음에도 비전, 마일스톤, 월/주 목표와 연관성이 명확하지 않거나 아예 없는 일정(예: 설거지, 방 청소 등 단순 가사노동이나 무관한 일반 업무)은 **이번 비전 분석 대화에서 절대로 먼저 언급하지 말고 아예 제외(생략)하십시오.**
   - 또한, 억지로 "비전 진행과는 관계가 없다고 볼 수 있습니다"라거나 "분석에서 제외했습니다" 등 부정적이거나 기운을 빠지게 하는 단정적인 결론을 지어 설명에 포함해서는 절대 안 됩니다.
   - 만약 사용자가 직접 질문하여 그러한 무관한 일정을 언급해야 하는 특수한 상황이 생기더라도, "관계가 없다"고 결론 내리지 말고 "간접적인 연결점은 있을 수 있으나, 지금은 비전에 직결되는 핵심 행동에 더 집중해 보자"는 식으로 부드럽고 유연한 열린 태도로 답변하십시오.

*6대 점검 규칙 (조건에 맞는 상황을 분석해 코치의 톤으로 자연스럽게 대화체로 조언할 것):*
1. 비전 진행 점검: 장기 비전, 마일스톤, 월목표, 주목표와 연관된 오늘의 일정 완료율을 파악합니다. (비전/목표와 무관하여 3번 침묵 원칙에 따라 생략된 일정은 분석 및 완료율 계산 대상에서 완전히 배제해야 합니다.)
2. 반복 미룸 탐지: 최근 계속 미뤄지고 있는 비전/목표 관련 일정이 있다면, "이번 주에 계속 미뤄지고 있는 목표가 있습니다. 오늘 시간이 괜찮으시다면 조금이라도 진행해보시는 건 어떨까요?" 식으로 부드럽게 제안합니다.
3. 중복 제안 금지: 이미 오늘 계획에 비전/목표 관련 일정이 있다면 새 일정 추가 없이 "오늘 계획에 이미 포함되어 있는 만큼 이 일정은 꼭 챙겨보셨으면 좋겠습니다."라고 강조합니다.
4. 마일스톤 지연: 마일스톤이나 장기 비전의 진척이 늦어지고 있다면 "원래 예상보다 조금 늦어지고 있는 것 같습니다. 오늘 조금만 진행해도 흐름을 이어갈 수 있을 것 같아요."라고 조언합니다.
5. 긍정적 흐름: 비전/목표 관련 일정 완료율이 높다면 "최근 목표 관련 일정 완료율이 높습니다. 지금의 흐름을 유지하면 마일스톤에 더 가까워질 수 있을 것 같아요."라고 칭찬합니다.
6. 구조 부족: 장기 비전은 있으나 마일스톤/기한이 없다면 "마일스톤 기한을 추가해주시거나 월목표, 주목표를 정해주시면 목표 진행 상황을 더 정확하게 도와드릴 수 있습니다."라고 제안합니다.]''';
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
            ...history.map(
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

    final chatBackgroundColor = _coach.isMaster
        ? const Color(0xFFFAF5EF)
        : Colors.transparent;

    return Stack(
      children: [
        Column(
          children: [
            _buildSummaryCard(),
            Expanded(
              child: Container(
                color: chatBackgroundColor,
                width: double.infinity,
                child: Column(
                  children: [
                    Expanded(
                      child: _messages.isEmpty
                          ? _buildEmptyState()
                          : _buildMessageList(),
                    ),
                    if (!_coach.isMaster &&
                        (_dynamicChips.isNotEmpty || _coach.chips.isNotEmpty))
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
              onTap: () {
                final mins = _timerConfirmMinutes ?? 5;
                setState(() {
                  _timerConfirmMinutes = null;
                  _timerConfirmTaskName = null;
                  _timerActiveMinutes = mins;
                });
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

  List<Map<String, String>> get _cheatKeyItems => [
    {'icon': '🗺️', 'label': '일정 에스코트'},
    {'icon': '⚡', 'label': '지금 뭐하지?'},
    {'icon': '🧭', 'label': '비전을 위한 오늘'},
  ];

  Widget _buildCheatKeyMenu() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4A017)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4A017).withOpacity(0.25),
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

              if (item['label'] == '일정 에스코트') {
                AnalyticsService.logFeatureUsage('cheat_schedule_escort');
              } else if (item['label'] == '지금 뭐하지?') {
                AnalyticsService.logFeatureUsage('cheat_next_action');
              } else if (item['label'] == '비전을 위한 오늘') {
                AnalyticsService.logFeatureUsage('cheat_today_vision');
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
                  Text(item['icon']!, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 8),
                  Text(
                    item['label']!,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF5B4E2A),
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
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFDE68A), width: 1.2),
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
                    color: _masterGold,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFFDE68A)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD4A017).withOpacity(0.08),
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
                        color: const Color(0xFF8E8A9E),
                      ),
                    ),
                    Text(
                      '$_completedTasks / $_totalTasks',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6B5EA8),
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
                    color: const Color(0xFFE8E3F8),
                    child: FractionallySizedBox(
                      widthFactor: progress,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFC4B5FD), Color(0xFF8B7CCC)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              if (widget.onOpenDrawer != null) {
                widget.onOpenDrawer!();
              }
            },
            child: const Icon(
              Icons.chevron_right_rounded,
              size: 28,
              color: Color(0xFF6B5EA8),
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
                  color: const Color(0xFF6B5EA8).withValues(alpha: 0.10),
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
                    color: const Color(0xFF8B7CCC).withOpacity(0.10),
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
                          color: const Color(0xFF7C5CFC),
                        ),
                      ),
                      Text(
                        '$_attendanceStreak일 출석',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3D3A4E),
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
                        color: const Color(0xFFA0A0B0),
                      ),
                    ),
                    Text(
                      '$_completedTasks / $_totalTasks',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6B5EA8),
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
                          : const Color(0xFFE8E3F8),
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
                            colors: [Color(0xFFC4B5FD), Color(0xFF8B7CCC)],
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
                      color: const Color(0xFF9B8FC8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 보기 버튼
          GestureDetector(
            onTap: () {
              if (widget.onOpenDrawer != null) {
                widget.onOpenDrawer!();
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFDDD6FE), width: 1.5),
              ),
              child: Text(
                '보기 ›',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF6B5EA8),
                ),
              ),
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
    final list = ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount:
          _messages.length +
          (_isLoading ? 1 : 0) +
          (_timerActiveMinutes != null ? 1 : 0),
      itemBuilder: (ctx, i) {
        // 타이머 위젯은 메시지 목록 맨 끝에
        if (_timerActiveMinutes != null &&
            i == _messages.length + (_isLoading ? 1 : 0)) {
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
        if (_isLoading && i == _messages.length) return _buildTypingIndicator();
        return _buildBubble(_messages[i]);
      },
    );

    // 마스터 비서는 은은한 크림톤 배경
    if (_coach.isMaster) {
      return ColoredBox(color: const Color(0xFFFAF5EF), child: list);
    }

    // 프렌즈는 배경 투명 (main_tab_screen에서 전체 배경 처리)
    return ColoredBox(color: Colors.transparent, child: list);
  }

  Widget _buildBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    final time = DateFormat('a h:mm', 'ko').format(msg.time);

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
                  fontSize: 10,
                  color: const Color(0xFFBBBBCC),
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
                color: isUser ? _coach.accentColor : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: _buildMessageText(
                msg,
                GoogleFonts.notoSansKr(
                  fontSize: 14,
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                  color: isUser ? Colors.white : const Color(0xFF1A1A2E),
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
                  fontSize: 10,
                  color: const Color(0xFFBBBBCC),
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
  Widget _buildChips() {
    final chips = _dynamicChips.isNotEmpty ? _dynamicChips : _coach.chips;
    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final chip = chips[i];
          final chipBg = Colors.white;
          final chipBorder = _coach.accentColor.withOpacity(0.3);
          final chipText = _coach.accentColor;
          return GestureDetector(
            onTap: () => _send(chip),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: chipBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                chip,
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: chipText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 입력창 ───────────────────────────────────────────────
  Widget _buildInputArea() {
    final isFriends = !_coach.isMaster;
    final isNyang = widget.coachId == 'cat';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: isFriends ? Colors.transparent : Colors.white,
        border: isFriends
            ? null
            : const Border(top: BorderSide(color: Color(0xFFF0EEF8))),
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
                        : (isNyang
                              ? Colors.white.withOpacity(0.3)
                              : (isFriends
                                    ? Colors.white.withOpacity(0.2)
                                    : Colors.white)),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: _isListening
                          ? Colors.redAccent
                          : (isNyang
                                ? _coach.accentColor.withOpacity(0.6)
                                : (isFriends
                                      ? Colors.white.withOpacity(0.3)
                                      : const Color(0xFFF3E5AB))),
                      width: _isListening ? 2.0 : 1.2,
                    ),
                    boxShadow: isFriends
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFFB8860B).withOpacity(0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: _isListening
                        ? Colors.redAccent
                        : (isNyang
                              ? _coach.accentColor
                              : (isFriends
                                    ? Colors.white
                                    : const Color(0xFFB8860B))),
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
                    color: isFriends
                        ? Colors.white.withOpacity(0.25)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isNyang
                          ? _coach.accentColor.withOpacity(0.5)
                          : (isFriends
                                ? Colors.white.withOpacity(0.3)
                                : const Color(0xFFDBC07A)),
                      width: 1.2,
                    ),
                  ),
                  child: TextField(
                    controller: _ctrl,
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: isNyang
                          ? const Color(0xFF1A1A2E)
                          : (isFriends
                                ? Colors.white
                                : const Color(0xFF1A1A2E)),
                    ),
                    decoration: InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      hintStyle: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        color: isNyang
                            ? const Color(0xFF4B445F).withOpacity(0.62)
                            : (isFriends
                                  ? Colors.white.withOpacity(0.6)
                                  : const Color(0xFFBBBBCC)),
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
                            colors: [Color(0xFF1A1A1A), Color(0xFF050505)],
                          ),
                    color: isFriends ? _coach.accentColor : null,
                    borderRadius: BorderRadius.circular(22),
                    border: isFriends
                        ? null
                        : Border.all(
                            color: const Color(0xFFDBC07A),
                            width: 1.2,
                          ),
                    boxShadow: [
                      BoxShadow(
                        color: isFriends
                            ? _coach.accentColor.withOpacity(0.35)
                            : Colors.black.withOpacity(0.18),
                        blurRadius: isFriends ? 10 : 15,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: isFriends ? Colors.white : const Color(0xFFFDE68A),
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
      'totalCount': tasksList.length + deferredList.length,
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

    // Keep last 90 days
    history.sort((a, b) => a['date']!.compareTo(b['date']!));
    if (history.length > 90) history = history.sublist(history.length - 90);

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
