import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_font.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/user_data.dart';
import '../services/notification_service.dart';
import '../services/analytics_service.dart';
import '../services/apple_calendar_sync_service.dart';
import '../services/morning_call_alarm_session.dart';
import '../services/calendar_pullback_cleanup.dart';
import '../services/daily_reset_service.dart';
import '../services/life_context_service.dart';
import '../services/widget_sync_service.dart';
import '../services/tasks_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'coach_config.dart';
import 'coach_selection_screen.dart';
import 'tasks_screen.dart';
import 'records_screen.dart';
import 'settings_screen.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_button.dart';

// 각 탭 화면 플레이스홀더
class ChatPlaceholderScreen extends StatelessWidget {
  const ChatPlaceholderScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline_rounded,
          size: 48,
          color: AppDesignTokens.brand,
        ),
        SizedBox(height: 12),
        Text(
          '채팅 화면',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text(
          '곧 만들어집니다!',
          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
}

class TasksPlaceholderScreen extends StatelessWidget {
  const TasksPlaceholderScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.checklist_rounded, size: 48, color: AppDesignTokens.brand),
        SizedBox(height: 12),
        Text(
          '할 일 화면',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text(
          '곧 만들어집니다!',
          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
}

class RecordPlaceholderScreen extends StatelessWidget {
  const RecordPlaceholderScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.bar_chart_rounded, size: 48, color: AppDesignTokens.brand),
        SizedBox(height: 12),
        Text(
          '기록 화면',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text(
          '곧 만들어집니다!',
          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
}

class SettingsPlaceholderScreen extends StatelessWidget {
  const SettingsPlaceholderScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.settings_outlined, size: 48, color: AppDesignTokens.brand),
        SizedBox(height: 12),
        Text(
          '설정 화면',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 8),
        Text(
          '곧 만들어집니다!',
          style: TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
        ),
      ],
    ),
  );
}

bool _isMasterCoach(String coachId) =>
    coachId == 'nyang_halbae' || coachId == 'sec_female';

bool isPlannerOverlayRoute(String? route) {
  return route == 'tasks' ||
      route == 'tasks_done_bottom_sheet' ||
      route == 'tasks_remaining_bottom_sheet' ||
      route == 'schedule' ||
      route == 'recurring_schedule' ||
      route == 'habit' ||
      route == 'vision' ||
      route == 'milestone';
}

int plannerOverlayTabIndexForRoute(String? route) {
  return switch (route) {
    'schedule' || 'recurring_schedule' => 1,
    'habit' => 3,
    'vision' || 'milestone' => 2,
    _ => 0,
  };
}

// ─────────────────────────────────────────────────────────────
// 메인 탭 화면
// ─────────────────────────────────────────────────────────────
class MainTabScreen extends StatefulWidget {
  final String coachId;
  final int initialDrawerIndex;
  final String? initialBottomSheet;
  final String? handoffFromCoachId;
  final bool openTasksOverlayOnStart;
  final int initialPlannerTabIndex;
  final String? initialPlannerDateKey;
  final String? initialPlannerItemId;
  const MainTabScreen({
    super.key,
    required this.coachId,
    this.initialDrawerIndex = 0,
    this.initialBottomSheet,
    this.handoffFromCoachId,
    this.openTasksOverlayOnStart = false,
    this.initialPlannerTabIndex = 0,
    this.initialPlannerDateKey,
    this.initialPlannerItemId,
  });

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _recordsFeedbackSeenSignatureKey =
      'nyang_records_feedback_seen_signature';

  /// 메인을 바꿀 수 있다는 안내를 이미 보여줬는지.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다 — 봤다는 것은 이 기기에서 일어난 일이고,
  /// 클라우드가 덮으면 새 기기에서 영영 못 본다.
  static const String _mainModeHintShownKey = 'main_mode_hint_shown';

  /// 안내를 언제 띄울지. 앱을 켠 직후는 볼 것이 많아 흘려보낸다.
  static const Duration _mainModeHintDelay = Duration(seconds: 6);

  static const String _catWidgetPromptHiddenKey =
      'cat_widget_prompt_hidden_forever';
  static const String _catWidgetPromptFirstSeenAtKey =
      'cat_widget_prompt_first_seen_at';
  static const String _catWidgetPromptLastShownAtKey =
      'cat_widget_prompt_last_shown_at';
  static const Duration _catWidgetPromptFirstDelay = Duration(days: 1);
  static const Duration _catWidgetPromptCooldown = Duration(days: 7);

  /// 어느 화면을 앱의 메인으로 쓸지. 'chat' 또는 'todo'.
  ///
  /// 'nyang_' 접두어를 쓴다 — 이건 이 사람의 선택이라 기기를 바꾸거나 다시
  /// 로그인해도 따라와야 한다.
  static const String mainModeKey = 'nyang_main_mode';
  static const String mainModeChat = 'chat';
  static const String mainModeTodo = 'todo';

  /// 서랍 번호는 뜻을 그대로 둔다(0 채팅 / 1 할일 / 2 기록 / 3 설정). 바뀌는 것은
  /// **그중 무엇이 본문 자리에 서는가**와 하단 탭에 늘어서는 순서뿐이다.
  ///
  /// 번호에 자리를 섞지 않는 이유는 하나다 — 이 번호를 보는 곳이 서른 곳이 넘는다.
  /// 순서를 번호에 담으면 그 전부가 모드를 알아야 한다.
  String _mainMode = mainModeChat;

  bool get _todoIsMain => _mainMode == mainModeTodo;

  /// 이 사람이 메인으로 고른 화면의 번호. 이 번호가 곧 "서랍이 닫힌 상태"다.
  int get _mainIndex => _todoIsMain ? 1 : 0;

  /// 지금 본문 자리에 실제로 서는 화면의 번호.
  ///
  /// **채팅은 서랍에 넣지 않는다.** 코치 이름과 배경 그림을 채팅 화면이 아니라
  /// 껍데기가 그려서, 서랍의 흰 통 안에 들어가면 헤더도 배경도 여백 기준도 다
  /// 잃는다. 할 일이 메인일 때 채팅을 열면 화면이 망가져 보이던 것이 이것이다.
  ///
  /// 그래서 채팅을 고르면 본문 자리를 쓴다 — 가로로 꽉 차고 하단 탭은 그대로
  /// 남아, 그 탭이 돌아가는 길이 된다.
  ///
  /// 기록과 설정은 서랍으로 둔다. 전체화면으로도 해봤는데(코치 헤더와 배경을
  /// 접고 탭 줄 색까지 갈랐다) 옆에서 열리는 편이 낫다는 판단이었다. 채팅·할 일과
  /// 달리 잠깐 들여다보고 돌아오는 자리다.
  int get _bodyIndex => _openDrawerIndex == 0 ? 0 : _mainIndex;

  /// 하단 탭에 늘어서는 순서. 채팅과 할 일만 자리를 바꾼다.
  List<int> get _tabOrder =>
      _todoIsMain ? const [1, 0, 2, 3] : const [0, 1, 2, 3];

  late int _openDrawerIndex; // 0: 채팅, 1: 할일, 2: 기록, 3: 설정
  late TabController _tabCtrl;
  final ChatScreenController _chatController = ChatScreenController();
  final TasksScreenController _tasksController = TasksScreenController();
  bool _coachAccessChecked = false;
  bool _widgetIntentDrawerMode = false;
  // 앱 전체에서 플래너 전체창이 딱 하나만 뜨도록 모든 화면 인스턴스가
  // 공유하는 플래그. 위젯을 연타하거나 화면이 겹쳐 쌓인 상태에서도
  // 이미 열려 있으면 새로 덮어 띄우지 않는다.
  static bool _isPlannerOverlayOpen = false;

  bool _redirectingForCoachAccess = false;
  bool _catWidgetPromptShowing = false;

  /// 개발용 플랜 시뮬레이터를 여는 데 필요한 연속 탭 수.
  static const int _debugPlanSelectorTapCount = 10;

  int _logoTapCount = 0;
  Timer? _logoTapTimer;

