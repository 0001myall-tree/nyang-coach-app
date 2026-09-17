import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_design_tokens.dart';

class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    this.icon,
    this.selected = false,
    this.enabled = true,
    this.backgroundColor,
    this.foregroundColor,
    this.selectedBackgroundColor,
    this.selectedForegroundColor,
    this.borderColor,
    this.boxShadow,
    this.fontSize,
    this.labelStyle,
    this.onTap,
  });

  final String label;
  final Widget? icon;
  final bool selected;
  final bool enabled;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? selectedBackgroundColor;
  final Color? selectedForegroundColor;
  final Color? borderColor;
  final List<BoxShadow>? boxShadow;
  final double? fontSize;

  /// 글씨를 따로 줄 때. 기본은 손글씨체다 - 칩에 적히는 건 사용자가 할 말이라
  /// 그렇게 맞춰뒀는데, 기능을 여는 버튼은 사용자의 말이 아니라 앱의 말이다.
  final TextStyle? labelStyle;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final effectiveBackground = selected
        ? selectedBackgroundColor ?? AppDesignTokens.brand
        : backgroundColor ?? AppDesignTokens.brandSoft;
    final effectiveForeground = selected
        ? selectedForegroundColor ?? Colors.white
        : foregroundColor ?? AppDesignTokens.brandPressed;
    final effectiveBorder = borderColor ?? AppDesignTokens.brandBorder;

    final chip = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: AppDesignTokens.chipMinHeight,
        minWidth: AppDesignTokens.minTouchTarget,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
          horizontal: AppDesignTokens.chipHorizontalPadding,
          vertical: AppDesignTokens.chipVerticalPadding,
        ),
        decoration: BoxDecoration(
          color: enabled ? effectiveBackground : AppDesignTokens.surfaceSubtle,
          borderRadius: BorderRadius.circular(AppDesignTokens.chipRadius),
          border: Border.all(
            color: enabled ? effectiveBorder : AppDesignTokens.divider,
          ),
          boxShadow: enabled ? boxShadow : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              IconTheme.merge(
                data: IconThemeData(
                  size: 16,
                  color: enabled
                      ? effectiveForeground
                      : AppDesignTokens.textDisabled,
                ),
                child: icon!,
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // 칩에 적히는 건 전부 사용자가 할 말이다. 코치 말풍선이 정자체라
                // 여기가 손글씨면 누가 말하는지가 글씨체로 갈린다. 정자체로 두면
                // 내 대답이 아니라 설문 보기처럼 읽힌다.
                //
                // 개구는 글자가 작게 앉아서 같은 숫자를 주면 옆의 정자체보다
                // 작아 보인다. 그래서 2를 더한다.
                style:
                    labelStyle?.copyWith(
                      color: enabled
                          ? effectiveForeground
                          : AppDesignTokens.textDisabled,
                    ) ??
                    GoogleFonts.gaegu(
                      fontSize: (fontSize ?? AppDesignTokens.textMeta) + 2,
                      fontWeight: FontWeight.w700,
                      color: enabled
                          ? effectiveForeground
                          : AppDesignTokens.textDisabled,
                    ),
              ),
            ),
          ],
        ),
      ),
    );

    if (onTap == null || !enabled) return chip;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppDesignTokens.chipRadius),
        child: chip,
      ),
    );
  }
}
