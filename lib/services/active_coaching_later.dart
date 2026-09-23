/// 시작 카드에서 [좀 더 있다가]를 눌렀을 때 내밀 시각들을 미리 만들어 둔다.
///
/// 카드는 다른 앱 위에 떠 있고, 거기서 두 번 누르면 앱을 안 열고도 끝나는 것이
/// 이 카드의 장점이다. 그 자리에서 시각을 고르게 하려면 네이티브가 시각을 알아야
/// 하는데, 계산을 코틀린에도 한 벌 두면 한쪽만 고쳤을 때 두 폰이 다른 시각을
/// 내민다. 이 앱이 여러 번 데인 모양이다.
///
/// 그래서 **Dart가 미리 만들어 두고 네이티브는 읽기만 한다.** 틈새 카드 문구를
/// 미리 만들어 두는 것과 같은 방식이다. 시작 시각은 미리 아는 값이라, 그 카드가
/// 뜰 순간을 기준으로 계산해둘 수 있다.
///
/// 만들어 둔 것은 낡을 수 있다. 시작 시각에 안 누르고 40분 뒤에 누르면 적어둔
/// 시각이 이미 지나 있다. 그래서 네이티브는 띄우기 전에 아직 오지 않은 것만
/// 고르고, 남는 것이 없으면 예전처럼 30분 뒤에 다시 부른다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'active_coaching_time.dart';
import 'busy_hours_service.dart';

class ActiveCoachingLater {
  const ActiveCoachingLater._();

  /// 네이티브가 읽어갈 자리.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기에서 방금 만든 값이라 클라우드가
  /// 덮으면 안 되고, 다른 기기에서 만든 시각이 내려와도 뜻이 없다.
  /// 네이티브에서는 'flutter.'가 붙은 이름으로 읽는다.
  static const String preparedKey = 'active_coaching_later';

  /// 그 일의 시작 시각을 기준으로 미룰 수 있는 시각들을 적어둔다.
  ///
  /// 적극 코칭이 꺼져 있으면 지운다. 끈 사람의 카드는 예전 그대로 — [좀 더
  /// 있다가]를 누르면 30분 뒤에 같은 카드가 한 번 더 온다.
  static Future<void> prepare(
    SharedPreferences prefs, {
    required String taskId,
    required DateTime startAt,
    required bool enabled,
  }) async {
    if (!enabled) {
      await clear(prefs);
      return;
    }
    final times = ActiveCoachingTime.choices(
      startAt,
      bedtime: prefs.getString('nyang_premium_min_sleep_time'),
      busyAt: (at) => BusyHoursService.busyNow(prefs, at) != null,
    );
    if (times.isEmpty) {
      await clear(prefs);
      return;
    }
    await prefs.setString(
      preparedKey,
      jsonEncode({
        'taskId': taskId,
        'times': times.map(ActiveCoachingTime.format).toList(),
      }),
    );
  }

  static Future<void> clear(SharedPreferences prefs) async {
    await prefs.remove(preparedKey);
  }

  /// 적어둔 시각들. 그 일의 것이 아니거나 전부 지났으면 빈 목록.
  static List<DateTime> read(
    SharedPreferences prefs, {
    required String taskId,
    required DateTime now,
  }) {
    final raw = prefs.getString(preparedKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const [];
      if (decoded['taskId']?.toString() != taskId) return const [];
      final times = decoded['times'];
      if (times is! List) return const [];
      final result = <DateTime>[];
      for (final item in times) {
        final parts = item.toString().split(':');
        if (parts.length != 2) continue;
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour == null || minute == null) continue;
        final at = DateTime(now.year, now.month, now.day, hour, minute);
        // 이미 지난 시각을 내밀면 누르는 순간 지나간 약속이 된다.
        if (!at.isAfter(now)) continue;
        result.add(at);
      }
      return result;
    } catch (_) {
      return const [];
    }
  }
}
