import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppDesignTokens.cardPadding),
    this.backgroundColor = AppDesignTokens.surface,
    this.borderColor = AppDesignTokens.brandBorder,
    this.selectedBorderColor = AppDesignTokens.brand,
    this.selected = false,
    this.borderWidth = 1.2,
    this.selectedBorderWidth = 2.2,
    this.radius = AppDesignTokens.cardRadius,
    this.shadows,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color backgroundColor;
  final Color borderColor;
  final Color selectedBorderColor;
  final bool selected;
  final double borderWidth;
  final double selectedBorderWidth;
  final double radius;
  final List<BoxShadow>? shadows;

  @override
  Widget build(BuildContext context) {
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? selectedBorderColor : borderColor,
          width: selected ? selectedBorderWidth : borderWidth,
        ),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: card,
      ),
    );
  }
}
