import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_move.dart';

/// 지금 이 일에 손대게 만드는 한 수.
///
/// 틈새 코칭이 쓰던 호출과 달리 "10분짜리 조각"으로 못 박지 않는다. 쪼개기도,
/// 첫 문장 대신 써주기도, 기준 낮추기도 다 한 수다.
void main() {
  group('답에서 한 수 꺼내기', () {
    const candidates = ['분기 리포트', '방 정리', '헬스장 가기'];

    test('고른 일과 한 수 둘을 읽는다', () {
      final picked = ActiveCoachingMove.read(
        '분기 리포트\n개요 세 줄 적기\n참고자료 모으기',
        candidates,
      );
      expect(picked?.task, '분기 리포트');
      expect(picked?.moves, ['개요 세 줄 적기', '참고자료 모으기']);
    });

    test('한 수가 하나뿐이어도 된다', () {
      // 되는 자리가 갈리지 않는 일이면 억지로 둘을 만들지 않는다.
      final picked = ActiveCoachingMove.read('방 정리\n눈앞 다섯 개만 치우기', candidates);
      expect(picked?.moves, ['눈앞 다섯 개만 치우기']);
    });

    test('셋을 보내와도 둘까지만 쓴다', () {
      // 셋이면 고르는 것도 일이 된다.
      final picked = ActiveCoachingMove.read(
        '분기 리포트\n개요 적기\n자료 모으기\n표지 만들기',
        candidates,
      );
      expect(picked?.moves.length, ActiveCoachingMove.maxMoves);
    });

    test('같은 말을 두 번 내놓으면 하나로 본다', () {
      final picked = ActiveCoachingMove.read(
        '방 정리\n눈앞 다섯 개 치우기\n눈앞 다섯 개 치우기',
        candidates,
      );
      expect(picked?.moves, ['눈앞 다섯 개 치우기']);
    });

    test('목록에 없는 일을 지어내면 버린다', () {
      // 적은 적 없는 일을 불러주면 안 된다.
      expect(ActiveCoachingMove.read('세금계산서\n서류 모으기', candidates), isNull);
    });

    test('NONE이면 낼 것이 없다', () {
      expect(ActiveCoachingMove.read('NONE', candidates), isNull);
    });

    test('일 이름만 오고 한 수가 없으면 버린다', () {
      expect(ActiveCoachingMove.read('방 정리', candidates), isNull);
    });

    test('한 수가 전부 길면 버린다', () {
      // 버튼에 안 들어가는 설명을 카드에 띄울 수는 없다.
      expect(
        ActiveCoachingMove.read(
          '방 정리\n먼저 방 전체를 둘러보고 어디부터 치울지 정한 다음에 시작하기',
          candidates,
        ),
        isNull,
      );
    });
  });

  group('한 줄 다듬기', () {
    test('따옴표와 마침표를 걷어낸다', () {
      expect(ActiveCoachingMove.readMove('"개요 세 줄 적기".'), '개요 세 줄 적기');
    });

    test('앞에 붙여 온 번호와 기호를 걷어낸다', () {
      expect(ActiveCoachingMove.readMove('1. 개요 세 줄 적기'), '개요 세 줄 적기');
      expect(ActiveCoachingMove.readMove('- 자료 모으기'), '자료 모으기');
    });

    test('길면 버린다', () {
      final long = '가' * (ActiveCoachingMove.maxMoveLength + 1);
      expect(ActiveCoachingMove.readMove(long), isNull);
    });

    test('빈 줄은 버린다', () {
      expect(ActiveCoachingMove.readMove('   '), isNull);
    });
  });

  group('넘기는 일 한 줄', () {
    test('시각과 하는 중 표시를 붙인다', () {
      expect(
        const ActiveCoachingCandidate(
          name: '분기 리포트',
          timeLabel: '오후 7:00',
          started: true,
        ).line,
        '분기 리포트 (오후 7:00 시작, 하는 중)',
      );
    });

    test('표시할 것이 없으면 이름만', () {
      expect(const ActiveCoachingCandidate(name: '방 정리').line, '방 정리');
    });
  });
}
