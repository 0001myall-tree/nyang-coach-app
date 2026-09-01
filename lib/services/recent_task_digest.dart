/// 최근에 적은 것들을 이름별로 묶어 센다.
///
/// 담당 영역이 있는 코치를 위한 자리다. 그 코치들이 알아야 하는 것은 이 사람의
/// 전체 실행률이 아니라 **자기 영역이 요즘 어떻게 되고 있는가**다. 햇살 코치는
/// 씻고 챙기는 것이, 할매 코치는 살림이, 형 코치는 몸 쓰는 일이 어디까지
/// 가는지를 알아야 자리를 잡아줄 수 있다.
///
/// 그런데 어느 항목이 어느 영역인지는 앱이 모른다. 이름을 미리 갈라 저장해
/// 두는 방법도 있었는데, 사람은 같은 일을 매번 조금씩 다르게 적어서 저장해둔
/// 이름과 자꾸 어긋난다. 그리고 새로 쓴 이름은 다음 분류까지 안 잡혀서, 막
/// 시작한 사람의 첫 달이 통째로 비어 보인다.
///
/// 그래서 가르지 않는다. 목록을 통째로 주고 코치가 자기 영역 것만 고른다.
/// 고르는 일은 뜻을 보는 일이라 코치가 잘하고, 세는 일은 앱이 한다 — 목록을
/// 눈으로 세면 "세 개라면"처럼 되받는 답이 나온다.
library;

import 'dart:convert';

/// 이름 하나가 최근에 어떻게 됐는지.
class TaskTally {
  const TaskTally({
    required this.name,
    required this.planned,
    required this.done,
    required this.startedOnly,
    required this.isRoutine,
    this.usualHour,
  });

  final String name;

  /// 목록에 오른 횟수.
  final int planned;

  /// 그중 끝낸 횟수.
  final int done;

  /// 손은 댔는데 못 끝낸 횟수.
  final int startedOnly;

  final bool isRoutine;

  /// 주로 손대는 시각. 표본이 모자라거나 흩어져 있으면 null.
  final int? usualHour;
}

class RecentTaskDigest {
  const RecentTaskDigest._();

  /// 며칠치를 볼지.
  ///
  /// 이레는 담당 영역 항목이 두세 개뿐일 수 있고, 한 달은 목록이 너무 길어진다.
  static const int windowDays = 14;

  /// 실을 이름 개수. 잦은 것부터 남긴다.
  static const int maxNames = 20;

  /// 시각을 말하려면 손댄 기록이 이만큼은 있어야 한다.
  ///
  /// 한 번 저녁에 했다고 "저녁에 하는 사람"이라고 하면 없는 패턴을 만든다.
  static const int minHourSamples = 2;

  static String promptBlock(String? historyRaw, {DateTime? now}) {
    final tallies = tally(historyRaw, now: now);
    if (tallies.isEmpty) return '';

    final buffer = StringBuffer(
      '\n[최근 $windowDays일에 적은 것 - 이름 / 적은 횟수 / 끝낸 횟수 / 주로 손댄 때]\n',
    );
    for (final item in tallies) {
      final parts = StringBuffer(item.name);
      if (item.isRoutine) parts.write('(루틴)');
      parts.write(' ${item.planned}/${item.done}');
      if (item.startedOnly > 0) parts.write(' 시작만${item.startedOnly}');
      final hour = item.usualHour;
      if (hour != null) parts.write(' ${_clock(hour)}');
      buffer.writeln(parts.toString());
    }
    buffer.writeln(
      '*이 중 네가 맡는 영역의 것만 보고 말하세요. 나머지는 아는 척하지 마세요.',
    );
    buffer.writeln(
      '*"주로 손댄 때"는 시작 표시가 없으면 끝낸 시각으로 대신 봅니다. 그 시간대에 그 일을 한다는 뜻까지만 읽으세요.',
    );
    return buffer.toString();
  }

  /// 이름별 셈. 잦은 것부터.
  static List<TaskTally> tally(String? historyRaw, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final floor = DateTime(at.year, at.month, at.day - windowDays);

    final planned = <String, int>{};
    final done = <String, int>{};
    final touched = <String, int>{};
    final routine = <String>{};
    final hours = <String, List<int>>{};

    for (final record in _decodeList(historyRaw)) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(floor) || day.isAfter(at)) continue;

      for (final task in _asList(record['tasks'])) {
        // 이월 표시는 그날 세운 계획이 아니라 넘어온 것이다.
        if (task['deferred'] == true) continue;
        final name = task['text']?.toString().trim() ?? '';
        if (name.isEmpty) continue;

        planned[name] = (planned[name] ?? 0) + 1;
        if (task['category'] == 'habit' || task['habitId'] != null) {
          routine.add(name);
        }

        final isDone = task['done'] == true;
        final startedAt = DateTime.tryParse(
          task['startedAt']?.toString() ?? '',
        );
        if (isDone) done[name] = (done[name] ?? 0) + 1;
        if (isDone || startedAt != null) {
          touched[name] = (touched[name] ?? 0) + 1;
        }

        // 시작 표시가 없으면 끝낸 시각으로 대신 본다. ▶를 안 누르고 체크만
        // 하는 사람은 이 칸이 늘 비는데, 자리를 잡아주려면 언제 하는지를
        // 알아야 한다.
        final marked =
            startedAt ??
            DateTime.tryParse(task['completedAt']?.toString() ?? '');
        if (marked != null) {
          (hours[name] ??= <int>[]).add(marked.hour);
        }
      }
    }

    final names = planned.keys.toList()
      ..sort((a, b) {
        final byCount = (planned[b] ?? 0).compareTo(planned[a] ?? 0);
        return byCount != 0 ? byCount : a.compareTo(b);
      });

    return [
      for (final name in names.take(maxNames))
        TaskTally(
          name: name,
          planned: planned[name] ?? 0,
          done: done[name] ?? 0,
          startedOnly: (touched[name] ?? 0) - (done[name] ?? 0),
          isRoutine: routine.contains(name),
          usualHour: _usualHour(hours[name]),
        ),
    ];
  }

  /// 주로 손대는 시각. 두 시간짜리 구간으로 묶어 보고, 흩어져 있으면 null.
  static int? _usualHour(List<int>? hours) {
    if (hours == null || hours.length < minHourSamples) return null;
    final counts = <int, int>{};
    for (final hour in hours) {
      final slot = hour - hour % 2;
      counts[slot] = (counts[slot] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    return top.value * 2 >= hours.length ? top.key : null;
  }

  /// "밤 8시"처럼 짧게.
  static String _clock(int hour) {
    final wrapped = hour % 24;
    final prefix = wrapped < 6
        ? '새벽'
        : wrapped < 12
        ? '아침'
        : wrapped < 18
        ? '낮'
        : '밤';
    final h = wrapped % 12 == 0 ? 12 : wrapped % 12;
    return '$prefix$h시';
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
}
