import 'dart:math';

/// 마스터 코치(여비서/냥할배) 자동 발화의 문구와 조립 규칙.
///
/// 채팅 화면에서 떼어낸 이유는 검증이다. 화면 안에 있으면 앱을 띄우고 로그인해서
/// 해당 시간대가 되기를 기다려야 발화 한 줄을 볼 수 있었다. 여기 있는 것은 위젯도
/// prefs도 모르고, 넘겨받은 [MasterGreetingContext] 하나로만 판단하므로 테스트에서
/// 모든 분기를 지어 넣고 나오는 문장을 눈으로 훑을 수 있다.
///
/// 화면에 남는 몫: 상태를 읽어 컨텍스트를 만드는 일, 하루 1회 가드, 실제 발화.

/// 마스터 코치 자동 발화의 시간 슬롯. 발화 예산은 슬롯당 하루 1회다.
/// 시각·계획·완료 상태는 "무슨 말을 할지"만 고르고 "몇 번 말할지"는 늘리지 않는다.
enum GreetingSlot { dawn, day, evening }

class MasterGreetingContext {
  final DateTime now;
  final int? daysSinceLastVisit;

  /// 습관을 뺀 오늘 일정. 자정 리셋이 습관을 자동으로 넣어주기 때문에,
  /// 습관까지 세면 "계획 없음" 분기가 영영 안 걸린다.
  final int planTotal;
  final int planDone;

  /// 격려 기준이 되는 완료 개수(습관 포함). 완료율이 아니라 개수를 쓰는 이유도
  /// 같다 — 자동 주입된 습관이 분모를 오염시킨다.
  final int doneCount;

  /// 격려에 녹일 완료 항목 이름. 제목이 길거나 완료가 없으면 null.
  final String? doneLabel;

  /// 저녁 선택 카드에 띄울 미완료 일정(습관 제외).
  final List<String> pendingPlans;

  /// 어젯밤 늦게까지(새벽 2~6시) 앱을 쓴 흔적이 있는지.
  final bool lateNight;

  /// 어제나 오늘 아프다고 말한 적이 있는지.
  final bool feltSick;

  /// 오늘 하기 싫다고 말했던 일정을 끝내 완료했는지.
  final bool resistedDone;

  /// 그 일정 이름. 제목이 길면 null이고, 이름 없이 격려만 한다.
  final String? resistedDoneLabel;

  const MasterGreetingContext({
    required this.now,
    required this.daysSinceLastVisit,
    required this.planTotal,
    required this.planDone,
    required this.doneCount,
    required this.doneLabel,
    required this.pendingPlans,
    required this.lateNight,
    required this.feltSick,
    this.resistedDone = false,
    this.resistedDoneLabel,
  });

  bool get hasPlan => planTotal > 0;

  double get planRate => planTotal == 0 ? 0 : planDone / planTotal;

  bool get isComeback =>
      daysSinceLastVisit != null && daysSinceLastVisit! >= 2;

  GreetingSlot get slot {
    if (now.hour < 7) return GreetingSlot.dawn;
    if (now.hour < 18) return GreetingSlot.day;
    return GreetingSlot.evening;
  }
}

class MasterGreetingResult {
  final String text;

  /// 비어 있지 않으면 저녁 ≤50% 선택 카드를 띄운다.
  final List<String> choices;

  const MasterGreetingResult(this.text, {this.choices = const []});
}

/// 코치 한 명의 발화 문구 한 벌.
class GreetingVoice {
  final List<String> dawn; // 00~05시: 아직 안 잔 사람
  final List<String> earlyMorning; // 05~07시: 일찍 일어난 사람
  final List<String> earlyStart; // 07~09시: 계획 유무를 따지지 않는 시작 인사
  final List<String> earlyQuestions;
  // 9시 뒤 낮 문구는 한 문장으로 끝나므로 제안이나 질문을 문장 안에 품는다.
  // 질문만 홀로 던지면 부담이 되니, 부담을 코치가 가져간다는 말과 한 세트로 둔다.
  final List<String> morningPlan; // 09~12시, 계획 있음
  final List<String> morningNoPlan;
  final List<String> afternoonBehind; // 12~18시, 계획은 있는데 아직 완료 0
  final List<String> afternoonNoPlan;
  final List<String> eveningLow; // 완료 50% 이하
  final List<String> eveningMid; // 51~80%
  final List<String> eveningHigh; // 81~99%
  // 저녁 초입(18~20시)은 낮인지 저녁인지 헷갈리는 시간이라 마무리 인사가 이르다.
  // 이 두 자리에서만 하루가 아직 열려 있다는 쪽으로 말한다.
  final List<String> earlyEveningNone; // 저녁 초입, 완료 0
  final List<String> earlyEveningHigh; // 저녁 초입, 81~99%
  final List<String> eveningAll; // 100%
  final List<String> eveningNoPlan;
  final List<String> comeback; // 2일 이상 만에 돌아왔을 때 앞에 붙일 한 문장

