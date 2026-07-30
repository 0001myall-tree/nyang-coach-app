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
  final List<String> morningPlan; // 09~12시, 계획 있음
  final List<String> morningNoPlan;
  final List<String> afternoonPlan; // 12~18시, 계획 있고 진척도 있음
  final List<String> afternoonBehind; // 12~18시, 계획은 있는데 아직 완료 0
  final List<String> afternoonNoPlan;
  final List<String> dayQuestions;
  final List<String> eveningLow; // 완료 50% 이하
  final List<String> eveningMid; // 51~80%
  final List<String> eveningHigh; // 81~99%
  final List<String> eveningAll; // 100%
  final List<String> eveningNoPlan;
  final List<String> comeback; // 2일 이상 만에 돌아왔을 때 앞에 붙일 한 문장
  final List<String> afterLateNight; // 늦게 잔 다음 날 낮
  final List<String> afterSick; // 아프다고 한 다음 날 낮

  /// 격려 문구. (완료 항목 이름을 넣는 형태, 이름 없이 쓰는 형태) 순서다.
  final List<(String, String)> encStarted; // 오전 1~2개 완료
  final List<(String, String)> encStrong; // 오전 3개 이상 완료
  final List<(String, String)> encFlow; // 오후 절반 이상 완료
  final List<(String, String)> encEvening; // 저녁 발화용

  final String otherChoiceLabel;

  const GreetingVoice({
    required this.dawn,
    required this.earlyMorning,
    required this.earlyStart,
    required this.earlyQuestions,
    required this.morningPlan,
    required this.morningNoPlan,
    required this.afternoonPlan,
    required this.afternoonBehind,
    required this.afternoonNoPlan,
    required this.dayQuestions,
    required this.eveningLow,
    required this.eveningMid,
    required this.eveningHigh,
    required this.eveningAll,
    required this.eveningNoPlan,
    required this.comeback,
    required this.afterLateNight,
    required this.afterSick,
    required this.encStarted,
    required this.encStrong,
    required this.encFlow,
    required this.encEvening,
    required this.otherChoiceLabel,
  });
}

class MasterGreetingCopy {
  /// 이 길이를 넘는 제목은 말풍선에서 겉돌아서 이름을 빼고 격려만 한다.
  static const doneLabelMaxLength = 20;

  /// 저녁 선택 카드에 버튼으로 직접 노출할 일정 개수. 넘으면 '그 외'로 접는다.
  static const pendingChoiceLimit = 3;

  static GreetingVoice forCoach(String coachId) =>
      coachId == 'nyang_halbae' ? nyangHalbae : secretary;

