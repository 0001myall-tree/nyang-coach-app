import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 움직인 날을 세는 자리.
///
/// 원래는 실행 유형에 이름을 붙이는 곳이기도 했다. 완료율 같은 숫자에 선을
/// 그어두고 어느 선에도 안 걸린 사람은 전부 "무난형"으로 보냈는데, 그 칸에는
/// 잘 굴러가는 사람과 문턱을 아슬아슬하게 비껴간 사람이 함께 들어갔다.
///
/// 더 큰 문제는 그 앞이었다. 적어둔 것의 1/4만 손대고 그건 다 끝내는 사람과,
/// 대부분 손대는데 1/3만 끝내는 사람이 숫자로는 똑같이 나왔다. 앞사람은 적는
/// 양을 줄여야 하고 뒷사람은 끝나는 크기로 쪼개야 하는데, 선 긋기는 둘을 같은
/// 칸에 넣었고 칸마다 처방이 달려 있어 처방까지 같이 틀렸다.
///
/// 그래서 이름 붙이는 일은 세 단계를 서로 견주는 [ExecutionFunnel]로 옮겼고,
/// 이름 목록은 [ExecutionTypeLabels]가 들고 있다. 새는 곳으로 이름을 붙이니
/// 안 걸린 사람을 담을 칸이 필요 없어져 무난형은 없앴다 — 세 군데 다 잘
/// 지나가면 안정형, 아직 셀 것이 모자라면 자유형이다.
///
/// 여기 남은 것은 "움직인 날" 하나뿐이다. 그건 완료율로는 안 보이는 값이라
/// 깔때기로 옮길 자리가 없다.
class ExecutionPatternService {
  const ExecutionPatternService._();

  /// 며칠을 볼지. 한 주면 요일 치우침 없이 리듬이 보인다.
  static const int windowDays = 7;

  /// 이번 이레와 지난 이레에 하루라도 해낸 날이 며칠인지.
  ///
  /// 편차형에게 진도를 재는 눈금이다. 완료율로는 안 보인다 — 하는 날에는
  /// 어차피 100%라, 손대는 날이 하루 늘어도 숫자가 그대로다.
  static Future<({int thisWeek, int lastWeek})> activeDayTrend() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_history');
    return (
      thisWeek: _activeDays(_records(raw)),
      lastWeek: _activeDays(_records(raw, weeksBack: 1)),
    );
  }

  static List<Map<String, dynamic>> _records(String? raw, {int weeksBack = 0}) {
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final from = DateTime.now().subtract(
      Duration(days: windowDays * (1 + weeksBack)),
    );
    final until = DateTime.now().subtract(
      Duration(days: windowDays * weeksBack),
    );
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      if (weeksBack > 0 && !date.isBefore(until)) continue;
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  /// 하루라도 해낸 날이 며칠인지. 편차형에게는 이게 진도를 재는 눈금이다.
  ///
  /// 완료율로는 나아지는 것이 안 보인다. 하는 날에는 어차피 100%라, 손대는
  /// 날이 하루 늘어도 완료율은 그대로다. 세어야 할 것은 며칠에 손댔느냐다.
  static int _activeDays(List<Map<String, dynamic>> records) {
    var count = 0;
    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map || task['done'] != true) continue;
        count++;
        break;
      }
    }
    return count;
  }
}
