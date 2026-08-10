import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/prompts/coach_prompt.dart';

void main() {
  group('집중력 저하 세 번째 갈래', () {
    const rule = Prompts.focusBestStartTime;

    test('앞의 둘을 써본 뒤에 꺼내는 것임을 밝힌다', () {
      expect(rule, contains('환기와 짧은 집중을 이미 권한 뒤'));
    });

    test('억지로 미는 게 답이 아니라고 짚는다', () {
      expect(rule, contains('억지로 붙잡으려 할수록'));
      // 안 되는 걸 사용자 탓으로 돌리면 이 앱이 하려는 것과 반대가 된다.
      expect(rule, contains('사용자 탓이 아니라는 뜻'));
    });

    test('시간대를 찾는 쪽으로 옮긴다', () {
      expect(rule, contains('잘 붙는 시간대'));
      expect(rule, contains('기록 탭'));
    });

    test('등록을 재촉하지 않는다', () {
      expect(rule, contains('한 번만 안내'));
      expect(rule, contains('재촉하지 말 것'));
      // 태그는 사용자가 부탁했을 때만. 출력 규칙과 어긋나면 안 된다.
      expect(rule, contains('걸어달라고 하면 그때 [HABIT: 습관명]'));
    });

    test('오늘 다시 밀지 않는다', () {
      // 이 갈래로 왔다는 건 오늘은 안 붙는다는 뜻이다.
      expect(rule, contains('다시 밀지 말 것'));
    });
  });

  group('앞의 두 갈래는 그대로', () {
    test('환기와 짧은 집중 단위가 남아 있다', () {
      expect(Prompts.focusFatigue, contains('인지적 환기'));
      expect(Prompts.focusFatigue, contains('짧은 집중 단위'));
    });

    test('시작도 못 한 사람에게 환기를 권하지 않는다', () {
      expect(Prompts.focusFatigue, contains('아직 시작도 못 했다'));
      expect(Prompts.focusFatigue, contains('첫 조각'));
    });
  });
}
