import 'package:flutter/material.dart';

abstract final class AppDesignTokens {
  // Brand
  static const Color brand = Color(0xFF8B7CFF);
  static const Color brandDark = Color(0xFF6B5EA8);
  static const Color brandSoft = Color(0xFFF5F3FF);
  static const Color brandBorder = Color(0xFFE8E3F8);

  // Neutral text
  static const Color textPrimary = Color(0xFF3D3A4E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFFA0A0B0);
  static const Color textDisabled = Color(0xFFBBBBCC);

  // Surfaces
  static const Color surface = Colors.white;
  static const Color surfaceSubtle = Color(0xFFF9FAFB);
  static const Color divider = Color(0xFFF0EEF8);

  // Type scale
  static const double textMeta = 11;
  static const double textCaption = 12;
  static const double textBody = 14;
  static const double textAction = 16;
  static const double textTitle = 18;

  // Radius scale
  static const double radiusSmall = 8;
  static const double radiusMedium = 16;
  static const double radiusLarge = 20;
  static const double radiusPill = 24;
  static const double radiusSheet = 30;

  // Bottom sheets
  static const double sheetMaxWidth = 640;
  static const double sheetTopMargin = 24;
  static const double sheetHorizontalPadding = 20;
  static const double sheetContentBottomPadding = 20;
  static const double sheetFooterHorizontalPadding = 20;
  static const double sheetFooterTopPadding = 12;
  static const double sheetFooterBottomPadding = 20;
  static const double sheetHandleWidth = 48;
  static const double sheetHandleHeight = 4;
  static const double sheetHandleRadius = 2;
  static const double sheetBarrierAlpha = 0.38;
  static const double sheetMaxHeightFactor = 0.92;

  // Components
  static const double minTouchTarget = 48;
  static const double buttonHeight = 56;
  static const double buttonRadius = 18;
  static const double buttonHorizontalPadding = 18;
  static const double buttonIconGap = 8;
  static const double cardRadius = 22;
  static const double cardInnerRadius = 18;
  static const double cardPadding = 16;
  static const double chipMinHeight = 28;
  static const double chipRadius = 9;
  static const double chipHorizontalPadding = 10;
  static const double chipVerticalPadding = 5;

  // Immersive backgrounds
  static const double darkGlassOpacity = 0.25;
  static const double lightGlassOpacity = 0.58;
  static const double lightGlassBorderOpacity = 0.68;

  static const List<BoxShadow> bubbleShadow = [
    BoxShadow(color: Color(0x0F000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x24000000), blurRadius: 24, offset: Offset(0, 10)),
  ];
}
