/// 낮에 코치가 먼저 말을 걸지, 건다면 뭐라고 할지 정한다.
///
/// 접속 여부가 아니라 오늘의 실행 상태를 본다. 안 들어왔다고 부르면 이미 잘
/// 하고 있는 사람에게도 같은 말이 가는데, 그건 부르는 쪽의 사정이지 그 사람의
/// 사정이 아니다.
///
/// 판단만 하고 보내지는 않는다. 순수 함수로 두어야 데이터를 넣어보며 확인할 수
/// 있다.
library;

import 'dart:math';

import 'repeat_keyword_service.dart';

enum NudgeKind {
  /// 오늘 등록된 일정이 없다.
  noPlan,

  /// 미룬 일을 오늘 다시 등록해두고 아직 시작하지 않았다.
  deferredAgain,

  /// 일정은 있는데 아직 아무것도 시작하지 않았다.
  notStarted,

  /// 요즘 해낸 것을 그냥 알아봐주는 날. 오늘 무엇을 하라는 말은 하지 않는다.
  praise,
}

class PreemptiveNudge {
  final NudgeKind kind;
  final String message;

  /// 문구에 이름을 넣은 일. 이름 없이 말한 경우엔 null.
  ///
  /// 채팅으로 이어붙일 때 이 일의 상태가 그대로인지 확인하는 데 쓴다.
  final String? taskName;

  /// 실행 유형을 짚어 건넨 말인지. 이건 주에 한 번만 쓴다.
  final bool isPattern;

  const PreemptiveNudge({
    required this.kind,
    required this.message,
    this.taskName,
    this.isPattern = false,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'message': message,
    if (taskName != null) 'taskName': taskName,
    if (isPattern) 'isPattern': true,
  };

  static PreemptiveNudge? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final message = json['message']?.toString() ?? '';
    if (message.isEmpty) return null;
    final kind = NudgeKind.values.where((k) => k.name == json['kind']);
    if (kind.isEmpty) return null;
    return PreemptiveNudge(
      kind: kind.first,
      message: message,
      taskName: json['taskName']?.toString(),
      isPattern: json['isPattern'] == true,
    );
  }
}

class PreemptiveNudgeService {
  /// 시작을 거드는 말. 계획을 세웠든 안 세웠든 통한다.
  ///
  /// 답이 응/아니로 끝나는 말은 두지 않는다. "같이 시작해볼까?"는 물음표가
  /// 붙어 있어도 제안이라, 답해도 손에 남는 것이 없다. 대신 무엇 하나를
  /// 꼽게 하는 말을 둔다 — 알림을 읽는 동안 답이 반쯤 떠오르고, 눌러 들어오면
  /// 코치가 같은 말을 하고 있어 거기 그대로 답하면 된다.
  static const List<String> notStartedMessages = [
    '집사, 오늘 것 중에 제일 하기 싫은 게 뭐냥?',
    '집사, 뭐가 제일 걸리냥? 냥이가 줄여주겠다냥.',
    '집사야, 오늘 첫 칸은 뭘로 열까냥?',
    '집사야, 하나만 고르면 뭐부터 하겠냥?',
    '집사야, 지금 3분 낼 수 있냥?',
    '집사, 100점 말고 3분만 하자냥.',
  ];

  /// 계획을 세우자고 청하는 말. 계획이 비어 있을 때만 쓴다.
  ///
  /// 줄바꿈을 쓰지 않는다. 안드로이드 알림은 접힌 상태에서 첫 줄만 보여서,
  /// 둘째 줄에 둔 말은 안 읽힌 채로 지나간다.
  static const List<String> planMessages = [
    '집사, 오늘 해보고픈 작은 성취 없냥?',
    '집사야, 오늘 딱 하나만 꼽으면 뭐냥?',
    '집사, 오늘 끝내면 속 시원할 게 뭐냥?',
    '집사야, 지금 머리에 걸리는 거 하나 있냥?',
    '집사, 오늘 미뤄둔 거 하나만 말해달라냥.',
    '밥은 먹었냥? 오늘 뭐 하나 정하고 갈까냥?',
    // 묻기만 하는 풀에 이유를 말해주는 말을 하나 섞는다. 다 물음표로 끝나면
    // 매일 낮에 질문만 받는 셈이라, 결이 다른 한 줄이 오히려 눈에 걸린다.
    '집사야, 완료는 계획에서 시작된다냥.',
  ];

