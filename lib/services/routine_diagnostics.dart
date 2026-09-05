import 'dart:convert';

import 'package:intl/intl.dart';

/// 루틴이 오늘 탭에서 사라졌을 때, 왜 안 올라왔는지 그 자리에서 보여준다.
///
/// 오늘 목록은 저장된 값 몇 개로 정해지는데 화면에는 결과만 나온다. 그래서
/// "루틴 탭에는 있는데 오늘 탭에는 없다"를 만나면, 반복 설정이 매일이 아닌
/// 것인지 그날 쉬기로 찍힌 것인지 목록을 만들다 빠진 것인지 구분할 방법이
/// 없었다. 셋은 고치는 자리가 전혀 다르다.
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
  }) {
    final today = dateKey(now);
    final lines = <String>[];

    lines.add('오늘 $today');
    lines.add('저장된 날짜 ${lastDate ?? '없음'}');
    lines.add('이 기기 정리 완료 ${resetDoneDate ?? '없음'}');
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
      lines.add(
        '- $name\n'
        '  반복: ${_freqLabel(h)}\n'
        '  오늘 목록: ${inToday ? '있음' : '없음'}\n'
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

    return lines.join('\n');
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
    if (freq == 'weekly') {
      final days = habit['days'];
      if (days is! List || days.isEmpty) {
        return '요일 지정인데 고른 요일이 없음';
      }
    }
    return null;
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
      final at = _timeOf(log['skippedAt']);
      return '쉬기${at == null ? '' : ' ($at)'}';
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
