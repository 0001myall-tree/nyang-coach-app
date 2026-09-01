import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/task_name_similarity.dart';

bool same(String a, String b) => TaskNameSimilarity.isSameWork(a, b);

/// 글자만 보고 아는 것까지가 여기 몫이다. 그 너머는 뜻을 보는 쪽이 맡는다.
void main() {
  group('글자만 보고 아는 것', () {
    test('글자가 같으면', () {
      expect(same('청소', '청소'), isTrue);
    });

    test('띄어쓰기와 문장부호만 다르면', () {
      expect(same('사업계획서 쓰기', '사업계획서쓰기'), isTrue);
      expect(same('청소하기!', '청소하기'), isTrue);
    });

    test('한쪽이 다른 쪽을 통째로 품으면', () {
      expect(same('사업계획서 쓰기', '오늘 사업계획서 쓰기'), isTrue);
    });

    test('견주는 순서를 타지 않는다', () {
      expect(same('오늘 사업계획서 쓰기', '사업계획서 쓰기'), isTrue);
    });
  });

  group('글자로는 모르는 것', () {
    // 여기서 false는 "다른 일"이 아니라 "글자로는 모르겠다"는 뜻이다.
    // 이 짝들은 뜻을 보는 판정으로 넘어간다.
    test('끝말만 다른 이름', () {
      expect(same('지원서 비교견적서 내기', '지원서 비교견적서 제출'), isFalse);
    });

    test('글자가 하나도 안 겹치는 같은 일', () {
      expect(same('책 읽기', '독서'), isFalse);
    });

    test('앞말이 같은 다른 일', () {
      // 예전에는 이걸 같은 일로 쳐서, 다른 일을 제안하지 못하게 됐다.
      expect(same('보고서 초안 쓰기', '보고서 초안 검토'), isFalse);
    });
  });

  group('겹쳐 보여도 다른 일', () {
    test('아무 관계 없는 이름', () {
      expect(same('운동하기', '장보기'), isFalse);
    });

    test('빈 이름은 아무것과도 같지 않다', () {
      expect(same('', '청소'), isFalse);
      expect(same('   ', '청소'), isFalse);
    });

    test('너무 짧은 이름끼리는 포함 관계를 보지 않는다', () {
      // 두 글자가 우연히 다른 이름 안에 들어 있는 일이 잦다.
      expect(same('독서', '독'), isFalse);
    });
  });
}
