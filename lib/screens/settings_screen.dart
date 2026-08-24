import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'coach_config.dart';
import 'landing_screen.dart';
import '../services/account_deletion_service.dart';
import '../services/content_report_service.dart';
import '../services/last_reply_log.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/tasks_sync_service.dart';
import '../models/user_data.dart';
import '../services/widget_sync_service.dart';
import '../services/apple_calendar_sync_service.dart';
import '../services/nyang_banner_nudge.dart';
import '../services/ongoing_task_nudge_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/alarm_permission_notice.dart';

class SettingsScreen extends StatefulWidget {
  final String coachId;
  final bool autoOpenPremiumLearnSettings;
  final ValueChanged<String>? onChatBgStyleChanged;

  /// 열자마자 펼칠 설정 시트. 채팅에서 데려올 때 쓴다.
  ///
  /// 설정 화면만 열어두면 사용자가 목록에서 다시 찾아야 한다. 부탁한 것이
  /// 모닝콜이면 모닝콜 시트까지 열어주는 것이 데려간다는 말에 맞다.
  final String? autoOpenSection;

  const SettingsScreen({
    super.key,
    required this.coachId,
    this.autoOpenPremiumLearnSettings = false,
    this.autoOpenSection,
    this.onChatBgStyleChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// 딴짓 방지 코치가 켜져 있을 때 이 줄을 누르면 고를 수 있는 것.
enum _OngoingNudgeAction { test, turnOff, openSettings }

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  /// 쿠폰 입력을 보여줄지.
  ///
  /// 지금은 닫아둔다. 쓸 수 있는 코드가 앱 안에 글자 그대로 박혀 있어서,
  /// 공개된 앱에서는 'MASTER'라고 치기만 해도 플랜이 켜지는 셈이 된다.
  /// 코드를 서버가 확인해주게 되면 그때 연다.
  static const bool _couponEntryEnabled = false;

  static final Uri _termsUrl = Uri.parse('https://joflowapp.com/terms');
  static final Uri _privacyUrl = Uri.parse('https://joflowapp.com/privacy');
  static final Uri _refundUrl = Uri.parse('https://joflowapp.com/refund');

  String _chatBgStyle = 'simple'; // 'simple' or 'emotional'
  bool _morningCallEnabled = true;
  TimeOfDay _morningCallTime = const TimeOfDay(hour: 7, minute: 0);
  String _morningCallCoachId = 'cat';
  bool _coreReminderEnabled = false;
  int _coreReminderAdvanceMinutes = 10;
  // 진행 중인 일정을 떠올리게 하는 냥냥이. 안드로이드에서만, 테스터가 직접 켠다.
  bool _ongoingNudgeEnabled = false;
  String? _homeWidgetStatus;
  UserData? _userData;
  String? _expandedSettingsSection;
  bool _appleCalendarEnabled = false; // iOS 애플 캘린더 연동 여부
  bool _appleCalendarBusy = false; // 연동 켜기/끄기 진행 중
  // 알람(모닝콜·일정 알람)을 막고 있는 권한. 사용자가 시스템 설정에서 직접 바꿀 수 있으므로
  // 화면에 돌아올 때마다 다시 확인한다.
  AlarmPermissionIssue _alarmPermissionIssue = AlarmPermissionIssue.none;

  bool get _isMaster =>
      widget.coachId == 'nyang_halbae' || widget.coachId == 'sec_female';
  bool get _hasMasterPlan =>
      _userData?.isPlanActive == true && _userData?.planType == 'master';
  bool get _isFreeUser => _userData?.isPlanActive != true;

  /// 채팅에서 데려온 자리를 펼친다.
  ///
  /// 설정값을 다 읽은 뒤라야 시트에 지금 상태가 들어간다. 먼저 열면 꺼져 있는
  /// 것처럼 보이고, 사용자가 그걸 보고 다시 켠다.
  Future<void> _openRequestedSection() async {
    final section = widget.autoOpenSection;
    if (section == null) return;
    await _loadSettings();
    // 권한 상태까지 읽고 연다. 시트 안의 경고 배너가 이 값을 보는데, 먼저
    // 열면 막혀 있어도 멀쩡한 것처럼 보인다.
    await _refreshAlarmPermission();
    if (!mounted) return;
    switch (section) {
      case 'morning_call':
        _showMorningCallSettingsModal();
      case 'core_reminder':
        _showCoreReminderSettingsModal();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    _refreshAlarmPermission();
    if (widget.autoOpenPremiumLearnSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPremiumLearnSettingsModal();
      });
    }
    _openRequestedSection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 시스템 설정 화면에서 권한을 켜고 돌아온 경우를 곧바로 반영한다.
    if (state == AppLifecycleState.resumed) {
      _refreshAlarmPermission();
    }
  }

  Future<void> _refreshAlarmPermission() async {
    final issue = await NotificationService().checkAlarmPermission();
    if (!mounted || issue == _alarmPermissionIssue) return;
    setState(() => _alarmPermissionIssue = issue);
  }

  /// 알람이 켜져 있는데 알림 권한이 없으면 알람이 전혀 울리지 않는다.
  bool get _anyAlarmEnabled => _morningCallEnabled || _coreReminderEnabled;

  bool get _alarmBlocked =>
      _anyAlarmEnabled &&
      _alarmPermissionIssue == AlarmPermissionIssue.notifications;

  /// 소리는 나지만 잠금화면 표시 등이 제한되는 상태.
  bool get _alarmLimited =>
      _anyAlarmEnabled &&
      _alarmPermissionIssue != AlarmPermissionIssue.none &&
      _alarmPermissionIssue != AlarmPermissionIssue.notifications;

  /// 배너·안내 문구에 쓸 알람 이름. 둘 다 켜져 있으면 모닝콜을 먼저 말한다.
  String get _blockedAlarmLabel => _morningCallEnabled ? '모닝콜' : '일정 알람';

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = await UserDataService.load();
    await WidgetSyncService.enforcePlanAccess(
      hasMasterPlan: userData.isPlanActive && userData.planType == 'master',
    );
    if (!userData.isPlanActive) {
      await _disablePaidReminderSettings(prefs);
    }
    final appleCalendarEnabled = await AppleCalendarSyncService.instance
        .isEnabled();
    if (!mounted) return;
    setState(() {
      _userData = userData;
      _appleCalendarEnabled = appleCalendarEnabled;
      _morningCallEnabled =
          prefs.getBool('nyang_morning_call_enabled') ?? false;
      final timeStr = prefs.getString('nyang_morning_call_time') ?? '07:00';
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        _morningCallTime = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 7,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
      final savedMorningCallCoach =
          prefs.getString('nyang_morning_call_coach') ?? 'cat';
      _morningCallCoachId = _notificationVoiceCoachId(
        savedMorningCallCoach,
        fallback: 'cat',
        allowRandom: true,
      );
      _coreReminderEnabled =
          prefs.getBool('nyang_core_reminder_enabled') ?? false;
      _coreReminderAdvanceMinutes =
          prefs.getInt('nyang_core_reminder_advance') ?? 10;
      _ongoingNudgeEnabled =
          prefs.getBool(OngoingTaskNudgeService.enabledKey) ??
          OngoingTaskNudgeService.defaultEnabled;
      _chatBgStyle = prefs.getString('nyang_chat_bg_style') ?? 'simple';
      _homeWidgetStatus = _buildHomeWidgetStatus(
        nyang: prefs.getBool('widget_nyang_enabled') ?? false,
        catCharacter: prefs.getBool('widget_cat_character_enabled') ?? false,
      );
    });
  }

  String? _buildHomeWidgetStatus({
    required bool nyang,
    required bool catCharacter,
  }) {
    final labels = <String>[if (nyang) '미니', if (catCharacter) '가로'];
    return labels.isEmpty ? null : labels.join(' / ');
  }

  Future<void> _disablePaidReminderSettings(SharedPreferences prefs) async {
    await prefs.setBool('nyang_core_reminder_enabled', false);
    await prefs.remove('nyang_core_reminder_resolved_coach');
    await NotificationService().syncCoreReminders();
  }

