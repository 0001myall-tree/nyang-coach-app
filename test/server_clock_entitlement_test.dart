import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/models/user_data.dart';
import 'package:nyang_coach/services/server_clock.dart';

/// 기기 시계를 돌려 구독을 늘리는 길을 막았는지 본다.
///
/// 기기 시각을 직접 바꿔볼 수는 없으니, 서버와의 차이를 넣어 같은 상황을
/// 만든다. 기기가 한 달 뒤를 가리키는 것과 서버가 한 달 앞이라고 알려주는 것은
/// 판정하는 쪽에서 보면 같은 일이다.
void main() {
  tearDown(() => ServerClock.setOffsetForTest(null));

  UserData planUntil(DateTime expiresAt) => UserData(
    planType: 'master',
    planExpiresAt: expiresAt,
  );

  group('구독 만료', () {
    test('서버가 아직 만료 전이라고 하면 쓸 수 있다', () {
      ServerClock.setOffsetForTest(Duration.zero);
      final data = planUntil(DateTime.now().add(const Duration(days: 3)));
      expect(data.isPlanActive, isTrue);
    });

    test('기기를 뒤로 돌려도 끝난 구독은 살아나지 않는다', () {
      // 기기가 30일 전을 가리키는 상황. 서버는 그만큼 앞서 있다.
      ServerClock.setOffsetForTest(const Duration(days: 30));
      final data = planUntil(DateTime.now().add(const Duration(days: 3)));
      expect(
        data.isPlanActive,
        isFalse,
        reason: '기기 기준으로는 사흘 남았지만 서버 기준으로는 27일 전에 끝났다',
      );
    });

    test('서버 시각을 못 받았으면 기기 시각으로 본다', () {
      // 화면에 남은 날을 적는 자리까지 막으면 인터넷이 없을 때 이상해진다.
      // 돈이 나가는 자리는 ensureSynced가 따로 지킨다.
      ServerClock.setOffsetForTest(null);
      final data = planUntil(DateTime.now().add(const Duration(days: 3)));
      expect(data.isPlanActive, isTrue);
    });
  });

  group('코치 보유', () {
    UserData ownsCoachUntil(DateTime expiresAt) => UserData(
      planType: 'friends',
      planExpiresAt: DateTime.now().add(const Duration(days: 365)),
      ownedCoaches: ['nyang_halbae'],
      ownedCoachExpiresAt: {'nyang_halbae': expiresAt},
    );

    test('기기를 뒤로 돌려도 만료된 코치는 열리지 않는다', () {
      ServerClock.setOffsetForTest(const Duration(days: 30));
      final data = ownsCoachUntil(DateTime.now().add(const Duration(days: 3)));
      expect(data.isOwnedCoachActive('nyang_halbae'), isFalse);
    });

    test('아직 남아 있으면 열린다', () {
      ServerClock.setOffsetForTest(Duration.zero);
      final data = ownsCoachUntil(DateTime.now().add(const Duration(days: 3)));
      expect(data.isOwnedCoachActive('nyang_halbae'), isTrue);
    });
  });
}
