/// 목표추진 상태("마감까지 될까", "너무 촉박해", "일정 좀 짜줘") 판정 로직.
///
/// 실행 저항과 짝을 이루는 반대편이다. 저항은 하기 싫은 것이고 이쪽은 하고
/// 싶은데 속도가 모자란 것이다. **하기 싫은 사람은 끌어주고, 하고 싶은데
/// 속도가 필요한 사람은 밀어준다** — 같은 코치가 두 손을 다르게 쓴다.
///
/// 이 상태를 따로 두는 이유는 하나다. 코치의 기본기가 "작게 쪼개기"라서,
/// 마감 계획을 물어도 "5분만 해보자"가 돌아왔다. 부담을 덜어주는 도구를
/// 계산이 필요한 자리에 쓰면 사용자는 답을 못 받는다.
///
/// 저항 표현이 함께 있으면 저항이 이긴다. "마감인데 하기 싫어"는 마감이
/// 문제가 아니라 하기 싫은 게 문제여서, 끌어주는 쪽이 먼저다.
class GoalPushService {
  const GoalPushService._();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 주어와 서술어 사이에 끼어드는 부사들. 고정 문자열로만 찾으면
  /// "일정이 너무 촉박해" 같은 실제 문장을 통째로 놓친다.
  static const String _adverbGap =
      r'(?:너무|정말|진짜|많이|좀|꽤|되게|엄청|아주|워낙|이미|벌써)*';

  /// 마감이 걸려 있다는 신호.
  static final List<RegExp> _deadlinePatterns = [
    RegExp('마감[이가은]?$_adverbGap(?:촉박|빠듯|얼마|코앞|다가|임박)'),
    RegExp('일정[이가은]?$_adverbGap(?:촉박|빠듯|빡빡)'),
    RegExp('시간[이가은]?$_adverbGap(?:촉박|빠듯|모자|부족)'),
    RegExp(r'(?:며칠|얼마|하루)밖에$_adverbGap?안남'),
    RegExp('안에$_adverbGap(?:끝내|마쳐|해내)'),
  ];

  /// 부사가 낄 자리가 없는 표현들.
  static const List<String> _deadlineSignals = [
    '마감까지',
    '마감전',
    '마감인데',
    '데드라인',
    '언제까지해야',
    '기한',
    '제출해야',
    '빨리끝내',
    '서둘러야',
    '늦으면안',
  ];

  /// 계획을 짜달라는 요청. 마감이라는 말이 없어도 계산으로 답할 자리다.
  static const List<String> _planRequestSignals = [
    '일정짜',
    '일정좀짜',
    '계획짜',
    '계획좀짜',
    '스케줄짜',
    '세부일정',
    '일정을짜',
    '계획을짜',
    '나눠서해야',
    '하루에얼마나',
    '며칠걸리',
  ];

  /// 하기 싫다는 쪽 신호. 이게 같이 있으면 목표추진이 아니다.
  ///
  /// 목록을 짧게 둔다. 실행 저항 판정은 이미 앱 안에 따로 있고, 여기서는
  /// "밀면 안 되는 말이 섞였는가"만 보면 된다.
  static const List<String> _resistanceSignals = [
    '하기싫',
    '하기시러',
    '귀찮',
    '부담',
    '엄두',
    '못하겠',
    '손이안',
    '시작이안',
    '무서워',
    '자신없',
  ];

  /// 마감이나 계획 요청이 들어 있는지. 하기 싫다는 말이 섞였는지는 안 본다.
  static bool mentionsDeadlineOrPlan(String text) {
    final normalized = _normalize(text);
    if (_deadlineSignals.any(normalized.contains)) return true;
    if (_planRequestSignals.any(normalized.contains)) return true;
    return _deadlinePatterns.any((p) => p.hasMatch(normalized));
  }

  /// 밀어도 되는 자리인지. 마감이나 계획 요청이 있고 저항이 섞이지 않았을 때.
  static bool isGoalPushExpression(String text) {
    final normalized = _normalize(text);
    if (_resistanceSignals.any(normalized.contains)) return false;
    return mentionsDeadlineOrPlan(text);
  }

