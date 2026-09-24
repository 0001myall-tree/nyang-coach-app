/// 적극 코칭이 지금 말을 걸 일 하나를 고르는 자리.
///
/// 미완료가 다섯 개여도 개입은 하나다. 다섯 개에 각각 알림을 보내면 그건
/// 코칭이 아니라 알림 폭탄이고, 무엇부터 하라는 건지도 알 수 없다.
///
/// 고르는 일을 모델에게 맡기지 않는다. 무엇이 중요한지는 앱이 알 수 없고,
/// 추측해서 짚으면 그 사람의 오늘과 안 맞는 말이 나간다. 대신 **사용자가 이미
/// 남긴 신호**만 위에서부터 훑는다 — 그 시각에 하겠다고 약속했고, 시작 시각을
/// 적어뒀고, 손을 댔다 멈췄고, 핵심으로 별을 찍었다. 전부 사용자가 한 일이다.
///
/// 여기까지 걸리는 것이 없으면 **고르지 않는다.** 남은 일을 보여주고 사용자가
/// 고르게 한다. 핵심을 찍지 않는 사람이 많아 네 번째 칸은 자주 비는데, 그때 앱이
/// 잡무 하나를 골라 짚으면 이 설계가 지키려는 것이 통째로 무너진다.
///
/// 이 파일은 판정만 한다. 저장도, 알림도, 화면도, 모델 호출도 없다. 넘겨받은
/// 목록과 시각 하나로만 판단하므로 테스트에서 모든 경우를 지어 넣고 무엇을
/// 잡는지 눈으로 확인할 수 있다.
library;

/// 무엇을 보고 골랐는지. 고른 이유에 따라 건네는 말이 달라진다.
enum ActiveCoachingSignal {
  /// 지금은 말을 걸지 않는다.
  none,

  /// 사용자가 그 시각에 하겠다고 정해둔 일. 그 시각이 됐다.
  promised,

  /// 적어둔 시작 시각이 지났는데 아직 손도 안 댄 일.
  lateStart,

  /// 시작해뒀다 멈춘 일.
  paused,

  /// 핵심으로 찍어둔 일.
  core,

  /// 남은 일이 하나뿐이다.
  ///
  /// 고르지 않는다는 원칙은 여럿 중 하나를 앱이 짚지 않으려는 것이다. 하나뿐이면
  /// 고를 것이 없는데 "하나 정해볼까?"를 물으면 우습다.
  onlyLeft,

  /// 고를 신호가 없다. 남은 일을 보여주고 사용자가 고르게 한다.
  askUser,

  /// 하루를 닫기 전 마지막 한 번.
  ///
  /// 무엇을 잡을지는 위 사다리가 그대로 정한다. 밤이라고 다른 기준을 쓰면
  /// 그게 곧 앱이 중요도를 추측하는 것이 된다. 달라지는 것은 건네는 말과,
  /// 예산 밖이라는 것뿐이다.
  nightWrap,
}

/// 고른 결과.
class ActiveCoachingPick {
  const ActiveCoachingPick(
    this.signal, {
    this.task,
    this.candidates = const [],
  });

  const ActiveCoachingPick.none()
    : signal = ActiveCoachingSignal.none,
      task = null,
      candidates = const [];

  final ActiveCoachingSignal signal;

  /// 말을 걸 일. [ActiveCoachingSignal.none]과 [ActiveCoachingSignal.askUser]에는
  /// 없다.
  final Map? task;

  /// 사용자에게 보여줄 남은 일들. [ActiveCoachingSignal.askUser]일 때만 채워진다.
  ///
  /// 고르는 것은 사용자지만 목록을 추리는 것은 앱이다. 끝낸 일이나 지금 돌고
  /// 있는 일을 섞어 보여주면 고르는 일 자체가 번거로워진다.
  final List<Map> candidates;

  bool get isNone => signal == ActiveCoachingSignal.none;
  bool get needsUserPick => signal == ActiveCoachingSignal.askUser;

  /// 고른 일의 이름. 없으면 null.
  String? get taskText => task?['text']?.toString().trim();

  /// 고른 일의 id. 없으면 null.
  String? get taskId => task?['id']?.toString();
}

class ActiveCoachingTarget {
  const ActiveCoachingTarget._();

  /// 적어둔 시작 시각에서 이만큼 지나도록 손도 안 댔으면 말을 건다.
  ///
  /// 정각은 "잊지 않았지?"를 묻는 기존 시작 카드의 자리다. 이쪽은 "왜 못
  /// 시작했어?"를 묻는 자리라 같은 시각에 겹치면 안 된다.
  ///
  /// 딴짓 방지의 30분과 헷갈리기 쉬운데, 그쪽은 **시작을 누른 뒤** 30분이고
  /// 이쪽은 **적어둔 시각에서** 30분이다. 재는 시계가 다르다.
  static const Duration lateStartAfter = Duration(minutes: 30);

