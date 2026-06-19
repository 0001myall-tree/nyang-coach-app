import 'dart:async';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart';
import '../services/notification_service.dart';


// ─────────────────────────────────────────────────────────────
// 타이머 화면 상태
// ─────────────────────────────────────────────────────────────
enum _TimerView { timer, done, soundOnly }


// ─────────────────────────────────────────────────────────────
// 포커스 타이머 상태 매니저
// ─────────────────────────────────────────────────────────────
class FocusTimerManager {
  static final FocusTimerManager _instance = FocusTimerManager._internal();
  factory FocusTimerManager() => _instance;
  FocusTimerManager._internal();

  DateTime? startTime;
  int duration = 0;
  int? pausedRemainSec;
  bool running = false;
  String? coachId;
  int stage = 25;

  Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    running = prefs.getBool('focus_timer_running') ?? false;
    stage = prefs.getInt('focus_timer_stage') ?? 25;
    duration = prefs.getInt('focus_timer_duration') ?? (stage * 60);
    coachId = prefs.getString('focus_timer_coach_id');
    final startStr = prefs.getString('focus_timer_start_time');
    startTime = startStr != null ? DateTime.tryParse(startStr) : null;
    pausedRemainSec = prefs.getInt('focus_timer_paused_remain');
  }

  Future<void> saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('focus_timer_running', running);
    await prefs.setInt('focus_timer_stage', stage);
    await prefs.setInt('focus_timer_duration', duration);
    if (coachId != null) {
      await prefs.setString('focus_timer_coach_id', coachId!);
    } else {
      await prefs.remove('focus_timer_coach_id');
    }
    if (startTime != null) {
      await prefs.setString('focus_timer_start_time', startTime!.toIso8601String());
    } else {
      await prefs.remove('focus_timer_start_time');
    }
    if (pausedRemainSec != null) {
      await prefs.setInt('focus_timer_paused_remain', pausedRemainSec!);
    } else {
      await prefs.remove('focus_timer_paused_remain');
    }
  }

  int getRemainSeconds() {
    if (!running) return pausedRemainSec ?? duration;
    if (startTime == null) return duration;
    final elapsed = DateTime.now().difference(startTime!).inSeconds;
    final remain = duration - elapsed;
    return remain > 0 ? remain : 0;
  }

  Future<void> start(int min, String coachId) async {
    running = true;
    stage = min;
    duration = min * 60;
    this.coachId = coachId;
    pausedRemainSec = null;
    startTime = DateTime.now();
    await saveState();
    await NotificationService().scheduleFocusTimerNotification(
      seconds: duration,
      coachId: coachId,
    );
  }

  /// 일시정지 후 재개 — 남은 시간 기준으로 startTime 역산
  Future<void> resume() async {
    if (running) return;
    final remain = pausedRemainSec ?? duration;
    running = true;
    pausedRemainSec = null;
    startTime = DateTime.now().subtract(Duration(seconds: duration - remain));
    await saveState();
    await NotificationService().scheduleFocusTimerNotification(
      seconds: remain,
      coachId: coachId ?? 'sec_male',
    );
  }

  Future<void> pause() async {
    if (!running) return;
    final remain = getRemainSeconds();
    running = false;
    pausedRemainSec = remain;
    startTime = null;
    await saveState();
    await NotificationService().cancelFocusTimerNotification();
  }

  Future<void> reset(int min) async {
    running = false;
    stage = min;
    duration = min * 60;
    pausedRemainSec = null;
    startTime = null;
    await saveState();
    await NotificationService().cancelFocusTimerNotification();
  }

  Future<int> getTodayCompletedCount() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    var baseToday = DateTime(now.year, now.month, now.day);
    if (now.hour < 3) baseToday = baseToday.subtract(const Duration(days: 1));
    final todayStr =
        '${baseToday.year}-${baseToday.month.toString().padLeft(2, '0')}-${baseToday.day.toString().padLeft(2, '0')}';
    return prefs.getInt('focus_timer_done_$todayStr') ?? 0;
  }

  Future<void> incrementTodayCount() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    var baseToday = DateTime(now.year, now.month, now.day);
    if (now.hour < 3) baseToday = baseToday.subtract(const Duration(days: 1));
    final todayStr =
        '${baseToday.year}-${baseToday.month.toString().padLeft(2, '0')}-${baseToday.day.toString().padLeft(2, '0')}';
    final key = 'focus_timer_done_$todayStr';
    final cur = prefs.getInt(key) ?? 0;
    await prefs.setInt(key, cur + 1);
  }
}


