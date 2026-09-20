import 'dart:convert';

/// 하루 기록을 만드는 단 한 곳.
///
/// 예전에는 다섯 곳이 각자 만들었다 — 채팅 화면, 할 일 화면(오늘치와 지난
/// 날), 자정 정리, 코치의 완료 처리. 전부 **같은 날 기록을 통째로 덮어쓰는데**
/// 담는 것이 달라서, 나중에 쓴 쪽이 이긴다. 채팅 쪽은 네 칸만 담았기 때문에
/// 거기서 덮이면 `inProgress`·`startedAt`·`completedAt`과 이정표가 통째로
/// 사라졌다.
///
/// **이 구멍은 만든 사람 눈에 안 보인다.** 할 일 화면을 자주 여는 사람은
/// 그쪽이 곧바로 온전한 기록으로 다시 써서 저절로 복구된다. 반대로 새로 온
/// 사람은 쏟아내기부터 시작 버튼까지 전부 채팅에서 끝내기 때문에 온전한 쪽이
/// 한 번도 돌지 않는다. 시작해서 붙잡고 있어도 기록에는 0%로 남았다.
///
/// 칸이 하나 늘 때 한쪽만 고쳐지는 일이 없도록, 줄을 만드는 일은 여기서만
/// 한다.
class DayRecordBuilder {
  const DayRecordBuilder._();

  /// 저장된 할 일 한 건(`nyang_tasks`의 한 줄)을 기록용 줄로 옮긴다.
  ///
  /// [task]는 `TaskItem.toJson()`이 뱉은 모양이거나 그것을 그대로 읽은
  /// 것이어야 한다. 시작 시각은 기록 쪽에서 `startedAt`으로 부른다.
  static Map<String, dynamic> taskEntry(
    Map task, {
    bool deferred = false,
  }) {
    final startedAt = task['inProgressAt'] ?? task['startedAt'];
    final completedAt = task['completedAt'];
    return {
      'text': task['text'],
      'done': task['done'] == true,
      'inProgress': task['inProgress'] == true,
      if (startedAt != null) 'startedAt': startedAt,
      if (completedAt != null) 'completedAt': completedAt,
      'category': task['category'] ?? 'today',
      'deferred': deferred,
    };
  }

  /// 오늘 몫으로 걸린 이정표 한 건.
  static Map<String, dynamic> milestoneEntry({
    required String text,
    required bool done,
    String? completedAt,
  }) => {
    'text': text,
    'done': done,
    if (completedAt != null) 'completedAt': completedAt,
    'category': 'milestone',
    'deferred': false,
  };

  /// 그날 몫으로 걸린 목표 이정표들. 저장된 그대로의 모양이다.
  ///
  /// 이정표는 할 일 목록(`nyang_tasks`)이 아니라 목표 안에 들어 있다. 그래서
  /// 할 일만 읽고 기록을 쓰면 **끝낸 이정표가 통째로 빠진다.** 채팅 화면이
  /// 오래 그랬고, 이정표를 하나 끝낸 날 채팅을 한마디 하면 그날이 도로 0이
  /// 됐다. 읽는 곳이 갈리지 않도록 고르는 일은 여기서만 한다.
  ///
  /// [visionsJson]은 `nyang_visions`에 담긴 그대로다. 없거나 깨져 있으면 빈
  /// 목록을 준다 — 기록을 쓰다 멈추는 것보다 이정표만 빠지는 편이 낫다.
  static List<Map<String, dynamic>> milestonesForDate(
    String? visionsJson,
    String dateKey,
  ) {
    if (visionsJson == null || visionsJson.isEmpty) return const [];

    final List<dynamic> visions;
    try {
      final decoded = jsonDecode(visionsJson);
      if (decoded is! List) return const [];
      visions = decoded;
    } catch (_) {
      return const [];
    }

    final found = <Map<String, dynamic>>[];
    for (final vision in visions) {
      if (vision is! Map) continue;
      final milestones = vision['milestones'];
      if (milestones is! List) continue;
      for (final milestone in milestones) {
        if (milestone is! Map) continue;
        if (milestone['date'] != dateKey) continue;
        found.add(Map<String, dynamic>.from(milestone));
      }
    }
    return found;
  }