  /// 복귀한 날 뒤에 붙일 문장. 뭘 했고 뭐가 남았는지 짚는 대신 도움을 청하라고만 한다.
  final List<String> comebackSupport;
  final List<String> afterLateNight; // 늦게 잔 다음 날 낮
  final List<String> afterSick; // 아프다고 한 다음 날 낮

  /// 격려 문구. (완료 항목 이름을 넣는 형태, 이름 없이 쓰는 형태) 순서다.
  final List<(String, String)> encStarted; // 오전 1~2개 완료
  final List<(String, String)> encStrong; // 오전 3개 이상 완료
  final List<(String, String)> encFlow; // 오후 절반 이상 완료
  final List<(String, String)> encEvening; // 저녁 발화용

  /// 하기 싫다던 일을 끝낸 날 저녁. 해낸 것을 짚고, 다음에도 도와주겠다고 한다.
  /// 다른 저녁 문구와 달리 이 자체로 두 문장이라 뒤에 격려를 붙이지 않는다.
  final List<(String, String)> eveningResistedDone;

  final String otherChoiceLabel;

  const GreetingVoice({
    required this.dawn,
    required this.earlyMorning,
    required this.earlyStart,
    required this.earlyQuestions,
    required this.morningPlan,
    required this.morningNoPlan,
    required this.afternoonBehind,
    required this.afternoonNoPlan,
    required this.eveningLow,
    required this.eveningMid,
    required this.eveningHigh,
    required this.earlyEveningNone,
    required this.earlyEveningHigh,
    required this.eveningAll,
    required this.eveningNoPlan,
    required this.comeback,
    required this.comebackSupport,
    required this.afterLateNight,
    required this.afterSick,
    required this.encStarted,
    required this.encStrong,
    required this.encFlow,
    required this.encEvening,
    required this.eveningResistedDone,
    required this.otherChoiceLabel,
  });
}

class MasterGreetingCopy {
  /// 이 길이를 넘는 제목은 말풍선에서 겉돌아서 이름을 빼고 격려만 한다.
  static const doneLabelMaxLength = 20;

  /// 저녁 선택 카드에 버튼으로 직접 노출할 일정 개수. 넘으면 '그 외'로 접는다.
  static const pendingChoiceLimit = 3;

  /// 이 시각 전까지는 저녁이어도 하루가 아직 열려 있는 것으로 본다.
  /// '아직 늦지 않았다'거나 '벌써 마무리돼 간다'는 말이 참이 되는 경계다.
  static const earlyEveningUntilHour = 20;

  static GreetingVoice forCoach(String coachId) =>
      coachId == 'nyang_halbae' ? nyangHalbae : secretary;