// ─────────────────────────────────────────────────────────────
// 포커스 타이머 위젯
// ─────────────────────────────────────────────────────────────
class FocusTimerWidget extends StatefulWidget {
  final String coachId;
  final int initialMinutes;
  final void Function(String) onMessage;

  const FocusTimerWidget({
    super.key,
    required this.coachId,
    required this.initialMinutes,
    required this.onMessage,
  });

  @override
  State<FocusTimerWidget> createState() => _FocusTimerWidgetState();
}

class _FocusTimerWidgetState extends State<FocusTimerWidget>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final FocusTimerManager _manager = FocusTimerManager();
  Timer? _ticker;
  bool _loaded = false;
  _TimerView _view = _TimerView.timer;
  int _completedStage = 25;
  int _todayCount = 0;

  // 집중 소리
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _soundOn = false;
  Timer? _soundTimer;

  // 별/사운드바 애니메이션
  late AnimationController _waveCtrl;
  late Animation<double> _waveAnim;

  // 이중 탭 방지
  bool _isToggling = false;

  // 비서 멘트
  static const _msgs = {
    'sec_male': {
      5:  {'start': '5분입니다. 저도 옆에서 대기하겠습니다.', 'done': '...끝났네요. 생각보다 잘 하셨습니다.'},
      15: {'start': '15분 시작합니다. 이 흐름 그대로 가시면 됩니다.', 'done': '15분 완료입니다. 조금 더 하실 수 있을 것 같은데요?'},
      25: {'start': '25분입니다. 집중하세요. 제가 지켜보고 있겠습니다.', 'done': '수고하셨습니다. 오늘 집중 시간, 제가 기억해두겠습니다.'},
    },
    'sec_female': {
      5:  {'start': '5분만요. 저도 여기서 같이 있을게요.', 'done': '수고하셨어요. 어때요, 할 만하죠? 🌸'},
      15: {'start': '15분 시작해요. 제가 곁에서 응원하고 있을게요.', 'done': '15분 해내셨어요! 조금 더 이어가볼까요?'},
      25: {'start': '25분이에요. 무리하지 말고 대표님 페이스대로 가요.', 'done': '정말 수고하셨어요. 오늘 집중 시간이 참 뿌듯하네요. 🌸'},
    },
  };

  bool get _isMale => widget.coachId == 'sec_male';

  List<Color> get _cardGradient => [const Color(0xFF1A1A2E), const Color(0xFF2D2A4E)];

  Color get _ringColor  => const Color(0xFFA78BFA);
  Color get _ringTrack  => Colors.white.withOpacity(0.1);
  Color get _labelColor => const Color(0xFFC4B5FD);
  Color get _soundActiveColor => const Color(0xFF7C3AED);

  static const _darkBg      = Color(0xFF1A1A2E);
  static const _purpleMain  = Color(0xFF7C3AED);
  static const _purpleLight = Color(0xFFA78BFA);

  // ── 코치 이미지 경로 ──────────────────────────────────────
  String get _coachTimerImg => _isMale
      ? 'assets/images/sec_male_timer_done.png'
      : 'assets/images/sec_female_timer_done.png';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _waveAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _waveCtrl, curve: Curves.easeInOut),
    );
    _initManager();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_manager.running) {
        final remain = _manager.getRemainSeconds();
        if (remain <= 0) {
          _ticker?.cancel();
          _manager.running = false;
          _manager.saveState();
          _onTimerDone(showMsg: true);
        } else {
          setState(() {});
        }
      }
    }
  }

  Future<void> _initManager() async {
    await _manager.loadState();
    _todayCount = await _manager.getTodayCompletedCount();

    if (_manager.coachId == null) {
      _manager.coachId = widget.coachId;
      _manager.stage = widget.initialMinutes;
      _manager.duration = widget.initialMinutes * 60;
      await _manager.saveState();
    }

    if (_manager.running) {
      final remain = _manager.getRemainSeconds();
      if (remain <= 0) {
        _manager.running = false;
        await _manager.saveState();
        _onTimerDone(showMsg: true);
      } else {
        _startTicker();
      }
    }

    if (mounted) setState(() { _loaded = true; });
  }

  String _getStartMsg() {
    final m = _msgs[widget.coachId] ?? _msgs['sec_male']!;
    return m[_manager.stage]?['start'] ?? '';
  }

  String _getDoneMsg() {
    final m = _msgs[widget.coachId] ?? _msgs['sec_male']!;
    return m[_manager.stage]?['done'] ?? '';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _soundTimer?.cancel();
    _waveCtrl.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  // ── 타이머 로직 ──────────────────────────────────────────

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      final remain = _manager.getRemainSeconds();
      setState(() {});
      if (remain <= 0) {
        t.cancel();
        _manager.running = false;
        _manager.saveState();
        _onTimerDone(showMsg: true);
      }
    });
  }

  Future<void> _onTimerDone({required bool showMsg}) async {
    _completedStage = _manager.stage;
    await _stopSound();
    await _manager.incrementTodayCount();
    await AnalyticsService.logFeatureUsage('timer');
    _todayCount = await _manager.getTodayCompletedCount();

    if (showMsg) {
      final msg = _getDoneMsg();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onMessage(msg);
      });
    }
    if (mounted) setState(() { _view = _TimerView.done; });
  }

  void _toggle() async {
    if (_isToggling) return; // 이중 탭 방지
    _isToggling = true;
    try {
      if (_manager.running) {
        _ticker?.cancel();
        await _manager.pause();
        if (mounted) setState(() {});
      } else {
        final isFirst = (_manager.pausedRemainSec == null);
        if (isFirst) {
          await _manager.start(_manager.stage, widget.coachId);
          final msg = _getStartMsg();
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) widget.onMessage(msg);
          });
        } else {
          await _manager.resume();
        }
        if (mounted) setState(() {});
        _startTicker();
      }
    } finally {
      _isToggling = false;
    }
  }

  void _reset() async {
    _ticker?.cancel();
    await _stopSound();
    await _manager.reset(_manager.stage);
    if (mounted) setState(() {});
  }

  void _setStage(int min) {
    if (_manager.running) return;
    // 소리가 켜져 있으면 끄고 재설정 (단계 변경 시 타이머 불일치 방지)
    if (_soundOn) _stopSound();
    _manager.reset(min).then((_) {
      if (mounted) setState(() {});
    });
  }

  // ── 집중 소리 로직 ──────────────────────────────────────

  void _toggleSound() async {
    if (_soundOn) {
      await _stopSound();
    } else {
      await _startSound(limitToStage: true);
    }
    if (mounted) setState(() {});
  }

  Future<void> _startSound({bool limitToStage = true}) async {
    _soundTimer?.cancel();
    _soundOn = true;
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/focus_sound.mp3'));
    if (limitToStage) {
      final stopAfterMs = _manager.stage * 60 * 1000;
      _soundTimer = Timer(Duration(milliseconds: stopAfterMs), () async {
        await _stopSound();
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _startSoundInfinite() async {
    _soundTimer?.cancel();
    _soundOn = true;
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/focus_sound.mp3'));
  }

  Future<void> _stopSound() async {
    _soundTimer?.cancel();
    _soundTimer = null;
    _soundOn = false;
    await _audioPlayer.stop();
  }

  // ── 표시 유틸 ────────────────────────────────────────────

  String get _timeDisplay {
    final remain = _manager.getRemainSeconds();
    final m = (remain ~/ 60).toString().padLeft(2, '0');
    final s = (remain % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress {
    if (_manager.duration <= 0) return 0.0;
    return _manager.getRemainSeconds() / _manager.duration;
  }

  // ── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: switch (_view) {
        _TimerView.timer    => _buildTimerView(),
        _TimerView.done     => _buildDoneView(),
        _TimerView.soundOnly => _buildSoundOnlyView(),
      },
    );
  }

  // ════════════════════════════════════════════════════════════
  // 1) 타이머 화면
  // ════════════════════════════════════════════════════════════
  Widget _buildTimerView() {
    final stageLabels = {5: '5분 집중', 15: '15분 집중', 25: '25분 집중'};
    final remain = _manager.getRemainSeconds();
    final isDone = remain <= 0;

    return Container(
      key: const ValueKey('timer'),
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 32, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
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
                  Text(
                    '⏱ FOCUS TIMER',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 2, color: _labelColor.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 140, height: 140,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(140, 140),
                          painter: _TimerRingPainter(
                            progress: _progress,
                            ringColor: _ringColor,
                            trackColor: _ringTrack,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _timeDisplay,
                              style: GoogleFonts.notoSansKr(
                                fontSize: 30, fontWeight: FontWeight.w900,
                                color: Colors.white, letterSpacing: -1,
                              ),
                            ),
                            Text(
                              isDone
                                  ? '완료!'
                                  : _manager.running
                                      ? '${_manager.stage}분 집중 중'
                                      : stageLabels[_manager.stage] ?? '${_manager.stage}분',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 9, fontWeight: FontWeight.w700,
                                color: _labelColor.withOpacity(0.85), letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [5, 15, 25].map((m) {
                      final isActive = _manager.stage == m;
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: GestureDetector(
                          onTap: () => _setStage(m),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isActive ? Colors.white : Colors.white.withOpacity(0.3),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '${m}분',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 11, fontWeight: FontWeight.w800,
                                color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
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

            // 컨트롤 영역
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: isDone ? null : _toggle,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          gradient: isDone
                              ? const LinearGradient(colors: [Color(0xFF9CA3AF), Color(0xFFD1D5DB)])
                              : LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: _cardGradient,
                                ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 14, offset: const Offset(0, 4))],
                        ),
                        child: Center(
                          child: Text(
                            isDone ? '완료 🎉' : _manager.running ? '⏸ 일시정지' : '▶ 시작',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 14, fontWeight: FontWeight.w900, color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 집중 소리 버튼
                  GestureDetector(
                    onTap: isDone ? null : _toggleSound,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOut,
                      width: 90,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _soundOn ? _soundActiveColor : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _soundOn ? _soundActiveColor : const Color(0xFFE5E7EB),
                          width: 1.5,
                        ),
                        boxShadow: _soundOn
                            ? [BoxShadow(color: _soundActiveColor.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 4))]
                            : [],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.headphones_rounded, size: 20,
                              color: _soundOn ? Colors.white : const Color(0xFF9CA3AF)),
                          const SizedBox(height: 3),
                          Text('집중 소리', style: GoogleFonts.notoSansKr(
                              fontSize: 9, fontWeight: FontWeight.w700,
                              color: _soundOn ? Colors.white : const Color(0xFF9CA3AF))),
                          Text(_soundOn ? 'ON' : 'OFF', style: GoogleFonts.notoSansKr(
                              fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1,
                              color: _soundOn ? Colors.white.withOpacity(0.9) : const Color(0xFFD1D5DB))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 리셋 버튼
                  GestureDetector(
                    onTap: _reset,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB), width: 1.5),
                      ),
                      child: Text('↺', style: GoogleFonts.notoSansKr(
                          fontSize: 14, fontWeight: FontWeight.w800, color: const Color(0xFF9CA3AF))),
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

  // ════════════════════════════════════════════════════════════
  // 2) 완료 화면 (코치 이미지 + 별 반짝임)
  // ════════════════════════════════════════════════════════════
  Widget _buildDoneView() {
    final stageMin = _completedStage;

    return Container(
      key: const ValueKey('done'),
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: _darkBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.28), blurRadius: 32, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── 코치 이미지 + 별 영역 ─────────────────────────
            SizedBox(
              height: 220,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 배경 그라디언트
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1A1A3E), _darkBg],
                        ),
                      ),
                    ),
                  ),

                  // 배경 보라 빛번짐
                  Positioned(
                    top: -30, left: 0, right: 0,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [_purpleMain.withOpacity(0.22), Colors.transparent],
                          radius: 0.7,
                        ),
                      ),
                    ),
                  ),

                  // 별 반짝임
                  ..._buildSparkles(),

                  // 코치 이미지 (상단 크롭 — 얼굴 반드시 표시)
                  Positioned(
                    bottom: -10, left: 0, right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 210,
                        height: 225,
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white, Colors.white, Colors.transparent],
                            stops: [0.0, 0.70, 1.0],
                          ).createShader(rect),
                          blendMode: BlendMode.dstIn,
                          child: Image.asset(
                            _coachTimerImg,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 텍스트 + 버튼 ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '수고하셨습니다! ✨',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${stageMin}분 집중이 완료되었습니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13, fontWeight: FontWeight.w500,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 새 타이머 시작 버튼
                  GestureDetector(
                    onTap: () async {
                      await _manager.reset(_completedStage);
                      if (mounted) setState(() { _view = _TimerView.timer; });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF7C3AED), Color(0xFF9F67F8)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: _purpleMain.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('새 타이머 시작', style: GoogleFonts.notoSansKr(
                                  fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                              Text('다시 집중을 시작할게요', style: GoogleFonts.notoSansKr(
                                  fontSize: 10, fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.75))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 집중 소리만 계속 듣기 버튼
                  GestureDetector(
                    onTap: () async {
                      await _startSoundInfinite();
                      if (mounted) setState(() { _view = _TimerView.soundOnly; });
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.5),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.headphones_rounded, color: Colors.white70, size: 20),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('집중 소리만 계속 듣기', style: GoogleFonts.notoSansKr(
                                  fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                              Text('타이머 없이 집중 소리를 계속 들을게요', style: GoogleFonts.notoSansKr(
                                  fontSize: 10, fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.5))),
                            ],
                          ),
                        ],
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

  /// 별 반짝임 위젯 (✦ 보라 + ★ 노랑, 애니메이션 펄스)
  /// left/right 구분으로 어떤 화면 너비에도 안전하게 표시
  List<Widget> _buildSparkles() {
    // [offset, top, size, opacity, 0=star/1=sparkle, 0=left/1=right]
    final specs = <List<double>>[
      [22,  16, 13, 0.90, 1, 0], // 왼쪽
      [50,  52,  7, 0.60, 0, 0],
      [14,  86,  9, 0.70, 1, 0],
      [28,  20, 10, 0.85, 0, 1], // 오른쪽 (right:)
      [10,  54, 14, 0.90, 1, 1],
      [38,  90,  7, 0.60, 0, 1],
      [158,  8,  8, 0.50, 1, 0], // 중앙 상단
      [125, 135, 6, 0.40, 0, 0],
      [198, 145, 7, 0.50, 1, 0],
    ];

    return specs.map((s) {
      final isSparkle = s[4] == 1;
      final isRight   = s[5] == 1;
      final color = isSparkle ? _purpleLight : const Color(0xFFFBBF24);
      return Positioned(
        left:  isRight ? null : s[0],
        right: isRight ? s[0] : null,
        top:   s[1],
        child: AnimatedBuilder(
          animation: _waveAnim,
          builder: (_, __) {
            final pulse = 0.7 + 0.3 * _waveAnim.value;
            return Opacity(
              opacity: s[3] * pulse,
              child: Text(
                isSparkle ? '✦' : '★',
                style: TextStyle(fontSize: s[2], color: color, fontWeight: FontWeight.w900),
              ),
            );
          },
        ),
      );
    }).toList();
  }

  // ════════════════════════════════════════════════════════════
  // 3) 집중 소리 재생 중 화면
  // ════════════════════════════════════════════════════════════
  Widget _buildSoundOnlyView() {
    return Container(
      key: const ValueKey('soundOnly'),
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: _darkBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 32, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤드폰 + 사운드바
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _waveAnim,
                    builder: (_, __) => _buildWaveBars(mirror: true),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _purpleLight, width: 2.5),
                      color: _purpleMain.withOpacity(0.15),
                    ),
                    child: const Icon(Icons.headphones_rounded, color: _purpleLight, size: 36),
                  ),
                  const SizedBox(width: 16),
                  AnimatedBuilder(
                    animation: _waveAnim,
                    builder: (_, __) => _buildWaveBars(mirror: false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                '집중 소리 재생 중',
                style: GoogleFonts.notoSansKr(
                  fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '타이머 없이 집중 소리를 계속 들을 수 있어요.\n원하실 때 중단해 주세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12, color: Colors.white.withOpacity(0.55), height: 1.6,
                ),
              ),
              const SizedBox(height: 24),

              // 중단 버튼
              GestureDetector(
                onTap: () async {
                  await _stopSound();
                  if (mounted) setState(() { _view = _TimerView.done; });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF9F67F8)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: _purpleMain.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 10),
                      Text('집중 소리 중단하기', style: GoogleFonts.notoSansKr(
                          fontSize: 15, fontWeight: FontWeight.w900, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 무한 재생 표시
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.graphic_eq_rounded, color: _purpleLight, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('집중 소리는 계속 재생 중이에요',
                          style: GoogleFonts.notoSansKr(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: Colors.white.withOpacity(0.7))),
                    ),
                    const Text('∞', style: TextStyle(fontSize: 18, color: _purpleLight, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 사운드바 애니메이션 막대
  Widget _buildWaveBars({required bool mirror}) {
    final heights = [14.0, 22.0, 18.0, 26.0];
    final bars = List.generate(4, (i) {
      final phase = i / 3;
      final t = (_waveAnim.value - phase).clamp(0.3, 1.0);
      final h = heights[i] * t;
      return Container(
        width: 3, height: h,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: _purpleLight.withOpacity(0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    });
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: mirror ? bars.reversed.toList() : bars,
    );
  }
}


// ── 원형 링 페인터 ───────────────────────────────────────────
class _TimerRingPainter extends CustomPainter {
  final double progress;
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

    canvas.drawCircle(center, radius,
        Paint()..color = trackColor..style = PaintingStyle.stroke..strokeWidth = strokeWidth);

    final sweepAngle = 2 * pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, sweepAngle, false,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_TimerRingPainter old) =>
      old.progress != progress || old.ringColor != ringColor || old.trackColor != trackColor;
}
