import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// 매일 루틴이 너무 많아 매일 다 못 채우는 상태인지 본다.
///
/// 매일 루틴이 다섯이면 매일 다섯 개가 뜨고, 셋만 하면 매일 두 개를 못 한
/// 날이 된다. 총량이 문제가 아니라 하루에 다 얹혀 있는 것이 문제다. 요일로
/// 나누면 같은 양을 하면서도 채운 날이 생긴다.
///
/// 판정은 여기서, 문장은 코치가 만든다. 어느 루틴을 나눠도 되는지는 코드로
/// 가를 수 없어서다 — 영양제는 매일이어야 하고 운동은 나눠도 된다는 판단은
/// 이름을 읽어야 나온다. 대신 후보를 좁혀서 넘긴다. 코치에게 전부 맡기면
/// 볼 것이 없는 날에도 뭔가를 만들어낸다.
class RoutineSpreadAnalysis {
  const RoutineSpreadAnalysis._();

  /// 이만큼 있어야 나눌 거리가 된다.
  ///
  /// 둘셋이면 나눠봐야 하루에 하나씩이라 나눈 티가 안 나고, 오히려 하던 것을
  /// 줄이라는 말로 들린다.
  static const int minDailyRoutines = 5;

  /// 루틴을 새로 만들어달라고 한 자리에서 짚기 시작하는 개수.
  ///
  /// 금요일 제안보다 하나 높다. 그쪽은 못 하고 있는 것이 이미 보인 뒤라 문턱이
  /// 낮아도 되지만, 이쪽은 아직 아무 실패도 없는데 미리 묻는 자리다. 물 마시기·
  /// 영양제·스트레칭처럼 정말 매일이어야 하는 것만으로도 대여섯은 쉽게 차서,
  /// 너무 이르게 물으면 멀쩡한 습관을 말리는 말이 된다.
  static const int askAtRegistrationFrom = 6;

  /// 최근 평일 이만큼을 본다.
  ///
  /// 주말은 세지 않는다. 주말에는 플래너를 잘 안 보고, 그러면 완료 표시도 안
  /// 남는다. 그대로 세면 토·일 이틀이 자동으로 "안 한 날"이 되어 매주 거의
  /// 모든 루틴이 후보로 올라온다.
  static const int windowDays = 5;

  /// 이만큼 못 한 루틴만 후보로 올린다. (평일 닷새 중 사흘 이상)
  static const int minMissedDays = 3;

  /// 이 요일에만 묻는다. (1=월 ~ 7=일, 금요일)
  ///
  /// 정해봐야 주말에는 안 보니까, 금요일에 정해두면 월요일부터 새 배치로
  /// 시작한다. 아무 때나 튀어나오지 않는다는 뜻이기도 하다.
  static const int askWeekday = DateTime.friday;

  /// 오늘 물어도 되는 날인지.
  static bool isAskDay(DateTime now) => now.weekday == askWeekday;

  /// 후보를 몇 개까지 넘길지.
  ///
  /// 코치는 이 중에서 한둘을 고른다. 너무 많이 주면 고르는 일이 되고, 그러면
  /// 사용자가 받는 제안도 여러 갈래가 된다.
  static const int maxCandidates = 4;

  static String _dateKey(DateTime date) =>
      DateFormat('yyyy-MM-dd').format(date);

