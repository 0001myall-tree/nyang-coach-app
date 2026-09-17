import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../screens/coach_config.dart';

class MorningCallAlarmSession {
  factory MorningCallAlarmSession() => _instance;
  MorningCallAlarmSession._internal();

  static final MorningCallAlarmSession _instance =
      MorningCallAlarmSession._internal();
  static const MethodChannel _alarmChannel = MethodChannel(
    'nyang_coach/morning_alarm',
  );

  final AudioPlayer _player = AudioPlayer();
  Timer? _initialDelayTimer;
  Timer? _watchdogTimer;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;
  String? _soundPath;
  bool _usesNativeAlarmSound = false;
  bool _isActive = false;
  bool _isPlaying = false;
  bool get isActive => _isActive;

  Future<void> start({
    required String coachId,
    String? soundName,
    Duration initialDelay = Duration.zero,
  }) async {
    await stop();

    final count = CoachConfigs.get(coachId).voiceCount;
    if (count <= 0) {
      _soundPath = null;
      _usesNativeAlarmSound = defaultTargetPlatform == TargetPlatform.android;
      if (!_usesNativeAlarmSound) return;
      _isActive = true;
      _isPlaying = true;
      await _startVibration();
      await _startNativeAlarmSound();
      return;
    }

    final selectedSoundName = soundName?.trim().isNotEmpty == true
        ? soundName!.trim()
        : '${coachId}_${Random().nextInt(count) + 1}';
    if (defaultTargetPlatform == TargetPlatform.android) {
      _soundPath = null;
      _usesNativeAlarmSound = true;
      _isActive = true;
      _isPlaying = true;
      await _startVibration();
      await _startNativeAlarmSound(soundName: selectedSoundName);
      return;
    }

    _soundPath = 'voice/$selectedSoundName.mp3';
    _usesNativeAlarmSound = false;
    _isActive = true;
    _isPlaying = false;

    try {
      await _completeSub?.cancel();
      await _stateSub?.cancel();
      _completeSub = _player.onPlayerComplete.listen((_) {
        _isPlaying = false;
        if (!_isActive) return;
        Future<void>.delayed(const Duration(milliseconds: 250), () {
          if (_isActive) _play();
        });
      });
      _stateSub = _player.onPlayerStateChanged.listen((state) {
        _isPlaying = state == PlayerState.playing;
      });

      await _player.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.music,
            audioFocus: AndroidAudioFocus.gainTransientExclusive,
          ),
          iOS: AudioContextIOS(category: AVAudioSessionCategory.playback),
        ),
      );
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _startVibration();

      if (initialDelay == Duration.zero) {
        await _play();
      } else {
        _initialDelayTimer = Timer(initialDelay, () {
          _play();
        });
      }
      _watchdogTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (!_isActive || _isPlaying) return;
        _play();
      });
    } catch (e) {
      debugPrint('모닝콜 알람 세션 시작 실패: $e');
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _isPlaying = false;
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    try {
      await _completeSub?.cancel();
      await _stateSub?.cancel();
      _completeSub = null;
      _stateSub = null;
      await _player.stop();
      await _stopNativeAlarmSound();
      await _stopVibration();
      _usesNativeAlarmSound = false;
      // 네이티브 소리를 안 쓴 경우에도 부른다. 알람이 울린 자리와 끄는 자리가
      // 늘 같은 것은 아니라서, 올려둔 볼륨만 남을 수 있다.
      await _restoreAlarmVolume();
    } catch (e) {
      debugPrint('모닝콜 알람 세션 중지 실패: $e');
    }
  }

  Future<void> _startVibration() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmChannel.invokeMethod('startMorningVibration');
    } catch (e) {
      debugPrint('모닝콜 진동 시작 실패: $e');
    }
  }

  Future<void> _stopVibration() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmChannel.invokeMethod('stopMorningVibration');
    } catch (e) {
      debugPrint('모닝콜 진동 중지 실패: $e');
    }
  }

  Future<void> _startNativeAlarmSound({String? soundName}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmChannel.invokeMethod('startMorningAlarmSound', {
        if (soundName != null && soundName.isNotEmpty) 'soundName': soundName,
      });
    } catch (e) {
      debugPrint('모닝콜 기본 알람음 시작 실패: $e');
    }
  }

  Future<void> _stopNativeAlarmSound() async {
    if (!_usesNativeAlarmSound) return;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmChannel.invokeMethod('stopMorningAlarmSound');
    } catch (e) {
      debugPrint('모닝콜 기본 알람음 중지 실패: $e');
    }
  }

  /// 모닝콜이 울리는 동안만 올려뒀던 폰 알람 볼륨을 되돌린다.
  ///
  /// 안 올렸으면 네이티브 쪽에서 그냥 돌아가므로 매번 불러도 된다.
  Future<void> _restoreAlarmVolume() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _alarmChannel.invokeMethod('restoreMorningVolume');
    } catch (e) {
      debugPrint('모닝콜 볼륨 되돌리기 실패: $e');
    }
  }

  Future<void> _play() async {
    if (!_isActive || _soundPath == null) return;
    try {
      await _player.stop();
      _isPlaying = false;
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(AssetSource(_soundPath!));
    } catch (e) {
      debugPrint('모닝콜 알람 세션 재생 실패: $e');
    }
  }
}