  static const secretary = GreetingVoice(
    dawn: [
      '{늦은 시간이네요|시간이 늦었네요}. 오늘은 {여기까지 하고|이만 접고} {쉬어가셔도 좋겠습니다|쉬시는 게 좋겠습니다}.',
      '아직 깨어 계시는군요. 남은 건 {내일의 대표님께|내일 아침의 대표님께} {맡겨두시죠|넘겨두시죠}.',
      '이 시간엔 {잘 자는 것이|푹 자두는 것이} 가장 좋은 {준비입니다|준비예요}.',
    ],
    earlyMorning: [
      '오늘 일찍 오셨네요. 왠지 {좋은 하루가|괜찮은 하루가} 기다리고 있을 것 같은데요?',
      '{이른 시간부터|해도 뜨기 전부터} 움직이시는군요. 느낌이 {좋습니다|좋은데요}.',
      '아침이 열리기 전부터 나와 계시네요. 이 조용한 시간, {꽤 좋죠|제법 좋죠}.',
      '일찍 시작하는 날이네요. {여유로운|느긋한} 하루 되셨으면 좋겠습니다.',
    ],
    // 갈래 표기 `{가|나}`는 발화할 때 하나씩 골라 펼친다. 문장을 이어붙이지 않고
    // 한 문장 안에서만 갈리므로 길이는 그대로다. 조사·어미만 갈리면 숫자만 늘고
    // 읽히는 느낌은 그대로이니, 틀마다 어휘가 바뀌는 축을 하나는 둔다.
    earlyStart: [
      '{오늘도 |}새로운 하루가 {시작되었습니다|열렸습니다|밝았습니다}.',
      '오늘 하루가 {이제 막|방금} {시작됐습니다|열렸습니다}.',
      '오늘 아침이 {왔습니다|밝았습니다|열렸습니다}.',
      '또 한 번 새 하루가 {주어졌습니다|시작됐습니다}.',
    ],
    earlyQuestions: [
      '{필요하신|필요한} 게 있으면 {말씀해 주세요|알려주세요}.',
      '천천히 {준비하시고|둘러보시고}, {필요할 때|필요하실 때} 불러주세요.',
      '{무엇부터|어디부터} 살펴볼까요?',
    ],
    morningPlan: [
      '오늘 일정 {실행하시다가|하시다가} 막히는 점 있으면 {말씀해 주세요|알려주세요}.',
      '{어느 것부터 시작할지|무엇부터 손댈지} 부담 없이 {골라드릴까요|잡아드릴까요}?',
      '오전이 아직 {넉넉하니|여유로우니} {가벼운 것부터|손이 가는 것부터} 하나만 {열어보시죠|잡아보시죠}.',
    ],
    morningNoPlan: [
      '오늘은 아직 {계획이|적어둔 일정이} 없는데, {하나만 같이 정해볼까요|제가 하나 골라드릴까요}?',
      '{비어 있는|아무것도 적히지 않은} 하루인데, 부담 없는 것으로 {하나만 잡아볼까요|하나 정해볼까요}?',
      '아직 {받아둔 일정이|적어둔 일이} 없으니 오늘은 {가벼운 것|작은 것} 하나만 {정해도 됩니다|잡아도 됩니다}.',
    ],
    afternoonBehind: [
      '하루의 절반이 지났으니 {가벼운 것부터|만만한 것부터} 하나만 {열어볼까요|잡아볼까요}?',
      '오후로 넘어왔는데 {남은 것 중|남겨둔 것 중} {제일 만만한 걸로|가장 가벼운 걸로} 제가 {골라드릴까요|잡아드릴까요}?',
      '{아직 손대지 못한|아직 그대로인} 일이 남아 있는데, {부담 없는 것부터|작은 것부터} {시작해보시죠|가보시죠}.',
    ],
    afternoonNoPlan: [
      '{오후인데|오후가 됐는데} 아직 적어둔 일정이 없네요, {작은 것|가벼운 것} 하나만 {정해볼까요|잡아볼까요}?',
      '적어둔 일 없이 오후가 됐는데, {지금부터|이제부터} 할 수 있는 걸로 제가 {골라드릴까요|하나 잡아드릴까요}?',
    ],
    eveningLow: [
      '오늘 하루도 {수고하셨습니다|고생 많으셨습니다}. 남은 것 중에 {유독 손이 안 가는|자꾸 미뤄지는} 게 있으셨나요?',
      '{고생 많으셨어요|수고 많으셨어요}. 오늘 미뤄진 일 중에 {특히 귀찮았던|유난히 버거웠던} 게 있을까요?',
      '오늘도 여기까지 오셨네요. {자꾸 미뤄지는|계속 밀리는} 일이 있다면 {어떤 걸까요|무엇일까요}?',
    ],
    eveningMid: [
      '오늘 흐름이 {좋으셨네요|괜찮으셨네요}.',
      '오늘 하루, {꽤|제법} 잘 굴러갔습니다.',
      '오늘은 흐름을 잘 {지키셨어요|끌고 오셨어요}.',
    ],
    eveningHigh: [
      '이 정도면 {곧 다 완료하시겠는데요|금방 다 마치시겠는데요}.',
      '{거의 다 오셨네요|다 온 것이나 마찬가지네요}, 조금만 더 하시면 됩니다.',
      '마무리가 {눈앞이네요|코앞이네요}.',
    ],
    // 아직 아무것도 못 했다고 재촉하지 않는다. 시간이 남았다고만 말한다.
    earlyEveningNone: [
      // 뒷문장은 그대로 두고 앞머리만 갈라 가짓수를 넓힌다. 안심시키는 약속은
      // 틀마다 하나씩(당장 달라지는 기분 / 하나로 충분함 / 낮춘 기준)이라 건드리지 않는다.
      '{아직 늦지 않았습니다|아직 늦은 시간이 아닙니다|지금도 늦지 않았습니다}. 하나만 하셔도 기분이 달라지실 거예요.',
      '{저녁은 이제 시작이니|이제 막 저녁이 됐으니|저녁은 아직 초입이니} 지금 하나만 하셔도 충분히 좋을 것 같습니다.',
      // 뭘 하면 되는지 되묻지 않고 기준을 박아준다. 고를 일정은 카드가 보여준다.
      '오늘이 아직 {끝난 게 아닙니다|남아 있습니다|다 지나간 게 아닙니다}. {가벼운 거|작은 거} 하나만 해도 충분합니다.',
    ],
    // 진척만 짚지 않고 코치 자신의 기분을 얹는다. 뒤에 격려가 한 문장 더
    // 붙으므로 여기서는 반드시 한 문장으로 끝낸다.
    earlyEveningHigh: [
      '벌써 마무리가 {눈앞이라|보이니} 저도 {덩달아 기분이 좋습니다|기분이 좋아집니다}.',
      '오늘도 {벌써 마무리돼 가시네요|어느새 끝이 보이네요}, 지켜보는 저까지 {흐뭇합니다|즐거워집니다}.',
      '이 시간에 {여기까지 오시다니|벌써 이만큼이라니}, 저도 {마음이 놓입니다|덩달아 뿌듯합니다}.',
    ],
    eveningAll: [
      '오늘 계획을 {전부|남김없이} 마치셨습니다.',
      '오늘은 계획을 {남김없이 끝내셨네요|하나도 남기지 않으셨네요}.',
      '오늘 몫을 {완주하셨어요|다 채우셨어요}.',
    ],
    eveningNoPlan: [
      '오늘 하루는 {어떻게 보내셨어요|어떻게 지내셨어요}?',
      // 갈래 경계를 어미 앞에 두면 받침에 따라 문장이 깨진다('어떤 날였는지').
      // 갈리는 쪽이 어미까지 품게 한다.
      '{오늘은 어떤 하루였는지|오늘 하루는 어떤 날이었는지} 궁금하네요.',
      '별다른 일 {없으셨나요|없이 지나갔나요}?',
    ],
    // 복귀 문구는 뒤에 슬롯 문구가 붙으니 반드시 한 문장이어야 한다.
    // 두 문장짜리를 두면 발화가 네 문장으로 늘어난다.
    comeback: [
      '다시 뵈어 반갑습니다.',
      '오랜만이네요, 돌아와 주셔서 좋습니다.',
      '잠시 쉬었다 오셨군요.',
    ],
    comebackSupport: [
      '실행하시다가 어려운 게 있으면 말씀해 주세요.',
      '하시다가 막히는 게 있으면 언제든 말씀해 주세요.',
      '필요한 게 있으면 편하게 말씀해 주세요.',
    ],
    afterLateNight: [
      '어제 늦게 주무신 것 같은데 컨디션은 괜찮으신지 모르겠네요. 오늘 일정 하시다가 힘든 일 있으면 말씀해 주세요.',
      '어젯밤 늦게까지 깨어 계셨죠. 무리되는 일이 있으면 언제든 알려주세요.',
    ],
    afterSick: [
      '어제 컨디션이 안 좋으셨는데 좀 회복되셨는지 모르겠어요. 오늘 일정 하시다가 심리적으로 힘든 일 있으면 알려주세요.',
      '몸은 좀 괜찮아지셨을까요. 오늘은 버거운 일이 있으면 그때그때 말씀해 주세요.',
    ],
    encStarted: [
      ('벌써 {{task}} 시작하셨네요.', '벌써 시작하셨네요.'),
      ('{{task}} 먼저 해두셨군요.', '벌써 하나 해두셨군요.'),
    ],
    encStrong: [
      ('오전인데 {{task}}까지 해내셨으니 출발이 아주 좋습니다.', '오전인데 벌써 여러 개를 해내셨네요.'),
      ('{{task}} 마치신 걸 보니 오늘 기세가 좋으십니다.', '벌써 여럿 마치셨어요. 대단하십니다.'),
    ],
    // 오후에 진척이 있을 때 나가는 유일한 문장이다. 걷어낸 afternoonPlan이
    // 하던 '몰아붙이지 않아도 된다'는 말까지 이 한 문장이 맡는다.
    encFlow: [
      ('{{task}}까지 마치셨으니 남은 건 천천히 보셔도 됩니다.', '여기까지 오셨으니 남은 건 천천히 보셔도 됩니다.'),
      ('{{task}} 끝내신 걸 보면 오늘은 서두르지 않으셔도 되겠어요.', '지금 흐름이면 서두르지 않으셔도 되겠어요.'),
    ],
    encEvening: [
      ('{{task}} 챙기신 게 눈에 띕니다.', '오늘 챙기신 것들이 눈에 띕니다.'),
      ('오늘 {{task}} 해내신 건 분명한 성과예요.', '오늘 해내신 것들은 분명한 성과예요.'),
    ],
    eveningResistedDone: [
      (
        '{{task}} 하기 싫다고 하시더니 결국 {해내셨네요|끝내셨네요}! 앞으로도 부담되는 일이 있으면 말씀해 주세요, 제가 적극적으로 {돕겠습니다|도와드리겠습니다}.',
        '하기 싫다고 하신 일을 결국 {해내셨네요|끝내셨네요}! 앞으로도 부담되는 일이 있으면 말씀해 주세요, 제가 적극적으로 {돕겠습니다|도와드리겠습니다}.',
      ),
      (
        '그렇게 미루고 싶어 하시던 {{task}}, 결국 {해내셨습니다|끝내셨습니다}! 버거운 일이 있으면 언제든 말씀해 주세요, 제가 {같이 붙겠습니다|끝까지 돕겠습니다}.',
        '미루고 싶어 하시던 일을 결국 {해내셨습니다|끝내셨습니다}! 버거운 일이 있으면 언제든 말씀해 주세요, 제가 {같이 붙겠습니다|끝까지 돕겠습니다}.',
      ),
    ],
    otherChoiceLabel: '그 외에 있어요',
  );

