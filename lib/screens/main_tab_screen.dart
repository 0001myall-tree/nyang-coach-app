import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/user_data.dart';
import '../services/notification_service.dart';
import '../services/analytics_service.dart';
import '../services/morning_call_alarm_session.dart';
import '../services/daily_reset_service.dart';
import '../services/widget_sync_service.dart';
import '../services/tasks_sync_service.dart';
import '../services/task_resistance_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'coach_config.dart';
import 'coach_selection_screen.dart';
import 'tasks_screen.dart';
import 'records_screen.dart';
import 'settings_screen.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/scheduled_checkin_icon.dart';

// 각 탭 화면 플레이스홀더
class ChatPlaceholderScreen extends StatelessWidget {
  const ChatPlaceholderScreen({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('💬', style: TextStyle(fontSize: 48)),
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
        Text('📋', style: TextStyle(fontSize: 48)),
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
        Text('📊', style: TextStyle(fontSize: 48)),
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
        Text('⚙️', style: TextStyle(fontSize: 48)),
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
    coachId == 'sec_male' || coachId == 'sec_female';

// ─────────────────────────────────────────────────────────────
// 메인 탭 화면
// ─────────────────────────────────────────────────────────────
class MainTabScreen extends StatefulWidget {
  final String coachId;
  final int initialDrawerIndex;
  final String? initialBottomSheet;
  final String? handoffFromCoachId;
  final bool openTasksOverlayOnStart;
  const MainTabScreen({
    super.key,
    required this.coachId,
    this.initialDrawerIndex = 0,
    this.initialBottomSheet,
    this.handoffFromCoachId,
    this.openTasksOverlayOnStart = false,
  });

  @override
  State<MainTabScreen> createState() => _MainTabScreenState();
}

class _MainTabScreenState extends State<MainTabScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late int _openDrawerIndex; // 0: 채팅, 1: 할일, 2: 기록, 3: 설정
  Map<String, dynamic>? _vacationInfo;
  late TabController _tabCtrl;
  final ChatScreenController _chatController = ChatScreenController();
  final TasksScreenController _tasksController = TasksScreenController();
  bool _coachAccessChecked = false;
  bool _widgetIntentDrawerMode = false;
  bool _redirectingForCoachAccess = false;

  int _logoTapCount = 0;
  Timer? _logoTapTimer;

  void _showDebugPlanSelector() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            '개발자용 플랜 시뮬레이터 🛠️',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.star_border, color: Colors.grey),
                title: Text(
                  '비구독자 상태 (none)',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
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
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
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
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
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
              child: Text(
                '닫기',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
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

    if (_logoTapCount >= 5) {
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
        widget.coachId == 'sec_male' || widget.coachId == 'sec_female';
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
              style: GoogleFonts.notoSansKr(
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
                  context,
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
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        if (friendsCoaches.isNotEmpty) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: Text(
                              '프렌즈 코치',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ...friendsCoaches.map(buildTile),
                          const SizedBox(height: 8),
                        ],
                        if (masterCoaches.isNotEmpty) ...[
                          if (friendsCoaches.isNotEmpty)
                            const Divider(height: 16, color: Color(0xFFF0F0F5)),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            child: Text(
                              '마스터 코치',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          ...masterCoaches.map(buildTile),
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
  Timer? _scheduledCheckInTimer;
  bool hasUnreadScheduledCheckIn = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _lastMorningCallDate;
  final Set<String> _firedCoreReminders = {};
  StreamSubscription? _reminderAudioSub;
  String _chatBgStyle = 'simple';
  StreamSubscription<User?>? _authSubscription;

  Future<void> _loadBgStyle() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _chatBgStyle = prefs.getString('nyang_chat_bg_style') ?? 'simple';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadBgStyle();
    _openDrawerIndex = widget.initialDrawerIndex;
    _widgetIntentDrawerMode = widget.initialDrawerIndex != 0;
    WidgetsBinding.instance.addObserver(this);
    DailyResetService.checkAndExecuteReset();
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
    _tabCtrl = TabController(length: _screens.length, vsync: this);
    _loadVacation();
    _startMorningCallEngine();
    _startCoreReminderEngine();
    _startScheduledCheckInEngine();
    AnalyticsService.logAppOpen();
    _ensureCurrentCoachAccess();
    if (widget.openTasksOverlayOnStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => _WidgetTasksOverlayScreen(
              initialBottomSheet: widget.initialBottomSheet,
            ),
          ),
        );
      });
    }

    // 냥냥코치 웹 앱(Nyang Insight) 연동 등을 통해 실시간으로 Firebase에 추가된 할 일 동기화
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        TasksSyncService.startRealTimeSync(user.uid, () {
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
    _scheduledCheckInTimer?.cancel();
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

  Future<void> _handleAppResumed() async {
    await NotificationService().handleNativeMorningAlarm();
    await DailyResetService.checkAndExecuteReset();
    if (mounted) {
      _tasksController.refresh();
      _chatController.refreshTaskProgress();
      setState(() {});
    }
    final canContinue = await _ensureCurrentCoachAccess(syncCloud: _isMaster);
    if (canContinue) {
      await _checkWidgetIntent();
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

  void _openFeatureLocationFromChat(String location) {
    final taskTabByLocation = {
      'today': 0,
      'goals': 1,
      'schedule': 2,
      'habit': 3,
    };

    if (location == 'records') {
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

  Future<void> _checkWidgetIntent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final widgetRoute = prefs.getString('widget_route');
    final widgetCoachId = prefs.getString('widget_coach_id');

    if (widgetRoute != null || widgetCoachId != null) {
      if (widgetRoute != null) prefs.remove('widget_route');
      if (widgetCoachId != null) prefs.remove('widget_coach_id');

      final isTasksRoute =
          widgetRoute == 'tasks' ||
          widgetRoute == 'tasks_done_bottom_sheet' ||
          widgetRoute == 'tasks_remaining_bottom_sheet';
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
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (_) => _WidgetTasksOverlayScreen(initialBottomSheet: type),
          ),
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
      final currentDate = '${now.year}-${now.month}-${now.day}';
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
              final fireKey =
                  'reminder_${item['id']}_${targetDate.toIso8601String()}_$currentDate';
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

  /// 배지/문자 시스템(코치 채팅창 밖에 있을 때)은 항상 여비서가 담당한다.
  /// 사용자가 실제로 마스터 코치 채팅창 안에 있을 때는 이 함수를 안 타고, 지금 보고 있는
  /// 코치가 대화형 체크인(findPreemptiveInterventionTarget)으로 자연스럽게 처리한다.
  String _resolveMasterCoachId() => 'sec_female';

  void _startScheduledCheckInEngine() {
    _scheduledCheckInTimer = Timer.periodic(const Duration(seconds: 10), (
      timer,
    ) async {
      await TaskResistanceService.checkForScheduledCheckIn(
        masterCoachId: _resolveMasterCoachId(),
      );
      final unread = await TaskResistanceService.hasUnreadScheduledCheckIn();
      if (mounted && unread != hasUnreadScheduledCheckIn) {
        setState(() => hasUnreadScheduledCheckIn = unread);
      }
    });
  }

  /// 배지를 눌렀을 때 호출 — 해당 코치 방으로 이동하고 배지를 지운다.
  Future<void> openScheduledCheckIn() async {
    final coachId = await TaskResistanceService.consumeUnreadScheduledCheckIn();
    if (mounted) setState(() => hasUnreadScheduledCheckIn = false);
    if (coachId == null || !mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => MainTabScreen(coachId: coachId),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
      (route) => false,
    );
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
    } else if ((CoachConfigs.all[targetCoachId]?.voiceCount ?? 0) <= 0) {
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
                style: GoogleFonts.notoSansKr(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${coach.name} 코치가 깨우러 왔어요',
                style: GoogleFonts.notoSansKr(
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
                  style: GoogleFonts.notoSansKr(
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
    if (targetCoachId != 'push' &&
        !CoachConfigs.all.containsKey(targetCoachId)) {
      targetCoachId = 'push';
    }

    if (targetCoachId == 'push') {
      NotificationService().showImmediateNotification(
        title: taskText.isNotEmpty ? '🔔 $taskText' : '🔔 오늘의 핵심 일정',
        body: '핵심 일정을 시작할 시간이에요!',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              taskText.isNotEmpty
                  ? '🔔 [$taskText] 일정을 시작할 시간이에요!'
                  : '🔔 핵심 일정을 시작할 시간이에요!',
            ),
            duration: const Duration(seconds: 5),
            backgroundColor: const Color(0xFF1A1A2E),
          ),
        );
      }
      return;
    }

    final coach = CoachConfigs.get(targetCoachId);

    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    await _audioPlayer.setVolume(1.0);
    _reminderAudioSub?.cancel();

    try {
      await _audioPlayer.play(
        AssetSource('voice/${targetCoachId}_reminder_$advanceMinutes.mp3'),
      );
    } catch (e) {
      debugPrint('Audio play error: $e');
    }

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
                  style: GoogleFonts.notoSansKr(
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
                style: GoogleFonts.notoSansKr(
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
                  style: GoogleFonts.notoSansKr(
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

  Future<void> _loadVacation() async {
    final prefs = await SharedPreferences.getInstance();
    final rawVacation = prefs.getString('nyang_vacation');
    if (mounted) {
      setState(() {
        if (rawVacation != null) {
          _vacationInfo = jsonDecode(rawVacation);
        } else {
          _vacationInfo = null;
        }
      });
    }
  }

  List<Widget> get _screens => [
    ChatScreen(
      coachId: widget.coachId,
      vacationInfo: _vacationInfo,
      controller: _chatController,
      onOpenDrawer: () => setState(() => _openDrawerIndex = 1),
      onOpenGoalVisionDrawer: _openTasksGoalVisionDrawer,
      onOpenFeatureLocation: _openFeatureLocationFromChat,
      onSwitchCoach: _switchCoachFromChat,
      onVacationChanged: () {
        _loadVacation();
      },
      handoffFromCoachId: widget.handoffFromCoachId,
      chatBgStyle: _chatBgStyle,
    ),
    const TasksPlaceholderScreen(),
    RecordsScreen(coachId: widget.coachId),
    SettingsScreen(coachId: widget.coachId),
  ];

  static const _tabLabels = ['채팅', '할 일', '기록', '설정'];

  Color get _tabActiveColor => _activeColor;

  Color get _tabInactiveColor {
    if (_chatBgStyle == 'simple') {
      // 심플 버전 선택되지 않은 탭: 짙은 보라회색
      return const Color(0xFF3A3652);
    }
    if (_isMaster) {
      return const Color(0xFF888899);
    }
    return Colors.white.withOpacity(0.6);
  }

  List<Widget> get _inactiveIcons => [
    _chatBubbleIcon(active: false, color: _tabInactiveColor),
    _clipboardIcon(color: _tabInactiveColor),
    _barChartIcon(color: _tabInactiveColor),
    _gearIcon(active: false, color: _tabInactiveColor),
  ];

  List<Widget> get _activeIcons => [
    _chatBubbleIcon(active: true, color: _tabActiveColor),
    _clipboardIcon(color: _tabActiveColor),
    _barChartIcon(color: _tabActiveColor),
    _gearIcon(active: true, color: _tabActiveColor),
  ];

  bool get _isMaster => _isMasterCoach(widget.coachId);

  Color get _activeColor =>
      _isMaster ? const Color(0xFFD4A017) : const Color(0xFF8B7CFF);

  void _onTabTapped(int index) {
    _loadBgStyle();
    if (index == 0) {
      if (_openDrawerIndex != 0) {
        HapticFeedback.lightImpact();
        setState(() {
          _openDrawerIndex = 0;
          _widgetIntentDrawerMode = false;
        });
        _chatController.refreshTaskProgress();
        // 채팅 탭으로 복귀 시 미뤄둔 할일 리마인드 확인 및 취침시간 이동 제안 확인
        Future.delayed(const Duration(milliseconds: 400), () {
          _chatController.checkDeferredReminder();
          _chatController.checkBedtimeMoveOffer();
        });
      }
      return;
    }
    if (_openDrawerIndex == index) return;
    HapticFeedback.lightImpact();
    setState(() {
      _openDrawerIndex = index;
      _widgetIntentDrawerMode = false;
    });
    if (index == 1) {
      Future.delayed(const Duration(milliseconds: 80), () {
        _tasksController.resetTodayDateSelection();
      });
    }
  }

  Future<void> _closeDrawerAndCheck() async {
    setState(() {
      _openDrawerIndex = 0;
      _widgetIntentDrawerMode = false;
    });
    _chatController.refreshTaskProgress();
    await _loadVacation();
    // 채팅 탭으로 복귀 시 미뤄둔 할일 리마인드 및 취침시간 이동 제안 확인
    Future.delayed(const Duration(milliseconds: 400), () {
      _chatController.checkDeferredReminder();
      _chatController.checkBedtimeMoveOffer();
    });
  }

  // 배경 이미지 경로
  String get _bgImagePath {
    if (_vacationInfo != null) return 'assets/images/vacation_bg.jpg';
    if (_chatBgStyle == 'simple') {
      return 'assets/images/bg_${widget.coachId}_simple.png';
    }
    return 'assets/images/bg_${widget.coachId}.png';
  }

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
    final isSimple = _chatBgStyle == 'simple';

    // 심플 모드일 때는 밝은 배경이므로 검은색 상태바 아이콘 적용
    final systemUiStyle = isSimple
        ? SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: const Color(0xFFFFFCFF),
            systemNavigationBarIconBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemUiStyle,
      child: Stack(
        children: [
          // 배경 전체 (심플 모드 시 단색+물결/원 무늬)
          if (isSimple)
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  color: AppDesignTokens.brandSurface,
                ),
                child: Stack(
                  children: [
                    // 은은한 원 모양 무늬 1
                    Positioned(
                      top: -80,
                      right: -80,
                      child: Container(
                        width: 320,
                        height: 320,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppDesignTokens.brand.withValues(alpha: 0.03),
                        ),
                      ),
                    ),
                    // 은은한 원 모양 무늬 2
                    Positioned(
                      top: 150,
                      right: -30,
                      child: Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppDesignTokens.brand.withValues(
                              alpha: 0.04,
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    // 은은한 원 모양 무늬 3
                    Positioned(
                      bottom: 100,
                      left: -100,
                      child: Container(
                        width: 400,
                        height: 400,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppDesignTokens.brandAccent.withValues(
                            alpha: 0.02,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // 배경 이미지 전체에 깔기 (심플 모드는 캐릭터만 있는 투명 배경)
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
              title: _buildAppBarTitle(isImmersive: true),
              actions: [
                if (hasUnreadScheduledCheckIn)
                  ScheduledCheckInIcon(onTap: openScheduledCheckIn),
                _buildPlannerHelpAction(),
              ],
            ),
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(key: const ValueKey(0), child: _screens[0]),
            ),
            bottomNavigationBar: _NyangBottomTabBar(
              currentIndex: _openDrawerIndex,
              onTap: _onTabTapped,
              labels: _tabLabels,
              inactiveIcons: _inactiveIcons,
              activeIcons: _activeIcons,
              activeColor: _activeColor,
              bgColor: isSimple
                  ? const Color(0xFFFFFCFF)
                  : Colors.black.withOpacity(0.35),
              inactiveColor: _tabInactiveColor,
              isImmersive: !isSimple,
              border: isSimple
                  ? const Border(
                      top: BorderSide(color: Color(0xFFE8E3F8), width: 1.0),
                    )
                  : null,
            ),
          ),
          // 서랍 오버레이 + 패널
          if (_openDrawerIndex != 0) _buildSideDrawer(),
        ],
      ),
    );
  }

  // ── 마스터: 채팅창에만 배경 (기존 레이아웃 유지) ─────────
  Widget _buildMasterLayout() {
    final isVacation = _vacationInfo != null;
    final scaffold = Scaffold(
      backgroundColor:
          Colors.transparent, // Let the background stack show through
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(90),
        child: Stack(
          children: [
            if (isVacation)
              Positioned.fill(child: Container(color: Colors.transparent)),
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
                                  color: isVacation
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
                                  size: 20,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _handleHeaderTap,
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                CoachConfigs.get(widget.coachId).name,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: isVacation
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
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
                                  color: isVacation
                                      ? Colors.white
                                      : const Color(0xFF1A1A2E),
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    _buildPlannerHelpAction(isVacation: isVacation),
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
        child: KeyedSubtree(key: const ValueKey(0), child: _screens[0]),
      ),
      bottomNavigationBar: _NyangBottomTabBar(
        currentIndex: _openDrawerIndex,
        onTap: _onTabTapped,
        labels: _tabLabels,
        inactiveIcons: _inactiveIcons,
        activeIcons: _activeIcons,
        activeColor: AppDesignTokens.brand, // 마스터도 활성은 연보라
        bgColor: isVacation ? Colors.black.withOpacity(0.35) : Colors.white,
        inactiveColor: isVacation
            ? Colors.white.withOpacity(0.6)
            : AppDesignTokens.textDisabled,
        isImmersive: isVacation,
        border: isVacation
            ? null
            : const Border(top: BorderSide(color: AppDesignTokens.divider)),
      ),
    );
    return Stack(
      children: [
        if (isVacation)
          Positioned.fill(
            child: Image.asset(
              'assets/images/vacationmaste_bg.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Container(color: const Color(0xFFDFEEDF)),
            ),
          ),
        if (!isVacation) ...[
          Positioned.fill(child: Container(color: Colors.white)),
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
        if (_openDrawerIndex != 0) _buildSideDrawer(),
      ],
    );
  }

  Widget _buildAppBarTitle({required bool isImmersive}) {
    final isVacation = _vacationInfo != null;
    final nameColor = isVacation
        ? Colors.white
        : (_chatBgStyle == 'simple'
              ? const Color(0xFF3A3652)
              : (isImmersive ? Colors.white : const Color(0xFF1A1A2E)));

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
            style: GoogleFonts.notoSansKr(
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

  Widget _buildPlannerHelpAction({bool isVacation = false}) {
    final foreground = isVacation ? Colors.white : AppDesignTokens.brandMuted;
    final border = isVacation
        ? Colors.white.withOpacity(0.30)
        : AppDesignTokens.brandCardBorder;
    final shadowColor = isVacation
        ? Colors.black.withOpacity(0.16)
        : AppDesignTokens.brand.withOpacity(0.16);

    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Tooltip(
        message: '플래너 활용법',
        child: InkWell(
          onTap: _showPlannerHelpDialog,
          borderRadius: BorderRadius.circular(26),
          child: SizedBox(
            width: 50,
            height: 50,
            child: Center(
              child: Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isVacation
                        ? [
                            Colors.white.withOpacity(0.30),
                            AppDesignTokens.brand.withOpacity(0.32),
                            AppDesignTokens.brand.withOpacity(0.46),
                          ]
                        : const [
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
                      color: Colors.white.withOpacity(isVacation ? 0.14 : 0.70),
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
                          color: Colors.white.withOpacity(
                            isVacation ? 0.20 : 0.74,
                          ),
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
                        style: GoogleFonts.notoSansKr(
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
                          title: '음성으로 일정 등록하기',
                          body:
                              '마이크를 누르고\n'
                              '"내일 오후 3시 회의 추가해줘"\n'
                              '"저녁 7시에 운동 등록해줘"\n'
                              '처럼 \'추가해줘\' 또는 \'등록해줘\'를 붙여 말하면 바로 일정을 등록할 수 있어요.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-reset.svg',
                          title: '오늘의 할 일 리셋',
                          body:
                              '할 일 목록이 매일 리셋되니까 사라졌다고 놀라지 마세요.\n'
                              '설정에서 할 일 리셋 시간을 조율할 수 있고, 다음 날 계획은 할 일 탭 상단 날짜를 누르고 짜시면 돼요.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-comments.svg',
                          title: '하기 싫을 땐 코치에게 말하기',
                          body:
                              '하기 싫은 일이 있을 때 코치에게 언제든 투정해도 돼요.\n'
                              '코치가 다 받아주고 리드해줘요.',
                        ),
                        const SizedBox(height: 18),
                        _buildPlannerHelpSection(
                          iconPath: 'assets/icons/planner-clock.svg',
                          title: '집중 타이머 시작하기',
                          body: '"타이머 좀 띄워줘" 라고 하면 바로 타이머가 튀어나와요.',
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
                              '특히 마스터 코치(비서 코치)들은 사용자의 우선순위와 미룬 항목 등을 파악하면서 더 똑똑하게 대답해줍니다.',
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
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
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

  Widget _buildPlannerHelpSection({
    required String iconPath,
    required String title,
    required String body,
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
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w900,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                body,
                style: GoogleFonts.notoSansKr(
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

  // ── 서랍 (모든 탭 공통) ────────────────────────
  Widget _buildSideDrawer() {
    final useCleanDrawer = _widgetIntentDrawerMode && _openDrawerIndex == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerTopPadding = MediaQuery.of(context).padding.top + 12;
    Widget drawerContent;
    if (_openDrawerIndex == 1) {
      drawerContent = TasksScreen(
        coachId: widget.coachId,
        controller: _tasksController,
        initialBottomSheet: widget.initialBottomSheet,
        onProgressChanged: _chatController.refreshTaskProgress,
        onCoreTaskSet: (msg) {
          // 핵심 설정 완료 시 채팅창에 비서 반응 메시지 주입
          setState(() => _openDrawerIndex = 0);
          _chatController.refreshTaskProgress();
          Future.delayed(
            const Duration(milliseconds: 300),
            () => _chatController.injectAiMessage(msg),
          );
        },
      );
    } else if (_openDrawerIndex == 2) {
      drawerContent = RecordsScreen(coachId: widget.coachId);
    } else if (_openDrawerIndex == 3) {
      drawerContent = SettingsScreen(coachId: widget.coachId);
    } else {
      drawerContent = const SizedBox.shrink();
    }

    return Stack(
      children: [
        if (!useCleanDrawer)
          // 오버레이 (drawer-overlay)
          GestureDetector(
            onTap: () async {
              await _closeDrawerAndCheck();
            },
            child: Container(color: Colors.black.withValues(alpha: 0.5)),
          ),
        // 서랍 패널 (오른쪽에서 슬라이드)
        Positioned(
          top: 0,
          bottom: 0,
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

  Widget _chatBubbleIcon({required bool active, required Color color}) {
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(
        painter: _ChatBubblePainter(active: active, color: color),
      ),
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

// ─────────────────────────────────────────────────────────────
// 하단 탭바
// ─────────────────────────────────────────────────────────────
class _NyangBottomTabBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<String> labels;
  final List<Widget> inactiveIcons;
  final List<Widget> activeIcons;
  final Color activeColor;
  final Color bgColor;
  final Color inactiveColor;
  final bool isImmersive;
  final Border? border;

  const _NyangBottomTabBar({
    required this.currentIndex,
    required this.onTap,
    required this.labels,
    required this.inactiveIcons,
    required this.activeIcons,
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
            children: List.generate(labels.length, (i) {
              final isActive = currentIndex == i;
              return Expanded(
                child: _TabItem(
                  label: labels[i],
                  inactiveIcon: inactiveIcons[i],
                  activeIcon: activeIcons[i],
                  isActive: isActive,
                  activeColor: activeColor,
                  inactiveColor: inactiveColor,
                  onTap: () => onTap(i),
                ),
              );
            }),
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
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.inactiveIcon,
    required this.activeIcon,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
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
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) {
          final color = widget.isActive
              ? widget.activeColor
              : widget.inactiveColor;
          return Opacity(
            opacity: _opacity.value,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 아이콘 (활성화 시 outlined 상태에서 색상만 변경)
                Transform.scale(
                  scale: _scale.value,
                  child: widget.isActive
                      ? ColorFiltered(
                          colorFilter: ColorFilter.mode(
                            widget.activeColor,
                            BlendMode.srcIn,
                          ),
                          child: widget
                              .inactiveIcon, // Use inactive (outline) icon
                        )
                      : widget.inactiveIcon,
                ),
                const SizedBox(height: 2),
                // 레이블
                Text(
                  widget.label,
                  style: GoogleFonts.notoSansKr(
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
class _ChatBubblePainter extends CustomPainter {
  final bool active;
  final Color color;
  _ChatBubblePainter({required this.active, required this.color});

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

    final path = Path()
      ..moveTo(w * 0.1, h * 0.15)
      ..quadraticBezierTo(w * 0.1, h * 0.05, w * 0.2, h * 0.05)
      ..lineTo(w * 0.8, h * 0.05)
      ..quadraticBezierTo(w * 0.9, h * 0.05, w * 0.9, h * 0.15)
      ..lineTo(w * 0.9, h * 0.68)
      ..quadraticBezierTo(w * 0.9, h * 0.78, w * 0.8, h * 0.78)
      ..lineTo(w * 0.38, h * 0.78)
      ..lineTo(w * 0.2, h * 0.96)
      ..lineTo(w * 0.22, h * 0.78)
      ..lineTo(w * 0.2, h * 0.78)
      ..quadraticBezierTo(w * 0.1, h * 0.78, w * 0.1, h * 0.68)
      ..close();

    if (active) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
    } else {
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_ChatBubblePainter old) =>
      old.active != active || old.color != color;
}

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
class _WidgetTasksOverlayScreen extends StatelessWidget {
  final String? initialBottomSheet;
  const _WidgetTasksOverlayScreen({this.initialBottomSheet});

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
                    style: GoogleFonts.notoSansKr(
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
              ),
            ),
          ],
        ),
      ),
    );
  }
}