  /// 루틴 id로 그 루틴의 주기를 찾는 표.
  ///
  /// [habitsJson]은 `nyang_habits`에 담긴 그대로다.
  static Map<String, String> habitFrequencyById(String? habitsJson) {
    if (habitsJson == null || habitsJson.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(habitsJson);
      if (decoded is! List) return const {};
      final table = <String, String>{};
      for (final habit in decoded) {
        if (habit is! Map) continue;
        final id = habit['id']?.toString();
        final freq = habit['freq']?.toString();
        if (id == null || freq == null) continue;
        table[id] = freq;
      }
      return table;
    } catch (_) {
      return const {};
    }
  }

  /// 이 할 일이 그날 달성률의 분모에 들어가는지.
  ///
  /// 주 몇 회짜리 루틴은 안 한 날에도 목록에 뜨기 때문에, 끝내지 않았으면
  /// 분모에서 뺀다. 안 그러면 주 2회 루틴이 나머지 닷새를 매일 깎는다.
  static bool countsTowardDailyCompletion(
    Map task,
    Map<String, String> habitFreqById,
  ) {
    final habitId = task['habitId']?.toString();
    if (habitId == null) return true;
    return habitFreqById[habitId] != 'weekly_count' || task['done'] == true;
  }

  /// 하루치 기록 한 벌.
  ///
  /// **여기가 기록을 만드는 유일한 자리다.** 예전에는 채팅 화면과 할 일 화면이
  /// 각자 만들어 같은 날 기록을 덮어썼는데, 담는 것이 달라서 나중에 쓴 쪽이
  /// 이겼다. 채팅 쪽은 시작 표시도 이정표도 빠뜨렸기 때문에, 채팅에서만 움직인
  /// 사람은 시작해서 붙잡고 있어도 0%로 남았다.
  ///
  /// [tasks]와 [deferred]는 저장된 할 일 모양, [milestones]는 [milestonesForDate]가
  /// 준 그대로다. 이월된 일은 그날 계획이 아니라 넘어온 것이라 분모에 넣지
  /// 않는다.
  static Map<String, dynamic> buildDayRecord({
    required String date,
    required List<Map<String, dynamic>> tasks,
    required List<Map<String, dynamic>> milestones,
    List<Map<String, dynamic>> deferred = const [],
    Map<String, String> habitFreqById = const {},
    DateTime? updatedAt,
  }) {
    final countableTasks = tasks
        .where((t) => countsTowardDailyCompletion(t, habitFreqById))
        .toList(growable: false);
    final doneTasks = countableTasks.where((t) => t['done'] == true);

    final entries = milestoneEntries(milestones);
    final doneMilestones = entries.where((m) => m['done'] == true);

    return {
      'date': date,
      'totalCount': countableTasks.length + entries.length,
      'doneCount': doneTasks.length + doneMilestones.length,
      'success': doneTasks.isNotEmpty || doneMilestones.isNotEmpty,
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
      'tasks': [
        ...tasks.map(taskEntry),
        ...entries,
        ...deferred.map((t) => taskEntry(t, deferred: true)),
      ],
    };
  }

  /// [milestonesForDate]가 준 이정표들을 기록용 줄로 옮긴 것.
  ///
  /// 이름이 빈 것은 뺀다 — 기록 탭에 빈 줄로 남아 분모만 키운다.
  static List<Map<String, dynamic>> milestoneEntries(
    List<Map<String, dynamic>> milestones,
  ) {
    final entries = <Map<String, dynamic>>[];
    for (final milestone in milestones) {
      final text = milestone['text']?.toString();
      if (text == null || text.isEmpty) continue;
      final done = milestone['done'] == true;
      entries.add(
        milestoneEntry(
          text: text,
          done: done,
          completedAt: done ? milestone['achievedDate']?.toString() : null,
        ),
      );
    }
    return entries;
  }
}