  static const nyangHalbae = GreetingVoice(
    dawn: [
      '{늦은 시간까지|이 늦게까지} 깨어 있구나냥. 오늘은 {여기서 접고|이만 접고} {자도 된다냥|쉬어도 된다냥}.',
      '이 시간엔 {잘 자두는 게|푹 자는 게} 제일 큰 {준비다냥|준비라냥}.',
      '밤이 깊었다냥. 남은 건 {내일의 자네한테|내일 아침의 자네한테} {맡기자냥|넘기자냥}.',
    ],
    earlyMorning: [
      '오늘은 일찍 나왔구나냥. 왠지 {좋은 하루가|괜찮은 하루가} 기다리고 있을 것 같다냥.',
      '{이른 시간부터|해도 뜨기 전부터} 움직이는구나냥. 느낌이 {좋다냥|좋구나냥}.',
      '해도 안 뜬 시간에 나왔구나냥. 이 조용한 시간이 {제법 좋다냥|꽤 좋다냥}.',
      '일찍 시작하는 날이구나냥. 오늘은 {여유로운|느긋한} 하루가 되면 좋겠다냥.',
    ],
    earlyStart: [
      '{새|또 다른} 하루가 막 {시작됐다냥|열렸다냥|밝았다냥}.',
      '오늘 하루가 {막|방금} {열렸구나냥|시작됐구나냥}.',
      '오늘 아침이 {왔다냥|밝았다냥|열렸다냥}.',
      '또 한 번 새 하루가 {왔구나냥|주어졌구나냥}.',
    ],
    earlyQuestions: [
      '필요한 게 있으면 {부르라냥|말하라냥}.',
      '천천히 {준비하다|둘러보다} 불러도 된다냥.',
      '{뭐부터|어디부터} 살펴볼까냥.',
    ],
    morningPlan: [
      '오늘 일정 {하다가|해나가다} 막히는 게 있으면 {말하라냥|알려주라냥}.',
      '{뭐부터 시작할지|어디부터 손댈지} 부담 없이 {골라줄까냥|잡아줄까냥}.',
      '오전은 아직 {넉넉하니|여유로우니} {가벼운 것부터|손이 가는 것부터} 하나만 {열어보자냥|잡아보자냥}.',
    ],
    morningNoPlan: [
      '오늘은 아직 {계획이|적어둔 일이} 없는데 {하나만 같이 정해볼까냥|내가 하나 골라줄까냥}.',
      '{비어 있는|아무것도 안 적힌} 하루인데, 부담 없는 걸로 {하나만 잡아볼까냥|하나 정해볼까냥}.',
      '아직 {받아둔 일정이|적어둔 일이} 없으니 오늘은 {가벼운 것|작은 것} 하나만 {정해도 된다냥|잡아도 된다냥}.',
    ],
    afternoonBehind: [
      '하루가 절반 지났으니 {가벼운 것부터|만만한 것부터} 하나만 {열어볼까냥|잡아볼까냥}.',
      '오후로 넘어왔는데 {남은 것 중|남겨둔 것 중} {제일 만만한 걸로|가장 가벼운 걸로} 내가 {골라줄까냥|잡아줄까냥}.',
      '{아직 손대지 못한|아직 그대로인} 일이 남았는데, {부담 없는 것부터|작은 것부터} {시작해보자냥|가보자냥}.',
    ],
    afternoonNoPlan: [
      '{오후인데|오후가 됐는데} 아직 적어둔 일이 없구나냥, {작은 것|가벼운 것} 하나만 {정해볼까냥|잡아볼까냥}.',
      '적어둔 일 없이 오후가 왔는데, {지금부터|이제부터} 할 수 있는 걸로 내가 {골라줄까냥|하나 잡아줄까냥}.',
    ],
    eveningLow: [
      '오늘도 {고생했다냥|수고했다냥}. 남은 것 중에 {유독 손이 안 가는|자꾸 미뤄지는} 게 있었냥?',
      '{수고했다냥|고생 많았다냥}. 오늘 미뤄진 일 중에 {특히 귀찮았던|유난히 버거웠던} 게 있냥?',
      '여기까지 왔구나냥. {자꾸 미뤄지는|계속 밀리는} 일이 있다면 {뭐냥|무엇이냥}?',
    ],
    eveningMid: [
      '오늘 흐름이 {좋았다냥|괜찮았다냥}.',
      '오늘 하루 {제법|꽤} 잘 굴러갔다냥.',
      '오늘은 흐름을 잘 {지켰다냥|끌고 왔다냥}.',
    ],
    eveningHigh: [
      '이 정도면 {곧 다 끝내겠구나냥|금방 다 마치겠구나냥}.',
      '{거의 다 왔다냥|다 온 거나 마찬가지다냥}, 조금만 더 하면 된다냥.',
      '마무리가 {코앞이구나냥|눈앞이구나냥}.',
    ],
    earlyEveningNone: [
      '{아직 안 늦었다냥|아직 늦은 시간 아니다냥|지금도 안 늦었다냥}. 하나만 해도 기분이 달라질 거다냥.',
      '{저녁은 이제 시작이니|이제 막 저녁이 됐으니|저녁은 아직 초입이니} 지금 하나만 해도 충분히 좋을 것 같다냥.',
      '오늘이 아직 {끝난 게 아니다냥|남아 있다냥|다 지나간 게 아니다냥}. {가벼운 거|작은 거} 하나만 해도 충분하다냥.',
    ],
    earlyEveningHigh: [
      '벌써 마무리가 {눈앞이라|보이니} 나도 {덩달아 기분이 좋다냥|기분이 좋아진다냥}.',
      '오늘도 {벌써 마무리돼 가는구나냥|어느새 끝이 보이는구나냥}, 지켜보는 나까지 {흐뭇하다냥|즐거워진다냥}.',
      '이 시간에 {여기까지 왔다니|벌써 이만큼이라니}, 나도 {마음이 놓인다냥|덩달아 뿌듯하다냥}.',
    ],
    eveningAll: [
      '오늘 계획을 {전부|남김없이} 마쳤구나냥.',
      '오늘은 계획을 {남김없이 끝냈다냥|하나도 안 남겼다냥}.',
      '오늘 몫을 {완주했구나냥|다 채웠구나냥}.',
    ],
    eveningNoPlan: [
      '오늘 하루는 {어떻게 보냈냥|어떻게 지냈냥}?',
      '{오늘은 어떤 하루였는지|오늘 하루는 어떤 날이었는지} 궁금하다냥.',
      '별다른 일 {없었냥|없이 지나갔냥}?',
    ],
    comeback: [
      '오랜만이구나냥.',
      '다시 와줬구나냥.',
      '쉬었다 다시 걷는 것도 좋다냥.',
    ],
    comebackSupport: [
      '하다가 어려운 게 있으면 말하라냥.',
      '하다가 막히는 게 있으면 언제든 말하라냥.',
      '필요한 게 있으면 편하게 말하라냥.',
    ],
    afterLateNight: [
      '어제 늦게 잔 것 같은데 컨디션은 괜찮은지 모르겠구나냥. 오늘 하다가 힘든 일 있으면 말하라냥.',
      '어젯밤 늦게까지 깨어 있었지냥. 무리되는 게 있으면 언제든 말하라냥.',
    ],
    afterSick: [
      '어제 몸이 안 좋았는데 좀 회복됐는지 모르겠구나냥. 오늘 하다가 마음이 힘든 일 있으면 알려주라냥.',
      '몸은 좀 괜찮아졌냥. 오늘은 버거운 게 있으면 그때그때 말하라냥.',
    ],
    encStarted: [
      ('벌써 {{task}} 시작했구나냥.', '벌써 시작했구나냥.'),
      ('{{task}} 먼저 해뒀구나냥.', '벌써 하나 해뒀구나냥.'),
    ],
    encStrong: [
      ('오전인데 {{task}}까지 해냈으니 출발이 아주 좋다냥.', '오전인데 벌써 여러 개를 해냈다냥.'),
      ('{{task}} 마친 걸 보니 오늘 기세가 좋구나냥.', '벌써 여럿 마쳤다냥. 제법이다냥.'),
    ],
    encFlow: [
      ('{{task}}까지 마쳤으니 남은 건 천천히 봐도 된다냥.', '여기까지 왔으니 남은 건 천천히 봐도 된다냥.'),
      ('{{task}} 끝낸 걸 보면 오늘은 서두르지 않아도 되겠다냥.', '지금 흐름이면 서두르지 않아도 되겠다냥.'),
    ],
    encEvening: [
      ('{{task}} 챙긴 게 눈에 띈다냥.', '오늘 챙긴 것들이 눈에 띈다냥.'),
      ('오늘 {{task}} 해낸 건 분명한 성과다냥.', '오늘 해낸 것들은 분명한 성과다냥.'),
    ],
    eveningResistedDone: [
      (
        '{{task}} 하기 싫다더니 결국 {해냈구나냥|끝냈구나냥}! 앞으로도 부담되는 일이 있으면 말하라냥, 내가 적극적으로 {돕겠다냥|도와주겠다냥}.',
        '하기 싫다던 일을 결국 {해냈구나냥|끝냈구나냥}! 앞으로도 부담되는 일이 있으면 말하라냥, 내가 적극적으로 {돕겠다냥|도와주겠다냥}.',
      ),
      (
        '그렇게 미루고 싶어 하던 {{task}}, 결국 {해냈다냥|끝냈다냥}! 버거운 일이 있으면 언제든 말하라냥, 내가 {같이 붙어주겠다냥|끝까지 돕겠다냥}.',
        '미루고 싶어 하던 일을 결국 {해냈다냥|끝냈다냥}! 버거운 일이 있으면 언제든 말하라냥, 내가 {같이 붙어주겠다냥|끝까지 돕겠다냥}.',
      ),
    ],
    otherChoiceLabel: '그 외에 있다냥',
  );
}

