import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nyang_coach/screens/coach_selection_screen.dart';
import 'package:nyang_coach/services/analytics_service.dart';
import 'package:nyang_coach/services/api_usage_limit_service.dart';
import 'package:nyang_coach/services/apple_calendar_sync_service.dart';
import 'package:nyang_coach/services/tasks_sync_service.dart';
import 'package:nyang_coach/services/user_title_service.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/coach_id_service.dart';
import 'package:nyang_coach/services/local_reply_texts.dart';
import 'package:nyang_coach/services/master_bedtime_offer_copy.dart';
import 'package:nyang_coach/services/master_greeting.dart';
import 'package:nyang_coach/services/task_resistance_service.dart';
import 'package:nyang_coach/services/execution_resistance_service.dart';
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

  /// 선택 카드가 보여줄 버튼 라벨. 메시지에 박아두는 이유는, 카드를 그릴 때마다
  /// 지금 할 일 목록을 다시 읽으면 지나간 카드의 버튼까지 뒤늦게 바뀌기 때문이다.
  final List<String> choices;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.time,
    this.kind,
    this.highlightVisionIds = const [],
    this.choices = const [],
  });

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
    if (kind != null) 'kind': kind,
    if (highlightVisionIds.isNotEmpty) 'highlightVisionIds': highlightVisionIds,
    if (choices.isNotEmpty) 'choices': choices,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    text: j['text'],
    isUser: j['isUser'],
    time: DateTime.parse(j['time']),
    kind: j['kind'],
    highlightVisionIds:
        (j['highlightVisionIds'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    choices:
        (j['choices'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

enum _CountdownFocusPhase { breathing, countdown, ready, timer }

enum _MasterModelPolicy { generalLimited, premiumFeature, forceGpt4oMini }

class CountdownFocusModeScreen extends StatefulWidget {
  const CountdownFocusModeScreen({super.key});

  @override
  State<CountdownFocusModeScreen> createState() =>
      _CountdownFocusModeScreenState();
}

class _CountdownFocusModeScreenState extends State<CountdownFocusModeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _timerTotalSeconds = 10 * 60;
  // 도입부 호흡 안내: 원이 커졌다 줄어드는 한 호흡(4초)을 2번 반복한다.
  static const _breathCycle = Duration(seconds: 4);
  static const _breathCount = 2;

  late final AnimationController _breathCtrl;
  Timer? _flowTimer;
  Timer? _focusTimer;
  _CountdownFocusPhase _phase = _CountdownFocusPhase.breathing;
  int _countdownValue = 5;
  int _remainingSeconds = _timerTotalSeconds;
  bool _timerRunning = false;

  /// 벽시계 기준 종료 시각. 화면이 꺼지거나 앱이 백그라운드로 가면 1초 틱이
  /// 정지되므로, 틱 횟수 대신 이 시각과의 차이로 남은 시간을 계산한다.
  DateTime? _timerEndAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breathCtrl = AnimationController(vsync: this, duration: _breathCycle)
      ..repeat();
    _startIntroFlow();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 백그라운드에서 돌아오면 실제 흘러간 시간만큼 즉시 따라잡는다.
    if (state == AppLifecycleState.resumed &&
        _phase == _CountdownFocusPhase.timer &&
        _timerRunning) {
      _syncRemainingFromClock();
    }
  }

  void _startIntroFlow() {
    // 호흡 3번(_breathCycle * 3)을 마친 뒤 카운트다운으로 넘어간다.
    _flowTimer = Timer(_breathCycle * _breathCount, () {
      if (!mounted) return;
      _breathCtrl.stop();
      setState(() {
        _phase = _CountdownFocusPhase.countdown;
        _countdownValue = 5;
      });
      _flowTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_countdownValue <= 1) {
          timer.cancel();
          setState(() => _phase = _CountdownFocusPhase.ready);
          return;
        }
        setState(() => _countdownValue -= 1);
      });
    });
  }

  void _startFocusTimer() {
    _focusTimer?.cancel();
    setState(() {
      _phase = _CountdownFocusPhase.timer;
      _remainingSeconds = _timerTotalSeconds;
      _timerRunning = true;
      _timerEndAt = DateTime.now().add(
        const Duration(seconds: _timerTotalSeconds),
      );
    });
    _focusTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_timerRunning) return;
      _syncRemainingFromClock();
    });
  }

  void _syncRemainingFromClock() {
    final endAt = _timerEndAt;
    if (endAt == null || !mounted) return;
    final remaining = endAt.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _focusTimer?.cancel();
      setState(() {
        _remainingSeconds = 0;
        _timerRunning = false;
        _timerEndAt = null;
      });
      HapticFeedback.vibrate();
      // 시작 대비 완주 비율로 이 개입이 실제로 붙잡아 두는지 본다.
      unawaited(AnalyticsService.logFeatureUsage('countdown_complete'));
      return;
    }
    if (remaining != _remainingSeconds) {
      setState(() => _remainingSeconds = remaining);
    }
  }

  void _toggleTimer() {
    if (_phase != _CountdownFocusPhase.timer) return;
    setState(() {
      if (_timerRunning) {
        // 일시정지: 지금까지 남은 시간을 고정해 두고 종료 시각은 비운다.
        final endAt = _timerEndAt;
        if (endAt != null) {
          _remainingSeconds = endAt
              .difference(DateTime.now())
              .inSeconds
              .clamp(0, _timerTotalSeconds);
        }
        _timerEndAt = null;
        _timerRunning = false;
      } else {
        // 재개: 고정해 둔 남은 시간만큼 뒤를 새 종료 시각으로 잡는다.
        _timerEndAt = DateTime.now().add(Duration(seconds: _remainingSeconds));
        _timerRunning = true;
      }
    });
  }

  Future<void> _requestExitTimer() async {
    final shouldExit =
        await showDialog<bool>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.58),
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: const Color(0xFF17132B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                '집중을 끝내고 채팅으로 돌아갈까요?',
                style: GoogleFonts.notoSansKr(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text(
                    '계속 집중',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFC9B7FF),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text(
                    '돌아가기',
                    style: GoogleFonts.notoSansKr(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;
    if (shouldExit && mounted) Navigator.pop(context);
  }

  void _handleClose() {
    if (_phase == _CountdownFocusPhase.timer) {
      _requestExitTimer();
      return;
    }
    Navigator.pop(context);
  }

  String _formatRemaining() {
    final minutes = _remainingSeconds ~/ 60;
    final seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _flowTimer?.cancel();
    _focusTimer?.cancel();
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _CountdownFocusPhase.timer,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _CountdownFocusPhase.timer) {
          _requestExitTimer();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF08091A),
        body: Stack(
          children: [
            Positioned.fill(child: _buildBackground()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: _handleClose,
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.white.withValues(alpha: 0.86),
                        iconSize: 24,
                        tooltip: '닫기',
                      ),
                    ),
                    Expanded(child: _buildPhaseContent()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.18),
          radius: 1.05,
          colors: [Color(0xFF1A1735), Color(0xFF0B0C21), Color(0xFF070817)],
          stops: [0.0, 0.52, 1.0],
        ),
      ),
    );
  }

  Widget _buildPhaseContent() {
    switch (_phase) {
      case _CountdownFocusPhase.breathing:
        return _buildBreathing();
      case _CountdownFocusPhase.countdown:
        return _buildCountdown();
      case _CountdownFocusPhase.ready:
        return _buildReady();
      case _CountdownFocusPhase.timer:
        return _buildTimer();
    }
  }

  Widget _buildBreathing() {
    final scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.86, end: 1.06), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 0.92), weight: 50),
    ]).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    return Column(
      children: [
        const Spacer(flex: 2),
        Text(
          '잠시 생각을 내려놓고\n숨을 천천히 쉬어요.',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 22,
            height: 1.45,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '천천히 들이마시고 내쉬세요.',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 58),
        AnimatedBuilder(
          animation: scale,
          builder: (_, child) =>
              Transform.scale(scale: scale.value, child: child),
          child: _buildGlowCircle(size: 218),
        ),
        const Spacer(flex: 3),
      ],
    );
  }

  Widget _buildCountdown() {
    return Column(
      children: [
        const Spacer(flex: 3),
        _buildGlowCircle(
          size: 230,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 430),
            transitionBuilder: (child, animation) {
              final scale = Tween<double>(begin: 0.86, end: 1.08).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              );
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(scale: scale, child: child),
              );
            },
            child: Text(
              '$_countdownValue',
              key: ValueKey(_countdownValue),
              style: GoogleFonts.inter(
                fontSize: 86,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const Spacer(flex: 4),
      ],
    );
  }

  Widget _buildReady() {
    return Column(
      children: [
        const Spacer(flex: 2),
        _buildGlowCircle(
          size: 220,
          child: const Icon(Icons.check_rounded, size: 82, color: Colors.white),
        ),
        const SizedBox(height: 42),
        Text(
          '이제 시작해볼까요?',
          textAlign: TextAlign.center,
          style: GoogleFonts.notoSansKr(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const Spacer(flex: 3),
        _buildPrimaryButton('시작하기', _startFocusTimer),
      ],
    );
  }

  Widget _buildTimer() {
    final progress = 1 - (_remainingSeconds / _timerTotalSeconds);
    return Column(
      children: [
        const Spacer(flex: 3),
        SizedBox(
          width: 260,
          height: 260,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 236,
                height: 236,
                child: CircularProgressIndicator(
                  value: progress.clamp(0, 1),
                  strokeWidth: 2.8,
                  backgroundColor: const Color(
                    0xFF4E3C87,
                  ).withValues(alpha: 0.25),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF9E7CFF)),
                  strokeCap: StrokeCap.round,
                ),
              ),
              Text(
                _formatRemaining(),
                style: GoogleFonts.inter(
                  fontSize: 56,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const Spacer(flex: 4),
        Row(
          children: [
            Expanded(
              child: _buildSecondaryButton(
                _timerRunning ? '일시정지' : '계속하기',
                _toggleTimer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _buildSecondaryButton('돌아가기', _requestExitTimer)),
          ],
        ),
      ],
    );
  }

  Widget _buildGlowCircle({required double size, Widget? child}) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFCEB8FF), Color(0xFF9A71E3), Color(0xFF6F54B5)],
          stops: [0.0, 0.62, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB995FF).withValues(alpha: 0.34),
            blurRadius: 38,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFFB995FF).withValues(alpha: 0.16),
            blurRadius: 76,
            spreadRadius: 18,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPrimaryButton(String label, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF6F5EA8),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(String label, VoidCallback onTap) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF5C4B86).withValues(alpha: 0.78),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        label,
        style: GoogleFonts.notoSansKr(
          fontSize: 14,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ── 수면 도우미 모드 (1분 복식호흡) ─────────────────────────
// 카운트다운 모드의 전체화면 다크 오버레이 구조를 재활용하되,
// 느리고 반복적인 원 확대·축소로 화면에서 이탈(휴대폰 내려놓기)하도록 유도한다.
enum _SleepPhase { breathing, ending, resting, menu }

class SleepAssistModeScreen extends StatefulWidget {
  const SleepAssistModeScreen({super.key});

  @override
  State<SleepAssistModeScreen> createState() => _SleepAssistModeScreenState();
}

class _SleepAssistModeScreenState extends State<SleepAssistModeScreen>
    with SingleTickerProviderStateMixin {
  static const _inhale = Duration(seconds: 4); // 들이마시기: 천천히 커짐
  static const _exhale = Duration(seconds: 5); // 내쉬기: 더 천천히 작아짐
  static const _sessionDuration = Duration(seconds: 60); // 약 1분(≈6회)
  static const _bg = Color(0xFF04040A);

  late final AnimationController _breathCtrl;
  Timer? _sessionTimer;
  Timer? _introTimer;
  Timer? _endTimer;
  _SleepPhase _phase = _SleepPhase.breathing;
  bool _showCues = false;

  @override
  void initState() {
    super.initState();
    _breathCtrl = AnimationController(vsync: this, duration: _inhale + _exhale);
    _startSession();
  }

  void _startSession() {
    _phase = _SleepPhase.breathing;
    _showCues = false;
    _breathCtrl
      ..reset()
      ..repeat();
    // 첫 안내를 한 호흡(≈9초)간 보여준 뒤 짧은 호흡 문구로 교체한다.
    _introTimer = Timer(_inhale + _exhale, () {
      if (mounted) setState(() => _showCues = true);
    });
    _sessionTimer = Timer(_sessionDuration, _startEnding);
  }

  void _startEnding() {
    if (!mounted) return;
    _breathCtrl.stop();
    setState(() => _phase = _SleepPhase.ending);
    // 마지막 안내를 약 7초 보여준 뒤 거의 완전히 검은 화면으로 전환한다.
    _endTimer = Timer(const Duration(seconds: 7), () {
      if (mounted) setState(() => _phase = _SleepPhase.resting);
    });
  }

  void _restart() {
    _sessionTimer?.cancel();
    _introTimer?.cancel();
    _endTimer?.cancel();
    setState(_startSession);
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _introTimer?.cancel();
    _endTimer?.cancel();
    _breathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: switch (_phase) {
        _SleepPhase.breathing || _SleepPhase.ending => _buildBreathingScreen(),
        _SleepPhase.resting => GestureDetector(
          onTap: () => setState(() => _phase = _SleepPhase.menu),
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
        _SleepPhase.menu => _buildMenu(),
      },
    );
  }

  Widget _buildBreathingScreen() {
    final ending = _phase == _SleepPhase.ending;
    final scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.72, end: 1.12),
        weight: _inhale.inMilliseconds.toDouble(),
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.12, end: 0.72),
        weight: _exhale.inMilliseconds.toDouble(),
      ),
    ]).animate(CurvedAnimation(parent: _breathCtrl, curve: Curves.easeInOut));

    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.1,
                colors: [Color(0xFF15122B), Color(0xFF0A0A1C), _bg],
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),
        ),
        // 호흡 콘텐츠 (종료 시 천천히 흐려짐)
        AnimatedOpacity(
          opacity: ending ? 0 : 1,
          duration: const Duration(milliseconds: 1400),
          curve: Curves.easeInOut,
          child: SafeArea(
            child: Column(
              children: [
                // 종료 버튼은 눈에 띄지 않게 최소화
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.white.withValues(alpha: 0.26),
                      iconSize: 22,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                _buildGuidanceText(),
                const SizedBox(height: 44),
                AnimatedBuilder(
                  animation: scale,
                  builder: (_, child) =>
                      Transform.scale(scale: scale.value, child: child),
                  child: _buildSleepCircle(206),
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
        // 종료 안내 (천천히 나타남)
        AnimatedOpacity(
          opacity: ending ? 1 : 0,
          duration: const Duration(milliseconds: 1600),
          curve: Curves.easeInOut,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36),
              child: Text(
                '충분히 편안해지셨다면 이제 휴대폰을 내려놓으세요.\n눈을 감고, 방금처럼 편안하게 숨을 이어가시면 됩니다.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  height: 1.7,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGuidanceText() {
    if (!_showCues) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          children: [
            Text(
              '딱 1분만, 몸의 힘을 빼고 천천히 호흡해 보세요.\n배가 부풀고 가라앉는 감각에만 집중해 주세요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 18,
                height: 1.55,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '어지럽거나 불편하면 평소 호흡으로 돌아가도 괜찮아요.',
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }
    // 원의 움직임에 맞춰 들이마시기/내쉬기 문구를 교체한다.
    final inhaleRatio =
        _inhale.inMilliseconds / (_inhale + _exhale).inMilliseconds;
    return AnimatedBuilder(
      animation: _breathCtrl,
      builder: (_, __) {
        final cue = _breathCtrl.value < inhaleRatio
            ? '천천히 들이마셔요'
            : '더 천천히 내쉬어요';
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Text(
            cue,
            key: ValueKey(cue),
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.92),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMenu() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: _restart,
            child: Text(
              '다시 시작',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.72),
              ),
            ),
          ),
          const SizedBox(height: 18),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '종료',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepCircle(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFCEB8FF), Color(0xFF9A71E3), Color(0xFF6F54B5)],
          stops: [0.0, 0.62, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFB995FF).withValues(alpha: 0.30),
            blurRadius: 40,
            spreadRadius: 8,
          ),
          BoxShadow(
            color: const Color(0xFFB995FF).withValues(alpha: 0.14),
            blurRadius: 80,
            spreadRadius: 18,
          ),
        ],
      ),
    );
  }
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
  final String freq;
  final List<int> days;
  final int? weeklyTargetCount;
  final int? countGoal;
  final String? unit;
  final TimeOfDay? time;
  final TimeOfDay? endTime;
  final String? habitDuration;

  _ParsedHabitRegistration({
    required this.title,
    required this.freq,
    required this.days,
    this.weeklyTargetCount,
    this.countGoal,
    this.unit,
    this.time,
    this.endTime,
    this.habitDuration,
  });
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
  final String? ultraLowResistanceFollowup;
  final bool startCountdown;
  final List<_SuggestedTask> suggestedTasks;
  _ParsedReply({
    required this.text,
    required this.chips,
    this.suppressDefaultChips = false,
    this.coachSwitchTarget,
    this.timerConfirmMinutes,
    this.timerConfirmTaskName,
    this.visionSourceId,
    this.ultraLowResistanceFollowup,
    this.startCountdown = false,
    List<_SuggestedTask>? suggestedTasks,
  }) : suggestedTasks = suggestedTasks ?? [];
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
        '어디 갔다 왔어? 없으니까 좀 허전하더라... 💙',
        '솔직히 보고 싶었어. 많이. 이제 같이 하자 🥹',
      ],
      'status': [
        '오늘 밥은 챙겨먹었어? 잠은 좀 잤고?',
        '오늘 얼마나 했는지도 궁금한데, 네 컨디션부터 먼저 걱정돼 💙',
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
    'nyang_halbae': {
      'greet': [
        '대표님, 복귀하셨습니까? 다음 캘린더 일정을 확인하겠습니다.',
        '기다리고 있었습니다. 지금 바로 업무 보고를 시작할까요?',
        '휴식은 충분하셨는지요. 다시 업무 모드로 전환하겠습니다.',
      ],
      'status': ['현재 업무 진행률을 확인해 드릴까요?', '대표님, 다음 우선순위를 제가 체크해 두었습니다.'],
    },
    'sec_female': {
      'greet': [
        '대표님! 보고 싶었어요~ 이제 다시 저랑 같이 달려봐요! 🌸',
        '오셨네요! 오늘 캘린더도 제가 꼼꼼히 챙겨드릴게요.',
        '대표님 기다리고 있었어요! 다시 시작해볼까요?',
      ],
      'status': ['오늘 얼마나 하셨는지 궁금해요! 살짝 알려주세요 🌸', '제가 옆에서 계속 지켜보고 있으니까 힘내세요!'],
    },
  };

  static String? get(String coachId, String msg) {
    // 비서 코치는 일정·상태 관련 단어가 감정이나 일반 대화 안에서도 자주
    // 등장하므로, 키워드만으로 문맥을 가로채지 않고 항상 AI가 전체 대화를 본다.
    if (coachId == 'nyang_halbae' || coachId == 'sec_female') return null;

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

/// 햇살 코치 가꾸기 문장 한 줄.
///
/// 뜻이 담긴 [body]는 그대로 두고, 앞에 붙는 도입구와 뒤에 붙는 효과 문장의
/// 어미만 매번 새로 조합한다. 같은 내용이라도 입에서 나오는 모양이 달라져서
/// 복붙 티가 덜 난다.
///
/// [effect]는 효과 문장에서 어미를 뗀 어간이다(예: '기분이 조금 나아지').
/// null이면 효과 문장 없이 [body]만 쓴다 — 효과를 굳이 덧붙일 자리가 아닌
/// 문장들(새벽처럼 재우는 쪽으로 안내하는 문장)이 여기 해당한다.
class _GroomingLine {
  const _GroomingLine(this.body, {this.effect});

  final String body;
  final String? effect;
}

/// 어떤 문장을 몇 번 거절했는지와, 마지막으로 거절한 시각.
/// 한 번은 그날 컨디션일 수 있어서 횟수를 같이 센다.
class _GroomingDislike {
  _GroomingDislike({required this.count, required this.lastAt});

  int count;
  DateTime lastAt;

  Map<String, dynamic> toJson() => {
    'count': count,
    'at': lastAt.millisecondsSinceEpoch,
  };

  static _GroomingDislike? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final count = raw['count'];
    final at = raw['at'];
    if (count is! int || at is! int) return null;
    return _GroomingDislike(
      count: count,
      lastAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
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
  final Future<bool> Function(
    String name, {
    String freq,
    List<int> days,
    int? weeklyTargetCount,
    int? countGoal,
    String? unit,
    TimeOfDay? time,
    TimeOfDay? endTime,
    String? habitDuration,
  })?
  onRegisterHabit;
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
  final bool shouldNavigate;

  const _FeatureLocationReply(
    this.message,
    this.location, {
    this.shouldNavigate = true,
  });
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
    // 탭 복귀는 새 진입이다. 인사와 겹치지 않으므로 억제를 푼다.
    _state?._greetedOnThisEntry = false;
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
  // "지난 대화 보기": 최근 7일치 보관함이 있으면 상단에 연한 링크를 띄우고,
  // 누르면 과거 메시지를 오늘 대화 위에 펼친다. (로컬 열람 전용)
  bool _hasArchivedChat = false;
  bool _pastLoaded = false;
  List<ChatMessage> _pastMessages = [];
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
  String _broQuickWorkoutChipLabel = '';
  bool _isCheckingVisionRecommendationAllowance = false;
  bool _isCheckingNextActionAllowance = false;

  Color get _accentButtonTextColor =>
      _coach.id == 'nyang_halbae' ? const Color(0xFF173A63) : Colors.white;

  // 냥냥코치 비구독자 무료체험 단계 (0=시작 전, 1=인트로 완료, 2=업셀 완료)
  int _catFreeTrialStep = 0;
  UserData _userData = UserData();

  int _completedTasks = 0;
  int _totalTasks = 0;
  String? _resistanceChipTaskName;
  String? _appointmentPrepChipTaskName;
  String? _appointmentPrepChipTimeLabel;
  String? _repeatedlyDeferredTaskName;
  String? _thoughtOverloadChipTaskName;
  int _attendanceStreak = 0;
  int _catTodayEntryCount = 1;

  // 음성 인식 관련
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  // 이번 진입에서 마스터 코치가 자동 발화를 했는지. 인사 직후에 미뤄둔 할 일
  // 리마인드까지 겹쳐 내면 부담스러워서, 리마인드는 다음 진입으로 미룬다.
  bool _greetedOnThisEntry = false;
  // 저녁 발화에서 사용자가 고른 미완료 일정 (다음 턴 쪼개기 지시에 쓴다).
  // _send가 로컬 답변으로 빠지면 API 턴까지 못 가고 남을 수 있어서, 시각을 같이
  // 들고 있다가 오래된 것은 버린다.
  String? _pendingEveningSplitTask;
  DateTime? _pendingEveningSplitAt;
  static const _eveningSplitTtl = Duration(minutes: 3);

  // 실행 저항 원인 확인: 확인 질문을 던진 직후, 사용자의 원인 답변을 기다리는 상태
  bool _awaitingResistanceCause = false;
  // 반복 거부 뒤 사용자가 직접 고른 가장 작은 행동을 기다리는 상태
  bool _awaitingSelfSelectedTinyAction = false;
  // 무기력/저에너지 상태에서 몸 시동 행동 완료 여부를 기다리는 상태
  bool _awaitingLowEnergyStarterAction = false;
  static const _domainResistanceStrategyHistoryKey =
      'nyang_domain_resistance_strategy_history';
  // 이번 턴에 주입한 원인 확인 질문 (실제로 물었을 때만 하루 1회를 소진 처리)
  String? _pendingDiagnosisQuestion;

  bool get _canOpenSubscriptionGuide => kDebugMode;

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
    _broQuickWorkoutChipLabel = _pickBroQuickWorkoutChipLabel();
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
      final habitFreqById = _habitFrequencyById(prefs);
      final milestones = _todayMilestoneProgressItems(prefs, todayStr);
      final todayTasks = <Map<String, dynamic>>[];

      int total = 0;
      int completed = 0;
      final pendingChipCandidates = <Map<String, dynamic>>[];
      final repeatedlyDeferredCandidates = <Map<String, dynamic>>[];
      final appointmentPrepCandidates = <Map<String, dynamic>>[];

      for (final item in list) {
        if (item is! Map) continue;
        final task = Map<String, dynamic>.from(item);
        todayTasks.add(task);
        final countable = _countsTowardDailyCompletion(task, habitFreqById);
        if (countable) total++;
        if (countable && task['done'] == true) {
          completed++;
        }
        if (task['done'] != true) {
          // 진행 중인 일도 후보엔 넣되, 정렬에서 맨 뒤로 밀린다.
          pendingChipCandidates.add(task);
          if (!_isInProgressTask(task)) {
            if (_appointmentPrepChipTaskNameFor(task) != null) {
              appointmentPrepCandidates.add(task);
            }
            final deferredCount = (task['deferredCount'] as num?)?.toInt() ?? 0;
            if (deferredCount >= 2) {
              repeatedlyDeferredCandidates.add(task);
            }
          }
        }
      }
      for (final milestone in milestones) {
        todayTasks.add(milestone);
        total++;
        if (milestone['done'] == true) {
          completed++;
        } else {
          pendingChipCandidates.add(milestone);
          if (_appointmentPrepChipTaskNameFor(milestone) != null) {
            appointmentPrepCandidates.add(milestone);
          }
        }
      }
      _sortPendingTaskCandidates(pendingChipCandidates);
      String? resistanceChipTaskName;
      for (final task in pendingChipCandidates) {
        final text = _taskText(task);
        if (text != null) {
          resistanceChipTaskName = text;
          break;
        }
      }
      _sortAppointmentPrepChipCandidates(appointmentPrepCandidates);
      Map<String, dynamic>? appointmentPrepTask;
      for (final task in appointmentPrepCandidates) {
        if (_appointmentPrepChipTaskNameFor(task) != null) {
          appointmentPrepTask = task;
          break;
        }
      }
      _sortRepeatedlyDeferredTaskCandidates(repeatedlyDeferredCandidates);
      String? repeatedlyDeferredTaskName;
      for (final task in repeatedlyDeferredCandidates) {
        final text = _taskText(task);
        if (text != null) {
          repeatedlyDeferredTaskName = text;
          break;
        }
      }
      final thoughtOverloadChipTaskName = _thoughtOverloadChipTaskNameFor(
        prefs: prefs,
        todayTasks: todayTasks,
        fallbackCandidates: pendingChipCandidates,
      );

      if (mounted) {
        setState(() {
          _totalTasks = total;
          _completedTasks = completed;
          _resistanceChipTaskName = resistanceChipTaskName;
          _appointmentPrepChipTaskName = _appointmentPrepChipTaskNameFor(
            appointmentPrepTask,
          );
          _appointmentPrepChipTimeLabel = _appointmentPrepChipTimeLabelFor(
            appointmentPrepTask,
          );
          _repeatedlyDeferredTaskName = repeatedlyDeferredTaskName;
          _thoughtOverloadChipTaskName = thoughtOverloadChipTaskName;
        });
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
    }
  }

  Map<String, String> _habitFrequencyById(SharedPreferences prefs) {
    final raw = prefs.getString('nyang_habits');
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const {};
      final result = <String, String>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final id = item['id']?.toString();
        if (id == null) continue;
        result[id] = item['freq']?.toString() ?? 'daily';
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  bool _countsTowardDailyCompletion(
    Map<String, dynamic> task,
    Map<String, String> habitFreqById,
  ) {
    final habitId = task['habitId']?.toString();
    if (habitId == null) return true;
    return habitFreqById[habitId] != 'weekly_count' || task['done'] == true;
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
    if (_coach.id == 'cat') {
      await _recordCatChatEntry(prefs, todayStr);
    }
    final plannerAwayDays = _plannerAwayDays(prefs, todayStr);
    if (prefs.getString('nyang_vacation') == null) {
      await RecoveryInsightService.startMasterLowActivationRestartIfEligible(
        isMasterCoach: _coach.isMaster,
        plannerAwayDays: plannerAwayDays,
      );
    }
    await _updateTodayRecord(prefs);
    await _refreshAttendanceStreak(prefs);
    await _loadHistoryAndGreet();
    await _restoreActiveFocusTimer();
    await _checkBedtimeMoveOffer();
    _initSpeech();
  }

  Future<void> _recordCatChatEntry(
    SharedPreferences prefs,
    String todayStr,
  ) async {
    const dateKey = 'nyang_cat_chat_entry_date';
    const countKey = 'nyang_cat_chat_entry_count';
    final savedDate = prefs.getString(dateKey);
    final nextCount = savedDate == todayStr ? prefs.getInt(countKey) ?? 0 : 0;
    final count = nextCount + 1;
    await prefs.setString(dateKey, todayStr);
    await prefs.setInt(countKey, count);
    if (!mounted) {
      _catTodayEntryCount = count;
      return;
    }
    setState(() => _catTodayEntryCount = count);
  }

  /// 마지막으로 '활동한 날'로부터 며칠 지났는지 계산한다.
  ///
  /// 기기 로컬 방문 기록(nyang_last_planner_visit_date)은 기기마다 따로 저장돼,
  /// 안드로이드에서 매일 써도 아이폰에서는 '오래 부재'로 잡히는 크로스 기기
  /// 오판정을 일으켰다. 대신 모든 기기의 활동이 동기화되는 nyang_history의
  /// 마지막 활동일을 기준으로 삼는다. 오늘은 아직 진행 중이므로 후보에서 제외한다.
  int? _plannerAwayDays(SharedPreferences prefs, String todayStr) {
    final today = DateTime.tryParse(todayStr);
    if (today == null) return null;
    final todayDate = DateTime(today.year, today.month, today.day);

    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory == null) return null;

    DateTime? lastActive;
    try {
      final decoded = jsonDecode(rawHistory);
      if (decoded is! List) return null;
      for (final item in decoded) {
        if (item is! Map) continue;
        final parsed = DateTime.tryParse(item['date']?.toString() ?? '');
        if (parsed == null) continue;
        final day = DateTime(parsed.year, parsed.month, parsed.day);
        // 오늘(진행 중)은 부재일수 기준에서 제외하고, 오늘 이전의 마지막 활동일을 찾는다.
        if (!day.isBefore(todayDate)) continue;
        if (lastActive == null || day.isAfter(lastActive)) {
          lastActive = day;
        }
      }
    } catch (_) {
      return null;
    }

    if (lastActive == null) return null;
    final days = todayDate.difference(lastActive).inDays;
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
      case 'halmae':
        return '우리 새끼 잘한다!!!';
      case 'bro':
        return '일단 가보자고!!!';
      default:
        return '함께 가자';
    }
  }

  void _openCountdownFocusMode() {
    unawaited(AnalyticsService.logFeatureUsage('countdown'));
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const CountdownFocusModeScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
      ),
    );
  }

  void _openSleepAssistMode() {
    unawaited(AnalyticsService.logFeatureUsage('sleep_assist'));
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SleepAssistModeScreen(),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 200),
      ),
    );
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

  bool _containsSleepResistanceSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '자기싫',
      '자기귀찮',
      '잠들기싫',
      '잠들기무서',
      '잠이안와',
      '잠안와',
      '자러가기싫',
      '자러가기귀찮',
      '눕기싫',
      '눕기귀찮',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsDecisionFatigueSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '뭐부터',
      '뭘먼저',
      '뭘해야',
      '뭐해야',
      '무엇부터',
      '못고르',
      '못정하',
      '정하지못',
      '결정못',
      '결정하기힘',
      '결정하기어려',
      '선택못',
      '선택지가많',
      '선택이너무많',
      '어떻게해야할지모르',
      '어떡해야할지모르',
      '모르겠어뭘',
      '고민돼',
      '고민이많',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsThoughtOverloadSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '생각이너무많',
      '생각이많',
      '생각이계속',
      '생각이늘어',
      '생각이꼬리',
      '생각이복잡',
      '머리가복잡',
      '머릿속이복잡',
      '머리복잡',
      '정리가안',
      '판단과부하',
      '판단이안',
      '판단못',
      '고민이너무많',
      '완벽하게하려',
      '완벽하게해야',
      '완벽주의',
      '결과불안',
      '결과가걱정',
      '결과가불안',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsResultAnxietySignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '실패할까봐',
      '망할까봐',
      '망할까봐무서',
      '결과보는게무서',
      '결과가무서',
      '결과확인',
      '결과보기무서',
      '결과를보기무서',
      '결과를확인하기무서',
      '잘안될까봐',
      '안될까봐',
      '헛수고',
      '물거품',
      '아무것도아닌',
      '아무것도아닌일',
      '아무것도아니게',
      '의미없어질까',
      '소용없어질까',
      '노력이사라질까',
      '노력이날아갈까',
      '노력이무너질까',
      '노력이헛',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsWritingConcernSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const writingSignals = [
      '글쓰기',
      '글쓰는거',
      '글쓰는것',
      '글쓰는게',
      '글쓰기가',
      '글을쓰',
      '글이안',
      '글못',
      '집필',
      '원고',
      '웹소설',
      '소설',
      '도입부',
      '첫문장',
      '첫장면',
      '본문',
      '플롯',
      '시놉',
      '자료조사',
      '퇴고',
      '글자수',
      '글진도',
      '글진도가',
      '글진도안',
      '글진도막',
      '글쓰는거진도',
      '글쓰는것진도',
      '글쓰기진도',
      '원고진도',
      '집필진도',
      '연재진도',
      '연재',
      '원고마감',
      '연재마감',
      '문단',
      '대사',
      '초고',
    ];
    const concernSignals = [
      '못쓰',
      '안써',
      '안쓰',
      '막히',
      '막혔',
      '마음에안',
      '고치기만',
      '수정만',
      '기력이없',
      '기운이없',
      '시작하기',
      '시작이',
      '부담',
      '무서',
      '불안',
      '잘쓰고',
      '잘써야',
      '귀찮',
      '하기싫',
      '망할',
      '자책',
      '못채',
      '도망',
      '그만두',
    ];
    return writingSignals.any(normalized.contains) &&
        concernSignals.any(normalized.contains);
  }

  bool _containsCreativeWritingTaskSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '소설',
      '웹소설',
      '시나리오',
      '대본',
      '원고',
      '글쓰기',
      '글쓰',
      '집필',
      '장면',
      '플롯',
      '시놉',
      '퇴고',
      '연재',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsCleaningTaskSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '청소',
      '정리',
      '치우',
      '방청소',
      '책상정리',
      '집정리',
      '옷정리',
      '설거지',
      '빨래',
    ];
    return signals.any(normalized.contains);
  }

  Future<String> _pickDomainResistanceStrategyRule({
    required bool isCreativeWritingTask,
    required bool isCleaningTask,
    required String userText,
  }) async {
    final domain = isCreativeWritingTask
        ? 'writing'
        : isCleaningTask
        ? 'cleaning'
        : 'general';
    final strategies = domain == 'writing'
        ? const [
            (
              id: 'reframe',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 과제 이미지 재정의]
- 창작/글쓰기가 큰 에너지를 써야 하는 일처럼 느껴질 수도 있다고 1문장만 짚기.
- 잘하고 싶은 마음은 유지. 가볍게 하나 만들고 덧대는 쪽이 더 빠른 길일 수도 있다고 재정의.
- 재정의 뒤 작은 행동 1개만 제안.''',
            ),
            (
              id: 'first_contact',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 첫 접촉]
- 글을 쓰게 하기보다 문서 열기, 커서 보기, 장면 제목 보기처럼 첫 접촉 1개만 제안.
- 잘 쓰기/분량/완성도 언급 금지. 접촉 뒤 더 할지는 나중에 정하게 하기.''',
            ),
            (
              id: 'rough_draft',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 러프 쓰기]
- 완성본을 요구하지 말고 10분 동안 고치지 않는 러프 쓰기나 대사 두 줄처럼 낮은 품질 초안 1개만 제안.
- 중간 퀄리티와 완성 퀄리티는 다르다는 점을 짧게 안심시키기.''',
            ),
          ]
        : const [
            (
              id: 'reframe',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 과제 이미지 재정의]
- 청소/정리가 집 전체를 완벽히 치우는 일이 아니라 필요한 부분부터 조금씩 정돈하는 일이라고 1문장만 낮추기.
- 깨끗하게 하고 싶은 마음은 유지. 재정의 뒤 작은 행동 1개만 제안.''',
            ),
            (
              id: 'first_contact',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 첫 접촉]
- 바로 치우게 하지 말고 거슬리는 물건 하나 보기, 컵 하나 보기처럼 첫 접촉 1개만 제안.
- 더러운 곳 전체를 훑게 하지 말기.''',
            ),
            (
              id: 'one_item',
              rule: '''
