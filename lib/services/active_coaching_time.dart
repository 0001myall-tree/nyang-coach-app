/// "좀 더 있다가 언제?"에 내놓을 시각들.
///
/// 지금은 [좀 더 있다가]를 누르면 30분 뒤에 같은 카드가 한 번 더 오는 것이
/// 전부다. 적극 코칭에서는 **언제 할지를 받는다** — 그래야 그 시각이 약속이
/// 되고, 그 시각에 확인할 근거가 생긴다.
///
/// **상대 표현을 쓰지 않는다.** 3시 12분에 "30분 뒤 · 3:30"은 18분 뒤라
/// 거짓말이 된다. "30분 뒤"라는 말을 지우면 어긋날 것이 없고, 지금 폰을 보고
/// 있는 사람이라 몇 시인지 안다.
///
/// **반듯한 시각으로 맞춘다.** "4시에 할게"는 약속이고 "4시 12분에 할게"는
/// 계산 결과다.
library;

/// 몇 시로 미룰지 고르는 자리.
class ActiveCoachingTime {
  const ActiveCoachingTime._();

  /// 첫 번째 자리를 잡는 기준.
  static const Duration near = Duration(minutes: 30);

  /// 두 번째 자리를 잡는 기준.
  static const Duration far = Duration(hours: 1);

  /// 취침 시각을 안 정해둔 사람의 경계.
  static const int defaultBedtimeHour = 23;

  /// 버튼에 올릴 시각들. 많아야 둘이고, 남는 자리가 없으면 비어 있다.
  ///
  /// [bedtime]은 'HH:mm'. 취침을 넘는 자리는 주지 않는다 — 10시 반에
  /// "한 시간 뒤"를 주면 11시 반에 부르게 된다.
  ///
  /// [busyAt]이 참인 시각도 주지 않는다. 근무 중으로 미뤄봐야 그 시각에
  /// 할 수 없다. 다만 [직접 고르기]로 굳이 그 시각을 고르는 것은 본인 선택이라
  /// 막지 않는다 — 여기서 빼는 것은 앱이 먼저 내미는 자리뿐이다.
  static List<DateTime> choices(
    DateTime now, {
    String? bedtime,
    bool Function(DateTime at)? busyAt,
  }) {
    final sleepAt = _bedtimeAfter(now, bedtime);
    final first = round(now.add(near));
    var second = round(now.add(far));
    // 같은 칸에 떨어지면 뒤엣것을 한 칸 민다. 같은 시각 버튼 둘은 고를 것이
    // 하나인 것과 같다.
    if (!second.isAfter(first)) second = first.add(const Duration(minutes: 30));

    final result = <DateTime>[];
    for (final at in [first, second]) {
      if (!at.isAfter(now)) continue;
      if (!at.isBefore(sleepAt)) continue;
      if (busyAt != null && busyAt(at)) continue;
      result.add(at);
    }
    return result;
  }

  /// 가장 가까운 :00 또는 :30.
  ///
  /// 0~14분은 정각으로, 15~44분은 반으로, 45분부터는 다음 정각으로 간다.
  static DateTime round(DateTime at) {
    final base = DateTime(at.year, at.month, at.day, at.hour);
    if (at.minute < 15) return base;
    if (at.minute < 45) return base.add(const Duration(minutes: 30));
    return base.add(const Duration(hours: 1));
  }

  /// 저장할 모양. "16:30".
  static String format(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  /// 다음 취침 시각.
  ///
  /// 자정을 넘겨 자는 사람은 그 취침이 다음 날 것이다 — 새벽 1시에 자는
  /// 사람에게 밤 10시는 아직 세 시간이 남은 시각이다.
  static DateTime _bedtimeAfter(DateTime now, String? bedtime) {
    final parsed = _parseHhMm(bedtime);
    var at = parsed == null
        ? DateTime(now.year, now.month, now.day, defaultBedtimeHour)
        : DateTime(now.year, now.month, now.day, parsed.$1, parsed.$2);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  static (int, int)? _parseHhMm(String? raw) {
    final parts = (raw ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }
}
