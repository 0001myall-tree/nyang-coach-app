import 'dart:convert';

/// 인지 에너지 최적화 기능의 발동 조건을 raw JSON(nyang_tasks)에서 직접 판정한다.
/// main_tab_screen.dart(백그라운드 알림 체크)와 chat_screen.dart(채팅 제안 체크)가
/// 각자 TasksScreen의 State에 접근할 수 없는 시점에 동일한 로직을 공유하기 위한 헬퍼.
class CognitiveOptimizeService {
  static bool isEligible(String? tasksRaw) {
    if (tasksRaw == null) return false;
    List<dynamic> notDone;
    try {
      notDone = (jsonDecode(tasksRaw) as List)
          .where((t) => t['done'] != true)
          .toList();
    } catch (_) {
      return false;
    }

    if (notDone.length >= 5) return true;

    final highLoadCount = notDone
        .where((t) => t['cognitiveLoad'] == '높음')
        .length;
    if (highLoadCount >= 2) return true;

    final modeCount = notDone
        .map((t) => t['cognitiveMode'])
        .whereType<String>()
        .toSet()
        .length;
    return modeCount >= 3;
  }
}