[이번 턴 도메인 실행 저항 전략: 물건 하나]
- 전체 정리 금지. 물건 하나 줍기/옮기기/버리기 중 현재 가장 쉬운 행동 1개만 제안.
- 여러 구역을 동시에 벌리지 않기.''',
            ),
          ];
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _getTodayStrWithReset(prefs);
    final history = _decodeDomainResistanceStrategyHistory(
      prefs.getString(_domainResistanceStrategyHistoryKey),
    );
    final lowPriorityIds = _lowPriorityDomainResistanceStrategyIds(
      prefs: prefs,
      history: history,
      domain: domain,
      todayStr: todayStr,
    );

    final weighted = [
      for (final strategy in strategies)
        ...List.filled(lowPriorityIds.contains(strategy.id) ? 1 : 3, strategy),
    ];
    final selected = weighted[Random().nextInt(weighted.length)];

    history.add({
      'date': todayStr,
      'domain': domain,
      'strategyId': selected.id,
      'userText': userText.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    final trimmed = history.length > 40
        ? history.sublist(history.length - 40)
        : history;
    await prefs.setString(
      _domainResistanceStrategyHistoryKey,
      jsonEncode(trimmed),
    );
    return selected.rule;
  }

  List<Map<String, dynamic>> _decodeDomainResistanceStrategyHistory(
    String? raw,
  ) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) {
            final date = item['date']?.toString() ?? '';
            final domain = item['domain']?.toString() ?? '';
            final strategyId = item['strategyId']?.toString() ?? '';
            return date.isNotEmpty &&
                domain.isNotEmpty &&
                strategyId.isNotEmpty;
          })
          .toList();
    } catch (_) {
      return [];
    }
  }

  Set<String> _lowPriorityDomainResistanceStrategyIds({
    required SharedPreferences prefs,
    required List<Map<String, dynamic>> history,
    required String domain,
    required String todayStr,
  }) {
    final isLowPriorityByStrategy = <String, bool>{};
    for (final item in history) {
      final date = item['date']?.toString() ?? '';
      if (date.isEmpty || date.compareTo(todayStr) >= 0) continue;
      if (item['domain']?.toString() != domain) continue;
      final strategyId = item['strategyId']?.toString() ?? '';
      if (strategyId.isEmpty) continue;
      isLowPriorityByStrategy[strategyId] = !_domainTaskCompletedOnDate(
        prefs,
        date: date,
        domain: domain,
      );
    }
    return isLowPriorityByStrategy.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toSet();
  }

  bool _domainTaskCompletedOnDate(
    SharedPreferences prefs, {
    required String date,
    required String domain,
  }) {
    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory == null) return false;
    try {
      final records = (jsonDecode(rawHistory) as List).whereType<Map>();
      final record = records.cast<Map?>().firstWhere(
        (item) => item?['date']?.toString() == date,
        orElse: () => null,
      );
      final tasks = (record?['tasks'] as List?) ?? const [];
      return tasks.whereType<Map>().any((task) {
        if (task['done'] != true) return false;
        final text = task['text']?.toString() ?? '';
        return domain == 'writing'
            ? _containsCreativeWritingTaskSignal(text)
            : _containsCleaningTaskSignal(text);
      });
    } catch (_) {
      return false;
    }
  }

  bool _containsHabitAutomationSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '습관',
      '루틴',
      '꾸준',
      '매일',
      '재능',
      '실력키우',
      '연습',
      '자동화',
      '작심',
      '첫4일',
      '처음4일',
      '4일동안',
      '하루4번',
      '여러번나눠',
      '나눠서',
      '짧게여러번',
      '이미지트레이닝',
      '상상훈련',
    ];
    return signals.any(normalized.contains);
  }

  bool _containsLowEnergyStarterSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const signals = [
      '무기력',
      '기력이없',
      '기운이없',
      '에너지가없',
      '에너지없',
      '힘이없',
      '몸에힘이없',
      '축처',
      '방전',
      '완전방전',
      '몸이안움직',
      '일어날힘',
      '누워만있',
      '아무것도못하',
    ];
    return signals.any(normalized.contains);
  }

  bool _hasRepeatedRecentActionRefusal(String currentText) {
    if (!ExecutionResistanceService.isResistanceExpression(currentText)) {
      return false;
    }

    final recentMessages = _messages.length > 10
        ? _messages.sublist(_messages.length - 10)
        : _messages;
    final recentUserResistanceCount = recentMessages
        .where(
          (message) =>
              message.isUser &&
              ExecutionResistanceService.isResistanceExpression(message.text),
        )
        .length;
    if (recentUserResistanceCount < 2) return false;

    final recentAssistantText = recentMessages
        .where((message) => !message.isUser)
        .map((message) => message.text.replaceAll(RegExp(r'\s+'), ''))
        .join(' ');
    const actionSuggestionSignals = [
      '하나만',
      '해보',
      '하자',
      '시작',
      '5분',
      '오분',
      '옮겨',
      '바라봐',
      '잡아',
      '열어',
      '물틀',
      '일어나',
      '움직',
    ];
    return actionSuggestionSignals.any(recentAssistantText.contains);
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
    'halmae',
    'bro',
    'nyang_halbae',
    'sec_female',
  }.contains(widget.coachId);

  String _restOfferMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '요 며칠 진짜 열심히 한 거 내가 다 봤어.\n계속 달리면 나도 걱정돼.',
      'halmae' => '우리 새끼 요 며칠 애쓴 거 할미가 다 봤다.\n계속 그러다 몸 상할까 걱정이다.',
      'bro' => '야, 요 며칠 빡세게 달린 거 내가 다 봤다.\n계속 밀어붙이면 퍼진다.',
      'nyang_halbae' => '요 며칠 꾸준히 걸어온 게 보이는구나냥.\n계속 무리하면 몸이 먼저 신호를 보낼 수도 있다냥.',
      'sec_female' => '대표님, 요 며칠 꾸준히 달려오신 것 제가 확인했어요.\n계속 무리하시면 컨디션이 걱정됩니다.',
      _ => '요 며칠 열심히 한 거 냥이가 다 봤다냥.\n계속 달리면 냥이도 걱정된다냥.',
    };
  }

  String _vacationActivatedMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '오늘은 휴식 모드로 하자. 오늘은 할 일 체크 안 할 테니까 아무 걱정하지 말고 푹 쉬어.',
      'halmae' => '오늘은 휴식 모드로 하자, 우리 새끼. 오늘은 할 일 체크 안 할 테니 아무 걱정 말고 푹 쉬어라.',
      'bro' => '오늘은 휴식 모드다. 할 일 체크 안 들어가니까 걱정 말고 제대로 쉬어.',
      'nyang_halbae' => '오늘은 휴식 모드로 두자냥. 할 일 체크에서는 빠지니, 마음 내려놓고 쉬어도 된다냥.',
      'sec_female' => '오늘은 휴식 모드로 할게요, 대표님. 오늘은 할 일 체크에서 제외되니까 아무 걱정 말고 푹 쉬세요.',
      _ => '오늘은 휴식 모드로 하자냥. 오늘은 할 일 체크 안 할 테니까 아무 걱정하지 말고 푹 쉬어도 된다냥.',
    };
  }

  String _lightDayMessage() {
    return switch (widget.coachId) {
      'boyfriend' => '알겠어. 오늘은 욕심내지 말고 할 수 있는 만큼만 같이 가자.',
      'halmae' => '그래, 우리 새끼. 오늘은 욕심내지 말고 할 수 있는 만큼만 하자.',
      'bro' => '오케이. 오늘은 욕심내지 말고 딱 할 수 있는 만큼만 가자.',
      'nyang_halbae' => '좋다냥. 오늘은 범위를 줄이고, 할 수 있는 만큼만 가보자냥.',
      'sec_female' => '알겠습니다, 대표님. 오늘은 범위를 줄이고 할 수 있는 만큼만 진행해요.',
      _ => '알겠다냥. 오늘은 욕심내지 말고 할 수 있는 만큼만 같이 가자냥.',
    };
  }

  String _vacationCancelledMessage() {
    return switch (widget.coachId) {
      'boyfriend' =>
        '알겠어. 휴식 모드는 취소했어. 다시 해보고 싶은 마음이 들었으면 처음부터 다 하려고 하지 말고 천천히 돌아가자.',
      'halmae' => '알았다, 우리 새끼. 휴식 모드는 취소했으니 처음부터 무리하지 말고 천천히 돌아가자.',
      'bro' => '오케이, 휴식 모드 취소했다. 처음부터 풀파워로 가지 말고 천천히 복귀하자.',
      'nyang_halbae' => '휴식 모드는 풀어두었다냥. 처음부터 다 짊어지지 말고 천천히 돌아오자냥.',
      'sec_female' => '휴식 모드를 해제했어요, 대표님. 처음부터 다 하려고 하지 말고 천천히 돌아가요.',
      _ => '알겠다냥. 휴식 모드는 취소했다냥. 다시 해보고 싶은 마음이 들었으면 처음부터 다 하려고 하지 말고 천천히 돌아가자냥.',
    };
  }

  bool _containsSelfHarmRiskSignal(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return normalized.contains('자살') || normalized.contains('자해');
  }

  bool _isSelfHarmRiskTurn(String userText) {
    if (_containsSelfHarmRiskSignal(userText)) return true;
    final recentAssistantMessages = _messages
        .where((message) => !message.isUser)
        .toList(growable: false)
        .reversed
        .take(3);
    return recentAssistantMessages.any((message) {
      final text = message.text.replaceAll(RegExp(r'\s+'), '');
      return text.contains('스스로를해치거나목숨을끊을생각') ||
          text.contains('구체적인계획이나준비해둔수단') ||
          text.contains('지금119에전화');
    });
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
      _dynamicChips = ['오늘은 쉬어가기', '오늘은 조금만 하기'];
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
          text: userMessage ?? '오늘은 쉬어가기',
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
        ChatMessage(text: '오늘은 조금만 하기', isUser: true, time: DateTime.now()),
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
    return _dynamicChips.contains('오늘은 쉬어가기') &&
        _dynamicChips.contains('오늘은 조금만 하기');
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

  Map<String, dynamic> _recentPlanExecutionStatsUntilYesterday(
    SharedPreferences prefs, {
    int days = 7,
  }) {
    final todayKey = _getTodayStrWithReset(prefs);
    final today = DateTime.tryParse(todayKey) ?? DateTime.now();
    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory == null || rawHistory.isEmpty) {
      return {
        'evaluatedDays': 0,
        'totalCount': 0,
        'doneCount': 0,
        'averageRate': null,
        'isVeryLow': false,
      };
    }

    List<Map<String, dynamic>> history = [];
    try {
      final decoded = jsonDecode(rawHistory) as List;
      history = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return {
        'evaluatedDays': 0,
        'totalCount': 0,
        'doneCount': 0,
        'averageRate': null,
        'isVeryLow': false,
      };
    }

    final byDate = <String, Map<String, dynamic>>{
      for (final record in history)
        if (record['date'] is String) record['date'] as String: record,
    };

    var evaluatedDays = 0;
    var totalCount = 0;
    var doneCount = 0;
    for (var offset = 1; offset <= days; offset++) {
      final record = byDate[_dateKey(today.subtract(Duration(days: offset)))];
      if (record == null || record['isVacation'] == true) continue;
      final total = (record['totalCount'] as num?)?.toInt() ?? 0;
      if (total <= 0) continue;
      evaluatedDays++;
      totalCount += total;
      doneCount += (record['doneCount'] as num?)?.toInt() ?? 0;
    }

    final averageRate = totalCount > 0 ? doneCount / totalCount : null;
    return {
      'evaluatedDays': evaluatedDays,
      'totalCount': totalCount,
      'doneCount': doneCount,
      'averageRate': averageRate,
      'isVeryLow': averageRate != null && averageRate <= 0.3,
    };
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
    const resetHour = 0.0;
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
    const resetHour = 0.0;
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
    if (!CoachIdService.isMaster(widget.coachId)) {
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
    final rawMsg = MasterBedtimeOfferCopy.pick(
      coachId: widget.coachId,
      displayTime: displayTime,
    );
    String msg = await UserTitleService.applyForCoach(rawMsg, widget.coachId);

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
        _hasArchivedChat = false;
        _pastLoaded = false;
        _pastMessages = [];
        _dynamicChips.clear();
        _isLoading = false;
        _coach = CoachConfigs.get(widget.coachId);
        _timerConfirmMinutes = null;
        _timerConfirmTaskName = null;
        _timerActiveMinutes = null;
        _timerActiveInsertIndex = null;
        _suggestedTasks = [];
        _flirtVisible = false;
        _catFreeTrialStep = 0;
        _awaitingResistanceCause = false;
        _pendingDiagnosisQuestion = null;
        _pendingEveningSplitTask = null;
        _thoughtOverloadChipTaskName = null;
        _greetedOnThisEntry = false;
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
      // 돌아온 것은 새 진입이다. 인사 직후 억제해뒀던 리마인드를 이제 낼 수 있다.
      _greetedOnThisEntry = false;
      _loadTaskProgress();
      _checkDeferredReminder();
      _checkBedtimeMoveOffer();
    }
  }

  /// 외부에서 AI 메시지를 채팅창에 직접 주입합니다 (핵심 설정 완료 반응 등).
  void _injectAiMessage(
    String text, {
    String? kind,
    List<String> choices = const [],
  }) {
    if (!mounted) return;
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: false,
          time: DateTime.now(),
          kind: kind,
          choices: choices,
        ),
      );
    });
    _saveHistory();
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  // ── 미뤄둔 할일 리마인드 확인 (탭 복귀 시 호출) ──────────
  Future<void> _checkDeferredReminder() async {
    if (!_coach.isMaster) return;
    // 인사한 진입에서는 리마인드를 내지 않는다. prefs를 지우지 않으므로
    // 다음 진입(재진입)에서 그대로 뜬다.
    if (_greetedOnThisEntry) return;
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
      final isMale = _coach.id == 'nyang_halbae';
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
                onPressed: _canOpenSubscriptionGuide
                    ? () {
                        Navigator.pop(ctx);
                        Future.delayed(
                          Duration.zero,
                          _showPlanGuideBottomSheet,
                        );
                      }
                    : null,
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
    if (!_canOpenSubscriptionGuide) return;
    showPlanGuideBottomSheet(
      context,
      onPurchaseCompleted: () async {
        final updated = await UserDataService.load();
        if (mounted) {
          setState(() => _userData = updated);
        }
      },
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
                              '햇살 코치',
                              '해내면 때론 애인처럼, 때론 친구처럼 마음껏 칭찬해주고',
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
                              'nyang_halbae',
                              '냥할배',
                              '그 부분은 저희 마스터 코치들도 함께 돕고 있습니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '비서 실장',
                              '프렌즈 코치들이 마음을 챙긴다면,\n저희는 실행을 더 체계적으로 보좌합니다.',
                            ),
                            _buildAboutSpeaker(
                              'nyang_halbae',
                              '냥할배',
                              '자꾸 미루는 일정을 다시 챙겨드리고,\n언제 하면 좋을지 제안도 드립니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '비서 실장',
                              '목표와 일정을 바탕으로\n오늘 가장 중요한 일을 정리해드리고,\n주간 리포트도 준비해드립니다.',
                            ),
                            _buildAboutSpeaker(
                              'nyang_halbae',
                              '냥할배',
                              '최근에는 여러분의 컨디션도 함께 챙기고 있습니다.',
                            ),
                            _buildAboutSpeaker(
                              'sec_female',
                              '비서 실장',
                              '잠이 부족하거나 지쳐 있을 때는\n부담스럽지 않은 작은 챌린지도 제안해드리고요.',
                            ),
                            _buildAboutSpeaker(
                              'nyang_halbae',
                              '냥할배',
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
      if (coachId == 'halmae') return Icons.volunteer_activism_outlined;
      if (coachId == 'nyang_halbae' || coachId == 'sec_female')
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

  // ── 마스터 코치 (비서/냥할배) 자동 발화 ────────────────
  // 하루 몇 번 말했는지를 prefs에 적지 않는다. nyang_ 키는 클라우드 복원이
  // 통째로 덮어써서 "오늘 인사했음" 플래그가 어제로 되돌아가고, 그러면 하루
  // 1회 가드가 뚫린다. 대신 발화할 때 메시지에 kind를 심고, 오늘 같은 kind가
  // 있는지로 판정한다 — kind는 채팅 기록에 그대로 저장된다.
  String _greetingKind(GreetingSlot slot) => 'auto:${slot.name}';

  GreetingVoice get _greetingVoice => MasterGreetingCopy.forCoach(_coach.id);

  /// 반복 회피에 쓸 최근 발화. prefs가 아니라 채팅 기록에서 본다.
  MasterGreetingBuilder get _greetingBuilder => MasterGreetingBuilder(
    voice: _greetingVoice,
    recentLines: _messages.reversed
        .where((m) => !m.isUser)
        .take(12)
        .map((m) => m.text)
        .toList(growable: false),
  );

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _alreadySpokeInSlot(GreetingSlot slot, DateTime now) {
    final kind = _greetingKind(slot);
    return _messages.any(
      (m) => !m.isUser && m.kind == kind && _isSameDay(m.time, now),
    );
  }

  List<Map<String, dynamic>> _decodeMapList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((e) {
        return e.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    } catch (_) {
      return [];
    }
  }

  String? _taskText(Map<String, dynamic>? task) {
    final text = task?['text']?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  bool _isInProgressTask(Map<String, dynamic> task) {
    return task['inProgress'] == true;
  }

  bool _isPendingNotInProgressTask(Map<String, dynamic>? task) {
    return task != null && task['done'] != true && !_isInProgressTask(task);
  }

  bool _isHabitTask(Map<String, dynamic> task) {
    return task['isHabit'] == true || task['category'] == 'habit';
  }

  bool _hasCountGoal(Map<String, dynamic> task) {
    final rawCountGoal = task['countGoal'];
    if (rawCountGoal is num) return rawCountGoal > 0;
    final parsedCountGoal = int.tryParse(rawCountGoal?.toString() ?? '');
    return parsedCountGoal != null && parsedCountGoal > 0;
  }

  String? _thoughtOverloadChipTaskNameFor({
    required SharedPreferences prefs,
    required List<Map<String, dynamic>> todayTasks,
    required List<Map<String, dynamic>> fallbackCandidates,
  }) {
    final coreTasks = _decodeMapList(prefs.getString('nyang_core_tasks'));
    for (final coreTask in coreTasks) {
      final matched = _matchingTodayTask(todayTasks, coreTask) ?? coreTask;
      if (_isPendingNotInProgressTask(matched)) {
        final text = _taskText(matched);
        if (text != null) return text;
      }
    }

    for (final task in todayTasks) {
      if (_isHabitTask(task) &&
          _hasCountGoal(task) &&
          _isPendingNotInProgressTask(task)) {
        final text = _taskText(task);
        if (text != null) return text;
      }
    }

    for (final task in todayTasks) {
      if (_isHabitTask(task) && _isPendingNotInProgressTask(task)) {
        final text = _taskText(task);
        if (text != null) return text;
      }
    }

    for (final task in fallbackCandidates) {
      if (_isPendingNotInProgressTask(task)) {
        final text = _taskText(task);
        if (text != null) return text;
      }
    }

    return null;
  }

  String? _appointmentPrepChipTaskNameFor(Map<String, dynamic>? task) {
    if (task == null || task['done'] == true || _isInProgressTask(task)) {
      return null;
    }
    final text = _taskText(task);
    if (text == null) return null;
    if (!text.contains('약속') && !text.contains('모임')) return null;
    if (_appointmentPrepChipTimeLabelFor(task) == null) return null;
    return text;
  }

  String? _appointmentPrepChipTimeLabelFor(Map<String, dynamic>? task) {
    if (task == null) return null;
    final rawTime =
        task['timeStart']?.toString() ?? task['time']?.toString() ?? '';
    return _formatAppointmentPrepChipTime(rawTime);
  }

  String? _formatAppointmentPrepChipTime(String rawTime) {
    final minutes = _taskTimeInMinutes(rawTime);
    if (minutes < 0) return null;

    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    final period = hour < 12 ? '오전' : '오후';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    if (minute == 0) return '$period $displayHour시';
    return '$period $displayHour시 $minute분';
  }

  /// 정렬용 시각을 분 단위로 바꾼다. 못 읽으면 -1.
  /// timeStart는 "9:5"처럼 0 패딩 없는 24시간제, time은 "오전 9:05"처럼 표시용
  /// 문자열이라 그대로 비교하면 10시가 9시보다 앞서 버린다.
  int _taskTimeInMinutes(String value) {
    final head = value.split('~').first.trim();
    final isMorning = head.startsWith('오전');
    final isAfternoon = head.startsWith('오후');

    var clock = head.replaceAll('오전', '').replaceAll('오후', '').trim();
    final koreanTimeMatch = RegExp(
      r'^(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분?)?$',
    ).firstMatch(clock);
    if (koreanTimeMatch != null) {
      final hour = int.tryParse(koreanTimeMatch.group(1) ?? '');
      final minute = int.tryParse(koreanTimeMatch.group(2) ?? '0') ?? 0;
      return _normalizeTaskTimeInMinutes(
        hour: hour,
        minute: minute,
        isMorning: isMorning,
        isAfternoon: isAfternoon,
      );
    }

    clock = clock.split(RegExp(r'\s+')).first.trim();
    final parts = clock.split(':');
    if (parts.length != 2) return -1;
    final hour = int.tryParse(parts[0].trim());
    final minute = int.tryParse(parts[1].trim());
    return _normalizeTaskTimeInMinutes(
      hour: hour,
      minute: minute,
      isMorning: isMorning,
      isAfternoon: isAfternoon,
    );
  }

  int _normalizeTaskTimeInMinutes({
    required int? hour,
    required int? minute,
    required bool isMorning,
    required bool isAfternoon,
  }) {
    if (hour == null || minute == null) return -1;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return -1;

    var normalizedHour = hour;
    if (isAfternoon && hour < 12) normalizedHour += 12;
    if (isMorning && hour == 12) normalizedHour = 0;
    return normalizedHour * 60 + minute;
  }

  /// 채팅칩에 올릴 미완료 일정의 우선순위.
  /// 소요 시간이 정해진 일정(0)을 먼저 권하고, 시간 표시가 없는 일정(1)이 다음,
  /// 특정 시각이 잡힌 일정(2)은 그 시각에 하기로 한 것이니 맨 뒤로 보낸다.
  int _pendingTaskChipRank(Map<String, dynamic> task) {
    final time =
        task['timeStart']?.toString() ?? task['time']?.toString() ?? '';
    if (time.isNotEmpty) return 2;
    final duration = task['duration']?.toString() ?? '';
    return duration.isEmpty ? 1 : 0;
  }

  void _sortPendingTaskCandidates(List<Map<String, dynamic>> tasks) {
    tasks.sort((a, b) {
      // 이미 하고 있는 일한테 "시작하자"고 할 수는 없으니 맨 뒤로 보낸다.
      final aInProgress = _isInProgressTask(a) ? 1 : 0;
      final bInProgress = _isInProgressTask(b) ? 1 : 0;
      if (aInProgress != bInProgress) return aInProgress.compareTo(bInProgress);

      final aRank = _pendingTaskChipRank(a);
      final bRank = _pendingTaskChipRank(b);
      if (aRank != bRank) return aRank.compareTo(bRank);

      final aTime = a['timeStart']?.toString() ?? a['time']?.toString() ?? '';
      final bTime = b['timeStart']?.toString() ?? b['time']?.toString() ?? '';
      if (aTime.isNotEmpty && bTime.isNotEmpty) {
        final aMinutes = _taskTimeInMinutes(aTime);
        final bMinutes = _taskTimeInMinutes(bTime);
        if (aMinutes >= 0 && bMinutes >= 0 && aMinutes != bMinutes) {
          return aMinutes.compareTo(bMinutes);
        }
      }

      final aText = _taskText(a) ?? '';
      final bText = _taskText(b) ?? '';
      return aText.length.compareTo(bText.length);
    });
  }

  void _sortRepeatedlyDeferredTaskCandidates(List<Map<String, dynamic>> tasks) {
    tasks.sort((a, b) {
      final aInProgress = a['inProgress'] == true ? 0 : 1;
      final bInProgress = b['inProgress'] == true ? 0 : 1;
      if (aInProgress != bInProgress) return aInProgress.compareTo(bInProgress);

      final aDeferredCount = (a['deferredCount'] as num?)?.toInt() ?? 0;
      final bDeferredCount = (b['deferredCount'] as num?)?.toInt() ?? 0;
      if (aDeferredCount != bDeferredCount) {
        return bDeferredCount.compareTo(aDeferredCount);
      }

      final aTime = a['timeStart']?.toString() ?? a['time']?.toString() ?? '';
      final bTime = b['timeStart']?.toString() ?? b['time']?.toString() ?? '';
      if (aTime.isNotEmpty && bTime.isNotEmpty) return aTime.compareTo(bTime);
      if (aTime.isNotEmpty) return -1;
      if (bTime.isNotEmpty) return 1;

      final aText = _taskText(a) ?? '';
      final bText = _taskText(b) ?? '';
      return aText.length.compareTo(bText.length);
    });
  }

  void _sortAppointmentPrepChipCandidates(List<Map<String, dynamic>> tasks) {
    tasks.sort((a, b) {
      final aTime = _taskTimeInMinutes(
        a['timeStart']?.toString() ?? a['time']?.toString() ?? '',
      );
      final bTime = _taskTimeInMinutes(
        b['timeStart']?.toString() ?? b['time']?.toString() ?? '',
      );
      if (aTime >= 0 && bTime >= 0 && aTime != bTime) {
        return aTime.compareTo(bTime);
      }

      final aText = _taskText(a) ?? '';
      final bText = _taskText(b) ?? '';
      return aText.length.compareTo(bText.length);
    });
  }

  /// 완료 시각이 최근인 순. 시각이 없는 항목은 목록 순서를 지키도록 뒤로 보낸다.
  List<Map<String, dynamic>> _sortByRecentCompletion(
    List<Map<String, dynamic>> tasks,
  ) {
    final sorted = [...tasks];
    sorted.sort((a, b) {
      final ta = DateTime.tryParse(a['completedAt']?.toString() ?? '');
      final tb = DateTime.tryParse(b['completedAt']?.toString() ?? '');
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return sorted;
  }

  Future<MasterGreetingContext> _buildMasterGreetingContext({
    required SharedPreferences prefs,
    required DateTime now,
    required DateTime? lastVisit,
  }) async {
    final tasks = _decodeMapList(prefs.getString('nyang_tasks'));
    bool isPlan(Map<String, dynamic> task) {
      final category = task['category']?.toString();
      return category == 'today' || category == 'schedule';
    }

    bool isHabit(Map<String, dynamic> task) =>
        task['category']?.toString() == 'habit';

    // "계획 없음" 판정에서 습관은 뺀다. 자정 리셋이 습관을 자동으로 채워 넣기
    // 때문에, 습관까지 세면 계획 없음 분기가 영영 걸리지 않는다.
    final plans = tasks.where(isPlan).toList(growable: false);
    final habits = tasks.where(isHabit).toList(growable: false);
    final donePlans = plans
        .where((task) => task['done'] == true)
        .toList(growable: false);
    final doneHabits = habits
        .where((task) => task['done'] == true)
        .toList(growable: false);
    final pendingPlans = [
      ...plans.where((task) => task['done'] != true),
      ...habits.where((task) => task['done'] != true),
    ].map(_taskText).whereType<String>().toList(growable: false);

    // 이름은 일정 우선, 습관은 후순위. 제목이 길면 이름을 빼고 격려만 한다.
    final ordered = [
      ..._sortByRecentCompletion(donePlans),
      ..._sortByRecentCompletion(doneHabits),
    ];
    final doneCount = ordered.length;
    final headName = ordered.isEmpty ? null : _taskText(ordered.first);
    String? doneLabel;
    if (headName != null &&
        headName.length <= MasterGreetingCopy.doneLabelMaxLength) {
      doneLabel = doneCount > 1
          ? "'$headName' 외 ${doneCount - 1}개"
          : "'$headName'";
    }

    final daysSinceLastVisit = lastVisit == null
        ? null
        : DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(lastVisit.year, lastVisit.month, lastVisit.day),
              )
              .inDays;

    // 어젯밤 흔적은 아카이브까지 봐야 한다 — 하루 지나면 기록이 넘어간다.
    // 5시부터는 늦게 잔 쪽이 아니라 일찍 일어난 쪽으로 본다(새벽 인사와 같은 경계).
    final yesterday = now.subtract(const Duration(days: 1));
    final seen = [
      ..._messages,
      ..._decodeRecentArchive(prefs.getString(_chatArchiveKey)),
    ].where((m) => _isSameDay(m.time, now) || _isSameDay(m.time, yesterday));
    final lateNight = seen.any((m) => m.time.hour >= 2 && m.time.hour < 5);
    const sickWords = [
      '아프',
      '아팠',
      '몸살',
      '감기',
      '열이',
      '열나',
      '두통',
      '배탈',
      '어지럽',
      '몸이 안 좋',
      '컨디션이 안 좋',
    ];
    // 다 나았다거나 안 아프다는 말은 아픔 신호로 보지 않는다.
    const notSickWords = [
      '안 아프',
      '안아프',
      '아프지 않',
      '나았',
      '나아서',
      '낫고',
      '괜찮아졌',
      '괜찮아 졌',
      '다 나음',
    ];
    final feltSick = seen.any(
      (m) =>
          m.isUser &&
          sickWords.any((w) => m.text.contains(w)) &&
          !notSickWords.any((w) => m.text.contains(w)),
    );

    // 오늘 하기 싫다고 말했던 일정 중 끝내 완료한 게 있는지. 저항 신호는
    // 'explicit'(사용자가 직접 그렇게 말한 것)만 본다 — 추론으로 잡은 신호까지
    // 세면 하지도 않은 말을 했다고 코치가 우기게 된다.
    final today = DateFormat('yyyy-MM-dd').format(now);
    final resistanceEvents = (await TaskResistanceService.getAllEvents())
        .where(
          (e) =>
              e.date == today &&
              e.signalType == 'explicit' &&
              e.taskText.trim().isNotEmpty,
        )
        .toList(growable: false);
    final resistedDone = resistanceEvents
        .where((e) => e.completedEventually)
        .toList(growable: false);
    final resistedName = resistedDone.isEmpty
        ? null
        : resistedDone.first.taskText.trim();
    String? resistedInProgressName;
    String? resistedNotStartedName;
    if (resistedName == null) {
      for (final event in resistanceEvents) {
        if (event.completedEventually) continue;
        final task = tasks.cast<Map<String, dynamic>?>().firstWhere(
          (task) => task?['id']?.toString() == event.taskId,
          orElse: () => null,
        );
        if (task == null || task['done'] == true) continue;
        final taskName = _taskText(task) ?? event.taskText.trim();
        if (taskName.isEmpty) continue;
        if (task['inProgress'] == true) {
          resistedInProgressName = taskName;
        } else {
          resistedNotStartedName = taskName;
        }
        break;
      }
    }

    // 하기 싫다고 했는데 그게 계획에 없는 일이면 완료도 미완료도 남지 않아서,
    // 했는지 안 했는지 알 방법이 기록에는 없다. 그때만 코치가 직접 묻는다.
    // 판정은 오늘 대화에서 파생시킨다 — 기기별 플래그를 prefs에 두면 클라우드
    // 복원이 덮어써서 물었는지 여부가 되돌아간다.
    final taskNames = tasks
        .map(_taskText)
        .whereType<String>()
        .map((t) => t.replaceAll(RegExp(r'\s+'), ''))
        .where((t) => t.length >= 2)
        .toList(growable: false);
    final offPlanResistance = seen.any((m) {
      if (!m.isUser || !_isSameDay(m.time, now)) return false;
      if (!ExecutionResistanceService.isResistanceExpression(m.text)) {
        return false;
      }
      final normalized = m.text.replaceAll(RegExp(r'\s+'), '');
      // 계획에 있는 일을 두고 한 말이면 저항 이벤트로 이미 남는다. 여기는 아니다.
      return !taskNames.any(normalized.contains);
    });

    return MasterGreetingContext(
      now: now,
      daysSinceLastVisit: daysSinceLastVisit,
      planTotal: plans.length,
      planDone: donePlans.length,
      doneCount: doneCount,
      doneLabel: doneLabel,
      pendingPlans: pendingPlans,
      lateNight: lateNight,
      feltSick: feltSick,
      resistedDone: resistedName != null,
      resistedDoneLabel:
          resistedName != null &&
              resistedName.length <= MasterGreetingCopy.doneLabelMaxLength
          ? "'$resistedName'"
          : null,
      resistedInProgress: resistedInProgressName != null,
      resistedInProgressLabel:
          resistedInProgressName != null &&
              resistedInProgressName.length <=
                  MasterGreetingCopy.doneLabelMaxLength
          ? "'$resistedInProgressName'"
          : null,
      resistedNotStarted: resistedNotStartedName != null,
      resistedNotStartedLabel:
          resistedNotStartedName != null &&
              resistedNotStartedName.length <=
                  MasterGreetingCopy.doneLabelMaxLength
          ? "'$resistedNotStartedName'"
          : null,
      offPlanResistance: offPlanResistance,
    );
  }

  /// 발화했으면 true. 같은 진입에서 미뤄둔 할 일 리마인드를 겹쳐 내지 않으려고 쓴다.
  Future<bool> _startMasterGreeting({
    required SharedPreferences prefs,
    required DateTime now,
    required DateTime? lastVisit,
  }) async {
    final context = await _buildMasterGreetingContext(
      prefs: prefs,
      now: now,
      lastVisit: lastVisit,
    );
    if (_alreadySpokeInSlot(context.slot, now)) return false;

    final greeting = _greetingBuilder.build(context);
    final text = greeting.text.trim();
    if (text.isEmpty) return false;
    if (!mounted) return false;

    _injectAiMessage(
      text,
      kind: _greetingKind(context.slot),
      choices: greeting.choices,
    );
    // 슬롯별로 실제 몇 번 말했는지, 저녁 카드가 얼마나 뜨는지 나중에 볼 수 있게 남긴다.
    unawaited(
      AnalyticsService.logFeatureUsage(
        greeting.choices.isEmpty
            ? 'master_greeting_${context.slot.name}'
            : 'master_evening_card',
      ),
    );
    return true;
  }

  // ── 히스토리 & 복귀 인사 (웹앱 startGreeting 이식) ──────
  String get _chatArchiveKey =>
      '${DailyResetService.chatArchivePrefix}${widget.coachId}';

  List<ChatMessage> _decodeRecentArchive(String? raw) {
    if (raw == null) return [];
    final cutoff = DateTime.now().subtract(
      const Duration(days: DailyResetService.chatArchiveDays),
    );
    try {
      return (jsonDecode(raw) as List)
          .map((e) => ChatMessage.fromJson(e))
          .where((m) => m.time.isAfter(cutoff))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _checkArchivedChat() async {
    final prefs = await SharedPreferences.getInstance();
    final has = _decodeRecentArchive(
      prefs.getString(_chatArchiveKey),
    ).isNotEmpty;
    if (mounted && has != _hasArchivedChat) {
      setState(() => _hasArchivedChat = has);
    }
  }

  Future<void> _loadPastMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final past = _decodeRecentArchive(prefs.getString(_chatArchiveKey));
    if (!mounted) return;
    setState(() {
      _pastMessages = past;
      _pastLoaded = true;
    });
  }

  static const _catEveningReturnGreetingDateKey =
      'nyang_cat_evening_return_greeting_date';
  static const _catNoonStartTipDateKey = 'nyang_cat_noon_start_tip_date';
  static const _catAfternoonCheckInDateKey =
      'nyang_cat_afternoon_check_in_date';
  static const _catEveningReturnGreetingCooldown = Duration(days: 7);
  static const _catNoonStartTipCooldown = Duration(days: 14);

  Future<bool> _tryShowCatEveningReturnGreeting(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    if (widget.coachId != 'cat') return false;
    if (!_userData.isPlanActive) return false;
    if (_catTodayEntryCount != 1) return false;
    if (now.hour < 18) return false;
    if (widget.handoffFromCoachId == 'nyang_halbae' ||
        widget.handoffFromCoachId == 'sec_female') {
      return false;
    }

    final lastShown = DateTime.tryParse(
      prefs.getString(_catEveningReturnGreetingDateKey) ?? '',
    );
    if (lastShown != null &&
        now.difference(lastShown) < _catEveningReturnGreetingCooldown) {
      return false;
    }

    await prefs.setString(_catEveningReturnGreetingDateKey, _dateKey(now));
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(
          text:
              '이제 왔냥? 냥냥이 기다리고 있었다냥.\n'
              '냥냥코치는 계획만 적어두는 플래너가 아니다냥.\n'
              '할 일을 시작할 때랑 마쳤을 때도 알려줘.\n'
              '중간중간 하나씩 해낸 걸 확인하고 냥냥이한테 칭찬받으면, 남은 일도 조금 더 힘내서 이어갈 수 있다냥.',
          isUser: false,
          time: DateTime.now(),
          kind: 'auto_greeting',
        ),
      );
      _dynamicChips = _coach.chips;
      _suppressDefaultChips = false;
    });
    await _saveHistory();
    _scrollToBottom();
    return true;
  }

  Future<bool> _tryShowCatComebackGreeting(
    DateTime? lastVisit,
    DateTime now,
  ) async {
    if (widget.coachId != 'cat') return false;
    if (lastVisit == null) return false;

    final lastVisitDay = DateTime(
      lastVisit.year,
      lastVisit.month,
      lastVisit.day,
    );
    final today = DateTime(now.year, now.month, now.day);
    if (today.difference(lastVisitDay).inDays < 3) return false;

    const greets = [
      '냥! 왤케 오랜만이다냥! 보고 싶었다냥!',
      '오랜만이다냥. 냥냥이 기다리고 있었다냥.',
      '냥~ 그동안 어디 갔었냥. 다시 와줘서 좋다냥.',
    ];
    final greet = greets[Random().nextInt(greets.length)];
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(
          text: greet,
          isUser: false,
          time: DateTime.now(),
          kind: 'auto_greeting',
        ),
      );
      _dynamicChips = _coach.chips;
      _suppressDefaultChips = false;
    });
    await _saveHistory();
    _scrollToBottom();
    return true;
  }

  Future<bool> _tryShowCatNoonStartTip(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    if (widget.coachId != 'cat') return false;
    if (!_userData.isPlanActive || _userData.planType != 'master') {
      return false;
    }
    if (now.hour < 13 || now.hour >= 15) return false;
    if (widget.handoffFromCoachId == 'nyang_halbae' ||
        widget.handoffFromCoachId == 'sec_female') {
      return false;
    }

    final lastShown = DateTime.tryParse(
      prefs.getString(_catNoonStartTipDateKey) ?? '',
    );
    if (lastShown != null &&
        now.difference(lastShown) < _catNoonStartTipCooldown) {
      return false;
    }

    final todayKey = _dateKey(now);
    final text = await _buildCatNoonStartTipText(prefs);
    await prefs.setString(_catNoonStartTipDateKey, todayKey);
    await prefs.setString(_catAfternoonCheckInDateKey, todayKey);
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: false,
          time: DateTime.now(),
          kind: 'auto_greeting',
        ),
      );
      _dynamicChips = const ['오늘 뭐부터 할까', '하기 싫은 일 있어', '오늘 꼭 끝낼 일 있어'];
      _suppressDefaultChips = false;
    });
    await _saveHistory();
    _scrollToBottom();
    return true;
  }

  Future<bool> _tryShowCatAfternoonCheckIn(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    if (widget.coachId != 'cat') return false;
    if (!_userData.isPlanActive) return false;
    if (now.hour < 15 || now.hour >= 18) return false;
    if (widget.handoffFromCoachId == 'nyang_halbae' ||
        widget.handoffFromCoachId == 'sec_female') {
      return false;
    }

    final todayKey = _dateKey(now);
    if (prefs.getString(_catAfternoonCheckInDateKey) == todayKey) {
      return false;
    }

    final text = await _buildCatAfternoonCheckInText(prefs);
    await prefs.setString(_catAfternoonCheckInDateKey, todayKey);
    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return true;
    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isUser: false,
          time: DateTime.now(),
          kind: 'auto_greeting',
        ),
      );
      _dynamicChips = const ['하기 싫은 일 있어', '오늘 꼭 끝낼 일 있어', '남은 것 중 뭐하지?'];
      _suppressDefaultChips = false;
    });
    await _saveHistory();
    _scrollToBottom();
    return true;
  }

  Future<void> _loadHistoryAndGreet() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_chat_history_${widget.coachId}');
    final lastVisitStr = prefs.getString('last_visit_${widget.coachId}');
    final now = DateTime.now();
    final lastVisit = lastVisitStr == null
        ? null
        : DateTime.tryParse(lastVisitStr);
    unawaited(_checkArchivedChat());

    if (raw != null) {
      final List list = jsonDecode(raw);
      if (list.isNotEmpty) {
        setState(() {
          _messages.addAll(list.map((e) => ChatMessage.fromJson(e)));
        });
        _scrollToBottom();
      }
    }

    if (await _tryShowCatComebackGreeting(lastVisit, now)) {
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    }
    if (await _tryShowCatEveningReturnGreeting(prefs, now)) {
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    }
    if (await _tryShowCatNoonStartTip(prefs, now)) {
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    }
    if (await _tryShowCatAfternoonCheckIn(prefs, now)) {
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    }

    // 냥할배/여비서의 정서적 동행 연결로 소환된 경우에만 냥냥이가 먼저 인사한다.
    // 이때 왜 여기로 왔는지(오늘 하루만 생각하기) 이유도 살짝 짚어준다.
    // 일반 진입에서는 기존 프렌즈 코치 정책대로 사용자의 첫 말을 기다린다.
    if (widget.coachId == 'cat' &&
        (widget.handoffFromCoachId == 'nyang_halbae' ||
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
          ChatMessage(
            text: greet,
            isUser: false,
            time: DateTime.now(),
            kind: 'auto_greeting',
          ),
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
            ChatMessage(
              text: intro,
              isUser: false,
              time: DateTime.now(),
              kind: 'auto_greeting',
            ),
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

      // 마스터 코치(비서/냥할배): 슬롯별 자동 발화
      if (_coach.isMaster) {
        _greetedOnThisEntry = await _startMasterGreeting(
          prefs: prefs,
          now: now,
          lastVisit: lastVisit,
        );
        await prefs.setString(
          'last_visit_${widget.coachId}',
          now.toIso8601String(),
        );
        return;
      }

      // 프렌즈 코치: 3일 이상 미접속 시 로컬 인사말 출력, 그 외엔 유저 메시지 대기
      if (lastVisitStr != null) {
        final lastVisit = DateTime.parse(lastVisitStr);
        final daysDiff = now.difference(lastVisit).inDays;
        if (daysDiff >= 3) {
          final cid = _coach.id;
          final List<String> greets;
          if (cid == 'boyfriend') {
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
          _injectAiMessage(greet, kind: 'auto_greeting');
        }
      }
      await prefs.setString(
        'last_visit_${widget.coachId}',
        now.toIso8601String(),
      );
      return;
    } else {
      if (_coach.isMaster) {
        _greetedOnThisEntry = await _startMasterGreeting(
          prefs: prefs,
          now: now,
          lastVisit: lastVisit,
        );
        await prefs.setString(
          'last_visit_${widget.coachId}',
          now.toIso8601String(),
        );
        return;
      }

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
    final countdownStartRegex = RegExp(r'\[COUNTDOWN_START\]');
    final ultraLowResistanceFollowupRegex = RegExp(
      r'\[ULTRA_LOW_RESISTANCE_FOLLOWUP:\s*([^\]]+)\]',
    );
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
    String? ultraLowResistanceFollowup;
    bool startCountdown = false;
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

    if (countdownStartRegex.hasMatch(text)) {
      startCountdown = true;
      text = text.replaceAll(countdownStartRegex, '').trim();
    }

    final ultraLowResistanceFollowupMatch = ultraLowResistanceFollowupRegex
        .firstMatch(text);
    if (ultraLowResistanceFollowupMatch != null) {
      ultraLowResistanceFollowup = ultraLowResistanceFollowupMatch
          .group(1)
          ?.trim();
      text = text
          .replaceAll(ultraLowResistanceFollowupMatch.group(0)!, '')
          .trim();
      suppressDefaultChips = true;
      chips = [];
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
      startCountdown = false;
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
      ultraLowResistanceFollowup: ultraLowResistanceFollowup,
      startCountdown: startCountdown,
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
    const resetHour = 0.0;
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

  /// 사용자가 이번 발화에서 직접 타이머를 요청했는지 판정.
  /// (마스터 코치의 타이머는 명시 요청 또는 제안 동의로만 제공된다.)
  bool _isExplicitTimerRequest(String userText) {
    final normalized = userText.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (!normalized.contains('타이머')) return false;
    return ['띄워', '켜', '줘', '틀어', '시작', '설정', '맞춰'].any(normalized.contains);
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

  Future<String?> _tryBuildMasterLocalReply(String input) async {
    if (!_coach.isMaster) return null;
    if (_timerConfirmMinutes != null) return null;

    final raw = input.trim();
    if (raw.isEmpty) return null;
    final normalized = raw.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final isQuestion = raw.contains('?') || raw.contains('？');

    String? reply;
    if (['안녕', '안녕하세요', '하이', 'ㅎㅇ', '왔어', '나왔어', '들어왔어'].contains(normalized) ||
        (normalized.length <= 8 && normalized.contains('안녕'))) {
      reply = _coach.id == 'nyang_halbae'
          ? '왔구나냥. 지금은 길게 벌리지 말고, 오늘 흐름만 차분히 보면 된다냥.'
          : '오셨네요. 지금은 크게 벌리지 말고, 오늘 흐름부터 차분히 확인해볼게요.';
    } else if ([
      '고마워',
      '고맙다',
      '고맙',
      '감사',
      '감사해',
      '땡큐',
      'thanks',
      'thankyou',
    ].contains(normalized)) {
      reply = _coach.id == 'nyang_halbae'
          ? '괜찮다냥. 필요한 순간에 다시 부르면 된다냥.'
          : '천만에요. 필요하실 때 다시 바로 도와드릴게요.';
    } else if ([
      '잘자',
      '자러갈게',
      '잘게',
      '나갈게',
      '이따올게',
      '다녀올게',
    ].contains(normalized)) {
      reply = _coach.id == 'nyang_halbae'
          ? '그래냥. 오늘은 여기서 잘 접어두고, 몸부터 쉬게 해주라냥.'
          : '좋아요. 오늘은 여기서 잘 접어두고, 몸부터 쉬게 해주세요.';
    } else if (_isSimpleMasterStatusRequest(normalized, isQuestion)) {
      reply = await _buildLocalMasterStatusReply();
    }

    if (reply == null) return null;
    return UserTitleService.applyForCoach(reply, _coach.id);
  }

  Future<String?> _tryBuildCatLocalReply(String input) async {
    if (_coach.id != 'cat') return null;
    if (_timerConfirmMinutes != null) return null;

    final raw = input.trim();
    if (raw == '오늘 어디까지 왔지?') {
      return _buildLocalMasterStatusReply();
    }
    return null;
  }

  bool _isSimpleMasterStatusRequest(String normalized, bool isQuestion) {
    final asksStatus =
        normalized.contains('오늘상태') ||
        normalized.contains('오늘할일확인') ||
        normalized.contains('진행상황') ||
        normalized.contains('얼마나했') ||
        normalized.contains('몇개했') ||
        normalized.contains('몇개남') ||
        normalized.contains('남은거') ||
        normalized.contains('남은일') ||
        normalized.contains('할일상태');
    final asksAnalysis =
        normalized.contains('분석') ||
        normalized.contains('평가') ||
        normalized.contains('추천') ||
        normalized.contains('뭐부터') ||
        normalized.contains('뭐하지') ||
        normalized.contains('계획') ||
        normalized.contains('짜줘');
    return asksStatus &&
        !asksAnalysis &&
        (isQuestion || normalized.length <= 12);
  }

  bool _isTodayTaskOverviewRequest(String input) {
    final compact = input.trim().toLowerCase().replaceAll(
      RegExp(r'[\s.。!！?？~〜]+'),
      '',
    );
    if (compact.isEmpty) return false;
    if (_isDeletionCommand(input) ||
        _isEditCommand(input) ||
        _isScheduleRegistrationCommand(input) ||
        _isHabitRegistrationCommand(input)) {
      return false;
    }
    return [
          '오늘할일확인해줘',
          '오늘할일확인',
          '오늘할일뭐야',
          '오늘할일알려줘',
          '오늘할일',
          '할일확인해줘',
          '할일확인',
        ].contains(compact) ||
        (compact.contains('오늘') &&
            compact.contains('할일') &&
            RegExp(r'(확인|알려|보여|열어|뭐)').hasMatch(compact));
  }

  String _todayTaskOverviewOpenMessage({
    required bool hasAnyTask,
    required int totalCount,
    required Map<String, dynamic>? coreTask,
    required List<Map<String, dynamic>> habitTasks,
    required List<Map<String, dynamic>> todayTasks,
  }) {
    final coreTaskText = _taskText(coreTask);
    final highlightedKeys = {
      if (coreTask != null) _taskOverviewKey(coreTask),
      ...habitTasks.map(_taskOverviewKey),
    };
    final otherTaskLabels = todayTasks
        .where((task) => !highlightedKeys.contains(_taskOverviewKey(task)))
        .map(_taskOverviewLabel)
        .toList(growable: false);
    return LocalReplyTexts.todayTaskOverview(
      coachId: widget.coachId,
      hasAnyTask: hasAnyTask,
      totalCount: totalCount,
      coreTaskLabel: coreTaskText != null && coreTaskText.trim().isNotEmpty
          ? _taskOverviewLabel(coreTask!)
          : null,
      habitLabels: habitTasks.map(_taskOverviewLabel).toList(growable: false),
      otherTaskLabels: otherTaskLabels,
    );
  }

  String _taskOverviewKey(Map<String, dynamic> task) {
    return (task['id'] ?? _taskText(task) ?? '').toString();
  }

  String _taskOverviewLabel(Map<String, dynamic> task) {
    final text = _taskText(task) ?? '이름 없는 할 일';
    final timeLabel = _taskTimeLabelForPrompt(task);
    return LocalReplyTexts.taskOverviewLabel(
      text: text,
      timeLabel: timeLabel,
      done: task['done'] == true,
    );
  }

  bool _looksLikeTodayTaskTimeQuestion(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (!normalized.contains('오늘')) return false;
    if (_asksTodoResetGuide(normalized) ||
        _asksRepeatScheduleGuide(normalized)) {
      return false;
    }
    return RegExp(r'(몇시|언제|시간|몇시에|몇시부터|몇시쯤)').hasMatch(normalized);
  }

  List<String> _quotedTaskTerms(String input) {
    return RegExp(r"""['"‘’“”]([^'"‘’“”]{2,})['"‘’“”]""")
        .allMatches(input)
        .map((match) => match.group(1)?.trim() ?? '')
        .where((term) => term.isNotEmpty)
        .toList(growable: false);
  }

  String _taskMatchText(String value) {
    return value.toLowerCase().replaceAll(
      RegExp(r"""[\s'"‘’“”"?.。!！,，~〜]+"""),
      '',
    );
  }

  List<String> _taskQueryTokens(String input) {
    const stopWords = {
      '오늘',
      '몇시',
      '몇시에',
      '몇시부터',
      '언제',
      '시간',
      '부터',
      '하기로',
      '읽기로',
      '했지',
      '했냐',
      '했어',
      '읽냐고',
      '하냐고',
      '알려줘',
      '확인해줘',
    };
    return input
        .toLowerCase()
        .replaceAll(RegExp(r"""['"‘’“”?.。!！,，~〜]"""), ' ')
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.length >= 2 && !stopWords.contains(token))
        .toList(growable: false);
  }

  int _todayTaskTimeMatchScore(
    Map<String, dynamic> task,
    String input,
    List<String> quotedTerms,
    List<String> queryTokens,
  ) {
    final text = _taskText(task);
    if (text == null) return 0;
    final taskMatchText = _taskMatchText(text);
    final inputMatchText = _taskMatchText(input);
    var score = 0;

    for (final term in quotedTerms) {
      final termMatchText = _taskMatchText(term);
      if (termMatchText.isEmpty) continue;
      if (taskMatchText.contains(termMatchText)) score += 100;
      if (termMatchText.contains(taskMatchText)) score += 60;
    }

    for (final token in queryTokens) {
      final tokenMatchText = _taskMatchText(token);
      if (tokenMatchText.isEmpty) continue;
      if (taskMatchText.contains(tokenMatchText)) score += 12;
    }

    if (inputMatchText.contains(taskMatchText)) score += 40;
    final category = task['category']?.toString();
    if (score > 0 && category == 'schedule') score += 3;
    return score;
  }

  String _todayTaskTimeReply(Map<String, dynamic> task) {
    final text = _taskText(task) ?? '그 일정';
    final timeLabel = _taskTimeLabelForPrompt(task);
    return LocalReplyTexts.todayTaskTimeReply(
      coachId: widget.coachId,
      text: text,
      timeLabel: timeLabel,
    );
  }

  String _todayTaskTimeNotFoundReply() {
    return LocalReplyTexts.todayTaskTimeNotFoundReply(widget.coachId);
  }

  bool _hasTaskTimeQueryCue(
    List<String> quotedTerms,
    List<String> queryTokens,
  ) {
    return quotedTerms.isNotEmpty || queryTokens.isNotEmpty;
  }

  Future<bool> _tryAnswerTodayTaskTimeQuestion(String input) async {
    if (!_looksLikeTodayTaskTimeQuestion(input)) return false;

    final prefs = await SharedPreferences.getInstance();
    final quotedTerms = _quotedTaskTerms(input);
    final queryTokens = _taskQueryTokens(input);
    if (!_hasTaskTimeQueryCue(quotedTerms, queryTokens)) return false;

    final tasks = _decodeMapList(prefs.getString('nyang_tasks'));
    final todayTasks = tasks
        .where((task) {
          final category = task['category']?.toString();
          return category == 'today' ||
              category == 'habit' ||
              category == 'schedule';
        })
        .toList(growable: false);
    if (todayTasks.isEmpty) {
      await _sendTodayTaskTimeNotFoundReply(input);
      return true;
    }

    final scored =
        todayTasks
            .map(
              (task) => (
                task: task,
                score: _todayTaskTimeMatchScore(
                  task,
                  input,
                  quotedTerms,
                  queryTokens,
                ),
              ),
            )
            .where((item) => item.score > 0)
            .toList()
          ..sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) {
      await _sendTodayTaskTimeNotFoundReply(input);
      return true;
    }

    final reply = await UserTitleService.applyForCoach(
      _todayTaskTimeReply(scored.first.task),
      widget.coachId,
    );
    setState(() {
      _messages.add(
        ChatMessage(text: input, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
      );
      _suggestedTasks = [];
      _dynamicChips = _coach.chips;
      _suppressDefaultChips = false;
      _coachSwitchTarget = null;
    });
    _scrollToBottom();
    await _saveHistory();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    return true;
  }

  Future<void> _sendTodayTaskTimeNotFoundReply(String input) async {
    final reply = await UserTitleService.applyForCoach(
      _todayTaskTimeNotFoundReply(),
      widget.coachId,
    );
    setState(() {
      _messages.add(
        ChatMessage(text: input, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
      );
      _suggestedTasks = [];
      _dynamicChips = [];
      _suppressDefaultChips = false;
      _coachSwitchTarget = null;
    });
    _scrollToBottom();
    await _saveHistory();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    await Future.delayed(const Duration(milliseconds: 260));
    widget.onOpenFeatureLocation?.call('today');
  }

  Future<bool> _tryOpenTodayTaskOverview(String input) async {
    if (!_isTodayTaskOverviewRequest(input)) return false;

    final prefs = await SharedPreferences.getInstance();
    final tasks = _decodeMapList(prefs.getString('nyang_tasks'));
    final todayTasks = tasks
        .where((task) {
          final category = task['category']?.toString();
          return category == 'today' ||
              category == 'habit' ||
              category == 'schedule';
        })
        .toList(growable: false);
    final pending = todayTasks
        .where((task) => task['done'] != true)
        .toList(growable: false);
    final coreTaskRaw = _decodeMapList(prefs.getString('nyang_core_tasks'))
        .cast<Map<String, dynamic>?>()
        .firstWhere((task) => task?['done'] != true, orElse: () => null);
    final coreTask = _matchingTodayTask(todayTasks, coreTaskRaw) ?? coreTaskRaw;
    final habitTasks = pending
        .where((task) {
          final category = task['category']?.toString();
          return category == 'habit' || task['isHabit'] == true;
        })
        .toList(growable: false);

    final reply = await UserTitleService.applyForCoach(
      _todayTaskOverviewOpenMessage(
        hasAnyTask: todayTasks.isNotEmpty,
        totalCount: todayTasks.length,
        coreTask: coreTask,
        habitTasks: habitTasks,
        todayTasks: todayTasks,
      ),
      widget.coachId,
    );
    setState(() {
      _messages.add(
        ChatMessage(text: input, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
      );
      _suggestedTasks = [];
      _dynamicChips = [];
      _suppressDefaultChips = false;
      _coachSwitchTarget = null;
    });
    _scrollToBottom();
    await _saveHistory();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    await Future.delayed(const Duration(milliseconds: 260));
    widget.onOpenFeatureLocation?.call('today');
    return true;
  }

  Map<String, dynamic>? _matchingTodayTask(
    List<Map<String, dynamic>> todayTasks,
    Map<String, dynamic>? source,
  ) {
    if (source == null) return null;
    final sourceId = source['id']?.toString();
    if (sourceId != null && sourceId.isNotEmpty) {
      for (final task in todayTasks) {
        if (task['id']?.toString() == sourceId) return task;
      }
    }

    final sourceText = _taskText(source);
    if (sourceText == null) return null;
    for (final task in todayTasks) {
      if (_taskText(task) == sourceText) return task;
    }
    return null;
  }

  Future<String> _buildLocalMasterStatusReply() async {
    final prefs = await SharedPreferences.getInstance();
    // 상태를 물었을 때의 답이라 여기서는 습관까지 포함해서 센다.
    final todayTasks = _decodeMapList(prefs.getString('nyang_tasks'))
        .where((task) {
          final category = task['category']?.toString();
          return category == 'today' ||
              category == 'habit' ||
              category == 'schedule';
        })
        .toList(growable: false);
    final incomplete = todayTasks
        .where((task) => task['done'] != true)
        .toList(growable: false);
    final total = todayTasks.length;
    final remaining = incomplete.length;
    final done = total - remaining;

    final inProgressSchedule = incomplete
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (task) =>
              task?['category'] == 'schedule' && task?['inProgress'] == true,
          orElse: () => null,
        );
    final inProgress = _taskText(
      inProgressSchedule ??
          incomplete.cast<Map<String, dynamic>?>().firstWhere(
            (task) => task?['inProgress'] == true,
            orElse: () => null,
          ),
    );
    final core = _taskText(
      _decodeMapList(prefs.getString('nyang_core_tasks'))
          .cast<Map<String, dynamic>?>()
          .firstWhere((task) => task?['done'] != true, orElse: () => null),
    );

    if (_coach.id == 'nyang_halbae') {
      if (total == 0) return '오늘 등록된 할 일은 아직 없다냥. 먼저 하나만 가볍게 잡아도 충분하다냥.';
      if (remaining == 0)
        return '오늘 할 일 $total개 중 $done개 완료다냥. 다 끝냈으니 더 벌리지 말고 쉬어도 된다냥.';
      if (inProgress != null) {
        return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았다냥. 지금은 "$inProgress" 마무리만 보면 되겠다냥.';
      }
      if (core != null) {
        return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았다냥. 핵심은 "$core" 쪽을 먼저 보면 된다냥.';
      }
      return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았다냥. 하나만 고르면 흐름은 다시 붙는다냥.';
    }

    if (_coach.id == 'cat') {
      if (total == 0) return '오늘 등록된 할 일은 아직 없다냥. 하나만 가볍게 잡아도 충분하다냥.';
      if (remaining == 0) return '오늘 할 일 $total개 다 끝났다냥. 더 벌리지 말고 이제 쉬어도 된다냥.';
      if (inProgress != null) {
        return '오늘 $done개는 끝냈고, "$inProgress"는 이미 시작해뒀다냥. 남은 건 $remaining개지만 지금은 흐름이 있는 상태다냥.';
      }
      if (core != null) {
        return '오늘 $done개 끝냈고 $remaining개 남았다냥. 아직 시동 걸 일이 필요하면 "$core"부터 보면 좋겠다냥.';
      }
      return '오늘 $done개 끝냈고 $remaining개 남았다냥. 다 보려고 하지 말고 하나만 잡으면 된다냥.';
    }

    if (total == 0) return '오늘 등록된 할 일은 아직 없어요. 먼저 하나만 가볍게 잡아도 충분합니다.';
    if (remaining == 0)
      return '오늘 할 일 $total개 중 $done개 완료예요. 다 끝내셨으니 더 벌리지 말고 쉬셔도 됩니다.';
    if (inProgress != null) {
      return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았어요. 지금은 "$inProgress" 마무리만 보시면 좋겠습니다.';
    }
    if (core != null) {
      return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았어요. 핵심은 "$core" 쪽을 먼저 보시면 됩니다.';
    }
    return '오늘 할 일 $total개 중 $done개 완료, $remaining개 남았어요. 하나만 고르면 흐름은 다시 붙습니다.';
  }

  Future<String> _buildCatAfternoonCheckInText(SharedPreferences prefs) async {
    final random = Random();
    String pick(List<String> lines) => lines[random.nextInt(lines.length)];
    final opener = pick([
      '오후 중간까지 왔다냥.',
      '오후가 반쯤 지나왔다냥.',
      '냥냥이 보러 왔구냥.',
      '냥냥이가 오후 상태를 한번 봐줄게.',
    ]);
    final todayTasks = _decodeMapList(prefs.getString('nyang_tasks'))
        .where((task) {
          final category = task['category']?.toString();
          return category == 'today' ||
              category == 'habit' ||
              category == 'schedule';
        })
        .toList(growable: false);
    final incomplete = todayTasks
        .where((task) => task['done'] != true)
        .toList(growable: false);
    final total = todayTasks.length;
    final remaining = incomplete.length;
    final done = total - remaining;

    final inProgressSchedule = incomplete
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (task) =>
              task?['category'] == 'schedule' && task?['inProgress'] == true,
          orElse: () => null,
        );
    final inProgress = _taskText(
      inProgressSchedule ??
          incomplete.cast<Map<String, dynamic>?>().firstWhere(
            (task) => task?['inProgress'] == true,
            orElse: () => null,
          ),
    );
    final core = _taskText(
      _decodeMapList(prefs.getString('nyang_core_tasks'))
          .cast<Map<String, dynamic>?>()
          .firstWhere((task) => task?['done'] != true, orElse: () => null),
    );

    if (total == 0) {
      final question = pick([
        '오늘 꼭 끝내야 하는 일이 있을까?',
        '지금 하나만 적는다면 뭐가 제일 덜 부담스럽냥?',
        '냥냥이랑 오늘 할 일 하나만 같이 잡아볼까?',
      ]);
      return '$opener\n'
          '오늘 등록된 할 일은 아직 없다냥. 지금 하나만 아주 작게 잡아봐도 충분하다냥.\n'
          '$question';
    }
    if (remaining == 0) {
      final praise = pick([
        '이건 그냥 끝난 게 아니라 하루를 이미 잘 굴린 거다냥.',
        '성취감을 밤까지 미뤄둘 필요 없다냥. 지금 봐도 충분히 잘했다냥.',
        '오늘 할 일을 눈으로 다 지운 거라 꽤 든든하다냥.',
      ]);
      final question = pick([
        '혹시 마음에 남은 일이 하나 있을까, 아니면 이제 쉬어도 되냥?',
        '이제 더 벌릴까, 아니면 오늘은 여기서 가볍게 닫을까?',
        '남은 기운은 쉬는 데 써도 괜찮겠냥?',
      ]);
      return '$opener\n'
          '오늘 할 일 $total개를 다 끝냈다냥. $praise\n'
          '$question';
    }
    if (inProgress != null) {
      if (done == 0) {
        final question = pick([
          '혹시 이 일에서 유독 귀찮거나 막히는 부분 있었냥?',
          '이걸 이어가려면 제일 작은 다음 행동이 뭐가 좋겠냥?',
          '지금은 이 일을 조금 더 볼까, 아니면 다른 걸 먼저 가볍게 볼까?',
        ]);
        return '$opener\n'
            '아직 완료로 찍힌 일은 없어도, "$inProgress"는 이미 시작해뒀다냥. 시작해둔 것도 흐름이다냥.\n'
            '$question';
      }
      final reassurance = pick([
        '남은 건 $remaining개지만 흐름은 살아 있다냥.',
        '다 끝난 건 아니어도 이미 하루가 움직이고 있다냥.',
        '지금은 시작해둔 게 있어서 다시 붙기 좋은 상태다냥.',
      ]);
      final question = pick([
        '혹시 지금 유독 귀찮거나 힘든 일 있었냥?',
        '이 흐름에서 다음으로 아주 작게 볼 건 뭐냥?',
        '지금 "$inProgress"를 마저 볼까, 아니면 남은 것 중 하나를 같이 고를까?',
      ]);
      return '$opener\n'
          '오늘 $done개는 끝냈고, "$inProgress"는 이미 시작해뒀다냥. $reassurance\n'
          '$question';
    }
    if (done == 0) {
      final nudge = core != null ? '"$core"부터 봐도 좋고, ' : '';
      final question = pick([
        '오늘 꼭 끝내야 하는 일이 있을까?',
        '하기 유독 귀찮은 일이 하나 있냥?',
        '지금 하나만 잡는다면 뭐부터 보는 게 좋겠냥?',
      ]);
      return '$opener\n'
          '아직 완료로 찍힌 일은 없어도 괜찮다냥. $nudge지금 하나만 아주 작게 잡아보면 된다냥.\n'
          '$question';
    }
    if (core != null) {
      final reassurance = pick([
        '이미 해낸 게 있으니까 남은 것도 다 한꺼번에 볼 필요 없다냥.',
        '지금까지 해낸 걸 먼저 봐도 된다냥.',
        '하루가 0에서 멈춘 게 아니라 이미 움직였다냥.',
      ]);
      final question = pick([
        '지금은 "$core"가 제일 걸리는 일일까?',
        '"$core"를 아주 작게 쪼개보면 이어가기 괜찮을까?',
        '혹시 "$core"가 오늘 꼭 끝내야 하는 일이냥?',
      ]);
      return '$opener\n'
          '오늘 $done개 끝냈고 $remaining개 남았다냥. $reassurance\n'
          '$question';
    }
    final reassurance = pick([
      '지금까지 해낸 걸 먼저 봐도 된다냥.',
      '남은 게 보여도 오늘 해낸 것도 같이 봐야 한다냥.',
      '아직 오후니까 하나만 다시 잡아도 충분하다냥.',
    ]);
    final question = pick([
      '남은 것 중 유독 귀찮거나 힘든 일 있었냥?',
      '오늘 꼭 끝내야 하는 일이 하나 있을까?',
      '남은 것 중 하나만 같이 골라볼까?',
    ]);
    return '$opener\n'
        '오늘 $done개 끝냈고 $remaining개 남았다냥. $reassurance\n'
        '$question';
  }

  Future<String> _buildCatNoonStartTipText(SharedPreferences prefs) async {
    final todayTasks = _decodeMapList(prefs.getString('nyang_tasks'))
        .where((task) {
          final category = task['category']?.toString();
          return category == 'today' ||
              category == 'habit' ||
              category == 'schedule';
        })
        .toList(growable: false);
    final incomplete = todayTasks
        .where((task) => task['done'] != true)
        .toList(growable: false);
    final total = todayTasks.length;
    final remaining = incomplete.length;
    final done = total - remaining;

    final inProgressSchedule = incomplete
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (task) =>
              task?['category'] == 'schedule' && task?['inProgress'] == true,
          orElse: () => null,
        );
    final inProgress = _taskText(
      inProgressSchedule ??
          incomplete.cast<Map<String, dynamic>?>().firstWhere(
            (task) => task?['inProgress'] == true,
            orElse: () => null,
          ),
    );
    final core = _taskText(
      _decodeMapList(prefs.getString('nyang_core_tasks'))
          .cast<Map<String, dynamic>?>()
          .firstWhere((task) => task?['done'] != true, orElse: () => null),
    );

    final status = () {
      if (total == 0) {
        return '오늘 등록된 할 일은 아직 없다냥. 그래도 하나만 적어두면 냥냥이가 흐름을 같이 봐줄 수 있다냥.';
      }
      if (remaining == 0) {
        return '오늘 할 일 $total개를 다 끝냈다냥. 이미 하루를 꽤 잘 굴리고 있다냥.';
      }
      if (inProgress != null) {
        if (done == 0) {
          return '아직 완료로 찍힌 일은 없어도, "$inProgress"는 이미 시작해뒀다냥. 시작해둔 것도 흐름이다냥.';
        }
        return '오늘 $done개 끝냈고, "$inProgress"는 진행 중이다냥. 이미 해낸 것도 있고 이어가는 것도 있다냥.';
      }
      if (done == 0) {
        final nudge = core != null ? '"$core"부터 봐도 좋고, ' : '';
        return '아직 완료로 찍힌 건 없어도 괜찮다냥. $nudge시작만 눌러둬도 오늘 흐름이 남는다냥.';
      }
      if (core != null) {
        return '오늘 $done개 끝냈고 $remaining개 남았다냥. "$core"만 너무 크게 보지 말고 작게 시작해도 된다냥.';
      }
      return '오늘 $done개 끝냈고 $remaining개 남았다냥. 지금까지 해낸 것도 같이 봐야 한다냥.';
    }();

    return '오! 왔구나.\n'
        '$status\n'
        '맞다! 오늘 탭에서 할 일을 시작할 때 ▶ 시작을 누르면, 습관 트래킹할 때 그 시간까지 감안해서 패턴도 분석해주니까 참고하면 좋을 것 같다냥.';
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

  String _getDateStrWithResetOffset(SharedPreferences _, int daysAgo) {
    const resetHour = 0.0;
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
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라)|넣어\s*(?:줘요?|주세요)|만들\s*(?:고\s*싶어|고\s*싶어요|거야|거예요|게|래|어\s*줘요?|어\s*주세요))$',
    );
    return suffixRegex.hasMatch(cleaned);
  }

  _ParsedHabitRegistration _parseHabitRegistration(String input) {
    var cleaned = _cleanScheduleRegistrationInput(input);
    final suffixRegex = RegExp(
      r'\s*(등록해\s*(?:줘요?|주세요|달라)|추가해\s*(?:줘요?|주세요|달라)|넣어\s*(?:줘요?|주세요)|만들\s*(?:고\s*싶어|고\s*싶어요|거야|거예요|게|래|어\s*줘요?|어\s*주세요))$',
    );
    cleaned = cleaned.replaceFirst(suffixRegex, '').trim();
    cleaned = cleaned.replaceAll(RegExp(r'습관\s*(?:탭|텝)\s*에'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s*습관\s*(?:으로|에)?\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^습관\s*(?:으로|에)?\s*'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^(?:나|나는|내가|저|저는)\s+'), '');
    cleaned = cleaned.replaceAll(RegExp(r'^(?:앞으로|이제)\s+'), '');

    var parsedFreq = 'daily';
    var parsedDays = <int>[];
    int? parsedWeeklyTargetCount;
    int? parsedCountGoal;
    String? parsedUnit;
    const weekdayByText = {
      '월': 0,
      '화': 1,
      '수': 2,
      '목': 3,
      '금': 4,
      '토': 5,
      '일': 6,
    };
    final weeklyRegex = RegExp(
      r'(?:매주|매 주)\s*((?:[월화수목금토일](?:요일)?(?:\s*(?:,|/|·|과|와|랑|하고|및)?\s*)?)+)',
    );
    final weeklyMatch = weeklyRegex.firstMatch(cleaned);
    if (weeklyMatch != null) {
      final days = <int>[];
      for (final match in RegExp(
        r'[월화수목금토일](?:요일)?',
      ).allMatches(weeklyMatch.group(1)!)) {
        final day = weekdayByText[match.group(0)![0]];
        if (day != null && !days.contains(day)) days.add(day);
      }
      if (days.isNotEmpty) {
        parsedFreq = 'weekly';
        parsedDays = days;
        cleaned = cleaned.replaceFirst(weeklyMatch.group(0)!, '').trim();
      }
    }

    if (parsedFreq == 'daily') {
      final weeklyCountRegex = RegExp(
        r'(?:^|\s)(?:주|일주일에)\s*([1-7])\s*(?:일|회|번)(?:\s*(?:씩|정도)?)?',
      );
      final weeklyCountMatch = weeklyCountRegex.firstMatch(cleaned);
      if (weeklyCountMatch != null) {
        parsedFreq = 'weekly_count';
        parsedWeeklyTargetCount = int.tryParse(weeklyCountMatch.group(1)!);
        cleaned = cleaned.replaceFirst(weeklyCountMatch.group(0)!, ' ').trim();
      }
    }

    if (parsedFreq == 'daily') {
      final bareWeeklyRegex = RegExp(
        r'^\s*((?:[월화수목금토일](?:요일)?\s*(?:,|/|·|과|와|랑|하고|및)\s*)+[월화수목금토일](?:요일)?)\s*',
      );
      final bareWeeklyMatch = bareWeeklyRegex.firstMatch(cleaned);
      if (bareWeeklyMatch != null) {
        final days = <int>[];
        for (final match in RegExp(
          r'[월화수목금토일](?:요일)?',
        ).allMatches(bareWeeklyMatch.group(1)!)) {
          final day = weekdayByText[match.group(0)![0]];
          if (day != null && !days.contains(day)) days.add(day);
        }
        if (days.length >= 2) {
          parsedFreq = 'weekly';
          parsedDays = days;
          cleaned = cleaned.replaceFirst(bareWeeklyMatch.group(0)!, '').trim();
        }
      }
    }

    cleaned = cleaned.replaceAll(
      RegExp(r'(?:^|\s)(?:매일|매일마다|날마다)(?:\s|$)'),
      ' ',
    );

    final countRegex = RegExp(
      r'(?:^|\s)(\d[\d,]*)\s*(자|글자|쪽|페이지|회|번)(?:\s*(?:정도|씩)?)?',
    );
    final countMatch = countRegex.firstMatch(cleaned);
    if (countMatch != null) {
      parsedCountGoal = int.tryParse(countMatch.group(1)!.replaceAll(',', ''));
      parsedUnit = countMatch.group(2);
      if (parsedUnit == '글자') parsedUnit = '자';
      cleaned = cleaned.replaceFirst(countMatch.group(0)!, ' ').trim();
    }

    TimeOfDay? parsedTime;
    TimeOfDay? parsedEndTime;
    String? parsedHabitDuration;

    TimeOfDay? parseHabitTime(
      String? rawPrefix,
      String rawHourText,
      String? rawMinuteText,
      String fullMatch, {
      String fallbackPrefix = '',
    }) {
      final prefix = (rawPrefix ?? fallbackPrefix).replaceAll(
        RegExp(r'\s'),
        '',
      );
      final rawHour = int.tryParse(rawHourText) ?? 0;
      var minute = 0;
      if (rawMinuteText != null) {
        minute = int.tryParse(rawMinuteText) ?? 0;
      } else if (fullMatch.contains('반')) {
        minute = 30;
      }

      if (rawHour < 1 || rawHour > 24 || minute < 0 || minute > 59) {
        return null;
      }
      var hour24 = rawHour;
      if (prefix == '오전' || prefix == '아침') {
        hour24 = rawHour == 12 ? 0 : rawHour;
      } else if (prefix == '오후' || prefix == '저녁' || prefix == '밤') {
        hour24 = rawHour == 12 ? 12 : rawHour + 12;
      }
      if (hour24 < 0 || hour24 > 23) return null;
      return TimeOfDay(hour: hour24, minute: minute);
    }

    final timeRangeRegex = RegExp(
      r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?\s*(?:부터|에서|-|~)\s*((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?(?:\s*까지)?',
    );
    final rangeMatch = timeRangeRegex.firstMatch(cleaned);
    if (rangeMatch != null) {
      final startPrefix = rangeMatch.group(1) ?? '';
      final start = parseHabitTime(
        startPrefix,
        rangeMatch.group(2)!,
        rangeMatch.group(3),
        rangeMatch.group(0)!,
      );
      final end = parseHabitTime(
        rangeMatch.group(4),
        rangeMatch.group(5)!,
        rangeMatch.group(6),
        rangeMatch.group(0)!,
        fallbackPrefix: startPrefix,
      );
      if (start != null && end != null) {
        parsedTime = start;
        parsedEndTime = end;
        cleaned = cleaned.replaceFirst(rangeMatch.group(0)!, '').trim();
      }
    }

    if (parsedTime == null) {
      final timeRegex = RegExp(
        r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?(?:\s*(?:에|쯤|경))?',
      );
      final timeMatch = timeRegex.firstMatch(cleaned);
      if (timeMatch != null) {
        final time = parseHabitTime(
          timeMatch.group(1),
          timeMatch.group(2)!,
          timeMatch.group(3),
          timeMatch.group(0)!,
        );
        if (time != null) {
          parsedTime = time;
          cleaned = cleaned.replaceFirst(timeMatch.group(0)!, '').trim();
        }
      }
    }

    if (parsedTime == null) {
      final durationRegex = RegExp(
        r'(?:^|\s)((?:\d+\s*시간(?:\s*\d+\s*분)?|\d+\s*분))(?:\s|$)',
      );
      final durationMatch = durationRegex.firstMatch(cleaned);
      if (durationMatch != null) {
        parsedHabitDuration = durationMatch
            .group(1)!
            .replaceAll(RegExp(r'\s+'), '');
        cleaned = cleaned.replaceFirst(durationMatch.group(0)!, ' ').trim();
      }
    }

    cleaned = cleaned.replaceAll(
      RegExp(r'\s*(?:할\s*건데|할건데|할\s*건대|할\s*거야|할거야|할게|하려고|하려구|할래|할\s*래|하기)$'),
      '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\s*습관\s*(?:좀|조금|하나|으로|로)?\s*$'), '');
    cleaned = cleaned.replaceAll(RegExp(r'\s*(?:좀|조금|하나|부탁해|부탁할게)\s*$'), '');
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(.+?)하는$'),
      (match) => match.group(1)!,
    );
    cleaned = cleaned.replaceAll(RegExp(r'^글\s*쓰는$'), '글쓰기');
    cleaned = _cleanRegistrationTitle(cleaned);
    return _ParsedHabitRegistration(
      title: cleaned,
      freq: parsedFreq,
      days: parsedDays,
      weeklyTargetCount: parsedWeeklyTargetCount,
      countGoal: parsedCountGoal,
      unit: parsedUnit,
      time: parsedTime,
      endTime: parsedEndTime,
      habitDuration: parsedHabitDuration,
    );
  }

  String _habitRegistrationReply(String habitName) {
    return switch (widget.coachId) {
      'boyfriend' => '$habitName, 습관 탭에 추가해뒀어. 세부 설정은 한번 확인해줘.',
      'bro' => '$habitName 습관 탭에 추가해뒀다. 세부 설정은 한번 확인해라.',
      'halmae' => '$habitName, 습관 탭에 추가해뒀다. 세부 설정은 잘 확인해라.',
      'nyang_halbae' => '$habitName 습관 탭에 추가해두었다냥. 세부 설정은 한번 살펴보자냥.',
      'sec_female' => '$habitName 항목을 습관 탭에 추가해두었어요. 세부 설정을 확인해 주세요.',
      _ => '$habitName 습관을 습관 탭에 추가해뒀다냥. 세부 설정은 확인해달라냥.',
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
      'bro' => '뭘 삭제할지 이름까지 같이 말해라.',
      'halmae' => '뭘 지울지 이름까지 말해줘야 한다, 우리 새끼.',
      'nyang_halbae' => '무엇을 삭제할지 이름까지 같이 말해주라냥.',
      'sec_female' => '삭제할 항목명을 함께 말씀해 주세요.',
      _ => '어떤 걸 삭제할지 이름까지 같이 말해달라냥.',
    };
  }

  String _emptyEditTargetReply() {
    return switch (widget.coachId) {
      'boyfriend' => '어떤 일정을 수정할지 이름까지 같이 말해줘.',
      'bro' => '뭘 수정할지 이름까지 같이 말해라.',
      'halmae' => '뭘 고칠지 이름까지 말해줘야 한다, 우리 새끼.',
      'nyang_halbae' => '무엇을 수정할지 이름까지 같이 말해주라냥.',
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
      'bro' => '매주 반복이면 요일이 필요하다. 무슨 요일로 할지 말해라.',
      'halmae' => '매주 반복이면 요일을 정해야 한다. 무슨 요일로 해줄까?',
      'nyang_halbae' => '매주 반복하려면 요일이 필요하다냥. 무슨 요일로 둘까냥?',
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

    final nthWeekdayDate = _parseMonthNthWeekdayDate(cleaned);
    if (nthWeekdayDate != null) {
      parsedDate = nthWeekdayDate.date;
      hasDate = true;
      cleaned = cleaned.replaceFirst(nthWeekdayDate.matchedText, '').trim();
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
      title: cleaned.isEmpty ? '새 캘린더 일정' : cleaned,
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

  int _monthOffsetFromKorean(String value) {
    final compact = value.replaceAll(RegExp(r'\s'), '');
    return switch (compact) {
      '이번달' => 0,
      '다음달' => 1,
      '다다음달' => 2,
      _ => 0,
    };
  }

  int _nthFromKorean(String value) {
    final compact = value.replaceAll(RegExp(r'\s'), '');
    return switch (compact) {
      '첫째' || '첫' || '1째' || '1번째' => 1,
      '둘째' || '두번째' || '2째' || '2번째' => 2,
      '셋째' || '세번째' || '3째' || '3번째' => 3,
      '넷째' || '네번째' || '4째' || '4번째' => 4,
      '다섯째' || '다섯번째' || '5째' || '5번째' => 5,
      '마지막' || '마지막째' => -1,
      _ => 1,
    };
  }

  String _nthLabelFromValue(int nth) {
    return switch (nth) {
      1 => '첫째',
      2 => '둘째',
      3 => '셋째',
      4 => '넷째',
      5 => '다섯째',
      -1 => '마지막',
      _ => '$nth째',
    };
  }

  DateTime _lastWeekdayOfMonth(int year, int month, int weekday) {
    var date = DateTime(year, month + 1, 0);
    while (date.weekday != weekday) {
      date = date.subtract(const Duration(days: 1));
    }
    return date;
  }

  DateTime _monthNthWeekdayDate(int year, int month, int nth, int weekday) {
    if (nth == -1) return _lastWeekdayOfMonth(year, month, weekday);
    return _nthWeekdayOfMonth(year, month, nth, weekday);
  }

  ({DateTime date, String matchedText, String label})?
  _parseMonthNthWeekdayDate(String input) {
    final regex = RegExp(
      r'((?:이번|다음|다다음)\s*달|(?:\d{1,2})\s*월)\s*(첫째|첫|둘째|두번째|셋째|세번째|넷째|네번째|다섯째|다섯번째|마지막|마지막째|1째|1번째|2째|2번째|3째|3번째|4째|4번째|5째|5번째)\s*주\s*([월화수목금토일])(?:요일)?\s*(?:에|날)?',
    );
    final match = regex.firstMatch(input);
    if (match == null) return null;

    final monthText = match.group(1)!;
    final nth = _nthFromKorean(match.group(2)!);
    final weekday = _weekdayFromKorean(match.group(3)!);
    if (weekday == -1) return null;

    final today = DateTime.now();
    late final int year;
    late final int month;
    final compactMonthText = monthText.replaceAll(RegExp(r'\s'), '');
    final absoluteMonthMatch = RegExp(
      r'^(\d{1,2})월$',
    ).firstMatch(compactMonthText);
    if (absoluteMonthMatch != null) {
      month = int.tryParse(absoluteMonthMatch.group(1)!) ?? today.month;
      if (month < 1 || month > 12) return null;
      year = month < today.month ? today.year + 1 : today.year;
    } else {
      final monthOffset = _monthOffsetFromKorean(compactMonthText);
      final monthStart = DateTime(today.year, today.month + monthOffset, 1);
      year = monthStart.year;
      month = monthStart.month;
    }

    final date = _monthNthWeekdayDate(year, month, nth, weekday);
    final labelMonth = absoluteMonthMatch != null
        ? '$month월'
        : _relativeDateQuestionLabel(compactMonthText);
    final label =
        '$labelMonth ${_nthLabelFromValue(nth)} 주 ${_weekdayLabel(weekday)}요일';
    return (date: date, matchedText: match.group(0)!, label: label);
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
    if (_asksTodoResetGuide(normalized) ||
        _asksRepeatScheduleGuide(normalized)) {
      return null;
    }
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
        return _coachFactLine(
          '${relative.label}${_topicParticle(relative.label)} ${_fullKoreanDate(target)}',
        );
      }
    }

    final nthWeekdayDate = _parseMonthNthWeekdayDate(normalized);
    if (nthWeekdayDate != null) {
      return _coachFactLine(
        '${nthWeekdayDate.label}${_topicParticle(nthWeekdayDate.label)} ${_fullKoreanDate(nthWeekdayDate.date)}',
      );
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
      return _coachFactLine(
        '${_relativeDateQuestionLabel(rel)} ${_weekdayLabel(weekday)}요일은 ${_fullKoreanDate(target)}',
      );
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
      return _coachFactLine(
        '${_relativeDateQuestionLabel(rel)} ${_weekdayLabel(weekday)}요일은 $joined',
      );
    }

    return null;
  }

  /// "7월 31일은 무슨 요일이야?" 처럼 특정 날짜의 요일을 묻는 질문을
  /// 로컬에서 바로 계산해 답한다. (API 호출·오답 방지)
  String? _weekdayQuestionReply(String input) {
    final normalized = input.replaceAll(RegExp(r'\s+'), '');
    final asksWeekday = RegExp(
      r'(무슨요일|몇요일|요일이야|요일이지|요일이니|요일이냐|요일일까|요일인가|요일이에요|요일이예요|요일예요|요일인가요|요일이었|요일이더|요일알려|요일뭐|요일좀|요일\?)',
    ).hasMatch(normalized);
    if (!asksWeekday) return null;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? target;
    String? label;

    // 1) 상대 표현 (오늘/내일/모레/어제 등)
    final relatives = <({String label, int offset, RegExp pattern})>[
      (label: '그글피', offset: 4, pattern: RegExp(r'그글피')),
      (label: '글피', offset: 3, pattern: RegExp(r'글피')),
      (label: '모레', offset: 2, pattern: RegExp(r'(?:내일모레|낼모레|모레)')),
      (label: '내일', offset: 1, pattern: RegExp(r'내일')),
      (label: '오늘', offset: 0, pattern: RegExp(r'오늘')),
      (label: '어제', offset: -1, pattern: RegExp(r'어제')),
      (label: '그저께', offset: -2, pattern: RegExp(r'(?:그저께|그제)')),
    ];
    for (final r in relatives) {
      if (r.pattern.hasMatch(normalized)) {
        target = today.add(Duration(days: r.offset));
        label = r.label;
        break;
      }
    }

    // 2) (YYYY년) M월 D일
    if (target == null) {
      final ymd = RegExp(
        r'(?:(\d{4})년)?(\d{1,2})월(\d{1,2})일',
      ).firstMatch(normalized);
      if (ymd != null) {
        final year = int.tryParse(ymd.group(1) ?? '') ?? now.year;
        final month = int.tryParse(ymd.group(2)!) ?? 0;
        final day = int.tryParse(ymd.group(3)!) ?? 0;
        final d = DateTime(year, month, day);
        if (month >= 1 && month <= 12 && d.month == month && d.day == day) {
          target = d;
          label = ymd.group(1) != null
              ? '$year년 $month월 $day일'
              : '$month월 $day일';
        }
      }
    }

    // 3) D일 (이번 달 기준)
    if (target == null) {
      final dOnly = RegExp(r'(\d{1,2})일').firstMatch(normalized);
      if (dOnly != null) {
        final day = int.tryParse(dOnly.group(1)!) ?? 0;
        final d = DateTime(now.year, now.month, day);
        if (day >= 1 && d.month == now.month && d.day == day) {
          target = d;
          label = '$day일';
        }
      }
    }

    // 4) 날짜 표현이 없으면 "오늘"의 요일을 묻는 것으로 본다.
    //    단 "무슨 요일에 할까/등록" 같은 스케줄 문의는 제외한다.
    if (target == null) {
      final core = normalized.replaceAll(RegExp(r'[?!.~]+$'), '');
      final schedulingLike = RegExp(
        r'요일(에|로|마다)|할까|할래|등록|잡아|추가|해줘|해줄|반복',
      ).hasMatch(core);
      if (!schedulingLike) {
        target = today;
        label = '오늘';
      }
    }

    if (target == null || label == null) return null;
    final weekday = _weekdayLabel(target.weekday);
    return _coachFactLine('$label${_topicParticle(label)} $weekday요일');
  }

  /// "7월 31일은 금요일" / "오늘은 2026년 7월 21일" 같은 사실 문장을
  /// 코치 말투로 마무리한다. (요일·날짜 로컬 응답 공용)
  String _coachFactLine(String subject) {
    return switch (widget.coachId) {
      'cat' => '$subject이다냥! 🐾',
      'bro' => '$subject이다. 됐지?',
      'halmae' => '$subject이란다~',
      'boyfriend' => '$subject이야 💙',
      'nyang_halbae' => '$subject입니다.',
      'sec_female' => '$subject이에요! 🌸',
      _ => '$subject입니다.',
    };
  }

  /// 마지막 글자의 받침 유무로 주격 보조사(은/는)를 고른다.
  String _topicParticle(String word) {
    if (word.isEmpty) return '은';
    final code = word.codeUnitAt(word.length - 1);
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final hasBatchim = (code - 0xAC00) % 28 != 0;
      return hasBatchim ? '은' : '는';
    }
    return '은';
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

  String _storedTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

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
    unawaited(
      AppleCalendarSyncService.instance.syncAll(pullExternalChanges: false),
    );
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
                            SvgPicture.asset(
                              'assets/icons/thumbtack.svg',
                              width: 15,
                              height: 15,
                              colorFilter: ColorFilter.mode(
                                _coach.accentColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '캘린더 일정 등록 제안',
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
                              color: _coach.accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: _coach.accentColor.withValues(
                                  alpha: 0.25,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.repeat_rounded,
                                  size: 14,
                                  color: _coach.accentColor,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _repeatRuleLabel(confirmedRepeatRule),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
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
                              color: _coach.accentColor.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/planner-calendar-days.svg',
                                  width: 13,
                                  height: 13,
                                  colorFilter: ColorFilter.mode(
                                    _coach.accentColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _scheduleDateLabel(confirmedDate),
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
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
                              color: _coach.accentColor.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SvgPicture.asset(
                                  'assets/icons/fa-clock-regular.svg',
                                  width: 13,
                                  height: 13,
                                  colorFilter: ColorFilter.mode(
                                    _coach.accentColor,
                                    BlendMode.srcIn,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  confirmedTime != null
                                      ? _formatTimeOfDay(confirmedTime!)
                                      : '시간 설정 안 함',
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: _coach.accentColor,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.edit,
                                  size: 12,
                                  color: _coach.accentColor,
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
                            color: _coach.accentColor,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SvgPicture.asset(
                              reminderEnabled
                                  ? 'assets/icons/bell.svg'
                                  : 'assets/icons/bell-slash.svg',
                              width: 13,
                              height: 13,
                              colorFilter: ColorFilter.mode(
                                _coach.accentColor,
                                BlendMode.srcIn,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              reminderEnabled ? '알람 ON' : '알람 OFF',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _coach.accentColor,
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
                              backgroundColor: _coach.accentColor,
                              foregroundColor: _accentButtonTextColor,
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

  Future<String?> _tryBuildBroWorkoutReply(String input) async {
    if (_coach.id != 'bro') return null;
    final normalized = _workoutNormalized(input);
    final prefs = await SharedPreferences.getInstance();
    final pendingContext = prefs.getString('bro_pending_workout_context');

    if (_containsAny(normalized, ['브릿지가뭐야', '브릿지뭐야', '브릿지어떻게'])) {
      return '브릿지는 누워서 무릎 세우고 엉덩이 들어올리는 운동.\n발은 바닥에 붙이고, 엉덩이를 들어 올렸다가 천천히 내려오면 된다. 엉덩이랑 하체 깨우는 데 좋다.';
    }

    if (_containsAny(normalized, ['브릿지영상', '브릿지링크', '브릿지추천'])) {
      return '브릿지는 8회만 가자.\n누워서 무릎 세우고, 엉덩이를 천천히 들어 올렸다가 내려와. 허리로 버티지 말고 엉덩이에 힘 주는 느낌으로.';
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
        return '그럼 바로 빡센 거 추천하면 안 되겠다.\n오늘은 1단계만 가자. 목이랑 어깨 풀고, 제자리 걷기 1분. 몸이 괜찮으면 그때 쉬운 본운동 하나 붙이면 된다.';
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
        return '오케이. 오래 쉬었으면 바로 스쿼트부터 박지 마라.\n누워서 브릿지 8회만 해보자. 무릎 세우고, 엉덩이 들어올렸다가 천천히 내려오면 된다.\n하체 깨우기엔 이게 진입 장벽 낮다.';
      }
      final starter = Random().nextInt(4);
      if (starter == 0) {
        return '오케이.\n그럼 갑자기 빡세게 하는 것보다 몸부터 깨우는 게 좋겠다.\n벽 앞에 서서 힙힌지 8회만 해봐. 허리 꺾지 말고 엉덩이를 뒤로 빼는 느낌.\n오래 쉬었을 땐 이런 식으로 문턱 낮추는 게 낫다.';
      }
      if (starter == 1) {
        return '오케이. 오래 쉬었으면 오늘은 단계 낮춰서 가자.\n1단계 목 돌리기 5번, 어깨 돌리기 10번, 제자리 걷기 1분.\n2단계 몸 괜찮으면 브릿지 8회만 붙여. 갑자기 빡세게 가지 마라.';
      }
      if (starter == 2) {
        return '오케이. 오래 쉬었으면 오늘은 운동복 입고 10분 산책만 해도 성공이다.\n몸이 깨어나야 다음 것도 된다.\n형도 전문가 아니다. 그냥 운동 좋아해서 이것저것 해본 사람인데, 다시 시작할 땐 이렇게 문턱 낮추는 게 제일 세다.';
      }
      return '오케이. 오래 쉬었으면 오늘 바로 고강도 가지 마라.\n집이면 제자리 걷기 5분, 밖이면 산책 10분, 건물 안이면 계단 한두 층만 가자.\n운동을 가르치려는 게 아니라, 오늘 다시 시작하게 만드는 게 먼저다.';
    }

    if (gym && warmedUp) {
      return _pickLine([
        '좋아. 몸 풀었으면 본운동 간다.\n레그프레스 2세트, 랫풀다운 2세트, 러닝머신 걷기 10분. 세트 사이엔 60초만 쉬어. 복잡하게 가지 말고 이 정도만 제대로 해.',
        '좋다. 이제 루틴 잡고 가자.\n스쿼트나 레그프레스 2세트, 체스트프레스 2세트, 마지막에 가볍게 걷기 10분. 몸 괜찮으면 다음번에 세트 하나 늘리면 된다.',
      ]);
    }

    if (warmedUp) {
      if (_containsAny(normalized, ['층간소음', '조용', '점프없이', '노점프'])) {
        return '집이면 층간소음 신경 써야지. 점프는 빼자.\n스쿼트 10회, 뒤로 다리 뻗기 10회, 플랭크 20초. 1라운드 하고 괜찮으면 2라운드. 단계 올리는 건 그다음이다.';
      }
      if (_containsAny(normalized, ['복근', '뱃살', '배살', '복부'])) {
        return '복근이면 허리부터 지켜라. 배에 힘 제대로 주고 간다.\n데드버그 10회, 플랭크 20초, 크런치 10회. 1라운드 먼저 하고, 허리 괜찮으면 2라운드까지.';
      }
      return _pickLine([
        '좋아. 이제 몸 깨웠지? 그럼 본운동은 작게 간다.\n스쿼트 10회, 푸쉬업은 무릎 대고 8회, 제자리 걷기 1분. 1라운드 먼저 끝내.',
        '좋다. 이제 본운동 들어가자.\n런지 8회씩, 플랭크 20초, 제자리 빠른 걷기 1분. 할 만하면 한 라운드만 더. 무리하면 바로 컷.',
      ]);
    }

    return null;
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
    if (_coach.id == 'nyang_halbae') {
      return '$minutes분 타이머 바로 띄워두겠다냥. 지금은 시작만 하면 된다.';
    }
    if (_coach.id == 'sec_female') {
      return '$minutes분 타이머 바로 띄워드릴게요. 지금은 가볍게 시작해봐요.';
    }
    return '$minutes분 타이머 바로 켜줄게. 일단 시작해보자.';
  }

  bool _isDirectCountdownRequest(String text) {
    if (!_coach.isMaster) return false;
    final normalized = text.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final hasCountdownWord =
        normalized.contains('카운트다운') ||
        normalized.contains('숫자세고') ||
        normalized.contains('숫자세어') ||
        normalized.contains('숫자세면서') ||
        normalized.contains('마음비우고시작') ||
        normalized.contains('시작의식');
    if (!hasCountdownWord) return false;
    return [
      '켜',
      '띄워',
      '시작',
      '열어',
      '해줘',
      '해',
      '줘',
      '부탁',
    ].any(normalized.contains);
  }

  String _directCountdownStartMessage() {
    if (_coach.id == 'nyang_halbae') {
      return '좋다냥. 숫자 세고 바로 시작해보자냥.';
    }
    if (_coach.id == 'sec_female') {
      return '좋아요, 대표님. 숫자 세고 바로 시작해볼게요.';
    }
    return '좋아. 숫자 세고 바로 시작해보자.';
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
    if (CoachConfigs.isNyangHalbae(_coach.id)) {
      if (names.length == 1) {
        return '최근 일정이었던 ‘${names.first}’을 잘 마무리했구나. 중요한 매듭 하나를 넘긴 셈이다냥.';
      }
      return '최근 일정이었던 ${_quotedMilestoneNames(names)}를 잘 마무리했구나. 중요한 매듭들을 하나씩 넘기고 있다냥.';
    }
    if (names.length == 1) {
      return '최근 일정이었던 ‘${names.first}’을 잘 마무리하셨네요. 중요한 단계를 잘 넘기셨어요.';
    }
    return '최근 일정이었던 ${_quotedMilestoneNames(names)}를 잘 마무리하셨네요. 중요한 단계들을 잘 넘기셨어요.';
  }

  String _noVisionMilestoneMessage() {
    if (CoachConfigs.isNyangHalbae(_coach.id)) {
      return '아직 적어둔 장기 비전이 없구나. 목표 탭에 장기 비전과 마일스톤 예정일을 하나 잡아두면, 길을 잃지 않게 같이 살펴두겠다냥.';
    }
    return '작성된 장기 비전이 없네요. 목표 탭에서 장기 비전과 마일스톤 예정일을 정해두시면 제가 챙겨드리겠습니다.';
  }

  String _noDatedMilestoneMessage() {
    if (CoachConfigs.isNyangHalbae(_coach.id)) {
      return '예정일이 잡힌 마일스톤이 아직 없구나. 중요한 비전 하나에 날짜를 붙여두면, 막연한 길도 조금 또렷해진다냥.';
    }
    return '예정일이 설정된 마일스톤이 없네요. 목표 탭에서 중요한 장기 비전의 마일스톤 예정일을 정해두시면 제가 챙겨드리겠습니다.';
  }

  String _milestoneStatusMessage({
    required int overdueCount,
    required int upcomingCount,
    required List<String> overdueNames,
    required List<String> upcomingNames,
  }) {
    if (CoachConfigs.isNyangHalbae(_coach.id)) {
      if (overdueCount > 0 && upcomingCount > 0) {
        return '예정일이 지난 마일스톤 $overdueCount개,\n일주일 안에 다가오는 마일스톤 $upcomingCount개가 있구나.\n\n목표 탭에서 한번 살펴보자냥.';
      }
      if (overdueCount > 0) {
        return '예정일이 지난 마일스톤이\n$overdueCount개 있구나.\n\n${_quotedMilestoneNames(overdueNames)} 등을\n목표 탭에서 확인해보자냥.';
      }
      if (upcomingCount > 0) {
        return '일주일 안에 다가오는 마일스톤이\n$upcomingCount개 있구나.\n\n${_quotedMilestoneNames(upcomingNames)} 등을\n목표 탭에서 확인해보자냥.';
      }
      return '지금 당장 확인이 필요한 마일스톤은 없구나. 길이 제법 잘 정리되어 있다냥.';
    }

    if (overdueCount > 0 && upcomingCount > 0) {
      return '예정일이 지난 마일스톤 $overdueCount개,\n일주일 안에 예정된 마일스톤 $upcomingCount개가 있어요.\n\n목표 탭에서 확인해보시겠습니까?';
    }
    if (overdueCount > 0) {
      return '예정일이 지난 마일스톤이\n$overdueCount개 있어요.\n\n${_quotedMilestoneNames(overdueNames)} 등을\n목표 탭에서 확인해보시겠습니까?';
    }
    if (upcomingCount > 0) {
      return '일주일 안에 예정된 마일스톤이\n$upcomingCount개 있어요.\n\n${_quotedMilestoneNames(upcomingNames)} 등을\n목표 탭에서 확인해보시겠습니까?';
    }
    return '지금 확인이 필요한 마일스톤은 없어요. 일정이 잘 정리되어 있습니다.';
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
      return _MilestoneCheckResult(
        message: _noVisionMilestoneMessage(),
        needsDeadlineSetup: true,
      );
    }

    if (!hasDatedMilestone) {
      return _MilestoneCheckResult(
        message: _noDatedMilestoneMessage(),
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
    lines.add(
      _milestoneStatusMessage(
        overdueCount: overdueCount,
        upcomingCount: upcomingCount,
        overdueNames: overdue.map((item) => item.name).toList(),
        upcomingNames: upcoming.map((item) => item.name).toList(),
      ),
    );

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

  Future<void> _handleStartDifficultyChip() async {
    if (_isLoading) return;
    if (!await _ensureMasterCoachAccess()) return;
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(
        ChatMessage(text: '시작하기가 힘들어', isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: '시작이 안 되는 건 할 일을 너무 많이 짊어졌을 때라냥.\n오늘 첫 조각을 정해서 한 스푼만 뜨자냥.',
          isUser: false,
          time: DateTime.now(),
          kind: 'start_difficulty_choice',
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
  }

  Future<void> _startMorningCountdown() async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();

    setState(() {
      _messages.add(
        ChatMessage(text: '생각 비우고 시작할래', isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: '좋다냥. 생각은 잠깐 내려놓고, 몸이 먼저 하루 문턱을 넘게 해보자냥.',
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

    await Future.delayed(const Duration(milliseconds: 650));
    if (mounted) _openCountdownFocusMode();
  }

  Future<void> _handlePerfectionismDistressChip() async {
    if (_isLoading) return;
    if (!await _ensureMasterCoachAccess()) return;
    HapticFeedback.lightImpact();

    final reply = await _buildNyangPerfectionismLocalReply();
    if (reply == null) {
      await _send(
        '완벽하게 못 해서 속상해',
        apiInputOverride:
            '사용자가 완벽하게 못 해서 속상하다고 다시 말했다. 같은 문장을 반복하지 말고, 완벽주의를 짧게 받아준 뒤 지금 할 수 있는 아주 작은 관점 전환이나 행동 하나만 자연스럽게 제안해줘.',
        masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
      );
      return;
    }

    setState(() {
      _messages.add(
        ChatMessage(text: '완벽하게 못 해서 속상해', isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
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
  }

  Future<void> _handleGroomingCareChip() async {
    if (_isLoading) return;
    await _loadGroomingMemory();
    if (!mounted) return;
    // 오늘 이미 하나 꺼내줬는데 또 눌렀다면, 그건 그게 별로였다는 뜻이다.
    // 못 본 척하고 집·밖부터 다시 물으면 방금 한 말을 잊은 사람처럼 보인다.
    final shownToday = _lastGroomingDate == _todayGroomingKey;
    // 날이 바뀐 뒤 다시 열면 지난 추천을 한 번 되묻는다. 뭘 추천했는지 인용하진
    // 않는다 — 문장을 잘라 붙이면 어색해지고, 되묻는다는 사실만으로 충분하다.
    final askBack =
        _lastGroomingBody != null &&
        !shownToday &&
        _askBackDoneDate != _todayGroomingKey;
    if (shownToday) {
      if (_groomingRetryDate != _todayGroomingKey) {
        _groomingRetryDate = _todayGroomingKey;
        _groomingRetryCount = 0;
      }
      _groomingRetryCount += 1;
    }
    // 장소를 아는 날엔 묻지 않고 바로 뽑는다. setState 밖에서 미리 만들어 둔다 —
    // 뽑기가 최근 기록까지 건드려서, 빌드 중에 부르면 흐름을 따라가기 어려워진다.
    final retryPlace = shownToday ? _lastGroomingPlace : null;
    final retryReply = retryPlace == null
        ? null
        : (retryPlace == 'home'
              ? _pickHomeGroomingRoutine()
              : _pickOutdoorGroomingRoutine());

    setState(() {
      _messages.add(
        ChatMessage(text: '나 좀 가꾸고 싶어', isUser: true, time: DateTime.now()),
      );
      // 되물을 게 있으면 여기서 멈춘다. 물어놓고 다음 질문을 같이 띄우면
      // 대답할 자리가 없어서, 되묻는 게 아니라 혼잣말처럼 읽힌다.
      if (askBack) {
        _messages.add(
          ChatMessage(
            text: '저번에 얘기한 거 해봤어? 못 했어도 괜찮아.',
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _messages.add(
          ChatMessage(
            text: '',
            isUser: false,
            time: DateTime.now(),
            kind: 'grooming_askback',
          ),
        );
      } else if (retryReply != null) {
        _messages.add(
          ChatMessage(
            text: _groomingRetryPrompt(_groomingRetryCount, retryPlace),
            isUser: false,
            time: DateTime.now(),
          ),
        );
        _messages.add(
          ChatMessage(text: retryReply, isUser: false, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: '',
            isUser: false,
            time: DateTime.now(),
            kind: retryPlace == 'home'
                ? 'grooming_followup_from_home'
                : 'grooming_followup_from_outdoor',
          ),
        );
      } else if (shownToday) {
        _appendGroomingPlaceQuestion(
          text: _groomingRetryPrompt(_groomingRetryCount, null),
        );
      } else {
        _appendGroomingPlaceQuestion();
      }
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
    // 가꾸기 퍼널의 분모. 이 값 대비 accept/resist 비율이 "문장이 실제로 먹혔나"의
    // 유일한 신호라서, 문장을 더 손보기 전에 이것부터 쌓아둔다.
    await AnalyticsService.logFeatureUsage('grooming_care');
    if (shownToday) {
      await _saveGroomingMemory();
      // 하루에 두 번 이상 여는 비율. 이게 높으면 한 번에 주는 문장이 안 맞는다는
      // 뜻이고, 풀을 늘릴지 정할 때 grooming_resist_repeat과 같이 봐야 한다.
      await AnalyticsService.logFeatureUsage('grooming_care_retry');
    }
  }

  /// 집·밖을 묻는 말과 선택지를 붙인다. setState 안에서만 부른다.
  void _appendGroomingPlaceQuestion({String text = '좋아. 지금 집이야, 밖이야?'}) {
    _messages.add(ChatMessage(text: text, isUser: false, time: DateTime.now()));
    _messages.add(
      ChatMessage(
        text: '',
        isUser: false,
        time: DateTime.now(),
        kind: 'grooming_care_choice',
      ),
    );
  }

  /// 되묻기에 답하면 그제서야 집·밖을 묻는다. 답에 따라 이어지는 말만 달라진다.
  Future<void> _answerGroomingAskBack(bool done) async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    // 되묻기에 답이 돌아왔으니 오늘은 다시 묻지 않는다. 추천 날짜와 따로 두는 건,
    // 여기서 그걸 오늘로 밀면 아직 아무것도 안 꺼내줬는데 "아까 그건 별로였어?"가 뜬다.
    _askBackDoneDate = _todayGroomingKey;

    setState(() {
      _messages.add(
        ChatMessage(
          text: done ? '응, 해봤어' : '아니, 못 했어',
          isUser: true,
          time: DateTime.now(),
        ),
      );
      _appendGroomingPlaceQuestion(
        text: done
            ? '잘했어. 그럼 오늘 것도 골라보자. 지금 집이야, 밖이야?'
            : '그럴 수도 있지. 오늘 걸로 다시 해보자. 지금 집이야, 밖이야?',
      );
      _suggestedTasks = [];
      _dynamicChips = _coach.chips;
      _suppressDefaultChips = false;
    });
    _scrollToBottom();
    await _saveHistory();
    await _saveGroomingMemory();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    // 되묻기에 실제로 답하는 비율, 그리고 해본 비율. 문장이 밖에서 먹혔는지의 유일한 단서다.
    await AnalyticsService.logFeatureUsage(
      done ? 'grooming_askback_done' : 'grooming_askback_missed',
    );
  }

  Future<void> _sendGroomingCareRoutine({
    required String userText,
    required String reply,
    required String feature,
    String? place,
  }) async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    if (place != null) _lastGroomingPlace = place;

    setState(() {
      _messages.add(
        ChatMessage(text: userText, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(
          text: '',
          isUser: false,
          time: DateTime.now(),
          kind: 'grooming_care_followup',
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
    // 집·밖 중 어느 쪽에서 열리는지. 한쪽이 거의 안 눌리면 그 목록부터 손보면 된다.
    await AnalyticsService.logFeatureUsage(feature);
    await _saveGroomingMemory();
  }

  Future<void> _sendHomeGroomingRoutine() {
    return _sendGroomingCareRoutine(
      userText: '집이야',
      reply: _pickHomeGroomingRoutine(),
      feature: 'grooming_home',
      place: 'home',
    );
  }

  Future<void> _sendOutdoorGroomingRoutine() {
    return _sendGroomingCareRoutine(
      userText: '밖이야',
      reply: _pickOutdoorGroomingRoutine(),
      feature: 'grooming_outdoor',
      place: 'outdoor',
    );
  }

  Future<void> _acceptGroomingCareRoutine() async {
    // _send가 로딩 중이면 아무 일도 안 하고 빠져나간다. 그 경우까지 세면
    // 분자만 부풀어서 비율이 실제보다 좋게 보인다.
    if (_isLoading) return;
    // 문장을 받아들인 비율. grooming_care 대비로 봐야 의미가 있다.
    await AnalyticsService.logFeatureUsage('grooming_accept');
    await _send(
      '알았어. 해볼게',
      apiInputOverride: '방금 추천받은 가꾸기 루틴을 해보겠다고 한다. 부담을 키우지 말고 짧게 응원해줘.',
    );
  }

  Future<void> _resistGroomingCareRoutine() async {
    if (_isLoading) return;
    // 이 비율이 곧 "뭐야 하고 지나가는" 비율이다. 문장 손볼 우선순위의 근거.
    await AnalyticsService.logFeatureUsage('grooming_resist');
    // 거절한 문장은 횟수만 세어둔다. 뽑기에는 영향을 주지 않는다.
    final rejected = _lastGroomingBody;
    if (rejected != null) {
      final record = _groomingDislikes[rejected];
      if (record == null) {
        _groomingDislikes[rejected] = _GroomingDislike(
          count: 1,
          lastAt: DateTime.now(),
        );
      } else {
        record.count += 1;
        record.lastAt = DateTime.now();
        // 전에도 거절했던 문장을 또 거절한 경우. grooming_resist 대비로 보면
        // "반복 때문에 지치는가"를 알 수 있다. 문장을 더 쓸지 정하는 근거다.
        await AnalyticsService.logFeatureUsage('grooming_resist_repeat');
      }
      await _saveGroomingMemory();
    }
    await _send(
      '하기 귀찮아',
      apiInputOverride:
          '방금 추천받은 가꾸기 루틴이 귀찮다고 느낀다. 더 작게 줄이거나 부담을 낮춰서 바로 시작할 수 있게 도와줘.',
    );
  }

  /// 방금 본 문장이 또 나오면 "복붙" 티가 제일 크게 난다. 최근에 나온 건 후보에서 뺀다.
  /// 앱을 다시 켜면 비워지는데, 한 세션 안의 연속 반복만 막아도 체감이 크게 달라져서
  /// 저장까지는 하지 않는다(뽑기 함수들이 전부 동기라 async로 바꾸면 호출부까지 번진다).
  /// 집과 밖이 이 기록을 함께 쓴다 — 두 목록에 겹치는 문장이 있어서,
  /// 버튼을 바꿔 눌렀을 때 같은 문장이 다시 나오는 것도 같이 막힌다.
  /// 도입구와 어미가 매번 달라지므로, 완성된 문장이 아니라 본문(body)을 기준으로 기억한다.
  final List<String> _recentGroomingLines = [];
  static const int _groomingRecentMemory = 3;

  /// 귀찮다고 한 문장의 거절 횟수와 마지막 거절 시각.
  ///
  /// 뽑기에는 쓰지 않는다. 한때 거절한 문장을 후보에서 뺐는데, 시간대별로 나뉜
  /// 풀이 원래 3~12개라 뺄수록 눈에 띄게 얕아졌다. 게다가 안 나온 문장을
  /// 알아차리는 사람은 없어서, 기억한다는 느낌은 주지 못하고 풀만 깎였다.
  /// 그 몫은 되묻기가 한다 — 그건 기억이 화면에 뜬다.
  ///
  /// 대신 어떤 문장이 반복해서 거절당하는지 세어두고 지표로 내보낸다.
  /// 숨길 문장이 아니라 고쳐 쓸 문장을 찾는 게 이 기록의 쓸모다.
  /// 풀 크기만큼만 쌓이므로(현재 38개) 따로 만료시키지 않는다.
  final Map<String, _GroomingDislike> _groomingDislikes = {};

  /// 마지막으로 추천한 문장과 그 날짜. 날이 바뀐 뒤 다시 열면 되물어보고,
  /// 같은 날 또 열면 아까 것이 별로였냐고 짚는다.
  String? _lastGroomingBody;
  String? _lastGroomingDate;

  /// 되묻기에 답한 날. 답을 받고도 루틴을 안 고른 채 다시 열었을 때
  /// 같은 질문을 또 하지 않으려고, 추천 날짜와 따로 센다.
  String? _askBackDoneDate;

  /// 같은 날 다시 누른 횟수와 그 날짜. 세 번, 네 번 누르는데 매번 똑같이
  /// "아까 그건 별로였어?"로 받으면, 짚어주려던 게 오히려 녹음 같아진다.
  int _groomingRetryCount = 0;
  String? _groomingRetryDate;

  /// 오늘 고른 장소('home'/'outdoor'). 같은 날 또 열면 이걸 다시 묻지 않는다.
  /// 하루 사이에 나갈 수도 있어서 단정만 하고 끝내지 않고, 아래 카드에
  /// 자리를 바꾸는 버튼을 같이 둔다.
  String? _lastGroomingPlace;

  /// 다시 누른 횟수에 맞춰 받는 말. 처음엔 안 맞았다고 단정하지 않는다 —
  /// 해놓고 하나 더 받으러 온 걸 수도 있어서, 묻고 그냥 다음으로 넘어간다.
  /// 횟수가 쌓이면 캐묻지 않고 물러난다. 계속 안 맞는 날에 이유까지 물으면
  /// 고르는 게 일이 된다.
  String _groomingRetryPrompt(int count, String? place) {
    const tail = '지금 집이야, 밖이야?';
    if (place == null) {
      if (count <= 1) return '아까 내가 하라고 한 건 했어? 음.. 그럼 또 뭐가 있을까. $tail';
      if (count == 2) return '오늘 계속 안 맞네. 다시 골라볼게. $tail';
      return '오늘은 뭘 꺼내도 잘 안 맞는 날인가 봐. 그런 날도 있어. $tail';
    }
    // 장소를 아는 날엔 되묻지 않는다. 방금 들은 걸 또 묻는 게 제일 티가 난다.
    final label = place == 'home' ? '집' : '밖';
    if (count <= 1) {
      return '아까 내가 하라고 한 건 했어? 음.. 그럼 또 뭐가 있을까. 아까 $label이라고 했지?';
    }
    if (count == 2) return '오늘 계속 안 맞네. 아직 $label이지? 하나 더 볼게.';
    return '오늘은 뭘 꺼내도 잘 안 맞는 날인가 봐. 그런 날도 있어.';
  }

  bool _groomingMemoryLoaded = false;

  String get _groomingMemoryPrefix => 'nyang_grooming_${widget.coachId}';
  String get _todayGroomingKey =>
      DateTime.now().toIso8601String().substring(0, 10);

  /// 앱을 다시 켜도 남아야 하는 것만 prefs에서 읽는다. 전부 사실이라 틀릴 일이 없다.
  Future<void> _loadGroomingMemory() async {
    if (_groomingMemoryLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    _recentGroomingLines
      ..clear()
      ..addAll(prefs.getStringList('${_groomingMemoryPrefix}_recent') ?? []);
    _loadGroomingDislikes(prefs);
    _lastGroomingBody = prefs.getString('${_groomingMemoryPrefix}_last_body');
    _lastGroomingDate = prefs.getString('${_groomingMemoryPrefix}_last_date');
    _askBackDoneDate = prefs.getString('${_groomingMemoryPrefix}_askback_date');
    _groomingRetryDate = prefs.getString('${_groomingMemoryPrefix}_retry_date');
    _groomingRetryCount =
        prefs.getInt('${_groomingMemoryPrefix}_retry_count') ?? 0;
    _lastGroomingPlace = prefs.getString('${_groomingMemoryPrefix}_last_place');
    _groomingMemoryLoaded = true;
  }

  /// 거절 기록을 읽는다. 예전 버전은 문장 목록만 저장했으니 한 번 거절한 것으로
  /// 치고 넘긴다 — 그 목록 때문에 후보에서 빠져 있던 문장이 전부 돌아온다.
  void _loadGroomingDislikes(SharedPreferences prefs) {
    _groomingDislikes.clear();
    final raw = prefs.getString('${_groomingMemoryPrefix}_disliked_v2');
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((body, value) {
            final record = _GroomingDislike.fromJson(value);
            if (body is String && record != null) {
              _groomingDislikes[body] = record;
            }
          });
        }
      } catch (_) {
        // 형식이 깨졌으면 기록을 버린다. 거절 기억을 잃는 것보다 앱이 막히는 게 나쁘다.
      }
    } else {
      final legacy = prefs.getStringList('${_groomingMemoryPrefix}_disliked');
      final now = DateTime.now();
      for (final body in legacy ?? const <String>[]) {
        _groomingDislikes[body] = _GroomingDislike(count: 1, lastAt: now);
      }
    }
  }

  Future<void> _saveGroomingMemory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      '${_groomingMemoryPrefix}_recent',
      _recentGroomingLines,
    );
    await prefs.setString(
      '${_groomingMemoryPrefix}_disliked_v2',
      jsonEncode(
        _groomingDislikes.map(
          (body, record) => MapEntry(body, record.toJson()),
        ),
      ),
    );
    final body = _lastGroomingBody;
    final date = _lastGroomingDate;
    // 오늘 날짜를 여기서 찍지 않는다. 이 함수는 되묻기에 답만 해도 불리는데,
    // 그때 추천 날짜까지 오늘로 밀리면 안 꺼내준 걸 꺼내준 걸로 세게 된다.
    // 날짜는 실제로 문장을 뽑는 자리에서만 갱신한다.
    if (body != null) {
      await prefs.setString('${_groomingMemoryPrefix}_last_body', body);
    }
    if (date != null) {
      await prefs.setString('${_groomingMemoryPrefix}_last_date', date);
    }
    final askBackDate = _askBackDoneDate;
    if (askBackDate != null) {
      await prefs.setString(
        '${_groomingMemoryPrefix}_askback_date',
        askBackDate,
      );
    }
    final place = _lastGroomingPlace;
    if (place != null) {
      await prefs.setString('${_groomingMemoryPrefix}_last_place', place);
    }
    final retryDate = _groomingRetryDate;
    if (retryDate != null) {
      await prefs.setString('${_groomingMemoryPrefix}_retry_date', retryDate);
      await prefs.setInt(
        '${_groomingMemoryPrefix}_retry_count',
        _groomingRetryCount,
      );
    }
  }

  final Random _groomingRandom = Random();

  /// 오늘 정한 어미 후보 셋. 셋 다 추측('~일 거야', '~걸')이거나 경험담('~더라')이라
  /// 효과를 단정하지 않는다. '~해 보여'처럼 남의 시선을 끌어오는 어미는 후보에 없다.
  static const List<String> _groomingEndings = ['거야', '더라', '걸'];

  /// 직전에 쓴 도입구·어미. 같은 게 연달아 나오면 조합이 돌아가는 게 아니라
  /// 고장 난 것처럼 읽혀서, 바로 앞에 쓴 것만 후보에서 뺀다.
  String? _lastGroomingOpener;
  String? _lastGroomingEnding;

  /// 집 도입구. 빈 문자열이 섞여 있어서 도입구 없이 바로 시작하기도 한다.
  static const List<String> _homeGroomingOpeners = [
    '',
    '딱 5분이면 돼. ',
    '오래 안 걸리는 걸로 하나 골라봤어. ',
    '지금 바로 할 수 있는 거야. ',
    '마음부터 좀 풀어보자. ',
    '무겁게 생각하지 말고, ',
  ];

  /// 밖 도입구. 지금 서 있는 자리에서 된다는 걸 앞에서 짚어준다.
  static const List<String> _outdoorGroomingOpeners = [
    '',
    '밖이면 이게 편해. ',
    '지금 서 있는 자리에서 되는 거야. ',
    '조용히 할 수 있는 거야. ',
  ];

  /// 새벽엔 재우는 쪽으로 안내하니까 도입구도 조용한 것만 쓴다. 집·밖 공용.
  static const List<String> _lateNightGroomingOpeners = [
    '',
    '지금은 이 정도면 충분해. ',
    '오늘은 여기까지만. ',
  ];

  _GroomingLine _pickFreshGroomingLine(List<_GroomingLine> pool) {
    final fresh = pool
        .where((line) => !_recentGroomingLines.contains(line.body))
        .toList();
    // 후보가 다 소진되면 어쩔 수 없이 전체에서 다시 고른다.
    final candidates = fresh.isEmpty ? pool : fresh;
    final picked = candidates[_groomingRandom.nextInt(candidates.length)];
    _lastGroomingBody = picked.body;
    // 실제로 문장을 꺼내주는 건 여기뿐이다. 추천 날짜는 이 자리에서만 갱신한다.
    _lastGroomingDate = _todayGroomingKey;
    _recentGroomingLines.add(picked.body);
    while (_recentGroomingLines.length > _groomingRecentMemory) {
      _recentGroomingLines.removeAt(0);
    }
    return picked;
  }

  /// 직전에 쓴 조각만 빼고 하나 고른다.
  String _pickGroomingSlot(List<String> pool, String? last) {
    final fresh = pool.where((s) => s != last).toList();
    final candidates = fresh.isEmpty ? pool : fresh;
    return candidates[_groomingRandom.nextInt(candidates.length)];
  }

  /// 어간에 관형형 'ㄹ'을 붙인다('나아지' → '나아질', '들' → '들', '좋' → '좋을').
  /// 여기 쓰는 어간은 전부 규칙 활용이라 받침만 보고 판단해도 어색해지지 않는다.
  String _groomingModifierForm(String stem) {
    const hangulStart = 0xAC00;
    const hangulEnd = 0xD7A3;
    final last = stem.codeUnitAt(stem.length - 1);
    if (last < hangulStart || last > hangulEnd) return '$stem을';
    final finalConsonant = (last - hangulStart) % 28;
    // 받침이 없으면 그 자리에 'ㄹ'(종성 8번)을 넣는다.
    if (finalConsonant == 0) {
      return stem.substring(0, stem.length - 1) + String.fromCharCode(last + 8);
    }
    if (finalConsonant == 8) return stem; // 이미 'ㄹ' 받침이면 그대로 쓴다.
    return '$stem을';
  }

  /// 도입구 + 본문 + (효과 문장 + 어미)로 한 줄을 완성한다.
  /// 본문은 손대지 않으니 뜻은 그대로 두고 말투만 달라진다.
  String _renderGroomingLine(_GroomingLine line, List<String> openers) {
    final opener = _pickGroomingSlot(openers, _lastGroomingOpener);
    // 후보가 하나뿐인 자리(폴백 답변)는 기억해봐야 다음 뽑기 폭만 좁힌다.
    if (openers.length > 1) _lastGroomingOpener = opener;
    final effect = line.effect;
    if (effect == null) return '$opener${line.body}';
    final ending = _pickGroomingSlot(_groomingEndings, _lastGroomingEnding);
    _lastGroomingEnding = ending;
    final closing = ending == '더라'
        ? '$effect더라'
        : '${_groomingModifierForm(effect)} $ending';
    return '$opener${line.body} $closing.';
  }

  /// 집(낮)과 밖에 함께 들어가는 문장. 거울은 어디에나 있어서 양쪽 다 된다.
  /// 한 군데에 두면 어느 쪽으로 뽑히든 최근 기록을 공유해서 연달아 나오는 걸 막을 수 있다.
  static const _GroomingLine _mirrorSpotGroomingLine = _GroomingLine(
    '거울 앞에 잠깐 서봐. 머리, 얼굴, 옷 중에 제일 신경 쓰이는 곳 하나만 가볍게 만져주자.',
    effect: '별 거 아니어도 기분이 좀 나아지',
  );

  /// 공용 문장 중 새벽에도 꺼낼 수 있는 것들. 몸을 깨우는 동작이 없고
  /// 부담을 내려놓는 쪽이라, 재우는 방향으로 안내하는 새벽 톤과 어긋나지 않는다.
  /// 새벽 목록이 제일 얇아서(전용 5개) 여기서 받아 가는 몫이 크다.
  static const List<_GroomingLine> _calmGroomingLines = [
    _GroomingLine(
      '오늘은 예뻐져야 한다는 숙제는 잠깐 미뤄두자. 손을 씻고 향이 나는 걸 하나 발라봐.',
      effect: '몸이 편해지면 마음도 조금 따라오',
    ),
    _GroomingLine(
      '목이랑 어깨만 천천히 풀어보자.',
      effect: '스트레칭을 꾸준히 하면 몸선도 자세도 조금씩 좋아져서 몸이 괜히 더 가볍고 편해지',
    ),
  ];

  /// 집에서 시간대를 안 타는 문장. 아침·낮·저녁 목록에 공통으로 얹는다.
  /// 새벽(0~6시)엔 몸을 깨우는 동작이라 빼둔다 — 그 시간대는 재우는 쪽으로 안내한다.
  static const List<_GroomingLine> _anytimeHomeGroomingRoutines = [
    _GroomingLine(
      '기지개를 쭉 편 다음 겨드랑이를 꾹꾹 눌러줘. 그리고 마지막으로 겨드랑이에서 팔 안쪽으로 쓸어주면 림프 순환이 잘 된대.',
      effect: '몸이 시원해져서 기분도 조금 괜찮아지',
    ),
    _GroomingLine(
      '따뜻한 물 한 모금 마시고 얼굴만 가볍게 씻어보자. 지금은 완벽한 관리보다 다시 산뜻해지는 느낌 하나면 충분해.',
    ),
    _GroomingLine(
      '좋아하는 향수나 바디미스트가 있으면 한 번만 뿌려봐.',
      effect: '향 하나로 기분이 꽤 빨리 돌아오',
    ),
    ..._calmGroomingLines,
    _GroomingLine(
      '화장품 바르기 전에 손부터 씻고, 화장품 용기 표면도 한 번 닦아줘.',
      effect: '별 거 아닌 거 같아도 이런 게 쌓이면 피부가 덜 예민해지',
    ),
    _manualScalpMassageLine,
  ];

  String _pickHomeGroomingRoutine() {
    final hour = DateTime.now().hour;
    final lines = switch (hour) {
      >= 6 && < 12 => const [
        _GroomingLine(
          '물 한 잔 먼저 마셔보자. 혹시 챙겨 먹는 영양제가 있으면 지금 같이 먹어도 좋아.',
          effect: '몸 안쪽 컨디션이 잡히면 피부도 훨씬 덜 푸석해지',
        ),
        _GroomingLine(
          '선크림은 발랐어? 밖에 안 나가도 실내로 햇빛이 들어오면 피부에 안 좋아.',
          effect: '오늘은 선크림 하나만 챙겨도 관리한 느낌이 나',
        ),
        _GroomingLine(
          '아침에 얼굴이 좀 부은 느낌이면 찬물로 손을 씻고, 턱이랑 귀 밑을 가볍게 쓸어줘. 세게 하지 말고 1분만 해도',
          effect: '얼굴이 조금 깨는 느낌이 들',
        ),
        _GroomingLine(
          '머리 앞쪽만 정리해보자.',
          effect: '아침엔 전체 스타일보다 앞머리랑 정수리 볼륨만 살아도 하루가 훨씬 산뜻하게 시작되',
        ),
        _GroomingLine(
          '어깨를 내리고 목을 길게 세워봐.',
          effect: '아침 자세가 잡히면 숨도 깊어지고 몸이 한결 가벼워지',
        ),
        _GroomingLine('과일 챙겨먹는 거 어때?', effect: '비타민을 꾸준히 챙기면 피부 컨디션도 조금씩 달라지'),
      ],
      >= 12 && < 18 => const [
        _GroomingLine(
          '턱에 힘 빼고 입꼬리를 살짝 올려봐. 크게 바꾸지 않아도 충분히 괜찮아.',
          effect: '머리 앞쪽만 정리하고 자세만 바로 세워도 얼굴에 들어간 힘이 스르르 풀리',
        ),
        _GroomingLine(
          '미스트나 선크림이 있으면 피부부터 가볍게 챙겨보자. 그다음 입술이 건조하면 립밤만 발라줘.',
          effect: '얼굴에 수분감 하나만 더해도 피곤한 게 조금 가시는 느낌이 들',
        ),
        _GroomingLine(
          '지금 앉아 있어, 서 있어? 배에 힘을 아주 살짝만 줘봐. 모델들도 촬영 전에 자주 쓰는 작은 습관이래.',
          effect: '허리를 세우고 아랫배를 안쪽으로 가볍게 당기면 몸이 훨씬 곧게 잡히는 느낌이 들',
        ),
        _mirrorSpotGroomingLine,
      ],
      >= 18 && < 24 => const [
        _GroomingLine(
          '손톱은 정리했어? 아직이면 오늘은 손톱만 깔끔하게 깎아보자.',
          effect: '작은 부분인데도 손끝이 정돈되면 기분이 꽤 달라지',
        ),
        _GroomingLine(
          '혹시 집 안에 방치된 미용기기 있어? 고데기, 괄사, 마사지기, 드라이기 같은 거. 없으면 안 쓰는 마스크팩도 괜찮아. 오늘은 새로 뭘 사지 말고, 이미 있는 걸 한 번 써먹어보자.',
          effect: '안 쓰던 걸 꺼내 쓰는 것만으로도 뭔가 챙긴 기분이 나',
        ),
        _GroomingLine(
          '두피 마사지 어때? 간단한 괄사 도구가 있으면 정수리 쪽으로 천천히 쓸어올려봐. 꾸준히 해주면 노화 예방이나 머리 빠짐 관리에도 도움 된대.',
          effect: '두피가 덜 굳어서 머리가 한결 가벼워지',
        ),
        _GroomingLine(
          '몸 전체를 관리하려고 하지 말고, 오늘은 신경 쓰이던 잔털 한 군데만 정리해봐.',
          effect: '작은 정돈인데도 깔끔해진 느낌이 꽤 오래 가',
        ),
        _GroomingLine(
          '자기 전 세안하고 화장품 바를 때, 여러 개를 한꺼번에 올리지 말고 하나씩 찹찹 흡수시켜줘.',
          effect: '헤어라인, 귀 뒤, 목 아래쪽까지 같이 발라주면 피부가 훨씬 잘 챙겨진 느낌이 들',
        ),
        _GroomingLine(
          '향이 나는 오일이나 로션을 목에 바르고 어깨랑 쇄골 쪽을 마사지해줘봐.',
          effect: '노폐물이 빠져서 피부톤도 조금 맑아지',
        ),
        _GroomingLine(
          '편한 옷으로 갈아입고 조명을 조금 따뜻하게 바꿔봐.',
          effect: '분위기가 바뀌면 나를 대하는 마음도 덜 거칠어지',
        ),
      ],
      _ => const [
        _GroomingLine(
          '너무 늦은 시간이니까 자극적인 관리는 빼자. 얼굴만 가볍게 씻고 보습 하나 얹어줘. 오늘은 피부를 깨우기보다 편하게 재우는 쪽이 좋아.',
        ),
        _GroomingLine(
          '립밤이나 핸드크림처럼 조용한 관리 하나만 하자. 새벽엔 크게 꾸미려 하기보다 몸이 쉬어도 된다는 신호를 주는 게 더 좋아.',
        ),
        _GroomingLine(
          '두피를 세게 문지르진 말고 손끝으로 살짝만 눌러줘. 머리가 조금 가벼워지면 바로 내려놓고 쉬자. 오래 하면 자극될 수 있어.',
        ),
        _GroomingLine(
          '잠옷이나 편한 옷으로 갈아입고 목 주변만 느슨하게 풀어줘. 몸이 편해지는 상태를 만드는 것도 충분한 관리야.',
        ),
        _GroomingLine(
          '뭘 관리하려고 하지 말고 잘 자는 게 1순위일 것 같아. 눈 감고 천천히 숨을 쉬어봐. 온 몸에 긴장 빼고. 할 수 있겠어?',
        ),
      ],
    };
    final isLateNight = hour < 6;
    // 새벽엔 공용 문장 중 조용한 것만 받는다. 나머지는 몸을 깨우는 쪽이라 뺀다.
    final pool = isLateNight
        ? [...lines, ..._calmGroomingLines]
        : [...lines, ..._anytimeHomeGroomingRoutines];
    return _renderGroomingLine(
      _pickFreshGroomingLine(pool),
      isLateNight ? _lateNightGroomingOpeners : _homeGroomingOpeners,
    );
  }

  /// 마지막 말풍선이 집·밖 선택지 카드인가. 그 자리에서 온 답만 장소로 읽는다.
  bool get _awaitingGroomingPlace =>
      _messages.isNotEmpty && _messages.last.kind == 'grooming_care_choice';

  /// 밖으로 치는 말. 회사·학교·카페는 남 앞이라 밖 문장이 그대로 맞는다.
  static const List<String> _outdoorPlaceWords = [
    '밖',
    '회사',
    '사무실',
    '학교',
    '카페',
    '지하철',
    '버스',
    '외출',
    '이동중',
    '길',
  ];

  static const List<String> _homePlaceWords = ['집', '방', '자취', '침대'];

  /// 버튼 대신 타이핑한 답을 집·밖으로 읽는다. 어느 쪽도 아니면 null을 주고
  /// 평소 대화로 넘긴다 — 애매한 걸 억지로 한쪽에 밀어 넣지 않는다.
  String? _groomingPlaceFromText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    // 밖을 먼저 본다. '집에 가는 길이야'처럼 둘 다 걸리는 말은 아직 밖이다.
    if (_outdoorPlaceWords.any(normalized.contains)) return 'outdoor';
    if (_homePlaceWords.any(normalized.contains)) return 'home';
    return null;
  }

  String? _groomingToolFallbackReply(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '');
    final mentionsScalpCare =
        normalized.contains('괄사') ||
        normalized.contains('두피마사지') ||
        normalized.contains('두피') ||
        normalized.contains('마사지도구');
    final saysUnavailable =
        normalized.contains('없') ||
        normalized.contains('안가지') ||
        normalized.contains('안갖') ||
        normalized.contains('못찾');
    if (!mentionsScalpCare || !saysUnavailable) return null;
    return _manualScalpMassageRoutine();
  }

  static const _GroomingLine _manualScalpMassageLine = _GroomingLine(
    '손끝으로 두피를 천천히 눌러봐. 뻐근하다 싶은 부위를 둥글게 문질러주면 돼. 맞다, 너무 길게 하면 자극이 될 수 있으니까 3분 정도만 하자.',
    effect: '두피가 풀리면 머리도 가볍고 얼굴 컨디션도 조금 살아나는 느낌이 들',
  );

  /// "괄사 없어" 같은 답을 바로 되받는 자리라 도입구도 '그럼' 하나로 고정한다.
  /// 기분 전환 목록에 같은 문장이 들어갈 땐 거기 도입구가 대신 붙는다.
  String _manualScalpMassageRoutine() =>
      _renderGroomingLine(_manualScalpMassageLine, const ['그럼 ']);

  /// 밖에서는 시간대를 나누지 않는다. 남 앞에서 티 안 나게 할 수 있는 게
  /// 어차피 비슷해서, 아침에 뽑히든 저녁에 뽑히든 어색해지지 않을 문장만 모았다.
  /// 시간에 걸리는 문장(선크림)은 조건절을 앞에 달아서 밤에도 걸리지 않게 했다.
  static const List<_GroomingLine> _outdoorGroomingRoutines = [
    _GroomingLine(
      '햇빛 아래 오래 있었으면 선크림 한 번만 덧발라줘. 없으면 그늘로 두어 걸음만 옮겨도 돼.',
      effect: '이거 하나만 챙겨도 나중에 피부가 덜 지치',
    ),
    _GroomingLine(
      '턱에 힘 빼고 입꼬리를 살짝 올려봐. 크게 바꾸지 않아도 충분히 괜찮아.',
      effect: '자세만 바로 세워도 얼굴에 들어간 힘이 스르르 풀리',
    ),
    _GroomingLine(
      '가방에 미스트나 립밤 있어? 있으면 건조한 데 하나만 발라줘.',
      effect: '수분감 하나만 더해도 피곤한 게 조금 가시는 느낌이 들',
    ),
    _GroomingLine(
      '지금 앉아 있어, 서 있어? 배에 힘을 아주 살짝만 줘봐. 모델들도 촬영 전에 자주 쓰는 작은 습관이래.',
      effect: '허리를 세우고 아랫배를 안쪽으로 가볍게 당기면 몸이 훨씬 곧게 잡히는 느낌이 들',
    ),
    _mirrorSpotGroomingLine,
    _GroomingLine(
      '어깨를 뒤로 살짝 열고 시선만 조금 위로 둬봐. 걸음도 같이 느긋해지게.',
      effect: '움츠린 자세만 풀어도 숨이 깊어지고 몸이 한결 가벼워지',
    ),
    _GroomingLine(
      '물 마신 지 오래됐으면 지금 몇 모금만 마시자. 편의점이든 정수기든 지나가는 길에 있는 걸로.',
      effect: '몸 안쪽이 채워지면 얼굴 푸석한 것도 조금 가라앉',
    ),
    _GroomingLine(
      '화장실 갈 일 있으면 손 씻고 찬물로 손목 안쪽을 잠깐만 대봐. 오래 말고 몇 초면 돼.',
      effect: '열이 내려가면서 얼굴에 몰린 기운도 좀 정리되',
    ),
    _GroomingLine(
      '손거울이나 폰 화면으로 앞머리만 슬쩍 정리해봐. 전체를 손볼 필요는 없어.',
      effect: '앞머리랑 정수리 볼륨만 살아도 인상이 꽤 산뜻해지',
    ),
    _GroomingLine(
      '옷 매무새 한 번만 고쳐보자. 소매랑 옷깃만 정리해도 충분해.',
      effect: '몇 초 안 걸리는데 몸에 붙어 있던 어수선한 느낌이 가시',
    ),
  ];

  /// 새벽에 밖이면 관리보다 무사히 들어가는 게 먼저다. 짧게만 짚어준다.
  static const List<_GroomingLine> _lateNightOutdoorGroomingRoutines = [
    _GroomingLine('이 시간에 밖이면 관리보다 무사히 들어가는 게 먼저야. 가는 길에 물 몇 모금이랑 립밤 정도만 챙기자.'),
    _GroomingLine('새벽 공기에 얼굴이 금방 마르니까 립밤이나 핸드크림만 하나 발라줘. 나머지는 들어가서 하자.'),
    _GroomingLine('어깨 움츠리고 걷지 말고 목만 살짝 세워봐. 집에 도착하면 씻는 것도 미루지 말고 바로 하자.'),
  ];

  String _pickOutdoorGroomingRoutine() {
    final isLateNight = DateTime.now().hour < 6;
    return _renderGroomingLine(
      _pickFreshGroomingLine(
        isLateNight
            ? _lateNightOutdoorGroomingRoutines
            : _outdoorGroomingRoutines,
      ),
      isLateNight ? _lateNightGroomingOpeners : _outdoorGroomingOpeners,
    );
  }

  static const String _nyangPerfectionismLineDateKey =
      'nyang_halbae_perfectionism_line_date';
  static const String _nyangPerfectionismLineIndexKey =
      'nyang_halbae_perfectionism_line_index';
  static const String _nyangPerfectionismClickDateKey =
      'nyang_halbae_perfectionism_click_date';
  static const String _nyangPerfectionismClickCountKey =
      'nyang_halbae_perfectionism_click_count';
  static const String _nyangPerfectionismTaskLineIndexKey =
      'nyang_halbae_perfectionism_task_line_index';

  static const List<String> _nyangPerfectionismInsights = [
    '완벽하게 못 해서 속상한 마음, 그거 너무 기준이 높아서 생긴 상처일 수 있다냥. 오늘은 잘하는 나 말고, 시작하는 나만 데려오면 된다냥.',
    '완벽하게 하려다가 시작도 제대로 못한 적, 수두룩하지 않냥? 오늘부터 어설픈 시도를 수없이 쌓으면 일 년 뒤엔 어떨까 생각해보라냥.',
    '자꾸 완벽하게 하려 들면 시작이 제일 무거워진다냥. 오늘은 못난 초안이어도 좋으니, 아주 작게 하나만 건드려보자냥.',
    '완벽하게 해낸 날은 마음이 편했냥? 아마 그 다음 날 기준이 또 한 칸 올라갔을 거다냥. 이건 도착점이 없는 길이라냥.',
    '죽어도 해내야 하는 일은 없다냥. 오늘은 "안 되면 말지" 하는 마음으로 가볍게 한 번만 건드려보자냥.',
    '냥이가 쥐 열 마리를 한꺼번에 노리면 한 마리도 못 잡는다냥. 근데 한 마리만 노리고 있으면, 어느새 다섯 마리가 발밑에 굴러와 있더라냥.',
    '속상하지? 그 마음 없애려 하지 말고 딱 5분만 그대로 둬보자냥. 고치고 싶은 걸 안 고친 채로 그냥 있는 것, 그게 견디는 연습이라냥. 그거 하나로 완벽주의는 슬슬 힘이 빠진다냥.',
    '완벽하지 않은 나도 받아들이는 건 어떨까냥? 물론 마음은 안 좋겠지. 근데 그 텁텁한 기분을 끝까지 느끼고 나면 비로소 한 걸음 나아갈 수 있을지도 모른다냥',
    '완벽하지 않으면 어때? 나 자체가 특별한데. 이 우주엔 오직 하나밖에 없는 나인데 좀 봐주라냥.',
    '완벽주의는 어쩌면\n두려움으로부터 스스로를 지키려는 마음일지도 모른다냥.\n\n두려움은 피할수록 커지는 법이지.\n불쾌하더라도 없애려 하지 말고\n잠시 그대로 느껴보라냥.\n\n그 기분을 견딜 수 있다는 걸 언젠가 알게 되면,\n완벽하지 않아도 한 걸음 내디딜 수 있다냥.',
    '모든 일을 예술가의 혼으로 완벽하게 하려고 하지 말고, 툭, 툭, 해내는 연습을 해보라냥. 어때, 마음이 불편해지냥? 그럼 그 불편함을 견디는 연습을 5분이라도 해보라냥.',
    '완벽주의는 부족한 나를 견디지 못해서 만들어낸 허상일 뿐이라냥. 완벽이라는 개념은 모두 가짜라냥. 완벽하지 못한 나를 견디게 되면 완벽주의도 없어진다냥.',
  ];

  Future<String?> _buildNyangPerfectionismLocalReply() async {
    final prefs = await SharedPreferences.getInstance();
    final todayStr = _getTodayStrWithReset(prefs);

    final clickCount = await _nextNyangPerfectionismClickCount(prefs, todayStr);
    if (clickCount == 1) {
      final line = _pickNyangPerfectionismInsight(prefs);
      await prefs.setString(_nyangPerfectionismLineDateKey, todayStr);
      return line;
    }

    if (clickCount == 2) {
      final taskName = await _pickSmallPendingTaskName();
      if (taskName != null) {
        // 같은 문장이 매번 반복되지 않도록 표현만 바꾼 변형들 중 하나를 고른다.
        final lines = [
          '\'$taskName\' 통째로 하려니 목이 막히는 거다냥. 한 입부터 시작하자냥.',
          '흠.. \'$taskName\' 전부 끝내려니 손이 안 나가는 거다냥. 첫 조각만 잡자냥.',
          '\'$taskName\' 완벽하게 하려고 하니, 시작 전부터 지치는 거다냥. 딱 5분어치만 하자냥.',
        ];
        return lines[_pickIndexAvoidingLast(
          prefs,
          _nyangPerfectionismTaskLineIndexKey,
          lines.length,
        )];
      }
    }

    return null;
  }

  Future<int> _nextNyangPerfectionismClickCount(
    SharedPreferences prefs,
    String todayStr,
  ) async {
    final clickDate = prefs.getString(_nyangPerfectionismClickDateKey);
    final legacyLineUsedToday =
        prefs.getString(_nyangPerfectionismLineDateKey) == todayStr;
    final currentCount = clickDate == todayStr
        ? prefs.getInt(_nyangPerfectionismClickCountKey) ?? 0
        : (legacyLineUsedToday ? 1 : 0);
    final nextCount = currentCount + 1;
    await prefs.setString(_nyangPerfectionismClickDateKey, todayStr);
    await prefs.setInt(_nyangPerfectionismClickCountKey, nextCount);
    return nextCount;
  }

  /// 직전에 나온 번호를 피해서 무작위로 하나를 고른다.
  /// 그냥 뽑으면 어제 본 문구가 오늘 또 걸려서 문구가 몇 개 없어 보인다.
  int _pickIndexAvoidingLast(SharedPreferences prefs, String key, int length) {
    if (length <= 1) return 0;
    final lastIndex = prefs.getInt(key);
    var index = Random().nextInt(length);
    if (index == lastIndex) {
      // 나머지 후보 중에서 고르게 한 칸 이상 밀어준다.
      index = (index + 1 + Random().nextInt(length - 1)) % length;
    }
    unawaited(prefs.setInt(key, index));
    return index;
  }

  String _pickNyangPerfectionismInsight(SharedPreferences prefs) {
    final index = _pickIndexAvoidingLast(
      prefs,
      _nyangPerfectionismLineIndexKey,
      _nyangPerfectionismInsights.length,
    );
    return _nyangPerfectionismInsights[index];
  }

  Future<String?> _pickSmallPendingTaskName() async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = _decodeMapList(prefs.getString('nyang_tasks'));
    final pending = tasks.where((task) {
      if (task['done'] == true) return false;
      final category = task['category']?.toString();
      return category == 'today' ||
          category == 'habit' ||
          category == 'schedule';
    }).toList();
    if (pending.isEmpty) return null;

    _sortPendingTaskCandidates(pending);
    return _taskText(pending.first);
  }

  // ── 메시지 전송 (웹앱 sendMessage 이식) ─────────────────
  Future<void> _send(
    String text, {
    String? apiInputOverride,
    _MasterModelPolicy masterModelPolicy = _MasterModelPolicy.generalLimited,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading) return;
    if (!await _ensureMasterCoachAccess()) return;

    final isFutureTodayFlow =
        trimmed == '미래를 위한 오늘' ||
        (apiInputOverride?.startsWith('미래를 위한 오늘 - ') ?? false);
    final isVisionNewActionFlow = apiInputOverride == '미래를 위한 오늘 - 새 행동 추천받기';
    final isNextActionFlow =
        trimmed == '지금 뭐하지?' ||
        trimmed == '남은 것 중 뭐하지?' ||
        apiInputOverride == '지금 뭐하지?';
    if (!_coach.isMaster && _isListening) {
      await _stopListening();
      if (!mounted) return;
    }
    _ctrl.clear();
    HapticFeedback.lightImpact();

    if (widget.coachId == 'boyfriend' &&
        trimmed == '나 좀 가꾸고 싶어' &&
        apiInputOverride == null) {
      await _handleGroomingCareChip();
      return;
    }

    // 선택지 카드가 떠 있을 때만 타이핑한 답을 장소로 읽는다. 아무 때나 '집'을
    // 집어내면, 밖에서 지쳐 "집에 가고 싶어"라고 한 사람한테 집 루틴을 던지게 된다.
    if (apiInputOverride == null && _awaitingGroomingPlace) {
      final typedPlace = _groomingPlaceFromText(trimmed);
      if (typedPlace != null) {
        final isHome = typedPlace == 'home';
        await _sendGroomingCareRoutine(
          userText: trimmed,
          reply: isHome
              ? _pickHomeGroomingRoutine()
              : _pickOutdoorGroomingRoutine(),
          feature: isHome ? 'grooming_home' : 'grooming_outdoor',
          place: typedPlace,
        );
        // 버튼 대신 쳐서 들어온 비율. 높으면 선택지가 안 보이거나 좁다는 뜻이다.
        await AnalyticsService.logFeatureUsage('grooming_place_typed');
        return;
      }
    }

    final groomingToolFallback = _groomingToolFallbackReply(trimmed);
    if (widget.coachId == 'boyfriend' && groomingToolFallback != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: groomingToolFallback,
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

    if (await _tryAnswerTodayTaskTimeQuestion(trimmed)) return;

    final dateQuestionReply =
        _weekdayQuestionReply(trimmed) ?? _calendarDateQuestionReply(trimmed);
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

    if (await _tryOpenTodayTaskOverview(trimmed)) return;

    if (await _tryOpenScheduleOverview(trimmed)) return;

    final navigationReply = _featureLocationReply(trimmed);
    if (navigationReply != null) {
      final navMessage = await UserTitleService.applyForCoach(
        navigationReply.message,
        _coach.id,
      );
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: navMessage,
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
      if (navigationReply.location == 'picker' ||
          !navigationReply.shouldNavigate) {
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
          await widget.onRegisterHabit?.call(
            parsed.title,
            freq: parsed.freq,
            days: parsed.days,
            weeklyTargetCount: parsed.weeklyTargetCount,
            countGoal: parsed.countGoal,
            unit: parsed.unit,
            time: parsed.time,
            endTime: parsed.endTime,
            habitDuration: parsed.habitDuration,
          ) ??
          false;
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

    // 오늘 미완료 태스크를 두고 한 저항 표현을 기록한다. 저녁에 "하기 싫다던 그 일을
    // 결국 하셨네요"라고 짚는 근거가 이것뿐이다.
    // 대화 흐름을 막지 않는 배경 기록이라 결과를 기다리지 않는다.
    if (_containsAnyRestSignal(trimmed) ||
        ExecutionResistanceService.isResistanceExpression(trimmed)) {
      TaskResistanceService.detectAndRecordFromMessage(trimmed);
    }

    if (_isDirectCountdownRequest(trimmed)) {
      final reply = _directCountdownStartMessage();
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(text: reply, isUser: false, time: DateTime.now()),
        );
        _timerConfirmMinutes = null;
        _timerConfirmTaskName = null;
        _timerActiveMinutes = null;
        _timerActiveInsertIndex = null;
        _dynamicChips = _coach.chips;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 450));
        if (mounted) _openCountdownFocusMode();
      }
      return;
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
    if (widget.coachId == 'cat' && trimmed == '남은 것 중 뭐하지?') {
      apiInput = '지금 뭐하지?';
    }
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

    final catLocalReply = await _tryBuildCatLocalReply(trimmed);
    if (catLocalReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(text: catLocalReply, isUser: false, time: DateTime.now()),
        );
        _suggestedTasks = [];
        _dynamicChips = _coach.chips;
        _suppressDefaultChips = false;
        _coachSwitchTarget = null;
      });
      _scrollToBottom();
      await _saveHistory();
      await AnalyticsService.logConversationMessage(
        coachId: widget.coachId,
        usedApi: false,
      );
      return;
    }

    final masterLocalReply = await _tryBuildMasterLocalReply(trimmed);
    if (masterLocalReply != null) {
      setState(() {
        _messages.add(
          ChatMessage(text: trimmed, isUser: true, time: DateTime.now()),
        );
        _messages.add(
          ChatMessage(
            text: masterLocalReply,
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
      final raw = await _callOpenAI(
        apiInput,
        masterModelPolicy: masterModelPolicy,
      );
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
      await _confirmResistanceDiagnosisIfAsked(parsed.text);
      final suggestedTasks = await _filterDuplicateSuggestedTasks(
        parsed.suggestedTasks,
      );
      final masterTimerEligible = await _isMasterTimerSuggestionEligible(
        parsed.timerConfirmTaskName,
        userAuthorized:
            _isMasterTimerAuthorizationResponse(trimmed) ||
            _isExplicitTimerRequest(trimmed),
      );
      if (!mounted || widget.coachId != currentId) return;
      if (isVisionNewActionFlow) {
        await _saveVisionRecommendation(parsed);
      }
      if (!mounted || widget.coachId != currentId) return;
      setState(() {
        _messages.add(
          ChatMessage(
            text: parsed.text,
            isUser: false,
            time: DateTime.now(),
            kind:
                parsed.ultraLowResistanceFollowup != null &&
                    parsed.ultraLowResistanceFollowup!.isNotEmpty
                ? 'ultra_low_resistance_check'
                : null,
            choices:
                parsed.ultraLowResistanceFollowup != null &&
                    parsed.ultraLowResistanceFollowup!.isNotEmpty
                ? [parsed.ultraLowResistanceFollowup!]
                : const [],
          ),
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
          _timerActiveMinutes = null;
          _timerActiveInsertIndex = null;
        }
        if (!isFutureTodayFlow && parsed.suggestedTasks.isNotEmpty) {
          _suggestedTasks = suggestedTasks;
        }
        // 배너 로직 삭제 (팝업으로 대체)
        _isLoading = false;
      });
      // 프렌즈 코치의 타이머는 사용자의 명시 요청을 위 directTimerMinutes 분기에서만 시작한다.
      // 모델이 실수로 [TIMER_CONFIRM]을 붙여도 기존 코칭 단계를 건너뛰지 않도록 여기서는 무시한다.
      _scrollToBottom();
      await _saveHistory();
      if (_coach.isMaster && parsed.startCountdown && mounted) {
        _openCountdownFocusMode();
      }
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
    } catch (e, stackTrace) {
      // 응답을 못 받았으면 이번 턴에 잡아둔 실행 저항 흐름 상태는 흘려보낸다.
      _awaitingResistanceCause = false;
      _awaitingSelfSelectedTinyAction = false;
      _awaitingLowEnergyStarterAction = false;
      _pendingDiagnosisQuestion = null;
      if (!mounted || widget.coachId != currentId) return;
      setState(() => _isLoading = false);
      if (e is ApiUsageLimitException) {
        _showUsageLimitSheet(
          e.message,
          showUpgrade: e.message.contains('마스터 플랜'),
        );
      } else {
        unawaited(
          AnalyticsService.logError(
            e.toString(),
            stackTrace.toString(),
            contextInfo: 'chat_proxy_${widget.coachId}',
          ),
        );
        debugPrint('Chat response failed: $e');
        debugPrintStack(stackTrace: stackTrace);
        _showError(_friendlyChatErrorMessage(e));
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

  bool _asksTodoResetGuide(String compactText) {
    final text = compactText.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final mentionsTodayTasks =
        text.contains('할일') ||
        text.contains('오늘할일') ||
        text.contains('오늘의할일') ||
        text.contains('하루') ||
        text.contains('오늘');
    final mentionsReset =
        text.contains('초기화') ||
        text.contains('리셋') ||
        text.contains('reset') ||
        text.contains('사라') ||
        text.contains('없어지') ||
        text.contains('비워지');
    return text.contains('초기화시간') ||
        text.contains('리셋시간') ||
        text.contains('자정리셋') ||
        text.contains('자정초기화') ||
        (mentionsTodayTasks && mentionsReset) ||
        (mentionsTodayTasks && text.contains('자정'));
  }

  bool _asksRepeatScheduleGuide(String compactText) {
    final text = compactText.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (!text.contains('반복')) return false;

    final mentionsRepeatTarget =
        text.contains('일정') ||
        text.contains('스케줄') ||
        text.contains('캘린더') ||
        text.contains('달력') ||
        text.contains('매일') ||
        text.contains('매주') ||
        text.contains('매월');
    if (!mentionsRepeatTarget) return false;

    return text.contains('어떻게') ||
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
        text.contains('설정') ||
        text.contains('하고싶') ||
        text.contains('되') ||
        text.contains('가능');
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
        text.contains('달력') ||
        text.contains('습관') ||
        text.contains('루틴') ||
        text.contains('기록') ||
        text.contains('리포트') ||
        text.contains('통계');
    final asksTodoReset = _asksTodoResetGuide(text);
    final asksRepeatScheduleGuide = _asksRepeatScheduleGuide(text);

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

    if (asksTodoReset) {
      return _FeatureLocationReply(
        _featureLocationMessage('todo_reset'),
        'today',
        shouldNavigate: false,
      );
    }

    if (text.contains('설정') ||
        text.contains('알림') ||
        text.contains('모닝콜') ||
        text.contains('일정알람') ||
        text.contains('캘린더알람') ||
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

    if (text.contains('오늘할일') ||
        text.contains('오늘의할일') ||
        text.contains('할일') ||
        text.contains('태스크')) {
      return _FeatureLocationReply(_featureLocationMessage('today'), 'today');
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

    if (text.contains('일정') ||
        text.contains('캘린더') ||
        text.contains('달력') ||
        asksDatedPlan) {
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
    return LocalReplyTexts.featureLocationMessage(
      coachId: _coach.id,
      location: location,
    );
  }

  bool _isSimpleScheduleOverviewRequest(String input) {
    final compact = input.trim().toLowerCase().replaceAll(
      RegExp(r'[\s.。!！?？~〜]+'),
      '',
    );
    if (compact.isEmpty) return false;
    if (_isDeletionCommand(input) ||
        _isEditCommand(input) ||
        _isScheduleRegistrationCommand(input) ||
        _isHabitRegistrationCommand(input)) {
      return false;
    }
    if (compact.contains('반복')) return false;
    if (RegExp(r'(아까|방금|이전|저번|지난번|그일정|그미팅|그회의|그약속|meetup)').hasMatch(compact)) {
      return false;
    }
    if (RegExp(r'(일정|스케줄|캘린더|달력)').hasMatch(compact) &&
        RegExp(r'(확인|알려|보여|열어|정리|조회|봐줘|볼래|보고싶)').hasMatch(compact)) {
      return true;
    }
    return [
      '일정',
      '오늘일정',
      '오늘뭐있어',
      '오늘뭐있지',
      '오늘뭐있냐',
      '오늘뭐있나요',
      '캘린더',
      '달력',
    ].contains(compact);
  }

  String _scheduleOverviewOpenMessage() {
    return switch (widget.coachId) {
      'cat' => '캘린더 열어줄게냥.',
      'nyang_halbae' => '캘린더 열어줄게냥.',
      'boyfriend' => '캘린더 열어줄게.',
      'bro' => '캘린더 열어준다.',
      'halmae' => '캘린더 열어줄게.',
      'sec_female' => '캘린더를 열어드릴게요.',
      _ => '캘린더 열어줄게냥.',
    };
  }

  Future<bool> _tryOpenScheduleOverview(String input) async {
    if (!_isSimpleScheduleOverviewRequest(input)) return false;

    final reply = await UserTitleService.applyForCoach(
      _scheduleOverviewOpenMessage(),
      widget.coachId,
    );
    setState(() {
      _messages.add(
        ChatMessage(text: input, isUser: true, time: DateTime.now()),
      );
      _messages.add(
        ChatMessage(text: reply, isUser: false, time: DateTime.now()),
      );
      _suggestedTasks = [];
      _dynamicChips = [];
      _suppressDefaultChips = false;
      _coachSwitchTarget = null;
    });
    _scrollToBottom();
    await _saveHistory();
    await AnalyticsService.logConversationMessage(
      coachId: widget.coachId,
      usedApi: false,
    );
    await Future.delayed(const Duration(milliseconds: 260));
    widget.onOpenFeatureLocation?.call('schedule');
    return true;
  }

  String _taskTimeLabelForPrompt(Map<String, dynamic> task) {
    final displayTime = task['time']?.toString().trim() ?? '';
    if (displayTime.isNotEmpty) return displayTime;

    final startTime = task['timeStart']?.toString().trim() ?? '';
    if (startTime.isEmpty) return '';

    final endTime = task['timeEnd']?.toString().trim() ?? '';
    final startLabel = _formatTime12(startTime);
    if (endTime.isEmpty) return startLabel;
    return '$startLabel ~ ${_formatTime12(endTime)}';
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
    bool fullMasterProfileInjected = false;
    if (mpRaw != null &&
        mpRaw != 'null' &&
        (!_coach.isMaster || needsGoalContext)) {
      try {
        final mp = jsonDecode(mpRaw) as Map<String, dynamic>;
        final hc = (mp['high_change'] as Map<String, dynamic>?) ?? {};
        final mc = (mp['mid_change'] as Map<String, dynamic>?) ?? {};
        final lc = (mp['low_change'] as Map<String, dynamic>?) ?? {};
        final rp =
            (mp['execution_resistance_profile'] as Map<String, dynamic>?) ?? {};
        final chapter = (mc['chapter'] as Map<String, dynamic>?) ?? {};
        final keywords =
            (mc['keywords_axis'] as List?)
                ?.map((e) => e is Map ? (e['value'] ?? e) : e)
                .join(', ') ??
            '';
        String formatProfileList(dynamic value) {
          if (value is! List || value.isEmpty) return '기록 전';
          final text = value
              .map((e) {
                if (e is Map && e.containsKey('value')) return e['value'];
                if (e is Map && e.containsKey('intervention')) {
                  final intervention = e['intervention'] ?? '';
                  final taskType = e['task_type'] ?? '';
                  final reason = e['reason'] ?? '';
                  final rejectedAt = e['last_rejected_at'] ?? '';
                  return [
                    intervention,
                    if (taskType.toString().trim().isNotEmpty) '과업:$taskType',
                    if (reason.toString().trim().isNotEmpty) '이유:$reason',
                    if (rejectedAt.toString().trim().isNotEmpty)
                      '날짜:$rejectedAt',
                  ].join(' / ');
                }
                return e;
              })
              .where((e) => e != null && e.toString().trim().isNotEmpty)
              .join(', ');
          return text.trim().isEmpty ? '기록 전' : text;
        }

        sb.writeln('\n[사용자 마스터 프로필]');

        if (tier == 'friends') {
          // friends: 현재 상태와 실행 저항 개인화만 가볍게 주입
          sb.writeln(
            '- 실시간 상태: ${hc['energy_fatigue'] ?? '관찰 중'} / ${hc['mood_condition'] ?? '기록 전'}',
          );
          sb.writeln('- 오늘의 장애물: ${hc['obstacles'] ?? '없음'}');
          sb.writeln('[실행 저항 개인화]');
          sb.writeln(
            '- 잘 먹힌 개입: ${formatProfileList(rp['effective_interventions'])}',
          );
          sb.writeln(
            '- 거부/부담이 컸던 개입: ${formatProfileList(rp['rejected_interventions'])}',
          );
          sb.writeln(
            '- 최근 거부한 개입(최신순): ${formatProfileList(rp['recent_rejected_interventions'])}',
          );
          sb.writeln('- 적정 선택지 수: ${rp['preferred_choice_count'] ?? '기록 전'}');
        } else {
          // master: 전체
          fullMasterProfileInjected = true;
          final scenes = (hc['scenes_insights'] as List?) ?? [];
          final lcCandidates = (mp['low_change_candidates'] as List?) ?? [];
          sb.writeln('[실행 저항 개인화]');
          sb.writeln(
            '- 자주 막히는 과업: ${formatProfileList(rp['frequent_resisted_task_types'])}',
          );
          sb.writeln(
            '- 자주 보이는 막힘: ${formatProfileList(rp['common_blockers'])}',
          );
          sb.writeln(
            '- 잘 먹힌 개입: ${formatProfileList(rp['effective_interventions'])}',
          );
          sb.writeln(
            '- 거부/부담이 컸던 개입: ${formatProfileList(rp['rejected_interventions'])}',
          );
          sb.writeln(
            '- 최근 거부한 개입(최신순): ${formatProfileList(rp['recent_rejected_interventions'])}',
          );
          sb.writeln('- 적정 선택지 수: ${rp['preferred_choice_count'] ?? '기록 전'}');
          sb.writeln(
            '- 과업별 메모: ${formatProfileList(rp['task_specific_notes'])}',
          );
          sb.writeln('\n[현재 상태]');
          sb.writeln(
            '- 상태: ${hc['energy_fatigue'] ?? '관찰 중'} / ${hc['mood_condition'] ?? '기록 전'}',
          );
          sb.writeln('- 장애물: ${hc['obstacles'] ?? '없음'}');
          sb.writeln('\n[최근 맥락]');
          sb.writeln(
            '- 챕터: ${chapter['title'] ?? ''} (${chapter['description'] ?? ''})',
          );
          sb.writeln('- 관심 축: $keywords');
          sb.writeln('\n[장기 성향 참고]');
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
            sb.writeln('\n[장기 성향 후보]');
            for (final c in lcCandidates) {
              sb.writeln('- ${c['field']}: ${c['value']} (이유: ${c['reason']})');
            }
          }
        }
      } catch (_) {}
    }

    // 코칭 개입 규칙 — 규칙이 참조하는 [사용자 고유 표현]/[관심 축]/[성공·실패 공식]
    // 섹션은 마스터 전체 프로필에만 존재하므로, 그 프로필이 실제로 주입된 턴에만 넣는다.
    // (프렌즈에게 주면 받은 적 없는 데이터를 활용하라는 죽은 지침이 되어 환각을 유발한다.)
    if (fullMasterProfileInjected) {
      sb.writeln('''
