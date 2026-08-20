import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/master_unlock_notice.dart';

/// "마스터 코치가 열렸어요"는 한 구독에 한 번만 나와야 한다.
///
/// 반복해서 뜨던 이유는 표시를 지우는 길이 있었기 때문이다. 마스터가 아닌 것으로
/// 읽히면 "다음 결제 때 다시 알려주려고" 표시를 지웠는데, 등급이 잠깐 다르게
/// 읽히는 순간마다 그 표시가 함께 지워졌다. 이제 지우지 않고, 무엇을 두고
/// 알렸는지를 적어둔 뒤 그것과 다를 때만 다시 알린다.
void main() {
  const currentPlan = 'master|2027-01-01T00:00:00.000';

  group('알릴 때와 알리지 않을 때', () {
    test('처음 마스터가 되면 알린다', () {
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: currentPlan,
          announced: null,
        ),
        MasterUnlockDecision.show,
      );
    });

    test('같은 구독으로 다시 와도 알리지 않는다', () {
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: currentPlan,
          announced: currentPlan,
        ),
        MasterUnlockDecision.alreadyShown,
      );
    });

    test('마스터가 아니면 아무것도 하지 않는다', () {
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: null,
          announced: currentPlan,
        ),
        MasterUnlockDecision.skip,
      );
    });

    // 잘못 읽힌 순간이 적어둔 것을 건드리지 않아야, 곧 제 등급으로 돌아왔을 때
    // 같은 안내가 다시 뜨지 않는다.
    test('등급이 잠깐 아니게 읽혀도 적어둔 것은 그대로다', () {
      // 마스터가 아닌 것으로 읽힌 순간 — 아무 결정도 하지 않는다.
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: null,
          announced: currentPlan,
        ),
        MasterUnlockDecision.skip,
      );
      // 제 등급으로 돌아온 뒤 — 이미 알린 것으로 남아 있다.
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: currentPlan,
          announced: currentPlan,
        ),
        MasterUnlockDecision.alreadyShown,
      );
    });

    test('클라우드에서 데이터를 받아오기 전에는 판단하지 않는다', () {
      expect(
        decideMasterUnlockNotice(
          restorePending: true,
          signature: currentPlan,
          announced: null,
        ),
        MasterUnlockDecision.skip,
      );
    });
  });

  group('구독을 알아보는 이름', () {
    test('마스터가 아니면 없다', () {
      expect(
        masterUnlockSignature(
          isPlanActive: true,
          planType: 'friends',
          planExpiresAt: DateTime(2027),
        ),
        isNull,
      );
      expect(
        masterUnlockSignature(
          isPlanActive: false,
          planType: 'master',
          planExpiresAt: DateTime(2020),
        ),
        isNull,
      );
    });

    // 해지하고 다시 결제하면 만료일이 달라진다. 그때는 새 구독으로 보고
    // 한 번 더 알려준다.
    test('다시 결제하면 이름이 달라진다', () {
      final first = masterUnlockSignature(
        isPlanActive: true,
        planType: 'master',
        planExpiresAt: DateTime(2026, 9, 1),
      );
      final again = masterUnlockSignature(
        isPlanActive: true,
        planType: 'master',
        planExpiresAt: DateTime(2027, 3, 1),
      );
      expect(first, isNot(again));
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: again,
          announced: first,
        ),
        MasterUnlockDecision.show,
      );
    });

    test('만료일이 없는 구독도 이름이 생긴다', () {
      expect(
        masterUnlockSignature(
          isPlanActive: true,
          planType: 'master',
          planExpiresAt: null,
        ),
        'master|forever',
      );
    });
  });
}
