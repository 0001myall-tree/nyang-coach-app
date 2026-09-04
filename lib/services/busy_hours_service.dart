import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'tasks_sync_service.dart';

/// 사용자가 규칙적으로 시간을 못 내는 때. 근무 시간이 대표적이다.
///
/// 저장 자리는 비서 학습 설정의 '고정 루틴'과 같다. 형식이 이미 같고 클라우드
/// 동기화도 걸려 있어서, 설정 화면이 돌아오면 여기서 넣은 것도 그대로 보인다.
///
/// 값을 채우는 길은 대화뿐이다 — 지금 앱에는 고정 루틴을 넣는 화면이 없다.
class BusyHoursService {
  static const String prefsKey = 'nyang_premium_routines';

  /// 대화에서 받아둘 수 있는 개수. 근무 시간과 등하원처럼 몇 개면 충분한데,
  /// 상한이 없으면 코치가 같은 이야기를 조금씩 다른 이름으로 계속 쌓는다.
  static const int _maxEntries = 5;

  static const List<String> _dayNames = ['일', '월', '화', '수', '목', '금', '토'];

  static final RegExp _tagRegex = RegExp(r'\[BUSY:\s*([^\]]+)\]');

  /// "9:00-19:00", "09-19", "9시-19시" 정도는 받아준다. 코치가 형식을 정확히
  /// 지킨다는 전제로 좁게 잡으면, 어긋난 한 번이 통째로 버려진다.
  static final RegExp _rangeRegex = RegExp(
    r'(\d{1,2})\s*(?::|시)?\s*(\d{2})?\s*[-~]\s*(\d{1,2})\s*(?::|시)?\s*(\d{2})?',
  );

  /// 답변에서 [BUSY: ...]를 읽는다. 못 알아들을 모양이면 null.
  static BusyHours? read(String raw) {
    final match = _tagRegex.firstMatch(raw);
    if (match == null) return null;
    final parts = match.group(1)!.split('|').map((p) => p.trim()).toList();
    if (parts.length < 2) return null;

    final name = parts[0];
    if (name.isEmpty) return null;

    final range = _rangeRegex.firstMatch(parts[1]);
    if (range == null) return null;
    final startHour = int.tryParse(range.group(1)!) ?? -1;
    final endHour = int.tryParse(range.group(3)!) ?? -1;
    if (startHour < 0 || startHour > 23 || endHour < 0 || endHour > 23) {
      return null;
    }
    final startMinute = int.tryParse(range.group(2) ?? '0') ?? 0;
    final endMinute = int.tryParse(range.group(4) ?? '0') ?? 0;
    if (startMinute > 59 || endMinute > 59) return null;

    final days = parts.length > 2 ? _days(parts[2]) : const <String>[];

    return BusyHours(
      name: name.length > 20 ? name.substring(0, 20) : name,
      start: _hhmm(startHour, startMinute),
      end: _hhmm(endHour, endMinute),
      days: days,
    );
  }

  static String strip(String raw) => raw.replaceAll(_tagRegex, '');

  /// 요일 칸을 읽는다.
  ///
  /// 글자를 그냥 훑으면 '평일'의 '일'이 일요일이 된다 — 평일이라고 적어준
  /// 사람이 주말까지 바쁜 사람으로 저장된다. 그래서 묶음 말을 먼저 펼쳐
  /// 떼어내고 남은 자리만 훑는다.
  static List<String> _days(String raw) {
    final picked = <String>{};
    var rest = raw;
    if (rest.contains('평일')) {
      picked.addAll(['월', '화', '수', '목', '금']);
    }
    if (rest.contains('주말')) {
      picked.addAll(['토', '일']);
    }
    for (final word in ['공휴일', '평일', '주말', '매일', '휴일', '내일', '요일']) {
      rest = rest.replaceAll(word, ' ');
    }
    picked.addAll(_dayNames.where(rest.contains));
    return _dayNames.where(picked.contains).toList();
  }

