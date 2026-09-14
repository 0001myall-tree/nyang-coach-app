import 'package:flutter/material.dart' show TimeOfDay;

/// 시각은 안 적고 때만 적은 일에 시각을 붙여준다.
///
/// "저녁 글쓰기", "아침 스트레칭"처럼 적는 사람이 많다. 지금까지 이런 일은
/// 시각 없는 일로 들어갔고, 그러면 앱이 챙길 수 있는 것이 거의 없었다 —
/// 시작 알림도 없고, 목록에서 순서도 없고, 낮에 "아직 안 했네" 소리를 저녁
/// 일에도 똑같이 했다.
///
/// **구간의 뒤쪽을 고른다.** 저녁을 6시로 잡으면 8시에 하려던 사람을 두 시간
/// 일찍 찌른다. 반대로 늦게 잡으면 그 사이에 이미 한 사람에게는 알림이 안
/// 가는 정도로 끝난다. 틀리는 방향을 고를 수 있다면 늦는 쪽이 덜 아프다.
///
/// 시각이 적혀 있는 일("7시 약속")은 여기 오지 않는다. 그건 숫자를 읽는
/// 자리가 따로 있고, 거기는 사용자가 적은 숫자를 그대로 쓴다.
class DaypartHint {
  const DaypartHint({required this.word, required this.time});

  /// 글에서 찾은 말. '저녁', '아침' 같은 것.
  final String word;

  /// 그 말에 붙일 시각.
  final TimeOfDay time;

  /// 말과 기본 시각. 순서대로 본다 — 앞의 것이 먼저 걸린다.
  ///
  /// '오전'이 '아침'보다 뒤에 있는 이유는 없다. 겹치는 말이 없어서다.
  static const Map<String, TimeOfDay> _defaults = {
    '새벽': TimeOfDay(hour: 5, minute: 30),
    '아침': TimeOfDay(hour: 9, minute: 0),
    '오전': TimeOfDay(hour: 10, minute: 30),
    '점심': TimeOfDay(hour: 12, minute: 30),
    '낮': TimeOfDay(hour: 14, minute: 0),
    '오후': TimeOfDay(hour: 16, minute: 0),
    '저녁': TimeOfDay(hour: 19, minute: 30),
    '밤': TimeOfDay(hour: 21, minute: 30),
    '자기 전': TimeOfDay(hour: 22, minute: 30),
    '자기전': TimeOfDay(hour: 22, minute: 30),
    '퇴근 후': TimeOfDay(hour: 19, minute: 30),
    '퇴근후': TimeOfDay(hour: 19, minute: 30),
  };

  /// 잠들기 이만큼 전까지는 시작할 수 있어야 한다.
  static const Duration _beforeBed = Duration(hours: 1);

  /// 퇴근하고 이만큼 뒤. 나오자마자 시작하라는 말은 안 된다.
  static const Duration _afterWork = Duration(minutes: 30);

  /// 글에서 때를 읽는다. 없으면 null.
  ///
  /// [bedtime]이 있으면 그보다 늦지 않게 당긴다. [workEnd]가 있으면 저녁·밤
  /// 일은 퇴근 뒤로 민다 — 9시부터 7시까지 일하는 사람에게 저녁 6시는 아직
  /// 회사다.
  static DaypartHint? read(
    String text, {
    TimeOfDay? bedtime,
    TimeOfDay? workEnd,
  }) {
    final found = _findWord(text);
    if (found == null) return null;

    var minutes = _minutes(_defaults[found]!);

    // 퇴근 뒤에 하는 것이 분명한 말만 민다. '아침'을 퇴근 뒤로 밀 수는 없다.
    if (workEnd != null && _afterWorkWords.contains(found)) {
      final after = _minutes(workEnd) + _afterWork.inMinutes;
      if (after > minutes) minutes = after;
    }

    if (bedtime != null) {
      // 자정을 넘겨 자는 사람의 취침 시각은 다음 날 것이다. 그대로 빼면
      // 새벽 2시가 한계선이 돼서, 저녁 일이 새벽 1시로 밀린다.
      final bed = bedtime.hour < 12
          ? _minutes(bedtime) + Duration.minutesPerDay
          : _minutes(bedtime);
      final limit = bed - _beforeBed.inMinutes;
      if (minutes > limit) minutes = limit;
    }

    return DaypartHint(
      word: found,
      time: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
  }

  /// 퇴근 뒤로 미룰 수 있는 말.
  static const Set<String> _afterWorkWords = {
    '저녁',
    '밤',
    '자기 전',
    '자기전',
    '퇴근 후',
    '퇴근후',
  };

  /// 글에 들어 있는 때. 없으면 null.
  ///
  /// 글자만 훑으면 '밤고구마'의 '밤'이 걸린다. 그래서 그 말 뒤에 조사나
  /// 띄어쓰기가 와야 때로 본다 — 사람이 때를 적을 때는 '저녁에', '저녁 '처럼
  /// 쓰지 '저녁글쓰기'라고 붙여 쓰지 않는다.
  static String? _findWord(String text) {
    for (final word in _defaults.keys) {
      final pattern = RegExp('(^|\\s)$word(에|엔|때|쯤|무렵|께)?(\\s|\$)');
      if (pattern.hasMatch(text)) return word;
    }
    return null;
  }

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
}
