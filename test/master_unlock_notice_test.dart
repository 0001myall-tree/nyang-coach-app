import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/master_unlock_notice.dart';

/// "마스터 코치가 열렸어요"는 한 사람에게 한 번만 나와야 한다.
///
/// 두 번 새어 나간 적이 있다. 처음에는 표시를 지우는 길이 있어서 — 등급이 잠깐
/// 다르게 읽히는 순간마다 지워졌다. 그다음에는 표시에 만료일이 붙어 있어서 —
/// 만료일이 흔들릴 때마다 새 구독으로 보였다. 이제 지우지 않고, 등급만 보고
/// 이름을 짓는다.
void main() {
  const currentPlan = 'master';

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
        masterUnlockSignature(isPlanActive: true, planType: 'friends'),
        isNull,
      );
      expect(
        masterUnlockSignature(isPlanActive: false, planType: 'master'),
        isNull,
      );
    });

    // 만료일이 이름에 들어 있던 동안에는, 값이 오갈 때마다 새 구독으로 보여서
    // 안내가 매일 다시 떴다. 만료일이 어떻게 흔들리든 이름은 같아야 한다.
    test('만료일이 달라져도 이름은 그대로다', () {
      const same = 'master';
      expect(
        masterUnlockSignature(isPlanActive: true, planType: 'master'),
        same,
      );
      expect(
        decideMasterUnlockNotice(
          restorePending: false,
          signature: same,
          announced: same,
        ),
        MasterUnlockDecision.alreadyShown,
      );
    });
  });
}
