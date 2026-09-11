import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 오늘 이 사람에게 쓸 수 있는 시간이 얼마나 되는지.
///
/// 지금까지 "많이 잡았다"를 개수로 쟀다. 평소 해내던 것보다 몇 개 많으냐로.
/// 그런데 두 시간밖에 없는 날의 다섯 개와 온종일 비는 날의 다섯 개는 전혀
/// 다른 이야기다. 개수는 그 차이를 못 본다.
///
/// 기록으로는 알 수 없다. 출근했는지, 약속이 있었는지, 아이가 아팠는지는
/// 앱에 남지 않는다. 본인은 아침에 이미 알고 있으니 물어보면 된다.
///
/// 답은 그날 하루에만 맞는 값이다. 오늘 답이 내일의 답이 아니다. 다만 버리지는
/// 않고 날짜별로 쌓아둔다 - 저녁에 "아침엔 두세 시간이라 했잖아"를 하려면 그
/// 답이 남아 있어야 하고, 며칠이 쌓이면 시간이 넉넉했던 날과 빠듯했던 날을
/// 견줄 수도 있다.
class DayCapacityService {
  const DayCapacityService._();

  /// 오늘 답만 담던 옛 자리. `날짜|답` 한 줄이었다.
  ///
  /// 이제는 [logKey]로 옮겨 적는다. 여기 남은 값은 옮기기 위해서만 읽는다.
  static const String _key = 'day_capacity';

  /// 날짜별로 쌓아둔 답. `{"2026-09-11": "두세 시간 정도"}`.
  ///
  /// 하루만 살던 값이었다. 아침에 물어서 받아놓고 그날 안에만 쓰고 버렸는데,
  /// 그러면 저녁에 "아침엔 두세 시간이라 했잖아"를 할 수가 없다. 그 한마디가
  /// 이 질문이 가진 힘의 대부분이다 - 앱이 센 숫자는 반박할 수 있어도 본인이
  /// 아침에 고른 답은 반박할 데가 없다.
  ///
  /// 쌓이면 견줄 수도 있게 된다. 시간이 넉넉했던 날과 빠듯했던 날에 실제로
  /// 얼마나 달랐는지는 이 값이 없으면 아예 못 세는 축이다.
  ///
  /// 이 기기에서만 뜻이 있는 값이라 'nyang_' 접두어를 쓰지 않는다.
  static const String logKey = 'day_capacity_log';

  /// 답을 몇 개까지 들고 있을지.
  ///
  /// 날짜가 아니라 답의 개수다. 사흘에 한 번 묻는 자리라 스물이면 두 달쯤을
  /// 덮는다.
  ///
  /// 더 들고 있을 이유가 없다. 이 답은 그날 실제로 얼마나 했는지와 맞붙여야
  /// 뜻이 생기는데, 하루 기록은 30일치만 남는다. 그보다 오래된 답은 견줄
  /// 상대가 없어서 혼자 남는다.
  static const int keepAnswers = 20;

  /// 답을 안 고르고 넘긴 날. 물어본 적은 있다는 표시다.
  static const String _skipped = '';

  /// 고를 수 있는 답과, 코치에게 넘길 한 줄.
  ///
  /// 시간을 숫자로 묻지 않는다. "오늘 몇 시간 쓸 수 있어?"는 답하려면 하루를
  /// 계산해봐야 하는 질문이고, 아침에 그걸 시키면 그것부터가 일이다.
  static const Map<String, String> answers = {
    '온종일 비어 있어': '오늘은 하루가 통째로 비어 있음.',
    '반나절쯤 돼': '오늘 쓸 수 있는 시간이 반나절쯤.',
    '두세 시간 정도': '오늘 쓸 수 있는 시간이 두세 시간뿐.',
    '거의 없어': '오늘은 짬이 거의 없음. 한두 가지가 한계.',
  };

  static List<String> get labels => answers.keys.toList(growable: false);

  /// 이만큼 넘게 잡는 날이 있는 사람에게만 묻는다.
  ///
  /// 이 질문의 값은 "오늘 이만큼이 되겠냐"를 재는 데 있다. 두세 개만 적는
  /// 사람에게는 잴 것이 없어서, 매일 아침 묻는 것이 순수한 부담만 된다.
  static const int asksFromPlanCount = 5;

