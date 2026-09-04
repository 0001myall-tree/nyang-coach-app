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

  /// 태그가 하나도 없으면 null — 저장된 것을 건드리지 않는다.
  ///
  /// 태그가 있으면 그 답변에 붙은 것 전부가 지금 맞는 값이다. 하나씩 더하고
  /// 지우는 태그를 따로 두지 않는 것은, 그러면 '바뀌었다'와 '없어졌다'와
  /// '하나만 빠졌다'를 앱이 각각 알아들어야 하기 때문이다. 무엇이 어떻게
  /// 달라졌는지는 대화를 본 코치가 안다. 앱은 받아 적기만 한다.
  ///
  /// [BUSY: 없음]은 빈 목록 — 이제 그런 때가 없다는 말이다.
  static List<BusyHours>? readAll(String raw) {
    final matches = _tagRegex.allMatches(raw).toList();
    if (matches.isEmpty) return null;
    final hours = <BusyHours>[];
    for (final match in matches) {
      final body = match.group(1)!.trim();
      if (_noneWords.contains(body)) continue;
      final parsed = _readOne(body);
      if (parsed != null) hours.add(parsed);
    }
    // 알아들은 게 하나도 없는데 '없음'도 아니면 형식이 깨진 것이다. 그걸
    // 비었다고 받아들이면 멀쩡한 값이 통째로 지워진다.
    if (hours.isEmpty &&
        !matches.any((m) => _noneWords.contains(m.group(1)!.trim()))) {
      return null;
    }
    return hours;
  }

  static const Set<String> _noneWords = {'없음', '없다', 'none', '-'};

  static BusyHours? _readOne(String body) {
    final parts = body.split('|').map((p) => p.trim()).toList();
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

  /// 받아 적은 것으로 통째로 바꾼다.
  ///
  /// 있던 것에 더하지 않는다. 코치가 넘기는 것은 '이번에 알게 된 것'이 아니라
  /// '지금 맞는 것 전부'라, 빠진 항목은 없어졌다는 뜻이다.
  static Future<void> replaceAll(List<BusyHours> hours) async {
    final prefs = await SharedPreferences.getInstance();
    final kept = hours.length > _maxEntries
        ? hours.sublist(hours.length - _maxEntries)
        : hours;
    await prefs.setString(
      prefsKey,
      jsonEncode(kept.map((h) => h.toJson()).toList()),
    );
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

  /// 받아둔 시간대를 프롬프트에 실을 모양으로. 없으면 빈 문자열.
  ///
  /// 오늘 걸리는 것만 추리지 않는다. 코치가 태그로 다시 적을 때 지금 맞는 것
  /// 전부를 적어야 하는데, 오늘 것만 보여주면 다른 요일 것을 없어진 줄 알고
  /// 빠뜨린다. 루틴을 어느 요일에 넣을지 고르는 자리에도 한 주가 다 필요하다.
  ///
  /// [withUpdateRule]은 대화에서만 붙인다. 자동 발화나 추천처럼 사용자의 답을
  /// 받을 수 없는 자리에서는 확인하라고 해봐야 물을 상대가 없다.
  static String promptBlock(
    SharedPreferences prefs, {
    bool withUpdateRule = false,
  }) {
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
    final block =
        '\n[늘 시간을 못 내는 때 - 일정 배치 시 이 시간대 피할 것]\n${lines.join('\n')}\n';
    if (!withUpdateRule) return block;
    // 어긋난 것을 찾으라고 시키지 않는다. 찾으라고 하면 없는 어긋남을 지어내
    // 매일 같은 것을 묻는다. 무엇이 어긋남이 아닌지를 알려주는 편이 낫다.
    return '$block'
        '- 이 시간대에 시작·완료 표시가 있어도 대개는 짬을 낸 것이다(점심시간 등). '
        '그 시간이 통째로 바뀐 것으로 보일 때만 한 번 확인하고, 답을 들으면 태그로 다시 적을 것.\n';
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
