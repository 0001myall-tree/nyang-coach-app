import 'dart:convert';

import 'package:intl/intl.dart';

import 'routine_schedule.dart';

/// 오늘 탭에 뭔가 빠지거나 남아 있을 때, 저장된 값을 그 자리에서 보여준다.
///
/// 오늘 목록은 저장된 값 몇 개로 정해지는데 화면에는 결과만 나온다. 그래서
/// "루틴 탭에는 있는데 오늘 탭에는 없다"를 만나면, 반복 설정이 매일이 아닌
/// 것인지 그날 쉬기로 찍힌 것인지 목록을 만들다 빠진 것인지 구분할 방법이
/// 없었다. 셋은 고치는 자리가 전혀 다르다. 핵심 칸에 어제 것이 남는 경우와
/// 지난 날 목록이 비어 보이는 경우도 같은 이유로 여기서 같이 보여준다.
class RoutineDiagnostics {
  static String dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  /// 저장된 값을 그대로 읽어 사람이 읽을 수 있는 한 장으로 만든다.
  static String build({
    required String? rawHabits,
    required String? rawHabitLogs,
    required String? rawTasks,
    required String? lastDate,
    required String? resetDoneDate,
    required DateTime now,
    String? rawCoreTasks,
    String? rawTasksByDate,
    bool? hasSyncedFromCloud,
    bool? pendingCloudUpload,
    bool? appleCalendarEnabled,
    String? rawCalendarEventMap,
  }) {
    final today = dateKey(now);
    final lines = <String>[];

    lines.add('오늘 $today');
    lines.add('저장된 날짜 ${lastDate ?? '없음'}');
    lines.add('이 기기 정리 완료 ${resetDoneDate ?? '없음'}');
    if (hasSyncedFromCloud != null) {
      lines.add('클라우드 복원 ${hasSyncedFromCloud ? '끝남' : '아직'}');
    }
    if (pendingCloudUpload != null) {
      lines.add('못 올린 변경 ${pendingCloudUpload ? '있음' : '없음'}');
    }
    if (lastDate != null && lastDate != today) {
      lines.add('※ 저장된 날짜가 오늘이 아님 — 정리가 아직 안 돌았거나 되돌려진 상태');
    }

    final habits = _decodeList(rawHabits);
    final logs = _decodeMap(rawHabitLogs);
    final tasks = _decodeList(rawTasks);

    final habitIdsInToday = <String>{};
    for (final t in tasks) {
      if (t is! Map) continue;
      final id = t['habitId']?.toString();
      if (id != null && id.isNotEmpty && id != 'null') habitIdsInToday.add(id);
    }

    lines.add('');
    lines.add('[루틴 ${habits.length}개]');
    if (habits.isEmpty) lines.add('- 없음');
    for (final h in habits) {
      if (h is! Map) {
        lines.add('- (읽을 수 없는 항목)');
        continue;
      }
      final id = h['id']?.toString() ?? '?';
      final name = h['name']?.toString() ?? '(이름 없음)';
      final inToday = habitIdsInToday.contains(id);
      final log = _logFor(logs, id, today);
      final reason = inToday
          ? null
          : missingReason(habit: h, logs: logs, today: today);
      lines.add(
        '- $name\n'
        '  반복: ${_freqLabel(h)}\n'
        '${_weekProgressLine(h, logs, now)}'
        '  오늘 목록: ${inToday ? '있음' : '없음'}\n'
        '${reason == null ? '' : '  빠진 이유: $reason\n'}'
        '  오늘 기록: ${_logLabel(log)}\n'
        '  만든 날: ${_dayOf(h['createdAt']) ?? '모름'} · id $id',
      );
    }

    lines.add('');
    lines.add('[오늘 목록 ${tasks.length}개]');
    if (tasks.isEmpty) lines.add('- 비어 있음');
    for (final t in tasks) {
      if (t is! Map) continue;
      final text = t['text']?.toString() ?? '(이름 없음)';
      final kind = t['category']?.toString() ?? 'today';
      final marks = <String>[
        if (t['done'] == true) '완료',
        if (t['inProgress'] == true) '진행 중',
      ];
      final suffix = marks.isEmpty ? '' : ' · ${marks.join(', ')}';
      lines.add('- $text ($kind)$suffix');
    }

    final todayIds = tasks
        .whereType<Map>()
        .map((t) => t['id'].toString())
        .toSet();
    final core = _decodeList(rawCoreTasks);
    lines.add('');
    lines.add('[오늘의 핵심 ${core.length}개]');
    if (core.isEmpty) lines.add('- 없음');
    for (final c in core) {
      if (c is! Map) continue;
      final text = c['text']?.toString() ?? '(이름 없음)';
      final id = c['id'].toString();
      // 목표 마일스톤은 오늘 목록이 아니라 목표 탭에서 온다.
      final fromGoals = id.startsWith('milestone_');
      final where = fromGoals
          ? '목표 탭'
          : todayIds.contains(id)
          ? '오늘 목록에 있음'
          : '오늘 목록에 없음 ← 어제 것이 남은 자리';
      lines.add('- $text ($where)');
    }

    final byDate = _decodeMap(rawTasksByDate);
    lines.add('');
    lines.add('[날짜별 보관 ${byDate.length}일]');
    if (byDate.isEmpty) lines.add('- 없음');
    final days = byDate.keys.toList()..sort();
    for (final day in days) {
      final value = byDate[day];
      final count = value is List ? value.length : 0;
      lines.add('- $day: $count개');
    }

    lines.addAll(
      _calendarLines(
        enabled: appleCalendarEnabled,
        rawEventMap: rawCalendarEventMap,
      ),
    );

    return lines.join('\n');
  }

