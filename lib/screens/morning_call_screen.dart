import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'coach_config.dart';
import 'dart:math';

class MorningCallScreen extends StatefulWidget {
  final String coachId;
  final String? soundName;
  const MorningCallScreen({super.key, required this.coachId, this.soundName});

  @override
  State<MorningCallScreen> createState() => _MorningCallScreenState();
}

class _MorningCallScreenState extends State<MorningCallScreen> {
  late final AudioPlayer _audioPlayer;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _playMorningCallAudio();
  }

  Future<void> _playMorningCallAudio() async {
    // CoachConfig에서 목소리 개수 읽기 → 나중에 목소리 추가 시 coach_config.dart만 수정하면 됨
    final count = CoachConfigs.get(widget.coachId).voiceCount;
    if (count > 0) {
      final soundName =
          widget.soundName ??
          '${widget.coachId}_${Random().nextInt(count) + 1}';
      final soundPath = 'voice/$soundName.mp3';

      try {
        await _audioPlayer.setAudioContext(
          AudioContext(
            android: AudioContextAndroid(
              usageType: AndroidUsageType.alarm,
              contentType: AndroidContentType.music,
              audioFocus: AndroidAudioFocus.none,
            ),
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {
                AVAudioSessionOptions.mixWithOthers,
                AVAudioSessionOptions.defaultToSpeaker,
              },
            ),
          ),
        );
        await _audioPlayer.setVolume(1.0);
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
        await _audioPlayer.play(AssetSource(soundPath));
        if (mounted) {
          setState(() {
            _isPlaying = true;
          });
        }
      } catch (e) {
        debugPrint('모닝콜 오디오 재생 실패: $e');
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    FlutterLocalNotificationsPlugin().cancel(id: 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 코치 설정 가져오기 (랜덤일 경우 이미 실제 coachId가 넘어옴)
    final coach = CoachConfigs.get(widget.coachId);

    return Scaffold(
      backgroundColor: Colors.white.withOpacity(0.95),
      body: Stack(
        children: [
          // 배경 블러 효과 느낌
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white, const Color(0xFFF3EFFF)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 코치 이미지
                    Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(
                          color: const Color(0xFF8B7CFF),
                          width: 4,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        image: DecorationImage(
                          image: AssetImage(coach.imagePath),
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B7CFF),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                '⏰',
                                style: TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 코치 이름
                    Text(
                      coach.name,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 메시지
                    Text(
                      '약속한 시간이 되었어요!\n얼른 일어나서 오늘을 시작해볼까요?',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.notoSansKr(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF6B7280),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 48),

                    // 끄기 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          // 오디오 중지 및 화면 닫기
                          _audioPlayer.stop();
                          FlutterLocalNotificationsPlugin().cancel(id: 0);
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B7CFF),
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                          elevation: 10,
                          shadowColor: const Color(0xFF8B7CFF).withOpacity(0.5),
                        ),
                        child: Text(
                          '모닝콜 끄고 시작하기',
                          style: GoogleFonts.notoSansKr(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
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
}
