/// 담당 영역의 루틴을 이 사람의 하루 어디에 둘지, 앱이 기록에서 계산한다.
///
/// 판정을 코치에게 맡기지 않는 이유가 있다. "잘 되고 있으면 개입하지 마세요"를
/// 문장으로 시키면 매번 무언가를 제안한다. 이 앱이 여러 번 겪은 일이라, 개입할지
/// 말지는 앱이 정하고 코치는 정해진 판정에 맞는 말만 한다.
///
/// 다섯 갈래뿐이다.
/// - [LifeVerdict.hold]: 아무 말도 하지 않는다. 잘 되고 있거나, 담당이 아니거나,
///   하루가 이미 빡빡하거나, 아직 셀 것이 모자라거나.
/// - [LifeVerdict.move]: 되는 요일이 따로 있다. 그 자리로 옮긴다.
/// - [LifeVerdict.reduce]: 잡은 횟수가 실제로 되는 횟수보다 많다. 내린다.
///
/// 이 둘은 이미 있는 루틴을 건드리는 것이라 문턱이 높다. 루틴은 한 번 넣으면
/// 거의 고정으로 두는 것인데, 어지간한 것마다 옮겨라 줄여라 하면 도와주는 게
/// 아니라 참견이 된다. 실제로 안 굴러가는 것만 짚는다.
/// - [LifeVerdict.today]: 오늘 하루 안에서 하나. 반복 약속을 걸지 않는다.
/// - [LifeVerdict.add]: 루틴으로 굳힌다. 반복이 이 사람 도구일 때만.
///
/// 루틴만 다루지 않는다. 루틴은 앞으로 계속 하겠다는 약속이라 무겁고, 필요할
/// 때만 하고 싶다는 사람에게 권하면 안 지킬 것을 하나 더 떠안기는 셈이 된다.
/// 그런 사람에게는 오늘 하루 안에서 할 것 하나를 짚는다.
///
/// 기본값은 [LifeVerdict.hold]다. 셀 것이 모자라면 아무것도 하지 않는다 —
/// 근거 없이 권하는 것보다 조용한 편이 낫다.
library;

import 'dart:convert';

/// 이번 주기에 무엇을 할지.
enum LifeVerdict { hold, move, reduce, today, add }

/// 요일 하나와 두 시간짜리 구간.
///
/// 요일은 0=월 … 6=일. 루틴이 요일을 그렇게 세고 있어서 맞춰 쓴다.
class OpenWindow {
  const OpenWindow({
    required this.weekday,
    required this.startHour,
    required this.evidence,
  });

  final int weekday;
  final int startHour;

  /// 이 구간에서 실제로 무언가를 시작한 날 수. 근거가 될 만한지를 이걸로 본다.
  final int evidence;

  static const List<String> weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  String get label {
    final prefix = startHour < 12 ? '오전' : '오후';
    final h = startHour % 12 == 0 ? 12 : startHour % 12;
    final endHour = startHour + 2;
    final eh = endHour % 12 == 0 ? 12 : endHour % 12;
    return '${weekdayNames[weekday]}요일 $prefix $h~$eh시';
  }

  @override
  String toString() => 'OpenWindow($label, evidence: $evidence)';
}

/// 목표한 요일과 실제로 되는 요일이 어긋난 루틴.
class WeakSpot {
  const WeakSpot({
    required this.habitId,
    required this.name,
    required this.rate,
    required this.workingDays,
    required this.targetDays,
  });

  final String habitId;
  final String name;

  /// 이 창 안에서의 성공 비율.
  final double rate;

  /// 실제로 해내고 있는 요일.
  final List<int> workingDays;

  /// 루틴에 잡혀 있는 요일. 주 n회처럼 요일이 없으면 빈 목록.
  final List<int> targetDays;
}

class LifeRoutinePlan {
  const LifeRoutinePlan({
    required this.verdict,
    this.reason = '',
    this.target,
    this.openWindows = const [],
  });

