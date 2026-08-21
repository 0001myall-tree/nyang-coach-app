/// 등록해달라는 말에서 "무엇을" 넣을지가 이 문장에 있는지 본다.
///
/// 등록 명령은 정규식이 먼저 잡아 API를 쓰지 않고 그 자리에서 카드를 띄운다.
/// 빠르고 공짜지만, 정규식은 이 문장 하나만 본다. 앞 턴에서 무슨 이야기를
/// 하고 있었는지는 모른다.
///
/// 그래서 "스트레칭 어때? → 할일에 추가해줘" 같은 흐름이 어긋난다. 꼬리인
/// '추가해줘'를 떼면 '할일에'가 남고, 그게 그대로 일정 이름이 됐다.
///
/// 이런 문장은 정규식이 맡지 않고 코치에게 넘긴다. 코치는 앞 대화를 보고
/// 있으므로 무엇을 말하는지 알고, [SCHEDULE:] 태그로 이름을 짚어준다.
/// 한 턴 느려지고 API를 한 번 쓰지만, 엉뚱한 이름으로 등록되는 것보다 낫다.
library;

class RegistrationTarget {
  /// 넣을 자리만 가리키는 말. 조사가 붙어 오므로 뒤쪽은 열어둔다 —
  /// "할일에", "할일로", "할일 목록에" 모두 같은 말이다.
  static final RegExp _placeOnly = RegExp(
    r'^(?:오늘|내일|모레)?'
    r'(?:할일|할것|일정|캘린더|계획|목록|리스트|스케줄|투두|루틴|습관)'
    r'(?:목록|리스트|탭|텝)?'
    r'(?:에다가?|에|으로|로|안에|쪽에)?$',
  );

  /// 앞 턴을 가리키는 말.
  static final RegExp _pointsBack = RegExp(
    r'^(?:이거|이것|이걸|그거|그것|그걸|저거|저것|저걸'
    r'|방금거|방금것|아까거|아까것|위에거|그일|이일)'
    r'(?:도|를|을|은|는|이|가)?$',
  );

  /// 문장 앞머리에 붙는 말. 이름이 아니다.
  static final RegExp _leadIn = RegExp(
    r'^(?:나|난|내가|저|전|제가|우리|이제|그럼|그러면|그리고|근데|아)\s+',
  );

  /// 이름이 이 문장에 없으면 true.
  static bool nameIsElsewhere(String beforeSuffix) {
    var rest = beforeSuffix.trim();
    rest = rest.replaceFirst(_leadIn, '');
    rest = rest.replaceAll(RegExp(r'\s+'), '');
    if (rest.isEmpty) return true;
    return _placeOnly.hasMatch(rest) || _pointsBack.hasMatch(rest);
  }
}
