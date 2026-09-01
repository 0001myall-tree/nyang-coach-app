import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/task_name_similarity.dart';

bool same(String a, String b) => TaskNameSimilarity.isSameWork(a, b);

void main() {
  group('같은 일로 본다', () {
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

    test('끝말만 다르면', () {
      // 목록에 있는 일을 코치가 조금 다르게 적어 새 할 일로 다시 제안하던 자리다.
      expect(same('지원서 비교견적서 내기', '지원서 비교견적서 제출'), isTrue);
      expect(same('보고서 초안 쓰기', '보고서 초안 작성'), isTrue);
    });

    test('견주는 순서를 타지 않는다', () {
      expect(
        same('지원서 비교견적서 제출', '지원서 비교견적서 내기'),
        same('지원서 비교견적서 내기', '지원서 비교견적서 제출'),
      );
    });
  });

  group('다른 일로 본다', () {
    test('앞말이 겹쳐도 낱말이 하나뿐이면', () {
      // '청소'와 '청소기 수리'가 같은 일이 되면 안 된다.
      expect(same('청소', '청소기 수리'), isFalse);
    });

    test('뗀 앞부분이 너무 짧으면', () {
      // 한두 글자는 우연히 겹친다.
      expect(same('책 읽기', '책 사기'), isFalse);
    });

    test('아무 관계 없는 이름', () {
      expect(same('운동하기', '장보기'), isFalse);
    });

    test('빈 이름은 아무것과도 같지 않다', () {
      expect(same('', '청소'), isFalse);
      expect(same('   ', '청소'), isFalse);
    });
  });

  group('짧은 이름은 포함 관계를 보지 않는다', () {
    test('두 글자끼리는 같을 때만', () {
      // '독서'가 '독서실 예약' 안에 있다고 같은 일은 아니다.
      expect(same('독서', '독'), isFalse);
    });
  });
}
