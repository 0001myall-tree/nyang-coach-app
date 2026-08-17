/// 루틴이 어느 날 올라오는지 정하는 규칙.
///
/// 이 규칙은 세 곳에서 필요하다. 오늘 목록을 만들 때(할 일 화면), 하루가
/// 바뀔 때(하루 리셋), 애플 캘린더로 내보낼 때다. 세 곳에 각각 복사돼 있던
/// 동안에는 한쪽만 고쳐도 나머지 둘이 조용히 어긋났고, 어긋난 자리는 화면에
/// 바로 안 보여서 며칠 뒤에야 "완료했는데 또 뜬다"로 나타났다.
///
/// 값을 날것으로 받는다. 화면은 [HabitItem]을, 나머지 둘은 저장소에서 막 꺼낸
/// Map을 들고 있어서, 어느 한쪽 모양을 고르면 다른 쪽이 변환을 하느라 또
/// 자기 계산을 갖게 된다.
library;

class RoutineSchedule {
  /// 주간 목표의 기본값. 사용자가 고르지 않았을 때 쓴다.
  static const int defaultWeeklyTarget = 5;

  /// 시각을 떼고 날짜만 남긴다.
  static DateTime dayOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// 그 주의 월요일.
  static DateTime startOfWeek(DateTime date) {
    final normalized = dayOnly(date);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  /// 기록을 찾을 때 쓰는 날짜 키. `2026-08-17` 꼴.
  static String dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// 주 몇 일짜리인지. 저장된 값이 숫자든 문자열이든 받아서 1~7로 맞춘다.
  static int weeklyTarget(Object? rawTarget) {
    final parsed = rawTarget is num
        ? rawTarget.toInt()
        : int.tryParse('$rawTarget') ?? defaultWeeklyTarget;
    if (parsed < 1) return 1;
    return parsed > 7 ? 7 : parsed;
  }

  /// 루틴을 만든 날. 못 읽으면 null.
  static DateTime? createdDate(Object? rawCreatedAt) {
    final raw = rawCreatedAt?.toString();
    if (raw == null || raw.isEmpty) return null;
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? null : dayOnly(parsed);
  }

  /// 만든 주에는 목표를 남은 날수만큼 줄인다.
  ///
  /// 금요일에 "주 5일"을 만들면 그 주에 남은 날은 사흘뿐이다. 줄이지 않으면
  /// 시작하자마자 못 채운 주가 되어, 첫 주부터 밀린 것으로 보인다.
  static int visibleWeeklyTarget({
    required int target,
    required DateTime? createdDate,
    required DateTime date,
  }) {
    final normalizedDate = dayOnly(date);
    final weekStart = startOfWeek(normalizedDate);
    if (createdDate == null ||
        createdDate.isBefore(weekStart) ||
        createdDate.isAfter(normalizedDate)) {
      return target;
    }
    final remainingDaysInCreationWeek = 8 - createdDate.weekday;
    return remainingDaysInCreationWeek < target
        ? remainingDaysInCreationWeek
        : target;
  }

  /// 하루치 기록이 몇 번으로 세어지는지. 0이면 안 한 날이다.
  ///
  /// "조금 했어"를 고른 날은 1이 아니라 0.25로 센다. 부분만 한 날을 한 날로
  /// 세면 주간 목표가 실제보다 빨리 채워진다.
  static double logCompletionRatio(Object? log) {
    if (log is! Map || log['done'] != true) return 0;
    final rawRatio = log['progressRatio'];
    if (rawRatio is num) {
      return _clampRatio(rawRatio.toDouble());
    }
    final count = (log['count'] as num?)?.toDouble();
    final countGoal = (log['countGoal'] as num?)?.toDouble();
    if (count != null && countGoal != null && countGoal > 0) {
      return _clampRatio(count / countGoal);
    }
    return 1;
  }

  static double _clampRatio(double ratio) {
    if (ratio < 0) return 0;
    return ratio > 1 ? 1 : ratio;
  }

  /// 이번 주에 몇 번 했는지. [includeDate]가 참이면 그날까지 포함해 센다.
  ///
  /// 만든 날이 이번 주 안이면 거기서부터 센다. 만들기 전의 빈 날은 안 한 날이
  /// 아니라 없던 날이다.
  static double doneCount({
    required Map<dynamic, dynamic>? logs,
    required DateTime? createdDate,
    required DateTime date,
    required bool includeDate,
  }) {
    if (logs == null) return 0;
    final normalizedDate = dayOnly(date);
    final weekStart = startOfWeek(normalizedDate);
    final startsInThisWeek =
        createdDate != null &&
        !createdDate.isBefore(weekStart) &&
        (includeDate
            ? !createdDate.isAfter(normalizedDate)
            : createdDate.isBefore(normalizedDate));
    final countStart = startsInThisWeek ? createdDate : weekStart;

    var count = 0.0;
    for (
      var cursor = countStart;
      includeDate ? !cursor.isAfter(normalizedDate) : cursor.isBefore(normalizedDate);
      cursor = cursor.add(const Duration(days: 1))
    ) {
      count += logCompletionRatio(logs[dateKey(cursor)]);
    }
    return count;
  }

  /// 그날 완료로 기록됐는지.
  static bool isDoneOn(Map<dynamic, dynamic>? logs, DateTime date) {
    final log = logs?[dateKey(dayOnly(date))];
    return log is Map && log['done'] == true;
  }

  /// 주 몇 일짜리 루틴을 그날 목록에 올릴지.
  ///
  /// 이번 주 목표를 이미 채웠으면 더 올리지 않는다. 다만 그날 이미 완료한
  /// 것은 목표를 채웠더라도 그대로 둔다 — 방금 끝낸 것이 눈앞에서 사라지면
  /// 완료가 취소된 것처럼 보인다.
  static bool shouldShowWeeklyCountOnDate({
    required Object? rawWeeklyTargetCount,
    required Object? rawCreatedAt,
    required Map<dynamic, dynamic>? logs,
    required DateTime date,
  }) {
    final created = createdDate(rawCreatedAt);
    final target = visibleWeeklyTarget(
      target: weeklyTarget(rawWeeklyTargetCount),
      createdDate: created,
      date: date,
    );
    if (logs == null) return true;
    if (isDoneOn(logs, date)) return true;
    final doneBefore = doneCount(
      logs: logs,
      createdDate: created,
      date: date,
      includeDate: false,
    );
    return doneBefore < target;
  }
}
