import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────
// 포커스 타이머 위젯 (웹앱 masterTimer 그대로 이식)
// ─────────────────────────────────────────────────────────────
class FocusTimerWidget extends StatefulWidget {
  final String coachId;
  final int initialMinutes;
  final void Function(String msg) onMessage; // 채팅창에 메시지 추가

  const FocusTimerWidget({
    super.key,
    required this.coachId,
    required this.initialMinutes,
    required this.onMessage,
  });

  @override
  State<FocusTimerWidget> createState() => _FocusTimerWidgetState();
}

class _FocusTimerWidgetState extends State<FocusTimerWidget> {
  late int _stage;      // 선택된 분 (5, 15, 25)
  late int _totalSec;
  late int _remainSec;
  bool _running = false;
  Timer? _timer;

  // 웹앱 _masterTimerMsgs 그대로
  static const _msgs = {
    'sec_male': {
      5: {'start': '5분입니다. 저도 옆에서 대기하겠습니다.', 'done': '...끝났네요. 생각보다 잘 하셨습니다.'},
      15: {'start': '15분 시작합니다. 이 흐름 그대로 가시면 됩니다.', 'done': '15분 완료입니다. 조금 더 하실 수 있을 것 같은데요?'},
      25: {'start': '25분입니다. 집중하세요. 제가 지켜보고 있겠습니다.', 'done': '수고하셨습니다. 오늘 집중 시간, 제가 기억해두겠습니다.'},
    },
    'sec_female': {
      5: {'start': '5분만요. 저도 여기서 같이 있을게요.', 'done': '수고하셨어요. 어때요, 할 만하죠? 🌸'},
      15: {'start': '15분 시작해요. 제가 곁에서 응원하고 있을게요.', 'done': '15분 해내셨어요! 조금 더 이어가볼까요?'},
      25: {'start': '25분이에요. 무리하지 말고 대표님 페이스대로 가요.', 'done': '정말 수고하셨어요. 오늘 집중 시간이 참 뿌듯하네요. 🌸'},
    },
  };

  bool get _isMale => widget.coachId == 'sec_male';

  // 남비서: 다크 / 여비서: 로즈
  List<Color> get _cardGradient => _isMale
      ? [const Color(0xFF1A1A2E), const Color(0xFF2D2A4E)]
      : [const Color(0xFFBE185D), const Color(0xFFDB2777)];

  Color get _ringColor => _isMale
      ? const Color(0xFFA78BFA)
      : const Color(0xFFFDE8F0);

  Color get _ringTrack => _isMale
      ? Colors.white.withOpacity(0.1)
      : Colors.white.withOpacity(0.2);

  Color get _labelColor => _isMale
      ? const Color(0xFFC4B5FD)
      : const Color(0xFFFDE8F0);

  @override
  void initState() {
    super.initState();
    _stage = widget.initialMinutes;
    _totalSec = _stage * 60;
    _remainSec = _totalSec;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _setStage(int min) {
    if (_running) return;
    setState(() {
      _stage = min;
      _totalSec = min * 60;
      _remainSec = _totalSec;
    });
  }

  void _toggle() {
    if (_running) {
      // 일시정지
      _timer?.cancel();
      setState(() => _running = false);
    } else {
      // 시작
      final isFirst = _remainSec == _totalSec;
      setState(() => _running = true);
      if (isFirst) {
        final msg = (_msgs[widget.coachId] ?? _msgs['sec_male']!)[_stage]!['start']!;
        Future.delayed(const Duration(milliseconds: 300), () => widget.onMessage(msg));
      }
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _remainSec--);
        if (_remainSec <= 0) {
          t.cancel();
          setState(() => _running = false);
          final msg = (_msgs[widget.coachId] ?? _msgs['sec_male']!)[_stage]!['done']!;
          Future.delayed(const Duration(milliseconds: 600), () => widget.onMessage(msg));
        }
      });
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _running = false;
      _remainSec = _totalSec;
    });
  }

  String get _timeDisplay {
    final m = (_remainSec ~/ 60).toString().padLeft(2, '0');
    final s = (_remainSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress => _remainSec / _totalSec;

  @override
  Widget build(BuildContext context) {
    final stageLabels = {5: '5분 집중', 15: '15분 집중', 25: '25분 집중'};
    final isDone = _remainSec <= 0;

    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── 헤더 (그라디언트 배경) ──────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _cardGradient,
                ),
              ),
              child: Column(
                children: [
                  // FOCUS TIMER 레이블
                  Text(
                    '⏱ FOCUS TIMER',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: _labelColor.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 원형 타이머
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // SVG 원형 프로그레스
                        CustomPaint(
                          size: const Size(140, 140),
                          painter: _TimerRingPainter(
                            progress: _progress,
                            ringColor: _ringColor,
                            trackColor: _ringTrack,
                          ),
                        ),
                        // 시간 표시
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeDisplay,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 30,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1,
                              ),
                            ),
                            Text(
                              isDone
                                  ? '완료!'
                                  : _running
                                      ? '${_stage}분 집중 중'
                                      : stageLabels[_stage] ?? '${_stage}분',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _labelColor.withOpacity(0.85),
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 단계 선택 버튼 (5, 15, 25)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [5, 15, 25].map((m) {
                      final isActive = _stage == m;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => _setStage(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '${m}분',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isActive
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            // ── 컨트롤 영역 (흰 배경) ──────────────────────
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  // 시작/일시정지 버튼
                  Expanded(
                    child: GestureDetector(
                      onTap: isDone ? null : _toggle,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: _cardGradient,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            isDone
                                ? '완료 🎉'
                                : _running
                                    ? '⏸ 일시정지'
                                    : '▶ 시작',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 리셋 버튼
                  GestureDetector(
                    onTap: _reset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFE5E7EB), width: 1.5),
                      ),
                      child: Text(
                        '↺',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
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
}

// ── 원형 링 페인터 (웹앱 SVG 그대로) ───────────────────────
class _TimerRingPainter extends CustomPainter {
  final double progress; // 1.0 → 0.0
  final Color ringColor;
  final Color trackColor;

  const _TimerRingPainter({
    required this.progress,
    required this.ringColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 7;
    const strokeWidth = 7.0;

    // 트랙 (배경 링)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );

    // 진행 링
    final circumference = 2 * pi * radius;
    final sweepAngle = 2 * pi * progress;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // 12시 방향에서 시작
      sweepAngle,
      false,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress ||
      old.ringColor != ringColor ||
      old.trackColor != trackColor;
}