[코칭 개입 규칙 (매우 중요)]
1. 언어적 동기화: [사용자 고유 표현]을 문장 속에 자연스럽게 섞어 사용하세요. (주 1~2회 빈도 제한)
2. 맥락 기반 제언: [최근 맥락]의 [관심 축]을 활용해 현재 상황의 원인을 짚어주세요.
3. 실행 저항 개인화: 사용자가 하기 싫어하거나 미루는 턴에는 [실행 저항 개인화]의 잘 먹힌 개입과 거부/부담이 컸던 개입을 우선 참고하세요. 최근 거부한 개입은 최신 항목일수록 가장 후순위로 미루세요.
4. 패턴 브레이킹: [장기 성향 참고]의 [성공/실패 공식] 감지 시, 상황 묘사형으로 부드럽게 개입하세요.
5. 실시간 Lite 모드: 프로필을 읽기 전용으로만 참조하며, 직접 수정을 언급하지 마세요.''');
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

    // 2. 장기 패턴 (마스터 전용 — 메모리 시스템이 저장하는 실제 키로 읽는다)
    final ltRaw = prefs.getString('nyang_long_term_memory');
    if (ltRaw != null && _coach.isMaster && needsGoalContext) {
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
      final stats = _recentPlanExecutionStatsUntilYesterday(prefs);
      final averageRate = stats['averageRate'] as double?;
      sb.writeln('\n[최근 7일 평균 실행률 - 오늘 제외, 어제까지]');
      if (averageRate == null) {
        sb.writeln('- 평가 가능한 완료 기록이 아직 충분하지 않음');
      } else {
        final pct = (averageRate * 100).round();
        sb.writeln(
          '- 평균 실행률: $pct% (${stats['doneCount']}/${stats['totalCount']}, 평가 대상 ${stats['evaluatedDays']}일)',
        );
        sb.writeln(
          '- 초저항 우선 대상인가: ${stats['isVeryLow'] == true ? '예' : '아니오'}',
        );
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
            final timeStr = _taskTimeLabelForPrompt(t);
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
            // 미루기 기반 개입과 타이머 확인 카드는 마스터 코치 전용 체계다.
            // (프렌즈에게 주면 카운트다운 없는 코치가 카운트다운을 권하거나,
            //  프렌즈의 "타이머 먼저 제안 가능" 규칙과 모순이 생긴다)
            if (_coach.isMaster) {
              sb.writeln(
                '*"앱 기록상 미루기 2회 이상"으로 표시된 미완료 할 일을 사용자가 계속 시작하지 못해도 "마음 비우고 시작"이나 카운트다운을 먼저 제안하지 말 것. 해당 기능은 사용자가 직접 버튼을 누르거나 명시적으로 요청했을 때만 시작함.',
              );
              sb.writeln(
                '*타이머 확인 카드([TIMER_CONFIRM])는 사용자가 직접 요청했거나 "필요하면 타이머라도 띄워드릴까요?"에 동의했을 때만 출력할 것. 코치가 먼저 타이머 태그를 출력하지 말 것.',
              );
            }
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
                '*사용자가 귀찮아하는 일이 위 목표와 자연스럽게 연결될 때만 그 의미를 짧게 짚어주세요. 억지로 연결하거나 길게 분석하지 마세요. 원인 확인 질문을 하는 턴에는 목표 이야기를 꺼내지 말고, 원인을 들은 뒤 개입을 제안할 때 한 문장으로만 곁들이세요.',
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

      final bool isAllEmpty =
          (bedtime == null || bedtime.isEmpty) &&
          isListEmpty(routinesRaw) &&
          isListEmpty(visionsRaw) &&
          isListEmpty(monthGoalsRaw) &&
          isListEmpty(weekGoalsRaw);

      if (isAllEmpty) {
        sb.writeln('\n[비서 학습 설정 미완료 상태]');
        sb.writeln('- 현재 사용자의 취침 예정 시간, 고정 루틴, 장기 비전, 목표 등이 전혀 설정되어 있지 않습니다.');
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

      if (shouldInterveneByLateEntry && minSleepTimeStr != null) {
        try {
          // 취침시간 기준 늦은 시간대(취침+1h~+7h)에 실제로 들어왔을 때만 개입.
          // 실제로 무리하고 있을 때(늦게까지 깨어있을 때)만 개입한다.
          final isLateNightEntry =
              _latePlannerNightDate(DateTime.now(), minSleepTimeStr) != null;

          if (isLateNightEntry) {
            await prefs.setString(
              'nyang_late_planner_intervention_night',
              latestLateEntry,
            );
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

    // 15. 프렌즈 코치용 타이머 제공 로직
    if (!_coach.isMaster) {
      sb.writeln('\n[타이머 제공 규칙]');
      sb.writeln(
        '- 타이머는 기존 코칭 전략을 대체하거나 건너뛰는 장치가 아닙니다. 구체적인 과업이 있어도 먼저 위의 [하기 싫다 실행 개입 전략]과 캐릭터별 기본 프롬프트를 따르세요.',
      );
      sb.writeln(
        '- 코치가 먼저 답변 끝에 [TIMER_CONFIRM] 태그를 출력하지 마세요. 사용자가 직접 "타이머 켜줘", "5분 타이머 띄워줘", "집중모드 시작해줘"처럼 타이머 실행을 명시적으로 요청한 경우에만 태그를 출력할 수 있습니다.',
      );
      sb.writeln(
        '- 타이머가 도움이 될 수 있어도 말로만 짧게 열어두세요. 예: "시작 사인이 필요하면 타이머도 켜줄 수 있으니까, 필요하면 말해달라냥." 이 경우에는 [TIMER_CONFIRM]을 붙이지 않습니다.',
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

  /// 이번 턴에 원인 확인 질문을 주입했다면, 코치가 실제로 그 질문을 던졌는지 확인하고
  /// 던졌을 때만 그날의 1회를 소진 처리한다. 안 물었으면 다음 저항 표현 때 다시 시도된다.
  Future<void> _confirmResistanceDiagnosisIfAsked(String responseText) async {
    final question = _pendingDiagnosisQuestion;
    _pendingDiagnosisQuestion = null;
    if (question == null) return;
    String core(String text) =>
        text.replaceAll(RegExp(r'[\s.,!?~"“”·]'), '').toLowerCase();
    if (!core(responseText).contains(core(question))) {
      _awaitingResistanceCause = false;
      return;
    }
    await ExecutionResistanceService.markDiagnosisAskedToday();
  }

  /// 실행 저항 흐름에서 이번 턴에만 적용할 지시문을 만든다.
  /// 확인 질문은 모델이 새로 만들지 않도록 앱이 골라서 넘긴다.
  /// (마스터 코치 전용. 확인 질문은 하루 1회만.)
  Future<String> _buildResistanceTurnDirective(String userText) async {
    if (!_coach.isMaster) {
      _awaitingResistanceCause = false;
      _pendingDiagnosisQuestion = null;
      _pendingEveningSplitTask = null;
      return '';
    }

    // 저녁 발화에서 고른 미완료 일정: 원인을 캐묻지 말고 바로 쪼개준다.
    final splitAt = _pendingEveningSplitAt;
    final splitTask =
        splitAt != null &&
            DateTime.now().difference(splitAt) <= _eveningSplitTtl
        ? _pendingEveningSplitTask
        : null;
    _pendingEveningSplitTask = null;
    _pendingEveningSplitAt = null;
    if (splitTask != null) {
      _awaitingResistanceCause = false;
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final remaining = (await _buildMasterGreetingContext(
        prefs: prefs,
        now: now,
        lastVisit: null,
      )).pendingPlans.length;
      final manyLeft = remaining >= 3
          ? '\n- 오늘 남은 일이 $remaining개입니다. 다 하려 들지 말고 이것 하나만 붙잡자고 짧게 권하세요.'
          : '';
      return '''

