import 'package:flutter/foundation.dart';

/// 코치가 태그에 적어 보낸 반복 규칙을 읽는다.
///
/// 형식은 `[HABIT: 이름|반복]`이다. 앞은 루틴 이름, 뒤는 얼마나 자주 할지다.
///
/// 예전에는 코치가 사용자 말을 그대로 넘기고 앱이 정규식으로 풀었다. 그래서
/// "매주 월수금"은 읽었지만 **"평일만"은 못 읽었다** — 정규식에 없는 말은
/// 그냥 매일이 됐고, 사용자는 평일만 하겠다고 말해놓고 주말에도 뜨는 루틴을
/// 받았다. 사람이 반복을 말하는 방법은 정규식으로 다 적을 수 없다.
///
/// 그 몫을 코치에게 넘긴다. 코치는 "평일만", "주말에만", "격일로", "가능하면
/// 자주" 같은 말을 여기 적힌 몇 가지 중 하나로 옮기기만 하면 된다.
class RoutineFrequency {
  const RoutineFrequency._({
    required this.freq,
    this.days = const [],
    this.weeklyTargetCount,
  });

  /// 'daily' | 'weekly' | 'weekly_count'. 저장소가 쓰는 값 그대로다.
  final String freq;

  /// 0=월 ~ 6=일. freq가 'weekly'일 때만 채워진다.
  final List<int> days;

  /// 주 몇 회. freq가 'weekly_count'일 때만 채워진다.
  final int? weeklyTargetCount;

  static const RoutineFrequency everyday = RoutineFrequency._(freq: 'daily');

  static const Map<String, int> _dayIndexByName = {
    '월': 0,
    '화': 1,
    '수': 2,
    '목': 3,
    '금': 4,
    '토': 5,
    '일': 6,
  };

  /// 코치가 적어 보낸 말. 못 읽으면 null — 그때는 예전 정규식이 맡는다.
  ///
  /// 사람이 쓰는 말도 조금은 받아준다. 코치가 형식을 늘 지킨다는 보장이 없고,
  /// 한 글자 틀렸다고 매일로 떨어뜨리면 사용자가 말한 것과 달라진다.
  static RoutineFrequency? parse(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final squeezed = text.replaceAll(RegExp(r'\s+'), '');

    if (RegExp(r'^(매일|daily|날마다|하루에한번)$').hasMatch(squeezed)) {
      return everyday;
    }
    if (RegExp(r'^(평일|주중|weekdays?)(만|에만)?$').hasMatch(squeezed)) {
      return const RoutineFrequency._(freq: 'weekly', days: [0, 1, 2, 3, 4]);
    }
    if (RegExp(r'^(주말|weekends?)(만|에만)?$').hasMatch(squeezed)) {
      return const RoutineFrequency._(freq: 'weekly', days: [5, 6]);
    }

    // 주 n회. "주3회", "주 3일", "일주일에 3번"
    final countMatch = RegExp(
      r'^(?:주|일주일에|한주에)([1-7])(?:회|번|일|날)?$',
    ).firstMatch(squeezed);
    if (countMatch != null) {
      final count = int.parse(countMatch.group(1)!);
      // 이레를 다 채우면 매일과 같다. 굳이 주 7회로 두면 화면이 매주 목표를
      // 세는데, 그건 매일 하는 사람에게 없어도 되는 계산이다.
      if (count >= 7) return everyday;
      return RoutineFrequency._(freq: 'weekly_count', weeklyTargetCount: count);
    }

    // 요일 나열. "월,수,금" "월수금" "화·목"
    final days = _parseDays(squeezed);
    if (days != null) {
      if (days.length >= 7) return everyday;
      return RoutineFrequency._(freq: 'weekly', days: days);
    }
    return null;
  }

  static List<int>? _parseDays(String squeezed) {
    // 요일 글자와 이음말만으로 이루어졌을 때만 요일 나열로 본다. 그러지 않으면
    // '일기'의 '일'이나 '수영'의 '수'를 요일로 읽는다.
    if (!RegExp(r'^[월화수목금토일요,·/및과와랑하고]+$').hasMatch(squeezed)) {
      return null;
    }
    final days = <int>{};
    for (final match in RegExp(r'[월화수목금토일]').allMatches(squeezed)) {
      // '요일'의 '일'은 요일 이름이 아니다.
      final index = match.start;
      if (match.group(0) == '일' &&
          index > 0 &&
          squeezed[index - 1] == '요') {
        continue;
      }
      final day = _dayIndexByName[match.group(0)];
      if (day != null) days.add(day);
    }
    if (days.isEmpty) return null;
    final sorted = days.toList()..sort();
    return sorted;
  }

  @override
  String toString() =>
      'RoutineFrequency($freq, days: $days, weekly: $weeklyTargetCount)';
}
