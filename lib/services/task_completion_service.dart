import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reset_service.dart';

/// 할 일 하나를 완료로 만드는 일을 화면 밖에서 처리한다.
///
/// 원래 이 일은 플래너 화면 안에만 있었다. 그래서 앱 밖에서 완료를 눌러도
/// 플래너를 열기 전까지는 아무 일도 일어나지 않았다 — 채팅만 하다 나가면
/// 코치는 계속 "그거 아직 안 했네요"라고 했다.
///
/// 여기서는 저장된 데이터만 보고 고친다. 화면도, 메모리에 올라간 목록도
/// 필요 없다. 그래서 앱이 막 켜지는 순간에도, 플래너가 닫혀 있어도 돌아간다.
///
/// 손대는 곳은 넷이다.
/// - `nyang_tasks` (또는 지난 날은 `nyang_today_tasks_by_date`): 완료 표시
/// - `nyang_core_tasks`: 같은 일이 핵심 일정에도 올라가 있으면 함께
/// - `nyang_habit_logs`: 습관이면 그날 도장
/// - `nyang_history`: 그날 기록의 완료 개수 (기록 탭과 연속 달성이 여기서 나온다)
class TaskCompletionService {
  static const String tasksKey = 'nyang_tasks';
  static const String coreTasksKey = 'nyang_core_tasks';
  static const String habitLogsKey = 'nyang_habit_logs';
  static const String habitsKey = 'nyang_habits';
  static const String historyKey = 'nyang_history';

  /// 저장소가 마지막으로 바뀐 시각.
  ///
  /// 화면이 열려 있는 채로 밖에서 데이터가 바뀔 수 있다. 그 화면이 메모리에
  /// 든 옛 목록을 그대로 저장하면 방금 한 완료가 되돌아간다. 화면은 돌아올 때
  /// 이 시각을 보고 자기가 읽어둔 것보다 새로우면 다시 읽는다.
  ///
  /// 이름이 'nyang_'으로 시작하지 않는다. 그 접두어는 클라우드가 통째로
  /// 덮어쓰기 때문에, 이 기기에서 언제 바뀌었는지를 담기에 맞지 않는다.
  static const String changedAtKey = 'task_store_changed_at';

  /// 완료로 바꾼다. 이미 완료였거나 그런 일이 없으면 false.
  static Future<bool> completeStoredTask({
    required String taskId,
    DateTime? at,
  }) => _apply(taskId: taskId, done: true, at: at ?? DateTime.now());

  /// 진행 중 표시만 내린다. 타이머형은 흘러간 만큼을 누적에 얹고 멈춘다.
  static Future<bool> pauseStoredTask({required String taskId}) =>
      _apply(taskId: taskId, done: false, at: DateTime.now());