  static const LifeRoutinePlan quiet = LifeRoutinePlan(
    verdict: LifeVerdict.hold,
  );

  final LifeVerdict verdict;

  /// 왜 그렇게 정했는지. 코치에게 그대로 넘긴다.
  final String reason;

  /// 옮기거나 줄일 대상. [LifeVerdict.add]와 [LifeVerdict.hold]에는 없다.
  final WeakSpot? target;

  /// 넣을 만한 자리. 근거가 많은 순서.
  final List<OpenWindow> openWindows;

  bool get speaks => verdict != LifeVerdict.hold;

  /// 코치에게 넘길 묶음. 말을 걸 자리가 아니면 빈 문자열.
  ///
  /// 판정과 근거만 준다. 무엇을 말할지까지 적어두면 같은 문장이 반복되고,
  /// 판단을 통째로 맡기면 볼 것이 없는 날에도 뭔가를 만들어낸다.
  String promptBlock() {
    if (!speaks) return '';
    final buffer = StringBuffer('\n[담당 영역 루틴 - 앱이 최근 30일 기록에서 낸 판단]\n');
    buffer.writeln('- $reason');

    switch (verdict) {
      case LifeVerdict.move:
        buffer.writeln(
          '*할 일: 되고 있는 요일로 옮기자고 하나만 권하세요. 못 지킨 날을 짚지 말고, 되는 자리가 따로 있더라는 이야기로 하세요.',
        );
      case LifeVerdict.reduce:
        buffer.writeln(
          '*할 일: 횟수나 분량을 실제로 되는 만큼으로 내리자고 권하세요. 의지가 아니라 양이 많았던 것이라고 짚고, 줄이는 것이 후퇴가 아니라는 것이 전해지게 하세요.',
        );
      case LifeVerdict.add:
        final where = openWindows.isEmpty
            ? ''
            : ' 넣을 자리 후보: ${openWindows.take(2).map((w) => w.label).join(', ')}.';
        buffer.writeln(
          '*할 일: 이 영역에서 반복으로 굳힐 것 하나만, 요일과 시각과 크기까지 정해서 권하세요. 여러 개를 늘어놓지 마세요.$where',
        );
      case LifeVerdict.today:
        final when = openWindows.isEmpty
            ? ''
            : ' 이 사람이 실제로 손대는 시간대: ${openWindows.take(2).map((w) => w.label).join(', ')}.';
        buffer.writeln(
          '*할 일: 오늘 하루 안에서 할 것 하나만, 언제 얼마나 할지까지 정해서 권하세요.$when',
        );
        buffer.writeln(
          '*루틴으로 만들자고 하지 마세요. 앞으로 계속 하겠다는 약속은 이 사람이 원한다고 하지 않았습니다. 오늘 한 번이면 됩니다.',
        );
        buffer.writeln(
          '*이미 하는 일에 붙이는 것도 방법입니다. 새 자리를 만드는 것보다 잊을 일이 적습니다. (예: 샤워 직후, 저녁 먹고 바로)',
        );
      case LifeVerdict.hold:
        break;
    }

    buffer.writeln('*이 판단은 앱이 기록을 세어 낸 것입니다. 여기 없는 것은 세지 않았습니다.');
    return buffer.toString();
  }
}

class LifeRoutineAnalysis {
  const LifeRoutineAnalysis._();

  /// 며칠을 보고 정할지.
  static const int windowDays = 30;

  /// 이만큼은 기록이 쌓여야 판정한다. 며칠치로 "당신은 이런 사람"이라고 하면
  /// 우연히 어긋난 며칠이 그 사람의 리듬이 된다.
  static const int minRecordedDays = 10;

  /// 이만큼 해내고 있으면 잘 되는 중이다.
  static const double keepingWellRate = 0.7;