  /// 계획이 비어 있는 날에 쓸 수 있는 말 전부.
  ///
  /// 계획을 청하는 말에 시작을 거드는 말까지 함께 쓴다. "3분만 하자"는 계획이
  /// 없는 사람에게도 그대로 통하기 때문이다. 반대는 안 된다 — 계획을 세워둔
  /// 사람에게 안 세웠냐고 물으면 그 순간 틀린 말이 된다.
  static List<String> get noPlanMessages => [
    ...planMessages,
    ...notStartedMessages,
  ];

  /// 미뤄놓고 다시 올린 일을 부를 때. `{{task}}`가 일정 이름 자리다.
  static const List<String> deferredAgainMessages = [
    '어제 미룬 \'{{task}}\', 오늘 다시 넣어뒀네.\n'
        '시작하기 좀 부담되냥? 냥냥이가 가볍게 줄여줄까?',
    '시작해! 시작해! \'{{task}}\' 시작해! 📣\n냥이가 응원한다냥!',
  ];

  /// 며칠째 넘어가고 있는 일을 부를 때.
  ///
  /// 응원 구호는 쓰지 않는다. 한 번 미룬 것과 며칠 미룬 것은 다른 상태다.
  /// 이틀을 넘겼다는 건 마음이 없어서가 아니라 그 일이 지금 감당하기에 큰
  /// 것이라, 밀어붙이면 부담 위에 부담을 얹는다.
  ///
  /// 며칠이 지났는지도 세어 보이지 않는다. 사실을 말한 것뿐이어도 듣는 쪽에는
  /// 지적으로 남는다. 대신 같이 하자고 하거나, 줄여주거나, 오늘은 넘겨도
  /// 된다고 먼저 말해준다.
  static const List<String> longDeferredMessages = [
    '\'{{task}}\' 오늘 하기로 이동했잖아.\n냥이랑 같이 시원하게 시작해볼까?',
    '\'{{task}}\'이 계속 미뤄지는 건 집사 탓이 아니다냥.\n'
        '덩어리가 커서 그런 거니까, 냥이가 작게 잘라줄까?',
    '\'{{task}}\' 아직 남아 있다냥. 오늘도 어려우면 넘겨도 된다냥.\n'
        '대신 뭐가 걸리는지만 알려주라냥.',
  ];

  /// 실행 유형을 짚어 건네는 말. 주에 한 번만 쓴다.
  ///
  /// 앱이 세어둔 유형이 있을 때만 쓸 수 있다. 앞자락이 칭찬인데 그게 사실이
  /// 아니면 그냥 아픈 말이 되기 때문이다 — "계획만 짜면 다 하면서"를 완료율이
  /// 낮은 사람에게 보내면 거짓말이다.
  ///
  /// 뼈대는 "잘하는 X가 있는데 왜 Y를 안 하냐"다. 못한 것을 세어 보이지 않고
  /// 그 사람의 강점과 어긋난다고 갸우뚱한다. 같은 사실이라도 세면 지적이 되고
  /// 갸우뚱하면 농담이 된다 — [longDeferredMessages]가 며칠인지 안 세는 것과
  /// 같은 이유다.
  ///
  /// '자유형'은 없다. 아직 셀 것이 적어 유형을 말하기 이른 상태라, 그 사람에게
  /// 는 짚어줄 것이 없다. 그때는 평소 문구로 간다.
  /// 어느 상황에서든 통하는 유형 문구.
  ///
  /// 유형 문구는 두 자리에서 나간다 — 오늘 아무것도 안 적은 날과, 적어는
  /// 뒀는데 손을 안 댄 날이다. 두 자리를 안 가르면 절반이 어긋난다. "계획만
  /// 짜면 다 하면서 왜 안 짜냥?"은 오늘 적어둔 사람에게는 틀린 말이고,
  /// "왜 다 오늘이냥?"은 목록이 비어 있는 사람에게는 가리킬 것이 없다.
  ///
  /// 여기 있는 것은 그날의 목록을 가리키지 않는 말들이라 양쪽에서 쓴다.
  static const Map<String, List<String>> patternMessages = {
    '벼락치기형': ['집사, 밤엔 그렇게 잘하면서 왜 낮엔 안 하냥?', '집사야, 결국 할 거면서 왜 밤까지 끌고 가냥?'],
    '편차형': ['집사, 되는 날엔 다 하면서 왜 오늘은 조용하냥?'],
    '안정형': ['집사, 요즘 왜 이렇게 잘하냥? 수상하다냥.', '집사야, 이 리듬 어디서 났냥? 오늘도 부탁한다냥.'],
  };

