import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_design_tokens.dart';
import 'coach_selection_screen.dart';

class PhilosophyIntroScreen extends StatefulWidget {
  const PhilosophyIntroScreen({super.key});

  @override
  State<PhilosophyIntroScreen> createState() => _PhilosophyIntroScreenState();
}

class _PhilosophyIntroScreenState extends State<PhilosophyIntroScreen> {
  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    _transitionTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const CoachSelectionScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF), // 연한 연보라 배경
      body: Stack(
        children: [
          // 하단 물결 데코레이션 (미니멀 그래픽)
          Positioned.fill(
            child: CustomPaint(
              painter: BottomWavesPainter(),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    
                    // 메인 철학 문구
                    Text(
                      '좋은 계획보다\n중요한 것은',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                        color: AppDesignTokens.textPrimary,
                        height: 1.55,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '실행입니다.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: AppDesignTokens.textPrimary,
                        letterSpacing: -1.0,
                      ),
                    ),
                    
                    // 구분선 (브랜드 연보라색 포인트)
                    const SizedBox(height: 28),
                    Container(
                      width: 24,
                      height: 2.5,
                      decoration: BoxDecoration(
                        color: AppDesignTokens.brandAccent,
                        borderRadius: BorderRadius.circular(1.2),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // 설명 및 핵심 포인트
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppDesignTokens.textSecondary,
                          height: 1.6,
                          letterSpacing: -0.2,
                        ),
                        children: [
                          const TextSpan(text: '사람마다 실행하는 방식은 다릅니다.\n당신에게 맞는 '),
                          TextSpan(
                            text: '실행 코치',
                            style: GoogleFonts.notoSansKr(
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.brand,
                            ),
                          ),
                          const TextSpan(text: '를 준비하고 있습니다.'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 52),
                    
                    // 점 3개 로딩 애니메이션
                    const ThreeDotLoader(),

                    const Spacer(flex: 4),

                    // 하단 브랜드 명칭
                    Padding(
                      padding: const EdgeInsets.only(bottom: 36.0),
                      child: Column(
                        children: [
                          RichText(
                            text: TextSpan(
                              style: GoogleFonts.notoSansKr(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppDesignTokens.brand,
                                letterSpacing: 0.8,
                              ),
                              children: [
                                const TextSpan(text: '냥냥코치'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'AI 실행 플래너',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppDesignTokens.textMuted,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
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
}

// 점 3개 순차 애니메이션 (로더)
class ThreeDotLoader extends StatefulWidget {
  const ThreeDotLoader({super.key});

  @override
  State<ThreeDotLoader> createState() => _ThreeDotLoaderState();
}

class _ThreeDotLoaderState extends State<ThreeDotLoader>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0.3, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    _startAnimations();
  }

  void _startAnimations() async {
    for (int i = 0; i < 3; i++) {
      if (!mounted) return;
      _controllers[i].repeat(reverse: true);
      await Future.delayed(const Duration(milliseconds: 180));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (index) {
        return FadeTransition(
          opacity: _animations[index],
          child: ScaleTransition(
            scale: _animations[index],
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 5),
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppDesignTokens.brandAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}

// 하단 미니멀 연보라 물결 칠하는 페인터
class BottomWavesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 뒤쪽 옅은 연보라 물결
    final paint1 = Paint()
      ..color = const Color(0xFFF1EEFC)
      ..style = PaintingStyle.fill;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.85);
    path1.cubicTo(
      size.width * 0.25,
      size.height * 0.80,
      size.width * 0.65,
      size.height * 0.92,
      size.width,
      size.height * 0.82,
    );
    path1.lineTo(size.width, size.height);
    path1.lineTo(0, size.height);
    path1.close();
    canvas.drawPath(path1, paint1);

    // 앞쪽 조금 더 선명한 연보라 물결
    final paint2 = Paint()
      ..color = const Color(0xFFEBE3FF)
      ..style = PaintingStyle.fill;

    final path2 = Path();
    path2.moveTo(0, size.height * 0.91);
    path2.cubicTo(
      size.width * 0.35,
      size.height * 0.86,
      size.width * 0.75,
      size.height * 0.96,
      size.width,
      size.height * 0.89,
    );
    path2.lineTo(size.width, size.height);
    path2.lineTo(0, size.height);
    path2.close();
    canvas.drawPath(path2, paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
