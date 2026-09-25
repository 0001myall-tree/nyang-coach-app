/// 한국어 시각 표현을 어디까지 한 덩어리로 볼지 정하는 곳.
///
/// 할 일 카드·일정 등록·루틴 등록이 각자 시각 정규식을 들고 있었고, 셋 다
/// "9시부터"의 '부터'를 시각의 일부로 안 봤다. 그래서 "9시"만 떼어내고 남은
/// 조사가 제목 앞에 붙어 '부터 운동'이 됐다.
///
/// 시각을 어떻게 읽을지는 화면마다 다르다(오전/오후가 없을 때 언제로 미루는지).
/// 하지만 어디까지가 시각이냐는 한 곳에서만 정한다.
library;

/// 시각 뒤에 붙어 시각의 일부로 봐야 하는 말.
///
/// 긴 쪽을 먼저 적는다. 정규식은 먼저 맞는 것을 집기 때문에 '부터'가 앞에
/// 오면 '부터는'의 '는'이 제목에 남는다.
const String _timeParticlePattern =
    r'(?:\s*(?:에서부터|서부터|부터는|부턴|부터|까지|에는|엔|에|쯤|경))?';

/// 시각 앞에 붙어 오전·오후를 정해주는 말. 자리 하나를 잡는다.
///
/// 새벽·낮·점심이 빠져 있어서 "새벽 5시 기상"이 5시만 떼고 '새벽 기상'으로
/// 남았다. 어느 쪽으로 읽는지는 [hourWithDaypart]가 정한다.
const String _daypartPattern = r'((?:오전|아침|새벽|오후|저녁|밤|낮|점심)\s*)?';

/// 앞말로 24시 시각을 정한다. 앞말이 없거나 모르는 말이면 null.
///
/// 밤은 오후가 아니다. "밤 12시"는 자정이고 "밤 1시"는 새벽 1시다 — 오후로
/// 읽던 때는 둘 다 낮 시각이 됐다. 낮·점심은 1시부터 6시까지만 오후다.
/// 13시부터는 이미 24시제라 앞말을 보지 않는다.
int? hourWithDaypart(String prefix, int rawHour) {
  if (rawHour < 1 || rawHour > 24) return null;
  if (prefix.isEmpty) return null;
  if (rawHour >= 13) return rawHour % 24;
  final morning = rawHour % 12;
  switch (prefix) {
    case '오전':
    case '아침':
    case '새벽':
      return morning;
    case '오후':
    case '저녁':
      return morning + 12;
    case '낮':
    case '점심':
      return rawHour <= 6 ? morning + 12 : (rawHour == 12 ? 12 : morning);
    case '밤':
      return rawHour <= 4 || rawHour == 12 ? morning : morning + 12;
  }
  return null;
}

/// 시각 하나. ("오후 3시", "9시 반부터", "7시 30분에")
///
/// 잡는 자리: 1=오전/오후 같은 앞말, 2=시, 3=분.
/// 3이 비어 있어도 매치된 글자에 '반'이 있으면 30분이라는 뜻이다.
const String kSingleTimePattern =
    '$_daypartPattern'
    r'(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
    '$_timeParticlePattern';

/// 시각에서 시각까지. ("9시부터 10시까지", "오후 2시~4시")
///
/// 잡는 자리: 1~3이 시작(앞말·시·분), 4~6이 끝.
/// 끝에 앞말이 없으면 시작의 앞말을 물려받는다고 본다.
const String kTimeRangePattern =
    '$_daypartPattern'
    r'(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
    r'\s*(?:부터|에서|-|~)\s*'
    '$_daypartPattern'
    r'(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
    r'(?:\s*까지)?';

final RegExp kSingleTimeRegex = RegExp(kSingleTimePattern);
final RegExp kTimeRangeRegex = RegExp(kTimeRangePattern);

final RegExp _rangeSeparatorRegex = RegExp(r'\s*(?:부터|에서|-|~)\s*');

/// 잡아낸 시각 표현을 시작 쪽 글자와 끝 쪽 글자로 자른다.
///
/// "9시 반부터 10시까지"에서 '반'은 시작에만 걸린 말이다. 매치된 글자를
/// 통째로 놓고 '반'을 찾으면 끝 시각까지 30분이 붙는다.
/// 범위가 아닌 시각 하나면 양쪽 다 그 글자를 돌려준다.
({String start, String end}) splitTimeRange(String matched) {
  final parts = matched.split(_rangeSeparatorRegex);
  if (parts.length < 2) return (start: matched, end: matched);
  return (start: parts.first, end: parts.sublist(1).join(' '));
}

/// 분을 안 적고 '반'이라고만 한 경우까지 읽는다.
int minuteFrom(String? minuteText, String segment) {
  if (minuteText != null) return int.tryParse(minuteText) ?? 0;
  return segment.contains('반') ? 30 : 0;
}