  static Future<bool> _apply({
    required String taskId,
    required bool done,
    required DateTime at,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    // 오늘 목록에서 먼저 찾고, 없으면 아직 들고 있는 지난 날들을 본다.
    // 밤에 눌러두고 며칠 뒤에 앱을 열면 그 일정은 이미 어제 자리로 넘어가 있다.
    final today = _todayKey(at);
    if (await _applyToToday(prefs, taskId: taskId, done: done, at: at)) {
      await _markChanged(prefs, at);
      return true;
    }
    if (!done) return false;
    if (await _applyToPastDays(prefs, taskId: taskId, at: at, today: today)) {
      await _markChanged(prefs, at);
      return true;
    }
    return false;
  }

  static Future<bool> _applyToToday(
    SharedPreferences prefs, {
    required String taskId,
    required bool done,
    required DateTime at,
  }) async {
    final tasks = _decodeList(prefs.getString(tasksKey));
    final task = _findById(tasks, taskId);
    if (task == null) return false;

    final dateKeyForDone = prefs.getString('nyang_last_date') ?? _todayKey(at);
    if (done && task['done'] == true) {
      // 네이티브가 앱 밖에서 먼저 표시해둔 경우다. 바꿀 것은 없지만 그날 기록은
      // 여기서 정확히 다시 센다 — 네이티브는 주 n회 습관 같은 걸 가릴 수 없다.
      await _rewriteRecord(prefs, dateKey: dateKeyForDone, tasks: tasks, at: at);
      return false;
    }

    _markTask(task, done: done, at: at);
    await prefs.setString(tasksKey, jsonEncode(tasks));
    if (!done) return true;

    await _mirrorCoreTask(prefs, taskId: taskId, at: at);
    await _stampHabit(prefs, task: task, dateKey: dateKeyForDone, at: at);
    await _rewriteRecord(prefs, dateKey: dateKeyForDone, tasks: tasks, at: at);
    return true;
  }

  /// 아직 보관 중인 지난 날에서 찾아 완료로 바꾼다.
  static Future<bool> _applyToPastDays(
    SharedPreferences prefs, {
    required String taskId,
    required DateTime at,
    required String today,
  }) async {
    final raw = prefs.getString(DailyResetService.plannedTasksByDateKey);
    if (raw == null || raw.isEmpty) return false;

    Map<String, dynamic> byDate;
    try {
      byDate = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return false;
    }

    for (final entry in byDate.entries) {
      // 미래에 세워둔 계획은 건드리지 않는다. 아직 오지 않은 날이다.
      if (entry.key.compareTo(today) >= 0) continue;
      final dayTasks = _asList(entry.value);
      final task = _findById(dayTasks, taskId);
      if (task == null) continue;
      if (task['done'] == true) return false;

      _markTask(task, done: true, at: at);
      byDate[entry.key] = dayTasks;
      await prefs.setString(
        DailyResetService.plannedTasksByDateKey,
        jsonEncode(byDate),
      );
      await _stampHabit(prefs, task: task, dateKey: entry.key, at: at);
      await _rewriteRecord(
        prefs,
        dateKey: entry.key,
        tasks: dayTasks,
        at: at,
      );
      return true;
    }
    return false;
  }

  static void _markTask(
    Map<String, dynamic> task, {
    required bool done,
    required DateTime at,
  }) {
    final elapsed = _elapsedSeconds(task, at);
    task['inProgress'] = false;
    task.remove('runStartedAt');
    task['elapsedSeconds'] = elapsed;
    if (!done) return;
    task['done'] = true;
    task['actualSeconds'] = elapsed;
    task['completedAt'] = at.toIso8601String();
  }

  /// 쌓인 시간 + 지금 돌고 있는 구간.
  static int _elapsedSeconds(Map<String, dynamic> task, DateTime at) {
    var elapsed = (task['elapsedSeconds'] as num?)?.toInt() ?? 0;
    final startedAt = DateTime.tryParse(task['runStartedAt']?.toString() ?? '');
    if (startedAt != null) {
      final ran = at.difference(startedAt).inSeconds;
      if (ran > 0) elapsed += ran;
    }
    return elapsed;
  }

  static Future<void> _mirrorCoreTask(
    SharedPreferences prefs, {
    required String taskId,
    required DateTime at,
  }) async {
    final core = _decodeList(prefs.getString(coreTasksKey));
    final task = _findById(core, taskId);
    if (task == null) return;
    task['done'] = true;
    task['completedAt'] = at.toIso8601String();
    await prefs.setString(coreTasksKey, jsonEncode(core));
  }

  /// 습관이면 그날 도장을 찍는다. 이미 찍혀 있으면 덮지 않는다 —
  /// 앱에서 개수나 시간까지 적어둔 기록을 맨몸 기록으로 지우면 안 된다.
  static Future<void> _stampHabit(
    SharedPreferences prefs, {
    required Map<String, dynamic> task,
    required String dateKey,
    required DateTime at,
  }) async {
    final habitId = task['habitId']?.toString();
    if (habitId == null || habitId.isEmpty || habitId == 'null') return;

    Map<String, dynamic> logs;
    try {
      logs = Map<String, dynamic>.from(
        jsonDecode(prefs.getString(habitLogsKey) ?? '{}') as Map,
      );
    } catch (_) {
      logs = {};
    }
    final forHabit = Map<String, dynamic>.from(
      (logs[habitId] as Map?) ?? const {},
    );
    if (forHabit.containsKey(dateKey)) return;

    forHabit[dateKey] = {
      'done': true,
      'status': 'done',
      'completedAt': at.toIso8601String(),
    };
    logs[habitId] = forHabit;
    await prefs.setString(habitLogsKey, jsonEncode(logs));
  }

  /// 그날 기록을 목록에서 다시 센다.
  ///
  /// 기록 탭과 코치가 말하는 "연속 달성"이 이 숫자에서 나온다. 개수를 하나
  /// 올리는 대신 목록을 통째로 다시 세므로, 몇 번을 불러도 같은 값이 된다.
  /// 마일스톤과 이월 항목은 목록에 없으므로 기록에 있던 그대로 둔다.
  static Future<void> _rewriteRecord(
    SharedPreferences prefs, {
    required String dateKey,
    required List<Map<String, dynamic>> tasks,
    required DateTime at,
  }) async {
    List<Map<String, dynamic>> history;
    try {
      history = _decodeList(prefs.getString(historyKey));
    } catch (_) {
      return;
    }

    final idx = history.indexWhere((h) => h['date'] == dateKey);
    final previous = idx >= 0 ? history[idx] : <String, dynamic>{};
    final kept = _asList(previous['tasks'])
        .where(
          (entry) =>
              entry['deferred'] == true || entry['category'] == 'milestone',
        )
        .toList(growable: false);
    final keptDone = kept.where((entry) => entry['done'] == true).length;

    final countable = tasks
        .where((task) => _countsTowardDailyCompletion(prefs, task))
        .toList(growable: false);
    final doneCount = countable.where((task) => task['done'] == true).length;
    final milestones = kept
        .where((entry) => entry['category'] == 'milestone')
        .length;

    final record = <String, dynamic>{
      'date': dateKey,
      'totalCount': countable.length + milestones,
      'doneCount': doneCount + keptDone,
      'success': doneCount + keptDone > 0,
      'isVacation': previous['isVacation'] ?? false,
      'updatedAt': at.toIso8601String(),
      'tasks': [
        ...tasks.map(
          (task) => {
            'text': task['text'],
            'done': task['done'] == true,
            'inProgress': task['inProgress'] == true,
            if (task['inProgressAt'] != null) 'startedAt': task['inProgressAt'],
            if (task['completedAt'] != null) 'completedAt': task['completedAt'],
            'category': task['category'],
            'deferred': false,
          },
        ),
        ...kept,
      ],
    };

    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
      history.sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    }
    await prefs.setString(historyKey, jsonEncode(history));
  }

