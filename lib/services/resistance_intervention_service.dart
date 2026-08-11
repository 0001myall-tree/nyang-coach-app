/// 실행 저항 개입을 종류별로 나누고, 거부당하면 다음 종류로 넘기는 로직.
///
/// 전에는 개입 전략 여러 개를 한 프롬프트에 다 실어놓고 모델이 고르게 했다.
/// 그러면 매번 가장 흔한 하나로 수렴하고, 사용자가 싫다고 해도 같은 제안을
/// 다시 밀면서 설득하는 일이 생긴다. 실제로 "커서 봐" → "싫어" → 또 "커서 봐"가
/// 반복됐다.
///
/// 그래서 고르는 일을 앱이 한다. 한 대화 안에서 이미 꺼낸 개입을 기억하고,
/// 거부당하면 아직 안 쓴 것 중 다음 것을 골라 그 하나만 프롬프트에 넣는다.
/// 모델에게는 선택지를 주지 않는다.
///
/// 시작 자리는 대화마다 한 칸씩 밀린다. 목록 맨 위부터 다시 훑으면 새 대화는
/// 늘 같은 방식으로 시작해서 금방 질린다. 마지막에 꺼낸 것 다음 자리를 기억해
/// 두고 거기서 시작하며, 한 바퀴 돌면 처음으로 돌아온다.
///
/// [interventions]의 rule 문구는 기존 프롬프트에 흩어져 있던 지시를 옮겨 담은
/// 것이다. 문구는 갈아끼워도 되고 순서를 바꿔도 되지만, id는 기록에 남으니
/// 한번 정한 뒤에는 바꾸지 않는 게 좋다.
library;

class ResistanceIntervention {
  const ResistanceIntervention({
    required this.id,
    required this.label,
    required this.rule,
    this.masterOnly = false,
    this.picksConcreteAction = false,
    this.preferredOnly = false,
  });

  /// 기록에 남는 식별자. 한번 정하면 바꾸지 않는다.
  final String id;

  /// 사람이 읽는 이름. 프롬프트에는 안 들어간다.
  final String label;

  /// 프롬프트에 그대로 들어가는 지시문.
  final String rule;

  /// 마스터 코치에게만 꺼낼 개입인지.
  ///
  /// 앱 기능을 가리키는 개입은 그 기능이 없는 코치에게 주면 안 된다. 없는
  /// 버튼을 누르라고 안내하게 된다.
  final bool masterOnly;

  /// 사용자가 지금 할 행동 하나를 골라주는 개입인지.
  ///
  /// 코치가 가진 분야별 노하우(할매의 청소 세분화 팁 같은 것)를 어디에 붙일지
  /// 가르는 값이다. 행동을 고르는 개입에는 그 목록이 곧 답이 되지만, 재정의나
  /// 품질 기준 낮추기처럼 "행동 제안은 붙이지 마세요"라고 못박은 개입에 붙이면
  /// 서로 반대되는 지시를 한 자리에 두는 꼴이 된다.
  final bool picksConcreteAction;

  /// 앱이 지목했을 때만 꺼내는 개입인지.
  ///
  /// 나머지는 어느 턴에 나와도 말이 되지만, 상태를 보고 꺼내야 하는 것도 있다.
  /// 몸 먼저 깨우기가 그렇다 — 기운이 없다고 하지 않은 사람에게 "손목 돌려봐"가
  /// 나오면 뜬금없고, 하고 나도 일이 한 칸 진행되지 않아 이 전략의 원칙과도
  /// 어긋난다. 순번에서는 빼두고 그 상태가 잡힌 턴에만 지목해서 꺼낸다.
  final bool preferredOnly;
}

class ResistanceInterventionService {
  const ResistanceInterventionService._();