/// [MasterGreetingContext] 하나를 문장으로 옮긴다.
///
/// 위젯 상태를 참조하지 않는다. 반복을 피하는 데 쓰는 최근 발화는 [recentLines]로,
/// 무작위는 [random]으로 받는다 — 테스트에서 씨앗을 고정하면 같은 문장이 재현된다.
class MasterGreetingBuilder {
  final GreetingVoice voice;

  /// 최근 코치 발화. 여기 이미 나온 문구는 후보에서 뺀다.
  final List<String> recentLines;

  final Random random;

  MasterGreetingBuilder({
    required this.voice,
    this.recentLines = const [],
    Random? random,
  }) : random = random ?? Random();

  /// 한 발화는 최대 2문장(복귀 인사가 붙으면 그 앞에 한 문장 더).
  MasterGreetingResult build(MasterGreetingContext context) {
    final hour = context.now.hour;
    final parts = <String>[];
    if (context.isComeback) {
      parts.add(pickLine(voice.comeback));
      // 오래 비웠다 돌아온 날은 뭘 했고 뭐가 남았는지 짚지 않는다. 뭉뚱그려
      // 도움을 청하라고만 하고 끝낸다. 새벽 문구는 원래 계획을 안 짚으니 그대로 둔다.
      if (context.slot != GreetingSlot.dawn) {
        parts.add(pickLine(voice.comebackSupport));
        return MasterGreetingResult(parts.join(' '));
      }
    }

    switch (context.slot) {
      case GreetingSlot.dawn:
        // 같은 새벽이라도 5시 전은 아직 안 잔 쪽, 그 뒤는 일찍 일어난 쪽으로 본다.
        parts.add(pickLine(hour < 5 ? voice.dawn : voice.earlyMorning));
        return MasterGreetingResult(parts.join(' '));

      case GreetingSlot.day:
        // 어제 아팠거나 늦게 잔 날은 계획 이야기보다 컨디션을 먼저 챙긴다.
        if (context.feltSick || context.lateNight) {
          parts.add(
            pickLine(context.feltSick ? voice.afterSick : voice.afterLateNight),
          );
          return MasterGreetingResult(parts.join(' '));
        }
        if (hour < 9) {
          // 9시 전에는 계획 유무를 따지지 않고 하루를 여는 인사만 한다.
          final encouragement = _dayEncouragement(context);
          parts.add(pickLine(voice.earlyStart));
          parts.add(
            encouragement.isNotEmpty
                ? encouragement
                : pickLine(voice.earlyQuestions),
          );
          return MasterGreetingResult(parts.join(' '));
        }
        parts.add(_dayLine(context));
        return MasterGreetingResult(parts.join(' '));

      case GreetingSlot.evening:
        // 하기 싫다던 일을 끝낸 날은 그게 오늘의 이야기다. 완료율이 낮아도
        // 뭐가 걸렸는지 되묻지 않고(선택 카드도 띄우지 않고) 해낸 것만 짚는다.
        // 문구가 이미 도움을 청하라는 말로 끝나므로 카드가 하던 몫도 겸한다.
        if (context.resistedDone) {
          final praise = pickEncouragement(
            voice.eveningResistedDone,
            context.resistedDoneLabel,
          );
          if (praise.isNotEmpty) {
            parts.add(praise);
            return MasterGreetingResult(parts.join(' '));
          }
        }
        if (!context.hasPlan) {
          parts.add(pickLine(voice.eveningNoPlan));
          return MasterGreetingResult(parts.join(' '));
        }
        final rate = context.planRate;
        // 18~20시는 낮인지 저녁인지 헷갈리는 시간이라 하루를 아직 접지 않는다.
        final isEarlyEvening = hour < MasterGreetingCopy.earlyEveningUntilHour;
        if (rate <= 0.5) {
          // 귀찮았던 일을 버튼으로 고르게 하고, 고른 일은 실행 저항 흐름으로 넘긴다.
          // 다만 아직 하나도 못 한 저녁 초입에는 뭐가 걸렸는지 묻는 대신
          // 지금 시작해도 늦지 않았다고 말한다.
          parts.add(
            pickLine(
              isEarlyEvening && context.planDone == 0
                  ? voice.earlyEveningNone
                  : voice.eveningLow,
            ),
          );
          return MasterGreetingResult(
            parts.join(' '),
            choices: eveningChoices(context.pendingPlans),
          );
        }
        if (rate >= 1.0) {
          parts.add(pickLine(voice.eveningAll));
        } else if (rate > 0.8) {
          parts.add(
            pickLine(
              isEarlyEvening ? voice.earlyEveningHigh : voice.eveningHigh,
            ),
          );
        } else {
          parts.add(pickLine(voice.eveningMid));
        }
        final encouragement = pickEncouragement(
          voice.encEvening,
          context.doneLabel,
        );
        if (encouragement.isNotEmpty) parts.add(encouragement);
        return MasterGreetingResult(parts.join(' '));
    }
  }

