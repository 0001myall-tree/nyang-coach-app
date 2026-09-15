import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_font.dart';

import '../theme/app_design_tokens.dart';

/// 배너 답변 팝업의 보기 하나.
class BannerAnswerAction {
  const BannerAnswerAction({
    required this.label,
    required this.icon,
    this.isPrimary = false,
    this.onTap,
  });

  final String label;

  /// assets/icons 아래 파일 이름(확장자 없이).
  final String icon;

  /// 지금 상태에서 가장 그럴듯한 답. 한 팝업에 하나만 둔다.
  final bool isPrimary;

  final VoidCallback? onTap;
}

/// 배너를 눌러 들어왔을 때 뜨는 답변 팝업.
///
/// 기본 AlertDialog였다. 보기 셋이 오른쪽에 텍스트로만 붙어 계단처럼 보였고,
/// 질문은 왼쪽에 있어서 눈이 두 번 움직였다. 팝업도 내용보다 한참 컸다.
///
/// 앱의 다른 자리와 같은 모양으로 맞춘다 — 채팅방의 선택지 버튼과 같은 둥근
/// 모서리, 같은 손글씨체다. 셋 다 "아직 안 한 말이고, 누르면 내 말이 되는"
/// 같은 부류라 글씨체도 그쪽을 따른다.
class BannerAnswerDialog extends StatelessWidget {
  const BannerAnswerDialog({required this.message, required this.actions});

  final String message;
  final List<BannerAnswerAction> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppDesignTokens.surface,
      surfaceTintColor: AppDesignTokens.surface,
      elevation: 8,
      shadowColor: AppDesignTokens.brand.withValues(alpha: 0.18),
      // 팝업이 늘 최대 폭으로 서 있으면, 짧은 질문에도 빈 자리가 넓게 남아
      // 글이 한쪽에 몰린 것처럼 보인다. 폭은 아래 IntrinsicWidth가 내용에서
      // 정하고, 여기 값은 "이보다 가장자리에 붙지는 않는다"는 선만 긋는다.
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDesignTokens.cardRadius),
      ),
      child: Padding(
        // 좌우를 같은 값으로 둔다. 질문과 보기가 같은 세로선에서 시작해야
        // 눈이 한 번만 움직인다.
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        // 폭을 내용에 맞춘다. 질문 한 줄이 가장 긴 경우가 대부분이라, 일정
        // 이름이 짧으면 팝업도 같이 좁아진다. 화면에 안 들어갈 만큼 길면
        // 바깥 제약이 잘라주고 그때부터 줄바꿈이 된다.
        //
        // 보기 버튼은 그렇게 정해진 폭을 그대로 채운다(stretch). 버튼마다
        // 글자 수가 달라도 너비는 하나로 맞아야 세로로 나란히 선다.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                style: appFont(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _buildAction(context, actions[i]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAction(BuildContext context, BannerAnswerAction action) {
    final ink = action.isPrimary ? Colors.white : AppDesignTokens.brandPressed;
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        action.onTap?.call();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: action.isPrimary
              ? AppDesignTokens.brand
              : AppDesignTokens.brandSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: action.isPrimary
                ? AppDesignTokens.brand
                : AppDesignTokens.brandBorder,
          ),
        ),
        child: Row(
          children: [
            SvgPicture.asset(
              'assets/icons/${action.icon}.svg',
              width: 14,
              height: 14,
              colorFilter: ColorFilter.mode(ink, BlendMode.srcIn),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                action.label,
                // 채팅방 선택지·빠른 답장 칩과 같은 손글씨체. 셋 다 아직 안 한
                // 말이고, 누르면 내 말이 된다.
                style: GoogleFonts.gaegu(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