  /// 지금 말을 걸 일 하나.
  ///
  /// [promises]는 사용자가 "몇 시에 할게"라고 정해준 시각. 할 일 id로 찾는다.
  /// [settled]는 완료·오늘 안 함·다른 날로 이미 결정이 난 일들이다.
  /// [skipTaskId]는 바로 앞 개입에서 다룬 일. 한 번은 건너뛴다.
  ///
  /// 이 셋은 아직 저장되는 값이 아니다(2단계에서 만든다). 여기서는 넘겨받기만
  /// 한다 — 판정이 저장 방식을 모르는 편이 나중에 저장 자리를 옮겨도 안전하다.
  static ActiveCoachingPick pick({
    required List tasks,
    required DateTime now,
    List coreTasks = const [],
    Map<String, DateTime> promises = const {},
    Set<String> settled = const {},
    String? skipTaskId,
  }) {
    // 지금 뭔가 붙잡고 있는 사람에게 말을 거는 것은 도움이 아니라 방해다.
    // 다른 일이 아무리 밀려 있어도 이쪽이 먼저다.
    if (tasks.any(_isRunning)) return const ActiveCoachingPick.none();

    final pending = <Map>[];
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      // 약속은 그 시각에 가서 하는 것이라 지금 당겨 할 자리가 없다.
      if (item['category'] == 'schedule') continue;
      if ((item['text']?.toString().trim() ?? '').isEmpty) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (settled.contains(id)) continue;
      pending.add(item);
    }

    // 오늘 할 일을 다 끝냈거나, 애초에 적어둔 것이 없는 날이다. 다 한 사람에게
    // 말을 거는 것은 칭찬이 아니라 잔소리고, 아무것도 안 적은 사람에게 계획을
    // 세우자고 하는 것은 낮 알림과 아침 인사가 이미 맡고 있다.
    if (pending.isEmpty) return const ActiveCoachingPick.none();

    // 방금 밀어낸 일은 한 번 건너뛴다. 사다리는 상태가 안 바뀌면 같은 답을
    // 내놓기 때문에, 이것이 없으면 다섯 개 중 늘 같은 하나만 계속 찔린다.
    final usable = skipTaskId == null
        ? pending
        : pending
              .where((item) => item['id']?.toString() != skipTaskId)
              .toList(growable: false);
    // 건너뛰고 나니 남는 것이 없다. 보여줄 목록도 없으므로 물어볼 자리도 아니다.
    if (usable.isEmpty) return const ActiveCoachingPick.none();

    final promised = _promisedNow(usable, promises, now);
    if (promised != null) {
      return ActiveCoachingPick(ActiveCoachingSignal.promised, task: promised);
    }

    final late = _lateStart(usable, now);
    if (late != null) {
      return ActiveCoachingPick(ActiveCoachingSignal.lateStart, task: late);
    }

    final paused = _paused(usable);
    if (paused != null) {
      return ActiveCoachingPick(ActiveCoachingSignal.paused, task: paused);
    }

    final core = _core(usable, coreTasks, now);
    if (core != null) {
      return ActiveCoachingPick(ActiveCoachingSignal.core, task: core);
    }

    if (pending.length == 1) {
      final only = _onlyLeft(pending, promises, now);
      // 하나뿐인데 아직 부를 때가 아니면 조용히 있는다. 고를 것이 없는 사람에게
      // "하나 정해볼까?"를 묻는 것은 말이 안 된다.
      if (only == null) return const ActiveCoachingPick.none();
      return ActiveCoachingPick(ActiveCoachingSignal.onlyLeft, task: only);
    }