  static const secretary = GreetingVoice(
    dawn: [
      '늦은 시간이네요. 오늘은 여기까지 하고 쉬어가셔도 좋겠습니다.',
      '아직 깨어 계시는군요. 남은 건 내일의 대표님께 맡겨두시죠.',
      '이 시간엔 잘 자는 것이 가장 좋은 준비입니다.',
    ],
    earlyMorning: [
      '오늘 일찍 오셨네요. 왠지 좋은 하루가 기다리고 있을 것 같은데요?',
      '이른 시간부터 움직이시는군요. 느낌이 좋습니다.',
      '아침이 열리기 전부터 나와 계시네요. 이 조용한 시간, 꽤 좋죠.',
      '일찍 시작하는 날이네요. 여유로운 하루 되셨으면 좋겠습니다.',
    ],
    earlyStart: [
      '오늘도 새로운 하루가 시작되었습니다.',
      '새 하루가 열렸네요.',
      '오늘 하루가 이제 막 시작됐습니다.',
      '아침이 왔습니다.',
    ],
    earlyQuestions: [
      '필요하신 게 있으면 말씀해 주세요.',
      '천천히 준비하시고, 필요할 때 불러주세요.',
      '무엇부터 살펴볼까요?',
    ],
    morningPlan: [
      '오늘 계획은 챙겨두었습니다.',
      '오늘 할 일은 정리해 두었어요.',
      '오전이 아직 넉넉하게 남아 있습니다.',
    ],
    morningNoPlan: [
      '아직 오늘 계획이 없네요.',
      '오늘은 아직 비어 있는 하루입니다.',
      '오늘 적어둔 일정이 아직 없어요.',
    ],
    afternoonPlan: [
      '오후로 넘어왔는데 지금 흐름이면 몰아붙이지 않으셔도 괜찮습니다.',
      '하루의 절반쯤 지났고, 여기까지 오셨으면 남은 건 천천히 보셔도 됩니다.',
      '오후가 시작됐고, 지금까지 온 걸 보면 서두를 필요는 없어 보여요.',
    ],
    afternoonBehind: [
      '오후로 넘어왔고 오늘 일정은 아직 그대로 기다리고 있습니다.',
      '하루의 절반이 지났는데 아직 손대지 못한 일들이 남아 있네요.',
      '오후가 시작됐어요. 남겨둔 것 중 가벼운 것부터 보시죠.',
    ],
    afternoonNoPlan: [
      '오후인데 아직 오늘 계획이 없네요.',
      '오늘은 아직 적어둔 일정 없이 오후가 됐습니다.',
    ],
    dayQuestions: [
      '무엇부터 시작해볼까요?',
      '어떤 것부터 손대볼까요?',
      '하나만 골라볼까요?',
      '필요하신 게 있으면 말씀해 주세요.',
    ],
    eveningLow: [
      '오늘 하루도 수고하셨습니다. 남은 것 중에 유독 손이 안 가는 게 있으셨나요?',
      '고생 많으셨어요. 오늘 미뤄진 일 중에 특히 귀찮았던 게 있을까요?',
      '오늘도 여기까지 오셨네요. 자꾸 미뤄지는 일이 있다면 어떤 걸까요?',
    ],
    eveningMid: [
      '오늘 흐름이 좋으셨네요.',
      '오늘 하루, 꽤 잘 굴러갔습니다.',
      '오늘은 흐름을 잘 지키셨어요.',
    ],
    eveningHigh: [
      '이 정도면 곧 다 완료하시겠는데요.',
      '거의 다 오셨습니다.',
      '마무리가 눈앞이네요.',
    ],
    eveningAll: [
      '오늘 계획을 전부 마치셨습니다.',
      '오늘은 남김없이 끝내셨네요.',
      '오늘 몫을 완주하셨어요.',
    ],
    eveningNoPlan: [
      '오늘은 어떻게 보내셨어요?',
      '오늘 하루는 어떠셨나요?',
      '오늘은 어떤 하루였는지 궁금하네요.',
    ],
    comeback: [
      '다시 뵈어 반갑습니다.',
      '오랜만이네요. 돌아와 주셔서 좋습니다.',
      '잠시 쉬었다 오셨군요.',
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
    encFlow: [
      ('{{task}}까지 마치신 걸 보니 흐름이 좋으십니다.', '여기까지 오셨네요. 흐름이 좋으십니다.'),
      ('{{task}} 끝내셨으니 오늘 흐름은 잘 잡히셨네요.', '오늘 흐름이 좋으시네요.'),
    ],
    encEvening: [
      ('{{task}} 챙기신 게 눈에 띕니다.', '오늘 챙기신 것들이 눈에 띕니다.'),
      ('오늘 {{task}} 해내신 건 분명한 성과예요.', '오늘 해내신 것들은 분명한 성과예요.'),
    ],
    otherChoiceLabel: '그 외에 있어요',
  );

  static const nyangHalbae = GreetingVoice(
    dawn: [
      '늦은 시간까지 깨어 있구나냥. 오늘은 여기서 접고 자도 된다냥.',
      '이 시간엔 잘 자두는 게 제일 큰 준비다냥.',
      '밤이 깊었다냥. 남은 건 내일의 자네한테 맡기자냥.',
    ],
    earlyMorning: [
      '오늘은 일찍 나왔구나냥. 왠지 좋은 하루가 기다리고 있을 것 같다냥.',
      '이른 시간부터 움직이는구나냥. 느낌이 좋다냥.',
      '해도 안 뜬 시간에 나왔구나냥. 이 조용한 시간이 제법 좋다냥.',
      '일찍 시작하는 날이구나냥. 오늘은 여유로운 하루가 되면 좋겠다냥.',
    ],
    earlyStart: [
      '새 하루가 시작됐다냥.',
      '오늘이 막 열렸구나냥.',
      '아침이 왔다냥.',
      '또 하루가 왔구나냥.',
    ],
    earlyQuestions: [
      '필요한 게 있으면 부르라냥.',
      '천천히 준비하다 부르면 된다냥.',
      '뭐부터 볼까냥.',
    ],
    morningPlan: [
      '오늘 할 일은 챙겨뒀다냥.',
      '오늘 계획은 여기 그대로 있다냥.',
      '오전은 아직 넉넉하다냥.',
    ],
    morningNoPlan: [
      '아직 오늘 계획이 없구나냥.',
      '오늘은 아직 비어 있는 하루다냥.',
      '적어둔 일이 아직 없구나냥.',
    ],
    afternoonPlan: [
      '오후로 넘어왔는데 지금 흐름이면 서두르지 않아도 된다냥.',
      '하루가 절반쯤 지났고, 여기까지 왔으면 남은 건 천천히 봐도 된다냥.',
      '오후가 시작됐고, 지금까지 온 걸 보면 급할 것 없다냥.',
    ],
    afternoonBehind: [
      '오후로 넘어왔는데 오늘 일은 아직 그대로 기다리고 있다냥.',
      '하루의 절반이 지났는데 아직 손대지 못한 게 남아 있구나냥.',
      '오후가 시작됐다냥. 남겨둔 것 중 가벼운 것부터 보자냥.',
    ],
    afternoonNoPlan: [
      '오후가 됐는데 아직 계획이 없구나냥.',
      '적어둔 일 없이 오후가 왔다냥.',
    ],
    dayQuestions: [
      '뭐부터 시작해볼까냥.',
      '어떤 것부터 손대볼까냥.',
      '하나만 골라보자냥.',
      '필요한 게 있으면 말하라냥.',
    ],
    eveningLow: [
      '오늘도 고생했다냥. 남은 것 중에 유독 손이 안 가는 게 있었냥?',
      '수고했다냥. 오늘 미뤄진 일 중에 특히 귀찮았던 게 있냥?',
      '여기까지 왔구나냥. 자꾸 미뤄지는 일이 있다면 뭐냥?',
    ],
    eveningMid: [
      '오늘 흐름이 좋았다냥.',
      '오늘 하루 제법 잘 굴러갔다냥.',
      '오늘은 흐름을 잘 지켰다냥.',
    ],
    eveningHigh: [
      '이 정도면 곧 다 끝내겠구나냥.',
      '거의 다 왔다냥.',
      '마무리가 코앞이구나냥.',
    ],
    eveningAll: [
      '오늘 계획을 전부 마쳤구나냥.',
      '오늘은 남김없이 끝냈다냥.',
      '오늘 몫을 완주했구나냥.',
    ],
    eveningNoPlan: [
      '오늘은 어떻게 보냈냥?',
      '오늘 하루는 어땠냥?',
      '오늘은 어떤 하루였냥?',
    ],
    comeback: [
      '오랜만이구나냥.',
      '다시 와줬구나냥.',
      '쉬었다 다시 걷는 것도 좋다냥.',
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
      ('{{task}}까지 마친 걸 보니 흐름이 좋구나냥.', '여기까지 왔다냥. 흐름이 좋구나냥.'),
      ('{{task}} 끝냈으니 오늘 흐름은 잘 잡혔다냥.', '오늘 흐름이 좋구나냥.'),
    ],
    encEvening: [
      ('{{task}} 챙긴 게 눈에 띈다냥.', '오늘 챙긴 것들이 눈에 띈다냥.'),
      ('오늘 {{task}} 해낸 건 분명한 성과다냥.', '오늘 해낸 것들은 분명한 성과다냥.'),
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
        final encouragement = _dayEncouragement(context);
        if (hour < 9) {
          // 9시 전에는 계획 유무를 따지지 않고 하루를 여는 인사만 한다.
          parts.add(pickLine(voice.earlyStart));
          parts.add(
            encouragement.isNotEmpty
                ? encouragement
                : pickLine(voice.earlyQuestions),
          );
        } else if (hour < 12) {
          parts.add(
            pickLine(context.hasPlan ? voice.morningPlan : voice.morningNoPlan),
          );
          parts.add(
            encouragement.isNotEmpty
                ? encouragement
                : pickLine(voice.dayQuestions),
          );
        } else {
          final List<String> pool;
          if (!context.hasPlan) {
            pool = voice.afternoonNoPlan;
          } else if (context.planDone > 0) {
            pool = voice.afternoonPlan;
          } else {
            pool = voice.afternoonBehind;
          }
          parts.add(pickLine(pool));
          parts.add(
            encouragement.isNotEmpty
                ? encouragement
                : pickLine(voice.dayQuestions),
          );
        }
        return MasterGreetingResult(parts.join(' '));

      case GreetingSlot.evening:
        if (!context.hasPlan) {
          parts.add(pickLine(voice.eveningNoPlan));
          return MasterGreetingResult(parts.join(' '));
        }
        final rate = context.planRate;
        if (rate <= 0.5) {
          // 귀찮았던 일을 버튼으로 고르게 하고, 고른 일은 실행 저항 흐름으로 넘긴다.
          parts.add(pickLine(voice.eveningLow));
          return MasterGreetingResult(
            parts.join(' '),
            choices: eveningChoices(context.pendingPlans),
          );
        }
        if (rate >= 1.0) {
          parts.add(pickLine(voice.eveningAll));
        } else if (rate > 0.8) {
          parts.add(pickLine(voice.eveningHigh));
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

  /// 최근에 쓴 문장은 피해서 고른다.
  String pickLine(List<String> pool) {
    if (pool.isEmpty) return '';
    final fresh = pool
        .where((line) => !recentLines.any((text) => text.contains(line)))
        .toList(growable: false);
    final candidates = fresh.isNotEmpty ? fresh : pool;
    return candidates[random.nextInt(candidates.length)];
  }

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

  /// 오전·오후 격려. 완료가 있으면 시각과 무관하게 붙고, 붙으면 질문을 뺀다.
  /// 기준은 완료율이 아니라 개수다 — 자동 주입된 습관이 분모를 오염시키기 때문.
  String _dayEncouragement(MasterGreetingContext context) {
    if (context.doneCount == 0) return '';
    if (context.now.hour < 12) {
      return pickEncouragement(
        context.doneCount >= 3 ? voice.encStrong : voice.encStarted,
        context.doneLabel,
      );
    }
    if (context.hasPlan && context.planRate >= 0.5) {
      return pickEncouragement(voice.encFlow, context.doneLabel);
    }
    return pickEncouragement(voice.encStarted, context.doneLabel);
  }
}
