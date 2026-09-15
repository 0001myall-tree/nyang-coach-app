import 'dart:ui' show Shadow, FontFeature;

import 'package:flutter/material.dart';

/// 앱 기본 글꼴 — 나눔스퀘어라운드 (네이버, SIL OFL 1.1).
///
/// 본문은 인터넷에서 받아오던 글꼴을 쓰고 있었다. 켤 때마다 내려받아야 했고,
/// 받기 전 한순간은 기본 글꼴로 보였다. 파일째 넣어두면 그럴 일이 없다.
///
/// 굵기는 네 단계뿐이다 — 300 / 400 / 700 / 800. 그 사이 값을 넘기면
/// 가장 가까운 것이 나온다. w900도 800(아주 굵게)으로 붙는다.
///
/// 손글씨체([GoogleFonts.gaegu])를 쓰는 채팅 칩처럼, 일부러 다른 글꼴을
/// 고른 자리는 이 함수를 쓰지 않는다.
const String kAppFontFamily = 'NanumSquareRound';

TextStyle appFont({
  TextStyle? textStyle,
  Color? color,
  Color? backgroundColor,
  double? fontSize,
  FontWeight? fontWeight,
  FontStyle? fontStyle,
  double? letterSpacing,
  double? wordSpacing,
  TextBaseline? textBaseline,
  double? height,
  Locale? locale,
  Paint? foreground,
  Paint? background,
  List<Shadow>? shadows,
  List<FontFeature>? fontFeatures,
  TextDecoration? decoration,
  Color? decorationColor,
  TextDecorationStyle? decorationStyle,
  double? decorationThickness,
}) {
  final base = textStyle ?? const TextStyle();
  return base.copyWith(
    fontFamily: kAppFontFamily,
    color: color,
    backgroundColor: backgroundColor,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontStyle: fontStyle,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    textBaseline: textBaseline,
    height: height,
    locale: locale,
    foreground: foreground,
    background: background,
    shadows: shadows,
    fontFeatures: fontFeatures,
    decoration: decoration,
    decorationColor: decorationColor,
    decorationStyle: decorationStyle,
    decorationThickness: decorationThickness,
  );
}
