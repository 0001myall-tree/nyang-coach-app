class PlannerRoutinePromptService {
  static const windowDays = 7;
  static const noPlanThreshold = 4;

  /// 플래너 보는 루틴을 권해볼 때인지.
  ///
  /// 한 번 말하면 그걸로 끝이다. 안 만들기로 한 것도 답이라, 몇 달 뒤에 같은
  /// 말을 다시 꺼내면 그 답을 못 들은 척하는 셈이 된다.
  ///
  /// 이미 그런 루틴이 있는지는 보지 않는다. 이름만 보고 알아내려니 놓치거나
  /// 엉뚱한 걸 삼켰는데, 평생 한 번 나가는 말이라 그렇게까지 가릴 일이 아니다.
  static bool shouldOffer({
    required List<dynamic> history,
    required List<dynamic> todayTasks,
    required DateTime now,
    DateTime? lastOfferedAt,
  }) {
    if (lastOfferedAt != null) return false;

    final recordsByDate = <String, Map>{};
    for (final item in history.whereType<Map>()) {
      final date = item['date']?.toString();
      if (date == null || date.isEmpty) continue;
      recordsByDate[date] = item;
    }

    var evaluatedDays = 0;
    var noPlanDays = 0;
    for (var offset = 0; offset < windowDays; offset++) {
      final day = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: offset));
      final key = _dateKey(day);
      final isToday = offset == 0;
      final hasNoPlan = isToday
          ? _directPlanCount(todayTasks) == 0
          : _recordDirectPlanCount(recordsByDate[key]) == 0;

      if (!isToday && !recordsByDate.containsKey(key)) continue;
      evaluatedDays++;
      if (hasNoPlan) noPlanDays++;
    }

    return evaluatedDays >= noPlanThreshold && noPlanDays >= noPlanThreshold;
  }

  static int _directPlanCount(List<dynamic> tasks) {
    return tasks.whereType<Map>().where(_isDirectPlan).length;
  }

  static int _recordDirectPlanCount(Map? record) {
    if (record == null) return 0;
    final tasks = record['tasks'];
    if (tasks is! List) {
      final total = (record['totalCount'] as num?)?.toInt();
      return total ?? 0;
    }
    return _directPlanCount(tasks);
  }

  static bool _isDirectPlan(Map task) {
    if (task['deferred'] == true) return false;
    final category = task['category']?.toString();
    if (category == 'habit' || category == 'milestone') return false;
    if (task['habitId'] != null) return false;
    return true;
  }

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
