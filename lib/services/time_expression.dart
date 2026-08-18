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

/// 시각 하나. ("오후 3시", "9시 반부터", "7시 30분에")
///
/// 잡는 자리: 1=오전/오후 같은 앞말, 2=시, 3=분.
/// 3이 비어 있어도 매치된 글자에 '반'이 있으면 30분이라는 뜻이다.
const String kSingleTimePattern =
    r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
    '$_timeParticlePattern';

/// 시각에서 시각까지. ("9시부터 10시까지", "오후 2시~4시")
///
/// 잡는 자리: 1~3이 시작(앞말·시·분), 4~6이 끝.
/// 끝에 앞말이 없으면 시작의 앞말을 물려받는다고 본다.
const String kTimeRangePattern =
    r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
    r'\s*(?:부터|에서|-|~)\s*'
    r'((?:오전|아침|오후|저녁|밤)\s*)?(\d{1,2})시(?:\s*(\d{1,2})분|\s*반)?'
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
