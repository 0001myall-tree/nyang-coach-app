import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_type_labels.dart';

/// 이름은 코치가 고르지만 뜻은 앱이 고정한다. 뜻을 안 주면 같은 이름이
/// 주마다 다른 것을 가리키게 되고, 사용자는 지난주 배지와 이번 주 배지가
/// 같은 말인지도 알 수 없다.
void main() {
  group('이름마다 뜻이 붙어 있다', () {
    test('빈 뜻이 없다', () {
      for (final entry in ExecutionTypeLabels.meanings.entries) {
        expect(entry.value.trim(), isNotEmpty, reason: entry.key);
      }
    });

    test('프롬프트 목록에 이름과 뜻이 함께 나간다', () {
      final listed = ExecutionTypeLabels.listForPrompt;
      for (final entry in ExecutionTypeLabels.meanings.entries) {
        expect(listed, contains(entry.key));
        expect(listed, contains(entry.value));
      }
    });

    test('뜻에 무엇을 하라는 말은 넣지 않는다', () {
      // 처방이 이름에 붙으면 이름이 틀릴 때 처방까지 같이 틀린다.
      for (final entry in ExecutionTypeLabels.meanings.entries) {
        expect(
          entry.value,
          isNot(contains('하세요')),
          reason: entry.key,
        );
        expect(entry.value, isNot(contains('해보')), reason: entry.key);
      }
    });
  });

  group('코치가 고른 이름 읽기', () {
    test('마지막 줄에서 읽는다', () {
      expect(
        ExecutionTypeLabels.readFrom('이번 주는 잘하셨어요.\n유형: 안정형'),
        '안정형',
      );
    });

    test('전각 콜론도 읽는다', () {
      expect(ExecutionTypeLabels.readFrom('유형： 자유형'), '자유형');
    });

    test('마침표가 붙어도 읽는다', () {
      expect(ExecutionTypeLabels.readFrom('유형: 편차형.'), '편차형');
    });

    test('목록에 없는 이름은 안 받는다', () {
      // 지어낸 이름을 배지에 띄우느니 배지를 안 띄우는 편이 낫다.
      expect(ExecutionTypeLabels.readFrom('유형: 몰아치기형'), isNull);
    });

    test('없음이면 배지를 띄우지 않는다', () {
      expect(ExecutionTypeLabels.readFrom('유형: 없음'), isNull);
    });

    test('줄 자체가 없으면 null', () {
      expect(ExecutionTypeLabels.readFrom('이번 주도 고생하셨어요.'), isNull);
    });
  });

  group('그 줄은 화면에 안 나간다', () {
    test('떼어낸다', () {
      expect(
        ExecutionTypeLabels.strip('이번 주는 잘하셨어요.\n유형: 안정형'),
        '이번 주는 잘하셨어요.',
      );
    });

    test('가운데 있어도 뗀다', () {
      expect(
        ExecutionTypeLabels.strip('앞\n유형: 안정형\n뒤'),
        '앞\n\n뒤',
      );
    });

    test('없으면 그대로', () {
      expect(ExecutionTypeLabels.strip('이번 주도 고생하셨어요.'), '이번 주도 고생하셨어요.');
    });
  });
}
