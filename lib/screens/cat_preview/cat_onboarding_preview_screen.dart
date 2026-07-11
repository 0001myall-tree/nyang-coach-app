import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_design_tokens.dart';
import '../../widgets/cat_onboarding_cta.dart';
import '../coach_config.dart';

/// 냥냥코치 무료체험 진입 시 보여주는 15초 안팎의 자동 시연 화면.
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
  static const _tUser1 = 0;
  static const _tCoachTyping = 1500;
  static const _tCoachBubble1 = 2500;
  static const _tTimerStart = 3400;
  static const _tTimerDone = _tTimerStart + 2500;
  static const _tCoachFeedback = _tTimerDone + 1000;
  static const _tMicActive = _tCoachFeedback + 1700;
  static const _tTypingStart = _tMicActive + 600;
  static const _tTypingDurationMs = 1800;
  static const _tUser2Sent = _tTypingStart + _tTypingDurationMs;
  static const _tScheduleDialogShow = _tUser2Sent + 300;
  static const _tScheduleDialogConfirm = _tScheduleDialogShow + 1000;
  static const _tScheduleDialogHide = _tScheduleDialogConfirm + 400;
  static const _tPlannerReveal = _tScheduleDialogHide + 300;
  static const _tCoachReminderAsk = _tPlannerReveal + 1800;
  static const _tUserReminderYes = _tCoachReminderAsk + 1200;
  static const _tReminderToggleOn = _tUserReminderYes + 700;
  static const _tCoachClosing = _tReminderToggleOn + 600;
  static const _tTotal = _tCoachClosing + 2000;

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

  bool get _showCoachFeedback => _elapsedMs >= _tCoachFeedback;
  bool get _micActive => _elapsedMs >= _tMicActive && _elapsedMs < _tUser2Sent;

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
  bool get _showPlannerPanel => _elapsedMs >= _tPlannerReveal;
  bool get _showCoachReminderAsk => _elapsedMs >= _tCoachReminderAsk;
  bool get _showUserReminderYes => _elapsedMs >= _tUserReminderYes;
  bool get _reminderOn => _elapsedMs >= _tReminderToggleOn;
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
                      if (_showCoachFeedback)
                        _coachBubble(
                          '잘했어 🎉\n시작한 것만으로도 오늘은 충분히 잘하고 있어.\n오늘 하루도 천천히 같이 가보자.',
                        ),
                      if (_showUser2) _userBubble(_userTypedFull),
                      if (_showPlannerPanel) _plannerPanel(),
                      if (_showCoachReminderAsk)
                        _coachBubble('일정 알림을 켜두면 회의 10분 전에 미리 알려줄게.'),
                      if (_showUserReminderYes) _userBubble('오, 그럼 켜둘게!'),
                      if (_showCoachClosing)
                        _coachBubble('하기 싫을 때나, 머릿속이 복잡해질 때\n언제든 나한테 말해.\n내가 도와줄게.'),
                    ],
                  ),
                ),
                _buildFakeInputBar(),
              ],
            ),
            if (_showScheduleDialog) _scheduleDialogOverlay(),
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

  Widget _coachBubble(String text) {
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
              child: Text(
                text,
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textBody,
                  color: AppDesignTokens.textPrimary,
                  height: 1.4,
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

  // ── 가짜 5분 타이머 카드 ──────────────────────────────
  Widget _timerCard() {
    return Container(
      margin: const EdgeInsets.only(left: 44, bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDesignTokens.cardRadius),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppDesignTokens.brand),
              const SizedBox(width: 8),
              Text(
                '스트레칭 타이머',
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_timerDone) ...[
            Center(
              child: Text(
                _timerLabel,
                style: GoogleFonts.notoSansKr(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: AppDesignTokens.brand,
                ),
              ),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _timerFraction,
                minHeight: 8,
                backgroundColor: AppDesignTokens.brandSoft,
                valueColor: const AlwaysStoppedAnimation(AppDesignTokens.brand),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _timerRunning
                      ? AppDesignTokens.brandDisabled
                      : AppDesignTokens.brand,
                  disabledBackgroundColor: _timerRunning
                      ? AppDesignTokens.brandDisabled
                      : AppDesignTokens.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.buttonRadius,
                    ),
                  ),
                ),
                child: Text(
                  _timerRunning ? '진행 중...' : '타이머 시작',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ] else
            Center(
              child: Column(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Color(0xFF5AD7B0),
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '스트레칭 완료!',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF5AD7B0),
                    ),
                  ),
                ],
              ),
            ),
        ],
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
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppDesignTokens.surfaceSubtle,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                _typedText.isEmpty ? ' ' : _typedText,
                style: GoogleFonts.notoSansKr(
                  fontSize: 14,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
              color: _micActive ? Colors.white : AppDesignTokens.textMuted,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  // ── 가짜 일정 등록 다이얼로그 ─────────────────────────
  Widget _scheduleDialogOverlay() {
    return Container(
      color: Colors.black45,
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusLarge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('📅', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  '일정 추가',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppDesignTokens.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '일정',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            Text(
              '온라인 회의',
              style: GoogleFonts.notoSansKr(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              '시간',
              style: GoogleFonts.notoSansKr(
                fontSize: 12,
                color: AppDesignTokens.textSecondary,
              ),
            ),
            Text(
              '${_todayLabel()} 오후 10:00',
              style: GoogleFonts.notoSansKr(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _scheduleConfirmPressed
                      ? AppDesignTokens.brandPressed
                      : AppDesignTokens.brand,
                  disabledBackgroundColor: _scheduleConfirmPressed
                      ? AppDesignTokens.brandPressed
                      : AppDesignTokens.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppDesignTokens.buttonRadius,
                    ),
                  ),
                ),
                child: Text(
                  '등록',
                  style: GoogleFonts.notoSansKr(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _todayLabel() {
    final now = DateTime.now();
    return '${now.month}월 ${now.day}일';
  }

  // ── 미니 "오늘 할 일" 패널 (강조 표시) ────────────────
  Widget _plannerPanel() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDesignTokens.cardRadius),
        boxShadow: AppDesignTokens.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 오늘 할 일',
            style: GoogleFonts.notoSansKr(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppDesignTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppDesignTokens.brandSoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppDesignTokens.brand, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.arrow_right_alt_rounded,
                  color: AppDesignTokens.brand,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '온라인 회의',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppDesignTokens.textPrimary,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      _reminderOn
                          ? Icons.notifications_active
                          : Icons.notifications_none_outlined,
                      size: 16,
                      color: _reminderOn
                          ? AppDesignTokens.brand
                          : AppDesignTokens.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '22:00',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.brand,
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
}
