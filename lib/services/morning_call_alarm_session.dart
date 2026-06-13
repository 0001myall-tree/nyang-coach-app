import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';

class MorningCallAlarmSession {
  factory MorningCallAlarmSession() => _instance;
  MorningCallAlarmSession._internal();

  static final MorningCallAlarmSession _instance =
      MorningCallAlarmSession._internal();

  final AudioPlayer _player = AudioPlayer();
  Timer? _initialDelayTimer;
  Timer? _watchdogTimer;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<PlayerState>? _stateSub;
  String? _soundPath;
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
    if (count <= 0) return;

    final selectedSoundName = soundName?.trim().isNotEmpty == true
        ? soundName!.trim()
        : '${coachId}_${Random().nextInt(count) + 1}';
    _soundPath = 'voice/$selectedSoundName.mp3';
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
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.defaultToSpeaker},
          ),
        ),
      );
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.stop);

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
    } catch (e) {
      debugPrint('모닝콜 알람 세션 중지 실패: $e');
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
