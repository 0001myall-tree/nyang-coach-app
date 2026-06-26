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
                style: GoogleFonts.notoSansKr(
                  fontSize: AppDesignTokens.textMeta,
                  fontWeight: FontWeight.w900,
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
