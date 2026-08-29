/// 코치가 답변 끝에 붙이는 플래너 조작 태그.
///
/// 정규식이 잡는 등록 명령과 달리, 이쪽은 앞 대화를 봐야 무엇을 말하는지 아는
/// 요청을 받는다. "아까 그거 8시로 옮겨줘", "어제 했던 청소 완료했어"처럼.
/// 코치는 오늘 일정 목록과 최근 대화를 함께 보고 있으므로 무엇을 가리키는지
/// 알아내고, 목록에 적힌 이름 그대로 태그에 적어 보낸다.
///
/// 앱은 이름으로 찾기만 한다. 말을 알아듣는 일과 데이터를 고치는 일을 갈라두면,
/// 새 말투가 나와도 앱은 손댈 것이 없다.
///
/// 태그를 받았다고 바로 고치지 않는다. 코치가 알아들은 것이 맞는지 확인 카드로
/// 한 번 묻고, 사용자가 누른 뒤에 값이 바뀐다. 되돌리기 쉬운 동작도 예외가 없다.
///
/// ## 카드로 받을지, 화면으로 데려갈지
///
/// 정할 값이 하나면 확인 카드로 묻고 앱이 쓴다. 값이 여럿이면 그 화면으로
/// 데려가고 앱은 아무것도 쓰지 않는다.
///
/// - 카드: 등록([TASK]·[SCHEDULE]·[HABIT]·[GOAL])과 완료([DONE]). 정할 것이
///   이름 하나, 또는 참/거짓 하나뿐이라 카드에서 확인하면 끝난다.
/// - 화면: 옮기기([MOVE])와 알람([REMIND]·[MORNING]). 시각·날짜·요일·스위치가
///   한 화면에 얽혀 있어서, 하나만 태그로 고치면 나머지와 어긋난다. 예전에
///   대신 고쳐주다 형식이 조금만 달라도 그 자리에서 조용히 실패했고, 코치가
///   바꿔주겠다고 말한 뒤였기에 사용자에게는 거짓말로 보였다.
///
/// 태그를 새로 만들 때는 이 기준으로 어느 쪽인지 먼저 정할 것.
library;

/// 무엇을 하려는지.
enum PlannerActionKind {
  /// 시각이나 날짜를 옮긴다.
  move,

  /// 완료로 표시한다. 지난 날의 일도 된다.
  done,

  /// 그 일정의 알람을 켜거나 끈다.
  remind,

  /// 모닝콜 시각을 바꾸거나 끈다.
  morning,
}

class PlannerAction {
  const PlannerAction({
    required this.kind,
    this.target = '',
    this.date,
    this.time,
    this.enabled,
  });

  final PlannerActionKind kind;

  /// 코치가 짚어준 일정 이름. 모닝콜에는 없다.
  final String target;

  /// 옮길 날짜, 또는 완료로 표시할 날. 없으면 오늘.
  final DateTime? date;

  /// 옮길 시각, 또는 모닝콜 시각.
  final ({int hour, int minute})? time;

  /// 켜는지 끄는지. [PlannerActionKind.remind]와 모닝콜에서 쓴다.
  final bool? enabled;

  /// 이름 자리는 없어도 된다. 모닝콜은 가리킬 일정이 없어 [MORNING]만 온다.
  static final RegExp _tag = RegExp(
    r'\[(MOVE|DONE|REMIND|MORNING)(?::\s*([^\]]*))?\]',
    caseSensitive: false,
  );

  static final RegExp _date = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
  static final RegExp _time = RegExp(r'(\d{1,2}):(\d{2})');

  /// "오후 6시", "6시 30분"처럼 우리말로 적어 보내는 경우.
  ///
  /// 형식은 HH:MM으로 적으라고 일러두지만 지키지 않을 때가 있다. 그때 조용히
  /// 버리면 사용자에게는 코치가 바꿔주겠다고 해놓고 아무 일도 안 한 것으로 보인다.
  static final RegExp _koreanTime = RegExp(
    r'(오전|오후)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?',
  );

  /// 답변에서 태그를 찾아낸다. 없으면 null.
  ///
  /// 한 턴에 하나만 받는다. 여러 개가 오면 첫 번째만 쓴다 — 카드가 겹치면
  /// 무엇을 고르는 건지 알기 어렵고, 앞의 조작이 뒤의 대상을 바꿔놓기도 한다.
  ///
  /// 완료만 예외다. 서로 건드리지 않아서 한 장에 모아 물을 수 있고, 이름은
  /// [doneTargets]가 따로 모아준다.
  static PlannerAction? parse(String reply) {
    final match = _tag.firstMatch(reply);
    if (match == null) return null;

    final kind = switch (match.group(1)!.toUpperCase()) {
      'MOVE' => PlannerActionKind.move,
      'DONE' => PlannerActionKind.done,
      'REMIND' => PlannerActionKind.remind,
      _ => PlannerActionKind.morning,
    };

    final parts = (match.group(2) ?? '')
        .split('|')
        .map((part) => part.trim())
        .toList();
    final rest = parts.skip(1).join(' ');

    // 모닝콜만 이름 자리가 없다. 첫 칸부터 값이다.
    final valueText = kind == PlannerActionKind.morning
        ? parts.join(' ')
        : rest;

    return PlannerAction(
      kind: kind,
      target: kind == PlannerActionKind.morning
          ? ''
          : (parts.isEmpty ? '' : parts.first),
      date: _readDate(valueText),
      time: _readTime(valueText),
      enabled: _readSwitch(valueText),
    );
  }