  /// 이 아래로 떨어져야 루틴을 건드린다.
  ///
  /// 루틴은 한 번 넣으면 거의 고정으로 두는 것이다. 그런데 70%를 기준으로
  /// 삼았더니 65%짜리에도 "옮기자"가 나갔다. 그건 도와주는 게 아니라 참견이다.
  /// 웬만하면 굴러가는 것은 그대로 두고, 실제로 안 굴러가는 것만 짚는다.
  ///
  /// 그 사이(40~70%)에는 아무 말도 안 한다. 새로 넣자고도 하지 않는다 —
  /// 반쯤 굴러가는 것을 둔 채 하나를 더 얹는 것도 참견이다.
  ///
  /// 이 구간이 조용한 이유는 반드시 판정에 적는다. 예전에 문턱 둘 사이에 낀
  /// 사람이 엉뚱한 이유("넣을 시간대를 못 찾음")를 달고 조용해진 적이 있다.
  static const double brokenRate = 0.4;

  /// 루틴을 판정하기 전에 이만큼은 지나야 한다.
  ///
  /// 지난주에 만든 루틴을 두고 "안 되고 있으니 옮기자"고 하면, 자리를 잡을
  /// 시간을 준 적이 없는 셈이다.
  static const Duration minRoutineAge = Duration(days: 21);

  /// 그 요일에 이만큼은 기회가 있어야 "되는 요일"이라고 말할 수 있다.
  static const int minChancesPerDay = 2;

  /// 잡은 것의 절반도 못 끝내는 사람에게는 새로 넣지 않는다.
  static const double crowdedDoneRatio = 0.5;

  /// 계획을 이만큼은 적어야 빡빡한지 아닌지를 따질 수 있다.
  static const int crowdedMinPlanPerDay = 3;

  /// 넣을 자리로 내놓으려면 그 구간에서 실제로 시작한 날이 이만큼은 있어야 한다.
  static const int minWindowEvidence = 2;

  /// 루틴이 이만큼 있으면 새 루틴을 권하지 않는다.
  ///
  /// 앞의 판정들은 전부 **담당 영역** 루틴만 센다. 그래서 햇살·할매·형이
  /// 각자 "내 영역엔 굴러가는 게 없네"라고 보고 하나씩 얹으면, 사용자 쪽에는
  /// 아무도 세지 않은 총량이 쌓인다. 매주 하나씩 늘어나는 그림이 여기서 난다.
  ///
  /// 그래서 이 문턱만 담당을 가리지 않고 **전체 루틴**을 센다. 지킬 수 있는
  /// 반복의 개수는 영역별로 따로 있는 것이 아니라 그 사람 하루에 하나뿐이다.
  static const int maxRoutinesForNew = 5;

  /// 담당이 아니라고 답한 경우들.
  ///
  /// 남이 주로 하는 집안일에 제안할 것은 없고, 챙기고 싶은 것이 없다고 한
  /// 사람에게 챙기라고 하는 것은 부탁받지 않은 참견이다.
  static const String _sharedAway = '다른 사람이 주로 해';
  static const String _wantsNothing = '딱히 없어';

  static LifeRoutinePlan analyze({
    String? historyRaw,
    String? habitsRaw,
    String? habitLogsRaw,
    String? schedulesRaw,
    Map<String, dynamic> answers = const {},
    Set<String> domainHabitIds = const {},
    bool? prefersRoutine,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();

    if (_notMyBusiness(answers)) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '이 영역은 사용자가 맡고 있지 않거나 챙기고 싶다고 하지 않았음.',
      );
    }

