import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../models/user_data.dart';
import '../services/tasks_sync_service.dart';
import '../services/widget_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'philosophy_intro_screen.dart';
import 'main_tab_screen.dart';
import '../theme/app_design_tokens.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_button.dart';
import '../widgets/app_card.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  _LandingScreenState createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with TickerProviderStateMixin {
  late AnimationController _introController;
  late AnimationController _controller;
  late Animation<double> _floatAnimation;

  @override
  void initState() {
    super.initState();

    // 코치 팝업 애니메이션 설정
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..forward();

    // 플로팅 애니메이션 설정
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _floatAnimation = Tween<double>(
      begin: 0,
      end: -15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await UserDataService.syncFromCloud().timeout(
        const Duration(seconds: 8),
        onTimeout: () {},
      );
      final data = await UserDataService.load();
      _enforceWidgetAccessInBackground(
        hasMasterPlan: data.isPlanActive && data.planType == 'master',
      );
      _syncTasksInBackground();

      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final widgetRoute = prefs.getString('widget_route');
      final widgetCoachId = prefs.getString('widget_coach_id');

      if (widgetRoute != null) prefs.remove('widget_route');
      if (widgetCoachId != null) prefs.remove('widget_coach_id');

      final hasWidgetIntent = widgetRoute != null || widgetCoachId != null;
      final targetCoachId = hasWidgetIntent
          ? 'cat'
          : data.selectedCoachId ?? 'cat';

      if (data.selectedCoachId != null && mounted) {
        if (!data.canAccessCoach(targetCoachId)) {
          await UserDataService.setSelectedCoach('cat');
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (context) => const PhilosophyIntroScreen(),
            ),
          );
          return;
        }

        if (hasWidgetIntent && data.selectedCoachId != 'cat') {
          await UserDataService.setSelectedCoach('cat');
        } else if (widgetCoachId != null &&
            widgetCoachId != data.selectedCoachId) {
          await UserDataService.setSelectedCoach(widgetCoachId);
        }

        final initialDrawerIdx =
            (widgetRoute == 'tasks' ||
                widgetRoute == 'tasks_done_bottom_sheet' ||
                widgetRoute == 'tasks_remaining_bottom_sheet')
            ? 1
            : 0;
        final initBottomSheet = widgetRoute == 'tasks_done_bottom_sheet'
            ? 'done'
            : widgetRoute == 'tasks_remaining_bottom_sheet'
            ? 'remaining'
            : null;

        final nav = Navigator.of(context);
        final landingRoute = ModalRoute.of(context);
        final mainRoute = MaterialPageRoute(
          builder: (context) => MainTabScreen(
            coachId: targetCoachId,
            initialDrawerIndex: initialDrawerIdx,
            initialBottomSheet: initBottomSheet,
          ),
        );

        if (landingRoute != null && landingRoute.isActive && nav.canPop()) {
          // LandingScreen 위에 모닝콜 등 다른 화면이 덮여있는 경우
          nav.replace(oldRoute: landingRoute, newRoute: mainRoute);
        } else {
          // 정상적으로 LandingScreen이 최상단일 경우
          nav.pushReplacement(mainRoute);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Auto login failed: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _enforceWidgetAccessInBackground({required bool hasMasterPlan}) {
    unawaited(
      WidgetSyncService.enforcePlanAccess(
        hasMasterPlan: hasMasterPlan,
      ).catchError((Object e, StackTrace stackTrace) {
        debugPrint('Widget access sync failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        return false;
      }),
    );
  }

  void _syncTasksInBackground() {
    unawaited(
      TasksSyncService.syncFromCloud().catchError((
        Object e,
        StackTrace stackTrace,
      ) {
        debugPrint('Task cloud sync failed: $e');
        debugPrintStack(stackTrace: stackTrace);
      }),
    );
  }

  @override
  void dispose() {
    _introController.dispose();
    _controller.dispose();
    super.dispose();
  }

  Widget _buildPopCoach(
    String imagePath,
    Offset finalOffset,
    double phaseOffset,
    double size, {
    ColorFilter? colorFilter,
    double imageScale = 1.0, // 원 내부 이미지 확대 비율
    Offset imageOffset = Offset.zero, // 원 내부 이미지 세부 조정(이동)
  }) {
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, child) {
        final curve = CurvedAnimation(
          parent: _introController,
          // 냥냥이와 거의 동시에(살짝 뒤에) 팝! 하고 나타나는 효과
          curve: const Interval(0.2, 1.0, curve: Curves.easeOutBack),
        );

        return Transform.scale(
          scale: curve.value, // 0에서 100%로 커지면서 등장
          child: Opacity(opacity: curve.value.clamp(0.0, 1.0), child: child),
        );
      },
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          // 속도를 기존의 절반으로 늦추고(2 * pi -> 1 * pi), 움직이는 폭도 살짝(6.0 -> 3.5) 줄임
          final floatY =
              math.sin(_controller.value * math.pi + phaseOffset) * 3.5;

          return Transform.translate(
            offset: Offset(finalOffset.dx, finalOffset.dy + floatY),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // 원 내부는 중앙 화이트 -> 외곽 옅은 보라색 그라데이션
                gradient: const RadialGradient(
                  colors: [AppDesignTokens.surface, AppDesignTokens.brandSoft],
                  stops: [0.6, 1.0],
                ),
                // 하얀색 테두리
                border: Border.all(color: Colors.white, width: 3.5),
                // 테두리 바깥으로 퍼지는 연보라색 그라데이션 빛(그림자) 효과
                boxShadow: [
                  BoxShadow(
                    color: AppDesignTokens.brandDisabled.withValues(alpha: 0.8),
                    blurRadius: 18.0,
                    spreadRadius: 2.0,
                  ),
                ],
              ),
              // 이미지가 원형 밖으로 나가지 않도록 클리핑
              child: ClipOval(
                child: Transform.translate(
                  offset: imageOffset,
                  child: Transform.scale(
                    scale: imageScale,
                    alignment: Alignment.topCenter, // 위쪽(얼굴 부분)을 기준으로 확대
                    child: colorFilter != null
                        ? ColorFiltered(
                            colorFilter: colorFilter,
                            child: Image.asset(
                              imagePath,
                              fit: BoxFit.cover,
                              alignment: Alignment.topCenter,
                            ),
                          )
                        : Image.asset(
                            imagePath,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCharacter({
    required double top,
    required double left,
    required String imagePath,
    required String name,
    required double size,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: SizedBox(
        width: 120, // 텍스트 길이에 상관없이 원 위치를 고정하기 위함
        child: Column(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
                image: DecorationImage(
                  image: AssetImage(imagePath),
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLoginBottomSheet() {
    final outerContext = context; // 상위 화면(LandingScreen)의 context 저장
    final showAppleLogin = defaultTargetPlatform == TargetPlatform.iOS;
    final loginButtonTopGap = showAppleLogin ? 28.0 : 24.0;
    final loginButtonBottomGap = showAppleLogin ? 16.0 : 20.0;
    showAppBottomSheet(
      context: context,
      builder: (sheetContext) {
        return AppBottomSheetScaffold(
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            0,
            24,
            AppDesignTokens.sheetContentBottomPadding,
          ),
          body: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 18),

                // 프로필 아이콘
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: AppDesignTokens.brandSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    color: AppDesignTokens.brand,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 24),

                // 텍스트
                Text(
                  '계정 연결하고\n더 편하게 사용해요',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
                SizedBox(height: loginButtonTopGap),

                if (showAppleLogin) ...[
                  _buildLoginButton(
                    text: 'Apple로 계속',
                    icon: const Icon(
                      Icons.apple,
                      size: 25,
                      color: Color(0xFF111827),
                    ),
                    onPressed: () =>
                        _handleSocialLogin(sheetContext, outerContext, 'apple'),
                  ),
                  const SizedBox(height: 12),
                ],

                _buildLoginButton(
                  text: 'Google로 계속',
                  icon: SvgPicture.string(
                    '''<svg width="22" height="22" viewBox="0 0 24 24">
  <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4" />
  <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
  <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" fill="#FBBC05" />
  <path d="M12 5.38c1.62 0 3.06.56 4.21 1.66l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
</svg>''',
                    width: 24,
                    height: 24,
                  ),
                  onPressed: () =>
                      _handleSocialLogin(sheetContext, outerContext, 'google'),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 12),
                  _buildLoginButton(
                    text: '네이버로 계속 (테스트)',
                    icon: Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF03C75A),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'N',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    onPressed: () =>
                        _showNaverTestLoginDialog(sheetContext, outerContext),
                  ),
                ],
                SizedBox(height: loginButtonBottomGap),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showNaverTestLoginDialog(
    BuildContext sheetContext,
    BuildContext outerContext,
  ) {
    showDialog<void>(
      context: sheetContext,
      builder: (dialogContext) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.radiusMedium),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF03C75A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'N',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '네이버 테스트 로그인',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '실제 네이버 계정 연동 없이\n테스트 계정으로 앱을 시작합니다.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    height: 1.5,
                    color: AppDesignTokens.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
                AppButton(
                  label: '테스트 계정으로 시작',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _handleSocialLogin(sheetContext, outerContext, 'naverTest');
                  },
                  backgroundColor: const Color(0xFF03C75A),
                  foregroundColor: Colors.white,
                  height: 48,
                ),
                const SizedBox(height: 8),
                AppButton(
                  label: '취소',
                  onPressed: () => Navigator.pop(dialogContext),
                  variant: AppButtonVariant.outline,
                  foregroundColor: AppDesignTokens.textMuted,
                  borderColor: AppDesignTokens.divider,
                  height: 44,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSocialLogin(
    BuildContext sheetContext,
    BuildContext outerContext,
    String provider,
  ) async {
    Navigator.pop(sheetContext);

    final authService = AuthService();
    final userCred = provider == 'apple'
        ? await authService.signInWithApple()
        : provider == 'naverTest'
        ? await authService.signInWithNaverTest()
        : await authService.signInWithGoogle();

    if (!outerContext.mounted) return;

    final isNaverTest = provider == 'naverTest';

    if (userCred != null || isNaverTest) {
      print(
        isNaverTest && userCred == null
            ? '네이버 테스트 로컬 세션 시작'
            : '로그인 성공: ${userCred?.user?.displayName}',
      );
      if (userCred != null) {
        await TasksSyncService.syncFromCloud();
      }
      final data = await UserDataService.load();
      if (!outerContext.mounted) return;

      final testCoachId = data.selectedCoachId ?? 'cat';
      if (isNaverTest && data.selectedCoachId == null) {
        await UserDataService.setSelectedCoach(testCoachId);
      }

      if (isNaverTest || data.canAccessCoach(testCoachId)) {
        Navigator.pushReplacement(
          outerContext,
          MaterialPageRoute(
            builder: (context) => MainTabScreen(coachId: testCoachId),
          ),
        );
      } else {
        if (data.selectedCoachId != null) {
          await UserDataService.setSelectedCoach('cat');
        }
        if (!outerContext.mounted) return;
        Navigator.pushReplacement(
          outerContext,
          MaterialPageRoute(
            builder: (context) => const PhilosophyIntroScreen(),
          ),
        );
      }
      return;
    }

    print('로그인 취소 또는 실패');
    final providerName = provider == 'apple'
        ? 'Apple'
        : provider == 'naverTest'
        ? '네이버 테스트'
        : 'Google';
    ScaffoldMessenger.of(outerContext).showSnackBar(
      SnackBar(
        content: Text('$providerName 로그인에 실패했습니다.'),
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  Widget _buildLoginButton({
    required String text,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return AppCard(
      onTap: onPressed,
      padding: EdgeInsets.zero,
      radius: AppDesignTokens.radiusMedium,
      borderColor: AppDesignTokens.divider,
      child: SizedBox(
        height: AppDesignTokens.buttonHeight,
        child: Row(
          children: [
            const SizedBox(width: 20),
            SizedBox(width: 24, child: Center(child: icon)),
            Expanded(
              child: Center(
                child: Text(
                  text,
                  style: GoogleFonts.notoSansKr(
                    fontSize: AppDesignTokens.textAction,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 44),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 모바일 뷰 고정 (최대 430px)
    final screenWidth = MediaQuery.of(context).size.width;
    final width = screenWidth > 430 ? 430.0 : screenWidth;

    return Scaffold(
      backgroundColor: AppDesignTokens.brandSoftAlt,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppDesignTokens.brandSoftAlt, AppDesignTokens.surface],
                stops: [0.0, 0.5],
              ),
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 상단 텍스트
                  Padding(
                    padding: const EdgeInsets.only(
                      top: 36.0,
                      bottom: 20.0,
                    ), // 8px 내림 (기존 28.0)
                    child: Center(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '오늘 하루',
                                style: GoogleFonts.nanumGothic(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppDesignTokens.textPrimary,
                                  letterSpacing: 0,
                                ),
                              ),
                              Positioned(
                                right: -76,
                                top: -28,
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 84,
                                  height: 84,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '코치들과 계획해요',
                            style: GoogleFonts.nanumGothic(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.brand,
                              letterSpacing: 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 중앙 일러스트 & 캐릭터
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        // 팀을 하나로 묶어주는 거대한 연보라색 배경 원 (크기 10% 축소)
                        Center(
                          child: Container(
                            width: width * 0.81,
                            height: width * 0.81,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              // 위쪽은 연보라색, 아래쪽은 바탕 화면(흰색)으로 맑게 녹아드는 그라데이션
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  AppDesignTokens.brandSoft, // 옅은 배경 연보라색
                                  Colors
                                      .white, // 바탕 화면색(흰색)으로 자연스럽게 페이드아웃 (탁한 투명화 방지)
                                ],
                                stops: [0.2, 0.8], // 부드럽게 스며드는 구간 설정
                              ),
                            ),
                          ),
                        ),

                        // 플래너 및 고양이 (중앙 애니메이션)
                        // 플래너 및 고양이 (중앙 고정 + 냥이만 애니메이션)

                        // 코치들 동시 등장 및 숨쉬는(둥둥 떠있는) 애니메이션 (원형 프로필 형태)
                        // 좌상단: 남비서
                        _buildPopCoach(
                          'assets/images/coach_sec_male_nobg.png',
                          const Offset(-100, -120), // 원래 위치로 복구 (기존 -104)
                          0.0,
                          width * 0.24, // 크기 10% 축소
                          imageScale: 1.4, // 추가 10% 확대 (총 1.4배)
                          imageOffset: const Offset(
                            8,
                            0,
                          ), // 원 안에서 얼굴 다시 왼쪽으로 8px 이동 (총 +8px)
                        ),
                        // 우상단: 여비서
                        _buildPopCoach(
                          'assets/images/coach_sec_female_nobg.png',
                          const Offset(100, -120), // 원래 위치로 복구 (기존 -104)
                          math.pi / 2,
                          width * 0.24, // 크기 10% 축소
                          imageScale: 1.4, // 추가 10% 확대 (총 1.4배)
                        ),
                        // 좌하단: 형 코치
                        _buildPopCoach(
                          'assets/images/coach_bro_nobg.png',
                          const Offset(-134, 15),
                          math.pi,
                          width * 0.24, // 크기 10% 축소
                          imageScale: 1.2, // 형 코치 얼굴 20% 확대
                          imageOffset: const Offset(
                            8,
                            0,
                          ), // 원 안에서 얼굴 오른쪽으로 8px 이동
                          // 형 코치 명도 증가
                          colorFilter: const ColorFilter.matrix([
                            1.15,
                            0,
                            0,
                            0,
                            15,
                            0,
                            1.15,
                            0,
                            0,
                            15,
                            0,
                            0,
                            1.15,
                            0,
                            15,
                            0,
                            0,
                            0,
                            1.0,
                            0,
                          ]),
                        ),
                        // 우하단: 할머니 코치
                        _buildPopCoach(
                          'assets/images/coach_halmae_nobg.png',
                          const Offset(134, 15),
                          math.pi * 1.5,
                          width * 0.24, // 크기 10% 축소
                          imageScale: 1.1, // 얼굴 10% 확대
                          // 할머니 붉은기 조절 + 전체 명도 증가 (기존보다 살짝 낮춤)
                          colorFilter: const ColorFilter.matrix([
                            0.98, 0, 0, 0, 10, // Red: 1.05 * 0.93 = 0.98
                            0, 1.05, 0, 0, 10,
                            0, 0, 1.05, 0, 10,
                            0, 0, 0, 1.0, 0,
                          ]),
                        ),

                        // 메인 고양이+플래너 합체 이미지 (숨쉬는 애니메이션)
                        Transform.translate(
                          offset: const Offset(0, 12),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _floatAnimation,
                              builder: (context, child) {
                                final scale =
                                    1.0 + (_floatAnimation.value / -15) * 0.02;
                                return Transform.scale(
                                  scale: scale,
                                  child: Transform.translate(
                                    offset: Offset(
                                      0,
                                      _floatAnimation.value * 0.4,
                                    ),
                                    child: child,
                                  ),
                                );
                              },
                              child: ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.9025,
                                  0.0,
                                  0.0,
                                  0.0,
                                  0.0, // R: 0.95(어둡게) * 0.95(붉은기 감소)
                                  0.0, 0.95, 0.0, 0.0, 0.0, // G: 0.95(어둡게)
                                  0.0, 0.0, 0.95, 0.0, 0.0, // B: 0.95(어둡게)
                                  0.0, 0.0, 0.0, 1.0, 0.0, // A: 1.0 (투명도 유지)
                                ]),
                                child: Image.asset(
                                  'assets/images/cat_planner.png',
                                  width: width * 0.55,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // 남친 코치 (좌상단) - 주석 처리 / 제거됨
                        // 남비서 코치 (우상단) - 주석 처리 / 제거됨
                        // 여비서 코치 (좌하단) - 주석 처리 / 제거됨
                        // 할매 코치 (우하단) - 주석 처리 / 제거됨
                      ],
                    ),
                  ),

                  // 하단 버튼 영역
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      40,
                      0,
                      40,
                      72,
                    ), // 좌우 패딩을 늘려 버튼 폭 약 10% 축소
                    child: Column(
                      children: [
                        // 로그인 / 가입 버튼 (프리미엄 다이어리 콘셉트)
                        GestureDetector(
                          onTap: _showLoginBottomSheet,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // 1. 우측 미니멀 인덱스 탭 (다이어리 디테일)
                              Positioned(
                                right: -6,
                                top: 16,
                                bottom: 16,
                                child: Container(
                                  width: 16,
                                  decoration: BoxDecoration(
                                    color: AppDesignTokens
                                        .brandPressed, // 버튼보다 살짝 어두운 톤
                                    borderRadius: const BorderRadius.only(
                                      topRight: Radius.circular(4),
                                      bottomRight: Radius.circular(4),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 2,
                                        offset: const Offset(2, 0),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 2. 다이어리 표지 본체
                              Container(
                                width: double.infinity,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppDesignTokens.brand,
                                  borderRadius: BorderRadius.circular(
                                    24,
                                  ), // 둘러보기 버튼과 통일
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.15,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: AppDesignTokens.brandStrong,
                                      blurRadius: 0,
                                      offset: const Offset(
                                        0,
                                        4,
                                      ), // 책의 두께감(하단 엣지)
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    // 입체감을 살리는 고급스러운 베벨(Bevel) 테두리 효과
                                    Container(
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(24),
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white.withValues(
                                              alpha: 0.25,
                                            ),
                                            Colors.transparent,
                                            Colors.black.withValues(
                                              alpha: 0.15,
                                            ),
                                          ],
                                          stops: const [0.0, 0.5, 1.0],
                                        ),
                                      ),
                                    ),
                                    // 얇은 안쪽 테두리 (가죽 스티치/프레스 라인 느낌)
                                    Padding(
                                      padding: const EdgeInsets.all(4.0),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withValues(
                                              alpha: 0.15,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 텍스트 & 아이콘
                                    const Center(
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '로그인 / 가입',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              letterSpacing:
                                                  1.0, // 고급감을 위한 자간 추가
                                            ),
                                          ),
                                          SizedBox(width: 8),
                                          Icon(
                                            Icons.arrow_forward_ios,
                                            size: 16,
                                            color: Colors.white,
                                          ), // 미니멀한 애플 스타일 화살표
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // 로그인 없이 둘러보기 버튼
                        AppButton(
                          label: '로그인 없이 둘러보기',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: () {},
                          variant: AppButtonVariant.outline,
                          backgroundColor: AppDesignTokens.surface,
                          foregroundColor: AppDesignTokens.brandPressed,
                          borderColor: AppDesignTokens.brandBorder,
                          height: 64,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