  /// 최근에 쓴 틀은 피해서 고르고, 고른 틀의 갈래를 펼친다.
  String pickLine(List<String> pool) {
    if (pool.isEmpty) return '';
    final fresh = pool
        .where((line) => !recentLines.any((text) => text.contains(anchor(line))))
        .toList(growable: false);
    final candidates = fresh.isNotEmpty ? fresh : pool;
    return expand(candidates[random.nextInt(candidates.length)]);
  }

  /// 갈래 표기 `{가|나}`에서 하나씩 골라 문장 하나로 펼친다.
  ///
  /// 문장을 이어붙이지 않고 한 문장 안에서만 치환하므로 발화 길이가 늘지 않는다.
  /// `{{task}}`는 세로줄이 없어서 갈래로 잡히지 않는다.
  String expand(String template) {
    final filled = template.replaceAllMapped(_group, (match) {
      final options = match.group(1)!.split('|');
      return options[random.nextInt(options.length)];
    });
    // 빈 갈래를 골랐을 때 생기는 이중 공백을 지운다.
    return filled.replaceAll(RegExp(r' {2,}'), ' ').trim();
  }

  /// 반복 회피에 쓸 지문. 갈래 밖 고정 부분 중 가장 긴 조각이다.
  ///
  /// 펼친 문장은 매번 달라서 텍스트를 그대로 비교할 수 없다. 대신 어느 틀에서
  /// 나왔는지 알아볼 수 있는 이 조각으로 본다. 지문이 짧으면 회피가 헐거워지므로
  /// 틀을 늘릴 때는 고정 부분을 남겨야 한다(테스트가 길이를 지킨다).
  String anchor(String template) {
    final fixed = template.split(_group).map((part) => part.trim()).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return fixed.first;
  }

