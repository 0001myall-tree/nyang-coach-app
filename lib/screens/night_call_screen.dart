import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nyang_coach/services/user_title_service.dart';
import 'coach_config.dart';

class NightCallScreen extends StatefulWidget {
  final String coachId;
  const NightCallScreen({super.key, required this.coachId});

  @override
  State<NightCallScreen> createState() => _NightCallScreenState();
}

class _NightCallScreenState extends State<NightCallScreen> {
  late final AudioPlayer _audioPlayer;
  late final String _safeCoachId;
  String _userTitle = UserTitleService.defaultTitle;

  @override
  void initState() {
    super.initState();
    _safeCoachId =
        widget.coachId == 'sec_female' || widget.coachId == 'sec_male'
        ? widget.coachId
        : 'sec_male';
    _audioPlayer = AudioPlayer();
    _loadUserTitle();
    _playNightCallAudio();
  }

  Future<void> _loadUserTitle() async {
    final title = await UserTitleService.getTitle();
    if (!mounted) return;
    setState(() {
      _userTitle = title;
    });
  }

  Future<void> _playNightCallAudio() async {
    final randNum = Random().nextInt(6) + 1;
    final soundPath = 'voice/${_safeCoachId}_night_$randNum.mp3';

    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.media,
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
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.play(AssetSource(soundPath));
    } catch (e) {
      debugPrint('나이트콜 오디오 재생 실패: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coach = CoachConfigs.get(_safeCoachId);
    final isFemale = _safeCoachId == 'sec_female';

    return Scaffold(
      backgroundColor: const Color(0xFF111827),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 156,
                  height: 156,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: const Color(0xFFA78BFA),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFA78BFA).withOpacity(0.28),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                    image: DecorationImage(
                      image: AssetImage(coach.imagePath),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                    ),
                  ),
                ),
                const SizedBox(height: 26),
                Text(
                  coach.name,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isFemale
                      ? '$_userTitle, 이제 하루를 정리하고\n취침 준비에 들어가실 시간이에요.'
                      : '$_userTitle, 이제 하루를 정리하고\n취침 준비에 들어가실 시간입니다.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.notoSansKr(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFE5E7EB),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _audioPlayer.stop();
                      if (context.mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B7CFF),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      elevation: 8,
                      shadowColor: const Color(0xFF8B7CFF).withOpacity(0.4),
                    ),
                    child: Text(
                      '나이트콜 확인했어요',
                      style: GoogleFonts.notoSansKr(
                        fontSize: 17,
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
    );
  }
}