    // 사용자가 남긴 신호가 하나도 없다. 여기서 앱이 하나 골라 짚으면 그게 곧
    // 추측이다. 남은 일을 보여주고 고르게 한다.
    return ActiveCoachingPick(ActiveCoachingSignal.askUser, candidates: usable);
  }

  /// 오늘 남은 일이 하나뿐이면 그 일. 아니면 null.
  ///
  /// 시각을 적어둔 일은 여기서 잡지 않는다. 그 일은 시작 시각에서 30분이 지나면
  /// 자기 자리에서 걸리고, 그 전에 부르면 정해둔 시각보다 먼저 재촉하게 된다.
  /// 뒤로 약속해둔 일도 같은 이유로 둔다.
  static Map? _onlyLeft(
    List<Map> pending,
    Map<String, DateTime> promises,
    DateTime now,
  ) {
    final item = pending.single;
    if (_startAt(item, now) != null) return null;
    final promised = promises[item['id']?.toString() ?? ''];
    if (promised != null && promised.isAfter(now)) return null;
    return item;
  }

  /// 지금 돌고 있는 일인지.
  static bool _isRunning(Object? item) =>
      item is Map && item['done'] != true && item['inProgress'] == true;

  /// 약속한 시각이 된 일. 여럿이면 약속이 이른 것.
  static Map? _promisedNow(
    List<Map> items,
    Map<String, DateTime> promises,
    DateTime now,
  ) {
    final matched = <MapEntry<DateTime, Map>>[];
    for (final item in items) {
      final at = promises[item['id']?.toString() ?? ''];
      if (at == null) continue;
      if (at.isAfter(now)) continue;
      matched.add(MapEntry(at, item));
    }
    return _earliest(matched);
  }

  /// 적어둔 시작 시각에서 [lateStartAfter]가 지나도록 손도 안 댄 일.
  ///
  /// 창을 닫지 않는다. 기존 시작 카드는 한 시간이 지나면 그날치를 접는데,
  /// 적극 코칭은 결정이 날 때까지 따라붙는 기능이라 시간이 지났다고 놓지 않는다.
  /// 밤이나 매인 시간대를 피하는 것은 이 판정이 아니라 예산 층이 한다.
  static Map? _lateStart(List<Map> items, DateTime now) {
    final matched = <MapEntry<DateTime, Map>>[];
    for (final item in items) {
      if (_touched(item)) continue;
      final start = _startAt(item, now);
      if (start == null) continue;
      if (now.isBefore(start.add(lateStartAfter))) continue;
      matched.add(MapEntry(start, item));
    }
    return _earliest(matched);
  }

  /// 시작해뒀다 멈춘 일. 여럿이면 멈춘 지 오래된 것.
  ///
  /// 아예 손도 안 댄 일보다 문턱이 낮다. "다시 시작하자"가 "시작하자"보다
  /// 쉽고, 얼마나 했는지도 앱이 알고 있어 건넬 말에 쓸 수 있다.
  static Map? _paused(List<Map> items) {
    final matched = <MapEntry<DateTime, Map>>[];
    for (final item in items) {
      if (!_touched(item)) continue;
      // 멈춘 시각을 안 남긴 일도 있다. 그런 것은 맨 뒤로 보낸다 — 언제
      // 멈췄는지 모르는 일을, 두 시간 전에 멈춘 일보다 먼저 부를 근거가 없다.
      final at = _parse(item['pausedAt']) ?? _distantFuture;
      matched.add(MapEntry(at, item));
    }
    return _earliest(matched);
  }

  /// 오늘의 핵심 중 아직 그대로인 일.
  ///
  /// 시각을 적어둔 핵심은 그 시각 전에는 짚지 않는다. 저녁 8시에 하기로 한
  /// 일을 오후 1시에 "아직 그대로네"라고 하면 재촉이기 이전에 틀린 말이다.
  static Map? _core(List<Map> items, List coreTasks, DateTime now) {
    if (coreTasks.isEmpty) return null;

    final coreIds = <String>{};
    final coreTexts = <String>{};
    for (final item in coreTasks) {
      if (item is! Map) continue;
      final id = item['id']?.toString() ?? '';
      if (id.isNotEmpty) coreIds.add(id);
      final text = item['text']?.toString().trim() ?? '';
      if (text.isNotEmpty) coreTexts.add(text);
    }
    if (coreIds.isEmpty && coreTexts.isEmpty) return null;

    final matched = <MapEntry<DateTime, Map>>[];
    for (final item in items) {
      final id = item['id']?.toString() ?? '';
      final text = item['text']?.toString().trim() ?? '';
      if (!coreIds.contains(id) && !coreTexts.contains(text)) continue;
      final start = _startAt(item, now);
      if (start != null && now.isBefore(start)) continue;
      matched.add(MapEntry(start ?? _distantPast, item));
    }
    return _earliest(matched);
  }

  /// 시각이 이른 것 하나. 시각이 같으면 먼저 적은 것.
  ///
  /// 무작위나 점수 매기기는 쓰지 않는다. 같은 목록이면 늘 같은 답이 나와야
  /// 테스트로 확인할 수 있고, 사용자에게도 앱이 변덕스러워 보이지 않는다.
  static Map? _earliest(List<MapEntry<DateTime, Map>> matched) {
    if (matched.isEmpty) return null;
    matched.sort((a, b) {
      final byTime = a.key.compareTo(b.key);
      if (byTime != 0) return byTime;
      final aMade = _parse(a.value['createdAt']) ?? _distantFuture;
      final bMade = _parse(b.value['createdAt']) ?? _distantFuture;
      return aMade.compareTo(bMade);
    });
    return matched.first.value;
  }

  /// 한 번이라도 손댄 일인지.
  ///
  /// 눌렀다가 곧바로 멈춘 일은 쌓인 시간이 0으로 남는다. 시작 표시만 보고
  /// 넘기면 그런 일이 "아예 안 건드린 일"로 통과한다.
  static bool _touched(Map item) {
    if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) return true;
    for (final key in ['pausedAt', 'inProgressAt', 'runStartedAt']) {
      if ((item[key]?.toString().trim() ?? '').isNotEmpty) return true;
    }
    return false;
  }

  /// "HH:mm"을 오늘의 시각으로. 적어두지 않았으면 null.
  static DateTime? _startAt(Map item, DateTime now) {
    final parts = (item['timeStart']?.toString() ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  static DateTime? _parse(Object? raw) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static final DateTime _distantPast = DateTime.utc(1970);
  static final DateTime _distantFuture = DateTime.utc(9999);
}
