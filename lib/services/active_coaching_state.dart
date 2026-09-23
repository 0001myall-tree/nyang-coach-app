/// 적극 코칭이 한 일과 사용자가 답한 것을 적어두는 자리.
///
/// 이게 없으면 따라붙을 수가 없다. 지금 있는 알림들은 상태를 안 남겨서, 같은
/// 조건이면 같은 말을 처음부터 다시 한다 — 어제 왜 못 했는지도, 몇 시에 하기로
/// 했는지도, 몇 번째 미루는 중인지도 모른 채 "아직이네"만 반복한다.
///
/// 두 벌로 나눠 둔다.
///
/// - **할 일별 추적**: 약속 시각·이유·횟수·결정. 기기를 바꿔도 따라와야 하므로
///   'nyang_' 접두어를 붙여 클라우드에 실린다.
/// - **사용자 예산**: 마지막으로 말 건 시각·오늘 몇 번·연속 무응답. 이 기기에서
///   방금 일어난 사실이라 접두어 없이 두고, 클라우드가 덮지 못하게 한다.
///
/// 둘 다 **하루치**다. 날짜가 바뀌면 통째로 비운다. 추적을 자정 너머로 끌고 가지
/// 않기로 했고, 그 전에 하루를 닫는 말을 한 번 건네는 것이 밤 정리 개입이다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 사용자가 그 일을 어떻게 하기로 했는지.
///
/// [none]이 아니면 그날 그 일에는 더 말 걸지 않는다. 사용자가 내린 결정이라
/// 다시 묻는 것은 그 말을 못 들은 것이 된다.
enum ActiveCoachingDecision {
  none,

  /// 했다.
  done,

  /// 오늘은 안 하기로.
  notToday,

  /// 다른 날로 옮기기로.
  moved,
}

/// 할 일 하나에 쌓인 추적.
class TaskTracking {
  const TaskTracking({
    this.promisedAt,
    this.originalStart,
    this.lastNudgedAt,
    this.nudges = 0,
    this.reason,
    this.decision = ActiveCoachingDecision.none,
    this.pickedByUser = false,
  });

  /// 사용자가 "몇 시에 할게"라고 정해준 시각.
  final DateTime? promisedAt;

  /// 그 시각을 할 일에 넣기 전에 적혀 있던 시작 시각("15:00").
  ///
  /// 덮어쓰기만 하면 "3시에 하기로 했다가 못 했다"가 사라진다. 세 번째 미루는
  /// 사람에게는 다른 말을 해야 하므로 원래 값을 들고 있는다.
  final String? originalStart;

  /// 이 일로 마지막에 말 건 시각.
  final DateTime? lastNudgedAt;

  /// 이 일로 몇 번 말 걸었는지.
  final int nudges;

  /// 사용자가 고른 "왜 못 했는지". 다음 한 수를 고르는 근거라 프롬프트까지 간다.
  final String? reason;

  final ActiveCoachingDecision decision;

  /// 사용자가 목록에서 직접 고른 일인지.
  ///
  /// 본인이 "이건 할 수 있다"고 말한 일이라, 다음에 개입할 때 먼저 본다.
  final bool pickedByUser;

  bool get isSettled => decision != ActiveCoachingDecision.none;

  TaskTracking copyWith({
    DateTime? promisedAt,
    String? originalStart,
    DateTime? lastNudgedAt,
    int? nudges,
    String? reason,
    ActiveCoachingDecision? decision,
    bool? pickedByUser,
  }) => TaskTracking(
    promisedAt: promisedAt ?? this.promisedAt,
    originalStart: originalStart ?? this.originalStart,
    lastNudgedAt: lastNudgedAt ?? this.lastNudgedAt,
    nudges: nudges ?? this.nudges,
    reason: reason ?? this.reason,
    decision: decision ?? this.decision,
    pickedByUser: pickedByUser ?? this.pickedByUser,
  );

  Map<String, dynamic> toJson() => {
    if (promisedAt != null) 'promisedAt': promisedAt!.toIso8601String(),
    if (originalStart != null) 'originalStart': originalStart,
    if (lastNudgedAt != null) 'lastNudgedAt': lastNudgedAt!.toIso8601String(),
    if (nudges > 0) 'nudges': nudges,
    if (reason != null && reason!.isNotEmpty) 'reason': reason,
    if (decision != ActiveCoachingDecision.none) 'decision': decision.name,
    if (pickedByUser) 'pickedByUser': true,
  };

  factory TaskTracking.fromJson(Map json) => TaskTracking(
    promisedAt: _parseTime(json['promisedAt']),
    originalStart: json['originalStart']?.toString(),
    lastNudgedAt: _parseTime(json['lastNudgedAt']),
    nudges: (json['nudges'] as num?)?.toInt() ?? 0,
    reason: json['reason']?.toString(),
    decision: ActiveCoachingDecision.values.firstWhere(
      (value) => value.name == json['decision']?.toString(),
      orElse: () => ActiveCoachingDecision.none,
    ),
    pickedByUser: json['pickedByUser'] == true,
  );
}