  /// 오늘 이전의 평일 [windowDays]일. 가까운 날부터.
  ///
  /// 오늘은 넣지 않는다. 아직 안 끝난 하루를 "못 한 날"로 세면 금요일 아침에
  /// 금요일이 이미 실패한 것이 된다.
  @visibleForTesting
  static List<String> recentWeekdays(DateTime now) {
    final days = <String>[];
    var cursor = DateTime(now.year, now.month, now.day);
    // 아무리 주말이 끼어도 열흘이면 평일 닷새를 채운다. 무한 반복을 막는 한도다.
    for (var step = 0; step < 20 && days.length < windowDays; step++) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (cursor.weekday == DateTime.saturday ||
          cursor.weekday == DateTime.sunday) {
        continue;
      }
      days.add(_dateKey(cursor));
    }
    return days;
  }

  /// 매일 루틴 중 요즘 자주 비는 것들. 조건에 못 미치면 빈 목록.
  static List<RoutineSpreadCandidate> candidates({
    required String? habitsRaw,
    required String? habitLogsRaw,
    required DateTime now,
  }) {
    final habits = _decodeList(habitsRaw);
    final logs = _decodeMap(habitLogsRaw);

    final daily = <Map<String, dynamic>>[];
    for (final item in habits) {
      if (item is! Map) continue;
      final habit = Map<String, dynamic>.from(item);
      if ((habit['freq']?.toString() ?? 'daily') != 'daily') continue;
      daily.add(habit);
    }
    if (daily.length < minDailyRoutines) return const [];

    final found = <RoutineSpreadCandidate>[];
    for (final habit in daily) {
      final id = habit['id']?.toString() ?? '';
      final name = habit['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;

      // 만든 지 얼마 안 된 루틴은 못 한 날을 셀 자리가 아직 없다. 시작하자마자
      // "요즘 뜸하네요"를 듣게 된다. 주말을 건너뛰고 세는 창만큼은 지나야 한다.
      final createdAt = DateTime.tryParse(habit['createdAt']?.toString() ?? '');
      if (createdAt != null && now.difference(createdAt).inDays < 7) {
        continue;
      }

      final forHabit = logs[id];
      var missed = 0;
      for (final day in recentWeekdays(now)) {
        final log = forHabit is Map ? forHabit[day] : null;
        final done = log is Map && log['done'] == true;
        if (!done) missed += 1;
      }
      if (missed < minMissedDays) continue;

      found.add(
        RoutineSpreadCandidate(
          habitId: id,
          name: name,
          missedDays: missed,
          doneDays: windowDays - missed,
        ),
      );
    }

    // 많이 빈 것부터. 코치가 앞의 것을 먼저 본다.
    found.sort((a, b) => b.missedDays.compareTo(a.missedDays));
    if (found.length > maxCandidates) {
      return found.sublist(0, maxCandidates);
    }
    return found;
  }

  /// 코치에게 넘길 재료. 후보가 없으면 빈 문자열.
  static String promptBlock({
    required List<RoutineSpreadCandidate> candidates,
    required int dailyRoutineCount,
  }) {
    if (candidates.isEmpty) return '';
    final lines = candidates
        .map(
          (c) =>
              '- ${c.name} (최근 평일 ${windowDays}일 중 ${c.doneDays}일 함, ${c.missedDays}일 비었음)',
        )
        .join('\n');
    return '[매일 루틴 $dailyRoutineCount개 중 요즘 자주 비는 것]\n$lines\n';
  }

  /// 매일 루틴 전부와 최근 현황. 코치가 무엇을 나눌지 고르는 재료다.
  ///
  /// [promptBlock]과 달리 자주 비는 것만 주지 않는다. 매일 유지할 것과 나눌
  /// 것을 갈라야 하는 자리라, 잘 지키고 있는 루틴도 보여야 "이건 그대로 두자"고
  /// 말할 수 있다. 빈 것만 주면 목록 전체가 문제처럼 보인다.
  ///
  /// 만든 지 얼마 안 된 것은 표시해서 넘긴다. 아직 못 한 날을 셀 자리가 없는데
  /// 숫자만 보면 제일 심하게 비는 루틴으로 보인다.
  static String allDailyRoutinesBlock({
    required String? habitsRaw,
    required String? habitLogsRaw,
    required DateTime now,
  }) {
    final logs = _decodeMap(habitLogsRaw);
    final days = recentWeekdays(now);

    final lines = <String>[];
    for (final item in _decodeList(habitsRaw)) {
      if (item is! Map) continue;
      final habit = Map<String, dynamic>.from(item);
      if ((habit['freq']?.toString() ?? 'daily') != 'daily') continue;
      final id = habit['id']?.toString() ?? '';
      final name = habit['name']?.toString().trim() ?? '';
      if (id.isEmpty || name.isEmpty) continue;

      final forHabit = logs[id];
      var done = 0;
      for (final day in days) {
        final log = forHabit is Map ? forHabit[day] : null;
        if (log is Map && log['done'] == true) done += 1;
      }

      final createdAt = DateTime.tryParse(habit['createdAt']?.toString() ?? '');
      final isNew = createdAt != null && now.difference(createdAt).inDays < 7;
      final timeStart = habit['timeStart']?.toString();
      final timeInfo = (timeStart == null || timeStart.isEmpty)
          ? ''
          : ', $timeStart';
      lines.add(
        '- $name (${days.length}일 중 $done일 함$timeInfo)'
        '${isNew ? ' *만든 지 일주일이 안 됨' : ''}',
      );
    }

    if (lines.isEmpty) return '';
    return '[매일 하는 루틴 ${lines.length}개 — 최근 평일 ${days.length}일]\n'
        '${lines.join('\n')}\n';
  }

  static List<dynamic> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// 매일 설정인 루틴이 몇 개인지.
  static int dailyRoutineCount(String? habitsRaw) {
    var count = 0;
    for (final item in _decodeList(habitsRaw)) {
      if (item is! Map) continue;
      if ((item['freq']?.toString() ?? 'daily') == 'daily') count += 1;
    }
    return count;
  }
}

@immutable
class RoutineSpreadCandidate {
  const RoutineSpreadCandidate({
    required this.habitId,
    required this.name,
    required this.missedDays,
    required this.doneDays,
  });

  final String habitId;
  final String name;
  final int missedDays;
  final int doneDays;
}
