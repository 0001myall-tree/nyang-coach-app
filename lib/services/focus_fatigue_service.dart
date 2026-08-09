/// 집중력 저하("집중이 안 돼", "머리에 안 들어와", "자꾸 딴짓하게 돼") 판정 로직.
///
/// 실행 저항과 정반대 상태다. 저항은 아직 일에 못 붙은 것이고, 이건 이미
/// 붙어 있었는데 흐트러진 것이다. 앞이면 첫 조각을 줘야 하고 뒤면 잠깐
/// 떼어놔야 해서, 같은 "집중이 안 돼"라는 말이라도 대응이 반대가 된다.
///
/// 흐름: 집중력 저하 표현 → 얼마나 했는지 확인 → 오래 했으면 환기,
///       애매하면 짧은 집중 단위, "아직 시작도 못 했다"면 실행 저항으로 되돌림
///
/// 작업 시간을 앱 기록으로 알아내려 하면 대부분 빈다. 기록을 꼬박꼬박 남기는
/// 사용자가 드물기 때문이다. 그래서 1차 분류를 말투로 한다. 한국어에서
/// "안 써져 / 안 들어와"(진행 중 실패)와 "손이 안 가 / 엄두가 안 나"(진입
/// 실패)는 갈리고, 뒤쪽은 이미 실행 저항 신호 목록에 들어가 있어서 두 상태가
/// 자연스럽게 겹치지 않는다.
class FocusFatigueService {
  const FocusFatigueService._();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 주어와 서술어 사이에 끼어드는 부사들.
  ///
  /// "집중이 안 돼"와 "집중이 너무 안 된다"는 같은 말인데, 고정 문자열로
  /// 찾으면 뒤쪽을 통째로 놓친다. 실제로 사용자가 쓰는 문장은 거의 부사가
  /// 낀 쪽이라 여기를 비워두면 판정이 대부분 빗나간다.
  static const String _adverbGap =
      r'(?:너무|정말|진짜|하나도|도무지|전혀|통|영|당최|잘|자꾸|계속|더는|이제|좀|많이|워낙|당췌)*';

  /// 집중력 저하 신호. 진행형 실패 표현만 모은다.
  static final List<RegExp> _focusFatiguePatterns = [
    RegExp('집중(?:력)?[이은가]?$_adverbGap안'),
    RegExp('집중(?:력)?[이은가]?$_adverbGap(?:떨어|바닥|흐트|깨|날아)'),
    RegExp('머리에$_adverbGap안들어'),
    RegExp('눈에$_adverbGap안들어'),
    RegExp('글이$_adverbGap안(?:써|나)'),
    RegExp('진도가$_adverbGap안'),
    RegExp('머리가$_adverbGap안돌아'),
  ];

  /// 부사가 끼어들 자리가 없는 표현들.
  static const List<String> _focusFatigueSignals = [
    '딴짓',
    '산만해',
    '산만하',
    '멍하니',
    '멍때',
    '머리가굳',
  ];

  /// "아직 시작도 못 했다"는 답. 이때는 집중력 저하가 아니라 실행 저항이다.
  /// 여기서 놓치면 시작조차 못 한 사람에게 "환기하고 와"를 권하게 되고,
  /// 그날 아예 시작을 못 하게 된다. 틀렸을 때 비용이 가장 큰 자리다.
  static const List<String> _notStartedSignals = [
    '아직시작',
    '시작도못',
    '시작못했',
    '시작안했',
    '손도못',
    '손도안',
    '아직안했',
    '아직못했',
    '이제하려',
    '이제시작',
    '하나도안했',
    '하나도못했',
    '한글자도',
    '아직아무것도',
  ];

  /// "계속 붙잡고 있었다"는 답. 확신이 설 때만 환기로 간다.
  static const List<String> _workedLongSignals = [
    '계속하고있',
    '계속했',
    '계속쓰',
    '계속보고있',
    '아까부터',
    '아침부터',
    '오전내내',
    '하루종일',
    '종일',
    '시간째',
    '시간동안',
    '시간넘게',
    '한참했',
    '한참하',
    '오래했',
    '오래하고',
    '쭉하고',
    '쭉했',
  ];

  static bool isFocusFatigueExpression(String text) {
    final normalized = _normalize(text);
    if (_focusFatigueSignals.any(normalized.contains)) return true;
    return _focusFatiguePatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  static bool saysNotStartedYet(String text) =>
      _notStartedSignals.any(_normalize(text).contains);

  static bool saysWorkedLong(String text) =>
      _workedLongSignals.any(_normalize(text).contains);

  /// 되묻고 받은 답으로 볼 수 있는 턴인지.
  ///
  /// 사용자가 화제를 바꿔 버린 턴까지 후속으로 세면 엉뚱한 말에 이 전략이
  /// 실린다. 시간을 묻는 질문의 답은 대체로 짧아서 길이로도 걸러진다.
  static bool looksLikeWorkHistoryAnswer(String text) =>
      saysWorkedLong(text) ||
      saysNotStartedYet(text) ||
      text.trim().length <= 25;
}