  void _showFreeSettingsLockedNotice() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('무료 이용자는 모닝콜 설정만 이용할 수 있어요.')));
  }

  /// 알람 설정 결과 안내. 실제 모양은 [showAlarmNoticeDialog]에 있다.
  Future<void> _showAlarmNoticeDialog({
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
    String closeLabel = '확인',
  }) {
    return showAlarmNoticeDialog(
      context,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
      closeLabel: closeLabel,
    );
  }

  VoidCallback _paidSettingsTap(VoidCallback action) {
    return () async {
      final userData = _userData ?? await UserDataService.load();
      if (!mounted) return;
      if (_userData == null) {
        setState(() => _userData = userData);
      }
      if (!userData.isPlanActive) {
        _showFreeSettingsLockedNotice();
        return;
      }
      action();
    };
  }

  Future<TimeOfDay?> _showFocusedTimePicker({
    required BuildContext context,
    required TimeOfDay initialTime,
  }) {
    return showTimePicker(
      context: context,
      initialTime: initialTime,
      barrierColor: Colors.black.withValues(alpha: 0.72),
    );
  }

  Future<void> _showLogoutDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            '로그아웃할까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
          ),
          content: Text(
            '다시 로그인하면 저장된 데이터를 이어서 사용할 수 있어요.',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6B687A),
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                '로그아웃',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFE15B64),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await AuthService().signOut();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingScreen()),
      (_) => false,
    );
  }

  void _showHomeWidgetSettingsModal() async {
    if (_isFreeUser) {
      _showFreeSettingsLockedNotice();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final latestUserData = await UserDataService.load();
    final isMasterPlan =
        latestUserData.isPlanActive && latestUserData.planType == 'master';
    await WidgetSyncService.enforcePlanAccess(hasMasterPlan: isMasterPlan);
    await prefs.setBool('widget_nyang_halbae_enabled', false);
    await prefs.setBool('widget_sec_female_enabled', false);

    bool tempNyang = prefs.getBool('widget_nyang_enabled') ?? false;
    bool tempCatCharacter =
        prefs.getBool('widget_cat_character_enabled') ?? false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> requestWidgetPin(String providerId) async {
              if (Platform.isIOS) {
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '저장됐어요. 홈 화면을 길게 누른 뒤 + 버튼에서 냥냥코치 위젯을 직접 추가해 주세요.',
                    ),
                  ),
                );
                return;
              }

              final didRequestPin = await WidgetSyncService.requestPinWidget(
                providerId,
              );
              if (!mounted) return;

              if (!didRequestPin) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text('이 기기에서는 앱에서 위젯 추가 요청을 띄울 수 없어요.'),
                  ),
                );
              }
            }

            Widget _buildWidgetToggle({
              required String title,
              required String subtitle,
              required bool value,
              required ValueChanged<bool> onChanged,
              required bool isLocked,
              bool isRecommended = false,
            }) {
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F9FB),
                  borderRadius: BorderRadius.circular(16),
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
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isLocked
                                        ? const Color(0xFFC0C0D0)
                                        : const Color(0xFF3D3A4E),
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
                                    color: const Color(0xFFEDE9FF),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '추천',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF6E5AE8),
                                    ),
                                  ),
                                ),
                              ],
                              if (isLocked) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.lock_rounded,
                                  size: 16,
                                  color: Color(0xFFC0C0D0),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isLocked
                                  ? const Color(0xFFC0C0D0)
                                  : const Color(0xFF8E8D9B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    CupertinoSwitch(
                      value: value,
                      activeColor: const Color(0xFF8B7CFF),
                      onChanged: (val) {
                        if (isLocked && val) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('마스터 플랜 전용 기능입니다.')),
                          );
                          return;
                        }
                        onChanged(val);
                      },
                    ),
                  ],
                ),
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const Icon(
                        Icons.widgets_rounded,
                        color: Color(0xFF8B7CFF),
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '홈 화면 위젯 설정',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '앱을 열지 않아도 오늘 할 일과 진행 상황을 바탕화면에서 바로 확인할 수 있어요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: const Color(0xFF8E8D9B),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _buildWidgetToggle(
                    title: '냥냥코치 미니 위젯',
                    subtitle: '남은 할 일을 작게 보기',
                    value: tempNyang,
                    isLocked: false,
                    onChanged: (val) {
                      setModalState(() {
                        tempNyang = val;
                        if (val) {
                          tempCatCharacter = false;
                        }
                      });
                    },
                  ),
                  _buildWidgetToggle(
                    title: '냥냥코치 가로 위젯',
                    subtitle: '냥이와 진행 상황을 넓게 보기',
                    isRecommended: true,
                    value: tempCatCharacter,
                    isLocked: false,
                    onChanged: (val) {
                      setModalState(() {
                        tempCatCharacter = val;
                        if (val) {
                          tempNyang = false;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        await prefs.setBool('widget_nyang_enabled', tempNyang);
                        await prefs.setBool(
                          'widget_cat_character_enabled',
                          tempCatCharacter,
                        );
                        await prefs.setBool(
                          'widget_nyang_halbae_enabled',
                          false,
                        );
                        await prefs.setBool('widget_sec_female_enabled', false);
                        await prefs.setBool(
                          'nyang_home_widget_enabled',
                          tempNyang || tempCatCharacter,
                        );

                        if (mounted) {
                          setState(() {
                            _homeWidgetStatus = _buildHomeWidgetStatus(
                              nyang: tempNyang,
                              catCharacter: tempCatCharacter,
                            );
                          });
                        }

                        final selectedProviderId = tempNyang
                            ? 'cat'
                            : tempCatCharacter
                            ? 'cat_character'
                            : null;

                        await WidgetSyncService.syncFromStoredTasks();

                        if (context.mounted) Navigator.pop(context);
                        if (selectedProviderId != null) {
                          await requestWidgetPin(selectedProviderId);
                        } else if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(
                              content: Text('홈 화면에 남아 있는 위젯은 길게 눌러 삭제해 주세요.'),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
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
                  const Spacer(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveMorningCallSettings(
    bool enabled,
    TimeOfDay time,
    String coachId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    await prefs.setBool('nyang_morning_call_enabled', enabled);
    await prefs.setString('nyang_morning_call_time', timeStr);
    await prefs.setString('nyang_morning_call_coach', coachId);
    TasksSyncService.scheduleSyncToCloud();

    setState(() {
      _morningCallEnabled = enabled;
      _morningCallTime = time;
      _morningCallCoachId = coachId;
    });

    String coachName = '랜덤 코치';
    if (coachId != 'random') {
      coachName = CoachConfigs.get(coachId).name;
    }

    var issue = AlarmPermissionIssue.none;
    if (enabled) {
      // 시스템 권한 창은 두 번 거절당하면 다시 뜨지 않는다. 그래서 요청 결과와
      // 별개로 실제 권한 상태를 다시 확인해, 없으면 설정으로 갈 길을 안내한다.
      await NotificationService().requestNotificationPermissions();
      await NotificationService().scheduleDailyMorningCall(
        hour: time.hour,
        minute: time.minute,
        coachId: coachId,
      );
      issue = await NotificationService().checkAlarmPermission();
    } else {
      await NotificationService().cancelAllMorningCalls();
    }
    if (!mounted) return;
    setState(() => _alarmPermissionIssue = issue);

    if (enabled && issue != AlarmPermissionIssue.none) {
      await showAlarmPermissionDialog(context, issue, alarmLabel: '모닝콜');
      return;
    }
    await _showAlarmNoticeDialog(
      title: enabled ? '⏰ 모닝콜이 설정되었어요' : '⏰ 모닝콜을 껐어요',
      message: enabled ? '$timeStr에 $coachName 모닝콜이 울려요!' : '모닝콜을 껐어요.',
    );
  }

  void _showMorningCallSettingsModal() {
    bool tempEnabled = _morningCallEnabled;
    TimeOfDay tempTime = _morningCallTime;
    String tempCoachId = _morningCallCoachId;
    bool isPickingTime = false;
    AlarmPermissionIssue modalIssue = _alarmPermissionIssue;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.alarm,
                            color: Color(0xFF8B7CFF),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '모닝콜 설정',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: tempEnabled,
                        activeColor: const Color(0xFF8B7CFF),
                        onChanged: (val) =>
                            setModalState(() => tempEnabled = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  if (tempEnabled)
                    buildAlarmPermissionBanner(
                      issue: modalIssue,
                      alarmLabel: '모닝콜',
                      onTap: () async {
                        await showAlarmPermissionDialog(
                          context,
                          modalIssue,
                          alarmLabel: '모닝콜',
                        );
                        final next = await NotificationService()
                            .checkAlarmPermission();
                        if (!mounted) return;
                        setState(() => _alarmPermissionIssue = next);
                        setModalState(() => modalIssue = next);
                      },
                    ),

                  // 시간 선택기
                  Opacity(
                    opacity: tempEnabled ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: () async {
                        if (!tempEnabled) return;
                        setModalState(() => isPickingTime = true);
                        try {
                          final picked = await _showFocusedTimePicker(
                            context: context,
                            initialTime: tempTime,
                          );
                          if (picked != null) {
                            setModalState(() => tempTime = picked);
                          }
                        } finally {
                          if (context.mounted) {
                            setModalState(() => isPickingTime = false);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 20,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F0FF),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '시간',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4B5563),
                              ),
                            ),
                            Text(
                              '${tempTime.hour.toString().padLeft(2, '0')}:${tempTime.minute.toString().padLeft(2, '0')}',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF8B7CFF),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: tempEnabled ? 1.0 : 0.55,
                    child: Text(
                      '휴대폰 설정에 따라 무음/진동 모드나 방해금지 상태에서는 모닝콜 소리가 제한될 수 있어요. 소리로 깨고 싶다면 앱 알림 권한과 알람 볼륨을 미리 확인해주세요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.45,
                        color: const Color(0xFF8E8A9E),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 코치 선택 리스트
                  Text(
                    '모닝콜 코치 선택',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: Opacity(
                      opacity: tempEnabled ? 1.0 : 0.5,
                      child: ListView(
                        children: [
                          // 랜덤 코치
                          _buildMorningCallCoachItem(
                            id: 'random',
                            name: '랜덤 코치 모닝콜',
                            subtitle: '모든 코치 중 한 명이 랜덤으로 깨워줘요',
                            isSelected: tempCoachId == 'random',
                            onTap: () {
                              if (tempEnabled)
                                setModalState(() => tempCoachId = 'random');
                            },
                          ),
                          _buildMorningCallCoachSectionHeader('FRIENDS 코치'),
                          ...CoachConfigs.all.values
                              .where(
                                (coach) =>
                                    coach.tier == 'friends' &&
                                    coach.voiceCount > 0,
                              )
                              .map((coach) {
                                return _buildMorningCallCoachItem(
                                  id: coach.id,
                                  name: coach.name,
                                  subtitle: '',
                                  isSelected: tempCoachId == coach.id,
                                  imagePath: coach.imagePath,
                                  onTap: () {
                                    if (tempEnabled) {
                                      setModalState(
                                        () => tempCoachId = coach.id,
                                      );
                                    }
                                  },
                                );
                              }),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(4, 4, 4, 12),
                            child: Divider(
                              height: 1,
                              thickness: 1,
                              color: Color(0xFFEDEAF8),
                            ),
                          ),
                          _buildMorningCallCoachSectionHeader('MASTER 코치'),
                          ...CoachConfigs.all.values
                              .where(
                                (coach) =>
                                    coach.tier == 'master' &&
                                    coach.voiceCount > 0,
                              )
                              .map((coach) {
                                return _buildMorningCallCoachItem(
                                  id: coach.id,
                                  name: coach.name,
                                  subtitle: '',
                                  isSelected: tempCoachId == coach.id,
                                  imagePath: coach.imagePath,
                                  onTap: () {
                                    if (tempEnabled) {
                                      setModalState(
                                        () => tempCoachId = coach.id,
                                      );
                                    }
                                  },
                                );
                              }),
                        ],
                      ),
                    ),
                  ),

                  // 저장 버튼
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    child: isPickingTime
                        ? const SizedBox(key: ValueKey('time-picker-open'))
                        : SizedBox(
                            key: const ValueKey('save-morning-call'),
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _saveMorningCallSettings(
                                  tempEnabled,
                                  tempTime,
                                  tempCoachId,
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A1A2E),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
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
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveCoreReminderSettings(
    bool enabled,
    int advanceMinutes,
  ) async {
    final userData = await UserDataService.load();
    final prefs = await SharedPreferences.getInstance();
    if (!userData.isPlanActive) {
      await _disablePaidReminderSettings(prefs);
      if (mounted) {
        setState(() {
          _coreReminderEnabled = false;
          _coreReminderAdvanceMinutes = 10;
        });
        _showFreeSettingsLockedNotice();
      }
      return;
    }
    await prefs.setBool('nyang_core_reminder_enabled', enabled);
    await prefs.setString('nyang_core_reminder_coach', 'push');
    await prefs.setInt('nyang_core_reminder_advance', advanceMinutes);
    TasksSyncService.scheduleSyncToCloud();

    setState(() {
      _coreReminderEnabled = enabled;
      _coreReminderAdvanceMinutes = advanceMinutes;
    });

    NotificationService().syncCoreReminders();

    // 모닝콜과 똑같이, 켠 직후에 실제로 울릴 수 있는 상태인지 확인한다.
    // 시스템 권한 창은 두 번 거절당하면 다시 뜨지 않으므로 요청 결과와 별개로 다시 본다.
    var issue = AlarmPermissionIssue.none;
    if (enabled) {
      await NotificationService().requestNotificationPermissions();
      issue = await NotificationService().checkAlarmPermission();
    }
    if (!mounted) return;
    setState(() => _alarmPermissionIssue = issue);

    if (enabled && issue != AlarmPermissionIssue.none) {
      await showAlarmPermissionDialog(
        context,
        issue,
        alarmLabel: '일정 알람',
        emoji: '🔔',
      );
      return;
    }

    await _showAlarmNoticeDialog(
      title: enabled ? '🔔 일정 푸쉬 알람이 설정되었어요' : '🔔 일정 푸쉬 알람을 껐어요',
      message: enabled
          ? '일정 시작 $advanceMinutes분 전에 알려드릴게요!'
          : '이제 일정 푸쉬 알람이 울리지 않아요.',
    );
  }

  /// 딴짓 방지 코치 켜고 끄기.
  ///
  /// 안드로이드는 "다른 앱 위에 표시" 권한이, 아이폰은 라이브 액티비티 허용이
  /// 있어야 한다. 둘 다 팝업으로 물을 수 없어서, 켜는 순간 설명을 먼저 읽히고
  /// 시스템 설정으로 보낸다. 없으면 켜도 아무것도 나타나지 않기 때문이다.
  Future<void> _toggleOngoingNudge() async {
    final isAndroid = Platform.isAndroid;

    // 켜져 있는 동안에는 바로 끄지 않고 무엇을 할지 묻는다. 30분을 기다려야
    // 확인되는 기능이라, 지금 한번 보는 길이 설정 안에 있어야 한다.
    if (_ongoingNudgeEnabled) {
      final action = await _askOngoingNudgeAction();
      if (action == null || !mounted) return;

      // 아이폰: 앱에서 켜도 아이폰 설정의 "실시간 활동"이 꺼져 있으면 아무것도
      // 뜨지 않는다. 그런데 그 사실을 확인할 길도, 거기로 가는 길도 앱 안에
      // 없었다. 켜져 있다고 적힌 화면만 보면서 왜 안 뜨는지 알 수 없었다.
      if (action == _OngoingNudgeAction.openSettings) {
        await OngoingTaskNudgeService.openSystemSettings();
        return;
      }

      if (action == _OngoingNudgeAction.test && !isAndroid) {
        // 아이폰 배너는 정해둔 시각이 와야 확인된다. 기다렸다 안 오면 무엇이
        // 막고 있는지 알 길이 없어서, 지금 보는 길을 여기 둔다.
        if (!await NotificationService().areNotificationsEnabled()) {
          if (!mounted) return;
          await _showAlarmNoticeDialog(
            title: '🔔 알림이 꺼져 있어요',
            message: '냥냥이 배너는 알림으로 찾아가요. 알림이 꺼져 있으면 오지 않습니다.',
            actionLabel: '설정 열기',
            closeLabel: '나중에',
            onAction: () async {
              await OngoingTaskNudgeService.openSystemSettings();
            },
          );
          return;
        }
        await NyangBannerNudge.showTest();
        if (!mounted) return;
        await _showAlarmNoticeDialog(
          title: '🐾 8초 뒤에 나타나요',
          message:
              '지금 홈으로 나가거나 다른 앱을 열어보세요. 화면 위로 냥냥이 배너가 '
              '내려옵니다.\n\n'
              '배너를 길게 누르거나 아래로 당기면 "시작할게"와 "좀 더 있다가"가 '
              '나와요. 그냥 누르면 앱이 열려요.',
        );
        return;
      }

      if (action == _OngoingNudgeAction.test) {
        // 막고 있는 게 있으면 먼저 말해준다. 그냥 안 나오면 어디가 문제인지
        // 알 길이 없어서, 기다린 사람만 헛수고한다.
        final blocked = await _describeOngoingNudgeBlockers();
        if (!mounted) return;
        if (blocked != null) {
          await _showAlarmNoticeDialog(
            title: '🐾 지금은 나올 수 없어요',
            message: blocked,
            actionLabel: '설정 열기',
            closeLabel: '나중에',
            onAction: () async {
              if (!await OngoingTaskNudgeService.isAvailable()) {
                await OngoingTaskNudgeService.openSystemSettings();
              } else {
                await OngoingTaskNudgeService.openBatterySettings();
              }
            },
          );
          return;
        }

        await OngoingTaskNudgeService.showTestNudge();
        if (!mounted) return;
        await _showAlarmNoticeDialog(
          title: '🐾 앱을 나가면 나타나요',
          message:
              '지금 홈으로 나가거나 다른 앱을 열어보세요. 몇 초 안에 화면 '
              '가장자리에 냥냥이가 나옵니다.\n\n'
              '냥냥코치 안에 머물러 있으면 나오지 않아요. 2분 동안 기다리다가 '
              '그래도 안 나가면 스스로 그만둡니다.',
        );
        return;
      }
    }

    final turningOn = !_ongoingNudgeEnabled;
    await OngoingTaskNudgeService.setEnabled(turningOn);
    if (!mounted) return;
    setState(() => _ongoingNudgeEnabled = turningOn);

    if (!turningOn) {
      await _showAlarmNoticeDialog(
        title: '🐾 딴짓 방지 코치를 껐어요',
        message: isAndroid
            ? '이제 다른 앱을 볼 때 냥냥이가 나타나지 않아요.'
            : '이제 잠금화면에 진행 중인 일정이 표시되지 않아요.',
      );
      return;
    }

    // 라이브 액티비티가 필요한 것은 다이내믹 아일랜드가 있는 아이폰뿐이다.
    // 없는 기종은 배너가 대신하므로, 실시간 활동을 켜달라고 할 이유가 없다.
    final needsLiveActivity =
        isAndroid || await OngoingTaskNudgeService.showsOverOtherApps();
    if (needsLiveActivity && !await OngoingTaskNudgeService.isAvailable()) {
      if (!mounted) return;
      await _showAlarmNoticeDialog(
        title: isAndroid ? '🐾 다른 앱 위에 표시를 켜주세요' : '🐾 실시간 활동을 켜주세요',
        message: isAndroid
            ? '이 권한이 없으면 냥냥이가 다른 앱 위로 나올 수 없어요.\n\n'
                  '설정에서 냥냥코치를 찾아 "다른 앱 위에 표시"를 켜주세요.'
            : '이 설정이 꺼져 있으면 잠금화면에 아무것도 뜨지 않아요.\n\n'
                  '설정에서 냥냥코치를 찾아 "실시간 활동"을 켜주세요.',
        actionLabel: '설정 열기',
        closeLabel: '나중에',
        onAction: () async {
          await OngoingTaskNudgeService.openSystemSettings();
        },
      );
      return;
    }

    // 알림이 꺼져 있으면 이 기능은 반쪽이 된다. 안드로이드는 냥냥이가 떠 있는
    // 동안 조용한 알림 한 줄이 함께 있어야 하고, 아이폰 배너는 알림 그 자체다.
    // 처음 물었을 때 거절했으면 시스템은 다시 묻지 않으므로 설정으로 데려간다.
    // 켰다는 인사보다 먼저 한다 — 이게 막혀 있으면 인사가 지키지 못할 약속이 된다.
    if (!await NotificationService().areNotificationsEnabled()) {
      if (!mounted) return;
      await _showAlarmNoticeDialog(
        title: '🔔 알림을 켜주세요',
        message: isAndroid
            ? '냥냥코치 알림이 꺼져 있어요.\n\n'
                  '냥냥이가 나와 있는 동안 조용한 알림 한 줄이 함께 있어야 해서, '
                  '알림이 꺼져 있으면 나올 수 없어요.'
            : '냥냥코치 알림이 꺼져 있어요.\n\n'
                  '이 아이폰은 냥냥이가 배너로 찾아가는데, 알림이 꺼져 있으면 '
                  '그 배너가 오지 않아요.',
        actionLabel: '설정 열기',
        closeLabel: '나중에',
        onAction: () async {
          await OngoingTaskNudgeService.openSystemSettings();
        },
      );
      if (!mounted) return;
    }

    // 배너로 찾아가는 아이폰은 인사와 안내가 한 장이다. 배너가 얼마나 머무를지는
    // 앱이 아니라 배너 스타일 설정이 정하므로, 그 길을 여기서 함께 낸다.
    // 이미 "지속"으로 해둔 사람에게는 부탁할 것이 없다.
    final needsBanner =
        await NyangBannerNudge.isNeededHere() &&
        !await OngoingTaskNudgeService.isBannerPersistent();
    if (!mounted) return;

    await _showAlarmNoticeDialog(
      title: '🐾 딴짓 방지 코치를 켰어요',
      message: isAndroid
          ? '일정을 시작하고 30분이 지난 뒤, 폰으로 다른 걸 보고 있으면 '
                '냥냥이가 화면 가장자리에 잠깐 나타나요.\n\n'
                '시작할 시각을 정해둔 일정은 그 시각에도 나타나요. '
                '시작하는 걸 잊었을 때요.\n\n'
                '소리도 진동도 없고, 그냥 두면 스스로 사라져요.'
          : await _iosNudgeDescription(),
      actionLabel: needsBanner ? '배너 설정 열기' : null,
      closeLabel: needsBanner ? '나중에' : '확인',
      onAction: needsBanner
          ? () async {
              await OngoingTaskNudgeService.openNotificationSettings();
            }
          : null,
    );

    // 절전이 걸려 있으면 냥냥이가 제때 못 나간다. 켠 직후 한 번만 짚어준다.
    if (!mounted) return;
    if (await OngoingTaskNudgeService.isBatterySleepRestricted()) {
      if (!mounted) return;
      await _showAlarmNoticeDialog(
        title: '🔋 한 가지만 더 확인해주세요',
        message:
            '지금 설정으로는 휴대폰이 냥냥코치를 재워둘 수 있어요. '
            '그러면 냥냥이가 늦게 나타나거나 아예 나타나지 않아요.\n\n'
            '배터리 설정에서 냥냥코치를 찾아 "제한 없음"으로 바꿔주세요.',
        actionLabel: '설정 열기',
        closeLabel: '나중에',
        onAction: () async {
          await OngoingTaskNudgeService.openBatterySettings();
        },
      );
    }
  }

  /// 냥냥이를 막고 있는 것이 있으면 사람이 읽을 문장으로. 없으면 null.
  Future<String?> _describeOngoingNudgeBlockers() async {
    final state = await OngoingTaskNudgeService.diagnose();
    if (state.isEmpty) return null;

    if (state['overlay'] == false) {
      return '"다른 앱 위에 표시" 권한이 꺼져 있어요.\n\n'
          '이 권한이 없으면 냥냥이가 다른 앱 위로 나올 수 없습니다. '
          '설정에서 냥냥코치를 찾아 켜주세요.';
    }
    if (state['notifications'] == false) {
      return '냥냥코치 알림이 꺼져 있어요.\n\n'
          '냥냥이가 나오는 동안 조용한 알림 한 줄이 함께 있어야 해서, '
          '알림이 꺼져 있으면 나올 수 없습니다.';
    }
    if (state['batteryRestricted'] == true) {
      return '휴대폰이 냥냥코치를 재워둘 수 있는 상태예요.\n\n'
          '지금 확인은 될 수도 있지만, 평소에는 냥냥이가 늦게 나오거나 '
          '아예 나오지 않습니다. 배터리 설정에서 "제한 없음"으로 바꿔주세요.';
    }
    return null;
  }

  /// 아이폰에서 이 기능이 실제로 무엇을 해주는지.
  ///
  /// 기종에 따라 하는 일이 다르다. 다이내믹 아일랜드가 있으면 딴짓 중에도 눈에
  /// 들어오지만, 없으면 잠금화면에서만 보인다 — 그건 딴짓을 막아주는 것이 아니라
  /// 진행 중이라는 표시다. 같은 문구로 안내하면 한쪽에게는 지키지 못할 약속이 된다.
  Future<String> _iosNudgeDescription() async {
    // 배너는 어느 아이폰에나 간다. 다이내믹 아일랜드가 있는 기종은 거기에 더해
    // 알약이 계속 보일 뿐이다.
    final banner =
        '시작할 시각이 되면, 그리고 시작하고 30분이 지나면 화면 위로 '
        '"냥냥이 배너"가 내려와요. 눌러서 바로 앱으로 올 수 있어요.'
        // 이미 "지속"으로 해둔 사람에게는 이 줄이 군더더기다.
        '${await OngoingTaskNudgeService.isBannerPersistent() ? '' : '\n\n'
            '배너가 금방 사라지지 않게 하려면 배너 스타일을 "지속"으로 '
            '바꿔주세요.'}';

    if (await OngoingTaskNudgeService.showsOverOtherApps()) {
      return '일정이 도는 동안에는 다른 앱을 봐도 화면 맨 위에 냥냥이가 작게 '
          '남아 있어요.\n\n$banner';
    }
    // 이 기종은 배너가 전부다. 잠금화면에도 뜨긴 하지만 그건 딴짓을 막아주지
    // 않으니 여기서 말하지 않는다 — 켜는 사람이 기대할 것은 딴짓하는 중에
    // 일어나는 일이어야 한다.
    return '이 아이폰은 다른 앱 위에 냥냥이를 띄울 수 없어서, 딴짓할 때 '
        '배너로 찾아가요.\n\n$banner';
  }

  /// 켜져 있는 동안 이 줄을 눌렀을 때 무엇을 할지.
  Future<_OngoingNudgeAction?> _askOngoingNudgeAction() async {
    final isAndroid = Platform.isAndroid;
    final available = isAndroid || await OngoingTaskNudgeService.isAvailable();
    final description = isAndroid ? '' : await _iosNudgeDescription();
    // 배너로 찾아가는 아이폰은 여기서도 "지금 한번 보기"를 준다. 시각을 기다렸다
    // 안 오면 무엇이 막고 있는지 알 길이 없기 때문이다.
    final needsBanner = await NyangBannerNudge.isNeededHere();
    if (!mounted) return null;

    return showDialog<_OngoingNudgeAction>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '🐾 딴짓 방지 코치',
            style: GoogleFonts.notoSansKr(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF3D3A4E),
            ),
          ),
          content: Text(
            isAndroid
                ? '지금 켜져 있어요. 일정을 시작하고 30분이 지난 뒤, 폰으로 다른 걸 '
                      '보고 있으면 나타납니다.'
                : needsBanner
                ? '지금 켜져 있어요.\n\n$description'
                : available
                ? '지금 켜져 있어요.\n\n$description'
                : '앱에서는 켜져 있는데, 아이폰 설정의 "실시간 활동"이 꺼져 있어요.\n\n'
                      '그래서 일정을 시작해도 화면 위에 아무것도 뜨지 않습니다.',
            style: GoogleFonts.notoSansKr(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6B6676),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, _OngoingNudgeAction.turnOff),
              child: Text(
                '끄기',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF9B96A8),
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                ctx,
                isAndroid || needsBanner
                    ? _OngoingNudgeAction.test
                    : _OngoingNudgeAction.openSettings,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B7CFF),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isAndroid || needsBanner
                    ? '지금 한번 보기'
                    : available
                    ? '아이폰 설정 열기'
                    : '실시간 활동 켜러 가기',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showCoreReminderSettingsModal() {
    if (_isFreeUser) {
      _showFreeSettingsLockedNotice();
      return;
    }
    bool tempEnabled = _coreReminderEnabled;
    int tempAdvance = _coreReminderAdvanceMinutes;
    AlarmPermissionIssue modalIssue = _alarmPermissionIssue;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.48,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.notifications_none,
                            color: Color(0xFF8B7CFF),
                            size: 24,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '일정 푸쉬 알람',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF1A1A2E),
                            ),
                          ),
                        ],
                      ),
                      CupertinoSwitch(
                        value: tempEnabled,
                        activeColor: const Color(0xFF8B7CFF),
                        onChanged: (val) =>
                            setModalState(() => tempEnabled = val),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '원하는 일정을 알려드려요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFA78BFA),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (tempEnabled)
                    buildAlarmPermissionBanner(
                      issue: modalIssue,
                      alarmLabel: '일정 알람',
                      onTap: () async {
                        await showAlarmPermissionDialog(
                          context,
                          modalIssue,
                          alarmLabel: '일정 알람',
                          emoji: '🔔',
                        );
                        final next = await NotificationService()
                            .checkAlarmPermission();
                        if (!mounted) return;
                        setState(() => _alarmPermissionIssue = next);
                        setModalState(() => modalIssue = next);
                      },
                    ),

                  // 알람 시간 선택
                  Opacity(
                    opacity: tempEnabled ? 1.0 : 0.5,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '알람 시간 선택',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          Container(
                            width: 168,
                            height: 40,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F0FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [10, 30].map((minutes) {
                                final isActive = tempAdvance == minutes;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      if (tempEnabled) {
                                        setModalState(
                                          () => tempAdvance = minutes,
                                        );
                                      }
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: isActive
                                            ? const Color(0xFF8B7CFF)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Text(
                                        '$minutes분 전',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: isActive
                                              ? Colors.white
                                              : const Color(0xFF6B7280),
                                        ),
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

                  const Spacer(),

                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _saveCoreReminderSettings(tempEnabled, tempAdvance);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A2E),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
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

  Widget _buildMorningCallCoachSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF9CA3AF),
        ),
      ),
    );
  }

  Widget _buildMorningCallCoachItem({
    required String id,
    required String name,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    bool isLocked = false,
    String? imagePath,
  }) {
    return GestureDetector(
      onTap: isLocked ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isLocked
              ? const Color(0xFFF3F4F6)
              : (isSelected ? const Color(0xFFF3F0FF) : Colors.white),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF8B7CFF)
                : const Color(0xFFE5E7EB),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Opacity(
          opacity: isLocked ? 0.5 : 1.0,
          child: Row(
            children: [
              if (id == 'random')
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else if (id == 'push')
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.notifications_active,
                    color: Color(0xFF9CA3AF),
                    size: 24,
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    image: DecorationImage(
                      image: AssetImage(imagePath!),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? const Color(0xFF8B7CFF)
                            : const Color(0xFF1A1A2E),
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isLocked)
                const Icon(Icons.lock, color: Color(0xFF9CA3AF), size: 24)
              else
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? const Color(0xFF8B7CFF)
                          : const Color(0xFFE5E7EB),
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: isSelected
                      ? Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Color(0xFF8B7CFF),
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isMaster ? Colors.transparent : Colors.white;

    return Container(
      color: bgColor,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Transform.translate(
          offset: const Offset(0, -18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 타이틀
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                child: Row(
                  children: [
                    const Icon(Icons.settings, color: Colors.black, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      '설정',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                  ],
                ),
              ),
              // 설정 리스트
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                  child: Column(
                    children: [
                      _buildSettingsNavigationTile(
                        icon: Icons.person_rounded,
                        label: '내 프로필',
                        status:
                            '$_planStatusLabel · ${_userData?.points ?? 0}P',
                        onTap: _paidSettingsTap(_showProfileSheet),
                        leadingCircle: true,
                      ),
                      const SizedBox(height: 10),

                      // 알림보다 위에 둔다. 이 앱이 하겠다는 일이 딴짓을
                      // 막아주는 것이라, 설정을 열었을 때 제일 먼저 보여야 한다.
                      if (OngoingTaskNudgeService.isSupported) ...[
                        _buildSettingsNavigationTile(
                          svgAsset: 'assets/icons/shield-cat.svg',
                          label: '딴짓 방지 코치',
                          subtitle: '앱 밖으로 새면 냥냥이가 살짝 챙겨줘요.',
                          status: _ongoingNudgeEnabled ? '켜짐' : '꺼짐',
                          onTap: _paidSettingsTap(_toggleOngoingNudge),
                        ),
                        const SizedBox(height: 10),
                      ],

                      _buildSettingsSectionTile(
                        id: 'notifications',
                        icon: Icons.notifications_none_rounded,
                        label: '알림',
                        status: _notificationSectionStatus,
                        children: [
                          _buildSettingsDetailRow(
                            icon: Icons.alarm_rounded,
                            label: '모닝콜',
                            status: _morningCallStatus ?? '꺼짐',
                            onTap: _showMorningCallSettingsModal,
                          ),
                          _buildSettingsDetailRow(
                            icon: Icons.notifications_none_rounded,
                            label: '일정 알림',
                            status: _coreReminderStatus ?? '꺼짐',
                            onTap: _paidSettingsTap(
                              _showCoreReminderSettingsModal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      _buildSettingsSectionTile(
                        id: 'display',
                        icon: Icons.tune_rounded,
                        label: '화면 및 사용',
                        status: _displaySectionStatus,
                        children: [
                          _buildSettingsDetailRow(
                            icon: Icons.widgets_rounded,
                            label: '홈 화면 위젯',
                            status: _homeWidgetStatus ?? '미사용',
                            onTap: _paidSettingsTap(
                              _showHomeWidgetSettingsModal,
                            ),
                          ),
                          if (!_isMaster)
                            _buildSettingsDetailRow(
                              icon: Icons.wallpaper_rounded,
                              label: '채팅 배경',
                              status: _chatBgStyle == 'emotional'
                                  ? '감성 버전'
                                  : '심플 버전',
                              onTap: _paidSettingsTap(_showBgStylePicker),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      _buildSettingsNavigationTile(
                        icon: Icons.psychology_rounded,
                        label: '비서 학습 설정',
                        status: 'MASTER 전용',
                        subtitle: '고정 일정과 취침 시간을 설정해요.',
                        onTap: () {
                          if (_hasMasterPlan) {
                            _showPremiumLearnSettingsModal();
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('비서 학습 설정은 마스터 플랜 구독자 전용입니다.'),
                            ),
                          );
                        },
                      ),
                      // 외부 연동은 아이폰(애플 캘린더) 전용이라 iOS에서만 노출한다.
                      // 안드로이드 구글 캘린더 연동은 지원 확정 후 별도로 추가.
                      if (Platform.isIOS) ...[
                        const SizedBox(height: 10),
                        _buildSettingsSectionTile(
                          id: 'external',
                          svgAsset: 'assets/icons/plug.svg',
                          label: '외부 연동',
                          status: _appleCalendarEnabled ? '연동됨' : '꺼짐',
                          children: [
                            _buildSettingsDetailRow(
                              svgAsset: 'assets/icons/calendar-days.svg',
                              label: '아이폰 캘린더 연동',
                              status: _appleCalendarBusy
                                  ? '처리 중'
                                  : (_appleCalendarEnabled ? '연동됨' : '꺼짐'),
                              onTap: _toggleAppleCalendar,
                            ),
                            // TODO: 구글 캘린더 연동 항목은 지원 확정 후 여기에 추가
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),

                      _buildSettingsNavigationTile(
                        icon: Icons.policy_outlined,
                        label: '약관 및 개인정보',
                        onTap: _showLegalLinksSheet,
                      ),
                      const SizedBox(height: 10),

                      _buildSettingsNavigationTile(
                        icon: Icons.flag_outlined,
                        label: '코치 답변 신고',
                        subtitle: '마지막으로 받은 답변을 그대로 보고 신고할 수 있어요.',
                        onTap: _showLastReplyDialog,
                      ),
                      const SizedBox(height: 20),

                      _buildLogoutButton(),
                      _buildDeleteAccountButton(),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _notificationSectionStatus {
    // 켜져 있어도 울리지 않는 상태라면 "켜짐"이라고 말하지 않는다.
    if (_alarmBlocked) return '$_blockedAlarmLabel 안 울림';
    if (_alarmLimited) return '$_blockedAlarmLabel 권한 확인';
    final enabledCount = [
      _morningCallEnabled,
      _coreReminderEnabled,
    ].where((enabled) => enabled).length;
    if (enabledCount == 0) return '꺼짐';
    if (enabledCount == 1) {
      return _morningCallEnabled ? '모닝콜 켜짐' : '일정 알림 켜짐';
    }
    return '2개 켜짐';
  }

  String get _displaySectionStatus {
    final active = <String>[];
    if (_homeWidgetStatus != null) active.add('위젯');
    active.add(_chatBgStyle == 'emotional' ? '감성 배경' : '심플 배경');
    return active.first;
  }

  Widget _buildSettingsNavigationTile({
    IconData? icon,
    String? svgAsset,
    required String label,
    required VoidCallback onTap,
    String? subtitle,
    String? status,
    bool leadingCircle = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1),
        ),
        child: Row(
          children: [
            leadingCircle
                ? Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0xFFB6A4FF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, color: Colors.white, size: 18),
                  )
                : _buildSettingLeadingGlyph(
                    icon: icon,
                    svgAsset: svgAsset,
                    color: const Color(0xFF8B7CFF),
                    size: 20,
                  ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF9A96A8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (status != null) ...[
              _buildSettingStatusBadge(status),
              const SizedBox(width: 6),
            ],
            const Icon(
              Icons.chevron_right_rounded,
              size: 22,
              color: Color(0xFF8E8A9E),
            ),
          ],
        ),
      ),
    );
  }

  /// 설정 행 앞 글리프. svgAsset이 있으면 폰트어썸 SVG를, 없으면 Material 아이콘을 그린다.
  Widget _buildSettingLeadingGlyph({
    IconData? icon,
    String? svgAsset,
    required Color color,
    required double size,
  }) {
    if (svgAsset != null) {
      // 폰트어썸 solid 아이콘은 여백 없이 꽉 차 Material 아이콘보다 커 보이므로
      // 살짝 줄여서 크기감을 맞추고, 원래 size 박스 안에 중앙 정렬해 정렬을 유지한다.
      final glyphSize = size * 0.8;
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: SvgPicture.asset(
            svgAsset,
            width: glyphSize,
            height: glyphSize,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          ),
        ),
      );
    }
    return Icon(icon, color: color, size: size);
  }

  Widget _buildSettingsSectionTile({
    required String id,
    IconData? icon,
    String? svgAsset,
    required String label,
    required String status,
    required List<Widget> children,
  }) {
    final expanded = _expandedSettingsSection == id;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? const Color(0xFFD8D0FA) : const Color(0xFFE8E3F8),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _expandedSettingsSection = expanded ? null : id;
              });
            },
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(
                children: [
                  _buildSettingLeadingGlyph(
                    icon: icon,
                    svgAsset: svgAsset,
                    color: const Color(0xFF8B7CFF),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                  ),
                  _buildSettingStatusBadge(status),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      size: 22,
                      color: Color(0xFF8E8A9E),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Column(
              children: [
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Color(0xFFF0EDF8),
                ),
                ...children,
              ],
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 160),
            sizeCurve: Curves.easeOut,
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsDetailRow({
    IconData? icon,
    String? svgAsset,
    required String label,
    required String status,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
        child: Row(
          children: [
            _buildSettingLeadingGlyph(
              icon: icon,
              svgAsset: svgAsset,
              color: const Color(0xFFB6A4FF),
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4B465C),
                ),
              ),
            ),
            _buildSettingStatusBadge(status),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFFB8B5C8),
            ),
          ],
        ),
      ),
    );
  }

  // 아이폰(애플) 캘린더 단방향 연동을 켜고 끈다.
  Future<void> _toggleAppleCalendar() async {
    if (_appleCalendarBusy) return;
    final service = AppleCalendarSyncService.instance;
    final messenger = ScaffoldMessenger.of(context);

    if (_appleCalendarEnabled) {
      final confirmed = await _confirmDisableAppleCalendar();
      if (confirmed != true) return;
      setState(() => _appleCalendarBusy = true);
      try {
        await service.disable();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _appleCalendarEnabled = false;
        _appleCalendarBusy = false;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text('아이폰 캘린더 연동을 해제했어요.')),
      );
      return;
    }

    setState(() => _appleCalendarBusy = true);
    messenger.showSnackBar(
      const SnackBar(content: Text('아이폰 캘린더에 연동하는 중이에요…')),
    );
    AppleCalendarEnableResult result;
    try {
      result = await service.enable();
    } catch (_) {
      result = AppleCalendarEnableResult.failed;
    }
    if (!mounted) return;
    setState(() {
      _appleCalendarEnabled = result == AppleCalendarEnableResult.success;
      _appleCalendarBusy = false;
    });
    messenger.hideCurrentSnackBar();
    switch (result) {
      case AppleCalendarEnableResult.success:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('아이폰 캘린더에 연동했어요. 캘린더 앱에서 "냥냥코치" 달력을 확인해보세요.'),
          ),
        );
      case AppleCalendarEnableResult.permissionDenied:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('캘린더 접근 권한이 필요해요. 설정 > 냥냥코치에서 캘린더를 허용해주세요.'),
          ),
        );
      case AppleCalendarEnableResult.unsupported:
      case AppleCalendarEnableResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('연동에 실패했어요. 잠시 후 다시 시도해주세요.')),
        );
    }
  }

  Future<bool?> _confirmDisableAppleCalendar() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '연동을 해제할까요?',
            style: GoogleFonts.notoSansKr(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF3D3A4E),
            ),
          ),
          content: Text(
            '아이폰 캘린더의 "냥냥코치" 달력과 그 안의 일정이 모두 삭제돼요. (냥냥코치 앱의 일정은 그대로예요.)',
            style: GoogleFonts.notoSansKr(
              fontSize: 13.5,
              height: 1.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF6B6676),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A96A8),
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                '해제',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF8B7CFF),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBgStylePicker() async {
    final styles = ['simple', 'emotional'];
    final labels = ['심플 버전', '감성 버전'];
    int selectedIndex = styles.indexOf(_chatBgStyle);
    if (selectedIndex == -1) selectedIndex = 0;

    final controller = FixedExtentScrollController(initialItem: selectedIndex);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 280,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Text(
                        '채팅 배경 선택',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final selectedStyle = styles[selectedIndex];
                          setState(() => _chatBgStyle = selectedStyle);
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setString(
                            'nyang_chat_bg_style',
                            selectedStyle,
                          );
                          widget.onChatBgStyleChanged?.call(selectedStyle);
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: Text(
                          '완료',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF8B7CFF),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 44,
                    magnification: 1.08,
                    useMagnifier: true,
                    selectionOverlay: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 36),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F0FF).withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSelectedItemChanged: (index) => selectedIndex = index,
                    children: List.generate(labels.length, (index) {
                      return Center(
                        child: Text(
                          labels[index],
                          style: GoogleFonts.notoSansKr(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF3D3A4E),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingStatusBadge(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 136),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EAFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF7D68DE),
          ),
        ),
      ),
    );
  }

  String get _planStatusLabel {
    final data = _userData;
    if (data == null || !data.isPlanActive) return '미구독';
    if (data.planType == 'master') return 'MASTER';
    if (data.planType == 'friends') return 'FRIENDS';
    return '미구독';
  }

  String get _morningCallStatusLabel {
    if (!_morningCallEnabled) return '';
    return '${_formatAmPmHour(_morningCallTime)} · ${_shortCoachName(_morningCallCoachId)}';
  }

  String get _coreReminderStatusLabel {
    if (!_coreReminderEnabled) return '';
    return '${_coreReminderAdvanceMinutes}분 전';
  }

  String? get _morningCallStatus =>
      _morningCallStatusLabel.isEmpty ? null : _morningCallStatusLabel;

  String? get _coreReminderStatus =>
      _coreReminderStatusLabel.isEmpty ? null : _coreReminderStatusLabel;

  String _shortCoachName(String coachId) {
    if (coachId == 'push') return '푸쉬';
    return CoachConfigs.get(coachId).name.replaceAll(' 코치', '');
  }

  String _notificationVoiceCoachId(
    String coachId, {
    required String fallback,
    bool allowRandom = false,
  }) {
    if (allowRandom && coachId == 'random') return coachId;
    if (coachId == 'push') return coachId;
    final coach = CoachConfigs.all[CoachConfigs.normalizeId(coachId)];
    if (coach == null || coach.voiceCount <= 0) return fallback;
    return coachId;
  }

  String _formatAmPmHour(TimeOfDay time) {
    final period = time.hour < 12 ? 'AM' : 'PM';
    final hour12 = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    if (time.minute == 0) return '$period $hour12시';
    return '$period $hour12:${time.minute.toString().padLeft(2, '0')}';
  }

  String get _planRemainingLabel {
    final data = _userData;
    if (data == null || !data.isPlanActive) return '구독권 없음';
    final expiresAt = data.planExpiresAt;
    if (expiresAt == null) return '기간 제한 없음';
    final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
    if (remaining <= 0) return '만료 예정';
    return '$remaining일 남음';
  }

  void _showProfileSheet() {
    final couponController = TextEditingController();
    final profileScrollController = ScrollController();
    String? errorText;
    bool isApplying = false;
    bool isRestoring = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> applyCoupon() async {
              final code = couponController.text.trim().toUpperCase();
              if (code.isEmpty) {
                setSheetState(() => errorText = '쿠폰 코드를 입력해주세요.');
                return;
              }

              setSheetState(() {
                isApplying = true;
                errorText = null;
              });

              var appliedMessage = '';
              if (code == 'FRIENDS' || code == 'FRIENDS5900') {
                await UserDataService.setPlan(
                  'friends',
                  expiresAt: DateTime.now().add(const Duration(days: 30)),
                );
                appliedMessage = 'FRIENDS 플랜 30일이 적용됐어요.';
              } else if (code == 'MASTER' || code == 'MASTER8900') {
                await UserDataService.setPlan(
                  'master',
                  expiresAt: DateTime.now().add(const Duration(days: 30)),
                );
                appliedMessage = 'MASTER 플랜 30일이 적용됐어요.';
              } else if (code.startsWith('POINT')) {
                final points = int.tryParse(code.replaceAll('POINT', ''));
                if (points == null || points <= 0) {
                  setSheetState(() {
                    isApplying = false;
                    errorText = '포인트 쿠폰 형식을 확인해주세요.';
                  });
                  return;
                }
                await UserDataService.addPoints(points.clamp(0, 50000));
                appliedMessage = '$points포인트가 충전됐어요.';
              } else {
                setSheetState(() {
                  isApplying = false;
                  errorText = '사용할 수 없는 쿠폰 코드예요.';
                });
                return;
              }

              final updated = await UserDataService.load();
              if (!mounted) return;
              setState(() => _userData = updated);
              setSheetState(() => isApplying = false);
              couponController.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    appliedMessage,
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }

            Future<void> restoreCloudData() async {
              final shouldRestore = await showDialog<bool>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: Text(
                      '클라우드 데이터 복원',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    content: Text(
                      '계정에 저장된 할 일, 일정, 목표, 기록을 이 기기로 다시 불러옵니다.\n\n현재 기기의 데이터는 클라우드 백업 내용으로 덮어써질 수 있어요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        height: 1.5,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(
                          '취소',
                          style: GoogleFonts.notoSansKr(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(
                          '복원하기',
                          style: GoogleFonts.notoSansKr(
                            color: const Color(0xFF8B7CFF),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );

              if (shouldRestore != true) return;

              setSheetState(() => isRestoring = true);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '클라우드 데이터를 불러오는 중입니다...',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                  ),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: const Color(0xFF1A1A2E),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );

              final diag = await TasksSyncService.syncFromCloud();
              if (!mounted) return;

              if (diag['status'] != 'SUCCESS') {
                setSheetState(() => isRestoring = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '복원 실패: ${diag['message']}',
                      style: GoogleFonts.notoSansKr(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LandingScreen()),
                (_) => false,
              );
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.88,
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(30),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ScrollConfiguration(
                            behavior: ScrollConfiguration.of(
                              context,
                            ).copyWith(scrollbars: false),
                            child: SingleChildScrollView(
                              controller: profileScrollController,
                              primary: false,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 48,
                                      height: 4,
                                      margin: const EdgeInsets.only(bottom: 22),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE5E7EB),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        width: 38,
                                        height: 38,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFB6A4FF),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.person_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '내 프로필',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                                color: const Color(0xFF1A1A2E),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '구독, 포인트, 쿠폰을 확인해요.',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF8A8798),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildProfileInfoCard(
                                          label: '구독 상태',
                                          value: _planStatusLabel,
                                          icon: Icons.workspace_premium_rounded,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildProfileInfoCard(
                                          label: '포인트',
                                          value: '${_userData?.points ?? 0}P',
                                          icon: Icons.toll_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _buildProfileInfoCard(
                                    label: '구독 남은 기간',
                                    value: _planRemainingLabel,
                                    icon: Icons.event_available_rounded,
                                    isWide: true,
                                  ),
                                  const SizedBox(height: 18),
                                  _buildPurchasedCoachSection(),
                                  const SizedBox(height: 18),
                                  // 쿠폰 코드가 앱 안에 글자로 박혀 있다. 공개된 앱에서
                                  // 'MASTER'만 쳐도 플랜이 켜지는 셈이라, 코드를 서버가
                                  // 확인해주기 전까지는 입구를 닫아둔다.
                                  if (_couponEntryEnabled) ...[
                                    Text(
                                      '쿠폰 입력',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    TextField(
                                      controller: couponController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        hintText: '쿠폰 또는 구독권 코드',
                                        errorText: errorText,
                                        hintStyle: GoogleFonts.notoSansKr(
                                          color: const Color(0xFFB8B5C6),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF8F7FF),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE8E3F8),
                                          ),
                                        ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFE8E3F8),
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(16),
                                          borderSide: const BorderSide(
                                            color: Color(0xFFB6A4FF),
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 54,
                                      child: ElevatedButton(
                                        onPressed: isApplying
                                            ? null
                                            : applyCoupon,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF1A1A2E,
                                          ),
                                          disabledBackgroundColor: const Color(
                                            0xFFE5E7EB,
                                          ),
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          isApplying ? '확인 중...' : '쿠폰 적용하기',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: OutlinedButton.icon(
                                      onPressed: isRestoring
                                          ? null
                                          : restoreCloudData,
                                      icon: isRestoring
                                          ? const SizedBox(
                                              width: 17,
                                              height: 17,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF8B7CFF),
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_download_rounded,
                                            ),
                                      label: Text(
                                        isRestoring ? '복원 중...' : '클라우드 데이터 복원',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF8B7CFF,
                                        ),
                                        side: const BorderSide(
                                          color: Color(0xFFD8CEFF),
                                          width: 1.2,
                                        ),
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    width: double.infinity,
                                    child: TextButton(
                                      onPressed: () {
                                        Navigator.pop(context);
                                        Future.delayed(
                                          Duration.zero,
                                          _showLogoutDialog,
                                        );
                                      },
                                      style: TextButton.styleFrom(
                                        foregroundColor: const Color(
                                          0xFF9A96A8,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                      ),
                                      child: Text(
                                        '다른 계정으로 로그인하기',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 56,
                          right: 0,
                          bottom: 12,
                          child: _buildCompactScrollHandle(
                            profileScrollController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      couponController.dispose();
      profileScrollController.dispose();
    });
  }

  Widget _buildCompactScrollHandle(ScrollController controller) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return AnimatedBuilder(
            animation: controller,
            builder: (context, child) {
              final hasScroll =
                  controller.hasClients &&
                  controller.position.maxScrollExtent > 4;
              final maxScroll = hasScroll
                  ? controller.position.maxScrollExtent
                  : 0.0;
              final offset = hasScroll
                  ? controller.offset.clamp(0.0, maxScroll).toDouble()
                  : 0.0;
              const thumbHeight = 12.0;
              final trackHeight = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : thumbHeight;
              final travel = trackHeight > thumbHeight
                  ? trackHeight - thumbHeight
                  : 0.0;
              final top = maxScroll > 0 ? travel * (offset / maxScroll) : 0.0;

              return Opacity(
                opacity: hasScroll ? 0.75 : 0.0,
                child: Transform.translate(
                  offset: Offset(0, top),
                  child: Container(
                    width: 4,
                    height: thumbHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFB6A4FF).withOpacity(0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildProfileInfoCard({
    required String label,
    required String value,
    required IconData icon,
    bool isWide = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: isWide ? 14 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F7FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFFB6A4FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A96A8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchasedCoachSection() {
    final data = _userData;
    final purchasedCoachIds =
        data?.ownedCoaches
            .where(
              (id) => id != 'cat' && id != 'nyang_halbae' && id != 'sec_female',
            )
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '구매한 코치',
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 10),
        if (purchasedCoachIds.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              '구매한 코치가 아직 없어요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8A8798),
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 180),
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: purchasedCoachIds.length,
                itemBuilder: (context, index) {
                  return _buildPurchasedCoachRow(purchasedCoachIds[index]);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPurchasedCoachRow(String coachId) {
    final data = _userData;
    final coach = CoachConfigs.all[CoachConfigs.normalizeId(coachId)];
    final name = coach?.name ?? coachId;
    final remaining = data?.ownedCoachRemainingLabel(coachId) ?? '이용 중';
    final isExpired = remaining == '만료됨';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.person_rounded,
            size: 18,
            color: isExpired
                ? const Color(0xFFB8B5C6)
                : const Color(0xFFB6A4FF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$name · 1년 이용권',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            remaining,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: isExpired
                  ? const Color(0xFFB8B5C6)
                  : const Color(0xFF8B7CFF),
            ),
          ),
        ],
      ),
    );
  }

  void _showPremiumLearnSettingsModal() {
    String selectedTitle = '대표님';
    final titleController = TextEditingController();
    TimeOfDay minSleepTime = const TimeOfDay(hour: 23, minute: 0);
    int sleepDuration = 7;
    List<Map<String, dynamic>> routines = [];
    List<Map<String, dynamic>> weekGoals = [];
    List<Map<String, dynamic>> monthGoals = [];
    List<Map<String, dynamic>> visions = [];
    bool isLoaded = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!isLoaded) {
              SharedPreferences.getInstance().then((prefs) {
                final rawWeek = prefs.getString('nyang_week_goals');
                final rawMonth = prefs.getString('nyang_month_goals');
                final rawVisions = prefs.getString('nyang_visions');
                final rawRoutines = prefs.getString('nyang_premium_routines');
                final title = prefs.getString('nyang_master_title');
                final minSleepTimeStr = prefs.getString(
                  'nyang_premium_min_sleep_time',
                );
                final sleepDurationPref = prefs.getInt(
                  'nyang_premium_sleep_duration',
                );

                setState(() {
                  if (rawWeek != null)
                    weekGoals = List<Map<String, dynamic>>.from(
                      jsonDecode(rawWeek),
                    );
                  if (rawMonth != null)
                    monthGoals = List<Map<String, dynamic>>.from(
                      jsonDecode(rawMonth),
                    );
                  if (rawVisions != null)
                    visions = List<Map<String, dynamic>>.from(
                      jsonDecode(rawVisions),
                    );
                  if (rawRoutines != null) {
                    routines = (jsonDecode(rawRoutines) as List).map((item) {
                      final routine = Map<String, dynamic>.from(item as Map);
                      TimeOfDay parseTime(String? value, TimeOfDay fallback) {
                        final parts = (value ?? '').split(':');
                        if (parts.length < 2) return fallback;
                        return TimeOfDay(
                          hour: int.tryParse(parts[0]) ?? fallback.hour,
                          minute: int.tryParse(parts[1]) ?? fallback.minute,
                        );
                      }

                      return {
                        'start': parseTime(
                          routine['start']?.toString(),
                          const TimeOfDay(hour: 9, minute: 0),
                        ),
                        'end': parseTime(
                          routine['end']?.toString(),
                          const TimeOfDay(hour: 18, minute: 0),
                        ),
                        'name': routine['name']?.toString() ?? '',
                        'days': List<String>.from(routine['days'] ?? []),
                      };
                    }).toList();
                  }
                  if (title != null) {
                    selectedTitle = title == '주인님' ? '대표님' : title;
                  }
                  titleController.text = selectedTitle == '대표님'
                      ? ''
                      : selectedTitle;
                  if (minSleepTimeStr != null) {
                    final parts = minSleepTimeStr.split(':');
                    if (parts.length >= 2) {
                      minSleepTime = TimeOfDay(
                        hour: int.tryParse(parts[0]) ?? minSleepTime.hour,
                        minute: int.tryParse(parts[1]) ?? minSleepTime.minute,
                      );
                    }
                  }
                  if (sleepDurationPref != null)
                    sleepDuration = sleepDurationPref;
                  isLoaded = true;
                });
              });
            }

            void saveGoalsToPrefs(String type, List<dynamic> items) async {
              final prefs = await SharedPreferences.getInstance();
              if (type == 'week') {
                await prefs.setString('nyang_week_goals', jsonEncode(items));
              } else if (type == 'month') {
                await prefs.setString('nyang_month_goals', jsonEncode(items));
              } else if (type == 'vision') {
                await prefs.setString('nyang_visions', jsonEncode(items));
              }
              TasksSyncService.scheduleSyncToCloud();
            }

            Widget buildSyncGoalList(
              List<Map<String, dynamic>> items,
              String type,
            ) {
              return Column(
                children: [
                  if (items.isNotEmpty)
                    ...items.asMap().entries.map((e) {
                      int idx = e.key;
                      var item = e.value;
                      String text = type == 'vision'
                          ? (item['name'] ?? '')
                          : (item['text'] ?? '');
                      bool done = type == 'vision'
                          ? false
                          : (item['done'] == true);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: done
                              ? Border.all(color: const Color(0xFFE8E3F8))
                              : Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            if (type != 'vision')
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    item['done'] = !done;
                                    saveGoalsToPrefs(type, items);
                                  });
                                },
                                child: Container(
                                  width: 48,
                                  height: 52,
                                  alignment: Alignment.center,
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: done
                                          ? const Color(0xFF8B7CFF)
                                          : const Color(
                                              0xFF8B7CFF,
                                            ).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: done
                                          ? const Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 14,
                                            )
                                          : Text(
                                              '${idx + 1}',
                                              style: GoogleFonts.notoSansKr(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF8B7CFF),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            if (type == 'vision')
                              const SizedBox(width: 16, height: 52),
                            Expanded(
                              child: TextFormField(
                                initialValue: text,
                                onChanged: (val) {
                                  if (type == 'vision')
                                    item['name'] = val;
                                  else
                                    item['text'] = val;
                                  saveGoalsToPrefs(type, items);
                                },
                                decoration: InputDecoration(
                                  hintText: type == 'vision'
                                      ? '장기 비전 입력...'
                                      : '목표 입력...',
                                  hintStyle: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: done
                                      ? const Color(0xFFC0C0D0)
                                      : const Color(0xFF3D3A4E),
                                  decoration: done
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Color(0xFFC0C0D0),
                                size: 18,
                              ),
                              onPressed: () {
                                setState(() {
                                  items.removeAt(idx);
                                  saveGoalsToPrefs(type, items);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        if (type == 'vision') {
                          items.add({
                            'id': DateTime.now().millisecondsSinceEpoch
                                .toString(),
                            'name': '',
                            'desc': '',
                            'deadline': {
                              'year': '2026',
                              'month': '1',
                              'period': '초',
                            },
                            'milestones': [],
                            'coachId': 'self',
                            'updatedAt': DateTime.now().toIso8601String(),
                          });
                        } else {
                          items.add({
                            'id': DateTime.now().millisecondsSinceEpoch,
                            'text': '',
                            'done': false,
                          });
                        }
                        saveGoalsToPrefs(type, items);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFDF8),
                        border: Border.all(
                          color: const Color(0xFFDDD6FE),
                          style: BorderStyle.solid,
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        type == 'vision' ? '➕ 비전 추가' : '➕ 목표 추가',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF8B7CFF),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.9,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
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
                  const SizedBox(height: 24),
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          SvgPicture.asset(
                            'assets/icons/user-gear.svg',
                            width: 22,
                            height: 22,
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF8B7CFF),
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '비서 학습 설정',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Color(0xFFA0A0B0)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SvgPicture.asset(
                        'assets/icons/wand-magic-sparkles.svg',
                        width: 13,
                        height: 13,
                        colorFilter: const ColorFilter.mode(
                          AppDesignTokens.brandMuted,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '입력할수록 비서가 생활 패턴을 정확히 파악해요.',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF9593A5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Content
                  Expanded(
                    child: ListView(
                      children: [
                        // 0. 호칭 설정
                        _buildLearnField(
                          icon: const Icon(
                            Icons.person,
                            color: Color(0xFF8B7CFF),
                            size: 18,
                          ),
                          title: '호칭 설정',
                          subtitle: '비서가 불러줬으면 하는 호칭을 선택하세요.',
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => setState(() {
                                  selectedTitle = '대표님';
                                  titleController.clear();
                                }),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selectedTitle == '대표님'
                                        ? const Color(0xFFEBE5FF)
                                        : Colors.white,
                                    border: Border.all(
                                      color: selectedTitle == '대표님'
                                          ? const Color(0xFF8B7CFF)
                                          : const Color(0xFFE5E7EB),
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '대표님 (기본)',
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 13,
                                      fontWeight: selectedTitle == '대표님'
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: selectedTitle == '대표님'
                                          ? const Color(0xFF8B7CFF)
                                          : const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: titleController,
                                  onChanged: (val) {
                                    setState(() {
                                      selectedTitle = val.trim().isEmpty
                                          ? '대표님'
                                          : val.trim();
                                    });
                                  },
                                  decoration: InputDecoration(
                                    hintText: '자유 기입',
                                    hintStyle: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 13,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                    fillColor: const Color(0xFFF9FAFB),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 1. 수면
                        _buildLearnField(
                          icon: SvgPicture.asset(
                            'assets/icons/fa-moon-solid.svg',
                            width: 17,
                            height: 17,
                            colorFilter: const ColorFilter.mode(
                              AppDesignTokens.brand,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: '컨디션 수면 기준',
                          subtitle: '다음 날 무리없는 수면 기준을 알려주세요.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '최소 취침 시간',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            color: const Color(0xFF9593A5),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        GestureDetector(
                                          onTap: () async {
                                            final time =
                                                await _showFocusedTimePicker(
                                                  context: context,
                                                  initialTime: minSleepTime,
                                                );
                                            if (time != null) {
                                              setState(
                                                () => minSleepTime = time,
                                              );
                                            }
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 6,
                                              horizontal: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F0FF),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.nightlight_round,
                                                  size: 14,
                                                  color: Color(0xFF8B7CFF),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  '${minSleepTime.hour.toString().padLeft(2, '0')}:${minSleepTime.minute.toString().padLeft(2, '0')}',
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: const Color(0xFFE5E7EB),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '최소 수면 시간',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            color: const Color(0xFF9593A5),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                            horizontal: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3F0FF),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<int>(
                                              value: sleepDuration,
                                              icon: const Icon(
                                                Icons.arrow_drop_down,
                                                color: Color(0xFF8B7CFF),
                                              ),
                                              isDense: true,
                                              menuMaxHeight: 250,
                                              items:
                                                  List.generate(
                                                    10,
                                                    (index) => index + 3,
                                                  ).map((hour) {
                                                    return DropdownMenuItem<
                                                      int
                                                    >(
                                                      value: hour,
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          const Icon(
                                                            Icons
                                                                .hourglass_bottom_rounded,
                                                            size: 14,
                                                            color: Color(
                                                              0xFF8B7CFF,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          Text(
                                                            '$hour시간',
                                                            style:
                                                                GoogleFonts.notoSansKr(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    );
                                                  }).toList(),
                                              onChanged: (value) {
                                                if (value != null) {
                                                  setState(
                                                    () => sleepDuration = value,
                                                  );
                                                }
                                              },
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                            ],
                          ),
                        ),

                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: 8.0,
                            left: 4.0,
                          ),
                          child: Text(
                            '- 아래는 목표 탭과 연동됩니다 -',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8B7CFF),
                            ),
                          ),
                        ),
                        // 3. 장기 비전
                        _buildLearnField(
                          icon: const Icon(
                            Icons.star_border,
                            color: Color(0xFF8B7CFF),
                            size: 20,
                          ),
                          title: '장기 비전',
                          subtitle: '앞으로 이루고 싶은 큰 목표를 알려주세요.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              buildSyncGoalList(visions, 'vision'),
                              const SizedBox(height: 8),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SvgPicture.asset(
                                    'assets/icons/fa-lightbulb-solid.svg',
                                    width: 12,
                                    height: 12,
                                    colorFilter: const ColorFilter.mode(
                                      AppDesignTokens.brand,
                                      BlendMode.srcIn,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '세부적인 마일스톤은 목표 탭에서 작성해 주세요!',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 11,
                                        color: const Color(0xFF8B7CFF),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 4. 이번 달 목표
                        _buildLearnField(
                          icon: SvgPicture.asset(
                            'assets/icons/bullseye.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              AppDesignTokens.brand,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: '이번 달 목표',
                          subtitle: '이번 달에 집중할 목표를 설정하세요.',
                          child: buildSyncGoalList(monthGoals, 'month'),
                        ),

                        // 5. 이번 주 목표
                        _buildLearnField(
                          icon: SvgPicture.asset(
                            'assets/icons/fa-fire-solid.svg',
                            width: 17,
                            height: 17,
                            colorFilter: const ColorFilter.mode(
                              AppDesignTokens.brand,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: '이번 주 목표',
                          subtitle: '이번 주에 달성할 작은 목표들을 적어보세요.',
                          child: buildSyncGoalList(weekGoals, 'week'),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  // Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString(
                          'nyang_master_title',
                          selectedTitle,
                        );
                        await prefs.remove('nyang_coach_name_nyang_halbae');
                        await prefs.remove('nyang_coach_name_sec_female');
                        this.setState(() {
                          _homeWidgetStatus = _buildHomeWidgetStatus(
                            nyang:
                                prefs.getBool('widget_nyang_enabled') ?? false,
                            catCharacter:
                                prefs.getBool('widget_cat_character_enabled') ??
                                false,
                          );
                        });
                        await prefs.setBool('nyang_night_call_enabled', false);
                        await prefs.setBool(
                          'nyang_night_call_daily_enabled',
                          false,
                        );
                        await prefs.setString(
                          'nyang_premium_min_sleep_time',
                          '${minSleepTime.hour.toString().padLeft(2, '0')}:${minSleepTime.minute.toString().padLeft(2, '0')}',
                        );
                        await prefs.setInt(
                          'nyang_premium_sleep_duration',
                          sleepDuration,
                        );
                        await prefs.setString(
                          'nyang_premium_routines',
                          jsonEncode(
                            routines
                                .where(
                                  (routine) =>
                                      (routine['name'] as String? ?? '')
                                          .trim()
                                          .isNotEmpty,
                                )
                                .map((routine) {
                                  final start = routine['start'] as TimeOfDay;
                                  final end = routine['end'] as TimeOfDay;
                                  return {
                                    'start':
                                        '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
                                    'end':
                                        '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}',
                                    'name': (routine['name'] as String).trim(),
                                    'days': List<String>.from(
                                      routine['days'] ?? [],
                                    ),
                                  };
                                })
                                .toList(),
                          ),
                        );
                        TasksSyncService.scheduleSyncToCloud();
                        await NotificationService().disableNightCallReminders();
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비서 학습 설정이 저장되었습니다.')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppDesignTokens.brand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            AppDesignTokens.radiusMedium,
                          ),
                        ),
                        elevation: 0,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.asset(
                            'assets/icons/bolt.svg',
                            width: 16,
                            height: 16,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '비서 학습시키기',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
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

  Widget _buildLearnField({
    required dynamic icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        border: Border.all(color: AppDesignTokens.brandBorder),
        borderRadius: BorderRadius.circular(AppDesignTokens.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: AppDesignTokens.brand.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: AppDesignTokens.brandSoftAlt,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: icon is Widget
                    ? icon
                    : Text(
                        icon.toString(),
                        style: const TextStyle(fontSize: 16),
                      ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Text(
              subtitle,
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppDesignTokens.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(left: 46), child: child),
        ],
      ),
    );
  }

  void _showLegalLinksSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E0F6),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                _buildLegalLinkTile(
                  icon: Icons.description_outlined,
                  title: '이용약관',
                  subtitle: '서비스 이용 규칙을 확인해요.',
                  url: _termsUrl,
                ),
                const SizedBox(height: 10),
                _buildLegalLinkTile(
                  icon: Icons.privacy_tip_outlined,
                  title: '개인정보처리방침',
                  subtitle: '데이터 수집과 보관 방식을 확인해요.',
                  url: _privacyUrl,
                ),
                const SizedBox(height: 10),
                _buildLegalLinkTile(
                  icon: Icons.workspace_premium_outlined,
                  title: '환불 안내',
                  subtitle: '환불 기준을 확인하세요.',
                  url: _refundUrl,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegalLinkTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Uri url,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openLegalLink(url),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8B7CFF), size: 20),
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
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF8A8798),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: Color(0xFFA0A0B0),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLegalLink(Uri url) async {
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('링크를 열 수 없어요. 잠시 후 다시 시도해주세요.')),
    );
  }

  /// 코치가 마지막으로 보낸 답변을 태그가 붙은 그대로 보여준다.
  ///
  /// 화면에 나오는 말은 태그를 떼어낸 뒤다. 그래서 조작이 안 될 때 코치가
  /// 태그를 안 붙인 것인지, 붙였는데 앱이 못 알아본 것인지 알 수 없었다.
  /// 여기서 한 번 보면 갈린다.
  Future<void> _showLastReplyDialog() async {
    final text = await LastReplyLog.read();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          '마지막 코치 답변',
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF1E1E2D),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              text ?? '아직 받은 답변이 없어요.',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                height: 1.6,
                color: const Color(0xFF3D3A4E),
              ),
            ),
          ),
        ),
        actions: [
          if (text != null)
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('복사했어요')),
                );
              },
              child: Text(
                '복사',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
              ),
            ),
          if (text != null)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _showReportReasonDialog(text);
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD9455F),
              ),
              child: Text(
                '신고',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '닫기',
              style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  /// 신고 사유를 고르고 보낸다. 답변 원문은 고른 사유와 함께 그대로 실려간다.
  Future<void> _showReportReasonDialog(String replyText) async {
    final noteController = TextEditingController();
    String? selectedReason;
    var isSending = false;

    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                '이 답변을 신고할까요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1E1E2D),
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final reason in ContentReportService.reasons)
                        InkWell(
                          onTap: isSending
                              ? null
                              : () =>
                                    setDialogState(() => selectedReason = reason),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                Icon(
                                  selectedReason == reason
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 20,
                                  color: selectedReason == reason
                                      ? const Color(0xFFD9455F)
                                      : const Color(0xFFB9B5C4),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    reason,
                                    style: GoogleFonts.notoSansKr(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF3D3A4E),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: noteController,
                        enabled: !isSending,
                        maxLines: 3,
                        maxLength: 300,
                        style: GoogleFonts.notoSansKr(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '더 알려주실 내용이 있으면 적어주세요 (선택)',
                          hintStyle: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            color: const Color(0xFF9A96A8),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: Text(
                    '취소',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: selectedReason == null || isSending
                      ? null
                      : () async {
                          setDialogState(() => isSending = true);
                          final ok = await ContentReportService.instance.submit(
                            reason: selectedReason!,
                            replyText: replyText,
                            note: noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                            coachId: widget.coachId,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext, ok);
                        },
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD9455F),
                  ),
                  child: Text(
                    isSending ? '보내는 중...' : '신고하기',
                    style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    noteController.dispose();
    if (!mounted || sent == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent ? '신고를 접수했어요. 확인 후 반영할게요.' : '신고를 보내지 못했어요. 잠시 후 다시 시도해주세요.',
          style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildDeleteAccountButton() {
    return TextButton(
      onPressed: _showDeleteAccountDialog,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFB9B5C4),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(
        '계정 삭제',
        style: GoogleFonts.notoSansKr(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    // 구독은 계정에 붙어 있다. 계정이 사라지면 남은 기간도 같이 사라진다는 걸
    // 지우기 전에 알려준다. 화면에 들고 있던 값이 오래됐을 수 있어 다시 읽는다.
    final data = await UserDataService.load();
    if (!mounted) return;
    final hasPlan = data.isPlanActive;
    // 화면 위쪽 배지가 쓰는 _planStatusLabel은 예전에 읽어둔 값을 본다.
    // 여기서는 방금 읽은 쪽으로 이름을 짓는다.
    final planLabel = data.planType == 'master' ? '마스터 플랜' : '프렌즈 플랜';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '계정을 삭제할까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '지금까지의 대화, 일정, 루틴, 기록이 모두 지워지고 되돌릴 수 없어요.\n'
                '다시 로그인해도 복구되지 않습니다.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B687A),
                  height: 1.45,
                ),
              ),
              // 이용 중인 플랜이 없으면 구독 이야기를 꺼내지 않는다. 삭제를
              // 망설이는 자리에서 상관없는 경고를 하나 더 얹을 이유가 없다.
              if (hasPlan) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF1F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFF6DADD)),
                  ),
                  // 남은 기간이 사라진다는 것과, 자동 결제는 스토어에서 따로
                  // 끊어야 한다는 것은 다른 이야기다. 계정을 지워도 스토어의
                  // 정기 결제는 그대로 돌아 돈이 계속 빠져나간다.
                  child: Text(
                    '이용 중인 $planLabel도 계정과 함께 사라져요.\n'
                    '남은 기간은 환불되지 않고, 정기 결제는 계정을 지워도 자동으로 멈추지 않습니다. '
                    '${Platform.isIOS ? 'App Store' : 'Play 스토어'}의 구독 설정에서 따로 해지해주세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFB4545D),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(
                '취소',
                style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                '삭제하기',
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFE15B64),
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final result = await AccountDeletionService.instance.deleteAccount();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // 진행 표시 닫기

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.message,
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
          ),
        ),
      );
      return;
    }

    await AuthService().signOut();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingScreen()),
      (_) => false,
    );
  }

  Widget _buildLogoutButton() {
    return TextButton(
      onPressed: _showLogoutDialog,
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFF9A96A8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      child: Text(
        '로그아웃',
        style: GoogleFonts.notoSansKr(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
