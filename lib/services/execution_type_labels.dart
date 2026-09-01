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

import 'execution_funnel.dart';

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
    '자유형': '플래너에 뜸하게 오거나 아직 셀 것이 적어 유형을 말하기 이른 상태',
  };

  static List<String> get all => meanings.keys.toList(growable: false);

  /// 프롬프트에 적을 목록. 이름마다 뜻이 붙는다.
  static String get listForPrompt => meanings.entries
      .map((entry) => '     · ${entry.key} — ${entry.value}')
      .join('\n');

  /// 판정을 못 받았을 때 앱이 대신 고르는 이름.
  ///
  /// 프렌즈 등급도 이름은 코치가 고른다. 다만 한도가 찼거나 통신이 끊기면
  /// 배지가 통째로 비는데, 그럴 바에는 깔때기가 짚은 자리를 그대로 이름으로
  /// 쓰는 편이 낫다. 문턱으로 붙이던 옛 이름과 달리 적어도 새는 자리는 맞다.
  static String? fromFunnel(ExecutionFunnel funnel) {
    if (!funnel.hasEnough) return null;
    // 밤에 몰아 시작하는 것은 어느 단계가 새는지와 다른 축이라, 세 축이 다
    // 잘 지나갈 때만 이름 자리를 준다.
    final leak = funnel.leak;
    if (leak == FunnelLeak.none && funnel.lateNightDays >= 2) return '벼락치기형';
    return switch (leak) {
      FunnelLeak.none => '안정형',
      FunnelLeak.planning => '계획 편차형',
      FunnelLeak.amount => '계획 과다형',
      FunnelLeak.starting => '시작 편차형',
      FunnelLeak.finishing => '시작 꾸준형',
      FunnelLeak.notStarted => '자유형',
    };
  }

  /// 이름마다 붙는 고정 한마디.
  ///
  /// 코치를 부를 수 없는 등급에서 쓴다. 그 등급도 이름은 코치가 고르므로
  /// 짚는 자리는 맞고, 그 자리에 맞는 말이 나간다. 문구까지 매주 API로
  /// 만들 만한 자리는 아니다.
  ///
  /// 강점을 먼저 말하고 그다음에 하나만 권한다. "이대로도 괜찮아"로 끝내지도,
  /// 못한 것부터 세지도 않는다.
  static const Map<String, String> comments = {
    '안정형':
        '계획하고 시작하고 끝내는 게 다 이어지고 있어. 지금 방식이 맞으니 여기서 하나 더 다지고 싶으면, 끝낸 김에 내일 할 것 하나를 미리 적어두는 걸 얹어봐.',
    '계획 편차형':
        '적어둔 날엔 곧잘 해내는데 적는 날 자체가 드물어. 다 지키지 못할까 봐 아예 안 적게 되는 거라면, 하루에 딱 하나만 적는 걸로 문턱을 낮춰봐.',
    '계획 과다형':
        '매일 손은 대고 있어. 다만 하루에 적어두는 양이 실제로 해내는 양보다 많아서 남는 게 쌓여. 다음엔 하루치를 절반으로 줄여서 다 끝내는 경험부터 만들어봐.',
    '시작 편차형':
        '계획은 꾸준히 쓰는데 그중 손도 못 대는 날이 있어. 계획을 세운 것만으로 이미 한 것처럼 느껴져서 정작 시작할 힘이 빠지는 걸 수도 있어. 언제 어디서 할지까지 같이 정해두면 첫 발이 가벼워져.',
    '시작 꾸준형':
        '제일 어려운 시작은 매번 해내고 있어. 손댄 게 끝까지 안 가는 거니까, 이번엔 한 번에 걸리는 시간을 짧게 잡아서 끝내는 경험부터 만들어봐.',
    '편차형':
        '의욕이 켜지면 계획부터 완료까지 몰아치고 꺼지면 손을 놓는 편이야. 나쁜 게 아니라 에너지가 몰아서 도는 리듬인 거고, 관건은 손 놓는 날에도 제일 만만한 것 하나만 살짝 걸쳐두는 거야.',
    '벼락치기형':
        '결국 다 손을 대긴 하는데 시작이 밤 늦게 몰려 있어. 막판 하나만 보지 말고 중간에 나만의 마감을 두어 개 끼워두면 미루는 자리가 줄어들 거야.',
    '자유형':
        '아직 잘하고 못하고를 따질 단계는 아니야. 계획 세우는 것도 시작하는 것도 너무 무겁게 보지 마.',
  };

  static String? commentFor(String? label) =>
      label == null ? null : comments[label];

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
