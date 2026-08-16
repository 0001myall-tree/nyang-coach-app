/// 낮에 코치가 먼저 말을 걸지, 건다면 뭐라고 할지 정한다.
///
/// 접속 여부가 아니라 오늘의 실행 상태를 본다. 안 들어왔다고 부르면 이미 잘
/// 하고 있는 사람에게도 같은 말이 가는데, 그건 부르는 쪽의 사정이지 그 사람의
/// 사정이 아니다.
///
/// 판단만 하고 보내지는 않는다. 순수 함수로 두어야 데이터를 넣어보며 확인할 수
/// 있다.
library;

import 'dart:math';

import 'repeat_keyword_service.dart';

enum NudgeKind {
  /// 오늘 등록된 일정이 없다.
  noPlan,

  /// 미룬 일을 오늘 다시 등록해두고 아직 시작하지 않았다.
  deferredAgain,

  /// 일정은 있는데 아직 아무것도 시작하지 않았다.
  notStarted,
}

class PreemptiveNudge {
  final NudgeKind kind;
  final String message;

  /// 문구에 이름을 넣은 일. 이름 없이 말한 경우엔 null.
  ///
  /// 채팅으로 이어붙일 때 이 일의 상태가 그대로인지 확인하는 데 쓴다.
  final String? taskName;

  const PreemptiveNudge({
    required this.kind,
    required this.message,
    this.taskName,
  });

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'message': message,
    if (taskName != null) 'taskName': taskName,
  };

  static PreemptiveNudge? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final message = json['message']?.toString() ?? '';
    if (message.isEmpty) return null;
    final kind = NudgeKind.values.where((k) => k.name == json['kind']);
    if (kind.isEmpty) return null;
    return PreemptiveNudge(
      kind: kind.first,
      message: message,
      taskName: json['taskName']?.toString(),
    );
  }
}

class PreemptiveNudgeService {
  /// 시작을 거드는 말. 계획을 세웠든 안 세웠든 통한다.
  static const List<String> notStartedMessages = [
    '오늘 냥이랑 하나라도 슬슬 시작해볼까?',
    '오늘 100점 말고 3분만 하자냥. 같이 시작해보자냥.',
    '하기 싫은 거 있으면 나한테 던져달라냥. 작게 줄여주겠다냥.',
    '집사야, 하기 싫을 땐 냥냥코치를 기억해달라냥.',
    '집사, 냥이가 기다리고 있다냥. 1분이면 된다냥',
  ];

  /// 계획을 세우자고 청하는 말. 계획이 비어 있을 때만 쓴다.
  static const List<String> planMessages = [
    '집사, 오늘 계획 아직 안 세웠냥?\n하나만 가볍게 잡아볼까?',
    '집사야, 오늘 뭐할지 하나만 같이 정해볼까?',
    '집사야, 오늘 할 일 하나만 가볍게 골라보자냥.',
    '집사, 오늘 할 일 같이 정해볼까냥?',
    '집사, 오늘 하루 냥이랑 가볍게 생각해볼까냥?',
    '집사, 오늘 할 일을 함께 정해볼까냥?',
  ];

  /// 계획이 비어 있는 날에 쓸 수 있는 말 전부.
  ///
  /// 계획을 청하는 말에 시작을 거드는 말까지 함께 쓴다. "3분만 하자"는 계획이
  /// 없는 사람에게도 그대로 통하기 때문이다. 반대는 안 된다 — 계획을 세워둔
  /// 사람에게 안 세웠냐고 물으면 그 순간 틀린 말이 된다.
  static List<String> get noPlanMessages => [
    ...planMessages,
    ...notStartedMessages,
  ];

  /// 미뤄놓고 다시 올린 일을 부를 때. `{{task}}`가 일정 이름 자리다.
  static const List<String> deferredAgainMessages = [
    '어제 미룬 \'{{task}}\', 오늘 다시 넣어뒀네.\n'
        '시작하기 좀 부담되냥? 냥냥이가 가볍게 줄여줄까?',
    '시작해! 시작해! \'{{task}}\' 시작해! 📣\n냥이가 응원한다냥!',
  ];

  /// 이름을 부르며 시작을 미는 말.
  ///
  /// 줄여주겠다는 말과 밀어주는 말을 섞어 둔다. 매번 부담을 낮춰주려 들면
  /// 그 일이 늘 어려운 일로 굳고, 매번 밀기만 하면 재촉이 된다.
  static const List<String> namedStartMessages = [
    '\'{{task}}\' 오늘 냥이랑 슬슬 시작해볼까?',
    '시작해! 시작해! \'{{task}}\' 시작해! 📣\n냥이가 응원한다냥!',
  ];