  /// 물어볼 만한 사람인지. 최근 이레에 많이 잡은 날이 있으면 묻는다.
  ///
  /// 완료율은 보지 않는다. 한동안 "잘 굴러가는 사람에게 묻는 건 검사에
  /// 가깝다"고 문턱을 두었는데, 그건 매일 묻던 시절의 이야기다. 사흘에 한
  /// 번이면 검사가 아니라 챙기는 말이고, 무엇보다 다 해내는 사람에게도 오늘
  /// 두 시간뿐인 날은 온다. 그날 여섯 개를 짜주면 잘 해내던 사람을 실패시킨다.
  ///
  /// 눈금이 애초에 다르기도 하다. 완료율은 어제까지의 이야기이고 이 질문은
  /// 오늘 이야기라, 어제로 오늘을 거를 이유가 없다.
  static bool worthAsking(String? historyRaw) {
    if (historyRaw == null || historyRaw.isEmpty) return false;
    List<dynamic> list;
    try {
      list = jsonDecode(historyRaw) as List<dynamic>;
    } catch (_) {
      return false;
    }
    final from = DateTime.now().subtract(const Duration(days: 7));
    final today = _todayKey();
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      // 오늘은 아직 안 끝났다. 아침에 여섯 개 적어둔 것만 보고 판단하면
      // 그날 하루를 지켜보지도 않고 세는 셈이다.
      if (_dateKey(date) == today) continue;
      final tasks = (item['tasks'] as List?) ?? const [];
      if (tasks.length >= asksFromPlanCount) return true;
    }
    return false;
  }

  /// 오늘 이미 물어봤거나 답했는지.
  static Future<bool> answeredToday() async {
    final prefs = await SharedPreferences.getInstance();
    return (await _log(prefs)).containsKey(_todayKey());
  }

  static Future<void> save(String answer) async {
    if (!answers.containsKey(answer)) return;
    await _write(answer);
  }

  /// 물어는 봤는데 답을 안 골랐을 때. 오늘은 다시 묻지 않는다.
  static Future<void> markAsked() async => _write(_skipped);

  /// 오늘 고른 답. 없으면 null.
  static Future<String?> today() async => answerOn(DateTime.now());

  /// 그날 고른 답. 안 물었거나 답을 안 골랐으면 null.
  ///
  /// 사흘에 한 번만 묻는 자리라, 대부분의 날은 null이다. 받는 쪽은 없는 날을
  /// 견뎌야 한다 - 없는 것이 예외가 아니라 보통이다.
  static Future<String?> answerOn(DateTime date) async {
    final prefs = await SharedPreferences.getInstance();
    final answer = (await _log(prefs))[_dateKey(date)];
    return (answer != null && answers.containsKey(answer)) ? answer : null;
  }

  /// 날짜별로 쌓인 답 전부. `{"2026-09-11": "두세 시간 정도"}`.
  ///
  /// 답을 안 고른 날은 빠진다. 물어봤다는 사실만으로는 견줄 것이 없다.
  static Future<Map<String, String>> recentAnswers() async {
    final prefs = await SharedPreferences.getInstance();
    final log = await _log(prefs);
    return {
      for (final entry in log.entries)
        if (answers.containsKey(entry.value)) entry.key: entry.value,
    };
  }

  static Future<void> _write(String answer) async {
    final prefs = await SharedPreferences.getInstance();
    final log = await _log(prefs);
    log[_todayKey()] = answer;
    await _save(prefs, log);
  }

  /// 저장된 기록. 읽는 김에 옛 자리에 남은 하루치를 옮겨 담는다.
  static Future<Map<String, String>> _log(SharedPreferences prefs) async {
    final log = <String, String>{};
    final raw = prefs.getString(logKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            log['$key'] = '$value';
          });
        }
      } catch (_) {}
    }

    // 옛 자리에 오늘 답이 남아 있을 수 있다. 새 자리로 옮기지 않으면 오늘
    // 아침에 답한 사람에게 오후에 또 묻게 된다.
    final legacy = prefs.getString(_key);
    if (legacy != null && legacy.contains('|')) {
      final parts = legacy.split('|');
      // 옛 자리는 자리를 안 채운 '2026-9-11' 모양이었다. 그대로 옮기면 같은
      // 날이 두 벌 남는다.
      final legacyDate = DateTime.tryParse(parts.first);
      if (parts.length == 2 && legacyDate != null) {
        final key = _dateKey(legacyDate);
        if (!log.containsKey(key)) {
          log[key] = parts.last;
          await _save(prefs, log);
        }
      }
      await prefs.remove(_key);
    }
    return log;
  }

  static Future<void> _save(
    SharedPreferences prefs,
    Map<String, String> log,
  ) async {
    if (log.length > keepAnswers) {
      final keys = log.keys.toList()..sort();
      for (final key in keys.take(log.length - keepAnswers)) {
        log.remove(key);
      }
    }
    await prefs.setString(logKey, jsonEncode(log));
  }

  /// `2026-09-11`. 자리를 채워서 적는다.
  ///
  /// 채우지 않으면 글자 순서가 날짜 순서와 달라진다 - '2026-10-1'이 '2026-9-1'
  /// 앞에 서서, 오래된 것부터 버리는 자리가 엉뚱한 날을 버린다.
  ///
  /// 하루 기록([nyang_history])이 쓰는 모양과도 같아야 한다. 시간과 결과를
  /// 견주려면 두 자료를 날짜로 맞붙여야 하는데, 모양이 다르면 맞붙지 않는다.
  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';

  /// 코치에게 넘길 한 줄. 안 물었거나 안 골랐으면 빈 문자열.
  ///
  /// 한동안 부르는 곳이 없었다. 아침에 물어서 답까지 받아놓고 코치에게는 안
  /// 보냈으니, 두세 시간뿐이라고 답한 사람에게 여섯 개짜리 하루를 짜주는 일이
  /// 생겼다. 물어놓고 안 듣는 것은 안 묻느니만 못하다.
  static Future<String> promptLine() async {
    final answer = await today();
    if (answer == null) return '';
    return answers[answer] ?? '';
  }

  static String _todayKey() => _dateKey(DateTime.now());
}