  /// 오늘 아무것도 안 적은 날에만 쓰는 유형 문구.
  static const Map<String, List<String>> patternNoPlanMessages = {
    '계획 편차형': ['집사, 계획만 짜면 다 하면서 왜 안 짜냥?', '집사야, 적어두기만 하면 해내면서 왜 안 적냥?'],
    '계획 과다형': ['집사, 하고 싶은 거 많아도 오늘은 하나만 적자냥.', '집사야, 욕심은 내일 내고 오늘은 하나만 적자냥.'],
    '시작 편차형': ['집사야, 문턱만 넘으면 되잖냥. 하나만 적자냥.'],
    '시작 꾸준형': ['집사야, 손은 잘 대잖냥. 하나만 적자냥.'],
  };

  /// 적어는 뒀는데 아직 손을 안 댄 날에만 쓰는 유형 문구.
  static const Map<String, List<String>> patternNotStartedMessages = {
    '시작 편차형': ['집사, 시작만 하면 다 해내면서 왜 안 시작하냥?', '집사야, 문턱만 넘으면 되는데 왜 앞에서 서 있냥?'],
    '계획 과다형': ['집사, 하고 싶은 건 많은데 왜 다 오늘이냥?', '집사야, 열 개 잡지 말고 하나만 고르면 안 되냥?'],
    '시작 꾸준형': ['집사, 시작은 잘하면서 왜 끝은 안 보냥?', '집사야, 손은 다 댔는데 왜 다 열어만 뒀냥?'],
    '계획 편차형': ['집사야, 오늘은 적었다냥. 적은 날엔 다 해냈다냥.'],
  };

  /// 이 유형에게 이 상황에서 건넬 수 있는 말 전부.
  static List<String> patternPool({
    required String typeLabel,
    required bool hasPlan,
  }) => [
    ...?patternMessages[typeLabel],
    ...?(hasPlan
        ? patternNotStartedMessages
        : patternNoPlanMessages)[typeLabel],
  ];

  /// 며칠째 플래너를 안 연 사람에게.
  ///
  /// 날수를 세지 않는다. "사흘 만이다냥"은 사실이지만 출석 체크가 된다 —
  /// [longDeferredMessages]가 며칠 미뤘는지 안 세는 것과 같은 이유다.
  ///
  /// "하나만 적어봐"를 반복하지 않는다. 오래 안 온 사람에게 그건 이미 여러 번
  /// 어긋난 요구라, 같은 말을 또 하면 안 통하던 것을 한 번 더 하는 셈이다.
  /// 대신 마음 쪽을 건드리거나, 그동안을 먼저 덮어주고 부른다.
  ///
  /// "안 와도 괜찮다"는 쓰지 않는다. 알림을 보내는 일 자체가 부르는 것이라,
  /// 본문이 오지 말라고 하면 둘이 상쇄되어 아무 말도 안 한 게 된다. 덮어주는
  /// 말은 목적어를 비워둔다 — "괜찮다냥"이 그동안의 전부를 덮는다.
  static const List<String> absenceMessages = [
    '집사, 오늘은 마음 한번 달리 먹어보자냥.',
    '집사, 괜찮다냥. 냥이랑 다시 시작해보자냥.',
    // 앱이 절대 셀 수 없는 것을 묻는 유일한 자리다. 왜 뜸했는지는 바빴는지
    // 지쳤는지 앱이 안 맞았는지에 따라 다른데, 그건 사용자만 안다.
    '집사, 요새 왜 뜸한지 말해주라냥.',
    '집사, 냥이는 그대로 여기 있다냥.',
  ];