  /// 꺼내는 순서. 시작 자리에서부터 내려가고, 끝에 닿으면 위로 돌아온다.
  ///
  /// 여기 있는 것들은 서로 대등하다. 어느 것이 먼저 나와도 말이 되도록 rule을
  /// 쓴다 — 앞이 막혔다는 걸 전제로 하는 문장을 넣으면 그게 첫 마디로 나올 때
  /// 거짓말이 된다.
  static const List<ResistanceIntervention> interventions = [
    ResistanceIntervention(
      id: 'shorten_time',
      label: '시간 낮추기',
      rule: '''[시간 낮추기]
- 할 일의 범위는 그대로 두고 붙잡는 시간만 낮추세요. 5~15분 사이에서 고르고 같은 숫자를 반복하지 마세요.
- 그 시간이 지나면 그만둬도 된다고 분명히 하세요.''',
    ),
    ResistanceIntervention(
      id: 'narrow_scope',
      label: '범위 좁히기',
      picksConcreteAction: true,
      rule: '''[범위 좁히기]
- 전체를 다 하려 하지 말고, 하고 나면 일이 한 칸 진행되는 작은 단위 하나만 정해주세요.
- 예: 청소=물건 하나 치우기, 설거지=컵 하나 씻기, 글쓰기=한 줄만 쓰기, 공부=한 문제만 풀기.
- 분리수거·약 먹기처럼 이미 하나의 행동인 일, 양치·샤워처럼 완료 단위가 정해진 일은 쪼개지 마세요.''',
    ),
    ResistanceIntervention(
      id: 'imagine_doing',
      label: '하고 있는 장면 떠올리기',
      rule: '''[하고 있는 장면 떠올리기]
- 지금 움직이라고 하지 말고, 그 일을 자연스럽게 하고 있는 자기 모습을 20초만 떠올려보게 하세요.
- 장면은 하나만. 예: 글쓰기=책상 앞에 앉아 수월하게 글을 쓰고 있는 모습, 청소=뭔가 들고 옮기고 있는 모습.
- 떠올린 것까지가 이번 턴입니다. 이어서 실제로 하라고 밀지 마세요.''',
    ),
    ResistanceIntervention(
      id: 'connect_purpose',
      label: '목적 연결',
      rule: '''[목적 연결]
- 이걸 끝내면 뭐가 나아지는지 하나만 구체적으로 짚어주세요. 예: 눈앞이 덜 복잡해짐, 내일 아침이 덜 정신없음.
- 목표나 비전의 중요성을 설명하지 마세요. 오늘 체감되는 변화면 됩니다.''',
    ),
    ResistanceIntervention(
      id: 'reframe_task',
      label: '과제 이미지 재정의',
      rule: '''[과제 이미지 재정의]
- 그 일이 실제보다 크게 느껴지고 있을 수 있다고 한 문장만 짚으세요. 예: 청소는 집 전체를 완벽히 치우는 일처럼, 글쓰기는 한 번에 다 써내야 하는 일처럼.
- 잘하고 싶은 마음은 인정한 채로 원래 크기만 다시 그려주세요. 행동 제안은 붙이지 마세요.''',
    ),
    ResistanceIntervention(
      id: 'allow_rough',
      label: '품질 기준 낮추기',
      rule: '''[품질 기준 낮추기]
- 잘하지 않아도 되고 고치지 않아도 된다는 쪽으로 기준을 내려주세요.
- 중간 퀄리티와 완성 퀄리티는 다르다고 짧게 안심시키세요. 분량이나 완성본을 요구하지 마세요.''',
    ),
    ResistanceIntervention(
      id: 'reorder',
      label: '순서 바꾸기',
      rule: '''[순서 바꾸기]
- 이 일을 밀지 말고, 오늘 할 일 중 지금 마음이 가장 덜 무거운 다른 일을 먼저 하자고 하세요.
- 미루는 게 아니라 순서를 바꾸는 것입니다. 원래 일을 언제 할지 다시 묻지 마세요.''',
    ),
    // 앱 기능을 가리키는 유일한 개입이다. 다른 방식이 말로 푸는 것인 데 반해
    // 이건 화면을 하나 띄우는 일이라, 띄워줄지 먼저 묻고 나서 움직인다.
    ResistanceIntervention(
      id: 'start_signal',
      label: '시작 신호 만들기',
      masterOnly: true,
      rule: '''[시작 신호 만들기]
- 할 일을 더 낮추지 말고, 시작 자체에 신호를 만드는 쪽으로 가세요.
- 정해진 신호가 행동을 시작하는 데 도움이 될 수 있다는 연구가 있다고 한 문장만 짚으세요. 효과를 길게 설명하거나 설득하지 마세요.
- 채팅창 위 빠른 실행의 '숫자 세고 시작'을 눌러도 된다고 알려주고, 대신 띄워줄지 한 번만 물으세요.
- 사용자가 띄워달라고 하면 그때 답변 끝에 [COUNTDOWN_START]를 붙이세요. 묻기도 전에 먼저 붙이지 마세요.''',
    ),
    ResistanceIntervention(
      id: 'let_user_choose',
      label: '선택권 주기',
      picksConcreteAction: true,
      rule: '''[선택권 주기]
- 코치가 방식을 정해주지 말고 사용자가 고르게 하세요. 의지 부족으로 평가하지 마세요.
- 현재 과업과 연결된 쉬운 선택지 2개 + 기타를 주고 고르게 하세요. 자유형 질문 금지.
- 끝에 [CHIPS: 선택지1|선택지2|기타]. 설득·분석·목표 설명 금지.''',
    ),
    // 순번에서 빠져 있는 하나. 기운이 없다고 말한 턴에만 앱이 지목해서 꺼낸다.
    //
    // 나머지 여덟은 전부 그 일을 어떻게 다룰지의 얘기라, 제일 작게 줄여도
    // 사용자가 하는 건 그 일의 한 조각이다. 몸이 안 움직이는 사람에게는 컵
    // 하나도 무거울 수 있어서 그 아래 층이 하나 필요하다.
    //
    // 커서만 보기 같은 것을 걷어낸 것과는 다르다. 그쪽은 일하는 척이라 하고
    // 나서 아무것도 안 변한 게 자책으로 돌아왔다. 이건 처음부터 그 일이 아니라
    // 몸을 깨우는 것이라고 선을 긋고 시작해서, 일이 그대로인 게 어긋나지 않는다.
    ResistanceIntervention(
      id: 'wake_body',
      label: '몸 먼저 깨우기',
      preferredOnly: true,
      rule: '''[몸 먼저 깨우기]
- 할 일을 쪼개거나 시작시키지 말고, 몸에 아주 작은 시동을 거는 것 하나만 권하세요.
- 기운이 없는 상태를 한 문장으로 짧게 받아준 뒤, "지금은 어떤 게 가장 쉬울 것 같아?"를 현재 코치 말투로 물으세요.
- 끝에 [CHIPS: 손가락 스트레칭하기|손목 돌리기|자리에서 일어나기]를 붙이세요.
- 이건 그 일이 아니라 몸을 깨우는 것입니다. 하고 나서 일이 얼마나 진행됐는지 묻지 마세요.
- 설득·원인 분석·목표 설명·긴 위로 금지. [TASK]와 [TIMER_CONFIRM]도 붙이지 마세요.''',
    ),
  ];

