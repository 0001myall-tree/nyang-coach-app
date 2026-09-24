import 'package:shared_preferences/shared_preferences.dart';

/// 네이티브가 앱이 꺼진 사이에 등급을 가릴 때 보는 결론 두 개.
///
/// 네이티브는 사용자 정보를 읽을 수 없어서, 등급 자체가 아니라 필요한 결론만
/// boolean으로 넘긴다. 사용자 정보가 읽히거나 저장될 때마다 여기로 알려준다.
///
/// - **유료 플랜인지**: 딴짓 방지 코칭이 나가도 되는지. 한때 프렌즈는 하루 한
///   일정까지였는데, 마스터만의 몫이 적극 코칭으로 옮겨가면서 풀었다. 플랜이
///   끝난 사람은 스위치가 켜진 채 남아 있어도 나가지 않는다.
/// - **마스터인지**: 적극 코칭이 나가도 되는지.
///
/// 둘은 한때 한 값이었다("마스터인지" 하나로 딴짓 방지 코칭의 하루치와 적극
/// 코칭을 함께 가렸다). 그 값을 프렌즈에게 켜면 적극 코칭까지 열려서 나눴다.
///
/// 여기 쓰는 키는 'nyang_'으로 시작하지 않는다. 그 접두어가 붙으면 클라우드에
/// 올라갔다 내려오는데, 이 기기에서 방금 읽은 등급이 다른 기기 값에 덮이면 안
/// 된다. 네이티브에서는 'flutter.'가 붙은 이름으로 읽는다.
class CoachTierFlags {
  const CoachTierFlags._();

  /// 유료 플랜인지. 옛 이름을 그대로 쓴다 — 네이티브가 이 이름으로 읽는다.
  static const String paidKey = 'ongoing_nudge_unlimited';

  /// 마스터 등급인지.
  static const String masterKey = 'active_coaching_master';

  static Future<void> publish({required bool paid, required bool master}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(paidKey, paid);
    await prefs.setBool(masterKey, master);
  }

  /// 딴짓 방지 코칭이 나가도 되는 플랜인지.
  static Future<bool> isPaid() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(paidKey) ?? false;
  }
}
