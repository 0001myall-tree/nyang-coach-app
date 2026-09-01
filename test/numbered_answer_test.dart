import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/numbered_answer.dart';

/// 답을 읽어내는 부분만 본다. 부르는 쪽은 통신이라 여기서 돌릴 수 없다.
///
/// 형식대로만 답하라고 일러두지만 지켜지지 않을 때가 있다. 그때 잘못 읽으면
/// 엉뚱한 제안이 사라지거나, 목록에 이미 있는 것이 다시 뜬다.
void main() {
  Set<int> read(String content, {int count = 3}) =>
      NumberedAnswer.read(content, count: count);

  group('번호를 읽는다', () {
    test('하나만 왔을 때', () {
      expect(read('2'), {1});
    });

    test('여러 개가 왔을 때', () {
      expect(read('1, 3'), {0, 2});
    });

    test('말이 섞여 와도 숫자만 읽는다', () {
      expect(read('2번이 이미 있는 일입니다'), {1});
    });

    test('앞뒤 공백과 마침표는 넘긴다', () {
      expect(read('  1.  '), {0});
    });
  });

  group('아무것도 고르지 않는다', () {
    test('NONE', () {
      expect(read('NONE'), isEmpty);
    });

    test('소문자로 와도', () {
      expect(read('none'), isEmpty);
    });

    test('NONE이라고 했으면 숫자가 섞여 있어도', () {
      // "1번은 다르고 나머지도 NONE" 같은 답에서 1을 집으면 안 된다.
      expect(read('1번은 다릅니다. NONE'), isEmpty);
    });

    test('빈 답', () {
      expect(read(''), isEmpty);
      expect(read('   '), isEmpty);
    });
  });

  group('범위 밖은 버린다', () {
    test('후보 개수를 넘는 번호', () {
      expect(read('5', count: 3), isEmpty);
    });

    test('0번은 없다', () {
      expect(read('0', count: 3), isEmpty);
    });

    test('쓸 수 있는 것만 남긴다', () {
      expect(read('2, 9', count: 3), {1});
    });
  });
}