  static final _group = RegExp(r'\{([^{}]*\|[^{}]*)\}');

  /// 격려 문구. 완료한 일 이름이 있으면 문장 안에 녹이고, 없으면 이름 없는 형태를 쓴다.
  String pickEncouragement(List<(String, String)> pool, String? doneLabel) {
    if (pool.isEmpty) return '';
    final variants = pool
        .map(
          (pair) => doneLabel == null
              ? pair.$2
              : pair.$1.replaceAll('{{task}}', doneLabel),
        )
        .toList(growable: false);
    return pickLine(variants);
  }

  /// 미완료 일정은 3개까지만 버튼으로 세우고, 넘치면 '그 외'로 접는다.
  List<String> eveningChoices(List<String> pending) {
    if (pending.isEmpty) return const [];
    if (pending.length <= MasterGreetingCopy.pendingChoiceLimit) {
      return List<String>.unmodifiable(pending);
    }
    return List<String>.unmodifiable([
      ...pending.take(MasterGreetingCopy.pendingChoiceLimit),
      voice.otherChoiceLabel,
    ]);
  }

  /// 9시 이후 낮 발화. 상황과 질문을 각각 한 문장씩 두면 둘이 같은 말을 하게
  /// 되므로(계획 문구가 "막히면 말씀해 주세요"인데 뒤에 "필요하면 말씀해
  /// 주세요"가 또 붙었다) 한 문장만 낸다. 짚을 완료가 있으면 그게 할 말이고,
  /// 없으면 상황 문구를 쓴다 — 상황 문구가 제안까지 안에 품고 있다.
  String _dayLine(MasterGreetingContext context) {
    final encouragement = _dayEncouragement(context);
    if (encouragement.isNotEmpty) return encouragement;
    if (context.now.hour < 12) {
      return pickLine(context.hasPlan ? voice.morningPlan : voice.morningNoPlan);
    }
    return pickLine(
      context.hasPlan ? voice.afternoonBehind : voice.afternoonNoPlan,
    );
  }

  /// 오전·오후 격려. 완료가 있으면 시각과 무관하게 붙는다.
  /// 기준은 완료율이 아니라 개수다 — 자동 주입된 습관이 분모를 오염시키기 때문.
  String _dayEncouragement(MasterGreetingContext context) {
    if (context.doneCount == 0) return '';
    if (context.now.hour < 12) {
      return pickEncouragement(
        context.doneCount >= 3 ? voice.encStrong : voice.encStarted,
        context.doneLabel,
      );
    }
    // 오후에 일정을 하나라도 끝냈으면 완료율과 무관하게 흐름 쪽으로 말한다.
    // 절반을 기준으로 갈라봐야 1/4쯤에서 "벌써 시작하셨네요"가 나가 어색했다.
    if (context.hasPlan && context.planDone > 0) {
      return pickEncouragement(voice.encFlow, context.doneLabel);
    }
    return pickEncouragement(voice.encStarted, context.doneLabel);
  }
}
