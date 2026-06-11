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
  String? _soundPath;
  bool _isActive = false;
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

    try {
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
      
      // Set to loop mode so native OS player handles repeating without needing Dart code
      await _player.setReleaseMode(ReleaseMode.loop);

      if (initialDelay == Duration.zero) {
        await _play();
      } else {
        _initialDelayTimer = Timer(initialDelay, () {
          _play();
        });
      }
    } catch (e) {
      debugPrint('모닝콜 알람 세션 시작 실패: $e');
    }
  }

  Future<void> stop() async {
    _isActive = false;
    _initialDelayTimer?.cancel();
    _initialDelayTimer = null;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('모닝콜 알람 세션 중지 실패: $e');
    }
  }

  Future<void> _play() async {
    if (!_isActive || _soundPath == null) return;
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource(_soundPath!));
    } catch (e) {
      debugPrint('모닝콜 알람 세션 재생 실패: $e');
    }
  }
}
