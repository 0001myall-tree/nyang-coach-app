import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_design_tokens.dart';
import '../../widgets/cat_onboarding_cta.dart';
import '../coach_config.dart';

/// 냥냥코치 무료체험 진입 시 보여주는 자동 시연 화면.
/// 실제 채팅/일정/타이머/알림 데이터는 전혀 건드리지 않는, 순수 스크립트 재생 화면이다.
/// 끝나면(또는 건너뛰면) 마지막 CTA를 보여주고, 그 결과(true = 플랜 시작하기)를
/// pop 결과로 돌려준다.
class CatOnboardingPreviewScreen extends StatefulWidget {
  const CatOnboardingPreviewScreen({super.key});

  @override
  State<CatOnboardingPreviewScreen> createState() =>
      _CatOnboardingPreviewScreenState();
}

class _CatOnboardingPreviewScreenState
    extends State<CatOnboardingPreviewScreen> {
  // ── 타임라인 (ms, 시연 시작 이후 누적 경과 시간 기준) ──────────
  // 실제 채팅 리듬에 가깝게, 넉넉한 간격으로 잡는다 (총 20~30초대 목표치).
  static const _tUser1 = 0;
  static const _tCoachTyping = 1200;
  static const _tCoachBubble1 = 2600;
  static const _tTimerStart = 4200;
  static const _tTimerDone = _tTimerStart + 3200;
  static const _tUserStretchDone = _tTimerDone + 700;
  static const _tCoachFeedback = _tUserStretchDone + 1500;
  static const _tMicActive = _tCoachFeedback + 2400;
  // 마이크로 듣고 있는 구간(동심원 애니메이션 + '마이크로 말하는 중' 라벨).
  static const _tListeningDurationMs = 2200;
  static const _tTypingStart = _tMicActive + _tListeningDurationMs;
  // 듣기가 끝난 뒤 인식된 문장이 입력창에 나타나는 구간 (타이핑이 아니라
  // 음성 인식 결과가 채워지는 느낌이라 짧게).
  static const _tTypingDurationMs = 900;
  static const _tUser2Sent = _tTypingStart + _tTypingDurationMs;
  static const _tScheduleDialogShow = _tUser2Sent + 400;
  static const _tScheduleDialogConfirm = _tScheduleDialogShow + 1600;
  static const _tScheduleDialogHide = _tScheduleDialogConfirm + 500;
  static const _tDrawerOpen = _tScheduleDialogHide + 400;
  static const _drawerSlideMs = 400;
  static const _tDrawerReminderTip = _tDrawerOpen + 1800;
  static const _tDrawerReminderOn = _tDrawerReminderTip + 1400;
  static const _tDrawerClose = _tDrawerReminderOn + 1600;
  static const _tCoachClosing = _tDrawerClose + _drawerSlideMs + 500;
  static const _tTotal = _tCoachClosing + 4000;

  static const _userTypedFull = '맞다.\n오늘 밤 10시에 온라인 회의 추가해줘.';

  int _elapsedMs = 0;
  bool _paused = false;
  bool _finished = false;
  Timer? _ticker;
  final ScrollController _scrollCtrl = ScrollController();

  CoachConfig get _cat => CoachConfigs.all['cat']!;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), _onTick);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTick(Timer timer) {
    if (_paused || _finished) return;
    setState(() => _elapsedMs += 100);
    _autoScroll();
    if (_elapsedMs >= _tTotal) {
      _finish();
    }
  }

  void _autoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _togglePause() => setState(() => _paused = !_paused);

  void _skip() {
    _ticker?.cancel();
    _finish();
  }

  Future<void> _finish() async {
    if (_finished) return;
    _finished = true;
    _ticker?.cancel();
    final startPlan = await showCatOnboardingCta(context);
    if (!mounted) return;
    Navigator.of(context).pop(startPlan);
  }

  // ── 파생 상태 (경과 시간 기반) ────────────────────────────
  bool get _showUser1 => _elapsedMs >= _tUser1;
  bool get _showCoachTyping =>
      _elapsedMs >= _tCoachTyping && _elapsedMs < _tCoachBubble1;
  bool get _showCoachBubble1 => _elapsedMs >= _tCoachBubble1;
  bool get _timerRunning =>
      _elapsedMs >= _tTimerStart && _elapsedMs < _tTimerDone;
  bool get _timerDone => _elapsedMs >= _tTimerDone;

  double get _timerFraction {
    if (_elapsedMs < _tTimerStart) return 0;
    if (_elapsedMs >= _tTimerDone) return 1;
    return (_elapsedMs - _tTimerStart) / (_tTimerDone - _tTimerStart);
  }

  String get _timerLabel {
    const totalSec = 5 * 60;
    final remain = (totalSec * (1 - _timerFraction)).round();
    final m = remain ~/ 60;
    final s = remain % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  bool get _showUserStretchDone => _elapsedMs >= _tUserStretchDone;
  bool get _showCoachFeedback => _elapsedMs >= _tCoachFeedback;
  bool get _micActive => _elapsedMs >= _tMicActive && _elapsedMs < _tUser2Sent;
  bool get _listening =>
      _elapsedMs >= _tMicActive && _elapsedMs < _tTypingStart;

  // 마이크 주변 동심원(리플) 애니메이션 진행률. 링마다 위상을 살짝 어긋나게 줘서
  // 계속 퍼져나가는 것처럼 보이게 한다. 0(막 시작)~1(다 퍼져서 사라짐).
  double _rippleProgress(int ringIndex) {
    if (!_listening) return 0;
    const cycleMs = 1000;
    final sinceListenStart = _elapsedMs - _tMicActive;
    final phase = (sinceListenStart + ringIndex * (cycleMs ~/ 3)) % cycleMs;
    return phase / cycleMs;
  }

  String get _typedText {
    if (_elapsedMs < _tTypingStart) return '';
    if (_elapsedMs >= _tUser2Sent) return '';
    final progress = ((_elapsedMs - _tTypingStart) / _tTypingDurationMs).clamp(
      0.0,
      1.0,
    );
    final chars = (_userTypedFull.length * progress).round();
    return _userTypedFull.substring(0, chars);
  }

  bool get _showUser2 => _elapsedMs >= _tUser2Sent;
  bool get _showScheduleDialog =>
      _elapsedMs >= _tScheduleDialogShow && _elapsedMs < _tScheduleDialogHide;
  bool get _scheduleConfirmPressed => _elapsedMs >= _tScheduleDialogConfirm;

  // 오른쪽에서 서랍처럼 열리는 "오늘의 할 일" 탭 미리보기.
  double get _drawerFraction {
    if (_elapsedMs < _tDrawerOpen) return 0;
    if (_elapsedMs < _tDrawerOpen + _drawerSlideMs) {
      return (_elapsedMs - _tDrawerOpen) / _drawerSlideMs;
    }
    if (_elapsedMs < _tDrawerClose) return 1;
    if (_elapsedMs < _tDrawerClose + _drawerSlideMs) {
      return 1 - (_elapsedMs - _tDrawerClose) / _drawerSlideMs;
    }
    return 0;
  }

  bool get _showReminderTip =>
      _elapsedMs >= _tDrawerReminderTip && _elapsedMs < _tDrawerClose;
  bool get _reminderOn => _elapsedMs >= _tDrawerReminderOn;
  bool get _showCoachClosing => _elapsedMs >= _tCoachClosing;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppDesignTokens.surfaceSubtle,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildControlBar(),
                Expanded(
                  child: ListView(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      if (_showUser1) _userBubble('오늘 늦잠 잤어... 아무것도 하기 싫다.'),
                      if (_showCoachTyping) _typingIndicator(),
                      if (_showCoachBubble1) ...[
                        _coachBubble(
                          '그럴 때 있지.\n근데 아직 늦지 않았어.\n스트레칭 5분만 해보는 거 어때?\n기분 나아질 거야.',
                        ),
                        _timerCard(),
                      ],
                      if (_showUserStretchDone) _userBubble('덕분에 스트레칭 했어ㅎㅎ'),
                      if (_showCoachFeedback)
                        _coachBubble(
                          '오~ 내가 해낼 줄 알았지.\n우리 집사 최고',
                          trailingIconAsset: 'assets/icons/heart.svg',
                        ),
                      if (_showUser2) _userBubble(_userTypedFull),
                      if (_showCoachClosing)
                        _coachBubble(
                          '지금처럼 하기 싫거나 머릿속이 복잡할 때\n언제든 말해. 내가 도와줄게',
                          trailingIconAsset: 'assets/icons/paw.svg',
                        ),
                    ],
                  ),
                ),
                _buildFakeInputBar(),
              ],
            ),
            if (_showScheduleDialog) _scheduleDialogOverlay(),
            if (_drawerFraction > 0) _taskDrawerOverlay(context),
          ],
        ),
      ),
    );
  }

  // ── 상단 재생 컨트롤 바 ────────────────────────────────
  Widget _buildControlBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            '냥냥코치 미리보기',
            style: GoogleFonts.notoSansKr(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _togglePause,
            icon: Icon(
              _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: AppDesignTokens.brand,
            ),
            tooltip: _paused ? '재생' : '일시정지',
          ),
          TextButton(
            onPressed: _skip,
            child: Text(
              '건너뛰기',
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 말풍선 ────────────────────────────────────────────
  Widget _userBubble(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _cat.accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDesignTokens.radiusLarge),
                  topRight: Radius.circular(AppDesignTokens.radiusLarge),
                  bottomLeft: Radius.circular(AppDesignTokens.radiusLarge),
                  bottomRight: Radius.circular(4),
                ),
                boxShadow: AppDesignTokens.bubbleShadow,
              ),
              child: Text(
                text,
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textBody,
                  color: Colors.white,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coachAvatar() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Image.asset(
        _cat.imagePath,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        errorBuilder: (_, __, ___) => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _cat.accentLight,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.pets, color: _cat.accentColor, size: 20),
        ),
      ),
    );
  }

  Widget _coachBubble(String text, {String? trailingIconAsset}) {
    final textStyle = GoogleFonts.notoSansKr(
      fontSize: AppDesignTokens.textBody,
      color: AppDesignTokens.textPrimary,
      height: 1.4,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _coachAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDesignTokens.radiusLarge),
                  topRight: Radius.circular(AppDesignTokens.radiusLarge),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(AppDesignTokens.radiusLarge),
                ),
                boxShadow: AppDesignTokens.bubbleShadow,
              ),
              child: trailingIconAsset == null
                  ? Text(text, style: textStyle)
                  : Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: text, style: textStyle),
                          const WidgetSpan(child: SizedBox(width: 4)),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: SvgPicture.asset(
                              trailingIconAsset,
                              width: 16,
                              height: 16,
                              colorFilter: const ColorFilter.mode(
                                AppDesignTokens.brand,
                                BlendMode.srcIn,
                              ),
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

  Widget _typingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _coachAvatar(),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppDesignTokens.radiusLarge),
                topRight: Radius.circular(AppDesignTokens.radiusLarge),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(AppDesignTokens.radiusLarge),
              ),
              boxShadow: AppDesignTokens.bubbleShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppDesignTokens.textDisabled,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 가짜 5분 타이머 카드 (실제 focus_timer_widget.dart 프렌즈 코치용
  // 카드와 동일한 톤: '집중 시간' 헤더, 큰 시간 숫자, 단계 칩, 시작/완료 뷰) ──
  Widget _timerCard() {
    const mainPurple = Color(0xFF7C6BEA);
    const softPurple = Color(0xFFF7F3FF);
    const borderPurple = Color(0xFFE7DDFC);

    return Container(
      margin: const EdgeInsets.only(left: 44, bottom: 12, top: 2),
      child: FractionallySizedBox(
        widthFactor: 0.88,
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderPurple, width: 1),
            boxShadow: [
              BoxShadow(
                color: mainPurple.withValues(alpha: 0.10),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: !_timerDone
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '집중 시간',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF7E73C8),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _timerLabel,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                        color: mainPurple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _timerRunning ? '총 5분 집중 중' : '5분 집중 준비',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF8B7DE0),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: mainPurple,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Center(
                        child: Text(
                          '5분',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(height: 1, color: const Color(0xFFF0ECFA)),
                    const SizedBox(height: 12),
                    Container(
                      width: 116,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: softPurple,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderPurple, width: 1),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _timerRunning
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 18,
                            color: mainPurple,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _timerRunning ? '일시정지' : '시작',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF5F52C6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFF3EEFF),
                        border: Border.all(color: borderPurple, width: 1),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 30,
                        color: mainPurple,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '집중 완료',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF4E438F),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '5분 스트레칭을 마쳤어요.',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8B7DE0),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── 하단 가짜 입력창 (마이크 + 타이핑 애니메이션) ─────────
  Widget _buildFakeInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppDesignTokens.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceSubtle,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                _listening
                    ? '듣고 있어요...'
                    : (_typedText.isEmpty ? ' ' : _typedText),
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontStyle: _listening ? FontStyle.italic : FontStyle.normal,
                  color: _listening
                      ? AppDesignTokens.textMuted
                      : AppDesignTokens.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (_listening) ...List.generate(3, (i) => _micRipple(i)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _micActive
                        ? AppDesignTokens.brand
                        : AppDesignTokens.surfaceSubtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.mic_none_rounded,
                    color: _micActive
                        ? Colors.white
                        : AppDesignTokens.textMuted,
                    size: 20,
                  ),
                ),
                if (_listening) Positioned(top: -34, child: _listeningLabel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 마이크 주위로 퍼지는 동심원(리플) — 소리가 입력되고 있다는 걸 보여준다.
  Widget _micRipple(int ringIndex) {
    final progress = _rippleProgress(ringIndex);
    final scale = 1.0 + progress * 0.9;
    final opacity = (1.0 - progress) * 0.45;
    return Transform.scale(
      scale: scale,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: AppDesignTokens.brand.withValues(alpha: opacity),
            width: 2,
          ),
        ),
      ),
    );
  }

  // 마이크 위에 뜨는 "마이크로 말하는 중" 캡션.
  Widget _listeningLabel() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppDesignTokens.brand,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppDesignTokens.bubbleShadow,
      ),
      child: Text(
        '마이크로 말하는 중',
        style: GoogleFonts.notoSansKr(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }

  // ── 가짜 일정 등록 다이얼로그 (실제 _showScheduleRegistrationDialog와
  // 동일한 칩 스타일 + 연보라 아이콘, 눈에 띄는 보라색 "추가하기" 버튼) ──
  Widget _scheduleDialogOverlay() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 32),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _iconGlyph('assets/icons/thumbtack.svg', size: 15),
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
            const SizedBox(height: 18),
            Text(
              '온라인 회의',
              style: GoogleFonts.notoSansKr(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: const Color(0xFF1E1E2D),
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip(
                  'assets/icons/planner-calendar-days.svg',
                  _todayLabel(),
                  const Color(0xFFF3F4F6),
                  const Color(0xFF4B5563),
                ),
                _chip(
                  'assets/icons/planner-clock.svg',
                  '오후 10:00',
                  const Color(0xFFF5F3FF),
                  const Color(0xFF8B7CFF),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF1E1E2D), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _iconGlyph('assets/icons/bell.svg', size: 13),
                  const SizedBox(width: 6),
                  Text(
                    '알람 ON',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1E1E2D),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            AnimatedScale(
              scale: _scheduleConfirmPressed ? 0.96 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppDesignTokens.brand,
                    disabledBackgroundColor: AppDesignTokens.brand,
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '추가하기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _scheduleConfirmPressed
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        color: Colors.white,
                        size: 18,
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
  }

  Widget _chip(String iconAsset, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _iconGlyph(iconAsset, size: 13),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  // 시연 화면 전반에서 쓰는 이모지 대체 아이콘 — 플래너 디자인 톤(연보라)으로 통일.
  Widget _iconGlyph(String assetPath, {double size = 14}) {
    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      colorFilter: const ColorFilter.mode(
        AppDesignTokens.brand,
        BlendMode.srcIn,
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일';
  }

  // ── 오른쪽에서 서랍처럼 열리는 "오늘의 할 일" 탭 미리보기 ─────
  // 실제 tasks_screen.dart 오늘 할 일 화면 톤(날짜, 진행률, 카드형 할일 목록)을
  // 흉내 내어, 새로 등록된 일정이 어떻게 플래너에 반영되는지 학습할 수 있게 한다.
  Widget _taskDrawerOverlay(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 0.86;
    return Stack(
      children: [
        // 어두운 스크림
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.35 * _drawerFraction),
          ),
        ),
        // 오른쪽에서 슬라이드되어 들어오는 패널
        Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          width: drawerWidth,
          child: FractionalTranslation(
            translation: Offset(1 - _drawerFraction, 0),
            child: Material(
              elevation: 12,
              color: Colors.white,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _todayFullLabel(),
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          color: AppDesignTokens.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _iconGlyph('assets/icons/paw.svg', size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '오늘의 할 일',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              color: AppDesignTokens.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: 0.6,
                          minHeight: 8,
                          backgroundColor: AppDesignTokens.brandSoft,
                          valueColor: const AlwaysStoppedAnimation(
                            AppDesignTokens.brand,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _fakeTaskRow(
                        done: true,
                        text: '스트레칭하기',
                        badgeText: '⏱ 5분',
                        highlighted: false,
                      ),
                      const SizedBox(height: 8),
                      _fakeTaskRow(
                        done: false,
                        text: '온라인 회의',
                        badgeText: '오후 10:00',
                        highlighted: true,
                      ),
                      const Spacer(),
                      if (_showReminderTip) _reminderTipCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reminderTipCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppDesignTokens.brandSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconGlyph('assets/icons/bell.svg', size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '일정 알림을 켜두면 회의 10분 전에\n미리 알려드려요.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppDesignTokens.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _reminderOn ? Icons.toggle_on : Icons.toggle_off_outlined,
                      size: 28,
                      color: _reminderOn
                          ? AppDesignTokens.brand
                          : AppDesignTokens.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _reminderOn ? '알림 켜짐' : '알림 꺼짐',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _reminderOn
                            ? AppDesignTokens.brand
                            : AppDesignTokens.textMuted,
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

  Widget _fakeTaskRow({
    required bool done,
    required String text,
    required String badgeText,
    required bool highlighted,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlighted ? AppDesignTokens.brandSoft : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? AppDesignTokens.brand : const Color(0xFFE8E3F8),
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: highlighted ? AppDesignTokens.cardShadow : null,
      ),
      child: Row(
        children: [
          if (highlighted) ...[
            Icon(Icons.arrow_right_alt_rounded, color: AppDesignTokens.brand),
            const SizedBox(width: 4),
          ] else
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: done ? AppDesignTokens.brand : Colors.transparent,
                border: Border.all(
                  color: done ? AppDesignTokens.brand : const Color(0xFFD1D5DB),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: done
                  ? const Icon(Icons.check, color: Colors.white, size: 13)
                  : null,
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.notoSansKr(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textPrimary,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationColor: AppDesignTokens.textMuted,
              ),
            ),
          ),
          Text(
            badgeText,
            style: GoogleFonts.notoSansKr(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: highlighted
                  ? AppDesignTokens.brand
                  : AppDesignTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  String _todayFullLabel() {
    final now = DateTime.now();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final w = weekdays[now.weekday - 1];
    return '${now.year}년 ${now.month}월 ${now.day}일 ($w)';
  }
}
