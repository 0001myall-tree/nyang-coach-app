/// 두 할 일 이름이 같은 일을 가리키는지 본다.
///
/// 코치가 이미 목록에 있는 일을 새 할 일로 다시 제안할 때가 있다. 프롬프트에
/// 붙이지 말라고 적어두었지만 지시는 지켜지지 않을 때가 있고, 그때 사용자에게는
/// 방금 하겠다고 말한 그 일이 새 할 일 카드로 다시 뜬 것으로 보인다.
///
/// 여기서 보는 것은 글자뿐이다. 글자만으로 확실한 것만 잡고, 애매한 것은
/// 건드리지 않는다.
///
/// '지원서 비교견적서 내기'와 '지원서 비교견적서 제출', '책 읽기'와 '독서'는
/// 글자로 가를 수 없다. 앞말이 같으면 같은 일로 치는 규칙을 뒀다가 걷어냈다 —
/// '보고서 초안 쓰기'가 있으면 '보고서 초안 검토'까지 사라져서, 다른 일을
/// 제안하지 못하게 됐다. 그런 판단은 [SameWorkCheck]가 뜻을 보고 한다.
library;

class TaskNameSimilarity {
  /// 한쪽이 다른 쪽을 통째로 품고 있으면 같은 일로 본다.
  ///
  /// '사업계획서 쓰기'가 이미 있는데 코치가 '오늘 사업계획서 쓰기'라고 적는
  /// 경우다. 너무 짧은 이름끼리는 우연히 겹칠 수 있어 그때는 같은지만 본다.
  static const int _minSubstringLength = 3;

  /// 글자만 보고 같은 일이라고 할 수 있는가.
  ///
  /// 여기서 false라고 다른 일이라는 뜻은 아니다. 글자로는 모르겠다는 뜻이다.
  static bool isSameWork(String a, String b) {
    final left = normalize(a);
    final right = normalize(b);
    if (left.isEmpty || right.isEmpty) return false;
    if (left == right) return true;

    return left.length >= _minSubstringLength &&
        right.length >= _minSubstringLength &&
        (left.contains(right) || right.contains(left));
  }

  /// 견주기 전에 지우는 것들. 띄어쓰기와 문장부호는 이름을 가르지 않는다.
  static String normalize(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[.。!！?？~〜]'), '')
      .trim()
      .toLowerCase();

}
