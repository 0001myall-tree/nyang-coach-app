import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'coach_config.dart';
import 'main_tab_screen.dart';
import 'landing_screen.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/tasks_sync_service.dart';
import '../models/user_data.dart';
import '../services/widget_sync_service.dart';
import 'package:home_widget/home_widget.dart';

class SettingsScreen extends StatefulWidget {
  final String coachId;
  final bool autoOpenPremiumLearnSettings;
  const SettingsScreen({
    super.key,
    required this.coachId,
    this.autoOpenPremiumLearnSettings = false,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static final Uri _termsUrl = Uri.parse(
    'https://example.com/nyang-coach/terms',
  );
  static final Uri _privacyUrl = Uri.parse(
    'https://example.com/nyang-coach/privacy',
  );
  static final Uri _subscriptionUrl = Uri.parse(
    'https://example.com/nyang-coach/subscription',
  );

  String _chatBgStyle = 'emotional'; // 'emotional' or 'simple'
  double _resetHour = 3.0; // 0 ~ 6

  bool _morningCallEnabled = true;
  TimeOfDay _morningCallTime = const TimeOfDay(hour: 7, minute: 0);
  String _morningCallCoachId = 'cat';
  bool _coreReminderEnabled = false;
  String _coreReminderCoachId = 'cat';
  int _coreReminderAdvanceMinutes = 10;
  String? _homeWidgetStatus;
  String _secMaleWidgetName = '남비서';
  String _secFemaleWidgetName = '여비서';
  UserData? _userData;

  bool get _isMaster =>
      widget.coachId == 'sec_male' || widget.coachId == 'sec_female';
  bool get _hasMasterPlan =>
      _userData?.isPlanActive == true && _userData?.planType == 'master';
  bool get _isFreeUser => _userData?.isPlanActive != true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.autoOpenPremiumLearnSettings) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showPremiumLearnSettingsModal();
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = await UserDataService.load();
    await WidgetSyncService.enforcePlanAccess(
      hasMasterPlan: userData.isPlanActive && userData.planType == 'master',
    );
    if (!userData.isPlanActive) {
      await _disablePaidReminderSettings(prefs);
    }
    setState(() {
      _userData = userData;
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
      _morningCallCoachId =
          prefs.getString('nyang_morning_call_coach') ?? 'cat';
      _coreReminderEnabled =
          prefs.getBool('nyang_core_reminder_enabled') ?? false;
      _coreReminderCoachId =
          prefs.getString('nyang_core_reminder_coach') ?? 'cat';
      _coreReminderAdvanceMinutes =
          prefs.getInt('nyang_core_reminder_advance') ?? 10;
      _resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
      _chatBgStyle = prefs.getString('nyang_chat_bg_style') ?? 'emotional';
      _secMaleWidgetName = _secretaryWidgetName(
        prefs.getString('nyang_coach_name_sec_male'),
        '남비서',
      );
      _secFemaleWidgetName = _secretaryWidgetName(
        prefs.getString('nyang_coach_name_sec_female'),
        '여비서',
      );
      _homeWidgetStatus = _buildHomeWidgetStatus(
        nyang: prefs.getBool('widget_nyang_enabled') ?? false,
        secMale: prefs.getBool('widget_sec_male_enabled') ?? false,
        secFemale: prefs.getBool('widget_sec_female_enabled') ?? false,
      );
    });
  }

