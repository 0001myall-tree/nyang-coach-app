import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_design_tokens.dart';

/// 냥냥코치 미리보기 시연이 끝난 뒤 보여주는 마지막 CTA.
/// 반환값: '플랜 시작하기'를 눌렀으면 true, '조금 더 둘러볼게요'를 눌렀으면 false.
/// 실제 플랜 안내 시트를 띄우는 것은 호출부(시연 화면을 pop한 뒤, 원래 채팅 화면의
/// context로)에서 처리한다 — 여기서 바로 띄우면 이 시트가 닫히는 시점의 context가
/// 곧 pop될 시연 화면의 context라서 안전하지 않다.
Future<bool> showCatOnboardingCta(BuildContext context) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    isScrollControlled: true,
    builder: (ctx) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        32,
        24,
        MediaQuery.of(ctx).padding.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🐾', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 16),
          Text(
            '냥냥코치와 함께\n하루를 시작해 보세요.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansKr(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.textPrimary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppDesignTokens.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.buttonRadius,
                  ),
                ),
                elevation: 0,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                '플랜 시작하기',
                style: GoogleFonts.notoSansKr(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFF4F4F4),
                foregroundColor: AppDesignTokens.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    AppDesignTokens.buttonRadius,
                  ),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                '조금 더 둘러볼게요',
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
  return result ?? false;
}