  /// 더 오래 안 온 사람에게, 해낸 적이 아예 없을 때.
  ///
  /// 아무것도 청하지 않고 아무것도 전제하지 않는다. 이 사람에게는 되살릴
  /// 기억도 부를 이름도 없다.
  static const List<String> longAbsenceMessages = [
    '집사, 냥이가 기다린다냥. 얼굴만 보고 가라냥.',
    '집사야, 다시 시작하는 건 언제든 된다냥.',
  ];

  /// 해낸 날의 느낌을 되살리는 말.
  ///
  /// 이름도 날짜도 안 대서 자리를 안 가린다. 오래 쉰 사람에게도, 오늘 아직
  /// 시작을 못 한 사람에게도 그대로 통한다. 반년 전 일이어도 어색하지 않다 —
  /// "언제 그랬더라"가 아니라 "그 기분 기억나지"라서다.
  ///
  /// 감정을 묻는 유일한 자리다. 나머지는 전부 무엇을 하느냐 이야기라, 결이
  /// 다른 한 줄이 오히려 잡힌다.
  ///
  /// 해낸 적이 한 번도 없는 사람에게는 쓰면 안 된다([hasEverDone]). 없던 날을
  /// 있었던 것처럼 말하는 것이 되기 때문이다.
  static const List<String> doneMemoryMessages = [
    '집사야, 계획 하나 해낸 날 뿌듯하지 않았냥?',
    '집사, 하나 해낸 날 뿌듯했던 거 기억나냥?',
  ];

  /// 더 오래 안 온 사람에게, 예전에 해낸 일 이름을 부를 수 있을 때.
  /// `{{task}}`가 그 이름 자리다.
  ///
  /// 여기서만 청한다. 막연한 "해보자"가 아니라 "너 이거 해냈잖냥"이 앞에 서기
  /// 때문이다 — 근거가 붙으면 요구가 아니라 초대가 된다.
  ///
  /// 너무 오래된 것은 안 부른다([namedAbsenceWithinDays]). 반년 전 것을 꺼내면
  /// 초대가 아니라 "네가 마지막으로 뭘 한 게 언제였더라"가 되어, 날수를 세지
  /// 않기로 한 규칙을 말만 바꿔 어기는 셈이 된다.
  static const List<String> longAbsenceNamedMessages = [
    "집사야, '{{task}}' 해냈듯이 오늘 해보자냥!",
    "집사, '{{task}}' 해냈잖냥. 오랜만에 하자냥!",
  ];

  /// 이 안에 해낸 것만 이름을 부른다.
  static const int namedAbsenceWithinDays = 30;

  /// 오래 안 온 사람에게 건넬 한 줄. [long]이면 더 오래된 쪽이다.
  ///
  /// [recentDoneName]이 있으면 그 이름을 부르며 청한다. 없으면 기다린다고만
  /// 한다.
  static String absenceMessage({
    required bool long,
    String? recentDoneName,
    bool hasEverDone = false,
  }) {
    if (!long) return _pick(absenceMessages);
    // 부를 이름이 있으면 이름으로, 없으면 그때의 느낌으로, 그것도 없으면
    // 아무것도 전제하지 않고.
    if (recentDoneName != null) {
      return _fill(longAbsenceNamedMessages, recentDoneName);
    }
    if (hasEverDone) return _pick(doneMemoryMessages);
    return _pick(longAbsenceMessages);
  }

  /// 지금까지 하루라도 뭔가 끝낸 적이 있는지.
  static bool hasEverDone(List<dynamic> history) => history
      .whereType<Map>()
      .any((record) => ((record['doneCount'] as num?)?.toInt() ?? 0) > 0);

