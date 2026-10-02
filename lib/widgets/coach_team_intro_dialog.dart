/// 실행코치 소개 창. 코치 선택 화면의 "냥냥코치란?"과 채팅의 첫 안내 창이
/// 같은 창을 쓴다 — 따로 두었을 때는 한쪽만 고쳐져서, 채팅 쪽에는 옛날 긴
/// 소개가 남아 있었다.
///
/// [onStart]는 "함께 시작하기"를 누른 뒤 할 일. 없으면 닫기만 한다.
library;

import 'package:flutter/material.dart';

import '../screens/coach_config.dart';
import '../theme/app_design_tokens.dart';
import '../theme/app_font.dart';

void showCoachTeamIntroDialog(BuildContext context, {VoidCallback? onStart}) {
  final scrollController = ScrollController();
  showDialog(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.82,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
                child: Row(
                  children: [
                    const Icon(
                      Icons.rocket_launch_rounded,
                      color: Color(0xFFD8D2FF),
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '실행코치 소개',
                      style: appFont(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF8E8A9E),
                      ),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RawScrollbar(
                  controller: scrollController,
                  thumbColor: const Color(0xFFD8D2FF),
                  radius: const Radius.circular(8),
                  thickness: 5,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 따옴표를 글자 줄 안에 넣는다. 글자 바깥에 따로 띄워
                        // 두었더니 줄바꿈 위치에 따라 글자와 겹쳤다.
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                          child: Text.rich(
                            TextSpan(
                              style: appFont(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFA78BFA),
                                height: 1.5,
                              ),
                              children: const [
                                TextSpan(
                                  text: '“ ',
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Color(0xFFD8D2FF),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                TextSpan(
                                  text: '계획을 세우는 것보다, 실제로\n움직이는 것이 중요하지 않을까요?',
                                ),
                                TextSpan(
                                  text: ' ”',
                                  style: TextStyle(
                                    fontSize: 22,
                                    color: Color(0xFFD8D2FF),
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        Container(
                          height: 1,
                          margin: const EdgeInsets.only(bottom: 24),
                          color: const Color(0xFFF0F0F5),
                        ),
                        _teamIntroSpeaker(
                          imagePath: 'assets/images/cat.png',
                          name: '냥냥코치',
                          text: '우리는 여러분이 다시 움직일 수 있도록 함께하는 코치들이다냥.',
                        ),
                        _teamIntroSpeaker(
                          imagePath: 'assets/images/boyfriend.png',
                          name: '햇살 코치',
                          text: '프렌즈 코치들은 하기 싫은 날에도 옆에서 다정하게 응원해줘요.',
                        ),
                        _teamIntroSpeaker(
                          imagePath: 'assets/images/nyang_halbae.png',
                          name: CoachConfigs.all['nyang_halbae']?.name ?? '냥할배',
                          text: '마스터 코치는 목표와 패턴을 함께 보고, 머리를 맞대고 코칭해준다냥.',
                        ),
                        _teamIntroSpeaker(
                          imagePath: 'assets/images/sec_female.png',
                          name: CoachConfigs.all['sec_female']?.name ?? '비서 실장',
                          text:
                              '계획만 세우고 끝나는 플래너가 아니라, 행동을 함께하는 플래너. 그게 냥냥코치입니다.',
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 22),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFF0F0F5), width: 1),
                  ),
                ),
                // 할 일 탭 "루틴 하나 더 만들기"와 같은 모양. 꽉 찬 보라
                // 덩어리는 너무 기본형이라, 연한 바탕에 흰 동그라미 아이콘과
                // 진보라 글씨로 권하는 말투를 맞춘다.
                child: Material(
                  color: AppDesignTokens.brand.withValues(alpha: 0.16),
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () {
                      Navigator.pop(dialogContext);
                      onStart?.call();
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.pets,
                              size: 16,
                              color: AppDesignTokens.brand,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '함께 시작하기',
                            style: appFont(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: AppDesignTokens.brandStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Widget _teamIntroSpeaker({
  required String imagePath,
  required String name,
  required String text,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: Image.asset(
            imagePath,
            width: 52,
            height: 52,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: appFont(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFA78BFA),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFEDEAF8)),
                ),
                child: Text(
                  text,
                  style: appFont(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3D3A4E),
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
