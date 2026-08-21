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

  static final RegExp _tag = RegExp(
    r'\[(MOVE|DONE|REMIND|MORNING):\s*([^\]]*)\]',
    caseSensitive: false,
  );

  static final RegExp _date = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
  static final RegExp _time = RegExp(r'(\d{1,2}):(\d{2})');

  /// 답변에서 태그를 찾아낸다. 없으면 null.
  ///
  /// 한 턴에 하나만 받는다. 여러 개가 오면 첫 번째만 쓴다 — 카드가 겹치면
  /// 무엇을 고르는 건지 알기 어렵고, 앞의 조작이 뒤의 대상을 바꿔놓기도 한다.
  static PlannerAction? parse(String reply) {
    final match = _tag.firstMatch(reply);
    if (match == null) return null;

    final kind = switch (match.group(1)!.toUpperCase()) {
      'MOVE' => PlannerActionKind.move,
      'DONE' => PlannerActionKind.done,
      'REMIND' => PlannerActionKind.remind,
      _ => PlannerActionKind.morning,
    };

    final parts = match
        .group(2)!
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
    if (m == null) return null;
    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return (hour: hour, minute: minute);
  }

  static bool? _readSwitch(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(off|끄기|해제)\b|끔').hasMatch(lower)) return false;
    if (RegExp(r'\b(on|켜기|설정)\b|켬').hasMatch(lower)) return true;
    return null;
  }

  /// 이 태그로 실제로 할 수 있는 일이 있는지.
  ///
  /// 코치가 이름만 적고 값을 빠뜨리는 일이 있다. 그대로 카드를 띄우면
  /// "집필을 (으)로 옮길까?" 같은 말이 나온다.
  bool get isUsable => switch (kind) {
    PlannerActionKind.move => target.isNotEmpty && (date != null || time != null),
    PlannerActionKind.done => target.isNotEmpty,
    PlannerActionKind.remind => target.isNotEmpty && enabled != null,
    PlannerActionKind.morning => time != null || enabled == false,
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
}

class PlannerActionResult {
  const PlannerActionResult(this.status, {this.label = '', this.detail = ''});

  final PlannerActionStatus status;

  /// 실제로 찾은 일정의 이름. 코치가 짚어준 이름과 다를 수 있다.
  final String label;

  /// 사람에게 보여줄 값. "오후 8시", "내일(8월 22일)" 같은 것.
  final String detail;

  bool get isOk => status == PlannerActionStatus.ok;
}