  /// 가까운 날에 해낸 일 하나의 이름. 부를 것이 없으면 null.
  static String? recentDoneTaskName({
    required List<dynamic> history,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final floor = today.subtract(const Duration(days: namedAbsenceWithinDays));
    String? found;
    DateTime? foundAt;
    for (final record in history.whereType<Map>()) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final at = DateTime(date.year, date.month, date.day);
      if (at.isBefore(floor) || at.isAfter(today)) continue;
      final name = _doneTaskName(record);
      if (name == null) continue;
      if (foundAt == null || at.isAfter(foundAt)) {
        found = name;
        foundAt = at;
      }
    }
    return found;
  }

  /// 요즘 해낸 것을 알아봐주는 말. `{{n}}`이 날수 자리다.
  ///
  /// 아무것도 청하지 않는다. 끝에 "그러니 오늘도 해보자"를 붙이면 칭찬이 아니라
  /// 미끼가 되고, 받는 쪽은 인정받은 게 아니라 다음 요구를 받은 것이 된다.
  ///
  /// 근거 없이 "잘하고 있어"라고 하지 않는다. 앱이 실제로 센 날수를 말한다 —
  /// 크기를 정하는 데 끼지 않은 쪽이 결과만 보고 인정해야 도장이 찍힌다.
  static const List<String> praiseWeekMessages = [
    '집사, 이번 주에 벌써 {{n}}일이나 움직였다냥.',
    '집사야, 이번 주 {{n}}일. 냥이는 다 보고 있었다냥.',
    '집사, {{n}}일이나 손댔다냥. 그거 아무나 못 한다냥.',
  ];

  /// 어제 적어둔 것을 다 끝냈을 때.
  ///
  /// 알아채는 말투를 쓰지 않는다. 어제 끝낼 때 이미 축하를 건넸는데 다음 날
  /// "다 했더라?" 하면, 코치가 어제 그 자리에 없었던 것처럼 들린다. 둘 다
  /// 아는 일로 두고 거기서 오늘을 잇는다.
  ///
  /// 여러 날을 모은 말은 다르다([praiseWeekMessages]). 이번 주에 며칠
  /// 움직였는지는 사용자도 세어본 적이 없어서, 그건 정말 새 소식이다.
  static const List<String> praiseYesterdayMessages = [
    '집사, 어제 다 해냈듯이 오늘도 하나만 하자냥.',
    '집사야, 어제처럼 오늘도 하나만 제대로 하자냥.',
  ];

  /// 조용하던 날들 끝에 어제 뭔가 해냈을 때. `{{task}}`가 그 일 이름 자리다.
  ///
  /// 이름과 꼬리를 둘 다 넣으면 알림 한 줄을 넘긴다. 넘치는 쪽은 뒤에서
  /// 잘리므로, 앞에 알아봐주는 말을 두고 이어가자는 말을 뒤에 둔다. 잘려도
  /// 남는 것이 칭찬이라 뜻이 무너지지 않는다.
  ///
  /// 여기서만 오늘을 잇자고 한다. 잘 굴러가는 사람에게 이어가자고 하면 이미
  /// 하고 있는 것을 시키는 말이 되는데, 끊겼다 이어진 자리는 다음 한 걸음이
  /// 제일 무거워서 어제 해낸 것이 그 걸음의 근거가 된다.
  static const List<String> praiseComebackMessages = [
    "집사, 어제 '{{task}}' 했듯이 오늘도 하나만.",
    "집사야, 어제 '{{task}}' 한 것처럼 가보자냥.",
    "집사, 어제 '{{task}}' 했다냥. 오늘도 하나만.",
  ];

  /// 이만큼 움직인 주라야 날수를 말한다.
  ///
  /// 이틀로 잡으면 거의 매주 걸려서 칭찬이 인사말이 된다. 사흘이면 "이번 주는
  /// 좀 됐다" 소리를 들을 만한 주다.
  static const int praiseWeekDays = 3;

  /// 이 날수만큼 조용했으면 '오랜만'으로 본다.
  ///
  /// 어제 앞의 이레를 본다. 그중 손댄 날이 하루 이하면, 어제 한 것은 이어가던
  /// 흐름이 아니라 끊겼다 이어진 것이다.
  static const int comebackQuietDays = 7;
  static const int comebackMovedAtMost = 1;

