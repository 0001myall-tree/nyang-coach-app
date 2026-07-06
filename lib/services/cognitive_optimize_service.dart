import 'dart:convert';

/// 인지 에너지 최적화 기능의 발동 조건을 raw JSON(nyang_tasks)에서 직접 판정한다.
/// main_tab_screen.dart(백그라운드 알림 체크)와 chat_screen.dart(채팅 제안 체크)가
/// 각자 TasksScreen의 State에 접근할 수 없는 시점에 동일한 로직을 공유하기 위한 헬퍼.
class CognitiveOptimizeService {
  static List<dynamic>? _notDoneTasks(String? tasksRaw) {
    if (tasksRaw == null) return null;
    try {
      return (jsonDecode(tasksRaw) as List)
          .where((t) => t['done'] != true)
          .toList();
    } catch (_) {
      return null;
    }
  }

  static bool isEligible(String? tasksRaw) {
    final notDone = _notDoneTasks(tasksRaw);
    if (notDone == null) return false;
    return _highLoadCount(notDone) >= 3;
  }

  static int _highLoadCount(List<dynamic> notDone) =>
      notDone.where((t) => t['cognitiveLoad'] == '높음').length;

  /// "🧠 고인지 작업이 n개 감지됐어요" 안내 문구에 쓸 개수.
  static int highLoadCount(String? tasksRaw) {
    final notDone = _notDoneTasks(tasksRaw);
    if (notDone == null) return 0;
    return _highLoadCount(notDone);
  }
}
