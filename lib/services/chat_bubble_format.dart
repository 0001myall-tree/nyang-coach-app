/// 코치 답변을 말풍선에 앉히기 좋게 줄을 나눈다.
///
/// 2~4문장이 한 덩어리로 붙어 나오면 말풍선이 글자 벽처럼 보인다. 그렇다고
/// 문장마다 무조건 끊으면 "응. 알겠어."까지 두 줄이 돼서 오히려 산만하다.
///
/// 그래서 앞 문장이 길 때만 끊는다. 길게 말한 뒤에는 쉬어가고, 짧게 던진
/// 말끼리는 붙여 둔다.
///
/// 프롬프트로 시키지 않는 이유는 두 가지다. 형식 지시는 모델이 가장 잘
/// 흘리는 종류이고, 매 턴 토큰을 낸다. 여기서 하면 공짜고 어긋나지 않는다.
library;

class ChatBubbleFormat {
  const ChatBubbleFormat._();

  /// 이 길이를 넘는 문장 뒤에는 줄을 바꾼다.
  static const int longSentence = 15;

  /// 문장이 끝나고 다음 문장이 시작되는 자리.
  ///
  /// 종결 부호 **뒤에 공백이 있을 때만** 자른다. 그래야 "3.5시간"이나
  /// "오후 3시"의 마침표에 걸리지 않는다.
  static final RegExp _sentenceBreak = RegExp(r'(?<=[.!?…~])[ \t]+');

  /// 태그를 떼어낸 자리에 남은 문장부호를 치운다.
  ///
  /// "쉬워진다냥. [TASK: 책 한 페이지 읽기]," 같은 답변에서 태그를 떼면
  /// "쉬워진다냥. ,"가 남는다. 화면에는 코치가 말을 하다 만 것으로 보인다.
  static String tidyAfterTags(String text) {
    // replaceAll은 $1 같은 그룹 참조를 문자 그대로 넣는다. 여기서는
    // replaceAllMapped를 써야 앞 글자를 되살릴 수 있다.
    return text
        // 문장 끝에 홀로 남은 부호. "…다냥. ," → "…다냥."
        .replaceAllMapped(
          RegExp(r'([.!?…])\s*[,·/]+'),
          (match) => match.group(1)!,
        )
        // 부호 앞의 공백. "…다냥 ." → "…다냥."
        .replaceAllMapped(
          RegExp(r'[ \t]+([,.!?…])'),
          (match) => match.group(1)!,
        )
        // 줄 끝에 남은 부호. "…다냥ㅋㅋ ," → "…다냥ㅋㅋ"
        .replaceAll(RegExp(r'[,·/]+[ \t]*$', multiLine: true), '')
        .trim();
  }

  static String wrap(String text) {
    // 코치가 이미 줄을 나눠 보냈으면 그 뜻을 존중한다. 거기에 또 넣으면
    // 문단 사이가 벌어져 답변이 띄엄띄엄해 보인다.
    if (text.contains('\n')) return text;

    final parts = text.split(_sentenceBreak);
    if (parts.length < 2) return text;

    final buffer = StringBuffer(parts.first);
    for (var i = 1; i < parts.length; i++) {
      final previous = parts[i - 1].trim();
      buffer
        ..write(_isLong(previous) ? '\n' : ' ')
        ..write(parts[i]);
    }
    return buffer.toString();
  }

  /// 글자 수는 runes로 센다. length로 세면 이모지 하나가 둘로 잡힌다.
  static bool _isLong(String sentence) => sentence.runes.length >= longSentence;
}
