import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/screen_open_target.dart';

void main() {
  group('코치가 가리킨 화면 읽기', () {
    test('탭 이름 그대로', () {
      expect(ScreenOpenTarget.read('여기 있어. [OPEN: 목표]'), 'goals');
      expect(ScreenOpenTarget.read('[OPEN: 기록]'), 'records');
      expect(ScreenOpenTarget.read('[OPEN: 설정]'), 'settings');
    });

    test('탭·화면 같은 뒷말이 붙어 와도 받는다', () {
      // 프롬프트에는 이름만 적으라고 했지만 모델은 화면 지도에서 읽은 대로
      // '할 일 탭 > 오늘'을 옮겨 적기도 한다. 여기서 안 받으면 코치는
      // 열어주겠다고 말해놓고 아무 일도 일으키지 않는다.
      expect(ScreenOpenTarget.read('[OPEN: 오늘 탭]'), 'today');
      expect(ScreenOpenTarget.read('[OPEN: 캘린더화면]'), 'schedule');
      expect(ScreenOpenTarget.read('[OPEN: 루틴 텝]'), 'habit');
    });

    test('사용자가 쓰는 옛 이름도 알아듣는다', () {
      expect(ScreenOpenTarget.read('[OPEN: 습관]'), 'habit');
      expect(ScreenOpenTarget.read('[OPEN: 달력]'), 'schedule');
      expect(ScreenOpenTarget.read('[OPEN: 할일]'), 'today');
    });

    test('비전은 목표와 다른 자리로 간다', () {
      expect(ScreenOpenTarget.read('[OPEN: 비전]'), 'vision');
      expect(ScreenOpenTarget.read('[OPEN: 마일스톤]'), 'vision');
    });

    test('태그가 없으면 아무 데도 안 간다', () {
      expect(ScreenOpenTarget.read('오늘 탭에서 오른쪽으로 밀면 완료야.'), isNull);
    });

    test('모르는 이름이면 열지 않는다', () {
      // 지어낸 탭으로 데려가느니 그 자리에 있는 편이 낫다.
      expect(ScreenOpenTarget.read('[OPEN: 대시보드]'), isNull);
      expect(ScreenOpenTarget.read('[OPEN: ]'), isNull);
    });

    test('둘을 적어 보내면 첫 번째만', () {
      expect(ScreenOpenTarget.read('[OPEN: 목표][OPEN: 기록]'), 'goals');
    });
  });

  group('본문에서 태그 지우기', () {
    test('모르는 이름이어도 대괄호는 남기지 않는다', () {
      expect(ScreenOpenTarget.strip('여기야. [OPEN: 대시보드]'), '여기야.');
    });

    test('지운 자리에 빈 줄이 쌓이지 않는다', () {
      expect(
        ScreenOpenTarget.strip('열어줄게.\n\n[OPEN: 목표]\n\n'),
        '열어줄게.',
      );
    });
  });
}