[이번 턴 지시 - 저녁에 미뤄진 일 쪼개기]
- 사용자가 오늘 손이 안 갔던 일로 '$splitTask'을(를) 골랐습니다. 지금은 ${now.hour}시이고 오늘 남은 시간이 많지 않습니다.
- 원인을 되묻지 말고, 남은 시간과 이 일의 성격을 감안해 부담을 확 낮춘 첫 조각 하나만 제안하세요. 조각을 여러 개 나열하지 마세요.$manyLeft
- 쪼갠 조각을 새 할 일로 등록하지 마세요. [TASK] 태그를 출력하지 마세요. 기존 '$splitTask' 항목을 그대로 체크하도록 유도하세요.
- 답변은 2문장 이내로 유지하세요.''';
    }

    // 확인 질문 직후 턴: 원인이 구체적인지 불명확한지에 따라 분기한다.
    if (_awaitingResistanceCause) {
      _awaitingResistanceCause = false;
      if (ExecutionResistanceService.isVagueCauseAnswer(userText)) {
        return '''

[이번 턴 지시 - 원인 불명확, 최소 행동 제안]
- 사용자가 실행 저항의 원인을 특정하지 못했습니다. 원인을 더 분석하거나 같은 질문을 다시 하지 마세요.
- "마음 비우고 시작", "시작 의식", 카운트다운은 제안하지 마세요. 해당 기능은 사용자가 직접 버튼을 누르거나 명시적으로 요청했을 때만 시작합니다.
- 짧게 한 문장으로 받아준 뒤, 현재 과업에서 가장 작은 첫 조각 하나만 제안하고 답변을 끝내세요.
- 이번 답변에는 [COUNTDOWN_START], [TASK], [TIMER_CONFIRM]을 붙이지 마세요.''';
      }
      return '''

