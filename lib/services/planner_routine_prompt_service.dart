class PlannerRoutinePromptService {
  static const cooldown = Duration(days: 30);
  static const windowDays = 7;
  static const noPlanThreshold = 4;

  static bool shouldOffer({
    required List<dynamic> history,
    required List<dynamic> todayTasks,
    required List<dynamic> habits,
    required DateTime now,
    DateTime? lastOfferedAt,
  }) {
    if (lastOfferedAt != null && now.difference(lastOfferedAt) < cooldown) {
      return false;
    }
    if (hasPlannerRoutine(habits) || hasPlannerRoutine(todayTasks)) {
      return false;
    }

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

  static bool hasPlannerRoutine(List<dynamic> items) {
    return items.whereType<Map>().any((item) {
      final category = item['category']?.toString() ?? '';
      final looksLikeHabit =
          category == 'habit' ||
          item['habitId'] != null ||
          item['freq'] != null;
      if (!looksLikeHabit && !item.containsKey('name')) return false;
      final text = '${item['name'] ?? ''} ${item['text'] ?? ''}'.replaceAll(
        RegExp(r'\s+'),
        '',
      );
      if (text.isEmpty) return false;
      final hasPlannerNoun =
          text.contains('플래너') ||
          text.contains('계획') ||
          text.contains('오늘할일') ||
          text.contains('할일');
      final hasRoutineAction =
          text.contains('보기') ||
          text.contains('확인') ||
          text.contains('열기') ||
          text.contains('체크') ||
          text.contains('점검') ||
          text.contains('정리');
      return hasPlannerNoun && hasRoutineAction;
    });
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
