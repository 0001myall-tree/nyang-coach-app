/// 두 할 일 이름이 같은 일을 가리키는지 본다.
///
/// 코치가 이미 목록에 있는 일을 새 할 일로 다시 제안할 때가 있다. 프롬프트에
/// 붙이지 말라고 적어두었지만 지시는 지켜지지 않을 때가 있고, 그때 사용자에게는
/// 방금 하겠다고 말한 그 일이 새 할 일 카드로 다시 뜬 것으로 보인다.
///
/// 글자가 똑같은 경우만 막으면 절반은 빠져나간다. 코치는 같은 일을 조금 다르게
/// 적는다 — '지원서 비교견적서 내기'와 '지원서 비교견적서 제출'처럼.
///
/// 애매하면 같은 일로 본다. 잘못 걸러내면 사용자가 플래너에서 직접 적으면
/// 되지만, 잘못 통과시키면 목록에 거의 같은 이름이 둘 남고 어느 쪽을 체크해야
/// 하는지부터 헷갈린다.
library;

class TaskNameSimilarity {
  /// 한쪽이 다른 쪽을 통째로 품고 있으면 같은 일로 본다.
  ///
  /// '사업계획서 쓰기'가 이미 있는데 코치가 '오늘 사업계획서 쓰기'라고 적는
  /// 경우다. 너무 짧은 이름끼리는 우연히 겹칠 수 있어 그때는 같은지만 본다.
  static const int _minSubstringLength = 3;

  /// 마지막 낱말을 뗀 앞부분이 이만큼은 돼야 견준다.
  ///
  /// '책 읽기'와 '책 사기'는 앞이 같지만 다른 일이다. 한두 글자는 우연히 겹친다.
  static const int _minHeadLength = 3;

  /// 같은 일을 가리키는가.
  static bool isSameWork(String a, String b) {
    final left = normalize(a);
    final right = normalize(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    if (left.length >= _minSubstringLength &&
        right.length >= _minSubstringLength &&
        (left.contains(right) || right.contains(left))) {
      return true;
    }

    // 끝말만 다른 경우. 같은 일을 두고 '내기'와 '제출', '쓰기'와 '작성'처럼
    // 끝말만 바꿔 적는 일이 흔하다.
    //
    // 앞이 같은데 뒤가 정말 다른 일도 걸린다 — '보고서 초안 쓰기'와 '보고서
    // 초안 검토'는 다른 일이다. 그래도 이쪽을 택한다.
    final leftHead = head(a);
    return leftHead.isNotEmpty && leftHead == head(b);
  }

  /// 견주기 전에 지우는 것들. 띄어쓰기와 문장부호는 이름을 가르지 않는다.
  static String normalize(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[.。!！?？~〜]'), '')
      .trim()
      .toLowerCase();

  /// 마지막 낱말을 뗀 앞부분.
  ///
  /// 낱말이 하나뿐이면 뗄 것이 없어 빈 문자열이다. '청소'와 '청소기 수리'가
  /// 같은 일이 되면 안 된다.
  static String head(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.length < 2) return '';
    final joined = normalize(words.sublist(0, words.length - 1).join());
    return joined.length < _minHeadLength ? '' : joined;
  }
}