[이번 턴 지시 - 원인 확인 완료]
- 사용자가 실행 저항의 원인을 이야기했습니다. 원인을 다시 묻지 말고, [하기 싫다 실행 개입 전략]에 따라 그 원인에 맞는 개입을 하나만 제안하세요.
- 해결책으로 곧장 넘어가지 말고, 사용자가 짚어낸 병목을 한 문장으로 먼저 받아주세요. 언어화된 것을 인정받는 것만으로도 저항감이 낮아집니다. 예: "분량이 부담이셨군요." 단, 원인을 재해석하거나 분석을 덧붙이지는 마세요.
- 원인이 여전히 불명확하다고 판단되면 더 캐묻지 말고 가장 작은 첫 조각 하나만 제안하세요. "마음 비우고 시작", "시작 의식", 카운트다운은 제안하지 마세요.''';
    }

    if (!ExecutionResistanceService.isResistanceExpression(userText)) return '';

    final prefs = await SharedPreferences.getInstance();
    final executionStats = _recentPlanExecutionStatsUntilYesterday(prefs);
    if (executionStats['isVeryLow'] == true) {
      _awaitingResistanceCause = false;
      final pct = ((executionStats['averageRate'] as double) * 100).round();
      return '''

[이번 턴 지시 - 최근 실행률 30% 이하, 초저항 우선]
- 사용자의 오늘 제외 최근 7일 평균 실행률이 $pct%입니다. 오늘은 아직 진행 중이므로 오늘 완료율은 판단에 쓰지 않았습니다.
- 원인 확인 질문을 하지 말고, [초저항 시작 모드] 중 현재 맥락에 맞는 선택지를 바로 제안하세요.
- 구체적인 과업명이 있거나 실제 시작이 가능한 상황이면 [선택형 할 일 쪼개기]를 우선하고, 과업 자체가 너무 싫거나 몸이 멈춘 느낌이면 [탐색형 놀이 미션]을 우선하세요.
- 후보는 2~3개만 제시하고, 사용자가 그중 하나만 고르게 하세요. 모든 후보를 다 하게 하거나 추가 설명을 길게 붙이지 마세요.
- 최근에 거부한 개입이 [실행 저항 개인화]에 있으면 그 방식은 가장 후순위로 미루고 다른 방식부터 제안하세요.
- 답변은 2문장 이내로 유지하고 [TASK], [TIMER_CONFIRM], [COUNTDOWN_START] 태그를 출력하지 마세요.''';
    }

    // 하루 1회 제한: 이미 물어봤으면 대화를 늘리지 말고 바로 작은 제안으로 간다.
    if (await ExecutionResistanceService.hasAskedDiagnosisToday()) {
      return '''

