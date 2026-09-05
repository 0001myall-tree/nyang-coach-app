/// 반복 일정이 언제까지인지. 코치가 태그에 적어 보낸 것을 읽는다.
///
/// 형식은 `[SCHEDULE: 매주 화금 오후 7시 학원|~2026-10-31]`이다.
///
/// 앱은 "10월 말까지"나 "이번 학기까지"를 날짜로 바꿀 수 없다. 반대로 코치는
/// 그걸 잘한다. 그래서 옮기는 일은 코치가 하고 여기서는 받아 적기만 한다.
///
/// 이 값이 없으면 반복은 끝나지 않는다 — 1년치가 통째로 들어가고, 학원이 끝난
/// 뒤로도 화·금마다 계속 뜬다.
library;

class ScheduleRepeatEnd {
  const ScheduleRepeatEnd._();

  /// 종료일을 뜻하는 조각인지. `~`로 시작하거나 `까지`로 끝난다.
  static bool looksLikeEnd(String piece) {
    final text = piece.trim();
    if (text.isEmpty) return false;
    return text.startsWith('~') ||
        text.startsWith('until') ||
        text.endsWith('까지');
  }

  /// 마지막 날. 못 읽으면 null.
  ///
  /// [today]보다 앞선 날은 받지 않는다. 이미 지난 날까지 반복하라는 말은
  /// 하루도 만들지 말라는 뜻이 되는데, 그건 등록을 부탁한 사람이 바란 것이
  /// 아니다.
  static DateTime? parse(String? raw, {required DateTime today}) {
    var text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    text = text
        .replaceFirst(RegExp(r'^~+'), '')
        .replaceFirst(RegExp(r'^until\s*:?\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'까지$'), '')
        .trim();
    if (text.isEmpty) return null;

    final match = RegExp(
      r'^(\d{4})[-./](\d{1,2})[-./](\d{1,2})$',
    ).firstMatch(text);
    if (match == null) return null;

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final parsed = DateTime(year, month, day);
    // 2월 31일 같은 날은 3월로 넘어간다. 코치가 잘못 적은 것이니 안 받는다.
    if (parsed.month != month || parsed.day != day) return null;

    final floor = DateTime(today.year, today.month, today.day);
    if (parsed.isBefore(floor)) return null;
    return parsed;
  }

  /// 사람에게 보여줄 말. `10월 31일까지`.
  static String label(DateTime date) => '${date.month}월 ${date.day}일까지';
}