  /// 이 기기의 애플 캘린더 연동 상태.
  ///
  /// 한동안은 캘린더에서 이벤트가 안 잡히면 "사용자가 지웠다"로 읽고 루틴을
  /// 쉬기로 찍었다. 지금은 그 길을 없애서 내보내기만 한다. 그래도 몇 개를
  /// 내보냈는지는 보이는 편이 낫다 — 연동이 도는지 아닌지가 여기서 갈린다.
  static List<String> _calendarLines({
    required bool? enabled,
    required String? rawEventMap,
  }) {
    if (enabled == null) return const [];
    final lines = <String>['', '[애플 캘린더 연동 ${enabled ? '켜짐' : '꺼짐'}]'];
    if (!enabled) return lines;
    lines.add('- 내보낸 이벤트: ${_decodeMap(rawEventMap).length}개');
    lines.add('- 캘린더에서 지운 것은 앱에 반영하지 않아요.');
    return lines;
  }

  /// 루틴이 오늘 목록에서 빠진 이유로 짐작되는 것. 없으면 null.
  ///
  /// 확정이 아니라 어디부터 볼지 가리키는 것이다.
  static String? missingReason({
    required Map<dynamic, dynamic> habit,
    required Map<String, dynamic> logs,
    required String today,
  }) {
    final id = habit['id']?.toString() ?? '';
    final log = _logFor(logs, id, today);
    if (log != null && log['status'] == 'skipped') {
      return '오늘 쉬기로 찍혀 있음';
    }
    final freq = habit['freq']?.toString() ?? 'daily';
    final date = DateTime.tryParse(today);
    if (freq == 'weekly') {
      final days = habit['days'];
      if (days is! List || days.isEmpty) {
        return '요일 지정인데 고른 요일이 없음';
      }
      if (date != null && !days.contains(date.weekday - 1)) {
        return '오늘 요일이 고른 요일에 없음';
      }
    }
    if (freq == 'weekly_count' && date != null) {
      final logsForHabit = logs[id];
      final showing = RoutineSchedule.shouldShowWeeklyCountOnDate(
        rawWeeklyTargetCount: habit['weeklyTargetCount'],
        rawCreatedAt: habit['createdAt'],
        logs: logsForHabit is Map ? logsForHabit : const {},
        date: date,
      );
      if (!showing) return '이번 주 횟수를 이미 채움';
    }
    return null;
  }