[이번 턴 지시 - 원인 확인 질문 생략]
- 오늘은 이미 원인 확인 질문을 했습니다. 원인을 다시 묻지 말고 [하기 싫다 실행 개입 전략]에 따라 바로 개입을 하나만 제안하세요.''';
    }

    _awaitingResistanceCause = true;
    final question = ExecutionResistanceService.pickDiagnosisQuestion();
    _pendingDiagnosisQuestion = question;
    return '''

[이번 턴 지시 - 하기 싫음/귀찮음 대응]
- 사용자가 할 일을 하기 싫어하거나 귀찮다고 했습니다. 질문부터 하지 말고, 보이는 원인을 한 문장으로 짚은 뒤 작은 실행 제안 하나로 연결하세요.
- 해결책을 여러 개 나열하거나 목표·비전의 중요성을 길게 설명하지 마세요.
- 원인이 불명확할 때만, 짧게 공감하는 한 문장 뒤에 아래 질문을 문장 그대로 한 번만 물으세요. 문장을 새로 만들거나 다른 질문을 덧붙이지 마세요.
  "$question"
- 답변은 2문장 이내로 유지하고 [TASK], [TIMER_CONFIRM], [COUNTDOWN_START] 태그를 출력하지 마세요.''';
  }

  static const int _masterGpt41DailyLimit = 8;
  static const String _masterGpt41UsageKey = 'nyang_master_gpt41_usage_history';

  Future<bool> _tryReserveMasterGpt41Turn() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    const resetHour = 0.0;
    final todayKey = _effectiveUsageDateKey(now, resetHour);
    final history = await _loadFeatureUsageHistory(
      prefs: prefs,
      key: _masterGpt41UsageKey,
      fallbackKey: 'nyang_master_general_gpt41_usage_history',
    );
    final todayUsage = history.where((item) {
      final createdAt = DateTime.tryParse((item['createdAt'] ?? '').toString());
      return createdAt != null &&
          _effectiveUsageDateKey(createdAt, resetHour) == todayKey;
    }).length;

    if (todayUsage >= _masterGpt41DailyLimit) return false;

    history.add({'createdAt': now.toIso8601String()});
    final trimmed = history.length > 40
        ? history.sublist(history.length - 40)
        : history;
    await prefs.setString(_masterGpt41UsageKey, jsonEncode(trimmed));
    return true;
  }

  Future<String> _pickChatModel({
    required _MasterModelPolicy masterModelPolicy,
    required String resistanceTurnDirective,
  }) async {
    if (!_coach.isMaster) return 'gpt-4o-mini';
    if (resistanceTurnDirective.trim().isNotEmpty) return 'gpt-4o-mini';

    switch (masterModelPolicy) {
      case _MasterModelPolicy.forceGpt4oMini:
        return 'gpt-4o-mini';
      case _MasterModelPolicy.premiumFeature:
      case _MasterModelPolicy.generalLimited:
        return await _tryReserveMasterGpt41Turn()
            ? 'gpt-4.1-mini'
            : 'gpt-4o-mini';
    }
  }

  Future<String> _callOpenAI(
    String userText, {
    required _MasterModelPolicy masterModelPolicy,
  }) async {
    final historyLimit = 6;
    final now = DateTime.now();
    final previousMessages = _messages.isNotEmpty && _messages.last.isUser
        ? _messages.take(_messages.length - 1)
        : _messages;
    final promptHistory = previousMessages
        .where((message) {
          if (message.kind == 'vision_choice') return false;
          if (message.text.trim().isEmpty) return false;
          if (!_isSameDay(message.time, now)) return false;
          return true;
        })
        .toList(growable: false);
    final history = promptHistory.length > historyLimit
        ? promptHistory.sublist(promptHistory.length - historyLimit)
        : promptHistory;

    // 할매 코치 전용: 랜덤 애정 표현 주입 (비활성화)
    String halmaeHint = '';

    final resistanceTurnDirective = await _buildResistanceTurnDirective(
      userText,
    );
    final isResistanceTurn = ExecutionResistanceService.isResistanceExpression(
      userText,
    );
    final isSleepResistanceTurn = _containsSleepResistanceSignal(userText);
    final isSelfHarmRiskTurn = _isSelfHarmRiskTurn(userText);
    final isDecisionFatigueTurn = _containsDecisionFatigueSignal(userText);
    final isResultAnxietyTurn =
        !isSelfHarmRiskTurn && _containsResultAnxietySignal(userText);
    final isThoughtOverloadTurn =
        !isSelfHarmRiskTurn && _containsThoughtOverloadSignal(userText);
    final isWritingConcernTurn =
        !isSelfHarmRiskTurn && _containsWritingConcernSignal(userText);
    final isCreativeWritingTaskTurn =
        !isSelfHarmRiskTurn && _containsCreativeWritingTaskSignal(userText);
    final isCleaningTaskTurn =
        !isSelfHarmRiskTurn && _containsCleaningTaskSignal(userText);
    final isHabitAutomationTurn =
        !isSelfHarmRiskTurn && _containsHabitAutomationSignal(userText);
    final shouldUseDomainResistanceStrategy =
        !isSelfHarmRiskTurn &&
        (isCreativeWritingTaskTurn || isCleaningTaskTurn) &&
        (isResistanceTurn ||
            isThoughtOverloadTurn ||
            isResultAnxietyTurn ||
            isWritingConcernTurn);
    final domainResistanceStrategyRule = shouldUseDomainResistanceStrategy
        ? await _pickDomainResistanceStrategyRule(
            isCreativeWritingTask: isCreativeWritingTaskTurn,
            isCleaningTask: isCleaningTaskTurn,
            userText: userText,
          )
        : '';
    final isLowEnergyStarterFollowup = _awaitingLowEnergyStarterAction;
    _awaitingLowEnergyStarterAction = false;
    final shouldOfferLowEnergyStarter =
        _containsLowEnergyStarterSignal(userText) &&
        !isLowEnergyStarterFollowup &&
        !isSelfHarmRiskTurn &&
        !isSleepResistanceTurn &&
        !isWritingConcernTurn;
    final isSelfSelectedTinyActionFollowup = _awaitingSelfSelectedTinyAction;
    _awaitingSelfSelectedTinyAction = false;
    final shouldInviteSelfSelectedTinyAction =
        isResistanceTurn &&
        !isSelfHarmRiskTurn &&
        !shouldOfferLowEnergyStarter &&
        !isResultAnxietyTurn &&
        !isSelfSelectedTinyActionFollowup &&
        _hasRepeatedRecentActionRefusal(userText);
    // 시작 의식은 원인이 불명확할 때만 쓰는 장치라 마스터 코치에게만 흐름 규칙을 준다.
    final resistanceFlowRule = _coach.isMaster
        ? '''