  /// 끝냈다고 짚은 이름 전부. 없으면 빈 목록.
  ///
  /// 완료만 여러 개를 받는다. 옮기기·알람은 하나씩 확인해야 하지만 — 앞의
  /// 조작이 뒤의 대상을 바꿔놓기도 한다 — 완료는 서로 건드리지 않아서 한 장에
  /// 모아 물어볼 수 있다. "다 했어"라고 한 사람에게 카드를 세 번 띄우거나
  /// 하나만 체크해주는 것은 둘 다 답이 아니다.
  static List<String> doneTargets(String reply) {
    final names = <String>[];
    for (final match in _tag.allMatches(reply)) {
      if (match.group(1)!.toUpperCase() != 'DONE') continue;
      final name = (match.group(2) ?? '').split('|').first.trim();
      if (name.isEmpty || names.contains(name)) continue;
      names.add(name);
    }
    return names;
  }

  /// 태그를 떼어낸 답변. 태그는 사용자에게 보이면 안 된다.
  static String strip(String reply) => reply.replaceAll(_tag, '').trim();

  static DateTime? _readDate(String text) {
    final m = _date.firstMatch(text);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final parsed = DateTime(year, month, day);
    // 2월 30일처럼 없는 날은 다음 달로 넘어간다. 그건 받지 않는다.
    if (parsed.month != month || parsed.day != day) return null;
    return parsed;
  }

  static ({int hour, int minute})? _readTime(String text) {
    final m = _time.firstMatch(text);
    if (m != null) {
      final hour = int.parse(m.group(1)!);
      final minute = int.parse(m.group(2)!);
      if (hour <= 23 && minute <= 59) return (hour: hour, minute: minute);
    }
    return _readKoreanTime(text);
  }

  /// 우리말로 적힌 시각. 오전/오후가 없으면 읽지 않는다.
  ///
  /// "6시"만으로는 아침인지 저녁인지 알 수 없다. 한쪽으로 찍으면 절반은 틀리고,
  /// 틀린 채로 카드가 떠서 사용자가 눌러버리면 조용히 엉뚱한 시각이 된다.
  /// 13시처럼 그 자체로 갈리는 것만 받는다.
  static ({int hour, int minute})? _readKoreanTime(String text) {
    final m = _koreanTime.firstMatch(text);
    if (m == null) return null;
    final ampm = m.group(1);
    var hour = int.parse(m.group(2)!);
    final minute = int.parse(m.group(3) ?? '0');
    if (hour > 23 || minute > 59) return null;
    if (ampm == '오후' && hour < 12) hour += 12;
    if (ampm == '오전' && hour == 12) hour = 0;
    if (ampm == null && hour < 13) return null;
    return (hour: hour, minute: minute);
  }

  static bool? _readSwitch(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(off|끄기|해제)\b|끔').hasMatch(lower)) return false;
    if (RegExp(r'\b(on|켜기|설정)\b|켬').hasMatch(lower)) return true;
    return null;
  }

  /// 이 태그로 데려갈 곳을 정할 수 있는지.
  ///
  /// 이름만 있으면 된다. 시각과 날짜는 데려간 화면에 이미 있고, 사용자가 그
  /// 화면에서 고른다. 앱이 시각을 읽어 대신 바꾸던 때는 "18:00" 대신 "6시"로
  /// 적혀 오면 그 자리에서 조용히 실패했다.
  bool get isUsable => switch (kind) {
    PlannerActionKind.morning => true,
    // 이름 없는 알람 이야기는 일정 알람 설정 자체를 가리킨다.
    PlannerActionKind.remind => true,
    _ => target.isNotEmpty,
  };
}

/// 조작을 시도한 결과.
enum PlannerActionStatus {
  /// 할 수 있다(미리보기) 또는 했다(실행).
  ok,

  /// 그런 이름이 없다.
  notFound,

  /// 같은 이름이 여럿이라 하나를 고를 수 없다.
  multiple,

  /// 이미 그렇게 되어 있다.
  noChange,

  /// 찾긴 했는데 바꾸지 못했다.
  failed,

  /// 루틴이라 여기서 고칠 것이 아니다. 루틴 탭으로 데려간다.
  ///
  /// 루틴은 시각 하나만 있는 것이 아니라 요일·주 몇 회·수량이 함께 걸려 있다.
  /// 한 조각만 태그로 고치면 나머지와 어긋나고, 무엇보다 오늘치만 바뀌었는지
  /// 앞으로 계속 바뀌었는지 사용자가 알 수 없다.
  routine,
}

class PlannerActionResult {
  const PlannerActionResult(
    this.status, {
    this.label = '',
    this.detail = '',
    this.id = '',
  });

  final PlannerActionStatus status;

  /// 실제로 찾은 일정의 이름. 코치가 짚어준 이름과 다를 수 있다.
  final String label;

  /// 찾은 항목의 id. 완료로 표시할 때 이걸로 다시 찾는다.
  ///
  /// 이름으로 두 번 찾지 않는다. 확인 카드를 띄우고 사용자가 누르기까지 사이에
  /// 목록이 바뀔 수 있고, 같은 이름이 하나 더 생기면 엉뚱한 것이 체크된다.
  final String id;

  /// 사람에게 보여줄 값. "오후 8시", "내일(8월 22일)" 같은 것.
  final String detail;

  bool get isOk => status == PlannerActionStatus.ok;
}