  void _showDebugPlanSelector() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '개발자용 플랜 시뮬레이터',
            style: appFont(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.star_border, color: Colors.grey),
                title: Text(
                  '비구독자 상태 (none)',
                  style: appFont(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  await UserDataService.setPlan('none');
                  if (mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.pets, color: Color(0xFF03C75A)),
                title: Text(
                  '프렌즈 플랜 (friends)',
                  style: appFont(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  await UserDataService.setPlan('friends');
                  if (mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.workspace_premium,
                  color: Color(0xFFD4A017),
                ),
                title: Text(
                  '마스터 플랜 (master)',
                  style: appFont(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  await UserDataService.setPlan('master');
                  if (mounted) Navigator.pop(context);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('닫기', style: appFont(fontWeight: FontWeight.w700)),
            ),
          ],
        );
      },
    ).then((_) {
      // 모달이 닫힌 후 새로고침
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CoachSelectionScreen(returnCoachId: widget.coachId),
        ),
      );
    });
  }

  void _handleHeaderTap() {
    _logoTapCount++;
    print('DEBUG: Header tapped. Count: $_logoTapCount');
    _logoTapTimer?.cancel();
    _logoTapTimer = Timer(const Duration(seconds: 2), () {
      print('DEBUG: Header tap timer expired. Resetting count.');
      _logoTapCount = 0;
    });

    if (_logoTapCount >= _debugPlanSelectorTapCount) {
      print('DEBUG: 5 taps reached! Showing modal.');
      _logoTapCount = 0;
      _logoTapTimer?.cancel();
      _showDebugPlanSelector();
    }
  }

  Future<void> _switchCoachFromChat(String coachId) async {
    final userData = await UserDataService.load();
    if (!userData.canAccessCoach(coachId)) return;

    await UserDataService.setSelectedCoach(coachId);
    if (!mounted) return;
    final isFromSecretary =
        widget.coachId == 'nyang_halbae' || widget.coachId == 'sec_female';
    final handoffFromCoachId = isFromSecretary && coachId == 'cat'
        ? widget.coachId
        : null;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainTabScreen(
          coachId: coachId,
          handoffFromCoachId: handoffFromCoachId,
        ),
      ),
    );
  }

  void _showOwnedCoachesDropdown() async {
    final userData = await UserDataService.load();
    final allCoaches = CoachConfigs.all.values.toList();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final masterCoaches = allCoaches
            .where((c) => c.tier == 'master')
            .toList();
        final friendsCoaches = allCoaches
            .where((c) => c.tier != 'master')
            .toList();

        // 마스터 플랜인 사람에게는 마스터 코치를 위에 둔다. 쓰는 코치가
        // 위에 있어야 하고, 마스터 플랜이면 마스터가 주 코치다. 프렌즈
        // 플랜이면 반대로 마스터 쪽은 잠겨 있는 목록이라 아래가 맞다.
        //
        // 플랜 이름이 아니라 실제로 들어갈 수 있는지로 가른다. 만료된 마스터
        // 플랜은 이름이 남아 있어도 자물쇠가 걸린 목록이라 위로 올릴 것이 없다.
        final hasMasterAccess = masterCoaches.any(
          (c) => userData.canAccessCoach(c.id),
        );
        final sections = <(String, List<CoachConfig>)>[
          if (hasMasterAccess) ...[
            if (masterCoaches.isNotEmpty) ('마스터 코치', masterCoaches),
            if (friendsCoaches.isNotEmpty) ('프렌즈 코치', friendsCoaches),
          ] else ...[
            if (friendsCoaches.isNotEmpty) ('프렌즈 코치', friendsCoaches),
            if (masterCoaches.isNotEmpty) ('마스터 코치', masterCoaches),
          ],
        ];

        Widget buildTile(CoachConfig c) {
          final isSelected = c.id == widget.coachId;
          final isOwned = userData.canAccessCoach(c.id);

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 0,
            ),
            visualDensity: const VisualDensity(
              horizontal: 0,
              vertical: -4,
            ), // 간격 축소
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFF3F0FF),
              backgroundImage: AssetImage(c.imagePath),
            ),
            title: Text(
              c.name,
              style: appFont(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isOwned
                    ? (isSelected ? const Color(0xFF6B5EA8) : Colors.black87)
                    : Colors.grey,
              ),
            ),
            trailing: isSelected
                ? const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF6B5EA8),
                    size: 20,
                  )
                : (!isOwned
                      ? const Icon(
                          Icons.lock_rounded,
                          color: Colors.grey,
                          size: 16,
                        )
                      : null),
            onTap: () {
              if (!isOwned) return;
              Navigator.pop(context);
              if (!isSelected) {
                Navigator.pushReplacement(
                  this.context,
                  MaterialPageRoute(
                    builder: (_) => MainTabScreen(coachId: c.id),
                  ),
                );
              }
            },
          );
        }

        return SafeArea(
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '내 코치 이동',
                  style: appFont(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final section in sections) ...[
                          if (section != sections.first)
                            const Divider(height: 16, color: Color(0xFFF0F0F5)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: Text(
                              section.$1,
                              style: appFont(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ...section.$2.map(buildTile),
                        ],
                        const SizedBox(height: 16),
                      ],
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

  Timer? _morningCallTimer;
  Timer? _coreReminderTimer;
  Timer? _dailyRolloverTimer;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _lastMorningCallDate;
  final Set<String> _firedCoreReminders = {};
  bool _showRecordsNewBadge = false;
  bool _hasMasterPlanForRecordsBadge = false;
  StreamSubscription<User?>? _authSubscription;

  String _dateKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String _recordsFeedbackWeekMonday(SharedPreferences prefs) {
    final lastDate = prefs.getString('nyang_last_date') ?? '';
    final parts = lastDate.split('-');
    DateTime baseDate;
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final d = int.tryParse(parts[2]) ?? DateTime.now().day;
      baseDate = DateTime(y, m, d);
    } else {
      final now = DateTime.now();
      baseDate = DateTime(now.year, now.month, now.day);
      if (now.hour < 3) {
        baseDate = baseDate.subtract(const Duration(days: 1));
      }
    }
    final monday = baseDate.subtract(Duration(days: baseDate.weekday - 1));
    return _dateKey(monday);
  }

  /// 안 읽음 표시가 보는 서명.
  ///
  /// 번호는 기록탭의 한마디 캐시와 같은 것을 쓴다. 한마디를 다시 뽑게 만들면
  /// 표시도 저절로 다시 뜬다 — 따로 두면 한쪽만 올리고 잊게 된다.
  String _recordsFeedbackSignature(String weekMonday) {
    return '$weekMonday:v${RecordsScreen.weeklyFeedbackVersion}';
  }

  Future<void> _refreshRecordsNewBadge({UserData? userData}) async {
    final data = userData ?? await UserDataService.load();
    final hasMasterPlan = data.isPlanActive && data.planType == 'master';
    if (!hasMasterPlan) {
      if (mounted && (_showRecordsNewBadge || _hasMasterPlanForRecordsBadge)) {
        setState(() {
          _showRecordsNewBadge = false;
          _hasMasterPlanForRecordsBadge = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final signature = _recordsFeedbackSignature(
      _recordsFeedbackWeekMonday(prefs),
    );
    final seenSignature = prefs.getString(_recordsFeedbackSeenSignatureKey);
    final shouldShow = seenSignature != signature && _openDrawerIndex != 2;
    if (mounted &&
        (_showRecordsNewBadge != shouldShow ||
            !_hasMasterPlanForRecordsBadge)) {
      setState(() {
        _showRecordsNewBadge = shouldShow;
        _hasMasterPlanForRecordsBadge = true;
      });
    }
  }

  Future<void> _markRecordsFeedbackSeen() async {
    final data = await UserDataService.load();
    final hasMasterPlan = data.isPlanActive && data.planType == 'master';
    if (!hasMasterPlan) {
      if (mounted && (_showRecordsNewBadge || _hasMasterPlanForRecordsBadge)) {
        setState(() {
          _showRecordsNewBadge = false;
          _hasMasterPlanForRecordsBadge = false;
        });
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _recordsFeedbackSeenSignatureKey,
      _recordsFeedbackSignature(_recordsFeedbackWeekMonday(prefs)),
    );
    if (mounted && (_showRecordsNewBadge || !_hasMasterPlanForRecordsBadge)) {
      setState(() {
        _showRecordsNewBadge = false;
        _hasMasterPlanForRecordsBadge = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlannerHelpSeen();
    _openDrawerIndex = widget.initialDrawerIndex;
    _widgetIntentDrawerMode = widget.initialDrawerIndex != 0;
    unawaited(_loadMainMode());
    unawaited(_maybeShowMainModeHint());
    WidgetsBinding.instance.addObserver(this);
    unawaited(_runStartupDailyReset());
    // 아이폰 캘린더를 되읽던 시절이 남긴 유령 할 일과 미래 쉬기 기록을 한 번
    // 치운다. 클라우드 복원이 끝난 뒤에만 돈다.
    unawaited(_cleanUpCalendarPullbackLeftovers());
    _startDailyRolloverWatcher();
    _audioPlayer.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.alarm,
          contentType: AndroidContentType.music,
          audioFocus: AndroidAudioFocus.gainTransientExclusive,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
      ),
    );
    _tabCtrl = TabController(length: _tabLabels.length, vsync: this);
    // 이미 쌓인 채팅에서 생활의 자취를 한 번 주워둔다. 두 번째부터는 아무
    // 일도 하지 않는다.
    unawaited(LifeContextService.seedFromChatHistory());
    // 한 주가 통째로 안 풀린 사람에게만, 아침에 한 번. 대개는 아무 일도 없다.
    _startMorningCallEngine();
    _startCoreReminderEngine();
    AnalyticsService.logAppOpen();
    _ensureCurrentCoachAccess();
    unawaited(_refreshRecordsNewBadge());
    if (_openDrawerIndex == 2) {
      unawaited(_markRecordsFeedbackSeen());
    }
    if (widget.openTasksOverlayOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPlannerOverlay(
          initialBottomSheet: widget.initialBottomSheet,
          initialTabIndex: widget.initialPlannerTabIndex,
          initialDateKey: widget.initialPlannerDateKey,
          initialItemId: widget.initialPlannerItemId,
        );
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_maybeShowCatWidgetPrompt());
      });
    }

    // 냥냥코치 웹 앱(Nyang Insight) 연동 등을 통해 실시간으로 Firebase에 추가된 할 일 동기화
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        TasksSyncService.startRealTimeSync(user.uid, () {
          unawaited(NotificationService().syncDailyMorningCall());
          if (mounted) {
            _tasksController.refresh();
            _chatController.refreshTaskProgress();
            setState(() {});
          }
        });
      } else {
        TasksSyncService.stopRealTimeSync();
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    TasksSyncService.stopRealTimeSync();
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    _morningCallTimer?.cancel();
    _coreReminderTimer?.cancel();
    _dailyRolloverTimer?.cancel();
    MorningCallAlarmSession().stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AnalyticsService.logAppOpen();
      _handleAppResumed();
    }
  }

  /// 앱을 배경으로 보내지 않은 채 자정을 넘기는 경우를 잡는다.
  ///
  /// 자정 정리는 원래 앱을 껐다 켤 때(리줌)만 돌았다. 켜둔 채로 날짜가
  /// 넘어가면 화면은 실시간으로 오늘을 계산해 보여주는데, 어제 목록을
  /// 보관하고 오늘 걸 새로 채우는 정리는 안 도는 채로 남아 있었다. 그 틈에
  /// 추가한 일정이 나중에 뒤늦게 도는 정리에 통째로 어제 날짜로 딸려가는
  /// 문제가 있었다.
  ///
  /// 처음에는 분 단위로 계속 확인했는데, 하루에 한 번 일어나는 일을 1440번
  /// 물어보는 셈이었다. 다음 자정에 딱 한 번 깨우고, 깨어난 자리에서 그다음
  /// 자정을 다시 예약한다.
  void _startDailyRolloverWatcher() {
    _dailyRolloverTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1);
    // 기기 시계가 자정을 막 지난 순간에 깨면 아직 어제로 읽힐 수 있다.
    // 몇 초 지나서 깨운다.
    final wait = nextMidnight.difference(now) + const Duration(seconds: 5);
    _dailyRolloverTimer = Timer(wait, () {
      unawaited(_checkDailyRollover());
      if (mounted) _startDailyRolloverWatcher();
    });
  }

  /// 앱을 처음 켤 때 도는 자정 정리.
  ///
  /// 정리와 화면의 첫 읽기가 나란히 달린다. 정리가 조금 늦게 끝나면 화면은
  /// 정리 이전 목록을 그대로 들고 있는데, 끝났다고 알려주는 자리가 없어서 그
  /// 상태가 앱을 끌 때까지 갔다. 어제 칸이 비어 보이던 나머지 절반이 여기다.
  /// 어느 화면을 메인으로 쓰는지 읽어온다.
  ///
  /// 화면을 세운 뒤에 읽는다. 그래서 할 일이 메인인 사람은 첫 한 박자 동안
  /// 채팅이 보일 수 있다 — prefs를 읽는 시간이라 눈에 잡히지는 않는다. 켜는
  /// 길(main.dart / landing_screen)이 열한 군데라 거기서 미리 읽어 넘기는 것은
  /// 나중에 값이 보이면 할 일이다.
  Future<void> _loadMainMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString(mainModeKey);
    if (!mounted || mode == null || mode == _mainMode) return;
    if (mode != mainModeChat && mode != mainModeTodo) return;
    setState(() {
      _mainMode = mode;
      // 서랍은 닫힌 채로 시작한다. 위젯이나 알림이 특정 서랍을 열어달라고
      // 부탁한 경우는 그대로 둔다.
      if (!_widgetIntentDrawerMode) _openDrawerIndex = _mainIndex;
    });
  }

  /// 메인 화면을 바꾼다. 두 화면의 데이터는 건드리지 않는다 — 어느 것이 본문
  /// 자리에 서고 어느 것이 서랍에 들어가는지만 바뀐다.
  Future<void> setMainMode(String mode) async {
    if (mode != mainModeChat && mode != mainModeTodo) return;
    if (mode == _mainMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(mainModeKey, mode);
    TasksSyncService.scheduleSyncToCloud();
    if (!mounted) return;
    setState(() {
      _mainMode = mode;
      _openDrawerIndex = _mainIndex;
      _widgetIntentDrawerMode = false;
    });
    unawaited(
      AnalyticsService.logFeatureUsage(
        mode == mainModeTodo ? 'main_mode_todo' : 'main_mode_chat',
      ),
    );
  }

  Future<void> _runStartupDailyReset() async {
    // 클라우드 복원이 끝나기를 기다렸다가 정리한다. 그냥 부르면 복원보다 먼저
    // 달릴 수 있고, 그때는 아직 안 온 데이터를 없는 것으로 치고 하루를 넘긴다.
    final rebuilt = await DailyResetService.checkAndExecuteResetAfterRestore();
    // 정리가 건너뛰어 빠진 하루 요약이 있으면 여기서 채운다. 정리 뒤에 불러야
    // 한다 - 정리가 방금 만든 것을 보고 그냥 지나가야 한다.
    unawaited(DailyResetService.catchUpMissedDailySummary());
    // 정리가 "오늘 것은 이미 끝났다"로 지나간 날에도 루틴은 맞춰준다.
    final synced = await DailyResetService.syncTodayHabitTasks();
    if ((!rebuilt && !synced) || !mounted) return;
    _tasksController.refresh();
    _chatController.refreshTaskProgress();
  }

  Future<void> _cleanUpCalendarPullbackLeftovers() async {
    final cleaned = await CalendarPullbackCleanup.runOnce();
    if (!cleaned || !mounted) return;
    _tasksController.refresh();
    _chatController.refreshTaskProgress();
    setState(() {});
  }

  Future<void> _checkDailyRollover() async {
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString(DailyResetService.lastDateKey);
    await DailyResetService.checkAndExecuteReset();
    unawaited(DailyResetService.catchUpMissedDailySummary());
    final synced = await DailyResetService.syncTodayHabitTasks();
    final after = prefs.getString(DailyResetService.lastDateKey);
    if (before == after && !synced) return;
    if (!mounted) return;
    _tasksController.refresh();
    _chatController.refreshTaskProgress();
    setState(() {});
  }

  Future<void> _handleAppResumed() async {
    await NotificationService().handleNativeMorningAlarm();
    // 설정에서 알림을 켜고 돌아온 경우다. 막혀 있던 동안 걸리지 않은 예약을
    // 여기서 다시 건다.
    unawaited(NotificationService().reapplyAlarmsIfPermissionRecovered());
    await DailyResetService.checkAndExecuteReset();
    await DailyResetService.syncTodayHabitTasks();
    try {
      final appleCalendarChanged = await AppleCalendarSyncService.instance
          .syncAll();
      if (appleCalendarChanged) {
        await WidgetSyncService.syncFromStoredTasks();
        TasksSyncService.scheduleSyncToCloud();
      }
    } catch (e, stackTrace) {
      debugPrint('Resume Apple calendar sync failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
    if (mounted) {
      _tasksController.refresh();
      _chatController.refreshTaskProgress();
      setState(() {});
    }
    final canContinue = await _ensureCurrentCoachAccess(syncCloud: _isMaster);
    if (canContinue) {
      await _refreshRecordsNewBadge();
      await _checkWidgetIntent();
      await _maybeShowCatWidgetPrompt();
    }
  }

  Future<bool> _ensureCurrentCoachAccess({bool syncCloud = false}) async {
    if (_redirectingForCoachAccess) return false;

    if (syncCloud) {
      await UserDataService.syncFromCloud().timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
    }
    final data = await UserDataService.load();
    unawaited(
      WidgetSyncService.enforcePlanAccess(
        hasMasterPlan: data.isPlanActive && data.planType == 'master',
      ).catchError((Object e, StackTrace stackTrace) {
        debugPrint('Widget access sync failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }),
    );
    final canAccess = data.canAccessCoach(widget.coachId);

    if (canAccess) {
      unawaited(_refreshRecordsNewBadge(userData: data));
      if (mounted && !_coachAccessChecked) {
        setState(() => _coachAccessChecked = true);
      }
      return true;
    }

    _redirectingForCoachAccess = true;
    await UserDataService.setSelectedCoach('cat');
    if (!mounted) return false;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CoachSelectionScreen()),
      (route) => false,
    );
    return false;
  }

  Future<void> _maybeShowCatWidgetPrompt() async {
    if (!mounted ||
        _catWidgetPromptShowing ||
        widget.coachId != 'cat' ||
        widget.openTasksOverlayOnStart ||
        _openDrawerIndex != _mainIndex) {
      return;
    }

    final data = await UserDataService.load();
    if (!data.isPlanActive || !data.canAccessCoach('cat')) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_catWidgetPromptHiddenKey) ?? false) return;

    final now = DateTime.now();
    final firstSeenAt = prefs.getInt(_catWidgetPromptFirstSeenAtKey);
    if (firstSeenAt == null) {
      await prefs.setInt(
        _catWidgetPromptFirstSeenAtKey,
        now.millisecondsSinceEpoch,
      );
      return;
    }
    final firstSeen = DateTime.fromMillisecondsSinceEpoch(firstSeenAt);
    if (now.difference(firstSeen) < _catWidgetPromptFirstDelay) return;

    final lastShownAt = prefs.getInt(_catWidgetPromptLastShownAtKey);
    if (lastShownAt != null) {
      final lastShown = DateTime.fromMillisecondsSinceEpoch(lastShownAt);
      if (now.difference(lastShown) < _catWidgetPromptCooldown) {
        return;
      }
    }

    final hasWidget = await WidgetSyncService.hasInstalledCatHomeWidget();
    if (hasWidget || !mounted) return;

    await prefs.setInt(
      _catWidgetPromptLastShownAtKey,
      now.millisecondsSinceEpoch,
    );
    _catWidgetPromptShowing = true;
    try {
      await _showCatWidgetPromptSheet(prefs);
    } finally {
      _catWidgetPromptShowing = false;
    }
  }

  Future<void> _openCatWidgetPromptFromChat() async {
    if (!mounted || _catWidgetPromptShowing) return;

    final prefs = await SharedPreferences.getInstance();
    final hasWidget = await WidgetSyncService.hasInstalledCatHomeWidget();
    if (hasWidget) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 냥냥코치 위젯이 활성화되어 있어요.')));
      return;
    }

    await prefs.setInt(
      _catWidgetPromptLastShownAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    _catWidgetPromptShowing = true;
    try {
      await _showCatWidgetPromptSheet(prefs);
    } finally {
      _catWidgetPromptShowing = false;
    }
  }

  Future<void> _showCatWidgetPromptSheet(SharedPreferences prefs) {
    return showAppBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        Future<void> chooseWidget(String widgetId) async {
          final isMini = widgetId == 'cat';
          await prefs.setBool('widget_nyang_enabled', isMini);
          await prefs.setBool('widget_cat_character_enabled', !isMini);
          await prefs.setBool('widget_nyang_halbae_enabled', false);
          await prefs.setBool('widget_sec_female_enabled', false);
          await prefs.setBool('nyang_home_widget_enabled', true);
          await WidgetSyncService.syncFromStoredTasks();

          if (sheetContext.mounted) Navigator.pop(sheetContext);

          if (Platform.isIOS) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('홈 화면을 길게 누른 뒤 + 버튼에서 냥냥코치 위젯을 추가해 주세요.'),
              ),
            );
            return;
          }

          final didRequestPin = await WidgetSyncService.requestPinWidget(
            widgetId,
          );
          if (!mounted || didRequestPin) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이 기기에서는 앱에서 위젯 추가 요청을 띄울 수 없어요.')),
          );
        }

        Future<void> hideForever() async {
          await prefs.setBool(_catWidgetPromptHiddenKey, true);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        }

        return AppBottomSheetScaffold(
          maxHeightFactor: 0.76,
          body: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppDesignTokens.brandSoft,
                      borderRadius: BorderRadius.circular(
                        AppDesignTokens.radiusMedium,
                      ),
                      border: Border.all(color: AppDesignTokens.brandBorder),
                    ),
                    child: const Icon(
                      Icons.widgets_rounded,
                      color: AppDesignTokens.brand,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '냥이가 홈 화면에서도 기다릴까?',
                          style: appFont(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: AppDesignTokens.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '앱을 열지 않아도 오늘 할 일을 살짝 볼 수 있다냥.',
                          style: appFont(
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                            color: AppDesignTokens.brandTextMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _CatWidgetPromptOption(
                title: '미니 위젯',
                subtitle: '작게 올려두고 남은 할 일을 바로 보기',
                onTap: () => chooseWidget('cat'),
              ),
              const SizedBox(height: 10),
              _CatWidgetPromptOption(
                title: '가로 위젯',
                subtitle: '냥이랑 오늘 진행 상황을 더 넓게 보기',
                isRecommended: true,
                onTap: () => chooseWidget('cat_character'),
              ),
            ],
          ),
          footer: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: '나중에',
                variant: AppButtonVariant.secondary,
                onPressed: () => Navigator.pop(sheetContext),
              ),
              const SizedBox(height: 8),
              AppButton(
                label: '다시는 보지 않기',
                variant: AppButtonVariant.outline,
                backgroundColor: Colors.transparent,
                foregroundColor: AppDesignTokens.textSecondary,
                borderColor: AppDesignTokens.divider,
                onPressed: hideForever,
              ),
            ],
          ),
        );
      },
    );
  }

  void _openTasksGoalVisionDrawer(List<String> highlightVisionIds) {
    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _tasksController.openGoalVision(highlightVisionIds: highlightVisionIds);
    });
  }

  /// 채팅에서 부탁받은 설정 시트를 열어둔 채 설정 탭으로 간다.
  String? _pendingSettingsSection;

  void _openSettingsSectionFromChat(String section) {
    setState(() {
      _pendingSettingsSection = section;
      _openDrawerIndex = 3;
      _widgetIntentDrawerMode = false;
    });
  }

  void _openFeatureLocationFromChat(String location) {
    final taskTabByLocation = {
      'today': 0,
      'schedule': 1,
      'goals': 2,
      'habit': 3,
    };

    if (location == 'records') {
      unawaited(_markRecordsFeedbackSeen());
      setState(() {
        _openDrawerIndex = 2;
        _widgetIntentDrawerMode = false;
      });
      return;
    }

    if (location == 'settings') {
      setState(() {
        _openDrawerIndex = 3;
        _widgetIntentDrawerMode = false;
      });
      return;
    }

    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (location == 'vision') {
        _tasksController.openGoalVision();
        return;
      }
      final tabIndex = taskTabByLocation[location];
      if (tabIndex != null) {
        _tasksController.openTab(tabIndex);
      }
    });
  }

  Future<bool> _registerHabitFromChat(
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
    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return false;
    return _tasksController.addHabitFromChat(
      name,
      freq: freq,
      days: days,
      weeklyTargetCount: weeklyTargetCount,
      countGoal: countGoal,
      unit: unit,
      time: time,
      endTime: endTime,
      habitDuration: habitDuration,
    );
  }

  /// 채팅에서 말로 등록한 주간·월간 목표. 습관과 같은 방식으로 서랍을 열어
  /// 들어간 자리를 바로 보여준다.
  Future<bool> _registerGoalFromChat(String type, String text) async {
    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return false;
    return _tasksController.addGoalFromChat(type, text);
  }

  Future<String> _handleDeleteCommandFromChat(
    Map<String, dynamic> command,
  ) async {
    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) {
      return '삭제할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
    }
    return _tasksController.handleDeleteCommand(command);
  }

  /// 할 일 탭을 열고 그 칸을 번쩍인다.
  ///
  /// 체크는 사용자가 한다. 채팅에서 대신 완료로 적어주는 길은 걷어냈다 —
  /// 코치가 알아들은 것이 맞는지 확인하는 데 드는 품이, 탭에서 체크 한 번
  /// 누르는 것보다 컸다.
  Future<String> _handleEditCommandFromChat(
    Map<String, dynamic> command,
  ) async {
    setState(() {
      _openDrawerIndex = 1;
      _widgetIntentDrawerMode = false;
    });
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) {
      return '수정할 항목을 찾는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
    }
    return _tasksController.handleEditCommand(command);
  }

  Future<void> _showPlannerOverlay({
    String? initialBottomSheet,
    int initialTabIndex = 0,
    String? initialDateKey,
    String? initialItemId,
  }) async {
    if (_isPlannerOverlayOpen) {
      final navigator = Navigator.of(context, rootNavigator: true);
      if (navigator.canPop()) {
        navigator.pop();
        await Future.delayed(const Duration(milliseconds: 180));
      }
      _isPlannerOverlayOpen = false;
    }
    _isPlannerOverlayOpen = true;

    if (_openDrawerIndex != _mainIndex || _widgetIntentDrawerMode) {
      setState(() {
        _openDrawerIndex = _mainIndex;
        _widgetIntentDrawerMode = false;
      });
    }

    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _PlannerOverlayScreen(
          initialBottomSheet: initialBottomSheet,
          initialTabIndex: initialTabIndex,
          initialDateKey: initialDateKey,
          initialItemId: initialItemId,
        ),
      ),
    );

    _isPlannerOverlayOpen = false;
    if (!mounted) return;
    setState(() {
      _openDrawerIndex = _mainIndex;
      _widgetIntentDrawerMode = false;
    });
    _chatController.refreshTaskProgress();
  }

  Future<void> _checkWidgetIntent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final widgetRoute = prefs.getString('widget_route');
    final widgetCoachId = prefs.getString('widget_coach_id');
    final widgetDate = prefs.getString('widget_date');
    final widgetItemId = prefs.getString('widget_item_id');

    if (widgetRoute != null ||
        widgetCoachId != null ||
        widgetDate != null ||
        widgetItemId != null) {
      if (widgetRoute != null) prefs.remove('widget_route');
      if (widgetCoachId != null) prefs.remove('widget_coach_id');
      if (widgetDate != null) prefs.remove('widget_date');
      if (widgetItemId != null) prefs.remove('widget_item_id');

      final isTasksRoute = isPlannerOverlayRoute(widgetRoute);
      const targetCoachId = 'cat';
      final type = widgetRoute == 'tasks_done_bottom_sheet'
          ? 'done'
          : widgetRoute == 'tasks_remaining_bottom_sheet'
          ? 'remaining'
          : null;
      final data = await UserDataService.load();

      if (!data.canAccessCoach(targetCoachId)) {
        await UserDataService.setSelectedCoach('cat');
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const CoachSelectionScreen()),
          (route) => false,
        );
        return;
      }

      if (isTasksRoute) {
        // 위젯을 누르기 전에 있던 화면은 그대로 두고, 할 일 창을 그 위에
        // 겹쳐서 띄운다. 닫으면 원래 있던 화면이 그대로 다시 보인다.
        if (!mounted) return;
        await _showPlannerOverlay(
          initialBottomSheet: type,
          initialTabIndex: plannerOverlayTabIndexForRoute(widgetRoute),
          initialDateKey: widgetDate,
          initialItemId: widgetItemId,
        );
        return;
      }

      // 채팅 관련 위젯(비서 코치 위젯의 '채팅' 버튼 등)은 해당 코치 화면으로 이동
      if (targetCoachId != widget.coachId) {
        await UserDataService.setSelectedCoach(targetCoachId);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainTabScreen(coachId: targetCoachId),
          ),
        );
      }
    }
  }

  void _startMorningCallEngine() {
    _morningCallTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      if (MorningCallAlarmSession().isActive) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final enabled = prefs.getBool('nyang_morning_call_enabled') ?? false;
      if (!enabled) return;

      final alarmTimeStr = prefs.getString('nyang_morning_call_time');
      if (alarmTimeStr == null) return;

      final now = DateTime.now();
      final currentHHMM =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final currentDate = '${now.year}-${now.month}-${now.day}';

      final lastFiredDate = prefs.getString('nyang_last_morning_call_date');

      if (currentHHMM == alarmTimeStr &&
          _lastMorningCallDate != currentDate &&
          lastFiredDate != currentDate) {
        _lastMorningCallDate = currentDate;
        await prefs.setString('nyang_last_morning_call_date', currentDate);

        final coachIdStr = prefs.getString('nyang_morning_call_coach') ?? 'cat';
        _fireMorningCall(coachIdStr);

        // Reschedule next morning call (picks a new random coach for tomorrow)
        await NotificationService().rescheduleNextMorningCall();
      }
    });
  }

  void _startCoreReminderEngine() {
    _coreReminderTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('nyang_core_reminder_enabled') ?? false;
      if (!enabled) return;

      final advanceMinutes = prefs.getInt('nyang_core_reminder_advance') ?? 10;
      final now = DateTime.now();
      // 알림 예약 쪽과 같은 자리수로 맞춰야 중복 방지 키가 서로 맞는다
      final currentDate =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final currentFullDate = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      );

      final rawCore = prefs.getString('nyang_core_tasks');
      if (rawCore == null || rawCore.isEmpty) return;

      final coreList = jsonDecode(rawCore) as List;
      bool shouldFire = false;
      String fireTaskText = '';

      final firedList = prefs.getStringList('nyang_fired_core_reminders') ?? [];
      final Set<String> firedSet = Set.from(firedList);

      for (var item in coreList) {
        if (item['isReminderEnabled'] == false) continue;
        final tTimeStart = item['timeStart'];
        if (tTimeStart != null && tTimeStart is String) {
          final parts = tTimeStart.split(':');
          if (parts.length == 2) {
            final tHour = int.tryParse(parts[0]) ?? 0;
            final tMin = int.tryParse(parts[1]) ?? 0;
            final scheduledDate = DateTime(
              now.year,
              now.month,
              now.day,
              tHour,
              tMin,
            );
            final targetDate = scheduledDate.subtract(
              Duration(minutes: advanceMinutes),
            );

            // Compute difference in minutes between now and the reminder target time
            final diff = currentFullDate.difference(targetDate).inMinutes;
            // Allow a 5-minute window so that manual testing or returning from background works
            if (diff >= 0 && diff <= 5) {
              // Include the exact target timestamp in the fireKey so a schedule change creates a new key
              final fireKey = NotificationService.coreReminderFireKey(
                alarmId: item['id'],
                targetDate: targetDate,
                dateKey: currentDate,
              );
              if (!firedSet.contains(fireKey) &&
                  !_firedCoreReminders.contains(fireKey)) {
                _firedCoreReminders.add(fireKey);
                firedSet.add(fireKey);
                await prefs.setStringList(
                  'nyang_fired_core_reminders',
                  firedSet.toList(),
                );
                shouldFire = true;
                fireTaskText = item['text'] ?? '';
                break;
              }
            }
          }
        }
      }

      if (shouldFire) {
        // Do not overwrite the fireKey here; it already stores the unique reminder identifier
        final coachIdStr =
            prefs.getString('nyang_core_reminder_coach') ?? 'push';
        _fireCoreReminder(coachIdStr, advanceMinutes, fireTaskText);
      }
    });
  }

  void _fireMorningCall(String configuredCoachId) async {
    if (MorningCallAlarmSession().isActive) return;
    AnalyticsService.logFeatureUsage('morning_call');
    final prefs = await SharedPreferences.getInstance();

    var targetCoachId = configuredCoachId;
    final resolvedCoachId = prefs.getString(
      'nyang_morning_call_resolved_coach',
    );
    if (configuredCoachId == 'random' &&
        resolvedCoachId != null &&
        resolvedCoachId.isNotEmpty) {
      targetCoachId = resolvedCoachId;
    }

    if (targetCoachId == 'random') {
      final availableCoaches = CoachConfigs.all.values
          .where((coach) => coach.voiceCount > 0)
          .map((coach) => coach.id)
          .toList();
      if (availableCoaches.isNotEmpty) {
        targetCoachId =
            availableCoaches[Random().nextInt(availableCoaches.length)];
      } else {
        targetCoachId = 'cat';
      }
    } else if (!CoachConfigs.all.containsKey(targetCoachId)) {
      targetCoachId = 'cat';
    }

    final coach = CoachConfigs.get(targetCoachId);
    final count = coach.voiceCount;
    String? soundName;

    if (count > 0) {
      final randNum = Random().nextInt(count) + 1;
      soundName = '${targetCoachId}_$randNum';
    }

    if (mounted) {
      MorningCallAlarmSession().start(
        coachId: targetCoachId,
        soundName: soundName,
      );
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return _buildMorningCallOverlay(coach);
        },
      );
    }
  }

  Widget _buildMorningCallOverlay(CoachConfig coach) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 펄스 애니메이션이나 단순 컨테이너
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: coach.accentColor, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: coach.accentColor.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                  image: DecorationImage(
                    image: AssetImage(coach.imagePath),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '⏰ 모닝콜 시간입니다!',
                style: appFont(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${coach.name} 코치가 깨우러 왔어요',
                style: appFont(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 64),
              ElevatedButton(
                onPressed: () {
                  MorningCallAlarmSession().stop();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: coach.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: Text(
                  '모닝콜 끄기',
                  style: appFont(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _fireCoreReminder(
    String configuredCoachId,
    int advanceMinutes,
    String taskText,
  ) async {
    AnalyticsService.logFeatureUsage('core_reminder');
    final prefs = await SharedPreferences.getInstance();

    // Use the resolved core reminder coach ID from SharedPreferences if it matches the configured setting,
    // which aligns the in-app engine with the background notification selection.
    String targetCoachId = configuredCoachId == 'random'
        ? 'push'
        : configuredCoachId;
    final resolvedCoachId = prefs.getString(
      'nyang_core_reminder_resolved_coach',
    );
    if (resolvedCoachId != null &&
        resolvedCoachId.isNotEmpty &&
        resolvedCoachId != 'random') {
      targetCoachId = resolvedCoachId;
    }
    targetCoachId = targetCoachId == 'push'
        ? 'push'
        : CoachConfigs.normalizeId(targetCoachId);
    if (targetCoachId != 'push' &&
        !CoachConfigs.all.containsKey(targetCoachId)) {
      targetCoachId = 'push';
    }
    if (targetCoachId != 'push' &&
        CoachConfigs.get(targetCoachId).voiceCount <= 0) {
      targetCoachId = 'push';
    }

    NotificationService().showImmediateNotification(
      title: taskText.isNotEmpty ? '🔔 $taskText' : '🔔 오늘의 핵심 일정',
      body: '$advanceMinutes분 뒤 시작해요.',
    );

    // iPhone에서는 사전 알림은 일반 푸시만, 시작 시각에는 냥냥이 배너만 쓴다.
    // 둘 다 iOS 알림 배너라 같은 역할로 겹치면 중복처럼 보인다.
    if (targetCoachId == 'push' || Platform.isIOS) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              taskText.isNotEmpty
                  ? '🔔 [$taskText] 일정이 $advanceMinutes분 뒤 시작돼요!'
                  : '🔔 핵심 일정이 $advanceMinutes분 뒤 시작돼요!',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: const Color(0xFF1A1A2E),
          ),
        );
      }
      return;
    }

    final coach = CoachConfigs.get(targetCoachId);

    if (mounted) {
      showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black87,
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, anim1, anim2) {
          return _buildCoreReminderOverlay(coach, taskText);
        },
      );
    }
  }

  Widget _buildCoreReminderOverlay(CoachConfig coach, String taskText) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: coach.accentColor, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: coach.accentColor.withOpacity(0.5),
                      blurRadius: 30,
                      spreadRadius: 10,
                    ),
                  ],
                  image: DecorationImage(
                    image: AssetImage(coach.imagePath),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  taskText.isNotEmpty ? '🔔 $taskText' : '🔔 오늘의 핵심 일정',
                  style: appFont(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${coach.name}가 잊지 않게 알려드려요!',
                style: appFont(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 64),
              ElevatedButton(
                onPressed: () {
                  _audioPlayer.stop();
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: coach.accentColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 48,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(32),
                  ),
                ),
                child: Text(
                  '확인',
                  style: appFont(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 본문 자리에 세울 화면 하나.
  ///
  /// 넷을 다 만들어 목록에 담고 그중 하나만 쓰던 자리다. 쓰지 않는 셋까지 매
  /// build마다 만들었고, 무엇보다 설정 화면은 그렇게 만들면 안 됐다 — 코치가
  /// 부탁한 시트를 꺼내오는 자리가 있어서, 목록을 만드는 것만으로 그 값이
  /// 소모돼 정작 설정 화면에 갔을 때 빈손이 된다.
  Widget _buildBody() {
    final body = _bodyIndex == 0 ? _buildChatScreen() : _buildTasksScreen();
    // 쓱 밀어서 채팅↔할일. 세로 스크롤이 살아 있어야 하니 가로 방향만 받는다.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: _onBodyHorizontalDrag,
      child: body,
    );
  }

  /// 본문에서 가로로 쓱 밀었을 때. 채팅과 할일 사이만 오간다.
  void _onBodyHorizontalDrag(DragEndDetails details) {
    // 서랍이 열려 있으면 본문 제스처가 아니다.
    if (_openDrawerIndex != _bodyIndex) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 220) return;

    final chatSlot = _tabOrder.indexOf(0);
    final todoSlot = _tabOrder.indexOf(1);
    if (chatSlot < 0 || todoSlot < 0) return;

    // 왼쪽으로 밀면 오른쪽 탭, 오른쪽으로 밀면 왼쪽 탭.
    final wantRightTab = velocity < 0;
    final currentSlot = _bodyIndex == 0 ? chatSlot : todoSlot;
    final targetSlot = wantRightTab ? currentSlot + 1 : currentSlot - 1;
    if (targetSlot != chatSlot && targetSlot != todoSlot) return;

    _onTabSlotTapped(targetSlot);
  }

  /// 채팅 화면. 본문 자리에도 서고 서랍에도 들어간다.
  ///
  /// 본문 자리가 채팅과 할 일 사이를 오갈 때마다 **새로 만들어진다**(본문의
  /// 키가 바뀐다). 할 일이 메인인 모드에서 채팅을 여닫으면 쓰다 만 메시지가
  /// 날아간다는 뜻이다. 대화 내용과 타이머는 prefs에서 되살아나므로 잃는 것은
  /// 그 한 가지다. 살려두는 일은 따로 잡을 것.
  Widget _buildChatScreen() => ChatScreen(
    coachId: widget.coachId,
    controller: _chatController,
    onOpenDrawer: () => setState(() => _openDrawerIndex = 1),
    onOpenGoalVisionDrawer: _openTasksGoalVisionDrawer,
    onOpenFeatureLocation: _openFeatureLocationFromChat,
    onOpenSettingsSection: _openSettingsSectionFromChat,
    onRegisterHabit: _registerHabitFromChat,
    onRegisterGoal: _registerGoalFromChat,
    onDeleteCommand: _handleDeleteCommandFromChat,
    onEditCommand: _handleEditCommandFromChat,
    onSwitchCoach: _switchCoachFromChat,
    onOpenCatWidgetPrompt: _openCatWidgetPromptFromChat,
    handoffFromCoachId: widget.handoffFromCoachId,
  );

  String? _takePendingSettingsSection() {
    final section = _pendingSettingsSection;
    _pendingSettingsSection = null;
    return section;
  }

  static const _tabLabels = ['채팅', '할 일', '기록', '설정'];

  Color get _tabActiveColor => _activeColor;

  Color get _tabInactiveColor {
    if (_isMaster) {
      return const Color(0xFF888899);
    }
    return Colors.white.withOpacity(0.6);
  }

  List<Widget> get _inactiveIcons => [
    _catFaceIcon(color: _tabInactiveColor),
    _clipboardIcon(color: _tabInactiveColor),
    _barChartIcon(color: _tabInactiveColor),
    _gearIcon(active: false, color: _tabInactiveColor),
  ];

  List<Widget> get _activeIcons => [
    _catFaceIcon(color: _tabActiveColor),
    _clipboardIcon(color: _tabActiveColor),
    _barChartIcon(color: _tabActiveColor),
    _gearIcon(active: true, color: _tabActiveColor),
  ];

  List<bool> get _tabNewBadges => [
    false,
    false,
    _hasMasterPlanForRecordsBadge && _showRecordsNewBadge,
    false,
  ];

  /// 메인을 바꿀 수 있다는 것을 한 번 알려준다.
  ///
  /// 하단 탭을 길게 눌러볼 생각을 하는 사람은 드물다. 기능이 있다는 사실만
  /// 한 번 전하고, 그 뒤로는 다시 말하지 않는다.
  Future<void> _maybeShowMainModeHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_mainModeHintShownKey) ?? false) return;
    await Future.delayed(_mainModeHintDelay);
    if (!mounted) return;
    // 서랍이 열려 있거나 전체창이 떠 있으면 지금이 아니다. 다음에 다시 만난다.
    if (_openDrawerIndex != _mainIndex || _isPlannerOverlayOpen) return;
    await prefs.setBool(_mainModeHintShownKey, true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: AppDesignTokens.textPrimary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 84),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
        ),
        content: Text(
          '채팅과 할 일 중 자주 쓰는 쪽을 메인으로 바꿀 수 있어요.\n'
          '아래 탭을 길게 눌러보세요.',
          style: appFont(
            fontSize: AppDesignTokens.textCaption,
            fontWeight: FontWeight.w600,
            color: Colors.white,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  /// 자리를 바꿀 수 있는 탭의 자리. 채팅과 할 일 둘뿐이다.
  ///
  /// 기록과 설정은 움직이지 않는다. 넷 다 끌리게 두면 사용자는 기록도 옮겨보고,
  /// 안 움직이면 고장으로 느낀다.
  Set<int> get _swappableSlots => {_tabOrder.indexOf(0), _tabOrder.indexOf(1)};

  /// 메인을 바꿀지 물어본다.
  ///
  /// 바꾸는 동작이 길게 누르기라 실수로 하기 어렵고, 되돌리는 동작도 같다.
  /// 그래서 "정말요?"를 묻지 않고 무엇이 바뀌는지만 보여주고 한 번 받는다.
  Future<void> _askSwapMain() async {
    final toTodo = !_todoIsMain;
    final target = toTodo ? '할 일' : '채팅';
    // 아래에서 올라오는 시트로 띄웠더니 하단 탭 바로 위라 눈에 안 들어왔다.
    // 화면 가운데 떠 있는 팝업으로 받는다.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (sheetContext) => Dialog(
        backgroundColor: AppDesignTokens.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusSheet),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$target을 메인으로 쓸까요?',
                style: appFont(
                  fontSize: AppDesignTokens.textTitle,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '앱을 열면 $target 화면이 먼저 보이고, '
                '${toTodo ? '채팅' : '할 일'}은 옆에서 열리는 서랍이 됩니다.\n'
                '대화 기록과 할 일은 그대로 있어요.',
                style: appFont(
                  fontSize: AppDesignTokens.textCaption,
                  color: AppDesignTokens.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: Text(
                        '그대로 둘게요',
                        style: appFont(
                          fontWeight: FontWeight.w700,
                          color: AppDesignTokens.textMuted,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesignTokens.brand,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusMedium,
                          ),
                        ),
                      ),
                      child: Text(
                        '바꾸기',
                        style: appFont(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;
    await setMainMode(toTodo ? mainModeTodo : mainModeChat);
  }

  /// 하단 탭에 실제로 늘어놓을 값들. 뜻은 그대로 두고 자리만 [_tabOrder]로 섞는다.
  List<T> _inTabOrder<T>(List<T> bySemantics) => [
    for (final index in _tabOrder) bySemantics[index],
  ];

  /// 지금 눌려 있는 탭의 **자리**. 하단 탭은 자리로 말하고 나머지는 뜻으로 말한다.
  int get _currentTabSlot {
    final slot = _tabOrder.indexOf(_openDrawerIndex);
    return slot < 0 ? 0 : slot;
  }

  /// 하단 탭이 누른 자리를 뜻으로 옮겨 [_onTabTapped]에 넘긴다.
  void _onTabSlotTapped(int slot) => _onTabTapped(_tabOrder[slot]);

  bool get _isMaster => _isMasterCoach(widget.coachId);

  Color get _activeColor =>
      _isMaster ? const Color(0xFFD4A017) : const Color(0xFF8B7CFF);

  void _onTabTapped(int index) {
    // 본문 자리를 누르면 서랍을 닫는다. 예전에는 이 갈래가 0번(채팅)에 박혀
    // 있었다 — 할 일이 메인인 모드에서는 그 0번이 "서랍에 있는 채팅"이라,
    // 채팅 탭을 눌러도 닫기만 하고 열리지 않았다.
    if (index == _mainIndex) {
      if (_openDrawerIndex != _mainIndex) {
        HapticFeedback.lightImpact();
        setState(() {
          _openDrawerIndex = _mainIndex;
          _widgetIntentDrawerMode = false;
        });
        if (index == 0) _onChatShown();
      }
      return;
    }
    if (_openDrawerIndex == index) return;
    HapticFeedback.lightImpact();
    if (index == 2) {
      unawaited(_markRecordsFeedbackSeen());
    }
    setState(() {
      _openDrawerIndex = index;
      _widgetIntentDrawerMode = false;
    });
    if (index == 1) {
      Future.delayed(const Duration(milliseconds: 80), () {
        _tasksController.resetTodayDateSelection();
      });
    }
    // 서랍으로 열리는 채팅도 "채팅에 왔다"는 자리다.
    if (index == 0) _onChatShown();
  }

  /// 채팅이 눈앞에 왔을 때. 본문으로 돌아온 것이든 서랍으로 열린 것이든 같다.
  void _onChatShown() {
    _chatController.refreshTaskProgress();
    // 미뤄둔 할일 리마인드와 취침시간 이동 제안을 확인한다.
    Future.delayed(const Duration(milliseconds: 400), () {
      _chatController.checkDeferredReminder();
      _chatController.checkBedtimeMoveOffer();
    });
  }

  Future<void> _closeDrawerAndCheck() async {
    setState(() {
      _openDrawerIndex = _mainIndex;
      _widgetIntentDrawerMode = false;
    });
    _chatController.refreshTaskProgress();
    // 채팅 탭으로 복귀 시 미뤄둔 할일 리마인드 및 취침시간 이동 제안 확인
    Future.delayed(const Duration(milliseconds: 400), () {
      _chatController.checkDeferredReminder();
      _chatController.checkBedtimeMoveOffer();
    });
  }

  // 배경 이미지 경로
  String get _bgImagePath => 'assets/images/bg_${widget.coachId}.png';

  @override
  Widget build(BuildContext context) {
    if (!_coachAccessChecked) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 마스터는 배경 없이 기존 스타일
    if (_isMaster) {
      return _buildMasterLayout();
    }
    // 프렌즈는 전체 배경 이미지
    return _buildFriendsLayout();
  }

  // ── 프렌즈: 전체 배경 이미지 (헤더/탭바 투명) ────────────
  Widget _buildFriendsLayout() {
    final systemUiStyle = SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: Stack(
        children: [
          // 배경 이미지 전체에 깔기
          Positioned.fill(
            child: Image.asset(
              _bgImagePath,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.white),
            ),
          ),
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              scrolledUnderElevation: 0,
              elevation: 0,
              centerTitle: false,
              titleSpacing: 20,
              // 딥링크 등으로 화면이 겹쳐 쌓여도 자동 뒤로가기 버튼이
              // 커스텀 뒤로가기 옆에 겹쳐 나오지 않게 한다.
              automaticallyImplyLeading: false,
              title: _buildAppBarTitle(isImmersive: true),
              actions: [_buildPlannerHelpAction()],
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey(_bodyIndex),
                child: _buildBody(),
              ),
            ),
            bottomNavigationBar: _NyangBottomTabBar(
              currentIndex: _currentTabSlot,
              onTap: _onTabSlotTapped,
              onLongPressSwappable: (_) => _askSwapMain(),
              swappableSlots: _swappableSlots,
              labels: _inTabOrder(_tabLabels),
              inactiveIcons: _inTabOrder(_inactiveIcons),
              activeIcons: _inTabOrder(_activeIcons),
              showNewBadges: _inTabOrder(_tabNewBadges),
              activeColor: _activeColor,
              bgColor: Colors.black.withOpacity(0.35),
              inactiveColor: _tabInactiveColor,
              isImmersive: true,
            ),
          ),
          // 서랍 오버레이 + 패널
          if (_openDrawerIndex != _bodyIndex) _buildSideDrawer(),
        ],
      ),
    );
  }

  // ── 마스터: 채팅창에만 배경 (기존 레이아웃 유지) ─────────
  Widget _buildMasterLayout() {
    final scaffold = Scaffold(
      backgroundColor:
          Colors.transparent, // Let the background stack show through
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: Stack(
          children: [
            // 오버레이 제거됨 (원본 이미지 선명도 유지)
            // 앱바 내용
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) =>
                                        CoachSelectionScreen(
                                          returnCoachId: widget.coachId,
                                        ),
                                    transitionsBuilder:
                                        (_, animation, __, child) {
                                          return FadeTransition(
                                            opacity: animation,
                                            child: SlideTransition(
                                              position:
                                                  Tween<Offset>(
                                                    begin: const Offset(
                                                      -0.05,
                                                      0,
                                                    ),
                                                    end: Offset.zero,
                                                  ).animate(
                                                    CurvedAnimation(
                                                      parent: animation,
                                                      curve:
                                                          Curves.easeOutCubic,
                                                    ),
                                                  ),
                                              child: child,
                                            ),
                                          );
                                        },
                                    transitionDuration: const Duration(
                                      milliseconds: 300,
                                    ),
                                  ),
                                );
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  color: const Color(0xFF1A1A2E),
                                  size: 20,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _handleHeaderTap,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                CoachConfigs.get(widget.coachId).name,
                                style: appFont(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1A1A2E),
                                ),
                              ),
                            ),
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: _showOwnedCoachesDropdown,
                              behavior: HitTestBehavior.opaque,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: const Color(0xFF1A1A2E),
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildPlannerHelpAction(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: KeyedSubtree(key: ValueKey(_bodyIndex), child: _buildBody()),
      ),
      bottomNavigationBar: _NyangBottomTabBar(
        currentIndex: _currentTabSlot,
        onTap: _onTabSlotTapped,
        onLongPressSwappable: (_) => _askSwapMain(),
        swappableSlots: _swappableSlots,
        labels: _inTabOrder(_tabLabels),
        inactiveIcons: _inTabOrder(_inactiveIcons),
        activeIcons: _inTabOrder(_activeIcons),
        showNewBadges: _inTabOrder(_tabNewBadges),
        activeColor: AppDesignTokens.brand, // 마스터도 활성은 연보라
        bgColor: Colors.white,
        inactiveColor: AppDesignTokens.textDisabled,
        isImmersive: false,
        border: const Border(top: BorderSide(color: AppDesignTokens.divider)),
      ),
    );
    return Stack(
      children: [
        ...[
          // 헤더 그림 뒤를 대화 바탕의 맨 윗색으로 칠한다.
          //
          // 흰색이었다. 그림은 화면 위에서 160만큼만 차지하는데, 상태바가 높은
          // 기기에서는 앱바가 아래로 밀려 대화 영역이 그보다 낮은 데서 시작한다.
          // 그 사이가 흰 띠로 남아, 오늘 목표 카드와 대화 사이에 색이 빈 구역이
          // 보였다. 대화 바탕과 같은 색으로 칠하면 어느 기기에서든 이어진다.
          Positioned.fill(
            child: Container(
              color: AppDesignTokens.masterChatBackgroundTop(widget.coachId),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height:
                160, // Reduced height scales down the face via BoxFit.cover and ends at goal widget middle
            child: Image.asset(
              'assets/images/bg_${widget.coachId}.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) => Container(color: Colors.white),
            ),
          ),
        ],
        scaffold,
        if (_openDrawerIndex != _bodyIndex) _buildSideDrawer(),
      ],
    );
  }

  Widget _buildAppBarTitle({required bool isImmersive}) {
    // 배경 그림 위에 얹히는 글씨라 그림 밝기를 따라간다.
    //
    // 프렌즈 방을 전부 흰색으로 두고 있었는데, 냥냥이 방만 햇살 드는 밝은
    // 거실이라 이름이 배경에 묻혔다. 나머지는 밤 헬스장이나 어두운 실내라
    // 흰색이 맞다. 재보니 냥냥이만 확연히 밝고(189) 나머지는 절반 아래다
    // (형 42, 남친 94, 할매 110).
    //
    // 배경 그림을 바꾸면 이 짝도 다시 봐야 한다.
    final isBrightRoom = widget.coachId == 'cat';
    final nameColor = isImmersive && !isBrightRoom
        ? Colors.white
        : const Color(0xFF1A1A2E);

    return Row(
      children: [
        // 뒤로가기 아이콘
        GestureDetector(
          onTap: () {
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) =>
                    CoachSelectionScreen(returnCoachId: widget.coachId),
                transitionsBuilder: (_, animation, __, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(-0.05, 0),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: child,
                    ),
                  );
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
          },
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: nameColor,
              size: 20,
            ),
          ),
        ),
        // 아바타 (왼쪽)
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: _activeColor.withOpacity(0.4), width: 2),
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/images/${widget.coachId}.png',
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.person, color: _activeColor, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // 코치 이름
        GestureDetector(
          onTap: _handleHeaderTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            CoachConfigs.get(widget.coachId).name,
            style: appFont(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: nameColor,
            ),
          ),
        ),
        const SizedBox(width: 2),
        // 드롭다운 아이콘
        GestureDetector(
          onTap: _showOwnedCoachesDropdown,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: nameColor,
              size: 24,
            ),
          ),
        ),
      ],
    );
  }

  /// 플래너 활용법을 한 번이라도 열어봤는지. 안 열어본 사람에게만 NEW를 띄운다.
  /// 기록이 쌓였는지로 판단하면, 며칠 쓰는 동안 한 번도 안 본 사람에게서
  /// 표시가 사라진다 — 정작 알려줘야 할 사람이다.
  static const _plannerHelpSeenKey = 'nyang_planner_help_seen';
  bool _plannerHelpSeen = true;

  Future<void> _loadPlannerHelpSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_plannerHelpSeenKey) ?? false;
    if (!mounted || seen == _plannerHelpSeen) return;
    setState(() => _plannerHelpSeen = seen);
  }

  Future<void> _markPlannerHelpSeen() async {
    if (_plannerHelpSeen) return;
    if (mounted) setState(() => _plannerHelpSeen = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_plannerHelpSeenKey, true);
  }

  Widget _buildPlannerHelpAction() {
    const foreground = AppDesignTokens.brandMuted;
    const border = AppDesignTokens.brandCardBorder;
    final shadowColor = AppDesignTokens.brand.withOpacity(0.16);

    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Tooltip(
        message: '플래너 활용법',
        child: InkWell(
          onTap: () {
            _markPlannerHelpSeen();
            _showPlannerHelpDialog();
          },
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Container(
                  width: 35,
                  height: 35,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: const [
                        Color(0xFFFFFEFF),
                        Color(0xFFF5F0FF),
                        Color(0xFFE9DFFF),
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                    border: Border.all(color: border, width: 1.1),
                    boxShadow: [
                      BoxShadow(
                        color: shadowColor,
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.70),
                        blurRadius: 8,
                        offset: const Offset(-3, -3),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        top: 6,
                        left: 8,
                        child: Container(
                          width: 12,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.74),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Center(
                        child: Icon(
                          Icons.question_mark_rounded,
                          color: foreground,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                // 도움말을 한 번도 누른 적 없는 사용자에게만 NEW 배지를 띄운다.
                if (!_plannerHelpSeen)
                  Positioned(
                    top: 0,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF43F3F),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: appFont(
                          fontSize: 9,
                          height: 1.0,
                          letterSpacing: 0.2,
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
      ),
    );
  }

  void _showPlannerHelpDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.34),
      builder: (dialogContext) {
        final maxHeight = MediaQuery.of(dialogContext).size.height * 0.72;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            constraints: BoxConstraints(maxWidth: 420, maxHeight: maxHeight),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppDesignTokens.brandCardBorder),
              boxShadow: [
                BoxShadow(
                  color: AppDesignTokens.brand.withOpacity(0.16),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
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
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppDesignTokens.brandSoft,
                      ),
                      child: const Icon(
                        Icons.question_mark_rounded,
                        color: AppDesignTokens.brandMuted,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '플래너 활용법',
                        style: appFont(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppDesignTokens.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      children: [
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-microphone.svg',
                          title: '음성으로 캘린더 일정 등록하기',
                          body:
                              '마이크를 누르고\n'
                              '"내일 오후 3시 회의 추가해줘"\n'
                              '"저녁 7시에 운동 등록해줘"\n'
                              '처럼 \'추가해줘\' 또는 \'등록해줘\'를 붙여 말하면 바로 캘린더 일정을 등록할 수 있어요.\n'
                              '등록 여부는 할 일 탭 > 오늘 탭에서 꼭 확인하세요.',
                          highlightTerms: const [
                            '추가해줘',
                            '등록해줘',
                            '할 일 탭 > 오늘 탭',
                          ],
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-reset.svg',
                          title: '오늘의 할 일 초기화',
                          body:
                              '할 일 목록이 매일 자정에 초기화돼요.\n'
                              '다음 날 계획은 할 일 탭 상단 날짜를 누르고 짜시면 돼요.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-comments.svg',
                          title: '귀찮거나 막힐 땐 코치에게 말하기',
                          body:
                              '하기 싫은 건 물론, 하다가 걸리는 게 생겨도 그냥 말해보세요.\n'
                              '“스트레칭 해야 하는데 거실이 너무 더워”처럼 사소한 것도 괜찮아요.\n'
                              '코치가 지금 상황에서 할 수 있는 방법을 찾아줘요.',
                          highlightTerms: const ['스트레칭 해야 하는데 거실이 너무 더워'],
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-clock.svg',
                          title: '집중 타이머 시작하기',
                          body:
                              '"타이머 좀 띄워줘" 라고 하면 바로 타이머가 튀어나와요.\n'
                              '특별히 집중하고픈 시간이 있다면 "30분 타이머 좀 띄워줘"처럼 말해보세요.',
                          // 긴 쪽을 앞에 둬야 짧은 쪽이 먼저 걸려 반만 칠해지지 않는다.
                          highlightTerms: const ['30분 타이머 좀 띄워줘', '타이머 좀 띄워줘'],
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/compass.svg',
                          title: '어디에 뭐가 있는지 모를 땐?',
                          body:
                              '코치한테 물어보세요.\n'
                              '장기 비전은 어디서 입력해?\n'
                              '할 일 창은 어디 있어?\n'
                              '코치가 대답해줄 거예요.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-calendar-days.svg',
                          title: '오늘 뭐부터 할지 모르겠다면',
                          body:
                              '혼자 고민하지 말고, 코치와 의논하세요.\n'
                              '특히 마스터 코치(비서 코치, 냥할배)들은 사용자의 장기 목표와 관련된 할 일과 미룬 항목 등을 알아서 파악하면서 더 똑똑하게 대답해줍니다.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-clipboard-check.svg',
                          title: '계획만 세우고 떠나지 마세요',
                          body:
                              '냥냥코치는 아침에 계획을 적고, 밤에 완료만 체크하는 플래너가 아닙니다.\n'
                              '할 일을 시작할 때 ▶ 를 누르면 걸린 시간이 흐르기 시작해요. 잠깐 쉬고 싶으면 Ⅱ 를 누르면 멈추고, 다시 누르면 이어집니다.\n'
                              '다 했으면 카드를 오른쪽으로 미세요.\n\n'
                              '시작해두고 도중에 멈춰도 괜찮아요. 시작했다는 게 중요하니까요.\n'
                              '코치들이 손이 안 간 중요한 일이 있으면 이야기해줄 거예요.\n\n'
                              '중간중간 할 일을 해낼 때마다 냥냥코치의 칭찬도 받아보세요. 작은 완료를 그때그때 확인하면 남은 일을 더 가볍게 이어갈 수 있습니다.\n\n'
                              '실행하는 하루를 냥냥코치와 함께하세요.',
                          highlightTerms: const [
                            '시작했다는 게 중요하니까요',
                            '카드를 오른쪽으로 미세요',
                            '이야기해줄 거예요',
                            '다시 누르면 이어집니다',
                            '작은 완료',
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 아이콘 없이 한 줄. 사용법이 아니라 덧붙이는 말이라
                        // 앞의 칸들과 같은 모양으로 세우면 항목처럼 읽힌다.
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'P.S. 설정에 생각보다 많은 기능이 숨겨져 있으니 살펴보세요.',
                            style: appFont(
                              fontSize: 13,
                              height: 1.5,
                              fontWeight: FontWeight.w700,
                              color: AppDesignTokens.brand,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: AppDesignTokens.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      '확인',
                      style: appFont(fontSize: 15, fontWeight: FontWeight.w900),
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

  Widget _buildPlannerHelpSection({
    required String iconPath,
    required String title,
    required String body,
    List<String> highlightTerms = const [],
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppDesignTokens.brandSoft,
          ),
          child: Center(
            child: SvgPicture.asset(
              iconPath,
              width: 16,
              height: 16,
              colorFilter: const ColorFilter.mode(
                AppDesignTokens.brandMuted,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: appFont(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              Text.rich(
                TextSpan(children: _plannerBodySpans(body, highlightTerms)),
                style: appFont(
                  fontSize: 13,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.brandTextMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<TextSpan> _plannerBodySpans(String body, List<String> highlightTerms) {
    if (highlightTerms.isEmpty) return [TextSpan(text: body)];

    final pattern = RegExp(highlightTerms.map(RegExp.escape).join('|'));
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in pattern.allMatches(body)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            color: AppDesignTokens.brandMuted,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
      cursor = match.end;
    }
    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }
    return spans;
  }

  /// 할 일 화면. 본문 자리에도 서고 서랍에도 들어간다.
  ///
  /// 서랍에만 있던 것을 함수로 뺐다. 두 자리가 같은 콜백을 쓰지 않으면, 할 일이
  /// 메인일 때 핵심 설정이나 계획 문답이 채팅으로 이어지지 않는다.
  Widget _buildTasksScreen() => TasksScreen(
    coachId: widget.coachId,
    controller: _tasksController,
    initialBottomSheet: widget.initialBottomSheet,
    onProgressChanged: _chatController.refreshTaskProgress,
    onCoreTaskSet: (msg) {
      // 핵심 설정 완료 시 채팅창에 비서 반응 메시지 주입
      //
      // 여기 0은 "닫는다"가 아니라 "채팅을 보여준다"다. 할 일이 메인인
      // 모드에서는 채팅 서랍을 여는 것이 되어 그대로 맞다.
      setState(() => _openDrawerIndex = 0);
      _chatController.refreshTaskProgress();
      Future.delayed(
        const Duration(milliseconds: 300),
        () => _chatController.injectAiMessage(msg),
      );
    },
    onOverplanTurns: (turns) {
      // 등록창에서 방금 주고받은 문답을 채팅으로 데려가 그 자리에서
      // 이어지듯 재생한다. 한 줄씩 살짝 텀을 둬 한꺼번에 쏟아지지
      // 않게 한다.
      setState(() => _openDrawerIndex = 0);
      var delay = 300;
      for (final turn in turns) {
        final text = turn['text']?.toString() ?? '';
        if (text.isEmpty) continue;
        final isUser = turn['isUser'] == true;
        Future.delayed(Duration(milliseconds: delay), () {
          if (isUser) {
            _chatController.injectUserChoice(text);
          } else {
            _chatController.injectAiMessage(text);
          }
        });
        delay += 600;
      }
    },
  );

  // ── 서랍 (모든 탭 공통) ────────────────────────
  Widget _buildSideDrawer() {
    final useCleanDrawer = _widgetIntentDrawerMode && _openDrawerIndex == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerTopPadding = MediaQuery.of(context).padding.top + 12;
    Widget drawerContent;
    if (_openDrawerIndex == 1) {
      drawerContent = _buildTasksScreen();
    } else if (_openDrawerIndex == 2) {
      drawerContent = RecordsScreen(coachId: widget.coachId);
    } else if (_openDrawerIndex == 3) {
      // 서랍이 이 화면으로 넘어올 때 새로 만들어지므로, 코치가 부탁한 시트는
      // 그 첫 build에서 한 번만 넘어간다.
      drawerContent = SettingsScreen(
        coachId: widget.coachId,
        autoOpenSection: _takePendingSettingsSection(),
      );
    } else {
      drawerContent = const SizedBox.shrink();
    }

    // 기록·설정 서랍은 하단 탭 위에서 끝난다. 서랍이 덮어버리면 탭을 누르려고
    // 먼저 서랍을 닫아야 해서, 다른 탭으로 가는 데 두 번이 든다.
    final keepBottomTabsOut = _openDrawerIndex == 2 || _openDrawerIndex == 3;
    final bottomTabsHeight = keepBottomTabsOut
        ? 68 + MediaQuery.of(context).padding.bottom
        : 0.0;

    return Stack(
      children: [
        if (!useCleanDrawer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            bottom: bottomTabsHeight,
            child: GestureDetector(
              onTap: () async {
                await _closeDrawerAndCheck();
              },
              child: Container(color: Colors.black.withValues(alpha: 0.5)),
            ),
          ),
        // 서랍 패널 (오른쪽에서 슬라이드)
        Positioned(
          top: 0,
          bottom: bottomTabsHeight,
          right: 0,
          width: useCleanDrawer ? screenWidth : 320,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7C5CFC).withValues(alpha: 0.15),
                  blurRadius: 32,
                  offset: const Offset(-4, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // 내용물 화면
                Expanded(
                  child: Material(
                    color: Colors.white,
                    child: Padding(
                      padding: EdgeInsets.only(top: drawerTopPadding),
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: true,
                        child: drawerContent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _catFaceIcon({required Color color}) {
    return SvgPicture.asset(
      'assets/icons/cat-face-tab.svg',
      width: 26,
      height: 26,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _clipboardIcon({required Color color}) {
    return SizedBox(
      width: 24,
      height: 26,
      child: CustomPaint(painter: _ClipboardPainter(color: color)),
    );
  }

  Widget _barChartIcon({required Color color}) {
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _BarChartPainter(color: color)),
    );
  }

  Widget _gearIcon({required bool active, required Color color}) {
    return Icon(
      active ? Icons.settings_rounded : Icons.settings_outlined,
      size: 24,
      color: color,
    );
  }
}

class _CatWidgetPromptOption extends StatelessWidget {
  const _CatWidgetPromptOption({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isRecommended = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isRecommended;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppDesignTokens.surfaceSubtle,
      borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppDesignTokens.minTouchTarget,
          ),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
            border: Border.all(color: AppDesignTokens.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appFont(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ),
                        if (isRecommended) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppDesignTokens.brandSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '추천',
                              style: appFont(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppDesignTokens.brand,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppDesignTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: AppDesignTokens.brandMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 하단 탭바
// ─────────────────────────────────────────────────────────────
class _NyangBottomTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// 자리를 바꿀 수 있는 탭을 길게 눌렀을 때. 그 탭의 자리를 넘긴다.
  final ValueChanged<int>? onLongPressSwappable;

  /// 자리를 바꿀 수 있는 탭의 자리들.
  final Set<int> swappableSlots;

  final List<String> labels;
  final List<Widget> inactiveIcons;
  final List<Widget> activeIcons;
  final List<bool> showNewBadges;
  final Color activeColor;
  final Color bgColor;
  final Color inactiveColor;
  final bool isImmersive;
  final Border? border;

  const _NyangBottomTabBar({
    required this.currentIndex,
    required this.onTap,
    this.onLongPressSwappable,
    this.swappableSlots = const {},
    required this.labels,
    required this.inactiveIcons,
    required this.activeIcons,
    required this.showNewBadges,
    required this.activeColor,
    required this.bgColor,
    required this.inactiveColor,
    this.isImmersive = false,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final tabContent = SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Row(
            children: [
              for (int i = 0; i < labels.length; i++) ...[
                Expanded(
                  child: _TabItem(
                    label: labels[i],
                    inactiveIcon: inactiveIcons[i],
                    activeIcon: activeIcons[i],
                    showNewBadge: showNewBadges.length > i
                        ? showNewBadges[i]
                        : false,
                    isActive: currentIndex == i,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    onTap: () => onTap(i),
                    onLongPress:
                        onLongPressSwappable != null &&
                            swappableSlots.contains(i)
                        ? () => onLongPressSwappable!(i)
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (isImmersive) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(color: bgColor, child: tabContent),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(color: bgColor, border: border),
      child: tabContent,
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final Widget inactiveIcon;
  final Widget activeIcon;
  final bool showNewBadge;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  /// 길게 눌렀을 때. 자리를 바꿀 수 있는 탭에만 들어온다.
  final VoidCallback? onLongPress;

  const _TabItem({
    required this.label,
    required this.inactiveIcon,
    required this.activeIcon,
    required this.showNewBadge,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _ctrl, curve: const Cubic(0.4, 0, 0.2, 1)),
    );
    _opacity = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Cubic(0.4, 0, 0.2, 1)),
    );
    if (widget.isActive) _ctrl.forward();
  }

  @override
  void didUpdateWidget(covariant _TabItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _ctrl.forward();
    } else if (!widget.isActive && oldWidget.isActive) {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final color = widget.isActive
              ? widget.activeColor
              : widget.inactiveColor;
          final icon = Transform.scale(
            scale: _scale.value,
            child: widget.isActive
                ? ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      widget.activeColor,
                      BlendMode.srcIn,
                    ),
                    child: widget.inactiveIcon,
                  )
                : widget.inactiveIcon,
          );
          return Opacity(
            opacity: _opacity.value,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    icon,
                    if (widget.showNewBadge)
                      Positioned(
                        top: -10,
                        right: -11,
                        child: Container(
                          width: 21,
                          height: 21,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5391E),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFE5391E,
                                ).withValues(alpha: 0.24),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '1',
                            style: appFont(
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                // 레이블
                Text(
                  widget.label,
                  style: appFont(
                    fontSize: AppDesignTokens.textMeta,
                    fontWeight: widget.isActive
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Custom Painters
// ─────────────────────────────────────────────────────────────
class _ClipboardPainter extends CustomPainter {
  final Color color;
  _ClipboardPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width;
    final h = size.height;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.1, h * 0.12, w * 0.8, h * 0.84),
        const Radius.circular(4),
      ),
      paint,
    );

    canvas.drawPath(
      Path()
        ..moveTo(w * 0.35, h * 0.12)
        ..lineTo(w * 0.35, h * 0.02)
        ..lineTo(w * 0.65, h * 0.02)
        ..lineTo(w * 0.65, h * 0.12),
      paint,
    );

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(w * 0.28, h * 0.46),
      Offset(w * 0.72, h * 0.46),
      linePaint,
    );
    canvas.drawLine(
      Offset(w * 0.28, h * 0.63),
      Offset(w * 0.60, h * 0.63),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_ClipboardPainter old) => old.color != color;
}

class _BarChartPainter extends CustomPainter {
  final Color color;
  _BarChartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final h = size.height;

    canvas.drawLine(
      Offset(w * 0.18, h * 0.88),
      Offset(w * 0.18, h * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.50, h * 0.88),
      Offset(w * 0.50, h * 0.26),
      paint,
    );
    canvas.drawLine(
      Offset(w * 0.82, h * 0.88),
      Offset(w * 0.82, h * 0.10),
      paint,
    );
  }

  @override
  bool shouldRepaint(_BarChartPainter old) => old.color != color;
}

// 위젯(홈 화면)에서 '할 일'을 눌렀을 때, 그 전 화면 위에 얹어서 보여주는
// 독립된 할 일 창. 닫으면 원래 있던 화면이 그대로 다시 보인다.
class _PlannerOverlayScreen extends StatelessWidget {
  final String? initialBottomSheet;
  final int initialTabIndex;
  final String? initialDateKey;
  final String? initialItemId;
  const _PlannerOverlayScreen({
    this.initialBottomSheet,
    this.initialTabIndex = 0,
    this.initialDateKey,
    this.initialItemId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(0, 2, 10, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Text(
                    '✕ 닫기',
                    style: appFont(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TasksScreen(
                coachId: 'cat',
                initialBottomSheet: initialBottomSheet,
                initialTabIndex: initialTabIndex,
                initialPlannerDateKey: initialDateKey,
                initialPlannerItemId: initialItemId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