  /// 주 몇 회짜리 루틴만, 이번 주에 몇 번 했는지 적는다. 나머지는 빈 줄.
  ///
  /// 주 n회는 목표를 채우면 그 주 남은 날에는 안 올라온다. 매일 루틴은 그런
  /// 일이 없어서, 옆에 나란히 놓고 보면 왜 하나만 사라지는지가 보인다.
  static String _weekProgressLine(
    Map<dynamic, dynamic> habit,
    Map<String, dynamic> logs,
    DateTime now,
  ) {
    if (habit['freq']?.toString() != 'weekly_count') return '';
    final id = habit['id']?.toString() ?? '';
    final logsForHabit = logs[id];
    final created = RoutineSchedule.createdDate(habit['createdAt']);
    final target = RoutineSchedule.visibleWeeklyTarget(
      target: RoutineSchedule.weeklyTarget(habit['weeklyTargetCount']),
      createdDate: created,
      date: now,
    );
    final done = RoutineSchedule.doneCount(
      logs: logsForHabit is Map ? logsForHabit : const {},
      createdDate: created,
      date: now,
      includeDate: false,
    );
    return '  이번 주(오늘 빼고): ${_trimNumber(done)} / $target회\n';
  }

  static String _trimNumber(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toStringAsFixed(2);
  }

  static Map<String, dynamic>? _logFor(
    Map<String, dynamic> logs,
    String habitId,
    String today,
  ) {
    final forHabit = logs[habitId];
    if (forHabit is! Map) return null;
    final log = forHabit[today];
    return log is Map ? Map<String, dynamic>.from(log) : null;
  }

  static String _logLabel(Map<String, dynamic>? log) {
    if (log == null) return '없음';
    final status = log['status']?.toString();
    if (status == 'skipped') {
      // 시각만 적으면 오늘 찍힌 것처럼 보인다. 실제로는 며칠 전에 미리 찍힌
      // 것이었고, 그래서 "아직 오지도 않은 시각에 쉬기로 돼 있다"가 됐다.
      // 언제 적혔는지는 날짜까지 봐야 갈린다.
      final at = _stampOf(log['skippedAt']);
      return '쉬기${at == null ? '' : ' ($at 찍힘)'}';
    }
    if (log['done'] == true) {
      final at = _timeOf(log['completedAt']);
      return '완료${at == null ? '' : ' ($at)'}';
    }
    return status ?? '알 수 없음';
  }

  static String _freqLabel(Map<dynamic, dynamic> habit) {
    final freq = habit['freq']?.toString() ?? 'daily';
    if (freq == 'daily') return '매일';
    if (freq == 'weekly_count') {
      return '주 ${habit['weeklyTargetCount'] ?? 5}일';
    }
    if (freq == 'weekly') {
      const names = ['월', '화', '수', '목', '금', '토', '일'];
      final days = habit['days'];
      if (days is! List || days.isEmpty) return '요일 지정 (고른 요일 없음)';
      final picked = days
          .map((d) => d is int && d >= 0 && d < 7 ? names[d] : '?')
          .join('/');
      return '요일 지정 $picked';
    }
    return '알 수 없음 ($freq)';
  }

  static String? _dayOf(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? null : dateKey(parsed);
  }

  /// 언제 적혔는지. 날짜까지 적는다.
  static String? _stampOf(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null
        ? null
        : DateFormat('yyyy-MM-dd HH:mm').format(parsed);
  }

  static String? _timeOf(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? null : DateFormat('HH:mm').format(parsed);
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
}
