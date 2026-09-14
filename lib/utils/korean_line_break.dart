import 'package:flutter/widgets.dart';

/// 한글은 글자 아무 데서나 줄이 바뀐다. 그래서 "골라둘까냥?"이 "골 /
/// 라둘까냥?"처럼 낱말 한가운데서 잘린다. 낱말 안의 글자들을 줄바꿈 금지
/// 문자로 이어 붙여, 띄어쓴 자리에서만 줄이 바뀌게 한다.
///
/// 낱말 하나가 한 줄보다 길면 그때는 원래대로 중간에서 잘린다.
String keepWordsWhole(String text) {
  const wordJoiner = '⁠';
  return text
      .split(' ')
      .map((word) => word.characters.join(wordJoiner))
      .join(' ');
}