    final records = _recordsWithin(historyRaw, at);
    if (records.length < minRecordedDays) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '아직 기록이 모자라 판정하지 않음.',
      );
    }

    final habits = _decodeList(habitsRaw)
        .where((h) => domainHabitIds.contains(h['id']?.toString()))
        .toList(growable: false);
    final logs = _decodeMap(habitLogsRaw);

    // 담당 영역 루틴부터 본다. 이미 있는 것을 굴러가게 하는 쪽이 새로 넣는
    // 것보다 늘 먼저다.
    final spots = <WeakSpot>[];
    var keepingWell = false;
    var runningish = false;
    for (final habit in habits) {
      // 만든 지 얼마 안 된 루틴은 판정하지 않는다. 다만 있는 것으로는 치므로
      // 그 사람에게 새 루틴을 얹지도 않는다.
      final createdAt = DateTime.tryParse(habit['createdAt']?.toString() ?? '');
      if (createdAt != null && at.difference(createdAt) < minRoutineAge) {
        runningish = true;
        continue;
      }
      final spot = _measure(habit, logs, records, at);
      if (spot == null) continue;
      if (spot.rate >= keepingWellRate) {
        keepingWell = true;
        continue;
      }
      if (spot.rate >= brokenRate) {
        runningish = true;
        continue;
      }
      spots.add(spot);
    }

    if (spots.isNotEmpty) {
      spots.sort((a, b) => a.rate.compareTo(b.rate));
      final worst = spots.first;
      // 되는 요일이 아예 없으면 자리를 옮겨봐야 소용이 없다. 양이 많은 것이다.
      if (worst.workingDays.isEmpty) {
        return LifeRoutinePlan(
          verdict: LifeVerdict.reduce,
          reason:
              "'${worst.name}'이(가) 30일 중 ${(worst.rate * 100).round()}%만 됨. 되는 요일이 따로 없어 자리를 옮길 곳이 없음.",
          target: worst,
        );
      }
      // 잡아둔 요일보다 실제로 되는 요일이 적으면, 자리가 아니라 횟수 문제다.
      if (worst.targetDays.length > worst.workingDays.length) {
        return LifeRoutinePlan(
          verdict: LifeVerdict.reduce,
          reason:
              "'${worst.name}'은(는) ${_days(worst.targetDays)}로 잡혀 있는데 실제로 되는 날은 ${_days(worst.workingDays)}뿐.",
          target: worst,
        );
      }
      return LifeRoutinePlan(
        verdict: LifeVerdict.move,
        reason:
            "'${worst.name}'이(가) ${_days(worst.workingDays)}에는 되고 있음. 그 자리로 옮기면 붙을 가능성이 큼.",
        target: worst,
      );
    }

    if (keepingWell) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '담당 영역 루틴이 잘 유지되고 있음. 건드릴 것 없음.',
      );
    }

    if (runningish) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '담당 영역 루틴이 완벽하진 않아도 굴러가는 중이거나 아직 자리를 잡는 중. 루틴은 한 번 정하면 두는 것이라 이 정도로는 건드리지 않음.',
      );
    }

    // 여기부터는 담당 영역에 굴러가는 루틴이 없는 사람이다.
    if (_crowded(records)) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '잡아둔 것도 절반을 못 끝내는 중. 새로 넣을 자리가 아님.',
      );
    }

    final windows = openWindows(
      historyRaw: historyRaw,
      habitsRaw: habitsRaw,
      schedulesRaw: schedulesRaw,
      now: at,
    );
    if (windows.isEmpty) {
      return const LifeRoutinePlan(
        verdict: LifeVerdict.hold,
        reason: '넣을 만한 시간대를 아직 찾지 못함.',
      );
    }

    // 이미 지고 있는 반복이 많으면 새 반복을 얹지 않는다. 담당 영역이 비었어도
    // 마찬가지다 — 비어 있는 것은 영역이고, 지키는 것은 사람이다.
    final routineCount = _decodeList(habitsRaw).length;

    // 반복이 이 사람 도구일 때만 루틴으로 권한다. 모르겠으면 가벼운 쪽부터 —
    // 루틴이 맞는 사람이면 오늘 한 번 해본 뒤에 스스로 반복으로 만든다.
    if (prefersRoutine == true && routineCount < maxRoutinesForNew) {
      return LifeRoutinePlan(
        verdict: LifeVerdict.add,
        reason: '담당 영역에 굴러가는 루틴이 없고, 비어 있으면서 실제로 뭔가 하는 시간대가 있음. 반복을 원한다고 답한 사람임.',
        openWindows: windows,
      );
    }
    return LifeRoutinePlan(
      verdict: LifeVerdict.today,
      reason: routineCount >= maxRoutinesForNew
          ? '담당 영역에 굴러가는 루틴은 없지만 이미 지고 있는 루틴이 $routineCount개임. 반복을 더 얹지 말고 오늘 하루 안에서 하나만.'
          : '담당 영역에 굴러가는 루틴이 없음. 반복을 원한다고 하지 않았으므로 오늘 하루 안에서 하나만.',
      openWindows: windows,
    );
  }

  // ── 빈자리 찾기 ───────────────────────────────

  /// 비어 있으면서 실제로 무언가를 시작하는 시간대.
  ///
  /// 비어 있기만 한 시간은 자리가 아니다. 새벽 4시는 늘 비어 있지만 거기에
  /// 청소를 넣으면 아무도 안 한다. 그 시간에 이 사람이 실제로 움직인 적이
  /// 있어야 자리가 된다.
  static List<OpenWindow> openWindows({
    String? historyRaw,
    String? habitsRaw,
    String? schedulesRaw,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final records = _recordsWithin(historyRaw, at);
    if (records.isEmpty) return const [];

    // 요일 × 2시간 구간에서 실제로 시작한 날 수.
    final starts = <String, int>{};
    for (final record in records) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) continue;
      final weekday = date.weekday - 1;
      final seen = <int>{};
      for (final task in _asList(record['tasks'])) {
        final startedAt = DateTime.tryParse(
          (task['startedAt'] ?? task['completedAt'])?.toString() ?? '',
        );
        if (startedAt == null) continue;
        final slot = startedAt.hour - startedAt.hour % 2;
        if (!seen.add(slot)) continue;
        starts['$weekday:$slot'] = (starts['$weekday:$slot'] ?? 0) + 1;
      }
    }
    if (starts.isEmpty) return const [];

    final taken = _takenSlots(habitsRaw, schedulesRaw, at);

    final windows = <OpenWindow>[];
    starts.forEach((key, evidence) {
      if (evidence < minWindowEvidence) return;
      if (taken.contains(key)) return;
      final parts = key.split(':');
      windows.add(
        OpenWindow(
          weekday: int.parse(parts[0]),
          startHour: int.parse(parts[1]),
          evidence: evidence,
        ),
      );
    });

    windows.sort((a, b) => b.evidence.compareTo(a.evidence));
    return windows;
  }

  /// 이미 무언가가 잡혀 있는 요일×구간.
  static Set<String> _takenSlots(
    String? habitsRaw,
    String? schedulesRaw,
    DateTime at,
  ) {
    final taken = <String>{};

    for (final habit in _decodeList(habitsRaw)) {
      final slot = _slotOf(habit['timeStart']?.toString());
      if (slot == null) continue;
      final days = _intList(habit['days']);
      if (days.isEmpty) {
        // 매일 하는 루틴은 모든 요일의 그 자리를 차지한다.
        for (var day = 0; day < 7; day++) {
          taken.add('$day:$slot');
        }
        continue;
      }
      for (final day in days) {
        taken.add('$day:$slot');
      }
    }

    _decodeMap(schedulesRaw).forEach((key, value) {
      final date = DateTime.tryParse(key);
      if (date == null) return;
      if (at.difference(date).inDays > windowDays) return;
      final weekday = date.weekday - 1;
      for (final item in _asList(value)) {
        final slot = _slotOf(item['timeStart']?.toString());
        if (slot == null) continue;
        taken.add('$weekday:$slot');
      }
    });

    return taken;
  }

  static int? _slotOf(String? hhmm) {
    if (hhmm == null || hhmm.isEmpty) return null;
    final hour = int.tryParse(hhmm.split(':').first);
    if (hour == null || hour < 0 || hour > 23) return null;
    return hour - hour % 2;
  }

  // ── 루틴 하나 재기 ────────────────────────────

  /// 그 루틴이 이 창 안에서 얼마나 됐는지, 어느 요일에 됐는지.
  ///
  /// 기회가 없던 날은 세지 않는다. 화·목 루틴을 월요일에 안 했다고 실패로
  /// 세면 어떤 루틴도 실패로 나온다.
  static WeakSpot? _measure(
    Map<String, dynamic> habit,
    Map<String, dynamic> logs,
    List<Map<String, dynamic>> records,
    DateTime at,
  ) {
    final id = habit['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final targetDays = _intList(habit['days']);
    final mine = logs[id];
    final byDate = mine is Map ? Map<String, dynamic>.from(mine) : const {};

    var chances = 0;
    var done = 0;
    final chancesByDay = <int, int>{};
    final doneByDay = <int, int>{};

    for (var offset = 0; offset < windowDays; offset++) {
      final day = DateTime(at.year, at.month, at.day - offset);
      final weekday = day.weekday - 1;
      if (targetDays.isNotEmpty && !targetDays.contains(weekday)) continue;
      final key = _dateKey(day);
      // 그날 앱을 안 열었으면 기회 자체가 없던 날이다.
      if (!records.any((r) => r['date'] == key)) continue;

      chances++;
      chancesByDay[weekday] = (chancesByDay[weekday] ?? 0) + 1;
      final log = byDate[key];
      if (log is Map && log['done'] == true) {
        done++;
        doneByDay[weekday] = (doneByDay[weekday] ?? 0) + 1;
      }
    }

    if (chances == 0) return null;

    final workingDays = <int>[];
    chancesByDay.forEach((weekday, count) {
      if (count < minChancesPerDay) return;
      final ok = doneByDay[weekday] ?? 0;
      if (ok / count >= keepingWellRate) workingDays.add(weekday);
    });
    workingDays.sort();

    return WeakSpot(
      habitId: id,
      name: habit['name']?.toString() ?? '',
      rate: done / chances,
      workingDays: workingDays,
      targetDays: targetDays,
    );
  }

  // ── 그 밖의 판정 ──────────────────────────────

  static bool _notMyBusiness(Map<String, dynamic> answers) {
    if (answers['share'] == _sharedAway) return true;
    final want = answers['want'];
    if (want == null) return false;
    final picked = want is List
        ? want.map((e) => e.toString()).toList()
        : [want.toString()];
    if (picked.isEmpty) return true;
    return picked.length == 1 && picked.first == _wantsNothing;
  }

  /// 잡아둔 것도 절반을 못 끝내는 중인지.
  static bool _crowded(List<Map<String, dynamic>> records) {
    var planned = 0;
    var done = 0;
    for (final record in records) {
      planned += (record['totalCount'] as num?)?.toInt() ?? 0;
      done += (record['doneCount'] as num?)?.toInt() ?? 0;
    }
    if (records.isEmpty) return false;
    final planPerDay = planned / records.length;
    if (planPerDay < crowdedMinPlanPerDay) return false;
    return done < planned * crowdedDoneRatio;
  }

  static String _days(List<int> days) =>
      days.map((d) => '${OpenWindow.weekdayNames[d]}요일').join('·');

  // ── 읽기 ──────────────────────────────────────

  static List<Map<String, dynamic>> _recordsWithin(String? raw, DateTime at) {
    final floor = DateTime(at.year, at.month, at.day - windowDays);
    return _decodeList(raw).where((record) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null) return false;
      return !date.isBefore(floor) && !date.isAfter(at);
    }).toList(growable: false);
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

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return const {};
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  static List<int> _intList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
        .whereType<int>()
        .where((d) => d >= 0 && d <= 6)
        .toList(growable: false);
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