  static String _pick(List<String> pool) => pool[Random().nextInt(pool.length)];

  static String _fill(List<String> pool, String taskName) =>
      _pick(pool).replaceAll('{{task}}', taskName);

  /// 오늘 무엇이든 손을 댔는지.
  ///
  /// 완료, 시작 표시, 타이머로 흐른 시간 중 하나라도 있으면 손을 댄 것이다.
  /// 타이머만 돌리고 시작 표시를 안 누른 경우가 있어 셋을 다 본다.
  static bool touchedToday(List<dynamic> todayTasks) {
    return todayTasks.whereType<Map>().any((task) {
      if (task['done'] == true) return true;
      if (task['inProgress'] == true) return true;
      if (task['inProgressAt'] != null) return true;
      return ((task['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0;
    });
  }

  static bool _isHabit(Map task) =>
      task['habitId'] != null || task['category'] == 'habit';

  /// 자정 리셋이 습관을 자동으로 채워 넣어서, 습관까지 세면 '계획 없음'이
  /// 영영 걸리지 않는다. 사용자가 직접 올린 것만 계획으로 본다.
  static List<Map> _plannedTasks(List<dynamic> todayTasks) => todayTasks
      .whereType<Map>()
      .where((task) => !_isHabit(task))
      .toList(growable: false);

  static String? _text(Map? task) {
    final text = task?['text']?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// 지금 부를지, 부른다면 뭐라고 할지. 부를 이유가 없으면 null.
  ///
  /// [todayTasks]는 오늘 할 일, [coreTasks]는 핵심으로 찍어둔 것,
  /// [history]는 하루 기록들이다.
  static PreemptiveNudge? decide({
    required List<dynamic> todayTasks,
    required List<dynamic> coreTasks,
    required List<dynamic> history,
  }) {
    // 이미 움직이고 있는 사람에게는 말을 걸지 않는다. 격려도 참견이 된다.
    if (touchedToday(todayTasks)) return null;

    final planned = _plannedTasks(todayTasks);
    if (planned.isEmpty) {
      return PreemptiveNudge(
        kind: NudgeKind.noPlan,
        message: _pick(noPlanMessages),
      );
    }

    // 미뤄놓고 오늘 다시 올린 일이 있으면 그게 오늘의 이야기다. 다시 적었다는
    // 것 자체가 하려는 마음인데 손이 안 가는 상태라, 부담을 줄여주는 쪽이 맞다.
    final deferred = planned.where(
      (task) => ((task['deferredCount'] as num?)?.toInt() ?? 0) >= 1,
    );
    if (deferred.isNotEmpty) {
      final name = _text(deferred.first);
      if (name != null) {
        return PreemptiveNudge(
          kind: NudgeKind.deferredAgain,
          message: _fill(deferredAgainMessages, name),
          taskName: name,
        );
      }
    }

    final name = _pickTaskToMention(
      todayTasks: todayTasks,
      planned: planned,
      coreTasks: coreTasks,
      history: history,
    );
    return PreemptiveNudge(
      kind: NudgeKind.notStarted,
      message: name == null
          ? _pick(notStartedMessages)
          : _fill(namedStartMessages, name),
      taskName: name,
    );
  }

  /// 이름을 넣어 부를 일 하나. 핵심 → 습관 → 요즘 반복되는 일 순으로 본다.
  ///
  /// 셋 다 없으면 null을 주고 이름 없이 부른다. 아무 일이나 집어서 부르면
  /// 왜 하필 그것인지 설명할 수 없고, 그러면 참견이 된다.
  static String? _pickTaskToMention({
    required List<dynamic> todayTasks,
    required List<Map> planned,
    required List<dynamic> coreTasks,
    required List<dynamic> history,
  }) {
    final plannedNames = planned.map(_text).whereType<String>().toSet();

    for (final core in coreTasks.whereType<Map>()) {
      final name = _text(core);
      if (name != null && plannedNames.contains(name)) return name;
    }

    for (final task in todayTasks.whereType<Map>()) {
      if (!_isHabit(task)) continue;
      final name = _text(task);
      if (name != null) return name;
    }

    final repeats = RepeatKeywordService.analyze(history);
    if (repeats.isEmpty) return null;
    for (final name in plannedNames) {
      if (RepeatKeywordService.matchingKeyword(name, repeats) != null) {
        return name;
      }
    }
    return null;
  }
}
