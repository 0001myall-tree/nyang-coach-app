import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'main_tab_screen.dart';
import 'landing_screen.dart';
import 'coach_config.dart';
import '../models/user_data.dart';
import '../services/auth_service.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/app_button.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_card.dart';
import '../widgets/app_chip.dart';
import '../widgets/plan_guide_bottom_sheet.dart';

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
    showPlanGuideBottomSheet(
      context,
      onLearnMore: _showNyangCoachTeamIntro,
      checkoutLabel: '코치들과 함께하기',
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
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: Color(0xFFD8D2FF),
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '실행코치 소개',
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
                            name: '자상한 코치',
                            text: '프렌즈 코치들은 하기 싫은 날에도 옆에서 다정하게 응원해줘요.',
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/sec_male.png',
                            name:
                                CoachConfigs.all['sec_male']?.name ?? '남비서 코치',
                            text:
                                '마스터 코치는 목표와 패턴을 함께 보고, 중요한 흐름을 놓치지 않게 챙겨드립니다.',
                          ),
                          _buildTeamIntroSpeaker(
                            imagePath: 'assets/images/sec_female.png',
                            name:
                                CoachConfigs.all['sec_female']?.name ??
                                '여비서 코치',
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

  void _handleCoachTap(Map<String, dynamic> coach, bool isLocked, int index) {
    _showCoachCarouselModal(index);
  }

  void _handleTitleTap() {
    _logoTapCount++;
    _logoTapTimer?.cancel();
    _logoTapTimer = Timer(const Duration(seconds: 2), () {
      _logoTapCount = 0;
    });

    if (_logoTapCount >= 5) {
      _logoTapCount = 0;
      _logoTapTimer?.cancel();
      _showDebugPlanSelector();
    }
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
      'subtitle': '가볍게 시작',
      'image': 'assets/images/cat.png',
      'color': _coachMint,
      'price': _userData.isPlanActive ? '플랜 포함' : '무료 입장 가능',
      'priceColor': _coachMintText,
      'priceBg': _coachMintSoft,
      'tags': [
        {'icon': Icons.extension, 'text': '할 일 쪼개기'},
        {'icon': Icons.track_changes_rounded, 'text': '실행 습관'},
      ],
    },
    {
      'id': 'boyfriend',
      'name': '자상한 코치',
      'subtitle': '남친 같은 따뜻함',
      'image': 'assets/images/boyfriend.png',
      'color': _coachMint,
      'price': '₩2,900 / 1년 이용',
      'tags': [
        {'icon': Icons.favorite, 'text': '자기돌봄'},
        {'icon': Icons.local_cafe, 'text': '생활관리'},
      ],
    },
    {
      'id': 'halmae',
      'name': '할매 코치',
      'subtitle': '생활의 달인',
      'image': 'assets/images/halmae.png',
      'color': _coachMint,
      'price': '₩2,900 / 1년 이용',
      'tags': [
        {'icon': Icons.favorite, 'text': '하루 돌봄'},
        {'icon': Icons.cleaning_services, 'text': '청소 습관'},
      ],
    },
    {
      'id': 'girlfriend',
      'name': '발랄한 코치',
      'subtitle': '여친 같은 밝은 응원',
      'image': 'assets/images/girlfriend.png',
      'color': _coachMint,
      'price': '₩2,900 / 1년 이용',
      'tags': [
        {'icon': Icons.auto_awesome, 'text': '칭찬 요정'},
        {'icon': Icons.favorite, 'text': '자기돌봄'},
      ],
    },
    {
      'id': 'bro',
      'name': '갓생 형 코치',
      'subtitle': '자기관리',
      'image': 'assets/images/bro.png',
      'color': _coachMint,
      'price': '₩2,900 / 1년 이용',
      'tags': [
        {'icon': Icons.fitness_center, 'text': '운동 습관'},
        {'icon': Icons.rocket_launch, 'text': '일단 시작'},
      ],
    },
  ];

  List<Map<String, dynamic>> get _masterCoaches => [
    {
      'id': 'sec_male',
      'name': CoachConfigs.all['sec_male']?.name ?? '남비서 코치',
      'subtitle': '스마트 케어',
      'image': 'assets/images/sec_male.png',
      'color': _masterGold,
      'price': 'MASTER 플랜 전용',
      'description': '복잡한 일정과 우선순위를 논리적으로 분석해 최적의 경로를 제안합니다.',
      'tags': [
        {'svgPath': 'assets/icons/bullseye.svg', 'text': '장기목표 조력'},
        {'svgPath': 'assets/icons/route.svg', 'text': '최적 경로 제안'},
      ],
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
      'subtitle': '야무진 챙김',
      'image': 'assets/images/sec_female.png',
      'color': _masterGold,
      'price': 'MASTER 플랜 전용',
      'description': '바쁜 하루 속에서도 무리하지 않도록, 하지만 야무지게 챙겨드려요.',
      'tags': [
        {'svgPath': 'assets/icons/bullseye.svg', 'text': '장기목표 조력'},
        {'svgPath': 'assets/icons/thumbtack.svg', 'text': '미루는 항목 관리'},
      ],
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

  void _showCoachCarouselModal(int initialIndex) {
    final activeCoaches = [..._friendsCoaches, ..._masterCoaches];
    final combinedIndex = _currentTab == CoachTab.master
        ? _friendsCoaches.length + initialIndex
        : initialIndex;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        final pageController = PageController(
          initialPage: combinedIndex,
          viewportFraction: 0.85,
        );
        int currentPage = combinedIndex;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return Material(
              color: Colors.transparent,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: SafeArea(
                  child: Stack(
                    children: [
                      // Close button
                      Positioned(
                        top: 16,
                        right: 16,
                        child: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),

                      // Carousel
                      Center(
                        child: SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: PageView.builder(
                            controller: pageController,
                            onPageChanged: (idx) {
                              setModalState(() {
                                currentPage = idx;
                              });
                            },
                            itemCount: activeCoaches.length,
                            itemBuilder: (context, index) {
                              final coach = activeCoaches[index];
                              final isLocked = !_userData.canAccessCoach(
                                coach['id'],
                              );
                              final planActive = _userData.isPlanActive;
                              final isFriendsCoach = ![
                                'sec_male',
                                'sec_female',
                              ].contains(coach['id']);
                              final alreadyOwned = !isLocked;
                              final description =
                                  (coach['description'] as String?)?.trim() ??
                                  '';

                              // Scale animation for non-focused pages
                              return AnimatedBuilder(
                                animation: pageController,
                                builder: (context, child) {
                                  double value = 1.0;
                                  if (pageController.position.haveDimensions) {
                                    value = pageController.page! - index;
                                    value = (1 - (value.abs() * 0.15)).clamp(
                                      0.85,
                                      1.0,
                                    );
                                  } else if (index != currentPage) {
                                    value = 0.85;
                                  }
                                  return Transform.scale(
                                    scale: value,
                                    child: child,
                                  );
                                },
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 20,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(24),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(24),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Image section
                                        Expanded(
                                          flex: 5,
                                          child: Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.asset(
                                                coach['image'],
                                                fit: BoxFit.cover,
                                                alignment: Alignment.topCenter,
                                              ),
                                              if (isLocked)
                                                Positioned(
                                                  top: 16,
                                                  right: 16,
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      if (!isFriendsCoach)
                                                        const Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                right: 6,
                                                              ),
                                                          child: Text(
                                                            'MASTER',
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              fontSize: 12,
                                                              letterSpacing:
                                                                  1.2,
                                                              shadows: [
                                                                Shadow(
                                                                  color: Colors
                                                                      .black54,
                                                                  blurRadius: 4,
                                                                  offset:
                                                                      Offset(
                                                                        0,
                                                                        1,
                                                                      ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ),
                                                      Container(
                                                        padding:
                                                            const EdgeInsets.all(
                                                              8,
                                                            ),
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors
                                                                  .white
                                                                  .withOpacity(
                                                                    0.8,
                                                                  ),
                                                              shape: BoxShape
                                                                  .circle,
                                                            ),
                                                        child: const Icon(
                                                          Icons.lock,
                                                          color: AppDesignTokens
                                                              .textPrimary,
                                                          size: 20,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              if (alreadyOwned &&
                                                  coach['id'] != 'cat')
                                                Positioned(
                                                  top: 16,
                                                  right: 16,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 6,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withOpacity(0.95),
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
                                                          size: 14,
                                                          color: _coachMintText,
                                                        ),
                                                        const SizedBox(
                                                          width: 4,
                                                        ),
                                                        Text(
                                                          '보유',
                                                          style: GoogleFonts.notoSansKr(
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color:
                                                                _coachMintText,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ),

                                        // Info section
                                        Expanded(
                                          flex: 4,
                                          child: Padding(
                                            padding: const EdgeInsets.all(20),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  coach['name'],
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 24,
                                                    fontWeight: FontWeight.w900,
                                                    color: AppDesignTokens
                                                        .textPrimary,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  coach['subtitle'],
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: const Color(
                                                      0xFF8B7CFF,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 16),
                                                if (coach.containsKey('tags') &&
                                                    coach['tags'] != null)
                                                  Wrap(
                                                    alignment:
                                                        WrapAlignment.center,
                                                    spacing: 8,
                                                    runSpacing: 8,
                                                    children:
                                                        (coach['tags']
                                                                as List<
                                                                  Map<
                                                                    String,
                                                                    dynamic
                                                                  >
                                                                >)
                                                            .map((tag) {
                                                              return Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          6,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: Colors
                                                                      .white,
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                  border: Border.all(
                                                                    color: const Color(
                                                                      0xFFE2D8FF,
                                                                    ),
                                                                  ),
                                                                ),
                                                                child: Row(
                                                                  mainAxisSize:
                                                                      MainAxisSize
                                                                          .min,
                                                                  children: [
                                                                    if (tag.containsKey(
                                                                      'svgPath',
                                                                    ))
                                                                      SvgPicture.asset(
                                                                        tag['svgPath']
                                                                            as String,
                                                                        width:
                                                                            14,
                                                                        height:
                                                                            14,
                                                                        colorFilter: const ColorFilter.mode(
                                                                          Color(
                                                                            0xFF8B7CFF,
                                                                          ),
                                                                          BlendMode
                                                                              .srcIn,
                                                                        ),
                                                                      )
                                                                    else
                                                                      Icon(
                                                                        tag['icon']
                                                                            as IconData,
                                                                        size:
                                                                            14,
                                                                        color: const Color(
                                                                          0xFF8B7CFF,
                                                                        ),
                                                                      ),
                                                                    const SizedBox(
                                                                      width: 4,
                                                                    ),
                                                                    Text(
                                                                      tag['text']
                                                                          as String,
                                                                      style: GoogleFonts.notoSansKr(
                                                                        fontSize:
                                                                            12,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        color: const Color(
                                                                          0xFF8B7CFF,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),
                                                              );
                                                            })
                                                            .toList(),
                                                  )
                                                else if (description.isNotEmpty)
                                                  Text(
                                                    description,
                                                    textAlign: TextAlign.center,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: AppDesignTokens
                                                              .textSecondary,
                                                          height: 1.5,
                                                        ),
                                                  )
                                                else if (isLocked &&
                                                    isFriendsCoach &&
                                                    !planActive)
                                                  Text(
                                                    '따뜻하게 다가오는 코치에요.\n지친 하루 끝에, 당신을 다정하게 챙겨줍니다.',
                                                    textAlign: TextAlign.center,
                                                    style:
                                                        GoogleFonts.notoSansKr(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                          color: AppDesignTokens
                                                              .textSecondary,
                                                          height: 1.5,
                                                        ),
                                                  ),

                                                const Spacer(),

                                                if (isLocked)
                                                  AppButton(
                                                    label: !planActive
                                                        ? '구독 안내 보기'
                                                        : (isFriendsCoach
                                                              ? '1년 이용 / 2,900원'
                                                              : '플랜 업그레이드'),
                                                    onPressed: () {
                                                      if (!planActive ||
                                                          !isFriendsCoach) {
                                                        Navigator.pop(context);
                                                        _showPlanGuidePlaceholder();
                                                      } else {
                                                        _purchaseCoach(
                                                          context,
                                                          coach,
                                                        );
                                                      }
                                                    },
                                                    backgroundColor:
                                                        AppDesignTokens
                                                            .brandAccent,
                                                  )
                                                else
                                                  AppButton(
                                                    label: '이 코치 선택하기',
                                                    onPressed: () async {
                                                      await UserDataService.setSelectedCoach(
                                                        coach['id'],
                                                      );
                                                      if (!mounted) return;
                                                      setState(() {
                                                        _selectedCoachId =
                                                            coach['id'];
                                                      });
                                                      Navigator.pop(context);
                                                      Navigator.pushReplacement(
                                                        context,
                                                        PageRouteBuilder(
                                                          pageBuilder:
                                                              (
                                                                _,
                                                                __,
                                                                ___,
                                                              ) => MainTabScreen(
                                                                coachId:
                                                                    coach['id'],
                                                              ),
                                                          transitionsBuilder:
                                                              (
                                                                _,
                                                                animation,
                                                                __,
                                                                child,
                                                              ) {
                                                                return FadeTransition(
                                                                  opacity:
                                                                      animation,
                                                                  child: child,
                                                                );
                                                              },
                                                          transitionDuration:
                                                              const Duration(
                                                                milliseconds:
                                                                    300,
                                                              ),
                                                        ),
                                                      );
                                                    },
                                                    backgroundColor:
                                                        const Color(0xFF8B7CFF),
                                                    foregroundColor:
                                                        Colors.white,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                      // Left arrow
                      Positioned(
                        left: 10,
                        top: MediaQuery.of(context).size.height * 0.35,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            if (currentPage > 0) {
                              pageController.previousPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),

                      // Right arrow
                      Positioned(
                        right: 10,
                        top: MediaQuery.of(context).size.height * 0.35,
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            if (currentPage < activeCoaches.length - 1) {
                              pageController.nextPage(
                                duration: const Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                              );
                            }
                          },
                        ),
                      ),

                      // Page indicators
                      Positioned(
                        bottom: MediaQuery.of(context).size.height * 0.1,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(activeCoaches.length, (
                            index,
                          ) {
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: currentPage == index ? 10 : 8,
                              height: currentPage == index ? 10 : 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: currentPage == index
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.4),
                              ),
                            );
                          }),
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
        backgroundColor: AppDesignTokens.brandSoft,
        body: SafeArea(
          child: Column(
            children: [
              // 상단 앱바
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _showPlanGuidePlaceholder,
                        style: TextButton.styleFrom(
                          foregroundColor: AppDesignTokens.brandAccent,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '구독 안내 >',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Center(
                      child: GestureDetector(
                        onTap: _handleTitleTap,
                        behavior: HitTestBehavior.opaque,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.notoSansKr(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.textPrimary,
                              letterSpacing: -0.5,
                              height: 1.4,
                            ),
                            children: [
                              const TextSpan(text: '오늘을 함께할\n'),
                              TextSpan(
                                text: '실행 코치',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppDesignTokens.brandAccent,
                                ),
                              ),
                              const TextSpan(text: '를 선택해 보세요'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),

              // 탭 영역 (세그먼트 컨트롤 스타일)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildTabButton(
                        tab: CoachTab.friends,
                        title: '프렌즈 코치',
                        color: _coachMint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTabButton(
                        tab: CoachTab.master,
                        title: '마스터 코치',
                        color: _masterGold,
                      ),
                    ),
                  ],
                ),
              ),

              // 카드 그리드 영역
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 24,
                    crossAxisSpacing: 20,
                    childAspectRatio: 0.8,
                  ),
                  itemCount: activeCoaches.length,
                  itemBuilder: (context, index) {
                    final coach = activeCoaches[index];
                    final isSelected = _selectedCoachId == coach['id'];
                    final isLocked = !_userData.canAccessCoach(coach['id']);
                    final hasFullAccess = coach['id'] == 'cat'
                        ? _userData.isPlanActive
                        : !isLocked;
                    final coachAccent = _currentTab == CoachTab.friends
                        ? _coachMint
                        : coach['color'] as Color;

                    return AnimatedScale(
                      scale: isSelected ? 1.03 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: AppCard(
                          onTap: () => _handleCoachTap(coach, isLocked, index),
                          padding: EdgeInsets.zero,
                          selected: false,
                          borderColor: Colors.transparent,
                          radius: AppDesignTokens.cardRadius,
                          shadows: [
                            if (isSelected)
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              )
                            else
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                          ],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 상단 이미지
                              Expanded(
                                flex: 65,
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
                                            ? Colors.black.withValues(
                                                alpha: 0.3,
                                              )
                                            : null,
                                        colorBlendMode: isLocked
                                            ? BlendMode.darken
                                            : null,
                                      ),

                                      if (isLocked)
                                        Positioned(
                                          top: 10,
                                          right: 10,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_currentTab ==
                                                  CoachTab.master)
                                                const Padding(
                                                  padding: EdgeInsets.only(
                                                    right: 4,
                                                  ),
                                                  child: Text(
                                                    'MASTER',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      fontSize: 11,
                                                      letterSpacing: 1.2,
                                                    ),
                                                  ),
                                                ),
                                              const Icon(
                                                Icons.lock,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (hasFullAccess)
                                        Positioned(
                                          top: 10,
                                          right: 10,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.95,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.check,
                                                  size: 11,
                                                  color: _coachMintText,
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '보유',
                                                  style: GoogleFonts.notoSansKr(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w800,
                                                    color: _coachMintText,
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
                              // 하단 텍스트
                              // FittedBox로 감싸서 기종/폰트 설정에 따라 텍스트 블록이
                              // 살짝 축소되더라도 절대 오버플로우가 나지 않게 한다.
                              Expanded(
                                flex: 35,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 12,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          coach['name'],
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            color: AppDesignTokens.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          coach['subtitle'],
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.notoSansKr(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color:
                                                AppDesignTokens.textSecondary,
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
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabButton({
    required CoachTab tab,
    required String title,
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? const Color(0xFF8B7CFF) : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: isSelected
                ? const Color(0xFF8B7CFF)
                : AppDesignTokens.textDisabled,
          ),
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
        color: AppDesignTokens.brandAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppDesignTokens.brand.withValues(alpha: 0.18),
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
