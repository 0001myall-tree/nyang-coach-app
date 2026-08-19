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
    });

    test('기능 얘기는 빼둔다', () {
      // 이 갈래의 통찰은 코치를 가리지 않는다. 프렌즈도 받는 문구라
      // 마스터에만 있는 화면을 여기서 가리키면 안 된다.
      expect(rule, isNot(contains('기록 탭')));
      expect(rule, isNot(contains('[HABIT')));
    });

    test('짚이는 시각이 있으면 거기서 해보자고 한다', () {
      // 기능 없이도 줄 수 있는 실행 하나는 남겨둔다.
      expect(rule, contains('다음엔 거기서 해보자고 한 번만'));
    });

    test('오늘 다시 밀지 않는다', () {
      // 이 갈래로 왔다는 건 오늘은 안 붙는다는 뜻이다.
      expect(rule, contains('다시 밀지 말 것'));
    });
  });

  group('마스터에만 붙는 안내', () {
    const tracking = Prompts.focusBestStartTimeTracking;

    test('기록 탭이 시작 시간대를 찾아준다고 알린다', () {
      expect(tracking, contains('기록 탭'));
      expect(tracking, contains('완료로 이어진 적이 많았던 시작 시간대'));
    });

    test('등록을 재촉하지 않는다', () {
      expect(tracking, contains('한 번만 안내'));
      expect(tracking, contains('재촉하지 말 것'));
      // 태그는 사용자가 부탁했을 때만. 출력 규칙과 어긋나면 안 된다.
      expect(tracking, contains('걸어달라고 하면 그때 [HABIT: 루틴명]'));
    });
  });

  group('결과 불안', () {
    test('무거운 판에도 두 번째 걸음 얘기가 들어갔다', () {
      expect(Prompts.thoughtOverload, contains('두 번째는 더 쉬워진다'));
    });

    group('프렌즈용 가벼운 판', () {
      const light = Prompts.resultAnxietyLight;

      test('결과를 붙잡을수록 불안해진다고 짚는다', () {
        expect(light, contains('결과를 붙잡고 있을수록 불안이 커진다'));
        // 조심스러워진 걸 게으름으로 읽지 않게 한 줄 받아준다.
        expect(light, contains('소중해서 조심스러워진'));
      });

      test('오늘 할 수 있는 한 걸음으로 내린다', () {
        expect(light, contains('딱 한 걸음'));
        expect(light, contains('두 번째는 더 쉬워진다'));
      });

      test('무거운 처방은 빠져 있다', () {
        // 30분 글쓰기와 판단 기준 적기는 마스터 판에만 있는 처방이다.
        expect(light, isNot(contains('30분')));
        expect(light, isNot(contains('판단 기준')));
      });

      test('짧게 끝내고 태그를 붙이지 않는다', () {
        expect(light, contains('3문장 이내'));
        expect(light, contains('[TASK]와 [TIMER_CONFIRM]은 붙이지 말 것'));
      });
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
