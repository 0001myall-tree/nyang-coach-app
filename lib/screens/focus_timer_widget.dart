import 'dart:async';
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
  String? sessionDate;
  int? insertIndex;

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static Future<String> todayKey() async {
    final prefs = await SharedPreferences.getInstance();
    final resetHour = prefs.getDouble('nyang_reset_hour') ?? 3.0;
    final now = DateTime.now();
    var baseToday = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      baseToday = baseToday.subtract(const Duration(days: 1));
    }
    return _dateKey(baseToday);
  }

  Future<void> loadState() async {
    final prefs = await SharedPreferences.getInstance();
    running = prefs.getBool('focus_timer_running') ?? false;
    stage = prefs.getInt('focus_timer_stage') ?? 25;
    duration = prefs.getInt('focus_timer_duration') ?? (stage * 60);
    coachId = prefs.getString('focus_timer_coach_id');
    final startStr = prefs.getString('focus_timer_start_time');
    startTime = startStr != null ? DateTime.tryParse(startStr) : null;
    pausedRemainSec = prefs.getInt('focus_timer_paused_remain');
    sessionDate = prefs.getString('focus_timer_session_date');
    insertIndex = prefs.getInt('focus_timer_insert_index');
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
      await prefs.setString(
        'focus_timer_start_time',
        startTime!.toIso8601String(),
      );
    } else {
      await prefs.remove('focus_timer_start_time');
    }
    if (pausedRemainSec != null) {
      await prefs.setInt('focus_timer_paused_remain', pausedRemainSec!);
    } else {
      await prefs.remove('focus_timer_paused_remain');
    }
    if (sessionDate != null) {
      await prefs.setString('focus_timer_session_date', sessionDate!);
    } else {
      await prefs.remove('focus_timer_session_date');
    }
    if (insertIndex != null) {
      await prefs.setInt('focus_timer_insert_index', insertIndex!);
    } else {
      await prefs.remove('focus_timer_insert_index');
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
    sessionDate ??= await todayKey();
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
    'cat': {
      5: {'done': '5분 해냈다냥! 시작한 집사 멋지다냥.'},
      15: {'done': '15분 집중 성공이다냥! 집사 꽤 하는데냥.'},
      25: {'done': '25분 달성이다냥! 냥이가 박수친다냥.'},
    },
    'boyfriend': {
      5: {'done': '5분 지나갔네. 시작 전보다 마음이 조금 가벼워졌으면 좋겠다.'},
      15: {'done': '15분 집중했네. 눈이랑 어깨 한번 쉬게 해주자.'},
      25: {'done': '25분 채웠네. 오래 집중했으니까 물 한잔 마시고 숨 좀 돌리자.'},
    },
    'girlfriend': {
      5: {'done': '5분 지나갔네. 시작 전보다 조금 덜 막막했으면 좋겠다.'},
      15: {'done': '15분 집중했구나. 이제 눈이랑 어깨 잠깐 쉬게 해주자.'},
      25: {'done': '25분 채웠네. 오래 집중했으니까 물 한잔 마시고 숨 좀 돌리자.'},
    },
    'halmae': {
      5: {'done': '5분 했네. 아이고 잘했다.'},
      15: {'done': '15분 집중했구나. 참 장하다.'},
      25: {'done': '25분 해냈네. 아주 기특하다.'},
    },
    'bro': {
      5: {'done': '5분 완료. 시작 좋다.'},
      15: {'done': '15분 집중 성공. 폼 좋다.'},
      25: {'done': '25분 달성. 제대로 했다.'},
    },
    'sec_male': {
      5: {
        'start': '5분입니다. 저도 옆에서 대기하겠습니다.',
        'done': '5분 완료! 짧은 시간이지만 해내신 모습이 멋집니다. 수고하셨어요! 🎉',
      },
      15: {
        'start': '15분 시작합니다. 이 흐름 그대로 가시면 됩니다.',
        'done': '15분 집중 성공! 대표님의 멋진 몰입에 저도 박수를 보냅니다. 👏',
      },
      25: {
        'start': '25분입니다. 집중하세요. 제가 지켜보고 있겠습니다.',
        'done': '25분 달성! 끝까지 해내신 대표님이 자랑스럽습니다. 최고예요! 🥳',
      },
    },
    'sec_female': {
      5: {'start': '5분만요. 저도 여기서 같이 있을게요.', 'done': '수고하셨어요. 어때요, 할 만하죠? 🌸'},
      15: {
        'start': '15분 시작해요. 제가 곁에서 응원하고 있을게요.',
        'done': '15분 해내셨어요! 조금 더 이어가볼까요?',
      },
      25: {
        'start': '25분이에요. 무리하지 말고 대표님 페이스대로 가요.',
        'done': '정말 수고하셨어요. 오늘 집중 시간이 참 뿌듯하네요. 🌸',
      },
    },
  };

  bool get _isMale => widget.coachId == 'sec_male';
  bool get _isMasterTimer =>
      widget.coachId == 'sec_male' || widget.coachId == 'sec_female';

  Color get _soundActiveColor => const Color(0xFF7C3AED);

  static const _darkBg = Color(0xFF1A1A2E);
  static const _purpleMain = Color(0xFF7C3AED);
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
    _waveAnim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _waveCtrl, curve: Curves.easeInOut));
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

    final remain = _manager.getRemainSeconds();
    final shouldStartFresh =
        _manager.coachId == null ||
        _manager.coachId != widget.coachId ||
        (!_manager.running && _manager.stage != widget.initialMinutes) ||
        (_manager.running && remain <= 0);

    if (shouldStartFresh) {
      _ticker?.cancel();
      await _stopSound();
      await NotificationService().cancelFocusTimerNotification();
      _manager.running = false;
      _manager.coachId = widget.coachId;
      _manager.stage = widget.initialMinutes;
      _manager.duration = widget.initialMinutes * 60;
      _manager.pausedRemainSec = null;
      _manager.startTime = null;
      await _manager.saveState();
    }

    if (_manager.running) {
      if (remain <= 0) {
        _manager.running = false;
        await _manager.saveState();
        _onTimerDone(showMsg: true);
      } else {
        _startTicker();
      }
    }

    if (mounted) {
      setState(() {
        _loaded = true;
      });
    }
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
      if (!mounted) {
        t.cancel();
        return;
      }
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

    if (showMsg) {
      final msg = _getDoneMsg();
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) widget.onMessage(msg);
      });
    }
    if (mounted) {
      if (_isMasterTimer) {
        await _manager.reset(_completedStage);
        if (!mounted) return;
        setState(() {
          _view = _TimerView.timer;
        });
        return;
      }
      setState(() {
        _view = _TimerView.done;
      });
    }
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

  // ── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: switch (_view) {
        _TimerView.timer =>
          _isMasterTimer ? _buildTimerView() : _buildFriendTimerView(),
        _TimerView.done =>
          _isMasterTimer ? _buildDoneView() : _buildFriendDoneView(),
        _TimerView.soundOnly => _buildSoundOnlyView(),
      },
    );
  }

  Widget _buildFriendTimerView() {
    final stageLabels = {5: '총 5분 집중 중', 15: '총 15분 집중 중', 25: '총 25분 집중 중'};
    final remain = _manager.getRemainSeconds();
    final isDone = remain <= 0;
    const mainPurple = Color(0xFF7C6BEA);
    const softPurple = Color(0xFFF7F3FF);
    const borderPurple = Color(0xFFE7DDFC);

    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.88,
        child: Container(
          key: const ValueKey('friendTimer'),
          margin: const EdgeInsets.only(top: 10, bottom: 2),
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
          child: Column(
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
                _timeDisplay,
                style: GoogleFonts.notoSansKr(
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                  color: mainPurple,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isDone
                    ? '집중 완료'
                    : _manager.running
                    ? stageLabels[_manager.stage] ?? '집중 중'
                    : '${_manager.stage}분 집중 준비',
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8B7DE0),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [5, 15, 25].map((m) {
                  final isActive = _manager.stage == m;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => _setStage(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: isActive ? mainPurple : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isActive ? mainPurple : borderPurple,
                              width: 1,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '$m분',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isActive ? Colors.white : mainPurple,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Container(height: 1, color: const Color(0xFFF0ECFA)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: isDone ? null : _toggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
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
                            _manager.running
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 18,
                            color: mainPurple,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _manager.running ? '일시정지' : '시작',
                            style: GoogleFonts.notoSansKr(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF5F52C6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  GestureDetector(
                    onTap: _reset,
                    child: Container(
                      width: 58,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: borderPurple, width: 1),
                      ),
                      child: const Icon(
                        Icons.refresh_rounded,
                        size: 20,
                        color: mainPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendDoneView() {
    final stageMin = _completedStage;
    const mainPurple = Color(0xFF7C6BEA);
    const borderPurple = Color(0xFFE7DDFC);

    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.88,
        child: Container(
          key: const ValueKey('friendDone'),
          margin: const EdgeInsets.only(top: 10, bottom: 2),
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
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
          child: Column(
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
                '$stageMin분 집중을 마쳤어요.',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF8B7DE0),
                ),
              ),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () async {
                  await _manager.reset(_completedStage);
                  if (mounted) {
                    setState(() {
                      _view = _TimerView.timer;
                    });
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: mainPurple,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '새 타이머 시작',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
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
    );
  }

  // ════════════════════════════════════════════════════════════
  // 1) 타이머 화면
  // ════════════════════════════════════════════════════════════
  Widget _buildTimerView() {
    final stageLabels = {5: '5분 집중', 15: '15분 집중', 25: '25분 집중'};
    final remain = _manager.getRemainSeconds();
    final isDone = remain <= 0;
    const timerMain = Color(0xFF9B8AF0);
    const timerAccent = Color(0xFFA99AE8);
    const timerInk = Color(0xFF2F266C);
    const timerBorder = Color(0xFFE7E0FA);

    return Align(
      key: const ValueKey('timer'),
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.78,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: timerBorder, width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: timerMain.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.timer_rounded, size: 15, color: timerAccent),
                    const SizedBox(width: 6),
                    Text(
                      'FOCUS TIMER',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: timerAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _timeDisplay,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: timerInk,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isDone
                      ? '완료'
                      : _manager.running
                      ? '${_manager.stage}분 집중 중'
                      : stageLabels[_manager.stage] ?? '${_manager.stage}분 집중',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: timerAccent,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [5, 15, 25].map((m) {
                    final isActive = _manager.stage == m;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () => _setStage(m),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          constraints: const BoxConstraints(minWidth: 58),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isActive ? timerMain : timerBorder,
                              width: isActive ? 1.8 : 1.2,
                            ),
                          ),
                          child: Text(
                            '$m분',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.notoSansKr(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: isActive ? timerInk : timerAccent,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: isDone ? null : _toggle,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 136,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: isDone
                          ? const LinearGradient(
                              colors: [Color(0xFF9CA3AF), Color(0xFFD1D5DB)],
                            )
                          : const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [timerMain, timerAccent],
                            ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: timerMain.withValues(alpha: 0.28),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isDone
                              ? Icons.check_rounded
                              : _manager.running
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 21,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isDone
                              ? '완료'
                              : _manager.running
                              ? '일시정지'
                              : '집중 시작',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GestureDetector(
                      onTap: _reset,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.replay_rounded,
                              size: 17,
                              color: timerAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '되돌리기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: timerAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 14,
                      margin: const EdgeInsets.symmetric(horizontal: 10),
                      color: timerBorder,
                    ),
                    GestureDetector(
                      onTap: isDone ? null : _toggleSound,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.headphones_rounded,
                              size: 17,
                              color: _soundOn ? _soundActiveColor : timerAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _soundOn ? 'ON' : 'OFF',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: _soundOn
                                    ? _soundActiveColor
                                    : timerAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
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
                    top: -30,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 200,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: [
                            _purpleMain.withValues(alpha: 0.22),
                            Colors.transparent,
                          ],
                          radius: 0.7,
                        ),
                      ),
                    ),
                  ),

                  // 별 반짝임
                  ..._buildSparkles(),

                  // 코치 이미지 (상단 크롭 — 얼굴 반드시 표시)
                  Positioned(
                    bottom: -10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: SizedBox(
                        width: 210,
                        height: 225,
                        child: ShaderMask(
                          shaderCallback: (rect) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white,
                              Colors.white,
                              Colors.transparent,
                            ],
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
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$stageMin분 집중이 완료되었습니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 22),

                  // 새 타이머 시작 버튼
                  GestureDetector(
                    onTap: () async {
                      await _manager.reset(_completedStage);
                      if (mounted) {
                        setState(() {
                          _view = _TimerView.timer;
                        });
                      }
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
                        boxShadow: [
                          BoxShadow(
                            color: _purpleMain.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '새 타이머 시작',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '다시 집중을 시작할게요',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.75),
                                ),
                              ),
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
                      if (mounted) {
                        setState(() {
                          _view = _TimerView.soundOnly;
                        });
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.headphones_rounded,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '집중 소리만 계속 듣기',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                '타이머 없이 집중 소리를 계속 들을게요',
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
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
      [22, 16, 13, 0.90, 1, 0], // 왼쪽
      [50, 52, 7, 0.60, 0, 0],
      [14, 86, 9, 0.70, 1, 0],
      [28, 20, 10, 0.85, 0, 1], // 오른쪽 (right:)
      [10, 54, 14, 0.90, 1, 1],
      [38, 90, 7, 0.60, 0, 1],
      [158, 8, 8, 0.50, 1, 0], // 중앙 상단
      [125, 135, 6, 0.40, 0, 0],
      [198, 145, 7, 0.50, 1, 0],
    ];

    return specs.map((s) {
      final isSparkle = s[4] == 1;
      final isRight = s[5] == 1;
      final color = isSparkle ? _purpleLight : const Color(0xFFFBBF24);
      return Positioned(
        left: isRight ? null : s[0],
        right: isRight ? s[0] : null,
        top: s[1],
        child: AnimatedBuilder(
          animation: _waveAnim,
          builder: (_, _) {
            final pulse = 0.7 + 0.3 * _waveAnim.value;
            return Opacity(
              opacity: s[3] * pulse,
              child: Text(
                isSparkle ? '✦' : '★',
                style: TextStyle(
                  fontSize: s[2],
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
        ],
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
                    builder: (_, _) => _buildWaveBars(mirror: true),
                  ),
                  const SizedBox(width: 16),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: _purpleLight, width: 2.5),
                      color: _purpleMain.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.headphones_rounded,
                      color: _purpleLight,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 16),
                  AnimatedBuilder(
                    animation: _waveAnim,
                    builder: (_, _) => _buildWaveBars(mirror: false),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Text(
                '집중 소리 재생 중',
                style: GoogleFonts.notoSansKr(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '타이머 없이 집중 소리를 계속 들을 수 있어요.\n원하실 때 중단해 주세요.',
                textAlign: TextAlign.center,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.55),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),

              // 중단 버튼
              GestureDetector(
                onTap: () async {
                  await _stopSound();
                  if (mounted) {
                    setState(() {
                      _view = _TimerView.done;
                    });
                  }
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
                    boxShadow: [
                      BoxShadow(
                        color: _purpleMain.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '집중 소리 중단하기',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 무한 재생 표시
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.graphic_eq_rounded,
                      color: _purpleLight,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '집중 소리는 계속 재생 중이에요',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                    const Text(
                      '∞',
                      style: TextStyle(
                        fontSize: 18,
                        color: _purpleLight,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
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
        width: 3,
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: _purpleLight.withValues(alpha: 0.7),
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