  /// 같은 이름이 있으면 갈아끼운다. 시간을 고쳐 말한 것을 새 항목으로 쌓으면
  /// 옛 시간대가 남아 하루 종일 바쁜 사람이 된다.
  static Future<void> save(BusyHours hours) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = _decode(prefs.getString(prefsKey))
      ..removeWhere((e) => e['name']?.toString().trim() == hours.name)
      ..add(hours.toJson());
    while (entries.length > _maxEntries) {
      entries.removeAt(0);
    }
    await prefs.setString(prefsKey, jsonEncode(entries));
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 지금이 그 시간대 안이면 이름을, 아니면 null.
  static String? busyNow(SharedPreferences prefs, DateTime now) {
    final today = _dayNames[now.weekday % 7];
    final minutes = now.hour * 60 + now.minute;
    for (final entry in _decode(prefs.getString(prefsKey))) {
      final days = ((entry['days'] as List?) ?? []).cast<String>();
      if (days.isNotEmpty && !days.contains(today)) continue;
      final start = _minutes(entry['start']?.toString());
      final end = _minutes(entry['end']?.toString());
      if (start == null || end == null || start == end) continue;
      // 자정을 넘기는 시간대(야간 근무 등)는 앞뒤가 뒤집혀 저장된다.
      final inside = end > start
          ? minutes >= start && minutes < end
          : minutes >= start || minutes < end;
      if (inside) return entry['name']?.toString();
    }
    return null;
  }

  /// 오늘 걸리는 시간대를 프롬프트에 실을 모양으로. 없으면 빈 문자열.
  ///
  /// 대화와 루틴 추천이 같은 문장을 쓴다. 자리마다 따로 적어두면 한쪽만 고쳐져
  /// 코치가 자리에 따라 다른 것을 아는 상태가 된다.
  static String promptBlock(SharedPreferences prefs, DateTime now) {
    final today = _dayNames[now.weekday % 7];
    final lines = <String>[];
    for (final entry in _decode(prefs.getString(prefsKey))) {
      final days = ((entry['days'] as List?) ?? []).cast<String>();
      if (days.isNotEmpty && !days.contains(today)) continue;
      final start = _label(entry['start']?.toString());
      final end = _label(entry['end']?.toString());
      if (start == null || end == null) continue;
      lines.add('- ${entry['name']}: $start ~ $end');
    }
    if (lines.isEmpty) return '';
    return '\n[오늘 고정 루틴 (일정 배치 시 이 시간대 피할 것)]\n${lines.join('\n')}\n';
  }

  /// 요일까지 포함한 한 주치. 루틴을 어느 요일에 넣을지 고르는 자리에 쓴다.
  ///
  /// 그 자리에 오늘 것만 보내면 토요일 오전을 권하면서 토요일에 뭐가 있는지는
  /// 모르는 상태가 된다.
  static String weeklyPromptBlock(SharedPreferences prefs) {
    final lines = <String>[];
    for (final entry in _decode(prefs.getString(prefsKey))) {
      final start = _label(entry['start']?.toString());
      final end = _label(entry['end']?.toString());
      if (start == null || end == null) continue;
      final days = ((entry['days'] as List?) ?? []).cast<String>();
      final when = days.isEmpty ? '매일' : days.join('');
      lines.add('- ${entry['name']}: $when $start ~ $end');
    }
    if (lines.isEmpty) return '';
    return '\n[늘 시간을 못 내는 때]\n${lines.join('\n')}\n';
  }

  static String? _label(String? hhmm) {
    final parts = (hhmm ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    if (hour == null) return null;
    final meridiem = hour >= 12 ? '오후' : '오전';
    final shown = hour > 12 ? hour - 12 : hour;
    return '$meridiem $shown:${parts[1]}';
  }

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static int? _minutes(String? hhmm) {
    final parts = (hhmm ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  static String _hhmm(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class BusyHours {
  final String name;
  final String start;
  final String end;

  /// 비어 있으면 매일. 설정 화면이 쓰던 규칙을 그대로 따른다.
  final List<String> days;

  const BusyHours({
    required this.name,
    required this.start,
    required this.end,
    required this.days,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'start': start,
    'end': end,
    'days': days,
  };
}