  /// 준비한 방식을 한 대화에서 모두 꺼내 쓴 뒤. 더 밀지 않고 닫는다.
  static const String exhaustedRule =
      '''- 이번 대화에서 쓸 방식을 모두 꺼냈고 사용자는 전부 내키지 않아 했습니다.
- 새 방식을 지어내거나 이미 꺼낸 방식을 다시 밀지 마세요.
- 오늘 이 일이 그만큼 무겁다는 뜻임을 한 문장 인정하고 여기까지 두자고 닫으세요.
- 2문장 이내. [TASK], [TIMER_CONFIRM], [CHIPS] 금지.''';

  /// 직전 제안이 거부당한 턴에 덧붙인다. 설득을 막는 자리다.
  static const String refusedPrefix = '''- 사용자가 거부하면 같은 종류의 제안을 다시 하지 마세요.
- 짧게 받아준 뒤 아래 방식으로 넘어가세요.''';

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 코치 제안에 대한 거부 표현.
  ///
  /// 실행 저항 표현("하기 싫다")과 겹치지만, 이쪽은 직전 제안을 향한 거절까지
  /// 잡아야 해서 더 넓다. "그건 좀", "안 할래"처럼 저항 목록에 없는 말이 실제
  /// 거절에서는 더 자주 나온다.
  static const List<String> _refusalSignals = [
    '그것도싫',
    '그건싫',
    '그거싫',
    '그것도별로',
    '그건별로',
    '별로야',
    '별론데',
    '안할래',
    '안하고싶',
    '안내켜',
    '내키지않',
    '내키지가않',
    '그건좀',
    '그것도좀',
    '그거말고',
    '다른거',
    '다른방법',
    '싫어',
    '싫은데',
    '싫다',
    '못하겠',
    '하기싫',
    '귀찮',
    '지금은안',
    '패스',
  ];

  static bool isRefusal(String text) =>
      _refusalSignals.any(_normalize(text).contains);

  /// 아직 안 꺼낸 것 중 다음 개입. 전부 꺼냈으면 null.
  ///
  /// [startAfterId]는 마지막으로 꺼냈던 개입이다. 그 다음 자리부터 훑어서,
  /// 새 대화가 늘 같은 방식으로 시작하지 않게 한다. null이면 목록 맨 위부터.
  ///
  /// [preferredId]는 앱이 이번 턴에 지목한 개입이다. 아직 안 꺼냈으면 순번을
  /// 건너뛰고 그것부터 나간다. 이미 꺼냈으면 순번대로 돌아간다 — 같은 대화에서
  /// 두 번 권할 것은 아니고, 한 번 권해서 안 통했으면 다른 길로 가야 한다.
  static ResistanceIntervention? nextIntervention(
    Iterable<String> offeredIds, {
    required bool isMaster,
    String? startAfterId,
    String? preferredId,
  }) {
    final offered = offeredIds.toSet();
    if (preferredId != null && !offered.contains(preferredId)) {
      final preferred = byId(preferredId);
      if (preferred != null && (!preferred.masterOnly || isMaster)) {
        return preferred;
      }
    }
    // 못 찾으면 -1 + 1 = 0이라 맨 위부터. 개입을 지운 뒤에도 안전하다.
    final start = interventions.indexWhere((i) => i.id == startAfterId) + 1;
    for (var step = 0; step < interventions.length; step++) {
      final candidate = interventions[(start + step) % interventions.length];
      if (candidate.masterOnly && !isMaster) continue;
      if (candidate.preferredOnly) continue;
      if (!offered.contains(candidate.id)) return candidate;
    }
    return null;
  }

  static ResistanceIntervention? byId(String id) {
    for (final intervention in interventions) {
      if (intervention.id == id) return intervention;
    }
    return null;
  }
}
