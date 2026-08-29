/// 하루를 몇 시에 시작했을 때 그날이 잘 풀렸는지.
///
/// 개별 할 일을 몇 시에 하면 잘 끝내는지를 보는 게 아니다. 그날 **첫 할 일**을
/// 붙잡은 시각과 **그날 전체 완료율**을 짝지어 모은다. 사람마다 하루가 잘
/// 풀리기 시작하는 시간대가 다르고, 그건 할 일 하나하나의 성질과는 별개다.
///
/// 시작 시각은 할 일을 처음 눌렀을 때 기록된다. 한 번 누르면 진행 중, 다시
/// 누르면 완료라서, 끝낸 일에는 대체로 시작 시각이 남아 있다.
///
/// 표시는 쌓인 날 수에 따라 세 단계로 나눈다. 이틀치로 "당신의 패턴은
/// 이렇습니다"라고 단정하면, 우연히 늦게 시작한 이틀 때문에 사용자가 자기
/// 리듬을 잘못 배운다. 그래서 3일부터 조심스럽게 말하고, 7일부터 단정한다.
library;

/// 두 시간짜리 시작 구간.
class StartWindow {
  const StartWindow(this.startHour);

  /// 0, 2, 4 … 22.
  final int startHour;

  int get endHour => startHour + 2;

  /// "오전 8시~10시" 같은 표시용 이름.
  ///
  /// 앞머리(새벽/오전/오후)는 시작 시각만 보고 붙인다. 끝 시각까지 따로
  /// 붙이면 "오전 10시~오후 12시"처럼 읽기 나쁜 말이 된다.
  String get label {
    final prefix = startHour < 6
        ? '새벽'
        : startHour < 12
        ? '오전'
        : '오후';
    return '$prefix ${_hour12(startHour)}시~${_hour12(endHour)}시';
  }

  static int _hour12(int hour) {
    final wrapped = hour % 24;
    if (wrapped == 0) return hour == 0 ? 0 : 12;
    return wrapped > 12 ? wrapped - 12 : wrapped;
  }

  @override
  bool operator ==(Object other) =>
      other is StartWindow && other.startHour == startHour;

  @override
  int get hashCode => startHour.hashCode;

  @override
  String toString() => 'StartWindow($label)';
}

/// 얼마나 확신을 갖고 말할 수 있는지.
enum StartPatternConfidence {
  /// 아직 못 보여준다.
  notEnough,

  /// 보여주되 단정하지 않는다.
  emerging,

  /// 패턴이라고 불러도 되는 만큼 쌓였다.
  established,
}

class StartPatternResult {
  const StartPatternResult({
    required this.confidence,
    required this.dayCount,
    this.window,
    this.completionPercent = 0,
  });

  static const StartPatternResult empty = StartPatternResult(
    confidence: StartPatternConfidence.notEnough,
    dayCount: 0,
  );

  final StartPatternConfidence confidence;

  /// 계산에 쓸 수 있었던 날 수. 할 일 3개가 아니라 유효한 날짜 3일이 기준이다.
  final int dayCount;

  /// 완료율이 가장 높았던 구간. [confidence]가 notEnough면 null.
  final StartWindow? window;

  /// 그 구간에 시작한 날들의 평균 완료율.
  final int completionPercent;

  bool get hasResult => window != null;
}

/// 하루치 계산 결과. 화면과 무관하게 기록만 보고 만든다.
class _DayStart {
  const _DayStart(this.startHour, this.completionRate);
  final int startHour;
  final double completionRate;
}

class StartPatternService {
  const StartPatternService._();

  /// 이 날수부터 조심스럽게 보여준다.
  static const int minDaysToShow = 3;

  /// 이 날수부터 "패턴"이라고 부른다.
  static const int minDaysToTrust = 7;

