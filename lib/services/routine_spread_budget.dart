import 'package:shared_preferences/shared_preferences.dart';

/// 요일로 나누자는 제안을 언제 다시 꺼낼지.
///
/// 코치별로 세지 않는다. 냥냥이가 묻든 마스터가 묻든 사용자에게는 같은 이야기라,
/// 코치를 바꿔 가며 같은 말을 두 번 듣게 하면 안 된다.
///
/// 'nyang_' 접두어를 쓴다 — 기기 사이에 오가야 한다. 아이폰에서 "그대로 둘게"
/// 했는데 안드로이드에서 다시 물으면 거절이 없던 일이 된다.
class RoutineSpreadBudget {
  const RoutineSpreadBudget._();

  /// 마지막으로 물어본 때.
  static const String lastAskedKey = 'nyang_routine_spread_asked_at';

  /// 마지막으로 "그대로 둘게"를 받은 때.
  static const String lastDeclinedKey = 'nyang_routine_spread_declined_at';

  /// 거절하면 이만큼 쉰다.
  ///
  /// 한 주 뒤에 또 물으면 그건 부탁이 아니라 조르는 것이다. 매일 루틴을 그대로
  /// 두는 것도 사용자의 선택이다.
  static const Duration declineCooldown = Duration(days: 30);

  /// 받아들였거나 그냥 지나간 뒤 이만큼은 쉰다.
  ///
  /// 나눈 배치가 몸에 붙는 데도 시간이 걸린다. 다음 주에 또 나누자고 하면 방금
  /// 정한 것이 무색해진다.
  static const Duration askCooldown = Duration(days: 14);

  /// 지금 물어도 되는지.
  static Future<bool> canAsk(SharedPreferences prefs, DateTime now) async {
    final declined = DateTime.tryParse(
      prefs.getString(lastDeclinedKey) ?? '',
    );
    if (declined != null && now.difference(declined) < declineCooldown) {
      return false;
    }
    final asked = DateTime.tryParse(prefs.getString(lastAskedKey) ?? '');
    if (asked != null && now.difference(asked) < askCooldown) return false;
    return true;
  }

  static Future<void> markAsked(
    SharedPreferences prefs,
    DateTime now,
  ) async => prefs.setString(lastAskedKey, now.toIso8601String());

  static Future<void> markDeclined(
    SharedPreferences prefs,
    DateTime now,
  ) async => prefs.setString(lastDeclinedKey, now.toIso8601String());
}
