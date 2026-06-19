import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main_tab_screen.dart';
import 'landing_screen.dart';
import 'coach_config.dart';
import '../models/user_data.dart';
import '../services/auth_service.dart';

class CoachSelectionScreen extends StatefulWidget {
  final String? returnCoachId;

  const CoachSelectionScreen({super.key, this.returnCoachId});

  @override
  State<CoachSelectionScreen> createState() => _CoachSelectionScreenState();
}

enum CoachTab { friends, master }

const _coachMint = Color(0xFF6FD3BE);
const _coachMintSoft = Color(0xFFEAF8F4);
const _coachMintText = Color(0xFF38C7A0);
const _masterGold = Color(0xFFE5B94A);

class _CoachSelectionScreenState extends State<CoachSelectionScreen> {
  String _selectedCoachId = 'cat';
  CoachTab _currentTab = CoachTab.friends;
  UserData _userData = UserData();

  int _logoTapCount = 0;
  Timer? _logoTapTimer;
  String? _lastTappedCoachId;

  void _goBack() {
    final destination = widget.returnCoachId == null
        ? const LandingScreen()
        : MainTabScreen(coachId: widget.returnCoachId!);

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 220),
      ),
    );
  }

  Future<void> _showAccountSwitchDialog() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            '다른 계정으로 로그인할까요?',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w900),
          ),
          content: Text(
            '현재 계정에서 로그아웃한 뒤 로그인 화면으로 돌아갑니다.',
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

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LandingScreen()),
      (_) => false,
    );
  }

  void _showPlanGuidePlaceholder() {
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
                                      planId: 'friends',
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
                                      planId: 'master',
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
                                      isMaster: true,
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
                                    const SizedBox(height: 14),
                                    _buildNyangCoachLearnMoreButton(),
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

  Widget _buildNyangCoachLearnMoreButton() {
    return GestureDetector(
      onTap: _showNyangCoachTeamIntro,
      child: Container(
        width: double.infinity,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF8B7CFF).withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          '냥냥코치 더 알아보기',
          style: GoogleFonts.notoSansKr(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF7D68DE),
          ),
        ),
      ),
    );
  }

  void _showNyangCoachTeamIntro() {
    final scrollController = ScrollController();
    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82,
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                  child: Row(
                    children: [
                      const Text('🐾', style: TextStyle(fontSize: 22)),
                      const SizedBox(width: 8),
                      Text(
                        '냥냥코치 팀 소개',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF8E8A9E),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
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
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Text(
                                  '계획을 세우는 것보다, 실제로\n움직이는 것이 중요하지 않을까요?',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFA78BFA),
                                    height: 1.5,
                                  ),
                                ),
                                const Positioned(
                                  top: -4,
                                  left: -6,
                                  child: Text(
                                    '“',
                                    style: TextStyle(
                                      fontSize: 42,
                                      color: Color(0xFFD8D2FF),
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const Positioned(
                                  bottom: -18,
                                  right: -4,
                                  child: Text(
                                    '”',
                                    style: TextStyle(
                                      fontSize: 42,
                                      color: Color(0xFFD8D2FF),
                                      height: 1,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.only(bottom: 24),
                            color: const Color(0xFFF0F0F5),
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/cat.png',
                            name: '냥냥코치',
                            text:
                                '그래서 냥냥코치가 태어났다냥!\n\n우리는 여러분이 다시 움직일 수 있도록 함께하는 코치들이다냥.',
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/boyfriend.png',
                            name: '남친 코치',
                            text: '프렌즈 코치들은 하기 싫은 날에도 옆에서 다정하게 응원해줘요.',
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/sec_male.png',
                            name: CoachConfigs.all['sec_male']?.name ?? '남비서 코치',
                            text:
                                '마스터 코치는 목표와 패턴을 함께 보고, 중요한 흐름을 놓치지 않게 챙겨드립니다.',
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/sec_female.png',
                            name: CoachConfigs.all['sec_female']?.name ?? '여비서 코치',
                            text:
                                '계획만 세우고 끝나는 플래너가 아니라, 행동을 함께하는 플래너. 그게 냥냥코치입니다.',
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFF0F0F5), width: 1),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const Icon(Icons.pets, size: 20),
                      label: Text(
                        '함께 시작하기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B7CFF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
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

  Widget _buildTeamIntroSpeaker({
    required String imagePath,
    required String name,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: Image.asset(
              imagePath,
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
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
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFFA78BFA),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEDEAF8)),
                  ),
                  child: Text(
                    text,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF3D3A4E),
                      height: 1.6,
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
    required String planId,
    required String title,
    required String subtitle,
    required String price,
    required String badge,
    required List<(String, String)> features,
    required bool isSelected,
    required VoidCallback onTap,
    String? originalPrice,
    String? subPrice,
    bool isMaster = false,
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
                if (isMaster)
                  const PremiumCrownIcon(size: 28)
                else
                  const SproutLineIcon(size: 30),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    title,
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
                  Row(
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
                    ],
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

  void _showSubscriptionStatusSheet() {
    final couponController = TextEditingController();
    String? errorText;
    bool isApplying = false;

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

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
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
                            const LockedCoachIcon(size: 36),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '내 구독 상태',
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
                              onPressed: () => Navigator.of(sheetContext).pop(),
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
                              child: _buildSubscriptionStatusCard(
                                label: '구독 상태',
                                value: _planStatusLabel,
                                icon: Icons.workspace_premium_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildSubscriptionStatusCard(
                                label: '포인트',
                                value: '${_userData.points}P',
                                icon: Icons.toll_rounded,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildSubscriptionStatusCard(
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
                              disabledBackgroundColor: const Color(0xFFE5E7EB),
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
                          child: TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Future.delayed(
                                Duration.zero,
                                _showAccountSwitchDialog,
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9A96A8),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
            );
          },
        );
      },
    ).whenComplete(couponController.dispose);
  }

  String get _planStatusLabel {
    if (!_userData.isPlanActive) return '미구독';
    if (_userData.planType == 'master') return 'MASTER';
    if (_userData.planType == 'friends') return 'FRIENDS';
    return '미구독';
  }

  String get _planRemainingLabel {
    if (!_userData.isPlanActive) return '구독권 없음';
    final expiresAt = _userData.planExpiresAt;
    if (expiresAt == null) return '기간 제한 없음';
    final remaining = expiresAt.difference(DateTime.now()).inDays + 1;
    if (remaining <= 0) return '만료 예정';
    return '$remaining일 남음';
  }

  Widget _buildSubscriptionStatusCard({
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
    final purchasedCoachIds = _userData.ownedCoaches
        .where((id) => id != 'cat' && id != 'sec_male' && id != 'sec_female')
        .toList();

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
    final name = _coachNameFromSelection(coachId);
    final remaining = _userData.ownedCoachRemainingLabel(coachId);
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

  String _coachNameFromSelection(String coachId) {
    final all = [..._friendsCoaches, ..._masterCoaches];
    final found = all.where((coach) => coach['id'] == coachId).toList();
    if (found.isEmpty) return coachId;
    return found.first['name']?.toString() ?? coachId;
  }

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
                  final updated = await UserDataService.load();
                  if (mounted) {
                    setState(() => _userData = updated);
                    Navigator.pop(context);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.pets, color: _coachMintText),
                title: Text(
                  '프렌즈 플랜 (friends)',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  await UserDataService.setPlan('friends');
                  final updated = await UserDataService.load();
                  if (mounted) {
                    setState(() => _userData = updated);
                    Navigator.pop(context);
                  }
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
                  final updated = await UserDataService.load();
                  if (mounted) {
                    setState(() => _userData = updated);
                    Navigator.pop(context);
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.refresh, color: Colors.blue),
                title: Text(
                  '개별 코치 구매 초기화',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w600),
                ),
                onTap: () async {
                  final data = await UserDataService.load();
                  data.ownedCoaches = [];
                  data.ownedCoachExpiresAt = {};
                  await UserDataService.save(data);
                  final updated = await UserDataService.load();
                  if (mounted) {
                    setState(() => _userData = updated);
                    Navigator.pop(context);
                  }
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
    );
  }

  void _handleCoachTap(Map<String, dynamic> coach, bool isLocked) {
    if (_lastTappedCoachId != coach['id']) {
      _logoTapCount = 0;
      _lastTappedCoachId = coach['id'];
    }
    _logoTapCount++;
    _logoTapTimer?.cancel();
    _logoTapTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
    });

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _logoTapTimer?.cancel();
      _showDebugPlanSelector();
      return;
    }

    if (isLocked) {
      _showCoachDetails(context, coach);
      return;
    }
    setState(() {
      _selectedCoachId = coach['id'];
    });
  }

  @override
  void initState() {
    super.initState();
    UserDataService.load().then((d) {
      if (mounted) setState(() => _userData = d);
    });
  }

  List<Map<String, dynamic>> get _friendsCoaches => [
    {
      'id': 'cat',
      'name': '냥냥 코치',
      'subtitle': '"딱 5분만 해보자냥."',
      'image': 'assets/images/cat.png',
      'color': _coachMint,
      'price': _userData.isPlanActive ? '플랜 포함' : '무료 입장 가능',
      'priceColor': _coachMintText,
      'priceBg': _coachMintSoft,
    },
    {
      'id': 'boyfriend',
      'name': '남친 코치',
      'subtitle': '"괜찮아. 토닥토닥"',
      'image': 'assets/images/boyfriend.png',
      'color': _coachMint,
      'price': '₩3,900 / 1년 이용',
    },
    {
      'id': 'halmae',
      'name': '할매 코치',
      'subtitle': '"내 새끼는 잘할겨"',
      'image': 'assets/images/halmae.png',
      'color': _coachMint,
      'price': '₩3,900 / 1년 이용',
    },
    {
      'id': 'girlfriend',
      'name': '여친 코치',
      'subtitle': '"오빠는 할 줄 알았어"',
      'image': 'assets/images/girlfriend.jpg',
      'color': _coachMint,
      'price': '₩3,900 / 1년 이용',
    },
    {
      'id': 'bro',
      'name': '갓생 형 코치',
      'subtitle': '"형이랑 시작해보자"',
      'image': 'assets/images/bro.png',
      'color': _coachMint,
      'price': '₩3,900 / 1년 이용',
    },
  ];

  List<Map<String, dynamic>> get _masterCoaches => [
    {
      'id': 'sec_male',
      'name': CoachConfigs.all['sec_male']?.name ?? '남비서 코치',
      'subtitle': '"우선순위부터 잡죠"',
      'image': 'assets/images/sec_male.png',
      'color': _masterGold,
      'price': 'MASTER 플랜 전용',
      'description': '복잡한 일정과 우선순위를 논리적으로 분석해 최적의 경로를 제안합니다.',
      'features': [
        {
          'icon': '🗺️',
          'title': '스마트 일정 케어',
          'sub': '목표와 연관된 중요한 일을 상기시키고 자주 미루는 일을 살펴 최적의 시간대를 잡아드려요.',
        },
        {
          'icon': '🌙',
          'title': '수면·컨디션 케어',
          'sub': '수면 패턴을 살펴 피로가 쌓이기 전에 휴식과 하루 마무리 시점을 알려드려요. 필요하면 나이트콜도 해드립니다.',
        },
        {
          'icon': '💌',
          'title': '주간 코치 리포트',
          'sub': '지난 7일의 완료 기록과 목표를 분석해 애정 어린 맞춤 피드백을 드려요.',
        },
      ],
    },
    {
      'id': 'sec_female',
      'name': CoachConfigs.all['sec_female']?.name ?? '여비서 코치',
      'subtitle': '"더 효율적인 전략은..."',
      'image': 'assets/images/sec_female.png',
      'color': _masterGold,
      'price': 'MASTER 플랜 전용',
      'description': '바쁜 하루 속에서도 무리하지 않도록, 하지만 야무지게 챙겨드려요.',
      'features': [
        {
          'icon': '🗺️',
          'title': '스마트 일정 케어',
          'sub': '목표와 연관된 중요한 일을 상기시키고 자주 미루는 일을 살펴 최적의 시간대를 잡아드려요.',
        },
        {
          'icon': '🌙',
          'title': '수면·컨디션 케어',
          'sub': '수면 패턴을 살펴 피로가 쌓이기 전에 휴식과 하루 마무리 시점을 알려드려요. 필요하면 나이트콜도 해드립니다.',
        },
        {
          'icon': '💌',
          'title': '주간 코치 리포트',
          'sub': '지난 7일의 완료 기록과 목표를 분석해 애정 어린 맞춤 피드백을 드려요.',
        },
      ],
    },
  ];

  Future<void> _purchaseCoach(
    BuildContext context,
    Map<String, dynamic> coach,
  ) async {
    // TODO: 실제 결제 연동 시 여기에 IAP 로직 추가
    // 결제 성공 가정 후 owned_coaches에 추가
    await UserDataService.addOwnedCoach(coach['id']);
    final updated = await UserDataService.load();
    if (mounted) {
      setState(() => _userData = updated);
      Navigator.pop(context); // 모달 닫기
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${coach['name']}이(가) 추가됐어요 🎉',
            style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _showCoachDetails(BuildContext context, Map<String, dynamic> coach) {
    final isFriendsCoach = !['sec_male', 'sec_female'].contains(coach['id']);
    final alreadyOwned = _userData.canAccessCoach(coach['id']);
    final planActive = _userData.isPlanActive;
    final description = (coach['description'] as String?)?.trim() ?? '';
    final features = coach['features'] as List?;
    final showsPlanRequiredNotice =
        isFriendsCoach && !alreadyOwned && !planActive;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Image.asset(
                  coach['image'],
                  width: 120,
                  height: 120,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                coach['name'],
                style: GoogleFonts.notoSansKr(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF1A1A2E),
                ),
              ),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF4B5563),
                    ),
                  ),
                ),
              ],
              if (features != null) const SizedBox(height: 24),
              // 특징 리스트 렌더링
              if (features != null)
                Column(
                  children: features.map((feat) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F0FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              feat['icon'],
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  feat['title'],
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1A1A2E),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  feat['sub'],
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              SizedBox(height: showsPlanRequiredNotice ? 16 : 32),
              // 구매 버튼 영역 (friends 코치 + 미보유 시만 표시)
              if (isFriendsCoach && !alreadyOwned) ...[
                if (!planActive)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFED7AA)),
                    ),
                    child: Row(
                      children: [
                        const Text('⚠️', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'friends 또는 master 플랜 구독 후 구매할 수 있어요.',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF92400E),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: planActive
                        ? () => _purchaseCoach(context, coach)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _coachMintText,
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      planActive ? '구매하기  ₩3,900 / 1년' : '구독 후 구매 가능',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: planActive
                            ? Colors.white
                            : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '닫기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCoaches = _currentTab == CoachTab.friends
        ? _friendsCoaches
        : _masterCoaches;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F3FF),
        body: SafeArea(
          child: Column(
            children: [
              // 상단 앱바
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: _goBack,
                      borderRadius: BorderRadius.circular(24),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Color(0xFF1A1A2E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '코치 선택',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _showSubscriptionStatusSheet,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB6A4FF),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        '내 구독 상태',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 탭 영역 (세그먼트 컨트롤 스타일)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEBE5FF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildTabButton(
                          tab: CoachTab.friends,
                          iconWidget: const SproutLineIcon(size: 30),
                          title: '프렌즈 코치',
                          subtitle: '계획 챙겨주는 친구',
                          color: _coachMint,
                        ),
                      ),
                      Expanded(
                        child: _buildTabButton(
                          tab: CoachTab.master,
                          iconWidget: const PremiumCrownIcon(size: 26),
                          title: '마스터 코치',
                          subtitle: '패턴까지 챙겨주는 비서',
                          color: _masterGold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: _buildSubscriptionGuideButton(),
              ),

              // 카드 그리드 영역
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: _currentTab == CoachTab.friends
                        ? 0.82
                        : 0.60,
                  ),
                  itemCount: activeCoaches.length,
                  itemBuilder: (context, index) {
                    final coach = activeCoaches[index];
                    final isSelected = _selectedCoachId == coach['id'];
                    final isLocked = !_userData.canAccessCoach(coach['id']);
                    final hasFullAccess = coach['id'] == 'cat'
                        ? _userData.isPlanActive
                        : !isLocked;

                    return GestureDetector(
                      onTap: () => _handleCoachTap(coach, isLocked),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelected
                                ? (_currentTab == CoachTab.friends
                                      ? _coachMint
                                      : coach['color'])
                                : Colors.transparent,
                            width: 3.5,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color:
                                    (_currentTab == CoachTab.friends
                                            ? _coachMint
                                            : coach['color'])
                                        .withOpacity(0.3),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              )
                            else
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // 상단 이미지
                            Expanded(
                              flex: 50,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(22),
                                ),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.asset(
                                      coach['image'],
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      color: isLocked
                                          ? Colors.black.withOpacity(0.3)
                                          : null,
                                      colorBlendMode: isLocked
                                          ? BlendMode.darken
                                          : null,
                                    ),
                                    if (isSelected && !isLocked)
                                      Container(
                                        color: coach['color'].withOpacity(0.1),
                                      ),
                                    if (isLocked)
                                      const Positioned(
                                        top: 10,
                                        right: 10,
                                        child: Icon(
                                          Icons.lock,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // 하단 텍스트 및 버튼
                            Expanded(
                              flex: 50,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 7,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    Text(
                                      coach['name'],
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      coach['subtitle'],
                                      textAlign: TextAlign.center,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.notoSansKr(
                                        fontSize: 12,
                                        height: 1.3,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF6B7280),
                                      ),
                                    ),
                                    const Spacer(), // 버튼을 맨 아래로 밀어줌
                                    if (_currentTab == CoachTab.friends)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hasFullAccess
                                              ? _coachMintSoft
                                              : (coach['priceBg'] ??
                                                    _coachMintSoft),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          hasFullAccess
                                              ? '보유 중 ✓'
                                              : coach['price'],
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: hasFullAccess
                                                ? _coachMintText
                                                : (coach['priceColor'] ??
                                                      _coachMintText),
                                          ),
                                        ),
                                      )
                                    else ...[
                                      InkWell(
                                        onTap: () =>
                                            _showCoachDetails(context, coach),
                                        borderRadius: BorderRadius.circular(10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                            vertical: 8,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFFFFBEB),
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Text(
                                            '더보기',
                                            style: GoogleFonts.notoSansKr(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w800,
                                              color: _masterGold,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 하단 선택하기 버튼
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                decoration: BoxDecoration(color: const Color(0xFFF5F3FF)),
                child: ElevatedButton(
                  onPressed: _userData.canAccessCoach(_selectedCoachId)
                      ? () async {
                          await UserDataService.setSelectedCoach(
                            _selectedCoachId,
                          );
                          if (!context.mounted) return;
                          Navigator.pushReplacement(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (_, __, ___) =>
                                  MainTabScreen(coachId: _selectedCoachId),
                              transitionsBuilder: (_, animation, __, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                              transitionDuration: const Duration(
                                milliseconds: 300,
                              ),
                            ),
                          );
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7B61FF),
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(
                        color: Color(0xFF7B61FF),
                        width: 1.5,
                      ),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '선택하기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
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

  Widget _buildSubscriptionGuideButton() {
    return InkWell(
      onTap: _showPlanGuidePlaceholder,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.88),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE8E3F8), width: 1.2),
        ),
        child: Row(
          children: [
            const LockedCoachIcon(size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '잠긴 코치들이 궁금하신가요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '구독 안내 보기',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: const Color(0xFFB6A4FF),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: Color(0xFFB6A4FF),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required CoachTab tab,
    required Widget iconWidget,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    final isSelected = _currentTab == tab;

    return GestureDetector(
      onTap: () {
        setState(() {
          _currentTab = tab;
          _selectedCoachId = tab == CoachTab.friends
              ? _friendsCoaches[0]['id']
              : _masterCoaches[0]['id'];
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: 16,
        ), // 세로 여백 다시 늘려서 넉넉하게 변경
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        child: Column(
          children: [
            iconWidget,
            const SizedBox(height: 6), // 글자 간격 늘림
            Text(
              title,
              style: GoogleFonts.notoSansKr(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: isSelected ? color : const Color(0xFF6B7280),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4), // 글자 간격 늘림
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.notoSansKr(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF9CA3AF),
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LockedCoachIcon extends StatelessWidget {
  final double size;
  const LockedCoachIcon({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFB6A4FF),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B7CFF).withOpacity(0.18),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(Icons.lock_rounded, size: size * 0.52, color: Colors.white),
    );
  }
}

class SproutLineIcon extends StatelessWidget {
  final double size;
  const SproutLineIcon({super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _SproutLinePainter()),
    );
  }
}

class _SproutLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _coachMint
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.08
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final stem = Path()
      ..moveTo(w * 0.5, h * 0.86)
      ..cubicTo(w * 0.52, h * 0.64, w * 0.5, h * 0.47, w * 0.44, h * 0.34);
    canvas.drawPath(stem, paint);

    final leftLeaf = Path()
      ..moveTo(w * 0.45, h * 0.36)
      ..cubicTo(w * 0.18, h * 0.16, w * 0.11, h * 0.17, w * 0.12, h * 0.28)
      ..cubicTo(w * 0.15, h * 0.47, w * 0.33, h * 0.5, w * 0.45, h * 0.36);
    canvas.drawPath(leftLeaf, paint);

    final rightLeaf = Path()
      ..moveTo(w * 0.49, h * 0.34)
      ..cubicTo(w * 0.73, h * 0.12, w * 0.91, h * 0.1, w * 0.88, h * 0.24)
      ..cubicTo(w * 0.85, h * 0.45, w * 0.66, h * 0.52, w * 0.49, h * 0.34);
    canvas.drawPath(rightLeaf, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PremiumCrownIcon extends StatelessWidget {
  final double size;
  const PremiumCrownIcon({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PremiumCrownPainter()),
    );
  }
}

class _PremiumCrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _masterGold
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final crown = Path()
      ..moveTo(w * 0.16, h * 0.78)
      ..lineTo(w * 0.16, h * 0.36)
      ..lineTo(w * 0.34, h * 0.54)
      ..lineTo(w * 0.5, h * 0.18)
      ..lineTo(w * 0.66, h * 0.54)
      ..lineTo(w * 0.84, h * 0.36)
      ..lineTo(w * 0.84, h * 0.78)
      ..close();
    canvas.drawPath(crown, paint);

    canvas.drawLine(
      Offset(w * 0.2, h * 0.84),
      Offset(w * 0.8, h * 0.84),
      paint,
    );
    canvas.drawCircle(Offset(w * 0.5, h * 0.6), w * 0.035, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