  /// 주 n회 습관은 실제로 한 날만 그날의 분모에 넣는다. 안 그러면 하지 않기로
  /// 한 날까지 미완료로 잡혀 완료율이 늘 낮게 나온다.
  static bool _countsTowardDailyCompletion(
    SharedPreferences prefs,
    Map<String, dynamic> task,
  ) {
    final habitId = task['habitId']?.toString();
    if (habitId == null || habitId.isEmpty || habitId == 'null') return true;
    final habits = _decodeList(prefs.getString(habitsKey));
    final habit = _findById(habits, habitId);
    if (habit == null) return true;
    if (habit['freq']?.toString() != 'weekly_count') return true;
    return task['done'] == true;
  }

  static Future<void> _markChanged(SharedPreferences prefs, DateTime at) =>
      prefs.setString(changedAtKey, at.toIso8601String());

  /// 저장소가 [since] 뒤에 바뀌었는지. 화면이 다시 읽을지 정하는 데 쓴다.
  static Future<bool> changedSince(DateTime since) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(changedAtKey);
    if (raw == null) return false;
    final at = DateTime.tryParse(raw);
    return at != null && at.isAfter(since);
  }

  /// 앱 밖에서 무언가 데이터를 고쳤다고 알린다(네이티브가 직접 쓴 경우 등).
  static Future<void> markChangedNow() async {
    final prefs = await SharedPreferences.getInstance();
    await _markChanged(prefs, DateTime.now());
  }

  static String _todayKey(DateTime at) =>
      '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  static Map<String, dynamic>? _findById(
    List<Map<String, dynamic>> items,
    String id,
  ) {
    for (final item in items) {
      if (item['id']?.toString() == id) return item;
    }
    return null;
  }
}