DateTime? _parseTime(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

/// 하루치 추적 전부.
class ActiveCoachingDay {
  const ActiveCoachingDay({required this.date, this.tasks = const {}});

  /// 'yyyy-MM-dd'.
  final String date;

  final Map<String, TaskTracking> tasks;

  TaskTracking of(String taskId) => tasks[taskId] ?? const TaskTracking();

  /// 사다리에 그대로 넘기는 약속 시각들.
  Map<String, DateTime> get promises => {
    for (final entry in tasks.entries)
      if (entry.value.promisedAt != null && !entry.value.isSettled)
        entry.key: entry.value.promisedAt!,
  };

  /// 사다리에 그대로 넘기는 "이미 결정이 난 일"들.
  Set<String> get settled => {
    for (final entry in tasks.entries)
      if (entry.value.isSettled) entry.key,
  };

  ActiveCoachingDay put(String taskId, TaskTracking tracking) =>
      ActiveCoachingDay(date: date, tasks: {...tasks, taskId: tracking});

  /// 오늘 목록에 없는 일은 버린다.
  ///
  /// 지운 일이나 다른 날로 옮긴 일이 계속 쌓이면, 자정에 비우기 전까지 하루치가
  /// 실제 목록보다 커진다. 그 안의 약속 시각은 부를 일이 없는데도 사다리를 탄다.
  ActiveCoachingDay pruneMissing(Set<String> liveTaskIds) => ActiveCoachingDay(
    date: date,
    tasks: {
      for (final entry in tasks.entries)
        if (liveTaskIds.contains(entry.key)) entry.key: entry.value,
    },
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    'tasks': {
      for (final entry in tasks.entries)
        if (entry.value.toJson().isNotEmpty) entry.key: entry.value.toJson(),
    },
  };

  factory ActiveCoachingDay.fromJson(Map json, {required String today}) {
    // 어제 것이면 없는 셈 친다. 자정을 넘긴 추적은 들고 가지 않는다.
    if (json['date']?.toString() != today) {
      return ActiveCoachingDay(date: today);
    }
    final raw = json['tasks'];
    if (raw is! Map) return ActiveCoachingDay(date: today);
    return ActiveCoachingDay(
      date: today,
      tasks: {
        for (final entry in raw.entries)
          if (entry.value is Map)
            entry.key.toString(): TaskTracking.fromJson(entry.value as Map),
      },
    );
  }
}

/// 사용자 한 사람의 개입 예산.
///
/// 할 일이 몇 개든 여기 적힌 것이 총량이다. 미완료가 다섯 개라고 다섯 번
/// 말 걸면 그건 코칭이 아니다.
class ActiveCoachingBudget {
  const ActiveCoachingBudget({
    required this.date,
    this.lastSpokeAt,
    this.spokenToday = 0,
    this.noReplyStreak = 0,
    this.lastTaskId,
    this.heldOffTaskId,
  });

  /// 개입과 개입 사이.
  static const Duration interval = Duration(hours: 2);

  /// 연달아 무응답이 쌓였을 때의 간격.
  ///
  /// 아예 접지는 않는다. 무응답의 뜻이 하나가 아니다 — 봤는데 무시한 것일 수도,
  /// 아예 못 본 것일 수도 있는데 구분할 방법이 없다. "오늘은 쉬는 날"이라고
  /// 단정하면 오후 내내 못 봤다가 저녁에 폰을 잡는 사람을 통째로 놓친다.
  static const Duration quietInterval = Duration(hours: 4);

  /// 간격을 벌리기 시작하는 무응답 횟수.
  static const int noReplyThreshold = 3;

  /// 하루에 몇 번까지.
  ///
  /// 아침 9시부터 밤 10시까지 열세 시간이라 두 시간 간격이면 최대 예닐곱 번이다.
  /// 간격이 사실상 지켜주지만, 간격을 손볼 때 총량이 같이 늘어나지 않게 못 박는다.
  static const int dailyCap = 7;

  /// 이 시각부터는 말 걸지 않는다. 밤 정리 개입은 이 예산 밖이라 걸리지 않는다.
  static const int quietFromHour = 22;

  final String date;
  final DateTime? lastSpokeAt;
  final int spokenToday;
  final int noReplyStreak;

  /// 바로 앞 개입에서 다룬 일. 사다리가 한 번 건너뛴다.
  final String? lastTaskId;

  /// 매인 시간대라 미뤄둔 개입 하나.
  ///
  /// 하나만 들고 간다. 퇴근하자마자 밀린 것이 세 번 연달아 오면 그게 제일 나쁘다.
  final String? heldOffTaskId;

  Duration get currentInterval =>
      noReplyStreak >= noReplyThreshold ? quietInterval : interval;

  /// 지금 말을 걸어도 되는지. 밤 정리 개입과 약속 시각 확인은 이걸 묻지 않는다.
  bool allows(DateTime now) {
    if (now.hour >= quietFromHour) return false;
    if (spokenToday >= dailyCap) return false;
    final last = lastSpokeAt;
    if (last == null) return true;
    return now.difference(last) >= currentInterval;
  }

  /// 말을 걸었다고 적는다.
  ///
  /// [countsTowardCap]이 거짓이면 총량에서 빼지만 시각은 남긴다. 약속 시각
  /// 확인은 사용자가 정한 것이라 총량에 넣지 않지만, 그 직후에 다른 개입이
  /// 곧바로 따라붙으면 그건 두 번 말 건 것이다.
  ActiveCoachingBudget spoke(
    DateTime now, {
    String? taskId,
    bool countsTowardCap = true,
  }) => ActiveCoachingBudget(
    date: date,
    lastSpokeAt: now,
    spokenToday: spokenToday + (countsTowardCap ? 1 : 0),
    noReplyStreak: noReplyStreak,
    lastTaskId: taskId ?? lastTaskId,
    heldOffTaskId: heldOffTaskId,
  );

  /// 답이 없었다고 적는다.
  ActiveCoachingBudget noReply() => _copyWith(noReplyStreak: noReplyStreak + 1);

  /// 한 번이라도 답했으면 간격을 되돌린다.
  ActiveCoachingBudget replied() => _copyWith(noReplyStreak: 0);

  /// 매인 시간대라 미뤄둔다. 이미 들고 있는 것은 새것으로 바뀐다.
  ActiveCoachingBudget holdOff(String taskId) =>
      _copyWith(heldOffTaskId: taskId);

  ActiveCoachingBudget clearHeldOff() => ActiveCoachingBudget(
    date: date,
    lastSpokeAt: lastSpokeAt,
    spokenToday: spokenToday,
    noReplyStreak: noReplyStreak,
    lastTaskId: lastTaskId,
  );

  ActiveCoachingBudget _copyWith({
    DateTime? lastSpokeAt,
    int? spokenToday,
    int? noReplyStreak,
    String? lastTaskId,
    String? heldOffTaskId,
  }) => ActiveCoachingBudget(
    date: date,
    lastSpokeAt: lastSpokeAt ?? this.lastSpokeAt,
    spokenToday: spokenToday ?? this.spokenToday,
    noReplyStreak: noReplyStreak ?? this.noReplyStreak,
    lastTaskId: lastTaskId ?? this.lastTaskId,
    heldOffTaskId: heldOffTaskId ?? this.heldOffTaskId,
  );

  Map<String, dynamic> toJson() => {
    'date': date,
    if (lastSpokeAt != null) 'lastSpokeAt': lastSpokeAt!.toIso8601String(),
    if (spokenToday > 0) 'spokenToday': spokenToday,
    if (noReplyStreak > 0) 'noReplyStreak': noReplyStreak,
    if (lastTaskId != null) 'lastTaskId': lastTaskId,
    if (heldOffTaskId != null) 'heldOffTaskId': heldOffTaskId,
  };

  factory ActiveCoachingBudget.fromJson(Map json, {required String today}) {
    if (json['date']?.toString() != today) {
      return ActiveCoachingBudget(date: today);
    }
    return ActiveCoachingBudget(
      date: today,
      lastSpokeAt: _parseTime(json['lastSpokeAt']),
      spokenToday: (json['spokenToday'] as num?)?.toInt() ?? 0,
      noReplyStreak: (json['noReplyStreak'] as num?)?.toInt() ?? 0,
      lastTaskId: json['lastTaskId']?.toString(),
      heldOffTaskId: json['heldOffTaskId']?.toString(),
    );
  }
}

/// 두 벌을 읽고 쓰는 자리.
class ActiveCoachingStore {
  const ActiveCoachingStore._();

  /// 할 일별 추적. 'nyang_' 접두어라 클라우드에 실린다 — 약속 시각은 기기를
  /// 바꿔도 따라와야 한다.
  static const String trackingKey = 'nyang_active_coaching';

  /// 사용자 예산. 접두어를 쓰지 않는다 — 이 기기에서 방금 일어난 사실이라
  /// 다른 기기에서 내려온 값에 덮이면 안 된다.
  static const String budgetKey = 'active_coaching_budget';

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static ActiveCoachingDay readDay(SharedPreferences prefs, DateTime now) =>
      ActiveCoachingDay.fromJson(
        _decode(prefs.getString(trackingKey)),
        today: dateKey(now),
      );

  static ActiveCoachingBudget readBudget(
    SharedPreferences prefs,
    DateTime now,
  ) => ActiveCoachingBudget.fromJson(
    _decode(prefs.getString(budgetKey)),
    today: dateKey(now),
  );

  static Future<void> writeDay(
    SharedPreferences prefs,
    ActiveCoachingDay day,
  ) async {
    await prefs.setString(trackingKey, jsonEncode(day.toJson()));
  }

  static Future<void> writeBudget(
    SharedPreferences prefs,
    ActiveCoachingBudget budget,
  ) async {
    await prefs.setString(budgetKey, jsonEncode(budget.toJson()));
  }

  static Map _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded : const {};
    } catch (_) {
      return const {};
    }
  }
}