  String _secretaryWidgetName(String? value, String fallback) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String? _buildHomeWidgetStatus({
    required bool nyang,
    required bool secMale,
    required bool secFemale,
  }) {
    final labels = <String>[
      if (nyang) '냥냥',
      if (secMale) _secMaleWidgetName,
      if (secFemale) _secFemaleWidgetName,
    ];
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

  VoidCallback _paidSettingsTap(VoidCallback action) {
    return () {
      if (_isFreeUser) {
        _showFreeSettingsLockedNotice();
        return;
      }
      action();
    };
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

    bool tempNyang = prefs.getBool('widget_nyang_enabled') ?? false;
    bool tempSecMale = prefs.getBool('widget_sec_male_enabled') ?? false;
    bool tempSecFemale = prefs.getBool('widget_sec_female_enabled') ?? false;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> requestWidgetPin(String providerId) async {
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
              required String imagePath,
              required bool value,
              required ValueChanged<bool> onChanged,
              required bool isLocked,
              required String providerId,
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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: const Color(0xFFE5E7EB),
                          width: 1,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(imagePath, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isLocked
                                    ? const Color(0xFFC0C0D0)
                                    : const Color(0xFF3D3A4E),
                              ),
                            ),
                          ),
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
                    ),
                    if (value)
                      Flexible(
                        flex: 0,
                        child: GestureDetector(
                          onTap: () async {
                            if (isLocked) return;
                            await requestWidgetPin(providerId);
                          },
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 112),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B7CFF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '바탕화면에 추가',
                                maxLines: 1,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (!value)
                      Flexible(
                        flex: 0,
                        child: GestureDetector(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('먼저 위젯을 켠 뒤 저장하고 바탕화면에 추가해 주세요.'),
                              ),
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 112),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE5E7EB),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '바탕화면에 추가',
                                maxLines: 1,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
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
                    '바탕화면에 꺼내둘 위젯을 선택해 주세요.\n(한 번에 하나의 위젯만 활성화할 수 있습니다)',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      color: const Color(0xFF8E8D9B),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _buildWidgetToggle(
                          title: '냥냥코치 위젯',
                          imagePath: 'assets/images/cat.png',
                          value: tempNyang,
                          isLocked: false,
                          providerId: 'cat',
                          onChanged: (val) {
                            setModalState(() {
                              tempNyang = val;
                              if (val) {
                                tempSecMale = false;
                                tempSecFemale = false;
                              }
                            });
                          },
                        ),
                        _buildWidgetToggle(
                          title: '$_secMaleWidgetName 위젯',
                          imagePath: 'assets/images/sec_male.png',
                          value: tempSecMale,
                          isLocked: !isMasterPlan,
                          providerId: 'sec_male',
                          onChanged: (val) {
                            setModalState(() {
                              tempSecMale = val;
                              if (val) {
                                tempNyang = false;
                                tempSecFemale = false;
                              }
                            });
                          },
                        ),
                        _buildWidgetToggle(
                          title: '$_secFemaleWidgetName 위젯',
                          imagePath: 'assets/images/sec_female.png',
                          value: tempSecFemale,
                          isLocked: !isMasterPlan,
                          providerId: 'sec_female',
                          onChanged: (val) {
                            setModalState(() {
                              tempSecFemale = val;
                              if (val) {
                                tempNyang = false;
                                tempSecMale = false;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () async {
                        final currentUserData = await UserDataService.load();
                        final canUseMasterWidget =
                            currentUserData.isPlanActive &&
                            currentUserData.planType == 'master';
                        if (!canUseMasterWidget &&
                            (tempSecMale || tempSecFemale)) {
                          tempNyang = true;
                          tempSecMale = false;
                          tempSecFemale = false;
                        }

                        await prefs.setBool('widget_nyang_enabled', tempNyang);
                        await prefs.setBool(
                          'widget_sec_male_enabled',
                          tempSecMale,
                        );
                        await prefs.setBool(
                          'widget_sec_female_enabled',
                          tempSecFemale,
                        );
                        await prefs.setBool(
                          'nyang_home_widget_enabled',
                          tempNyang || tempSecMale || tempSecFemale,
                        );

                        if (mounted) {
                          setState(() {
                            _homeWidgetStatus = _buildHomeWidgetStatus(
                              nyang: tempNyang,
                              secMale: tempSecMale,
                              secFemale: tempSecFemale,
                            );
                          });
                        }

                        final selectedProviderId = tempNyang
                            ? 'cat'
                            : tempSecMale
                            ? 'sec_male'
                            : tempSecFemale
                            ? 'sec_female'
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

    if (enabled) {
      await NotificationService().scheduleDailyMorningCall(
        hour: time.hour,
        minute: time.minute,
        coachId: coachId,
      );
    } else {
      await NotificationService().cancelAllMorningCalls();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⏰ $timeStr에 $coachName 모닝콜이 설정되었어요!')),
      );
    }
  }

  void _showMorningCallSettingsModal() {
    bool tempEnabled = _morningCallEnabled;
    TimeOfDay tempTime = _morningCallTime;
    String tempCoachId = _morningCallCoachId;

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

                  // 시간 선택기
                  Opacity(
                    opacity: tempEnabled ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: () async {
                        if (!tempEnabled) return;
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: tempTime,
                        );
                        if (picked != null) {
                          setModalState(() => tempTime = picked);
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
                  const SizedBox(height: 24),

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
                              .where((coach) => coach.tier == 'friends')
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
                              .where((coach) => coach.tier == 'master')
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
                  SizedBox(
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
    String coachId,
    int advanceMinutes,
  ) async {
    final userData = await UserDataService.load();
    final prefs = await SharedPreferences.getInstance();
    if (!userData.isPlanActive) {
      await _disablePaidReminderSettings(prefs);
      if (mounted) {
        setState(() {
          _coreReminderEnabled = false;
          _coreReminderCoachId = 'cat';
          _coreReminderAdvanceMinutes = 10;
        });
        _showFreeSettingsLockedNotice();
      }
      return;
    }
    await prefs.setBool('nyang_core_reminder_enabled', enabled);
    await prefs.setString('nyang_core_reminder_coach', coachId);
    await prefs.setInt('nyang_core_reminder_advance', advanceMinutes);
    TasksSyncService.scheduleSyncToCloud();

    setState(() {
      _coreReminderEnabled = enabled;
      _coreReminderCoachId = coachId;
      _coreReminderAdvanceMinutes = advanceMinutes;
    });

    NotificationService().syncCoreReminders();

    String coachName = '랜덤 코치';
    if (coachId != 'random') {
      coachName = CoachConfigs.get(coachId).name;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('🔔 $coachName 일정 알람이 설정되었어요!')));
    }
  }

  void _showCoreReminderSettingsModal() {
    if (_isFreeUser) {
      _showFreeSettingsLockedNotice();
      return;
    }
    bool tempEnabled = _coreReminderEnabled;
    String tempCoachId = _coreReminderCoachId;
    int tempAdvance = _coreReminderAdvanceMinutes;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
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
                            '코치의 일정 알람',
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

                  // 코치 선택 리스트
                  Text(
                    '알람 코치 선택',
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
                          // 기본 푸시 알람
                          _buildMorningCallCoachItem(
                            id: 'push',
                            name: '기본 푸쉬 알람',
                            subtitle: '코치 없이 조용하게 시스템 알람만 받아요',
                            isSelected: tempCoachId == 'push',
                            onTap: () {
                              if (tempEnabled)
                                setModalState(() => tempCoachId = 'push');
                            },
                          ),
                          // 랜덤 코치
                          _buildMorningCallCoachItem(
                            id: 'random',
                            name: '랜덤 코치',
                            subtitle: '모든 코치 중 한 명이 랜덤으로 알람을 보내줘요',
                            isSelected: tempCoachId == 'random',
                            onTap: () {
                              if (tempEnabled)
                                setModalState(() => tempCoachId = 'random');
                            },
                          ),
                          _buildMorningCallCoachSectionHeader('FRIENDS 코치'),
                          ...CoachConfigs.all.values
                              .where((coach) => coach.tier == 'friends')
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
                              .where((coach) => coach.tier == 'master')
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
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _saveCoreReminderSettings(
                          tempEnabled,
                          tempCoachId,
                          tempAdvance,
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
          offset: const Offset(0, -32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단 타이틀
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      // 프로필/구독/쿠폰 관리
                      _buildProfileCard(),
                      const SizedBox(height: 16),

                      // 알람 설정 버튼
                      _buildActionButton(
                        icon: Icons.alarm,
                        label: '모닝콜',
                        status: _morningCallStatus,
                        onTap: _showMorningCallSettingsModal,
                      ),
                      const SizedBox(height: 16),

                      // 일정 알람 설정 버튼
                      _buildActionButton(
                        icon: Icons.notifications_none,
                        label: '일정 알람',
                        status: _coreReminderStatus,
                        onTap: _paidSettingsTap(_showCoreReminderSettingsModal),
                      ),
                      const SizedBox(height: 16),

                      // 홈 화면 위젯 버튼 (모달 호출)
                      _buildActionButton(
                        icon: Icons.widgets_rounded,
                        label: '홈 화면 위젯',
                        status: _homeWidgetStatus,
                        onTap: _paidSettingsTap(_showHomeWidgetSettingsModal),
                      ),
                      const SizedBox(height: 16),

                      if (!_isMaster) ...[
                        // 채팅 배경 설정
                        _buildBgStyleCard(),
                        const SizedBox(height: 16),
                      ],

                      // 할 일 리셋 시간 설정
                      _buildResetHourCard(),
                      const SizedBox(height: 16),

                      // MASTER 전용 비서 학습 설정
                      _buildPremiumLearnCard(),
                      const SizedBox(height: 16),

                      _buildActionButton(
                        icon: Icons.policy_outlined,
                        label: '약관 및 개인정보',
                        subtitle: '이용약관, 개인정보처리방침, 구독 안내를 확인해요.',
                        onTap: _showLegalLinksSheet,
                      ),
                      const SizedBox(height: 24),

                      _buildLogoutButton(),

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

  Widget _buildBgStyleCard() {
    return GestureDetector(
      onTap: _paidSettingsTap(_showBgStylePicker),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wallpaper_rounded,
              color: Color(0xFF8B7CFF),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '채팅 배경',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _chatBgStyle == 'emotional' ? '감성 버전' : '심플 버전',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF8B7CFF),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF8B7CFF),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBgStylePicker() async {
    final styles = ['emotional', 'simple'];
    final labels = ['감성 버전', '심플 버전'];
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    String? subtitle,
    String? status,
    VoidCallback? onTap,
    bool isToggle = false,
    bool toggleValue = false,
    ValueChanged<bool>? onToggle,
  }) {
    return GestureDetector(
      onTap: isToggle && onToggle != null
          ? () => onToggle(!toggleValue)
          : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF8B7CFF), size: 18),
            const SizedBox(width: 8),
            if (subtitle != null)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF3D3A4E),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFFA0A0B0),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              Text(
                label,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
              const Spacer(),
            ],
            if (status != null) ...[
              _buildSettingStatusBadge(status),
              const SizedBox(width: 8),
            ],
            if (isToggle)
              Transform.scale(
                scale: 0.8,
                child: CupertinoSwitch(
                  value: toggleValue,
                  activeColor: const Color(0xFF8B7CFF),
                  onChanged: onToggle,
                ),
              )
            else
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

  Widget _buildProfileCard() {
    return GestureDetector(
      onTap: _paidSettingsTap(_showProfileSheet),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xFFB6A4FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Row(
                children: [
                  Text(
                    '내 프로필',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                  const SizedBox(width: 40),
                  Text(
                    '${_planStatusLabel} · ${_userData?.points ?? 0}P',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF9A96A8),
                    ),
                  ),
                ],
              ),
            ),
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
    return '${_coreReminderAdvanceMinutes}분 전 · ${_shortCoachName(_coreReminderCoachId)}';
  }

  String? get _morningCallStatus =>
      _morningCallStatusLabel.isEmpty ? null : _morningCallStatusLabel;

  String? get _coreReminderStatus =>
      _coreReminderStatusLabel.isEmpty ? null : _coreReminderStatusLabel;

  String _shortCoachName(String coachId) {
    if (coachId == 'random') return '랜덤';
    if (coachId == 'push') return '푸쉬';
    return CoachConfigs.get(coachId).name.replaceAll(' 코치', '');
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
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        primary: true,
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
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                  tooltip: '닫기',
                                  style: IconButton.styleFrom(
                                    foregroundColor: const Color(0xFF8A8798),
                                    backgroundColor: const Color(0xFFF8F7FF),
                                    shape: const CircleBorder(),
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
                              textCapitalization: TextCapitalization.characters,
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
                                onPressed: isApplying ? null : applyCoupon,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1A1A2E),
                                  disabledBackgroundColor: const Color(
                                    0xFFE5E7EB,
                                  ),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                    : const Icon(Icons.cloud_download_rounded),
                                label: Text(
                                  isRestoring ? '복원 중...' : '클라우드 데이터 복원',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF8B7CFF),
                                  side: const BorderSide(
                                    color: Color(0xFFD8CEFF),
                                    width: 1.2,
                                  ),
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
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
                                  foregroundColor: const Color(0xFF9A96A8),
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
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(couponController.dispose);
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
              (id) => id != 'cat' && id != 'sec_male' && id != 'sec_female',
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
            child: Scrollbar(
              thumbVisibility: true,
              child: ListView.builder(
                padding: const EdgeInsets.only(right: 12),
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
    final coach = CoachConfigs.all[coachId];
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

  Widget _buildResetHourCard() {
    return GestureDetector(
      onTap: _paidSettingsTap(_showResetHourPicker),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Row(
          children: [
            const Icon(Icons.refresh, color: Color(0xFF8B7CFF), size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘의 할 일 초기화',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFEDE7FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatResetHour(_resetHour.toInt()),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF8B7CFF),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Color(0xFF8B7CFF),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatResetHour(int hour) {
    return hour == 0 ? '자정' : '새벽 ${hour}시';
  }

  Future<void> _showResetHourPicker() async {
    int selectedHour = _resetHour.round().clamp(0, 6);
    final controller = FixedExtentScrollController(initialItem: selectedHour);

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
                        '리셋 시간 선택',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          setState(() => _resetHour = selectedHour.toDouble());
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setDouble(
                            'nyang_reset_hour',
                            selectedHour.toDouble(),
                          );
                          TasksSyncService.scheduleSyncToCloud();
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
                        color: const Color(0xFFF3F0FF).withOpacity(0.72),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onSelectedItemChanged: (index) => selectedHour = index,
                    children: List.generate(7, (index) {
                      return Center(
                        child: Text(
                          _formatResetHour(index),
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

  void _showPremiumLearnSettingsModal() {
    String selectedTitle = '대표님';
    final titleController = TextEditingController();
    final maleNameController = TextEditingController();
    final femaleNameController = TextEditingController();
    TimeOfDay minSleepTime = const TimeOfDay(hour: 23, minute: 0);
    int sleepDuration = 7;
    List<Map<String, dynamic>> routines = [];
    List<Map<String, dynamic>> weekGoals = [];
    List<Map<String, dynamic>> monthGoals = [];
    List<Map<String, dynamic>> visions = [];
    bool isNightCallEnabled = false;
    bool isDailyNightCallEnabled = false;
    String selectedNightCallCoach = 'sec_male';
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
                final nightCall = prefs.getBool('nyang_night_call_enabled');
                final dailyNightCall = prefs.getBool(
                  'nyang_night_call_daily_enabled',
                );
                final nightCallCoach = prefs.getString(
                  'nyang_night_call_coach',
                );
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
                  maleNameController.text =
                      prefs.getString('nyang_coach_name_sec_male') ?? '';
                  femaleNameController.text =
                      prefs.getString('nyang_coach_name_sec_female') ?? '';
                  if (nightCall != null) isNightCallEnabled = nightCall;
                  if (dailyNightCall != null)
                    isDailyNightCallEnabled = dailyNightCall;
                  if (nightCallCoach != null)
                    selectedNightCallCoach = nightCallCoach;
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
                          const Text('👑', style: TextStyle(fontSize: 22)),
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
                  Text(
                    '✨ 입력할수록 비서가 생활 패턴을 정확히 파악해요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF9593A5),
                    ),
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

                        // 비서 애칭 설정
                        _buildLearnField(
                          icon: const Icon(
                            Icons.badge,
                            color: Color(0xFF8B7CFF),
                            size: 18,
                          ),
                          title: '비서 애칭 설정',
                          subtitle: '비서의 애칭을 정해주세요.',
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      maleNameController.clear();
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: maleNameController.text.isEmpty
                                            ? const Color(0xFFEBE5FF)
                                            : Colors.white,
                                        border: Border.all(
                                          color: maleNameController.text.isEmpty
                                              ? const Color(0xFF8B7CFF)
                                              : const Color(0xFFE5E7EB),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '남비서 코치 (기본)',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight:
                                              maleNameController.text.isEmpty
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: maleNameController.text.isEmpty
                                              ? const Color(0xFF8B7CFF)
                                              : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: maleNameController,
                                      onChanged: (val) {
                                        setState(() {});
                                      },
                                      decoration: InputDecoration(
                                        hintText: '자유 기입',
                                        hintStyle: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 13,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF9FAFB),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() {
                                      femaleNameController.clear();
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: femaleNameController.text.isEmpty
                                            ? const Color(0xFFEBE5FF)
                                            : Colors.white,
                                        border: Border.all(
                                          color:
                                              femaleNameController.text.isEmpty
                                              ? const Color(0xFF8B7CFF)
                                              : const Color(0xFFE5E7EB),
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        '여비서 코치 (기본)',
                                        style: GoogleFonts.notoSansKr(
                                          fontSize: 13,
                                          fontWeight:
                                              femaleNameController.text.isEmpty
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color:
                                              femaleNameController.text.isEmpty
                                              ? const Color(0xFF8B7CFF)
                                              : const Color(0xFF6B7280),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller: femaleNameController,
                                      onChanged: (val) {
                                        setState(() {});
                                      },
                                      decoration: InputDecoration(
                                        hintText: '자유 기입',
                                        hintStyle: TextStyle(
                                          color: Colors.grey[400],
                                          fontSize: 13,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        filled: true,
                                        fillColor: const Color(0xFFF9FAFB),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // 1. 수면
                        _buildLearnField(
                          icon: '🌙',
                          title: '컨디션 수면 기준',
                          subtitle: '다음 날 무리없는 수면 기준을 알려주세요.',
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        final time = await showTimePicker(
                                          context: context,
                                          initialTime: minSleepTime,
                                        );
                                        if (time != null) {
                                          setState(() => minSleepTime = time);
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 6,
                                          horizontal: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF3F0FF),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        borderRadius: BorderRadius.circular(8),
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
                                                return DropdownMenuItem<int>(
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
                                                      const SizedBox(width: 8),
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
                        ),

                        // 1-2. 수면·컨디션 관리
                        _buildLearnField(
                          icon: const Icon(
                            Icons.nights_stay,
                            color: Color(0xFF8B7CFF),
                            size: 18,
                          ),
                          title: '취침 기준 컨디션 케어',
                          subtitle:
                              '정한 취침 기준보다 1시간 이상 늦게 앱에 들어온 날이 이틀 연속이면, 비서가 하루 마무리와 나이트콜을 부드럽게 제안합니다.',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '비서가 눈치채서 제안하기',
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF3D3A4E),
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: isNightCallEnabled,
                                    onChanged: (val) async {
                                      setState(() {
                                        isNightCallEnabled = val;
                                      });
                                    },
                                    activeColor: const Color(0xFF8B7CFF),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                height: 1,
                                color: const Color(0xFFF0EEF8),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '매일 자동 나이트콜',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w800,
                                            color: const Color(0xFF3D3A4E),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '최소 취침 시간 2시간 전에 매일 나이트콜을 받습니다.',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: const Color(0xFF9593A5),
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isDailyNightCallEnabled,
                                    onChanged: (val) => setState(
                                      () => isDailyNightCallEnabled = val,
                                    ),
                                    activeColor: const Color(0xFF8B7CFF),
                                  ),
                                ],
                              ),
                              if (isNightCallEnabled ||
                                  isDailyNightCallEnabled) ...[
                                const SizedBox(height: 14),
                                Text(
                                  '나이트콜 담당 비서',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 11,
                                    color: const Color(0xFF9593A5),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () => setState(
                                        () =>
                                            selectedNightCallCoach = 'sec_male',
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              selectedNightCallCoach ==
                                                  'sec_male'
                                              ? const Color(0xFFEBE5FF)
                                              : Colors.white,
                                          border: Border.all(
                                            color:
                                                selectedNightCallCoach ==
                                                    'sec_male'
                                                ? const Color(0xFF8B7CFF)
                                                : const Color(0xFFE5E7EB),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '남비서 코치',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 13,
                                            fontWeight:
                                                selectedNightCallCoach ==
                                                    'sec_male'
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color:
                                                selectedNightCallCoach ==
                                                    'sec_male'
                                                ? const Color(0xFF8B7CFF)
                                                : const Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    GestureDetector(
                                      onTap: () => setState(
                                        () => selectedNightCallCoach =
                                            'sec_female',
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              selectedNightCallCoach ==
                                                  'sec_female'
                                              ? const Color(0xFFEBE5FF)
                                              : Colors.white,
                                          border: Border.all(
                                            color:
                                                selectedNightCallCoach ==
                                                    'sec_female'
                                                ? const Color(0xFF8B7CFF)
                                                : const Color(0xFFE5E7EB),
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          '여비서 코치',
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 13,
                                            fontWeight:
                                                selectedNightCallCoach ==
                                                    'sec_female'
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color:
                                                selectedNightCallCoach ==
                                                    'sec_female'
                                                ? const Color(0xFF8B7CFF)
                                                : const Color(0xFF6B7280),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                              Text(
                                '💡 세부적인 마일스톤은 목표 탭에서 작성해 주세요!',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 11,
                                  color: const Color(0xFF8B7CFF),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 4. 이번 달 목표
                        _buildLearnField(
                          icon: '🎯',
                          title: '이번 달 목표',
                          subtitle: '이번 달에 집중할 목표를 설정하세요.',
                          child: buildSyncGoalList(monthGoals, 'month'),
                        ),

                        // 5. 이번 주 목표
                        _buildLearnField(
                          icon: '🔥',
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
                        final maleName = maleNameController.text.trim();
                        final femaleName = femaleNameController.text.trim();
                        await prefs.setString(
                          'nyang_coach_name_sec_male',
                          maleName,
                        );
                        await prefs.setString(
                          'nyang_coach_name_sec_female',
                          femaleName,
                        );

                        CoachConfigs.customSecMaleName = maleName.isEmpty
                            ? null
                            : maleName;
                        CoachConfigs.customSecFemaleName = femaleName.isEmpty
                            ? null
                            : femaleName;
                        this.setState(() {
                          _secMaleWidgetName = _secretaryWidgetName(
                            maleName,
                            '남비서',
                          );
                          _secFemaleWidgetName = _secretaryWidgetName(
                            femaleName,
                            '여비서',
                          );
                          _homeWidgetStatus = _buildHomeWidgetStatus(
                            nyang:
                                prefs.getBool('widget_nyang_enabled') ?? false,
                            secMale:
                                prefs.getBool('widget_sec_male_enabled') ??
                                false,
                            secFemale:
                                prefs.getBool('widget_sec_female_enabled') ??
                                false,
                          );
                        });
                        await prefs.setBool(
                          'nyang_night_call_enabled',
                          isNightCallEnabled || isDailyNightCallEnabled,
                        );
                        await prefs.setBool(
                          'nyang_night_call_daily_enabled',
                          isDailyNightCallEnabled,
                        );
                        await prefs.setString(
                          'nyang_night_call_coach',
                          selectedNightCallCoach,
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
                        int nightCallH = minSleepTime.hour - 2;
                        if (nightCallH < 0) nightCallH += 24;
                        if (isDailyNightCallEnabled) {
                          await NotificationService().scheduleDailyNightCall(
                            hour: nightCallH,
                            minute: minSleepTime.minute,
                            coachId: selectedNightCallCoach,
                          );
                        } else {
                          await NotificationService().cancelDailyNightCall();
                        }
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('비서 학습 설정이 저장되었습니다.')),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B7CFF),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        '⚡ 비서 학습시키기',
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
        color: Colors.white,
        border: Border.all(color: const Color(0xFFF0EEF8)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B7CFF).withOpacity(0.03),
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
                  color: Color(0xFFFAF9FF),
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
                  color: const Color(0xFF3D3A4E),
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
                color: const Color(0xFF9593A5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.only(left: 46), child: child),
        ],
      ),
    );
  }

  Widget _buildPremiumLearnCard() {
    return GestureDetector(
      onTap: () {
        if (_hasMasterPlan) {
          _showPremiumLearnSettingsModal();
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비서 학습 설정은 마스터 플랜 구독자 전용입니다.')),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Column(
          children: [
            // 상단 뱃지 행
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDE7FF),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!_hasMasterPlan) ...[
                        const Icon(
                          Icons.lock,
                          size: 10,
                          color: Color(0xFF8B7CFF),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        'MASTER 전용',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF8B7CFF),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 메인 내용
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -5),
                    child: const Icon(
                      Icons.psychology_rounded,
                      size: 36,
                      color: Color(0xFF8B7CFF),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Transform.translate(
                      offset: const Offset(0, -8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '비서 학습 설정',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF3D3A4E),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '고정 일정과 취침 시간을 설정하면 비서가 더 완벽한 일정을 짜드려요.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF888899),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -5),
                    child: const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                  title: '구독 및 환불 안내',
                  subtitle: '플랜 결제와 환불 기준을 확인해요.',
                  url: _subscriptionUrl,
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
