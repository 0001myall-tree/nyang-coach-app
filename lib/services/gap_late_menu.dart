/// 하루가 얼마 안 남았을 때 틈새 코칭이 건네는 한 수.
///
/// 이른 시각에는 "이따 할 것의 앞 15분을 지금 해두자"가 통한다. 늦은 시각에는
/// 안 통한다 — 이따 할 시간이 없는데 미리 해두라는 말이 되기 때문이다. 그때는
/// 새로 시작시키는 대신 **오늘 남은 것을 건지는 쪽**이 맞다.
///
/// 여기 있는 것은 전부 **폰으로 되는 일**이다. 틈새 코칭은 사용자가 지금 어디
/// 있는지 모른다. "루틴 지금 해라"는 헬스장에 있어야 하는 사람에게 무리다.
library;

import 'package:flutter/foundation.dart';

/// 늦은 시각에 건넬 말과, 그 말이 가리키는 할 일.
@immutable
class GapLateSuggestion {
  const GapLateSuggestion({required this.body, this.taskId});

  final String body;

  /// 이 말이 부른 할 일. 부른 것이 없으면 null.
  ///
  /// 미리 만들어 둔 문장이 낡았는지 확인하는 데 쓴다 — 그 일을 이미 끝냈으면
  /// 다른 말이 나가야 한다.
  final String? taskId;
}

class GapLateMenu {
  const GapLateMenu._();

  /// 취침까지 이만큼 남았으면 늦은 쪽으로 본다.
  static const Duration lateWindow = Duration(hours: 4);

  /// 취침 시각을 안 정해둔 사람의 경계.
  ///
  /// 취침이 23시면 "4시간 전"이 정확히 19시다. 적어둔 사람과 안 적어둔 사람이
  /// 같은 자리에서 갈리도록 맞춘 값이다.
  static const int defaultLateHour = 19;

  /// 지금이 늦은 쪽인지.
  ///
  /// [bedtime]은 `HH:mm`. 자정을 넘겨 자는 사람은 그 취침이 다음 날 것이다 —
  /// 새벽 1시에 자는 사람에게 저녁 9시는 아직 네 시간이 남은 이른 시각이다.
  static bool isLate(DateTime at, {String? bedtime}) {
    final parsed = _parseHhMm(bedtime);
    if (parsed == null) return at.hour >= defaultLateHour;

    var sleepAt = DateTime(at.year, at.month, at.day, parsed.$1, parsed.$2);
    if (sleepAt.isBefore(at)) {
      sleepAt = sleepAt.add(const Duration(days: 1));
    }
    return sleepAt.difference(at) <= lateWindow;
  }

  /// 오늘 남은 것을 건지는 한 수. 건넬 말이 없으면 null.
  ///
  /// 위에서부터 맞는 것 하나만 고른다. 순서는 **얼마나 가까이 갔나**다 —
  /// 이미 손댔던 일이 제일 앞이고, 그다음이 적어는 뒀는데 아직 안 고른 것이다.
  static GapLateSuggestion? suggest({
    required List<dynamic> tasks,
    required List<dynamic> coreTasks,
  }) {
    // 하고 있는 사람에게 말을 거는 것은 방해다.
    if (tasks.whereType<Map>().any((t) => t['inProgress'] == true)) return null;

    final paused = _firstPaused(tasks);
    if (paused != null) {
      final name = paused['text']?.toString().trim() ?? '';
      final minutes = ((paused['elapsedSeconds'] as num?)?.toInt() ?? 0) ~/ 60;
      return GapLateSuggestion(
        body: minutes > 0
            ? "집사, '${_shorten(name)}' $minutes분 하다 멈췄다냥. 조금만 더 붙을까냥?"
            : "집사, '${_shorten(name)}' 하다 멈췄다냥. 조금만 더 붙을까냥?",
        taskId: paused['id']?.toString(),
      );
    }

    final remaining = tasks
        .whereType<Map>()
        .where((t) => t['done'] != true)
        .toList(growable: false);
    if (remaining.isEmpty) {
      // 오늘 건질 것이 없다. 이 시각에 "오늘 뭘 할지 정하자"는 늦었고, 내일
      // 것을 하나 정해두는 것은 밤에 할 만한 일이다. 기록 탭이 안정형에게
      // 하는 조언도 같다 — "끝낸 김에 내일 할 것 하나를 미리 적어두는 걸
      // 얹어봐".
      //
      // (오늘 것을 다 끝낸 사람에게는 애초에 이 카드가 안 뜬다. 다 한 사람에게
      // 여유 있냐고 묻는 것은 칭찬이 아니라 잔소리라서, 띄울지 정하는 쪽에서
      // 이미 걸러진다.)
      return const GapLateSuggestion(body: '집사, 내일 할 것 하나만 정해두고 잘까냥?');
    }

    // 핵심은 알림이 붙는다. 하나 짚어두는 것이 오늘 완료율에 제일 곧게 닿는다.
    if (coreTasks.whereType<Map>().isEmpty) {
      return const GapLateSuggestion(body: '집사, 핵심 하나만 짚고 갈까냥?');
    }

    return const GapLateSuggestion(body: '집사, 오늘 남은 것 중 하나만 골라볼까냥?');
  }

  /// 하다가 멈춘 일 하나. 없으면 null.
  ///
  /// `진행 중`과 다르다. 진행 중은 타이머가 도는 중이라 이 사람은 틈이 아니고,
  /// 멈춘 것은 오늘 가장 가까이 갔던 일이라 다시 붙는 문턱이 제일 낮다.
  static Map? _firstPaused(List<dynamic> tasks) {
    for (final item in tasks.whereType<Map>()) {
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) <= 0) continue;
      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      return item;
    }
    return null;
  }

  /// 카드 한 줄에 들어가는 만큼.
  static const int nameLimit = 12;

  static String _shorten(String text) =>
      text.length <= nameLimit ? text : '${text.substring(0, nameLimit)}…';

  static (int, int)? _parseHhMm(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }
}
