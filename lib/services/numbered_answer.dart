/// 목록에서 몇 번을 고르라고 물었을 때 오는 답을 읽는다.
///
/// 형식대로만 답하라고 일러두지만 지켜지지 않을 때가 있다. "2번요", "1번과
/// 3번입니다"처럼 온다. 그때 잘못 읽으면 엉뚱한 것이 고쳐지거나 사라지는데,
/// 사용자에게는 이유가 안 보인다.
///
/// 고를 것이 없다고 할 때는 NONE이라고 답하게 한다. 그 말이 들어 있으면
/// 숫자가 섞여 있어도 아무것도 고르지 않은 것으로 본다 — "1번은 다릅니다,
/// NONE" 같은 답에서 1을 집으면 안 된다.
library;

class NumberedAnswer {
  const NumberedAnswer._();

  /// 답에 적힌 번호를 0부터로 돌려준다. 범위 밖은 버린다.
  ///
  /// 사람이 세듯 1부터 적게 하고 읽을 때 0부터로 돌린다. 0번부터 적게 하면
  /// 그 자체를 자주 틀린다.
  static Set<int> read(String content, {required int count}) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return const {};
    if (RegExp(r'\bnone\b', caseSensitive: false).hasMatch(trimmed)) {
      return const {};
    }

    final picked = <int>{};
    for (final match in RegExp(r'\d+').allMatches(trimmed)) {
      final number = int.tryParse(match.group(0)!);
      if (number == null || number < 1 || number > count) continue;
      picked.add(number - 1);
    }
    return picked;
  }
}
