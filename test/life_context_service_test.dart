import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/life_context_service.dart';

/// 같은 말을 [times]번 들은 것으로 친다.
List<LifeHit> hits(Map<String, int> counts) => [
  for (final entry in counts.entries)
    for (var i = 0; i < entry.value; i++)
      LifeHit(kind: entry.key, at: DateTime.now()),
];

void main() {
  group('생활 형태 가려내기', () {
    test('한 번 들은 말로는 정하지 않는다', () {
      // 남의 퇴근 이야기를 옮긴 것일 수도 있다.
      expect(LifeContextService.resolveFrom(hits({'job': 1})), isNull);
    });

    test('두 번 쌓이고 다른 쪽이 없으면 그 생활로 본다', () {
      expect(LifeContextService.resolveFrom(hits({'job': 2})), 'job');
    });

    test('두 생활이 비슷하게 나오면 고르지 않는다', () {
      // 학교 다니면서 알바하는 사람이 있다. 근소한 차이로 하나를 고르면
      // 틀린 쪽으로 굳는다.
      expect(
        LifeContextService.resolveFrom(hits({'student': 4, 'parttime': 3})),
        isNull,
      );
    });

    test('한쪽이 뚜렷하게 앞서면 그쪽으로 본다', () {
      expect(
        LifeContextService.resolveFrom(hits({'student': 6, 'parttime': 3})),
        'student',
      );
    });

    test('아무것도 없으면 모른다고 한다', () {
      expect(LifeContextService.resolveFrom(const []), isNull);
    });
  });

  group('말에서 줍기', () {
    test('한쪽에서만 쓰는 말을 줍는다', () {
      expect(LifeContextService.kindsIn('오늘 퇴근하고 할게'), {'job'});
      expect(LifeContextService.kindsIn('알바 끝나고 해야지'), {'parttime'});
      expect(LifeContextService.kindsIn('내일 수업 있어서'), {'student'});
    });

    test('여러 생활에 걸치는 말은 줍지 않는다', () {
      // '마감'은 직장인도 프리랜서도 학생도 쓴다. 그런 말로 세면 숫자만
      // 늘고 뜻은 흐려진다.
      expect(LifeContextService.kindsIn('내일까지 마감이야'), isEmpty);
      expect(LifeContextService.kindsIn('회의가 세 개나 있어'), isEmpty);
    });

    test('아무 자취도 없으면 빈손이다', () {
      expect(LifeContextService.kindsIn('오늘 너무 피곤해'), isEmpty);
    });
  });

  group('아니라고 하면', () {
    test('그만뒀다는 말을 알아듣는다', () {
      expect(LifeContextService.negatedKindsIn('나 회사 안 다녀'), {'job'});
      expect(LifeContextService.negatedKindsIn('알바 그만뒀어'), {'parttime'});
      expect(LifeContextService.negatedKindsIn('작년에 퇴사했어'), {'job'});
    });

    test('그냥 말한 것과 가른다', () {
      // 같은 낱말이라도 아니라는 말이 붙지 않으면 그 생활을 사는 것이다.
      expect(LifeContextService.negatedKindsIn('퇴근하고 할게'), isEmpty);
      expect(LifeContextService.negatedKindsIn('알바 끝나고 해야지'), isEmpty);
    });

    test('아니라는 말만 있고 무엇인지 없으면 아무 일도 없다', () {
      expect(LifeContextService.negatedKindsIn('오늘은 안 해'), isEmpty);
    });
  });
}
