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
/// 하루짜리다. 오늘 답이 내일의 답이 아니다.
class DayCapacityService {
  const DayCapacityService._();

  /// 이 기기에서만 뜻이 있는 값이라 'nyang_' 접두어를 쓰지 않는다.
  static const String _key = 'day_capacity';

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

  /// 잘 굴러가는 사람에게는 묻지 않는다. 자기 하루를 이미 맞춰 잡고 있는
  /// 사람에게 시간을 묻는 것은 검사에 가깝다.
  static const double asksBelowRate = 0.7;

  /// 물어볼 만한 사람인지. 최근 이레에 많이 잡은 날이 있고, 그날들이
  /// 실제로 잘 안 끝났을 때만.
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
    var bigDays = 0;
    var planned = 0;
    var done = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      if ('${date.year}-${date.month}-${date.day}' == today) continue;
      final tasks = (item['tasks'] as List?) ?? const [];
      if (tasks.length >= asksFromPlanCount) bigDays++;
      for (final task in tasks) {
        if (task is! Map) continue;
        planned++;
        if (task['done'] == true) done++;
      }
    }
    if (bigDays == 0 || planned == 0) return false;
    return done / planned < asksBelowRate;
  }

  /// 오늘 이미 물어봤거나 답했는지.
  static Future<bool> answeredToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key)?.startsWith(_todayKey()) ?? false;
  }

  static Future<void> save(String answer) async {
    if (!answers.containsKey(answer)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '${_todayKey()}|$answer');
  }

  /// 물어는 봤는데 답을 안 골랐을 때. 오늘은 다시 묻지 않는다.
  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, '${_todayKey()}|');
  }

  /// 오늘 고른 답. 없으면 null.
  static Future<String?> today() async {
    final prefs = await SharedPreferences.getInstance();
    final parts = (prefs.getString(_key) ?? '').split('|');
    if (parts.length != 2 || parts.first != _todayKey()) return null;
    return answers.containsKey(parts.last) ? parts.last : null;
  }

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

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
