import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_design_tokens.dart';

enum AppButtonVariant { primary, secondary, outline }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.height = AppDesignTokens.buttonHeight,
    this.fullWidth = true,
    this.backgroundColor,
    this.foregroundColor,
    this.disabledBackgroundColor,
    this.borderColor,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonVariant variant;
  final double height;
  final bool fullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final colors = _AppButtonColors.forVariant(
      variant,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      disabledBackgroundColor: disabledBackgroundColor,
      borderColor: borderColor,
    );

    final button = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: AppDesignTokens.minTouchTarget,
        minWidth: fullWidth ? double.infinity : AppDesignTokens.minTouchTarget,
      ),
      child: SizedBox(
        width: fullWidth ? double.infinity : null,
        height: height < AppDesignTokens.minTouchTarget
            ? AppDesignTokens.minTouchTarget
            : height,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: enabled
                ? colors.background
                : colors.disabledBackground,
            foregroundColor: colors.foreground,
            disabledForegroundColor: colors.foreground.withValues(alpha: 0.62),
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesignTokens.buttonHorizontalPadding,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDesignTokens.buttonRadius),
              side: BorderSide(color: colors.border),
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                IconTheme.merge(
                  data: const IconThemeData(size: 20),
                  child: icon!,
                ),
                const SizedBox(width: AppDesignTokens.buttonIconGap),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.notoSansKr(
                      fontSize: AppDesignTokens.textAction,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return fullWidth ? button : IntrinsicWidth(child: button);
  }
}

class _AppButtonColors {
  const _AppButtonColors({
    required this.background,
    required this.foreground,
    required this.disabledBackground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color disabledBackground;
  final Color border;

  static _AppButtonColors forVariant(
    AppButtonVariant variant, {
    Color? backgroundColor,
    Color? foregroundColor,
    Color? disabledBackgroundColor,
    Color? borderColor,
  }) {
    return switch (variant) {
      AppButtonVariant.primary => _AppButtonColors(
        background: backgroundColor ?? AppDesignTokens.brand,
        foreground: foregroundColor ?? Colors.white,
        disabledBackground: disabledBackgroundColor ?? const Color(0xFFD8CEF8),
        border: borderColor ?? Colors.transparent,
      ),
      AppButtonVariant.secondary => _AppButtonColors(
        background: backgroundColor ?? AppDesignTokens.surface,
        foreground: foregroundColor ?? AppDesignTokens.brandDark,
        disabledBackground:
            disabledBackgroundColor ?? AppDesignTokens.surfaceSubtle,
        border: borderColor ?? AppDesignTokens.brandBorder,
      ),
      AppButtonVariant.outline => _AppButtonColors(
        background: backgroundColor ?? Colors.transparent,
        foreground: foregroundColor ?? AppDesignTokens.brandDark,
        disabledBackground:
            disabledBackgroundColor ?? AppDesignTokens.surfaceSubtle,
        border: borderColor ?? AppDesignTokens.brandBorder,
      ),
    };
  }
}