  /// 이 날짜 앞의 기록은 이 계산에 쓸 수 없다.
  ///
  /// 그전에는 습관에만 시작 시각을 남겼다. 일반 할 일은 눌러도 시각이 안
  /// 남아서, 하루 중 가장 이른 시작을 찾으면 언제나 습관 시각이 나왔다.
  /// 아침부터 일한 날도 밤에 한 운동이 "하루의 시작"으로 잡혔다는 뜻이다.
  ///
  /// 모든 할 일이 시각을 남기기 시작한 건 2026-08-08 배포부터이고, 기록에
  /// 실제로 찍히기 시작한 첫날이 8월 9일이다. 그 앞은 세지 않는다. 데이터가
  /// 늦게 쌓이더라도 없는 패턴을 지어내는 것보단 낫다.
  static const String firstReliableDate = '2026-08-09';

  /// [records]는 nyang_history의 하루 기록들이다.
  static StartPatternResult analyze(List<Map<String, dynamic>> records) {
    final days = <_DayStart>[];
    for (final record in records) {
      final date = (record['date'] ?? '').toString();
      // 날짜 문자열이 YYYY-MM-DD라 사전순 비교가 곧 시간순 비교다.
      if (date.isEmpty || date.compareTo(firstReliableDate) < 0) continue;
      final day = _readDay(record);
      if (day != null) days.add(day);
    }

    if (days.length < minDaysToShow) {
      return StartPatternResult(
        confidence: StartPatternConfidence.notEnough,
        dayCount: days.length,
      );
    }

    // 구간별로 모아 평균을 낸다.
    final byWindow = <int, List<double>>{};
    for (final day in days) {
      final windowStart = day.startHour - (day.startHour % 2);
      byWindow.putIfAbsent(windowStart, () => []).add(day.completionRate);
    }

    int? bestHour;
    var bestAverage = 0.0;
    var bestSampleCount = 0;
    for (final entry in byWindow.entries) {
      final average = entry.value.reduce((a, b) => a + b) / entry.value.length;
      final sampleCount = entry.value.length;
      // 평균이 같으면 더 여러 날 그랬던 구간을, 그것도 같으면 이른 쪽을 고른다.
      final better =
          bestHour == null ||
          average > bestAverage ||
          (average == bestAverage &&
              (sampleCount > bestSampleCount ||
                  (sampleCount == bestSampleCount && entry.key < bestHour)));
      if (better) {
        bestHour = entry.key;
        bestAverage = average;
        bestSampleCount = sampleCount;
      }
    }

    if (bestHour == null) return StartPatternResult.empty;

    return StartPatternResult(
      confidence: days.length >= minDaysToTrust
          ? StartPatternConfidence.established
          : StartPatternConfidence.emerging,
      dayCount: days.length,
      window: StartWindow(bestHour),
      completionPercent: (bestAverage * 100).round(),
    );
  }

  /// 하루 기록에서 첫 시작 시각과 완료율을 뽑는다. 둘 중 하나라도 없으면 null.
  static _DayStart? _readDay(Map<String, dynamic> record) {
    // 휴식 모드인 날은 완료율로 사람을 평가하면 안 되는 날이다.

    final tasks = (record['tasks'] as List?) ?? const [];
    final counted = tasks
        .whereType<Map>()
        .where((task) => task['deferred'] != true)
        .toList();
    if (counted.isEmpty) return null;

    int? earliestMinutes;
    for (final task in counted) {
      final startedAt = DateTime.tryParse((task['startedAt'] ?? '').toString());
      if (startedAt == null) continue;
      // 날짜를 빼고 하루 안에서의 시각만 본다. 날짜까지 넣어 비교하면 하루
      // 리셋 전에 찍힌 새벽 기록이 언제나 가장 이른 시각이 된다.
      final minutes = startedAt.hour * 60 + startedAt.minute;
      if (earliestMinutes == null || minutes < earliestMinutes) {
        earliestMinutes = minutes;
      }
    }
    if (earliestMinutes == null) return null;

    final done = counted.where((task) => task['done'] == true).length;
    return _DayStart(earliestMinutes ~/ 60, done / counted.length);
  }
}
