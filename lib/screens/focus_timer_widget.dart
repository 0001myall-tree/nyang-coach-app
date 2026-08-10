import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/analytics_service.dart';
import '../services/focus_cycle.dart';
import '../services/notification_service.dart';
import '../services/user_title_service.dart';

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

  /// 사용자가 저장해둔 작업·휴식·반복 설정. 없으면 5·15·25 버튼만 쓴다.
  ///
  /// 타이머가 끝나도 지우지 않는다. 한 번 자기 리듬을 정해둔 사람은 다음에도
  /// 같은 값으로 시작하고 싶어 한다.
  FocusCycleSetting? cycleSetting;

  /// 지금 돌고 있는 구간. 설정이 있어도 시작 전에는 null이다.
  FocusCycleStep? cycleStep;

  bool get isCycleRunning => cycleStep != null;

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static Future<String> todayKey() async {
    const resetHour = 0.0;
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
    cycleSetting = _decodeSetting(prefs.getString(_cycleSettingKey));
    final phaseName = prefs.getString('focus_timer_cycle_phase');
    final round = prefs.getInt('focus_timer_cycle_round');
    if (cycleSetting != null && phaseName != null && round != null) {
      cycleStep = FocusCycleStep(
        phase: phaseName == 'rest' ? FocusPhase.rest : FocusPhase.work,
        round: round,
        minutes: stage,
      );
    } else {
      cycleStep = null;
    }
  }

  static const String _cycleSettingKey = 'focus_timer_cycle_setting';

  static FocusCycleSetting? _decodeSetting(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return FocusCycleSetting.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCycleSetting(FocusCycleSetting? setting) async {
    cycleSetting = setting;
    cycleStep = null;
    final prefs = await SharedPreferences.getInstance();
    if (setting == null) {
      await prefs.remove(_cycleSettingKey);
    } else {
      await prefs.setString(_cycleSettingKey, jsonEncode(setting.toJson()));
    }
    await saveState();
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
    final step = cycleStep;
    if (step != null) {
      await prefs.setString('focus_timer_cycle_phase', step.phase.name);
      await prefs.setInt('focus_timer_cycle_round', step.round);
    } else {
      await prefs.remove('focus_timer_cycle_phase');
      await prefs.remove('focus_timer_cycle_round');
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
      coachId: coachId ?? 'nyang_halbae',
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
    cycleStep = null;
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

  /// 생각 정리용으로 켠 타이머인지. 시간을 재는 일은 같지만 하는 일이 달라서
  /// (일을 붙잡는 게 아니라 머릿속을 종이로 옮기는 것) 이름과 버튼만 갈아입힌다.
  /// 화면을 따로 만들면 타이머 고칠 때마다 두 곳을 손봐야 한다.
  final bool isMindTimer;

  const FocusTimerWidget({
    super.key,
    required this.coachId,
    required this.initialMinutes,
    required this.onMessage,
    this.isMindTimer = false,
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
    'nyang_halbae': {
      5: {
        'start': '5분만 잡아보자냥. 시작은 작을수록 좋더군.',
        'done': '5분 지났구나. 짧아 보여도 흐름을 바꾸기엔 충분할 때가 있다냥.',
      },
      15: {
        'start': '15분 가보자냥. 끝보다 지금 손에 잡힌 일만 보자.',
        'done': '15분을 붙잡았구나. 마음이 조금 덜 흩어졌다면 그걸로 좋다냥.',
      },
      25: {
        'start': '25분을 시작하자냥. 서두르지 말고 한 걸음씩 가면 된다.',
        'done': '25분을 지나왔구나. 오늘은 그만큼 앞으로 간 것이다냥.',
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

  bool get _isMale => widget.coachId == 'nyang_halbae';
  bool get _isMasterTimer =>
      widget.coachId == 'nyang_halbae' || widget.coachId == 'sec_female';

  /// 반복 설정은 마스터 코치 타이머에만 있다. 생각 정리용 타이머는 한 번
  /// 재고 끝나는 게 그 기능의 전부라 반복이 낄 자리가 없다.
  bool get _canUseCycle => _isMasterTimer && !widget.isMindTimer;

  FocusCycleSetting? get _cycleSetting =>
      _canUseCycle ? _manager.cycleSetting : null;

  Color get _soundActiveColor => const Color(0xFF7C3AED);

  static const _darkBg = Color(0xFF1A1A2E);
  static const _purpleMain = Color(0xFF7C3AED);
  static const _purpleLight = Color(0xFFA78BFA);

  // ── 코치 이미지 경로 ──────────────────────────────────────
  String get _coachTimerImg => _isMale
      ? 'assets/images/coach_nyang_halbae_nobg.png'
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

  Future<String> _getDoneMsg() async {
    final m = _msgs[widget.coachId] ?? _msgs['nyang_halbae']!;
    final message = m[_manager.stage]?['done'] ?? '';
    return UserTitleService.applyForCoach(message, widget.coachId);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
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

    // 반복 설정으로 도는 중이면 다음 구간으로 이어간다. 마지막 작업이 끝나면
    // next가 null이라 아래 평소 흐름으로 떨어진다.
    final setting = _cycleSetting;
    final step = _manager.cycleStep;
    if (setting != null && step != null) {
      if (step.phase.isWork) await _manager.incrementTodayCount();
      final next = FocusCycle.next(setting, step);
      if (next != null) {
        _manager.cycleStep = next;
        await _manager.start(next.minutes, widget.coachId);
        if (mounted) setState(() {});
        _startTicker();
        return;
      }
      _manager.cycleStep = null;
      await AnalyticsService.logFeatureUsage('timer_cycle_done');
      if (showMsg) {
        final done = await _getDoneMsg();
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) widget.onMessage(done);
        });
      }
      if (mounted) {
        await _manager.reset(setting.workMinutes);
        if (!mounted) return;
        setState(() => _view = _TimerView.timer);
      }
      return;
    }

    await _manager.incrementTodayCount();
    await AnalyticsService.logFeatureUsage('timer');

    if (showMsg) {
      final msg = await _getDoneMsg();
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
          // 저장해둔 설정이 있으면 그 첫 구간부터 시작한다. 5·15·25를 눌러
          // 쓰던 사람은 설정이 없으니 예전 그대로 한 번만 돈다.
          final setting = _cycleSetting;
          if (setting != null && !_manager.isCycleRunning) {
            final first = FocusCycle.first(setting);
            _manager.cycleStep = first;
            await _manager.start(first.minutes, widget.coachId);
          } else {
            await _manager.start(_manager.stage, widget.coachId);
          }
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
    _manager.cycleStep = null;
    _manager.reset(min).then((_) {
      if (mounted) setState(() {});
    });
  }

  /// 타이머만 크게 보는 화면으로 넘어간다.
  ///
  /// 조작은 이 위젯이 그대로 들고 있고 화면은 껍데기만 빌려준다. 상태를
  /// 양쪽에 두면 한쪽에서 멈춘 게 다른 쪽에 안 보인다.
  void _openFocusScreen() {
    Navigator.of(context)
        .push(
          PageRouteBuilder<void>(
            pageBuilder: (_, _, _) => MasterTimerFocusScreen(
              onToggle: () async => _toggle(),
              onStop: () async => _reset(),
              onToggleSound: () async => _toggleSound(),
              isSoundOn: () => _soundOn,
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            transitionDuration: const Duration(milliseconds: 220),
            reverseTransitionDuration: const Duration(milliseconds: 180),
          ),
        )
        .then((_) {
          if (mounted) setState(() {});
        });
  }

  // ── 반복 설정 (마스터 전용) ──────────────────────────────

  /// 저장해둔 설정을 타이머 카드에 한 줄로 보여준다.
  ///
  /// 돌고 있는 중에는 지금 몇 회차인지로 바꾼다. 25분이 네 번 도는데 화면에
  /// 남은 시간만 보이면 몇 번째인지 알 길이 없다.
  Widget _buildCycleSummaryRow(
    FocusCycleSetting setting, {
    required Color main,
    required Color accent,
    required Color ink,
    required Color border,
  }) {
    final step = _manager.cycleStep;
    final label = step != null
        ? '${FocusCycle.progressLabel(setting, step)} · ${step.minutes}분'
        : setting.summary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: main.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.repeat_rounded, size: 14, color: main),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: _manager.running ? null : _openCycleSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.2),
            ),
            child: Text(
              '설정 변경',
              style: GoogleFonts.notoSansKr(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: _manager.running ? border : accent,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCycleSheet() async {
    if (_manager.running) return;
    final result = await showModalBottomSheet<_CycleSheetResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CycleSettingSheet(
        initial: _cycleSetting ?? FocusCycleSetting.pomodoro,
        canClear: _cycleSetting != null,
      ),
    );
    if (result == null || !mounted) return;
    await _manager.saveCycleSetting(result.setting);
    // 저장한 값이 바로 시계에 뜨게 맞춰둔다. 시작을 누르면 여기서부터 돈다.
    await _manager.reset(result.setting?.workMinutes ?? _manager.stage);
    if (mounted) setState(() {});
  }

  // ── 집중 소리 로직 ──────────────────────────────────────

  void _toggleSound() async {
    if (_soundOn) {
      await _stopSound();
    } else {
      await _startSound();
    }
    if (mounted) setState(() {});
  }

  /// 켜두면 끝까지 돈다. 멈추는 건 두 곳뿐이다 — 타이머가 끝날 때([_onTimerDone])와
  /// 사용자가 직접 끌 때. 예전에는 "켠 시점부터 타이머 길이만큼" 세는 별도
  /// 타이머가 같이 돌았는데, 실제 남은 시간과 어긋나서 일시정지 후 재개하면
  /// 소리가 먼저 끊겼다.
  Future<void> _startSound() async {
    _soundOn = true;
    await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    await _audioPlayer.play(AssetSource('sounds/focus_sound.mp3'));
  }

  Future<void> _stopSound() async {
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
    // 마스터 코치 타이머는 "05:00"이 이미 시간을 보여주므로
    // 그 아래 "n분 집중" 문구를 숨겨 중복을 없앤다.
    final isMaster =
        widget.coachId == 'nyang_halbae' || widget.coachId == 'sec_female';
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
                // 제목은 가운데를 지키고 전체 보기만 오른쪽 끝에 앉힌다.
                // 시계 옆에 두면 시계 폭을 빼앗아 "24:40"이 두 줄로 쪼개진다.
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.timer_rounded, size: 15, color: timerAccent),
                        const SizedBox(width: 6),
                        Text(
                          // 이 화면은 마스터 코치만 쓴다. 프렌즈 타이머는 따로
                          // 그려지고 '집중 시간'이라고 적는다.
                          widget.isMindTimer ? 'MIND TIMER' : 'MASTER TIMER',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.6,
                            color: timerAccent,
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      child: GestureDetector(
                        onTap: _openFocusScreen,
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.open_in_full_rounded,
                              size: 13,
                              color: timerAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '전체 보기',
                              style: GoogleFonts.notoSansKr(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: timerAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _timeDisplay,
                  maxLines: 1,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: timerInk,
                  ),
                ),
                if (!isMaster) ...[
                  const SizedBox(height: 2),
                  Text(
                    isDone
                        ? '완료'
                        : _manager.running
                        ? '${_manager.stage}분 집중 중'
                        : stageLabels[_manager.stage] ??
                              '${_manager.stage}분 집중',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: timerAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // 저장해둔 반복 설정이 있으면 그 요약이 빠른 선택 자리를
                // 대신한다. 둘을 같이 두면 어느 값으로 시작하는지 헷갈린다.
                if (_cycleSetting != null)
                  _buildCycleSummaryRow(
                    _cycleSetting!,
                    main: timerMain,
                    accent: timerAccent,
                    ink: timerInk,
                    border: timerBorder,
                  )
                else
                  // 셋을 균등하게 나눈다. 가운데 정렬로 두면 "직접 설정"만
                  // 글자가 길어서 줄이 한쪽으로 쏠려 보인다.
                  Row(
                    children: [
                      // 마스터는 5분 자리를 직접 설정에 내준다. 세밀하게 쓸
                      // 사람은 그쪽에서 더 짧은 값도 고를 수 있다.
                      ...(_canUseCycle ? [15, 25] : [5, 15, 25]).map((m) {
                        final isActive = _manager.stage == m;
                        return Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: () => _setStage(m),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
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
                          ),
                        );
                      }),
                      if (_canUseCycle)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: GestureDetector(
                              onTap: _openCycleSheet,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: timerMain.withValues(alpha: 0.55),
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  '직접 설정',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.notoSansKr(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: timerMain,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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
                              : widget.isMindTimer
                              ? '생각 시작'
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
                            // 켜짐/꺼짐을 색으로만 나누면 처음 보는 사람은
                            // 어느 쪽인지 모른다. 아이콘 모양으로도 갈라둔다.
                            Icon(
                              _soundOn
                                  ? Icons.headphones_rounded
                                  : Icons.headset_off_rounded,
                              size: 17,
                              color: _soundOn ? _soundActiveColor : timerAccent,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              // 라벨은 늘 같게 둔다. "켜기/끄기"로 쓰면 지금
                              // 상태인지 누르면 될 일인지 읽는 사람마다 갈린다.
                              '백색소음',
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
                      await _startSound();
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

// ─────────────────────────────────────────────────────────────
// 반복 설정 바텀시트
// ─────────────────────────────────────────────────────────────

class _CycleSheetResult {
  const _CycleSheetResult(this.setting);

  /// null이면 반복을 끄고 5·15·25로 돌아간다.
  final FocusCycleSetting? setting;
}

/// 작업·휴식·반복 횟수를 고르는 시트.
///
/// 숫자를 직접 입력받지 않고 목록에서 고르게 한다. 0분이나 300분이 저장되면
/// 타이머가 시작하자마자 끝나거나 하루를 통째로 잡아먹는다.
class _CycleSettingSheet extends StatefulWidget {
  const _CycleSettingSheet({required this.initial, required this.canClear});

  final FocusCycleSetting initial;
  final bool canClear;

  @override
  State<_CycleSettingSheet> createState() => _CycleSettingSheetState();
}

class _CycleSettingSheetState extends State<_CycleSettingSheet> {
  late int _work = widget.initial.workMinutes;
  late int _rest = widget.initial.restMinutes;
  late int _rounds = widget.initial.rounds;

  static const Color _main = Color(0xFF9B8AF0);
  static const Color _accent = Color(0xFFA99AE8);
  static const Color _ink = Color(0xFF2F266C);
  static const Color _border = Color(0xFFE7E0FA);

  FocusCycleSetting get _setting => FocusCycleSetting(
    workMinutes: _work,
    restMinutes: _rest,
    rounds: _rounds,
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: _border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '시간 설정 변경',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _row(
              label: '작업 시간',
              hint: '집중해서 일하는 시간',
              value: _work,
              unit: '분',
              choices: FocusCycleSetting.workChoices,
              onPick: (v) => setState(() => _work = v),
            ),
            _divider(),
            _row(
              label: '쉬는 시간',
              hint: '짧게 휴식하는 시간',
              value: _rest,
              unit: '분',
              choices: FocusCycleSetting.restChoices,
              onPick: (v) => setState(() => _rest = v),
            ),
            _divider(),
            _row(
              label: '반복 횟수',
              hint: '몇 번 반복할지 설정',
              value: _rounds,
              unit: '회',
              choices: FocusCycleSetting.roundChoices,
              onPick: (v) => setState(() => _rounds = v),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _main.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: _accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '총 예상 시간',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _setting.totalLabel,
                    style: GoogleFonts.notoSansKr(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _setting.hasRest
                        ? '(작업 $_work분 + 휴식 $_rest분) × $_rounds회'
                        : '작업 $_work분 한 번',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _accent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => Navigator.pop(context, _CycleSheetResult(_setting)),
              child: Container(
                width: double.infinity,
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [_main, _accent],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '이 설정으로 저장',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 반복을 쓰다가 그만두고 싶을 때 빠져나갈 길. 없으면 한 번 저장한
            // 사람은 5·15·25 버튼을 다시 볼 수 없다.
            if (widget.canClear) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () =>
                    Navigator.pop(context, const _CycleSheetResult(null)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '반복 끄고 5 · 15 · 25분으로 돌아가기',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _accent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Container(height: 1, color: _border.withValues(alpha: 0.7)),
  );

  Widget _row({
    required String label,
    required String hint,
    required int value,
    required String unit,
    required List<int> choices,
    required ValueChanged<int> onPick,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border, width: 1.2),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: value,
                isDense: true,
                borderRadius: BorderRadius.circular(12),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: _accent,
                ),
                style: GoogleFonts.notoSansKr(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
                items: [
                  for (final choice in choices)
                    DropdownMenuItem(
                      value: choice,
                      child: Text('$choice$unit'),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) onPick(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 전체 보기 (집중 모드)
// ─────────────────────────────────────────────────────────────

/// 남은 시간을 발자국으로 두른 원.
///
/// 숫자만 보면 얼마나 남았는지 머리로 계산해야 한다. 원을 두른 발자국이
/// 하나씩 사라지면 눈으로 바로 읽힌다. 12시 자리에서 시계 방향으로 지워진다.
///
/// 스무 개다. 더 촘촘하면 하나 사라진 게 눈에 안 띄어서 줄어드는 맛이 없고,
/// 25분짜리 한 구간에서 대략 1분 15초에 하나씩 빠지는 속도가 된다.
class PawRing extends StatelessWidget {
  const PawRing({
    super.key,
    required this.progress,
    required this.size,
    this.pawCount = 20,
    this.activeColor = const Color(0xFF7C6BE0),
    this.fadedColor = const Color(0xFFE3DCFA),
    this.wave,
    this.showWater = true,
    this.child,
  });

  /// 남은 비율. 1이면 전부 찍혀 있고 0이면 다 사라진다.
  final double progress;
  final double size;
  final int pawCount;
  final Color activeColor;
  final Color fadedColor;

  /// 물결을 흔드는 애니메이션. 0에서 1로 돌면 한 주기다.
  ///
  /// 값이 아니라 애니메이션 자체를 받는다. 값으로 받으면 물결이 한 프레임
  /// 움직일 때마다 발자국 스물여덟 개까지 통째로 다시 만들어진다.
  final Animation<double>? wave;

  final bool showWater;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    // 반올림하지 않는다. 0.9개 남았을 때 하나로 올려버리면 시간이 다 됐는데도
    // 발자국이 남아 있다.
    final remaining = (clamped * pawCount).floor();
    final radius = size / 2 - 18;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (showWater)
            RepaintBoundary(
              child: SizedBox(
                width: radius * 1.72,
                height: radius * 1.72,
                child: AnimatedBuilder(
                  animation: wave ?? const AlwaysStoppedAnimation(0.0),
                  builder: (_, _) => CustomPaint(
                    painter: _WaterPainter(
                      level: clamped,
                      phase: wave?.value ?? 0,
                    ),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < pawCount; i++)
            _paw(index: i, radius: radius, isOn: i < remaining),
          // 가운데 내용은 원 안쪽을 넘지 않게 묶는다. 안 묶으면 시계가
          // 발자국을 뚫고 나간다.
          if (child != null) SizedBox(width: radius * 1.4, child: child),
        ],
      ),
    );
  }

  Widget _paw({
    required int index,
    required double radius,
    required bool isOn,
  }) {
    // 12시에서 시작해 시계 방향으로 돈다.
    final angle = (index / pawCount) * 2 * math.pi - math.pi / 2;
    return Transform.translate(
      offset: Offset(radius * math.cos(angle), radius * math.sin(angle)),
      child: Transform.rotate(
        // 발끝이 원 바깥을 보게 돌린다. 그냥 두면 전부 같은 방향이라
        // 원을 두른 느낌이 안 난다.
        angle: angle + math.pi / 2,
        child: Opacity(
          opacity: isOn ? 1 : 0.45,
          child: SvgPicture.asset(
            'assets/icons/paw.svg',
            width: 15,
            height: 15,
            colorFilter: ColorFilter.mode(
              isOn ? activeColor : fadedColor,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }
}

/// 타이머만 크게 보는 화면.
///
/// 채팅창 안의 카드는 작아서 곁눈질용이다. 실제로 집중하는 동안에는 화면을
/// 통째로 내주는 편이 낫다. 여기서도 멈추고 되돌릴 수 있어야 카드로 돌아가지
/// 않는다.
class MasterTimerFocusScreen extends StatefulWidget {
  const MasterTimerFocusScreen({
    super.key,
    required this.onToggle,
    required this.onStop,
    required this.onToggleSound,
    required this.isSoundOn,
  });

  final Future<void> Function() onToggle;
  final Future<void> Function() onStop;
  final Future<void> Function() onToggleSound;
  final bool Function() isSoundOn;

  @override
  State<MasterTimerFocusScreen> createState() => _MasterTimerFocusScreenState();
}

class _MasterTimerFocusScreenState extends State<MasterTimerFocusScreen>
    with SingleTickerProviderStateMixin {
  final FocusTimerManager _manager = FocusTimerManager();
  Timer? _ticker;
  late final AnimationController _waveCtrl;

  static const Color _ink = Color(0xFF2F266C);
  static const Color _main = Color(0xFF7C6BE0);
  static const Color _accent = Color(0xFF9B8AF0);

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _waveCtrl.dispose();
    super.dispose();
  }

  String get _timeDisplay {
    final remain = _manager.getRemainSeconds();
    final m = (remain ~/ 60).toString().padLeft(2, '0');
    final s = (remain % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progress {
    final total = _manager.duration;
    if (total <= 0) return 0;
    return _manager.getRemainSeconds() / total;
  }

  /// 지금 무엇을 하는 중인지. 반복 설정 없이 한 번만 재는 중이면 회차가 없다.
  String get _phaseLabel {
    final step = _manager.cycleStep;
    if (step == null) return '집중 중';
    return step.phase.isWork ? '집중 중' : '휴식 중';
  }

  String? get _roundLabel {
    final setting = _manager.cycleSetting;
    final step = _manager.cycleStep;
    if (setting == null || step == null) return null;
    return '${step.round} / ${setting.rounds}회차';
  }

  String? get _nextLabel {
    final setting = _manager.cycleSetting;
    final step = _manager.cycleStep;
    if (setting == null || step == null) return null;
    final next = FocusCycle.next(setting, step);
    if (next == null) return '다음: 마지막 구간';
    return next.phase.isWork
        ? '다음: 집중 ${next.minutes}분'
        : '다음: 휴식 ${next.minutes}분';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final ringSize = (width * 0.78).clamp(240.0, 340.0);
    final round = _roundLabel;
    final next = _nextLabel;

    return Scaffold(
      backgroundColor: const Color(0xFFFBFAFF),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 0),
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_fullscreen_rounded),
                  color: _accent,
                  tooltip: '작게 보기',
                ),
              ),
            ),
            const Spacer(),
            PawRing(
              progress: _progress,
              size: ringSize,
              wave: _waveCtrl,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SvgPicture.asset(
                        'assets/icons/paw.svg',
                        width: 13,
                        height: 13,
                        colorFilter: const ColorFilter.mode(
                          _accent,
                          BlendMode.srcIn,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _phaseLabel,
                        style: GoogleFonts.notoSansKr(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      _timeDisplay,
                      maxLines: 1,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 52,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        color: _ink,
                      ),
                    ),
                  ),
                  if (round != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      round,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _main,
                      ),
                    ),
                  ],
                  if (next != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      next,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Padding(
              // 설명 문구를 뺀 자리만큼 아래 여백을 준다. 발자국이 줄어드는
              // 건 보면 알게 되는 일이라, 굳이 적어두면 화면만 어수선해진다.
              padding: const EdgeInsets.only(bottom: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _circleAction(
                    icon: Icons.close_rounded,
                    label: '종료',
                    onTap: () async {
                      await widget.onStop();
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                  const SizedBox(width: 14),
                  _wideAction(),
                  const SizedBox(width: 14),
                  _circleAction(
                    icon: widget.isSoundOn()
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    label: '백색소음',
                    onTap: () async {
                      await widget.onToggleSound();
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wideAction() {
    final running = _manager.running;
    // 멈춘 데는 두 가지가 있다. 눌렀다가 잠깐 세운 것과 아직 시작도 안 한 것.
    // 둘 다 "다시 시작"이라고 하면, 처음 여는 사람은 자기가 뭘 멈춘 줄 안다.
    final paused = _manager.pausedRemainSec != null;
    final label = running
        ? '일시정지'
        : paused
        ? '다시 시작'
        : '집중 시작';
    return GestureDetector(
      onTap: () async {
        await widget.onToggle();
        if (mounted) setState(() {});
      },
      child: Container(
        width: 150,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE7E0FA), width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              running ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 20,
              color: _main,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.notoSansKr(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String label,
    required Future<void> Function() onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE7E0FA), width: 1.4),
            ),
            child: Icon(icon, size: 20, color: _accent),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.notoSansKr(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// 원 안에 고인 물. 남은 시간만큼 차 있고 줄면서 빠진다.
///
/// 발자국이 정확한 눈금이고 이쪽은 분위기다. 그래서 가득 찼을 때도 원을 다
/// 채우지 않는다 — 꽉 찬 원은 시계처럼 읽히려 들어서, 발자국과 서로 다른
/// 값을 말하는 것처럼 보인다.
class _WaterPainter extends CustomPainter {
  const _WaterPainter({required this.level, required this.phase});

  /// 남은 비율 0~1.
  final double level;

  /// 물결 위상 0~1.
  final double phase;

  /// 가득 찼을 때 원 높이의 몇 할까지 차오르는지.
  ///
  /// 처음엔 절반만 채웠는데, 시작하자마자 반쯤 지난 것처럼 보였다. 가득 찬
  /// 데서 줄어드는 편이 "이만큼 남았다"로 바로 읽힌다.
  static const double _maxFill = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (level <= 0) return;
    final radius = size.width / 2;
    final center = Offset(radius, radius);
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );

    final fill = size.height * _maxFill * level;
    final surfaceY = size.height - fill;
    // 물이 얕아질수록 물결도 잔잔해진다. 한 방울 남았는데 크게 출렁이면
    // 남은 양이 실제보다 많아 보인다.
    final amplitude = (6.0 * level).clamp(1.0, 6.0);

    final path = Path()..moveTo(0, surfaceY);
    for (double x = 0; x <= size.width; x += 4) {
      final t = x / size.width;
      final y =
          surfaceY +
          math.sin((t * 2 + phase) * 2 * math.pi) * amplitude +
          math.sin((t * 3.3 + phase * 1.6) * 2 * math.pi) * amplitude * 0.35;
      path.lineTo(x, y);
    }
    path
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      path,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x66A99AE8), Color(0x997C6BE0)],
        ).createShader(Rect.fromLTWH(0, surfaceY, size.width, fill + 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaterPainter old) =>
      old.level != level || old.phase != phase;
}
