import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/gap_fragment_check.dart';
import 'package:nyang_coach/services/gap_coaching_service.dart';

/// 남은 일 목록을 보고, 어느 일을 어떻게 준비해둘지 골라온다.
///
/// 처음엔 키워드 사전이 이 일을 했고, 사전에 없는 이름은 전부 "10분만 미리
/// 해두면"으로 떨어졌다. 그다음엔 앱이 일을 고르고 이름만 넘겼는데, 그러면
/// '사당역 19시' 같은 약속까지 쪼개라고 넘어갔다. 이제 고르는 것도 맡긴다.
void main() {
  group('답에서 고른 일 꺼내기', () {
    const candidates = ['분기 리포트', '사당역 19시', '헬스장 가기'];

    test('고른 일과 준비를 두 줄로 읽는다', () {
      final pick = GapFragmentCheck.readPick('분기 리포트\n개요 잡기', candidates);
      expect(pick?.task, '분기 리포트');
      expect(pick?.prep, '개요 잡기');
    });

    test('따옴표를 붙여 와도 읽는다', () {
      final pick = GapFragmentCheck.readPick(
        '"헬스장 가기"\n\'운동복 챙기기\'',
        candidates,
      );
      expect(pick?.task, '헬스장 가기');
      expect(pick?.prep, '운동복 챙기기');
    });

    test('목록에 없는 일을 지어내면 버린다', () {
      // 카드가 적은 적 없는 일을 불러주면 안 된다.
      expect(
        GapFragmentCheck.readPick('세금계산서 발행\n항목 적어두기', candidates),
        isNull,
      );
    });

    test('NONE이면 고른 것이 없다', () {
      expect(GapFragmentCheck.readPick('NONE', candidates), isNull);
    });

    test('한 줄만 오면 못 읽은 것으로 본다', () {
      expect(GapFragmentCheck.readPick('분기 리포트', candidates), isNull);
    });

    test('준비 자리에 설명이 오면 버린다', () {
      expect(
        GapFragmentCheck.readPick(
          '분기 리포트\n먼저 자료를 모으고 개요를 잡은 다음 초안을 씁니다',
          candidates,
        ),
        isNull,
      );
    });
  });

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
        // 하는 중인 일도 코치가 고른다. '이따 할'을 붙이면 이미 붙잡고 있는
        // 일이 나중 일이 된다.
        expect(body, isNot(contains('이따 할')));
      }
    });

    test('10분이라고 말한다', () {
      // 그보다 길면 조각이 아니라 또 하나의 일이 된다.
      final body = GapCoachingService.fragmentBody(
        name: '분기 리포트',
        fragment: '개요 잡기',
      );
      expect(body, contains('10분'));
    });

    test('이름이 길면 줄여서 넣는다', () {
      final body = GapCoachingService.fragmentBody(
        name: '분기 리포트 초안 정리해서 팀에 공유하기',
        fragment: '개요 잡기',
      );
      expect(body, contains('…'));
    });

    test('이름과 조각이 둘 다 길어도 한 줄을 넘지 않는다', () {
      // 카드 한 줄이 넘치면 카드가 통째로 늘어난다. 조각은 코치가 지은 말이라
      // 자를 수 없으니 이름 쪽이 더 물러난다.
      final body = GapCoachingService.fragmentBody(
        name: '모두의 창업 2차 개요 정리해서 공유하기',
        fragment: '자료 목록 만들어두기',
      );
      expect(body.length, lessThanOrEqualTo(GapCoachingService.bodyLimit));
      expect(body, contains('자료 목록 만들어두기'));
    });
  });

  test('오늘 물어봤다는 표시는 클라우드가 덮지 못한다', () {
    // 이 기기에서 오늘 물어봤다는 사실이라 다른 기기 값이 내려오면 안 된다.
    expect(GapCoachingService.fragmentCacheKey.startsWith('nyang_'), isFalse);
  });
}