  /// 칭찬을 다시 꺼내도 되기까지. 유형 짚기와 같다.
  static const Duration praiseInterval = Duration(days: 7);

  /// 지금 알아봐줄 것이 있는지. 없으면 null.
  ///
  /// 어제 다 해낸 쪽을 먼저 본다. 방금 있었던 일이라 알아봐준 티가 제일 난다.
  static String? praiseMessage({
    required List<dynamic> history,
    required DateTime now,
    required DateTime? lastPraiseAt,
  }) {
    if (lastPraiseAt != null && now.difference(lastPraiseAt) < praiseInterval) {
      return null;
    }

    final yesterdayDate = now.subtract(const Duration(days: 1));
    final yesterday = _dateKey(yesterdayDate);
    for (final record in history.whereType<Map>()) {
      if (record['date']?.toString() != yesterday) continue;
      final total = (record['totalCount'] as num?)?.toInt() ?? 0;
      final done = (record['doneCount'] as num?)?.toInt() ?? 0;
      if (done <= 0) break;

      // 오랜만에 해낸 것이 먼저다. 다 끝낸 날보다 드문 일이고, 이름을 불러
      // 말할 수 있어서 알아봐준 티가 제일 난다.
      final name = _doneTaskName(record);
      if (name != null && _wasQuietBefore(history, yesterdayDate)) {
        return _fill(praiseComebackMessages, name);
      }
      if (total > 0 && done >= total) return _pick(praiseYesterdayMessages);
      break;
    }

    final moved = movedDaysThisWeek(history: history, now: now);
    if (moved >= praiseWeekDays) {
      return _pick(praiseWeekMessages).replaceAll('{{n}}', '$moved');
    }
    return null;
  }