  /// 하겠다는 마음이 드러난 표현. 마감이 없어도 밀어줄 자리다.
  ///
  /// 시작하면 잘하고 싶어지는 게 사람 마음인데, 이 앱의 기본기가 "작게
  /// 쪼개기"라서 그때마다 브레이크가 걸렸다. 하겠다는 사람에게 "천천히 해도
  /// 된다"고 하면 답답하고, 무엇보다 코치의 수가 하나뿐이라는 게 드러난다.
  /// 뭘 말하든 같은 답이 돌아오면 그때부터 코치가 아니라 자동응답기다.
  static const List<String> _driveSignals = [
    '다끝낼',
    '다끝내',
    '끝장',
    '몰아서',
    '한번에끝',
    '오늘안에끝',
    '더할래',
    '더하고싶',
    '제대로하고싶',
    '제대로해보',
    '열심히해보',
    '달려볼',
    '해치우',
    '이번엔진짜',
    '이번엔제대로',
    '각잡고',
    '풀로',
    '밤새서',
  ];

  /// 하겠다는 어미. "대청소할래", "정리할 거야"처럼 의욕이 어미에만 실릴 때가
  /// 많은데, 위의 목록은 전부 강도가 센 표현이라 그런 말을 다 놓쳤다.
  ///
  /// 하다 계열만 본다. '~려고'까지 넓히면 "쓰려고"를 잡는 대신 "자려고",
  /// "쉬려고", "미루려고"까지 하겠다는 말로 읽는다. 못 잡는 것보다 잘못 잡는
  /// 쪽이 나쁘다 — 자려는 사람을 밀어붙이게 된다.
  static final RegExp _intentEnding = RegExp(r'할래|할거야|할게|해야지|하려고');

  /// 같은 어미를 쓰면서 뜻은 정반대인 말들. 어미 바로 앞에 이것들이 붙는다.
  /// "안 할래", "그만할래", "내일 할래"를 하겠다는 말로 읽으면 안 된다.
  static const List<String> _intentReversers = [
    '안',
    '못',
    '그만',
    '포기',
    '내일',
    '나중에',
    '이따',
    '주말에',
  ];

  static bool _showsIntent(String normalized) {
    for (final match in _intentEnding.allMatches(normalized)) {
      final before = normalized.substring(0, match.start);
      if (_intentReversers.any(before.endsWith)) continue;
      return true;
    }
    return false;
  }

  static bool showsDrive(String text) {
    final normalized = _normalize(text);
    if (_resistanceSignals.any(normalized.contains)) return false;
    return _driveSignals.any(normalized.contains) || _showsIntent(normalized);
  }

  /// 하기 싫다는 말과 마감이 함께 있는 자리.
  ///
  /// 위로만 하고 끝내면 마감은 그대로 온다. 그렇다고 밀기만 하면 하기 싫다고
  /// 말한 사람을 못 본 척하는 것이다. 끌고 나서 미는 순서가 필요하다.
  static bool isReluctantDeadline(String text) {
    final normalized = _normalize(text);
    if (!_resistanceSignals.any(normalized.contains)) return false;
    return mentionsDeadlineOrPlan(text);
  }

  /// 사용자가 스스로 속도를 원한다고 말했는지.
  ///
  /// 독촉은 이 앱이 함부로 할 일이 아니다. "작심삼일도 괜찮다"고 말해 온
  /// 코치가 갑자기 몰아붙이면 그 말이 거짓이 된다. 다만 본인이 촉박하다고
  /// 말했을 때의 재촉은 요청받은 것이라 다르다.
  static bool wantsSpeed(String text) {
    final normalized = _normalize(text);
    return _resistanceSignals.every((s) => !normalized.contains(s)) &&
        (_deadlineSignals.any(normalized.contains) ||
            _deadlinePatterns.any((p) => p.hasMatch(normalized)));
  }
}
