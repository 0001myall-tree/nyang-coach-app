import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_design_tokens.dart';

Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor:
        barrierColor ??
        Colors.black.withValues(alpha: AppDesignTokens.sheetBarrierAlpha),
    builder: builder,
  );
}

class AppBottomSheetScaffold extends StatelessWidget {
  const AppBottomSheetScaffold({
    super.key,
    required this.body,
    this.footer,
    this.backgroundColor = AppDesignTokens.surface,
    this.maxHeightFactor = AppDesignTokens.sheetMaxHeightFactor,
    this.maxWidth = AppDesignTokens.sheetMaxWidth,
    this.showHandle = true,
    this.handleColor = const Color(0xFFE5E7EB),
    this.contentPadding = const EdgeInsets.fromLTRB(
      AppDesignTokens.sheetHorizontalPadding,
      0,
      AppDesignTokens.sheetHorizontalPadding,
      AppDesignTokens.sheetContentBottomPadding,
    ),
    this.footerPadding,
  });

  final Widget body;
  final Widget? footer;
  final Color backgroundColor;
  final double maxHeightFactor;
  final double maxWidth;
  final bool showHandle;
  final Color handleColor;
  final EdgeInsetsGeometry contentPadding;
  final EdgeInsetsGeometry? footerPadding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final usableHeight = math.max(
      240.0,
      media.size.height -
          media.viewInsets.bottom -
          AppDesignTokens.sheetTopMargin,
    );
    final maxSheetHeight = usableHeight * maxHeightFactor.clamp(0.5, 1.0);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxSheetHeight,
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppDesignTokens.radiusSheet),
            ),
            child: Material(
              color: backgroundColor,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showHandle)
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: AppBottomSheetHandle(color: handleColor),
                      ),
                    Flexible(
                      child: Padding(padding: contentPadding, child: body),
                    ),
                    if (footer != null)
                      Padding(
                        padding:
                            footerPadding ??
                            EdgeInsets.fromLTRB(
                              AppDesignTokens.sheetFooterHorizontalPadding,
                              AppDesignTokens.sheetFooterTopPadding,
                              AppDesignTokens.sheetFooterHorizontalPadding,
                              math.max(
                                AppDesignTokens.sheetFooterBottomPadding,
                                media.padding.bottom + 10,
                              ),
                            ),
                        child: footer!,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppBottomSheetHandle extends StatelessWidget {
  const AppBottomSheetHandle({super.key, this.color = const Color(0xFFE5E7EB)});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppDesignTokens.sheetHandleWidth,
      height: AppDesignTokens.sheetHandleHeight,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppDesignTokens.sheetHandleRadius),
      ),
    );
  }
}