  /// 이번 주에 하나라도 끝낸 날이 며칠인지. 오늘은 빼고 센다.
  ///
  /// 오늘은 아직 안 움직인 날이라 이 말이 나가는 것이다. 오늘을 넣으면 늘 0이
  /// 하나 붙는 셈이고, 기록 탭의 '움직인 날'과도 어긋난다.
  static int movedDaysThisWeek({
    required List<dynamic> history,
    required DateTime now,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    var count = 0;
    for (final record in history.whereType<Map>()) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(monday) || !day.isBefore(today)) continue;
      if (((record['doneCount'] as num?)?.toInt() ?? 0) > 0) count++;
    }
    return count;
  }

  /// 그날 끝낸 일 하나의 이름. 부를 것이 없으면 null.
  ///
  /// 이름이 너무 길면 알림 한 줄을 혼자 다 먹는다. 그때는 부르지 않고 이름
  /// 없는 말로 간다 — 잘라 붙이면 무슨 일인지 알아보기 어렵다.
  static const int praiseNameLimit = 8;

  static String? _doneTaskName(Map record) {
    final tasks = record['tasks'];
    if (tasks is! List) return null;
    for (final task in tasks.whereType<Map>()) {
      if (task['done'] != true) continue;
      final text = task['text']?.toString().trim() ?? '';
      if (text.isEmpty || text.length > praiseNameLimit) continue;
      return text;
    }
    return null;
  }

  /// [day] 앞이 조용했는지. 그날은 세지 않는다.
  static bool _wasQuietBefore(List<dynamic> history, DateTime day) {
    final until = DateTime(day.year, day.month, day.day);
    final from = until.subtract(const Duration(days: comebackQuietDays));
    var moved = 0;
    for (final record in history.whereType<Map>()) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final at = DateTime(date.year, date.month, date.day);
      if (at.isBefore(from) || !at.isBefore(until)) continue;
      if (((record['doneCount'] as num?)?.toInt() ?? 0) > 0) moved++;
    }
    return moved <= comebackMovedAtMost;
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// 유형을 짚는 말을 다시 꺼내도 되기까지.
  ///
  /// 유형은 주에 한 번 바뀔까 말까다. 매일 보내면 같은 말이 반복되고, 사흘째
  /// 부터는 짚어주는 말이 아니라 잔소리가 된다.
  static const Duration patternInterval = Duration(days: 7);

  /// 지금 유형을 짚어도 되는지.
  static bool canUsePattern({
    required String? typeLabel,
    required DateTime now,
    required DateTime? lastPatternAt,
    bool hasPlan = false,
  }) {
    if (typeLabel == null) return false;
    if (patternPool(typeLabel: typeLabel, hasPlan: hasPlan).isEmpty) {
      return false;
    }
    if (lastPatternAt == null) return true;
    return now.difference(lastPatternAt) >= patternInterval;
  }

  /// 이 횟수부터는 미는 말을 쓰지 않는다.
  static const longDeferredThreshold = 2;

  /// 이름을 부르며 시작을 미는 말.
  ///
  /// 줄여주겠다는 말과 밀어주는 말을 섞어 둔다. 매번 부담을 낮춰주려 들면
  /// 그 일이 늘 어려운 일로 굳고, 매번 밀기만 하면 재촉이 된다.
  static const List<String> namedStartMessages = [
    '\'{{task}}\' 오늘 냥이랑 슬슬 시작해볼까?',
    '시작해! 시작해! \'{{task}}\' 시작해! 📣\n냥이가 응원한다냥!',
  ];

  static String _pick(List<String> pool) => pool[Random().nextInt(pool.length)];

  static String _fill(List<String> pool, String taskName) =>
      _pick(pool).replaceAll('{{task}}', taskName);

  /// 오늘 무엇이든 손을 댔는지.
  ///
  /// 완료, 시작 표시, 타이머로 흐른 시간 중 하나라도 있으면 손을 댄 것이다.
  /// 타이머만 돌리고 시작 표시를 안 누른 경우가 있어 셋을 다 본다.
  static bool touchedToday(List<dynamic> todayTasks) {
    return todayTasks.whereType<Map>().any((task) {
      if (task['done'] == true) return true;
      if (task['inProgress'] == true) return true;
      if (task['inProgressAt'] != null) return true;
      return ((task['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0;
    });
  }

  static bool _isHabit(Map task) =>
      task['habitId'] != null || task['category'] == 'habit';

  /// 자정 리셋이 습관을 자동으로 채워 넣어서, 습관까지 세면 '계획 없음'이
  /// 영영 걸리지 않는다. 사용자가 직접 올린 것만 계획으로 본다.
  static List<Map> _plannedTasks(List<dynamic> todayTasks) => todayTasks
      .whereType<Map>()
      .where((task) => !_isHabit(task))
      .toList(growable: false);

  static String? _text(Map? task) {
    final text = task?['text']?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// 지금 부를지, 부른다면 뭐라고 할지. 부를 이유가 없으면 null.
  ///
  /// [todayTasks]는 오늘 할 일, [coreTasks]는 핵심으로 찍어둔 것,
  /// [history]는 하루 기록들이다.
  /// [typeLabel]은 앱이 세어둔 실행 유형, [lastPatternAt]·[lastPraiseAt]은 그
  /// 말을 마지막으로 건넨 때다. 셋 다 없으면 평소 문구로만 간다.
  static PreemptiveNudge? decide({
    required List<dynamic> todayTasks,
    required List<dynamic> coreTasks,
    required List<dynamic> history,
    String? typeLabel,
    DateTime? now,
    DateTime? lastPatternAt,
    DateTime? lastPraiseAt,
  }) {
    // 이미 움직이고 있는 사람에게는 말을 걸지 않는다. 격려도 참견이 된다.
    if (touchedToday(todayTasks)) return null;

    final at = now ?? DateTime.now();

    // 알아봐줄 것이 있는 날은 그것부터다. 오늘 뭘 하라는 말은 다른 날에도 할
    // 수 있지만, 어제 다 해낸 것은 오늘 말하지 않으면 지나간다.
    final praise = praiseMessage(
      history: history,
      now: at,
      lastPraiseAt: lastPraiseAt,
    );
    if (praise != null) {
      return PreemptiveNudge(kind: NudgeKind.praise, message: praise);
    }

    final planned = _plannedTasks(todayTasks);
    final everDone = hasEverDone(history);

    if (planned.isEmpty) {
      final pattern = _patternMessage(
        typeLabel,
        at,
        lastPatternAt,
        hasPlan: false,
      );
      return PreemptiveNudge(
        kind: NudgeKind.noPlan,
        message: pattern ?? _pick(_withMemory(noPlanMessages, everDone)),
        isPattern: pattern != null,
      );
    }

    // 미뤄놓고 오늘 다시 올린 일이 있으면 그게 오늘의 이야기다. 다시 적었다는
    // 것 자체가 하려는 마음인데 손이 안 가는 상태라, 부담을 줄여주는 쪽이 맞다.
    int deferredCount(Map task) =>
        (task['deferredCount'] as num?)?.toInt() ?? 0;

    // 여러 개면 제일 오래 넘어간 것부터 본다. 그게 제일 굳어 있는 일이다.
    final deferred = planned.where((task) => deferredCount(task) >= 1).toList()
      ..sort((a, b) => deferredCount(b).compareTo(deferredCount(a)));
    if (deferred.isNotEmpty) {
      final name = _text(deferred.first);
      if (name != null) {
        final longDeferred =
            deferredCount(deferred.first) >= longDeferredThreshold;
        return PreemptiveNudge(
          kind: NudgeKind.deferredAgain,
          message: _fill(
            longDeferred ? longDeferredMessages : deferredAgainMessages,
            name,
          ),
          taskName: name,
        );
      }
    }

    final name = _pickTaskToMention(
      todayTasks: todayTasks,
      planned: planned,
      coreTasks: coreTasks,
      history: history,
    );
    if (name == null) {
      final pattern = _patternMessage(
        typeLabel,
        at,
        lastPatternAt,
        hasPlan: true,
      );
      return PreemptiveNudge(
        kind: NudgeKind.notStarted,
        message: pattern ?? _pick(_withMemory(notStartedMessages, everDone)),
        isPattern: pattern != null,
      );
    }
    return PreemptiveNudge(
      kind: NudgeKind.notStarted,
      message: _fill(namedStartMessages, name),
      taskName: name,
    );
  }

  /// 해낸 적이 있는 사람에게만 그때 느낌을 되살리는 말을 함께 뽑는다.
  static List<String> _withMemory(List<String> base, bool everDone) =>
      everDone ? [...base, ...doneMemoryMessages] : base;

  /// 지금 쓸 수 있는 유형 문구. 못 쓰면 null.
  static String? _patternMessage(
    String? typeLabel,
    DateTime now,
    DateTime? lastPatternAt, {
    required bool hasPlan,
  }) {
    if (!canUsePattern(
      typeLabel: typeLabel,
      now: now,
      lastPatternAt: lastPatternAt,
      hasPlan: hasPlan,
    )) {
      return null;
    }
    return _pick(patternPool(typeLabel: typeLabel!, hasPlan: hasPlan));
  }

  /// 이름을 넣어 부를 일 하나. 핵심 → 습관 → 요즘 반복되는 일 순으로 본다.
  ///
  /// 셋 다 없으면 null을 주고 이름 없이 부른다. 아무 일이나 집어서 부르면
  /// 왜 하필 그것인지 설명할 수 없고, 그러면 참견이 된다.
  static String? _pickTaskToMention({
    required List<dynamic> todayTasks,
    required List<Map> planned,
    required List<dynamic> coreTasks,
    required List<dynamic> history,
  }) {
    final plannedNames = planned.map(_text).whereType<String>().toSet();

    for (final core in coreTasks.whereType<Map>()) {
      final name = _text(core);
      if (name != null && plannedNames.contains(name)) return name;
    }

    for (final task in todayTasks.whereType<Map>()) {
      if (!_isHabit(task)) continue;
      final name = _text(task);
      if (name != null) return name;
    }

    final repeats = RepeatKeywordService.analyze(history);
    if (repeats.isEmpty) return null;
    for (final name in plannedNames) {
      if (RepeatKeywordService.matchingKeyword(name, repeats) != null) {
        return name;
      }
    }
    return null;
  }
}