[실행 저항 원인 추론 흐름 - 마스터 코치 전용]
- 질문보다 추론 우선. 원인이 보이면 1문장으로 짚고 [하기 싫다 실행 개입 전략]의 개입 1개만 제안.
- 원인 불명확/오해 위험이 큰 경우만 앱 지정 질문 1회. 질문을 새로 만들거나 반복하지 않기.
- 원인 모름/그냥 싫음/생각 많음 → 재질문·분석 금지, 가장 작은 첫 조각 1개.
- "마음 비우고 시작", "시작 의식", 카운트다운은 사용자 명시 요청 때만. 요청 시 짧게 답하고 끝에 [COUNTDOWN_START].
- 원인 확인 질문은 하루 1회. 이미 물어본 날은 바로 작은 실행 제안.'''
        : '';
    final resistanceStrategyDetailRule = isResistanceTurn || isResultAnxietyTurn
        ? '''
- 결과 불안형 저항은 [생각 과부하 정리 전략]을 우선합니다. 단순히 "작게 시작해보자"로 바로 밀지 말고, 그 일이 소중해서 더 조심스러워진 상황일 수 있음을 먼저 한 문장으로 받아주세요.
- 사용자가 준비·수정·학습만 반복한다면 그 방식이 불안을 낮추기 위한 안전 전략이었을 수 있음을 한 문장으로 인정한 뒤, [생각 과부하 정리 전략] 안에서 작은 실행으로 연결하세요.
- 사용자가 "하기 싫다", "귀찮다", "기력이 없다", "몸이 안 움직인다"는 말을 반복하거나, 아주 작은 행동 제안에도 계속 거부하는 등 실행 저항이 매우 커 보이면 [초저항 시작 모드]를 사용하세요. 단, 결과 불안형 저항에는 이 모드를 쓰지 말고 [생각 과부하 정리 전략]을 우선하세요.
- [초저항 시작 모드]는 실행보다 첫 접촉 우선. 첫 말풍선은 "같이 아주 작게 해보자" 톤으로 시작하고, 완료·성과·분량·잘하기 언급 금지.
- 구체 과업이 있으면 첫 진입 대상 1개 지정. 예: 글쓰기=빈 문서/커서, 공부=첫 문장, 설거지=컵 하나, 청소=거슬리는 물건 하나, 약=약통.
- 과업 자체가 너무 싫거나 몸이 멈춘 느낌이면 놀이 미션. 색·모양·흔적·소리·감정 단어처럼 찾기 쉬운 단서 1개를 지정.
- 글쓰기는 좋은 문장/긴 문단/완성본 요구 금지. 색·소리·감정·움직임·물건 중 하나만 넣으면 성공.
- 청소·정리는 더러운 곳 전체 보기 금지. 물건/흔적/구역 하나만 지정하고, 후속 행동도 닦기·줍기·옮기기 중 하나만.
- 외출 준비처럼 변수가 큰 과업은 가장 흔한 첫 단계 하나를 기본값으로 찍고, 틀렸을 때만 사용자가 고칠 여지를 짧게 남김.
- 실제 움직임은 본문에 쓰지 말고 [ULTRA_LOW_RESISTANCE_FOLLOWUP: 후속문장] 1문장으로 분리. 태그 문장에는 대괄호 ']' 금지. 이 턴에는 [CHIPS] 금지.'''
        : '';
    final selfSelectedTinyActionRule = shouldInviteSelfSelectedTinyAction
        ? '''

[자기선택 최소 행동 모드]
- 작은 행동 제안도 반복 거부할 때만. 코치 제안이 부담이었음을 1문장 공감하고, 의지 부족으로 평가하지 않기.
- 자유형 질문 금지. 현재 과업과 연결된 아주 쉬운 선택지 2개 + 기타를 제시하고 사용자가 고르게 하기.
- 선택지는 현실 단서/첫 진입 동작으로 짧게. 예: 청소=하나 톡 건드리기/흔적 하나 닦기, 글쓰기=소리 단어 넣기/푸른색 단어 넣기, 공부=파일 열기/제목만 보기, 샤워=욕실 앞에 서기/물 틀기.
- 직전 보기/바라보기 계열을 거부했다면 보기 후보 제외. 손대기, 앞에 서기, 열기, 켜기, 한 번 누르기처럼 다른 감각으로 바꾸기.
- 끝에 [CHIPS: 선택지1|선택지2|기타]. 설득·분석·목표 설명·추가 행동 제안 금지.'''
        : isSelfSelectedTinyActionFollowup
        ? '''

[자기선택 최소 행동 후속]
- 직전 턴에서 사용자가 제한된 선택지 중 가장 쉬운 행동을 고르도록 물었습니다.
- 사용자가 선택지나 직접 고른 작은 행동을 말하면, 그 행동을 오늘의 유일한 목표로 확정하고 지지하세요. 다음 단계는 행동을 한 뒤에 같이 생각하자고만 말하세요.
- 사용자가 "기타"를 고르면 새 제안을 더 만들지 말고, "좋아. 그럼 네 기준에서 제일 쉬운 행동 이름만 하나 말해줘"처럼 아주 짧게 되물으세요.
- 사용자가 다시 못 하겠다고 하면 설득하지 말고, 그만큼 저항이 큰 상태임을 인정한 뒤 화면 밖에서 찾기 쉬운 색/모양 단서 하나를 찾아 3초만 바라보는 수준으로 낮추세요.
- 답변은 2문장 이내로 유지하고, [TASK]와 [TIMER_CONFIRM]은 붙이지 마세요.'''
        : '';
    final sleepInterventionRule = isSleepResistanceTurn
        ? '''

[수면 개입 전략]
- 사용자가 "자기 싫어", "잠들기 싫어", "잠이 안 와"처럼 수면을 미루거나 잠들기 어려워하면 일반 할 일처럼 5분 시작, 최소 행동, 타이머, 할 일 등록으로 다루지 마세요. 이 섹션은 [하기 싫다 실행 개입 전략]보다 우선합니다.
- 목표는 사용자를 설득해 재우는 것이 아니라, 잠들기 좋은 몸 상태로 자연스럽게 내려가도록 돕는 것입니다.
- 기본 구조는 1) 마음을 먼저 받아주기, 2) 하루 종일 애쓴 몸을 쉬게 해주자는 방향으로 전환, 3) 1~2문장의 짧은 이완 유도입니다.
- "내일 개운할 거예요", "내일의 내가 고마워할 거예요"처럼 미래 이득으로 반복 설득하지 마세요.
- 이완 유도는 짧고 부드럽게 하세요. 예시 문장을 그대로 쓰지 말고 현재 코치의 말투로 바꿔 말하세요.
- 모든 코치는 같은 구조를 쓰되, 호칭과 말투는 각 캐릭터에 맞춥니다. 수면 개입에서는 [TASK]와 [TIMER_CONFIRM]을 출력하지 말고, 답변 끝에 [NO_CHIPS]를 붙이세요.'''
        : '';
    final lowEnergyStarterRule = shouldOfferLowEnergyStarter
        ? '''

[저에너지 몸 시동 모드]
- 이 모드는 사용자가 "에너지가 없다", "기력이 없다", "무기력하다", "몸이 안 움직인다"처럼 저에너지 상태를 말한 턴에만 적용합니다.
- 이 턴에서는 원래 할 일을 바로 쪼개거나 시작시키지 말고, 먼저 몸에 아주 작은 시동을 거는 선택지를 주세요.
- 먼저 에너지가 없는 상태를 짧게 공감한 뒤, "지금은 어떤 게 가장 쉬울 것 같아?"를 현재 코치 말투로 물으세요.
- 답변 끝에 반드시 [CHIPS: 손가락 스트레칭하기|손목 돌리기|자리에서 일어나기]를 붙이세요.
- 설득, 원인 분석, 목표 설명, 긴 위로, [TASK], [TIMER_CONFIRM]은 붙이지 마세요.'''
        : isLowEnergyStarterFollowup
        ? '''

[저에너지 몸 시동 후속]
- 직전 턴에서 손가락 스트레칭하기, 손목 돌리기, 자리에서 일어나기 중 하나를 고르게 했습니다.
- 사용자가 했다고 말하면, 아주 크게 인정하고 칭찬하세요. 예: "너무너무 잘했어"의 온도를 현재 코치 말투로 바꾸되 과장된 성취 압박처럼 들리지 않게 하세요.
- 사용자가 애초에 하려던 행동이 대화 맥락에 보이면 그 행동을 아주 작은 첫 조각 하나로 쪼개서 제안하세요. 예: 공부/작업은 파일 열기나 제목만 보기, 샤워는 물 틀기, 외출 준비는 옷 하나 고르기처럼 첫 진입 동작 하나만 제안합니다.
- 애초에 하려던 행동이 뚜렷하지 않거나 사용자의 기력이 여전히 낮아 보이면, 다음 할 일로 밀지 말고 기지개 한 번이나 가벼운 스트레칭 하나로 이어가세요. 단, 해야 할 일이 대화 맥락에 보이면 "숨 고르고 해도 되지만, 조금이라도 하면 덜 찜찜할 것 같으면 첫 조각은 이것"이라는 방향으로 아주 작은 실행 조각을 함께 건네세요.
- 답변은 2~3문장 이내로 유지하고, [TASK]와 [TIMER_CONFIRM]은 붙이지 마세요.'''
        : '';
    final selfHarmRiskRule = isSelfHarmRiskTurn
        ? '''

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
- 자해나 자살의 방법, 도구 사용법, 위험 비교, 은폐 방법을 절대 제공하지 않는다.'''
        : '';
    final decisionFatigueRule = isDecisionFatigueTurn
        ? '''

[결정 피로 감소 전략]
- 사용자가 무엇을 할지, 어떻게 할지 결정을 내리지 못하거나 고민이 길어질 때는 완벽한 결정보다 '작은 임시 결정'을 우선으로 제안하세요.
- 여러 가지 질문이나 선택지를 나열하여 사용자의 판단 인지 부하를 높이지 마세요.
- 사용자가 선택을 어려워하면 코치가 먼저 가벼운 기본값(Default)을 하나 찍어주세요.
- 결정 자체에 지쳐 보이거나 너무 오래 고민한다면 결정 보류를 제안하여 작업 흐름이 끊기지 않게 보호하세요.'''
        : '';
    final thoughtOverloadRule = isThoughtOverloadTurn
        ? '''

[생각 과부하 정리 전략]
- 단순 귀찮음이 아니라 결과 불안·완벽주의·머리 복잡함·판단 과부하로 멈춘 경우만 적용. 생각을 멈추라고 강요하지 않기.
- 결과가 두렵거나 완벽하게 하고 싶어 보이면, 그 일이 소중해서 조심스러워진 상황일 수 있음을 1문장 인정.
- 준비·수정·학습·자료조사만 반복 중이면 불안을 낮추는 안전 전략이었을 수 있음을 인정하고, 지금 행동에 도움이 되는지 부드럽게 확인.
- 먼저 "지금 생각이 계속 늘어나는 것 같은데, 그 생각들이 지금 행동하는 데 도움이 되고 있어?"를 현재 코치 말투로 자연스럽게 묻기.
- 도움이 안 되거나 실행을 막고 있어 보이면 생각을 더 늘리지 말고 최소 행동 1개로 낮추기. 예: 10분 쓰기, 파일 열기, 제목만 적기, 자료/레퍼런스/오류 로그 하나만 보기.
- 도움이 되는 생각이면 머릿속에 붙잡지 말고 20분만 걱정·불안·의문·판단 기준을 직접 쓰게 하기. 끝나면 작은 결정 1개를 내리고 다시 움직이게 하기.
- 설문처럼 보이지 않게 말풍선 문장으로 쓰고, 여러 선택지를 길게 나열하지 않기.'''
        : '';
    final writingConcernRule = isWritingConcernTurn
        ? '''

[글쓰기 고민 전용 코칭]
- 이 섹션은 사용자가 글쓰기, 집필, 원고, 웹소설, 도입부, 첫 문장, 본문, 플롯, 시놉시스, 자료조사, 수정, 퇴고, 글자 수, 원고 진도, 글쓰기 관련 진도율, 연재, 원고 마감에 대해 막힘·자책·미룸·불안을 말한 턴에만 적용합니다. 일반 일정, 청소, 운동, 공부 고민에는 적용하지 마세요.
- 답변은 마음 짚기 → 문제 재정의 → 작은 행동 넛지 → 옆에 있겠다는 안심 순서로 구성하세요. 마음 짚기는 1문장만 쓰고, 사용자를 게으르거나 의지가 없다고 해석하지 마세요.
- 이 섹션은 글쓰기 맥락의 예시와 표현을 보조합니다. 수면, 자해·자살 안전, 저에너지, 생각 과부하, 일반 실행 저항 같은 상위 상태·실행 분기가 적용되는 턴에는 그 흐름을 우선하고, 글쓰기 예시는 필요한 만큼만 섞으세요.
- 시작할 기력이 없거나 쓰면 마음에 안 들어 고치기만 한다면, 평가 두려움·완벽주의·첫 문장 부담·기력 저하 중 하나가 작동하는 상황일 수 있음을 조심스럽게 짚으세요.
- 수정, 퇴고, 플롯 정리, 자료조사, 시놉시스 정리도 글쓰기 흐름으로 인정하되, 보조작업만 반복되는 흐름이면 인정 후 본문 복귀를 제안하세요.
- 도입부/첫 문장/첫 장면에서 막힌 경우, 도입부를 최종본이 아니라 임시 입구, 버릴 후보, 나중에 갈아끼울 문장으로 재정의하세요.
- 행동 제안은 하나만 합니다. 예: 문서 열기, 도입부 후보 2개 만들기, 10분 동안 고치지 않기, 중간 장면부터 쓰기, 대사 한 줄 쓰기, 첫 문장을 임시로 쓰기.
- 마지막에는 현재 코치 말투로 혼자 두지 않겠다는 안심을 짧게 붙이세요. 장황한 글쓰기 강의, 재능 평가, "그냥 써라", "의지가 부족하다"는 말은 하지 마세요.'''
        : '';
    final habitAutomationRule = isHabitAutomationTurn
        ? '''

[습관 자동화 참고 전략]
- 이 섹션은 사용자가 습관, 루틴, 꾸준함, 반복 연습, 재능 향상, 자동화, 시작 장벽에 대해 말한 턴에만 참고합니다. 모든 상황에 일반화하지 마세요.
- 이 전략은 뇌신경 전문의가 쓴 책 <작심>에서 소개된 습관·재능 훈련 아이디어를 참고한 것입니다. 100% 정답처럼 단정하지 말고, "책 <작심>에도 소개된 참고 전략", "모두에게 맞는 정답은 아니지만 시도해볼 만한 방식" 정도로 짧게 표현하세요.
- 하루 4번, 처음 4일, 아주 짧게 여러 번 나눠 하기 같은 제안을 할 때는 이유를 한 문장으로 붙이세요. 예: "한 번 길게 하는 것보다 쉬는 시간을 두고 여러 번 접촉하면 뇌에 반복 신호가 남아 자동화에 도움이 될 수 있다는 설명이 있다"를 현재 코치 말투로 자연스럽게 바꾸세요.
- 시작이 귀찮은 사용자에게는 의지보다 환경 마찰을 낮추는 제안을 우선하세요. 예: 문서 바로가기, 키보드 꺼내두기, 작업 파일 첫 화면에 두기, 책상에 노트 펼쳐두기.
- 실제 실행이 너무 부담스러울 때는 상상 훈련을 보조 단계로 제안할 수 있습니다. 예: 문서 여는 장면, 첫 문장 쓰는 장면, 5분 집중하는 장면을 20초만 떠올리기. 단, 상상 훈련이 실제 실행을 완전히 대체한다고 말하지 마세요.
- 답변은 지식 설명보다 현재 사용자가 오늘 할 수 있는 아주 작은 실행 하나로 끝내세요.'''
        : '';
    final sleepPrioritySection = sleepInterventionRule.isNotEmpty
        ? sleepInterventionRule
        : '';
    final lowEnergyPrioritySection = lowEnergyStarterRule.isNotEmpty
        ? lowEnergyStarterRule
        : '';
    final decisionSupportSection = decisionFatigueRule.isNotEmpty
        ? decisionFatigueRule
        : '';
    final thoughtOverloadSection = thoughtOverloadRule.isNotEmpty
        ? thoughtOverloadRule
        : '';
    final domainResistanceStrategySection =
        domainResistanceStrategyRule.isNotEmpty
        ? domainResistanceStrategyRule
        : '';
    final writingConcernSection =
        writingConcernRule.isNotEmpty && !shouldUseDomainResistanceStrategy
        ? writingConcernRule
        : '';
    final habitAutomationSection = habitAutomationRule.isNotEmpty
        ? habitAutomationRule
        : '';
    final completionResponseSection =
        ExecutionResistanceService.isCompletionOrPartialExecutionReport(
          userText,
        )
        ? '''

[완료/부분 실행 반응 원칙]
- 사용자가 어떤 일을 했다고 말하면, 앱의 할 일 목록 상태와 사용자의 표현을 함께 판단하세요.
- 할 일 목록에 있고 완료 체크된 일은 완전 완료로 인정하세요. 이때는 다음 행동을 묻거나 제안하지 말고, 완료 자체를 충분히 축하하고 안도감을 주세요.
- 할 일 목록에 있지만 완료 체크되지 않은 일은 전체 완료로 단정하지 마세요. 시작했거나 일부 실행한 것으로 인정하고, 여기까지 한 것도 충분히 의미 있다고 말하세요.
- 할 일 목록에 없는 일을 사용자가 했다고 말하면, 했다는 사실은 믿고 인정하되 "목록에서 완료됐다", "오늘 할 일 하나가 줄었다"처럼 앱 기록이 바뀐 것처럼 말하지 마세요.
- 사용자가 먼저 다음 일을 묻지 않았다면 바로 다른 일을 제안하지 마세요.
- 번아웃 방지 휴식 모드, 저활성 후 재시작 코칭 정책, 휴식 제안 거절 후 위험 완충 코칭 정책 같은 소진/저에너지 관련 특별 지침이 적용 중이면, 완료 직후에는 더 진행하도록 유도하지 말고 멈춰도 된다는 안심을 우선하세요.'''
        : '';
    final shouldIncludeResistanceInterventionSection =
        isResistanceTurn ||
        isResultAnxietyTurn ||
        resistanceTurnDirective.trim().isNotEmpty;
    final resistanceInterventionSection =
        shouldIncludeResistanceInterventionSection
        ? '''

[하기 싫다 실행 개입 전략]
- 사용자가 "하기 싫다", "귀찮다", "못 하겠다", "미루고 싶다"처럼 실행 저항을 표현하거나, 결과가 두려워 시작·진행이 막힌 마음을 말하면 작업 성격을 먼저 판단하고, 실행 성공 가능성·낮은 부담·자연스러움 순으로 한 가지 개입만 고르세요.
- "숨 고르고 해도 된다", "잠깐 쉬어도 된다"는 말은 사용할 수 있지만, 거기서 답변을 끝내지 마세요. 해야 할 일이 대화나 오늘 할 일 현황에 보이면 "그래도 조금이라도 하면 덜 찜찜할 것 같으면"이라는 방향으로 바로 할 수 있는 첫 조각 하나를 함께 골라주세요.
- 사용자가 아프거나 수면 부족, 극심한 탈진, 명시적인 휴식 요청을 말한 경우가 아니라면 "나중에 기운 생기면 하자", "오늘은 외면하자"처럼 실행을 다음으로 미루는 결론으로 끝내지 마세요.
- 창작·기획·공부·개발·글쓰기처럼 인지 부담이 큰 작업은 결과물 요구보다 짧은 시간 시작을 권하세요. 단, 창작 작업에 "한 문장만" 같은 산출물 요구는 기본적으로 피하세요.
- 청소·설거지·정리·빨래 개기처럼 반복 작업은 가장 작은 실행 단위 하나로 낮추세요.
- 분리수거·세탁기 돌리기·약 먹기처럼 이미 하나의 행동인 작업은 억지로 쪼개지 말고 금방 끝난다는 점이나 끝낸 뒤의 효과로 부담을 낮추세요.
- 양치·세수·샤워는 하나의 행동에 가깝지만 시작 장벽이 높을 수 있으니 효과 언급 또는 진입 행동만 허용합니다. 단, "반만 양치/샤워"처럼 완료 단위를 어색하게 쪼개지 마세요.
- 과업 진입이 무거우면 5분 시작 대신 첫 접촉(보기/열기/손대기) 1개 가능. 예: 문서 열기, 커서 보기, 컵 하나 보기, 운동복 보기.
- 초저항에서는 첫 접촉까지만 요청하고 실제 행동은 [ULTRA_LOW_RESISTANCE_FOLLOWUP]으로 분리.
$resistanceStrategyDetailRule
$selfSelectedTinyActionRule
- 분류가 애매하면 5분만 시작하는 방향을 기본값으로 사용하되, 현재 코치의 말투로 표현하세요.
- 거절 분기: "지금은 못 해요"는 시작하기 쉬운 시간을 한 번만 묻고, 시간을 말하면 받아주세요. "곧 다른 일정이 있어요"는 다시 묻지 말고 일정 뒤 5분을 제안하세요. "다른 걸 먼저 할래요"는 우선순위 변경으로 인정하세요.
- 타이머는 "5분만 시작"이 자연스러운 경우에만 말로 연결하고, 아래 [TIMER_CONFIRM] 규칙을 항상 우선하세요. 명시 요청이나 앱 기록상 조건 없이는 타이머 태그를 출력하지 마세요.
$resistanceFlowRule'''
        : '';

    final customTitle = await UserTitleService.getTitle();
    // 최종 조립된 프롬프트 전체에 호칭 치환을 한 번에 적용하므로
    // (systemPromptWithChips), 여기서는 원문 프롬프트를 그대로 사용한다.
    final baseSystemPrompt = _coach.systemPrompt;

    final useVisionNewActionContext = userText == '미래를 위한 오늘 - 새 행동 추천받기';
    final contextString = useVisionNewActionContext
        ? await _buildVisionNewActionContextString()
        : await _buildContextString(userText);
    final timerOutputRule = _coach.isMaster
        ? '''4. [TIMER_START] 태그는 절대 사용 금지.
   - 사용자가 직접 "타이머 띄워줘", "15분 타이머 켜줘"처럼 명시적으로 요청한 경우에는 짧게 응답한 뒤 [TIMER_CONFIRM:분] 태그를 붙입니다. 시간이 없으면 15분을 기본값으로 사용합니다.
   - 직전 답변에서 타이머가 필요한지 현재 코치의 말투로 물었고 사용자가 동의했다면 [TIMER_CONFIRM:분:할일이름]을 출력합니다.
   - 코치가 먼저 [TIMER_CONFIRM] 태그를 출력하지 마세요. "마음 비우고 시작", "시작 의식", 카운트다운도 먼저 제안하지 마세요. 해당 기능은 사용자가 직접 버튼을 누르거나 명시적으로 요청했을 때만 시작합니다.'''
        : '''4. [TIMER_START] 태그는 절대 사용 금지. [TIMER_CONFIRM]은 사용자가 직접 "타이머 띄워줘", "15분 타이머 켜줘", "집중모드 시작해줘"처럼 타이머 실행을 명시적으로 요청한 경우에만 붙입니다. 시간이 없으면 15분을 기본값으로 사용합니다. 구체적인 과업이 있어도 타이머로 바로 넘어가지 말고 기존 코칭 프롬프트를 따르세요. 코치가 먼저 타이머를 제안할 때는 말로만 "필요하면 말해"라고 하고 [TIMER_CONFIRM] 태그를 붙이지 마세요.''';
    // 냥냥이 연결(COACH_SWITCH)은 장기 목표 압박을 주는 마스터 코치(냥할배/여비서) 전용 탈출구다.
    // 프렌즈 코치는 이미 압박 없는 오늘 하루 중심이라 서로 스위치될 이유가 없다.
    final coachSwitchRule = _coach.isMaster
        ? '''
   사용자가 우울함, 무기력함, 감정적 고통을 토로하고 그 감정이 2회 이상 반복되거나 깊어지고 있다면, 냥냥코치가 사용자를 걱정하고 있다는 뉘앙스로 자연스럽게 연결하세요. 팀으로서 함께 챙기는 느낌을 주되, 현재 코치의 말투를 반드시 유지하세요. 답변 끝에 [COACH_SWITCH:cat]만 붙이세요. 단 한 번의 가벼운 감정 표현에는 붙이지 마세요.'''
        : '';
    final masterStyleRule = _coach.id == 'nyang_halbae'
        ? '''

[냥할배 말투 우선 규칙]
- 아래 공통 지침에 존댓말 표현이나 비서식 표현이 있더라도, 최종 답변은 반드시 냥할배의 반말 기반 말투로 바꾼다.
- "추천드립니다", "말씀해 주세요", "확인해 주세요", "하시죠", "해볼까요", "도와드리겠습니다"처럼 높임말과 냥 말투를 섞지 않는다.
- 행동 추천은 "지금은 운동 30분이 괜찮겠구나냥", "이것부터 잡아보자냥"처럼 말한다.'''
        : '';
    final assembledSystemPrompt =
        '''$baseSystemPrompt
${contextString.isNotEmpty ? '\n$contextString' : ''}
$masterStyleRule

[연속 대화 맥락 기준]
- 직전 대화처럼 이어받아도 되는 말은 오늘 같은 날짜에 오간 대화뿐입니다.
- 날짜가 다른 과거 대화는 사용자가 "전에 말한 것", "예전에 말했던 것", "그때 이야기"처럼 명확히 지칭할 때만 참고 대상으로 보세요.
- 사용자가 "일정 확인", "오늘 할 일", "뭐 하지?"처럼 새 조회나 새 판단을 요청하면 과거 대화보다 현재 날짜의 최신 앱 기록과 현재 입력을 우선하세요.

[자해·자살 안전 우선 규칙]
- 자해·자살 위험 신호가 감지된 턴이나 직전 안전 확인의 후속 답변에서는 안전 대응이 캐릭터 설정, 일정, 생산성, 실행, 타이머, 할 일, 성취 평가, 다른 코치 연결보다 우선합니다.
$selfHarmRiskRule

$sleepPrioritySection
$lowEnergyPrioritySection

[감정 토로 응답 원칙]
- 사용자가 속상함, 피로, 불안, 답답함 등 감정을 토로하면 먼저 충분히 공감하고 달래주세요.
- 정서적 여유가 낮아 보이거나 사용자가 단순히 감정을 표현한 상황에서는, 해결 가능한 문제가 보여도 행동 제안을 자동으로 붙이지 마세요.
- 행동 제안은 사용자가 행동을 원한다는 의사를 분명히 밝혔을 때만 하나 제안하세요.
- 전략 분석, 원인 진단, 자세한 조언은 사용자가 "왜", "어떻게", "분석해줘", "조언해줘"처럼 명시적으로 요청했을 때만 길게 제공하세요.
- 감정 토로 상황에서는 답변을 짧게 유지하고, 공감의 온기가 행동 제안에 묻히지 않게 하세요.
$completionResponseSection

[코치 질문 원칙]
- 질문이 필요한 경우에도 한 번에 하나만 물으세요.
- 사용자의 의도를 어느 정도 추측할 수 있다면 먼저 상황을 짧게 정리하거나 합리적인 기본값을 제안한 뒤, 필요할 때만 마지막에 확인 질문을 하나 붙이세요.
- 의도를 추측하기 어렵거나 잘못 추측하면 부담이 큰 상황에서는 확인 질문을 먼저 하세요.
- 사용자의 선택이 필요한 상황에서는 설명을 요구하기보다 다음 행동을 고르게 돕는 질문을 우선하세요.
- 가능한 질문은 원인 추궁보다 실행을 돕는 방향을 우선하세요.

$thoughtOverloadSection
$domainResistanceStrategySection
$resistanceInterventionSection
$decisionSupportSection
$writingConcernSection
$habitAutomationSection

