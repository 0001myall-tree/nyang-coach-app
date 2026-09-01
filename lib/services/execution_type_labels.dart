/// 실행 유형에 붙일 수 있는 이름들.
///
/// 이름은 코치가 주 1회 고른다. 앱이 문턱으로 정하던 때는 앞뒤가 정반대인 두
/// 사람이 같은 이름으로 묶였고, 이름마다 처방이 달려 있어 처방까지 같이
/// 틀렸다.
///
/// 다만 목록 밖의 이름은 받지 않는다. 기록 탭 배지가 이 이름을 그대로 쓰기
/// 때문에, 코치가 새 이름을 지어내면 화면이 모르는 말이 뜬다.
///
/// 이름에 처방을 달지 않는다. 무엇을 할지는 그 주의 숫자를 보고 코치가 정한다.
library;

class ExecutionTypeLabels {
  const ExecutionTypeLabels._();

  /// 어디에도 맞지 않을 때. 배지를 띄우지 않는다.
  static const String none = '없음';

  /// 이름과 그 이름이 가리키는 모양.
  ///
  /// 뜻은 고정하고 처방은 열어둔다. 이름만 주고 뜻을 안 주면 코치가 제 뜻을
  /// 갖다 붙여서, 같은 이름이 주마다 다른 것을 가리키게 된다. 그러면 사용자는
  /// 지난주 배지와 이번 주 배지가 같은 말인지도 알 수 없다.
  ///
  /// 반대로 무엇을 하라는 것까지 적어두면 예전으로 돌아간다 — 이름이 처방을
  /// 데려오고, 이름이 안 맞으면 처방까지 같이 틀린다.
  static const Map<String, String> meanings = {
    '안정형': '세 축이 다 잘 지나감. 지금 방식이 이 사람에게 맞게 돌아가는 중',
    '계획 편차형': '목록을 만드는 날 자체가 드묾. 다만 만든 날에는 대체로 해냄',
    '계획 과다형': '목록이 있는 날엔 많이 잡는데 그중 일부만 손댐. 자리가 아니라 한 번에 잡는 양이 문제',
    '시작 편차형': '목록은 꾸준히 만드는데, 그중 아예 손도 안 대는 날이 따로 있음',
    '시작 꾸준형': '손은 매번 대는데 손댄 것이 끝까지 가는 비율이 낮음',
    '편차형': '다 해낸 날과 아예 손도 안 댄 날로 갈림. 계획도 완료도 들쭉날쭉',
    '벼락치기형': '시작이 밤 늦게 몰림. 다 끝냈는지와 무관하게 손대는 시각이 막판',
    '자유형': '플래너에 뜸하게 오거나 아직 셀 것이 적어 유형을 말하기 이름',
  };

  static List<String> get all => meanings.keys.toList(growable: false);

  /// 프롬프트에 적을 목록. 이름마다 뜻이 붙는다.
  static String get listForPrompt => meanings.entries
      .map((entry) => '     · ${entry.key} — ${entry.value}')
      .join('\n');

  /// 코치 답변 끝에 붙은 `유형: 이름` 줄을 읽는다.
  ///
  /// 목록에 없는 이름이면 null. 지어낸 이름을 배지에 띄우느니 배지를 안 띄우는
  /// 편이 낫다.
  static String? readFrom(String reply) {
    final match = RegExp(
      r'^\s*유형\s*[:：]\s*(.+)$',
      multiLine: true,
    ).allMatches(reply).lastOrNull;
    if (match == null) return null;
    final picked = match.group(1)?.trim().replaceAll(RegExp(r'[.。]$'), '');
    if (picked == null || picked.isEmpty || picked == none) return null;
    return all.contains(picked) ? picked : null;
  }

  /// 그 줄을 떼어낸 본문. 화면에 그대로 나가는 말이라 남아 있으면 안 된다.
  static String strip(String reply) => reply
      .replaceAll(RegExp(r'^\s*유형\s*[:：].*$', multiLine: true), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

extension _LastOrNull<T> on Iterable<T> {
  T? get lastOrNull {
    T? found;
    for (final item in this) {
      found = item;
    }
    return found;
  }
}
