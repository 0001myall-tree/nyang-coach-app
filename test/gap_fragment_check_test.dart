import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/gap_fragment_check.dart';
import 'package:nyang_coach/services/gap_coaching_service.dart';

/// 할 일 이름 하나를 보고 15분 안에 끝나는 조각 하나를 받아온다.
///
/// 지금까지는 키워드 사전이 이 일을 했고, 사전에 없는 이름은 전부
/// "10분만 미리 해두면"으로 떨어져 정작 이 기능이 하려던 걸 못 했다.
void main() {
  group('답에서 조각 꺼내기', () {
    test('그대로 온 답을 읽는다', () {
      expect(GapFragmentCheck.readFragment('개요 잡기'), '개요 잡기');
    });

    test('따옴표와 마침표는 걷어낸다', () {
      // 형식을 정확히 지킨다는 전제로 좁게 잡으면, 멀쩡한 답이 통째로 버려진다.
      expect(GapFragmentCheck.readFragment('"개요 잡기".'), '개요 잡기');
      expect(GapFragmentCheck.readFragment("'자료 모으기'"), '자료 모으기');
      expect(GapFragmentCheck.readFragment('개요 잡기\n'), '개요 잡기');
    });

    test('여러 줄로 오면 첫 줄만 쓴다', () {
      expect(GapFragmentCheck.readFragment('개요 잡기\n이렇게 하면 좋습니다'), '개요 잡기');
    });

    test('NONE이면 조각이 없다', () {
      expect(GapFragmentCheck.readFragment('NONE'), isNull);
      expect(GapFragmentCheck.readFragment('none'), isNull);
    });

    test('설명을 붙여 오면 조각이 아니다', () {
      // 길면 카드 한 줄을 혼자 다 먹는다.
      expect(
        GapFragmentCheck.readFragment('먼저 자료를 모으고 개요를 잡은 다음 초안을 씁니다'),
        isNull,
      );
    });

    test('빈 답은 없는 것으로 본다', () {
      expect(GapFragmentCheck.readFragment(''), isNull);
      expect(GapFragmentCheck.readFragment('   '), isNull);
    });
  });

  group('조각을 넣은 문장', () {
    test('조각이 무엇이든 말이 된다', () {
      // 사전이 쓰던 "개요만 잡아둬도"류는 조각 모양이 정해져 있을 때만 되는
      // 틀이라, 모델이 만들어 오는 말에는 안 맞는다.
      for (final fragment in ['개요 잡기', '자료 목록 만들기', '운동복 챙기기', '예상 질문 적기']) {
        final body = GapCoachingService.fragmentBody(
          name: '분기 리포트',
          fragment: fragment,
        );
        expect(body, contains('분기 리포트'));
        expect(body, contains(fragment));
        expect(body, endsWith('써볼까냥?'));
      }
    });

    test('15분이라고 말한다', () {
      // 30분은 조각이 아니라 또 하나의 일이 된다.
      final body = GapCoachingService.fragmentBody(
        name: '분기 리포트',
        fragment: '개요 잡기',
      );
      expect(body, contains('15분'));
    });

    test('이름이 길면 줄여서 넣는다', () {
      final body = GapCoachingService.fragmentBody(
        name: '분기 리포트 초안 정리해서 팀에 공유하기',
        fragment: '개요 잡기',
      );
      expect(body, contains('…'));
    });
  });

  test('오늘 물어봤다는 표시는 클라우드가 덮지 못한다', () {
    // 이 기기에서 오늘 물어봤다는 사실이라 다른 기기 값이 내려오면 안 된다.
    expect(GapCoachingService.fragmentCacheKey.startsWith('nyang_'), isFalse);
  });
}
