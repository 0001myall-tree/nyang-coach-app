import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/coach_tier_flags.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 딴짓 방지 코칭은 유료 플랜이면 등급과 상관없이 나가고, 적극 코칭은
/// 마스터에게만 열린다. 두 결론이 한 값이던 때는 하나를 풀면 다른 하나도
/// 같이 풀렸다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('프렌즈는 딴짓 방지 코칭을 받고, 적극 코칭은 열리지 않는다', () async {
    await CoachTierFlags.publish(paid: true, master: false);
    final prefs = await SharedPreferences.getInstance();
    expect(await CoachTierFlags.isPaid(), isTrue);
    expect(prefs.getBool(CoachTierFlags.masterKey), isFalse);
  });

  test('플랜이 끝나면 딴짓 방지 코칭도 나가지 않는다', () async {
    await CoachTierFlags.publish(paid: false, master: false);
    expect(await CoachTierFlags.isPaid(), isFalse);
  });

  test('아직 아무것도 안 적혔으면 나가지 않는 쪽으로 읽는다', () async {
    expect(await CoachTierFlags.isPaid(), isFalse);
  });
}