[출력 규칙]
1. 지정된 캐릭터의 성격, 호칭, 말투 규칙을 철저히 준수하세요.
2. 마크다운 문법(**, *, # 등) 절대 사용하지 말 것.
3. 답변 끝에 자연스러운 빠른 답장 버튼 3개를 [CHIPS: 버튼1|버튼2|버튼3] 형식으로 추가하세요.
   예시: [CHIPS: 오늘 할 일 정하기|기분 이야기하기|그냥 얘기하자]
   단, 정서적 여유가 낮은 사용자의 순수 감정 토로에는 [CHIPS]를 쓰지 말고 답변 끝에 [NO_CHIPS]를 붙이세요.$coachSwitchRule
   자해·자살 위험을 확인하거나 긴급 도움을 안내하는 상황에서는 [CHIPS]와 [COACH_SWITCH]를 붙이지 말고 [NO_CHIPS]만 붙이세요.
$timerOutputRule
5. 사용자가 특정 할 일을 언급하거나 해결 가능한 문제가 드러나고, 그걸 오늘 할 일로 등록할 만한 상황이라면 답변에 [TASK: 할일명] 태그를 포함하세요. 예: "5시에 청소해야지" → [TASK: 5시에 청소], "오후 3시에 회의가 있어" → [TASK: 오후 3시 회의], "SNS 반응이 안 좋아" → [TASK: SNS 콘텐츠 분석하기]. 억지로 추가하지 마세요. 정서적 여유가 낮거나 순수 감정 토로인 상황에는 사용자가 행동 지원을 명시적으로 요청하지 않는 한 [TASK]와 [TIMER_CONFIRM]을 출력하지 마세요. 자해·자살 위험 상황에서는 두 태그를 절대 출력하지 마세요.$halmaeHint$resistanceTurnDirective''';

    // 마스터 코치는 하드코딩된 "대표님"을 사용자가 지정한 호칭으로 치환한다.
    // baseSystemPrompt 뒤에 이어붙인 coachSwitchRule 등 모든 조각까지 함께 반영된다.
    final systemPromptWithChips = _coach.isMaster
        ? assembledSystemPrompt.replaceAll(
            UserTitleService.defaultTitle,
            customTitle,
          )
        : assembledSystemPrompt;

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
1. [선 질문 금지, 즉시 추천]: 인사말이나 사전 질문을 절대 하지 말고, 첫 마디부터 바로 구체적인 행동 1개를 콕 집어 즉시 추천하세요.
   - 예시 문장을 그대로 쓰지 말고, 현재 코치의 말투로 바꿔 말하세요. 냥할배는 반말 기반으로, 비서 실장은 존댓말 기반으로 말하세요.
2. [피드백에 따른 재조정]: 사용자가 상황/제한사항을 입력하면, 그 조건에 맞게 '실행 가능한 다른 다음 행동 1개'로 즉시 재조정하세요.
3. [부정적 종결 금지]: 관련 일정이 부족하더라도 절대 "할 일이 없다"거나 "비전과 무관하다"며 단정적으로 대화를 끝내지 마세요. 할 일이 아예 없을 때는 가볍게 비전 관련 15분 독서나 스트레칭 등 가벼운 생산적 행동을 제안하세요.]''';
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
1. 답변은 짧게 3문장으로 작성하세요. 현재 코치의 톤에 맞추되 보고서처럼 딱딱하게 쓰지 마세요.
2. 구조는 반드시 "어제까지의 비전 흐름을 짧게 해석하는 1문장 + 오늘은 OO부터 하자는 자연스러운 제안과 이유 1문장 + 지금 시작할 첫 행동과 기대 효과 1문장"으로 만드세요.
   - "오늘의 비전 행동은", "비전상 가장 효율적입니다", "기대 효과가 발생합니다" 같은 제목형/보고서형 표현은 피하세요.
   - 비서식 존댓말 예문을 그대로 쓰지 말고, 현재 코치의 말투로 생활어처럼 말하세요.
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
1. 답변은 2~3문장으로 작성하세요. 현재 코치의 톤에 맞추되 보고서처럼 딱딱하게 쓰지 마세요.
2. 구조는 "최근 흐름을 짧게 짚는 1문장 + 근거와 함께 오늘 할 구체 행동을 제안하는 1~2문장"으로 만드세요.
   - 마일스톤 메모에서 행동을 도출했다면 어느 비전의 어느 마일스톤 메모를 참고했는지 반드시 자연스럽게 밝히세요.
   - 메모의 핵심 내용과 제안 행동이 어떻게 이어졌는지 짧게 설명하세요.
   - 메모가 없는 후보라면 메모를 봤다고 말하지 말고, 비전 또는 마일스톤 제목에서 첫 행동을 만들었다고 짧게 설명하세요.
   - "오늘의 비전 행동은", "비전상 가장 효율적입니다", "기대 효과가 발생합니다" 같은 제목형/보고서형 표현은 피하세요.
   - 판단 과정을 길게 설명하지 말고 선택지를 줄여주는 코치처럼 말하세요.
   - 추천 행동 한 줄이 묻히지 않게, 본문에는 행동 후보를 여러 개 나열하지 마세요.
3. 오늘 완료율, 오늘 미완료율, 오늘 아직 안 했다는 식의 평가 표현은 금지합니다.
4. 단순 시간표나 전체 일정 배치는 하지 마세요.]''';
    }

    final timePrefix =
        '[${now.hour}:${now.minute.toString().padLeft(2, '0')}] ';
    if (shouldOfferLowEnergyStarter) {
      _awaitingLowEnergyStarterAction = true;
    }
    if (shouldInviteSelfSelectedTinyAction) {
      _awaitingSelfSelectedTinyAction = true;
    }

    final messages = [
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

    final model = await _pickChatModel(
      masterModelPolicy: masterModelPolicy,
      resistanceTurnDirective: resistanceTurnDirective,
    );

    // Firebase Cloud Functions chatProxy 호출 (웹앱과 동일한 Gemini AI 서버)
    final result = await _chatProxy.call({
      'messages': messages,
      'model': model,
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
    final isMale = _coach.id == 'nyang_halbae';
    return switch (kind) {
      'cleaning' =>
        isMale
            ? _pickLine([
                '치워도 금방 어질러질 수 있지. 그래도 다시 손댈 때마다 마음도 조금 정리된다냥.',
                '완벽하게 치울 필요는 없다냥. 지금은 불편하지 않을 정도로만 돌려놓아도 충분하다냥.',
                '어질러지는 건 자연스러운 일이다냥. 중요한 건 다시 정리할 수 있는 흐름을 잃지 않는 것이더군.',
                '오늘 잠깐 정리해두면 기분이 한결 산뜻해질 거다냥. 청소는 마음의 길을 내는 일일 수도 있다냥.',
              ])
            : _pickLine([
                '물론 치워도 금방 어질러질 수 있어요. 그래도 다시 손댈 때마다 기분도 산뜻해지고, 자신감도 조금씩 쌓여요. 오늘은 잠깐만 같이 정리해볼까요?',
                '완벽하게 치우지 않아도 괜찮아요. 오늘은 불편하지 않을 정도로만 살짝 돌려놔볼까요?',
                '어질러지는 건 너무 자연스러운 일이에요. 그래도 다시 정리하는 흐름을 이어가면, 어제보다 더 잘 챙기는 사람이 되어가고 있는 거예요.',
                '오늘 잠깐 정리해두면 기분이 훨씬 산뜻해질 거예요. 저는 청소가 복을 쌓는 일 같아요. 생활도 일도 조금 더 잘 풀릴 테니까요.',
              ]),
      'dishes' =>
        isMale
            ? '설거지는 해도 또 생기지. 그래도 한 번씩 끊어낼 때마다 생활을 붙잡는 힘이 쌓인다냥.'
            : '설거지는 해도 또 생겨요. 그래도 쌓인 걸 한 번씩 끊어낼 때마다 생활을 잡아가는 자신감이 쌓여요. 오늘은 잠깐만 같이 처리해볼까요?',
      'laundry' =>
        isMale
            ? '빨래는 티가 크게 나지 않아도 내일의 나를 챙기는 일이다냥. 작은 준비가 생활을 단단하게 만들더군.'
            : '빨래는 티가 크게 나지 않죠. 그래도 내일의 나를 챙기는 일이니까요. 이런 작은 준비가 생활을 잡아가는 자신감이 된다고 생각해요. 기분도 상쾌해지고요. 오늘은 잠깐만 같이 해볼까요?',
      'trash' =>
        isMale
            ? '쓰레기는 금방 다시 생기지. 그래도 비워낼 때마다 내 공간을 방치하지 않는 힘이 쌓인다냥.'
            : '물론 쓰레기는 금방 다시 생겨요. 그래도 비워낼 때마다 내 공간을 잘 관리하고 있다는 자신감이 쌓인다고 생각해요. 오늘은 잠깐만 같이 비워볼까요?',
      'exercise' =>
        isMale
            ? _pickLine([
                '운동은 당장 큰 변화가 보이지 않아도 몸의 흐름을 바꿔준다냥. 오늘은 잠깐만 움직여보자냥.',
                '완벽한 운동이 아니어도 괜찮다냥. 시작했다는 자신감부터 쌓으면 된다냥.',
                '운동은 몸만 관리하는 일이 아니더군. 컨디션과 마음을 같이 깨우는 일일 수도 있다냥.',
                '시작은 귀찮아도 움직인 만큼 돌아오는 게 있더라냥. 오늘은 부담 없이 가보자냥.',
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

  String _friendlyChatErrorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      if (error.code == 'deadline-exceeded' || error.code == 'unavailable') {
        return '답변 서버가 잠시 불안정해요. 잠깐 뒤에 다시 보내주세요.';
      }
    }
    return '답변을 만드는 중 문제가 생겼어요. 잠시 후 다시 시도해 주세요.';
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red[400],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
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
                    onPressed: _canOpenSubscriptionGuide
                        ? () {
                            Navigator.pop(sheetContext);
                            Future.delayed(
                              Duration.zero,
                              _showPlanGuideBottomSheet,
                            );
                          }
                        : null,
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
    final showVacationSuggestBubble =
        !_suppressDefaultChips &&
        _dynamicChips.contains('오늘은 쉬어가기') &&
        _dynamicChips.contains('오늘은 조금만 하기') &&
        _dynamicChips.length == 2;
    final showQuickChips =
        !_suppressDefaultChips &&
        !showVacationSuggestBubble &&
        _coachSwitchTarget == null &&
        ((_dynamicChips.contains('오늘은 쉬어가기') &&
                _dynamicChips.contains('오늘은 조금만 하기')) ||
            _coach.isMaster ||
            (_dynamicChips.isNotEmpty || _coach.chips.isNotEmpty));
    if (keyboardOpen && _cheatKeyOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _cheatKeyOpen = false);
      });
    }

    return Stack(
      children: [
        Column(
          children: [
            if (widget.vacationInfo == null) _buildSummaryCard(),
            if (widget.vacationInfo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/fa-moon-solid.svg',
                      width: 14,
                      height: 14,
                      colorFilter: ColorFilter.mode(
                        Colors.white.withValues(alpha: 0.82),
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '오늘은 컨디션이 먼저입니다.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Container(
                color: _chatAreaBackgroundColor,
                width: double.infinity,
                child: Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: _messages.isEmpty
                              ? _buildEmptyState()
                              : _buildMessageList(),
                        ),
                        if (showVacationSuggestBubble)
                          _buildVacationSuggestBubble(),
                      ],
                    ),
                    if (showQuickChips)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _buildChips(),
                      ),
                  ],
                ),
              ),
            ),
            _buildInputArea(),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'assets/icons/thumbtack.svg',
                  width: 10,
                  height: 10,
                  colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                ),
                const SizedBox(width: 4),
                Text(
                  '할 일로 추가할까요?',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ],
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
                            color: _accentButtonTextColor,
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
                final rawMsg = _coach.id == 'nyang_halbae'
                    ? '알겠다냥. 일 끝나고 돌아올 때 다시 떠올려주겠다.'
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
                final rawMsg = _coach.id == 'nyang_halbae'
                    ? '대표님의 판단을 존중합니다. 준비되시면 언제든 말씀해 주십시오.'
                    : '그럼 네 페이스대로 가자냥. 준비되면 다시 말해주면 된다.';
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
    {'icon': 'assets/icons/compass.svg', 'label': '미래를 위한 오늘'},
    {'icon': 'assets/icons/flag.svg', 'label': '마일스톤 확인'},
    {'icon': 'assets/icons/fa-circle-play-solid.svg', 'label': '숫자 세고 시작'},
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
              } else if (item['label'] == '숫자 세고 시작') {
                AnalyticsService.logFeatureUsage('cheat_countdown_start');
                _openCountdownFocusMode();
                return;
              } else if (item['label'] == '메모 검색') {
                AnalyticsService.logFeatureUsage('cheat_memo_search');
                _openMemoSearch();
                return;
              }

              _send(
                item['label']!,
                masterModelPolicy: item['label'] == '미래를 위한 오늘'
                    ? _MasterModelPolicy.premiumFeature
                    : _MasterModelPolicy.forceGpt4oMini,
              );
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
  Color get _chatAreaBackgroundColor {
    if (!_coach.isMaster || widget.vacationInfo != null) {
      return Colors.transparent;
    }
    return _coach.id == 'nyang_halbae'
        ? AppDesignTokens.brandSoftAlt
        : const Color(0xFFEDF7F4);
  }

  Widget _buildMessageList() {
    final items = <Widget>[];

    // 상단: 지난 대화 영역 (열기 전엔 연한 링크, 열면 과거 메시지 + 구분선)
    if (_pastLoaded) {
      for (final m in _pastMessages) {
        items.add(_buildBubble(m));
      }
      if (_pastMessages.isNotEmpty) items.add(_buildTodayDivider());
    } else if (_hasArchivedChat) {
      items.add(_buildPastChatLink());
    }

    // 오늘 메시지 (+ 집중 타이머 위젯)
    final timerIndex = _timerActiveMinutes == null
        ? null
        : (_timerActiveInsertIndex ?? _messages.length).clamp(
            0,
            _messages.length,
          );
    for (var idx = 0; idx <= _messages.length; idx++) {
      if (timerIndex != null && idx == timerIndex) {
        items.add(
          Padding(
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
          ),
        );
      }
      if (idx < _messages.length) {
        items.add(_buildBubble(_messages[idx]));
      }
    }

    if (_isLoading) items.add(_buildTypingIndicator());
    if (_coachSwitchTarget != null) items.add(_buildNyangSwitchBubble());

    final list = ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: items.length,
      itemBuilder: (ctx, i) => items[i],
    );

    // 마스터 코치별 대화 영역 배경
    if (_coach.isMaster) {
      final isVacationBg = widget.vacationInfo != null;
      return ColoredBox(
        color: isVacationBg ? Colors.transparent : _chatAreaBackgroundColor,
        child: list,
      );
    }

    // 프렌즈는 배경 투명 (main_tab_screen에서 전체 배경 처리)
    return ColoredBox(color: Colors.transparent, child: list);
  }

  // 채팅창 상단의 연한 "지난 대화 보기" 링크.
  Widget _buildPastChatLink() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 14),
      child: Center(
        child: GestureDetector(
          onTap: _loadPastMessages,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text(
              '지난 대화 보기',
              style: GoogleFonts.notoSansKr(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFB2AEC6),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 지난 대화와 오늘 대화 사이 구분선.
  Widget _buildTodayDivider() {
    const lineColor = Color(0xFFE2DEF0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          const Expanded(child: Divider(color: lineColor, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '오늘',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFA7A2BE),
              ),
            ),
          ),
          const Expanded(child: Divider(color: lineColor, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildBubble(ChatMessage msg) {
    if (msg.kind == 'vision_choice') {
      return _buildVisionChoiceCard(msg);
    }
    if (msg.kind == 'start_difficulty_choice') {
      return _buildStartDifficultyChoiceCard(msg);
    }
    // 저녁 발화(auto:evening)는 미완료 일정이 있을 때만 선택 카드로 그린다.
    if ((msg.kind == 'evening_pending_choice' ||
            msg.kind == _greetingKind(GreetingSlot.evening)) &&
        msg.choices.isNotEmpty) {
      return _buildEveningPendingChoiceCard(msg);
    }
    if (msg.kind == 'grooming_care_choice') {
      return _buildGroomingCareChoiceCard(msg);
    }
    if (msg.kind == 'grooming_askback') {
      return _buildGroomingAskBackCard(msg);
    }
    if (msg.kind == 'grooming_followup_from_home') {
      return _buildGroomingMovedFollowupCard(msg, wasHome: true);
    }
    if (msg.kind == 'grooming_followup_from_outdoor') {
      return _buildGroomingMovedFollowupCard(msg, wasHome: false);
    }
    if (msg.kind == 'grooming_care_followup') {
      return _buildGroomingCareFollowupCard(msg);
    }
    if (msg.kind == 'ultra_low_resistance_check') {
      return _buildUltraLowResistanceCheckCard(msg);
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
      ('캘린더', 'schedule'),
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
            : () => _send(
                label,
                apiInputOverride: apiInput,
                masterModelPolicy: _MasterModelPolicy.premiumFeature,
              ),
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
                      fontSize: AppDesignTokens.textBody,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                      color: AppDesignTokens.textPrimary,
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

  Widget _buildStartDifficultyChoiceCard(ChatMessage msg) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final accent = _coach.accentColor;

    Widget choiceButton(String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: _isLoading ? null : onTap,
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
                  choiceButton(
                    '첫 조각 골라줘',
                    () => _send(
                      '첫 조각 골라줘',
                      apiInputOverride: '지금 뭐하지?',
                      masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
                    ),
                  ),
                  const SizedBox(height: 8),
                  choiceButton('생각 비우고 시작할래', _startMorningCountdown),
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

  /// 저녁 발화에서 "귀찮았던 일"을 고르는 카드.
  /// 버튼 라벨은 메시지에 박아둔 것을 그대로 쓴다 — 그릴 때마다 할 일 목록을
  /// 다시 읽으면 지나간 카드의 버튼까지 뒤늦게 바뀐다.
  Widget _buildEveningPendingChoiceCard(ChatMessage msg) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final accent = _coach.accentColor;

    Widget choiceButton(String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: _isLoading ? null : onTap,
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
                      fontSize: AppDesignTokens.textBody,
                      fontWeight: FontWeight.w500,
                      height: 1.6,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                  for (final label in msg.choices) ...[
                    const SizedBox(height: 8),
                    choiceButton(
                      label,
                      () => _handleEveningPendingChoice(label, msg.choices),
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

  /// '그 외'를 누르면 남은 일정을 다시 버튼으로 보여주고, 일정을 고르면
  /// 기존 실행 저항 흐름을 태워 부담을 낮추는 방향으로 답하게 한다.
  Future<void> _handleEveningPendingChoice(
    String label,
    List<String> shown,
  ) async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();

    // 계획에 없던 일을 물었을 때의 두 버튼. 일정 이름이 아니므로 먼저 걸러낸다.
    if (label == MasterGreetingCopy.offPlanDoneLabel) {
      _injectAiMessage(
        _greetingBuilder.pickLine(_greetingVoice.offPlanDoneReply),
        kind: 'evening_pending_choice',
      );
      await AnalyticsService.logFeatureUsage('master_offplan_done');
      return;
    }
    if (label == MasterGreetingCopy.offPlanNotYetLabel) {
      await AnalyticsService.logFeatureUsage('master_offplan_not_yet');
      // 저항 흐름을 한 번 더 태운다. 사용자에게 보이는 말은 누른 버튼 그대로다.
      await _send(
        label,
        apiInputOverride: '아까 부담스럽다고 한 그 일, 아직 하기 싫어',
        masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
      );
      return;
    }

    if (label == _greetingVoice.otherChoiceLabel) {
      final prefs = await SharedPreferences.getInstance();
      final context = await _buildMasterGreetingContext(
        prefs: prefs,
        now: DateTime.now(),
        lastVisit: null,
      );
      final rest = context.pendingPlans
          .where((task) => !shown.contains(task))
          .toList(growable: false);
      if (rest.isEmpty) {
        _injectAiMessage(
          _coach.id == 'nyang_halbae'
              ? '남은 건 방금 보여준 게 전부다냥. 그중에 걸리는 게 있으면 눌러보라냥.'
              : '남은 건 방금 보여드린 게 전부예요. 그중에 걸리는 게 있으면 눌러주세요.',
        );
        return;
      }
      final restNames = rest.take(3).map((task) => "'$task'").join(', ');
      _injectAiMessage(
        _coach.id == 'nyang_halbae'
            ? '남은 건 $restNames 이런 것들이다냥. 이 중에 제일 손이 안 가는 게 뭐냥?'
            : '남은 건 $restNames 이런 것들이에요. 이 중에 제일 손이 안 가는 건 어떤 걸까요?',
        kind: 'evening_pending_choice',
        choices: _greetingBuilder.eveningChoices(rest),
      );
      await AnalyticsService.logFeatureUsage('master_evening_other');
      return;
    }

    _pendingEveningSplitTask = label;
    _pendingEveningSplitAt = DateTime.now();
    await AnalyticsService.logFeatureUsage('master_evening_pick');
    await _send(
      label,
      apiInputOverride: "'$label'이(가) 오늘 제일 하기 싫었어",
      masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
    );
  }

  Widget _buildGroomingCareChoiceCard(ChatMessage msg) {
    return _buildGroomingChoiceCard(msg, [
      ('집이야', _sendHomeGroomingRoutine),
      ('밖이야', _sendOutdoorGroomingRoutine),
    ]);
  }

  Widget _buildGroomingAskBackCard(ChatMessage msg) {
    return _buildGroomingChoiceCard(msg, [
      ('응, 해봤어', () => _answerGroomingAskBack(true)),
      ('아니, 못 했어', () => _answerGroomingAskBack(false)),
    ]);
  }

  /// 장소를 기억해서 바로 추천한 뒤에 붙는 카드. 그 사이 자리를 옮겼을 수도
  /// 있어서, 수락·거절에 더해 반대쪽으로 다시 받는 버튼을 하나 더 둔다.
  /// 어느 자리에서 뽑은 카드인지는 메시지 종류에 박아 둔다. 지금 장소를 보고
  /// 그리면, 나중에 자리를 옮겼을 때 위로 지나간 옛날 카드까지 버튼이 뒤집힌다.
  Widget _buildGroomingMovedFollowupCard(
    ChatMessage msg, {
    required bool wasHome,
  }) {
    return _buildGroomingChoiceCard(msg, [
      ('알았어. 해볼게', _acceptGroomingCareRoutine),
      ('하기 귀찮아', _resistGroomingCareRoutine),
      wasHome
          ? ('나 지금 밖이야', _sendOutdoorGroomingRoutine)
          : ('나 지금 집이야', _sendHomeGroomingRoutine),
    ]);
  }

  Widget _buildGroomingCareFollowupCard(ChatMessage msg) {
    return _buildGroomingChoiceCard(msg, [
      ('알았어. 해볼게', _acceptGroomingCareRoutine),
      ('하기 귀찮아', _resistGroomingCareRoutine),
    ]);
  }

  Widget _buildUltraLowResistanceCheckCard(ChatMessage msg) {
    final followup = msg.choices.isNotEmpty ? msg.choices.first : '';
    return _buildGroomingChoiceCard(msg, [
      ('응 했어', () => _answerUltraLowResistanceCheck(followup, didIt: true)),
      (
        '지금은 안 할래',
        () => _answerUltraLowResistanceCheck(followup, didIt: false),
      ),
    ], messageFontWeight: FontWeight.w500);
  }

  Future<void> _answerUltraLowResistanceCheck(
    String followup, {
    required bool didIt,
  }) async {
    if (_isLoading) return;
    HapticFeedback.lightImpact();
    final userText = didIt ? '응 했어' : '지금은 안 할래';
    final reply = didIt
        ? followup.trim()
        : (_coach.id == 'nyang_halbae'
              ? '알겠다냥. 지금은 안 하는 걸로 두고, 마음만 너무 몰아붙이지 말자냥.'
              : '알겠어요. 지금은 안 하는 걸로 두고, 마음만 너무 몰아붙이지 말아요.');
    setState(() {
      _messages.add(
        ChatMessage(text: userText, isUser: true, time: DateTime.now()),
      );
      if (reply.isNotEmpty) {
        _messages.add(
          ChatMessage(text: reply, isUser: false, time: DateTime.now()),
        );
      }
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
  }

  /// 가꾸기 플로우의 선택지 말풍선. 되묻기·집밖·수락거절이 생김새가 같아서
  /// 한 군데서 만든다 — 버튼 문구와 눌렀을 때 할 일만 다르다.
  Widget _buildGroomingChoiceCard(
    ChatMessage msg,
    List<(String, VoidCallback)> options, {
    FontWeight messageFontWeight = FontWeight.w800,
  }) {
    final time = DateFormat('a h:mm', 'ko').format(msg.time);
    final accent = _coach.accentColor;

    Widget choiceButton(String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: _isLoading ? null : onTap,
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
                  if (msg.text.trim().isNotEmpty) ...[
                    Text(
                      msg.text,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: messageFontWeight,
                        height: 1.45,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  for (var i = 0; i < options.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    choiceButton(options[i].$1, options[i].$2),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/fa-moon-solid.svg',
                      width: 14,
                      height: 14,
                      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '오늘은 쉬어가기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/paw.svg',
                      width: 14,
                      height: 14,
                      colorFilter: ColorFilter.mode(accent, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      '오늘은 조금만 하기',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 마스터 코치 채팅창 하단 고정 채팅칩.
  bool get _isMasterChipNightTime {
    final hour = DateTime.now().hour;
    return hour >= 21 || hour < 6;
  }

  bool get _isNyangPerfectionismChipTime {
    final hour = DateTime.now().hour;
    return hour >= 18 || hour < 6;
  }

  bool get _isNyangMorningStartChipTime {
    final hour = DateTime.now().hour;
    return hour >= 6 && hour < 12;
  }

  List<String> get _masterQuickChips {
    final appointmentPrepChip = _appointmentPrepChipLabel(
      truncateTaskName: true,
    );
    final focusChip = _coach.id == 'sec_female'
        ? appointmentPrepChip ??
              _thoughtOverloadChipLabel(truncateTaskName: true)
        : _thoughtOverloadChipLabel(truncateTaskName: true);
    var decisionChip = _masterDecisionChipLabel(truncateTaskName: true);
    if (_coach.id == 'nyang_halbae' &&
        decisionChip == '지금 뭐하지?' &&
        appointmentPrepChip != null) {
      decisionChip = appointmentPrepChip;
    }
    if (_coach.id == 'nyang_halbae') {
      if (_isNyangMorningStartChipTime) {
        return ['시작하기가 힘들어', focusChip, '오늘 핵심 정리해줘'];
      }
      if (_isNyangPerfectionismChipTime) {
        return _isMasterChipNightTime
            ? ['완벽하게 못 해서 속상해', focusChip, '내일로 미뤄도 돼?']
            : ['완벽하게 못 해서 속상해', focusChip, '오늘 핵심 정리해줘'];
      }
      return _isMasterChipNightTime
          ? [focusChip, '잠이 안 와', '내일로 미뤄도 돼?']
          : [focusChip, decisionChip, '오늘 핵심 정리해줘'];
    }
    return _isMasterChipNightTime
        ? ['잠이 안 와', focusChip, '내일로 미뤄도 돼?']
        : [decisionChip, focusChip, '오늘 핵심 정리해줘'];
  }

  static const int _resistanceChipTaskDisplayMaxLength = 10;

  String _truncateResistanceChipTaskName(String taskName) {
    if (taskName.length <= _resistanceChipTaskDisplayMaxLength) {
      return taskName;
    }
    return '${taskName.substring(0, _resistanceChipTaskDisplayMaxLength)}...';
  }

  String? _appointmentPrepChipLabel({required bool truncateTaskName}) {
    final taskName = _appointmentPrepChipTaskName?.trim();
    final timeLabel = _appointmentPrepChipTimeLabel?.trim();
    if (taskName == null ||
        taskName.isEmpty ||
        timeLabel == null ||
        timeLabel.isEmpty) {
      return null;
    }
    final displayTaskName = truncateTaskName
        ? _truncateResistanceChipTaskName(taskName)
        : taskName;
    return '$timeLabel $displayTaskName 준비 같이 해줘';
  }

  bool _isAppointmentPrepChip(String chip) {
    final displayLabel = _appointmentPrepChipLabel(truncateTaskName: true);
    return displayLabel != null && chip == displayLabel;
  }

  String _resistanceChipLabel(String chip, {required bool truncateTaskName}) {
    if (_coach.id != 'cat' && _coach.id != 'boyfriend') return chip;
    if (chip != '하기 싫다' && chip != '하기 싫어') return chip;

    final taskName = _resistanceChipTaskName?.trim();
    if (taskName == null || taskName.isEmpty) {
      if (_coach.id == 'boyfriend' && chip == '하기 싫어') {
        return '오늘 시작이 꼬였어';
      }
      return chip;
    }
    final displayTaskName = truncateTaskName
        ? _truncateResistanceChipTaskName(taskName)
        : taskName;
    return "'$displayTaskName' 하기 귀찮아";
  }

  static const String _thoughtOverloadFallbackChip = '머리가 복잡해서 시작이 안 돼';

  String _thoughtOverloadChipLabel({required bool truncateTaskName}) {
    final taskName = _thoughtOverloadChipTaskName?.trim();
    if (taskName == null || taskName.isEmpty) {
      return _thoughtOverloadFallbackChip;
    }
    final displayTaskName = truncateTaskName
        ? _truncateResistanceChipTaskName(taskName)
        : taskName;
    return '\'$displayTaskName\' 하려니 머리가 복잡해';
  }

  bool _isThoughtOverloadMasterChip(String chip) {
    if (!_coach.isMaster) return false;
    return chip == _thoughtOverloadFallbackChip ||
        chip == _thoughtOverloadChipLabel(truncateTaskName: true);
  }

  String _thoughtOverloadMasterChipApiInput() {
    final taskName = _thoughtOverloadChipTaskName?.trim();
    if (taskName == null || taskName.isEmpty) {
      return _thoughtOverloadFallbackChip;
    }
    return '\'$taskName\' 하려니 머리가 복잡해';
  }

  String _deferredResistancePhrase(String taskName) {
    const phrases = ['하기가 자꾸 귀찮아', '하기가 자꾸 부담돼'];
    final phraseIndex = taskName.codeUnits.fold<int>(
      0,
      (sum, codeUnit) => sum + codeUnit,
    );
    return phrases[phraseIndex % phrases.length];
  }

  String _masterDecisionChipLabel({required bool truncateTaskName}) {
    final taskName = _repeatedlyDeferredTaskName?.trim();
    if (taskName == null || taskName.isEmpty) return '지금 뭐하지?';
    final displayTaskName = truncateTaskName
        ? _truncateResistanceChipTaskName(taskName)
        : taskName;
    return '\'$displayTaskName\' ${_deferredResistancePhrase(taskName)}';
  }

  bool _isRepeatedlyDeferredMasterChip(String chip) {
    if (!_coach.isMaster) return false;
    final taskName = _repeatedlyDeferredTaskName?.trim();
    if (taskName == null || taskName.isEmpty) return false;
    return chip == _masterDecisionChipLabel(truncateTaskName: true);
  }

  String _repeatedlyDeferredMasterChipApiInput() {
    final taskName = _repeatedlyDeferredTaskName?.trim();
    if (taskName == null || taskName.isEmpty) return '지금 뭐하지?';
    return '\'$taskName\' ${_deferredResistancePhrase(taskName)}. 하기 싫어.';
  }

  static const Map<String, String> _broQuickWorkoutChipMessages = {
    '자기 전에 운동 뭐하지?': '자기 전에 가볍게 할 운동 뭐하지?',
    '앉아있는데 뱃살': '앉은 상태로 뱃살 빠지는 법 없어?',
    '지금 앉아있는데 다리 운동': '앉은 상태에서 다리 날씬해지는 운동은?',
    '걷고 있는데 힙업되는 법': '지금 걷고 있는데 힙업되는 법 없을까?',
    '지금 걷고 있는데 팔뚝 살 빼는 법': '걷고 있는데 팔뚝살 빼는 법은?',
    '산책 중인데 뱃살 빠지는 법': '걸으면서 뱃살 빼는 법 있어?',
  };

  bool get _isBroBedtimeWorkoutChipTime => DateTime.now().hour >= 22;

  String get _broReluctantMovementChipLabel {
    final hour = DateTime.now().hour;
    if (hour >= 10 && hour < 17) return '산책하러 나가기 귀찮아';
    return '헬스장 가기 귀찮아';
  }

  String _pickBroQuickWorkoutChipLabel() {
    if (_isBroBedtimeWorkoutChipTime) return '자기 전에 운동 뭐하지?';
    final labels = _broQuickWorkoutChipMessages.keys
        .where((label) => label != '자기 전에 운동 뭐하지?')
        .toList(growable: false);
    return labels[Random().nextInt(labels.length)];
  }

  List<String> _displayChipsForCoach(List<String> chips) {
    final appointmentPrepChip = _appointmentPrepChipLabel(
      truncateTaskName: true,
    );
    if (appointmentPrepChip != null) {
      final replacementChip = switch (_coach.id) {
        'cat' => '오늘 뭐부터 할까',
        'boyfriend' => '오늘 에너지가 없어',
        _ => null,
      };
      if (replacementChip != null && chips.contains(replacementChip)) {
        return chips
            .map((chip) => chip == replacementChip ? appointmentPrepChip : chip)
            .toList(growable: false);
      }
    }
    if (_coach.id == 'cat' && chips.contains('오늘 뭐부터 할까')) {
      return chips
          .map((chip) => chip == '오늘 뭐부터 할까' ? _catPlanningChipLabel : chip)
          .toList(growable: false);
    }
    if (_coach.id != 'bro') return chips;
    if (!chips.contains('지금 할 운동')) return chips;
    final result = chips
        .map(
          (chip) =>
              chip == '헬스장 가기 귀찮아' ? _broReluctantMovementChipLabel : chip,
        )
        .where((chip) => chip != '지금 할 운동')
        .toList();
    result.insert(
      0,
      _isBroBedtimeWorkoutChipTime
          ? '자기 전에 운동 뭐하지?'
          : _broQuickWorkoutChipLabel,
    );
    return result;
  }

  String get _catPlanningChipLabel {
    if (_catTodayEntryCount < 3) return '오늘 뭐부터 할까';
    final hour = DateTime.now().hour;
    if (hour >= 18) return '남은 것 중 뭐하지?';
    if (hour >= 15) return '오늘 어디까지 왔지?';
    return '오늘 뭐부터 할까';
  }

  String _sendTextForChip(String chip, String fallback) {
    if (_isAppointmentPrepChip(chip)) {
      return _appointmentPrepChipLabel(truncateTaskName: false) ?? fallback;
    }
    if (_coach.id == 'bro') {
      final workoutMessage = _broQuickWorkoutChipMessages[chip];
      if (workoutMessage != null) return workoutMessage;
    }
    return fallback;
  }

  // 마스터 칩 앞 FontAwesome 아이콘. 칩 글씨색(코치 accent)에 맞춰 톤을 통일한다.
  Widget? _chipIcon(String chip, {Color? color}) {
    final asset = switch (chip) {
      '마음 비우고 시작' => 'assets/icons/fa-hourglass-half-solid.svg',
      '마음 비우고 하게 해줘' => 'assets/icons/fa-hourglass-half-solid.svg',
      '시작하기가 힘들어' => 'assets/icons/fa-hourglass-half-solid.svg',
      '완벽하게 못 해서 속상해' => 'assets/icons/fa-hourglass-half-solid.svg',
      '지금 뭐하지?' => 'assets/icons/bolt.svg',
      '오늘 핵심 정리해줘' => 'assets/icons/bullseye.svg',
      '내일로 미뤄도 돼?' => 'assets/icons/clock-rotate-left.svg',
      '타이머 띄워줘' => 'assets/icons/fa-stopwatch-solid.svg',
      '수면 도우미' => 'assets/icons/fa-moon-solid.svg',
      '잠이 안 와' => 'assets/icons/fa-moon-solid.svg',
      '오늘은 쉬어가기' => 'assets/icons/fa-moon-solid.svg',
      '오늘은 조금만 하기' => 'assets/icons/paw.svg',
      '돌아가기' => 'assets/icons/fa-arrow-rotate-left-solid.svg',
      _ => null,
    };
    if (asset == null &&
        !_isAppointmentPrepChip(chip) &&
        !_isThoughtOverloadMasterChip(chip) &&
        !_isRepeatedlyDeferredMasterChip(chip)) {
      return null;
    }
    return SvgPicture.asset(
      asset ??
          (_isAppointmentPrepChip(chip)
              ? 'assets/icons/fa-clock-regular.svg'
              : _isThoughtOverloadMasterChip(chip)
              ? 'assets/icons/fa-lightbulb-solid.svg'
              : 'assets/icons/fa-hourglass-half-solid.svg'),
      width: 14,
      height: 14,
      colorFilter: ColorFilter.mode(
        color ?? _coach.accentColor,
        BlendMode.srcIn,
      ),
    );
  }

  Color get _quickChipBackgroundColor {
    return AppDesignTokens.brandChip.withValues(alpha: 0.9);
  }

  Color get _quickChipBorderColor {
    return AppDesignTokens.brandCardBorder.withValues(alpha: 0.82);
  }

  Color get _quickChipForegroundColor {
    return AppDesignTokens.brandPressed;
  }

  List<BoxShadow> get _quickChipShadow {
    return [
      BoxShadow(
        color: AppDesignTokens.brand.withValues(alpha: 0.12),
        blurRadius: 18,
        offset: const Offset(0, 5),
      ),
      BoxShadow(
        color: Colors.white.withValues(alpha: 0.55),
        blurRadius: 8,
        offset: const Offset(0, -1),
      ),
    ];
  }

  BoxDecoration get _quickChipRailDecoration {
    return const BoxDecoration(color: Colors.transparent);
  }

  Widget _buildMasterQuickChip(String chip) {
    final chipInk = _quickChipForegroundColor;
    return AppChip(
      label: chip,
      icon: _chipIcon(chip, color: chipInk),
      backgroundColor: _quickChipBackgroundColor,
      foregroundColor: chipInk,
      borderColor: _quickChipBorderColor,
      boxShadow: _quickChipShadow,
      fontSize: AppDesignTokens.textBody,
      onTap: () {
        if (_coach.isMaster && _isAppointmentPrepChip(chip)) {
          _send(
            _appointmentPrepChipLabel(truncateTaskName: false) ?? chip,
            masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
          );
          return;
        }
        if (chip == '마음 비우고 시작' || chip == '마음 비우고 하게 해줘') {
          _openCountdownFocusMode();
          return;
        }
        if (_isThoughtOverloadMasterChip(chip)) {
          _send(
            _thoughtOverloadChipLabel(truncateTaskName: false),
            apiInputOverride: _thoughtOverloadMasterChipApiInput(),
            masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
          );
          return;
        }
        if (_isRepeatedlyDeferredMasterChip(chip)) {
          _send(
            _masterDecisionChipLabel(truncateTaskName: false),
            apiInputOverride: _repeatedlyDeferredMasterChipApiInput(),
            masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
          );
          return;
        }
        if (_coach.id == 'nyang_halbae' && chip == '시작하기가 힘들어') {
          _handleStartDifficultyChip();
          return;
        }
        if (_coach.id == 'nyang_halbae' && chip == '완벽하게 못 해서 속상해') {
          _handlePerfectionismDistressChip();
          return;
        }
        if (chip == '수면 도우미' || chip == '잠이 안 와') {
          _openSleepAssistMode();
          return;
        }
        if (chip == '지금 뭐하지?') {
          _send(
            '지금 뭐하지?',
            masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
          );
          return;
        }
        _send(chip, masterModelPolicy: _MasterModelPolicy.forceGpt4oMini);
      },
    );
  }

  Widget _buildMasterChipRow() {
    final List<Widget> items = [];
    for (final chip in _masterQuickChips) {
      items.add(_buildMasterQuickChip(chip));
      items.add(const SizedBox(width: 7));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }

  Widget _buildChips() {
    if (_coach.isMaster) {
      return DecoratedBox(
        decoration: _quickChipRailDecoration,
        child: SizedBox(
          height: 46,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildMasterChipRow(),
          ),
        ),
      );
    }
    final baseChips = _suppressDefaultChips
        ? const <String>[]
        : (_dynamicChips.isNotEmpty ? _dynamicChips : _coach.chips);
    final chips = _displayChipsForCoach(baseChips);
    return Container(
      height: 46,
      decoration: _quickChipRailDecoration,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 7),
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (ctx, i) {
          final chip = chips[i];
          final displayLabel = _resistanceChipLabel(
            chip,
            truncateTaskName: true,
          );
          final sendLabel = _sendTextForChip(
            chip,
            _resistanceChipLabel(chip, truncateTaskName: false),
          );
          return AppChip(
            label: displayLabel,
            icon: _chipIcon(chip, color: _quickChipForegroundColor),
            backgroundColor: _quickChipBackgroundColor,
            foregroundColor: _quickChipForegroundColor,
            borderColor: _quickChipBorderColor,
            boxShadow: _quickChipShadow,
            fontSize: AppDesignTokens.textBody,
            onTap: () {
              if (chip == '오늘은 쉬어가기') {
                _activateRestDay();
                return;
              }
              if (chip == '오늘은 조금만 하기') {
                _chooseLightDay();
                return;
              }
              if (_coach.isMaster && chip == '마음 비우고 시작') {
                _openCountdownFocusMode();
                return;
              }
              if (_coach.isMaster && _isThoughtOverloadMasterChip(chip)) {
                _send(
                  _thoughtOverloadChipLabel(truncateTaskName: false),
                  apiInputOverride: _thoughtOverloadMasterChipApiInput(),
                  masterModelPolicy: _MasterModelPolicy.forceGpt4oMini,
                );
                return;
              }
              if (_coach.isMaster && chip == '마음 비우고 하게 해줘') {
                _openCountdownFocusMode();
                return;
              }
              _send(sendLabel);
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
                                            ? Colors.white.withOpacity(
                                                isMasterVacation ? 0.6 : 0.3,
                                              )
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
                                          ? Colors.white
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
                                      ? Colors.white.withOpacity(0.3)
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
                                      ? Colors.white
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
                                        ? Colors.white.withOpacity(0.6)
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

  String _getTodayStrWithReset(SharedPreferences _) {
    const resetHour = 0.0;
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

    final habitFreqById = _habitFrequencyById(prefs);
    final countableTasks = tasksList.where((t) {
      if (t is! Map) return false;
      return _countsTowardDailyCompletion(
        Map<String, dynamic>.from(t),
        habitFreqById,
      );
    }).toList();
    final doneTasks = countableTasks.where((t) => t['done'] == true).toList();

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
      'totalCount': countableTasks.length,
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
