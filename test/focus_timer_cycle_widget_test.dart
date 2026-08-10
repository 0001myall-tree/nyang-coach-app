import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/screens/focus_timer_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 타이머 카드를 실제 화면 너비로 그려본다.
///
/// 저장된 코치·시간을 미리 넣어두는 건 초기화가 "처음부터 다시" 경로를 타지
/// 않게 하려는 것이다. 그 경로는 알림과 소리 플러그인을 부르는데, 테스트에는
/// 그 플러그인이 없어서 화면이 영영 안 그려진다.
Future<void> pumpTimer(
  WidgetTester tester, {
  required String coachId,
  int minutes = 15,
  Map<String, Object> extraPrefs = const {},
  Size size = const Size(360, 780),
}) async {
  SharedPreferences.setMockInitialValues({
    'focus_timer_coach_id': coachId,
    'focus_timer_stage': minutes,
    'focus_timer_duration': minutes * 60,
    'focus_timer_running': false,
    ...extraPrefs,
  });

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: FocusTimerWidget(
          coachId: coachId,
          initialMinutes: minutes,
          onMessage: (_) {},
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

const savedPomodoro = {
  'focus_timer_cycle_setting': '{"work":25,"rest":5,"rounds":4}',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('마스터 타이머', () {
    testWidgets('제목이 MASTER TIMER다', (tester) async {
      await pumpTimer(tester, coachId: 'nyang_halbae');
      expect(find.text('MASTER TIMER'), findsOneWidget);
    });

    testWidgets('15분·25분·직접 설정 셋만 나온다', (tester) async {
      await pumpTimer(tester, coachId: 'nyang_halbae');
      expect(find.text('15분'), findsOneWidget);
      expect(find.text('25분'), findsOneWidget);
      expect(find.text('직접 설정'), findsOneWidget);
      // 5분 자리를 직접 설정에 내줬다.
      expect(find.text('5분'), findsNothing);
    });

    testWidgets('버튼 셋의 너비가 같다', (tester) async {
      // 글자 길이가 달라도 칸은 같아야 한다. 가운데 정렬로 두면 "직접 설정"만
      // 넓어서 줄이 한쪽으로 쏠려 보인다.
      await pumpTimer(tester, coachId: 'nyang_halbae');
      double slotWidth(String label) => tester
          .getSize(
            find
                .ancestor(of: find.text(label), matching: find.byType(Padding))
                .first,
          )
          .width;
      expect(slotWidth('15분'), closeTo(slotWidth('직접 설정'), 0.5));
      expect(slotWidth('25분'), closeTo(slotWidth('직접 설정'), 0.5));
    });

    testWidgets('좁은 화면에서도 넘치지 않는다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        size: const Size(300, 700),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('직접 설정'), findsOneWidget);
    });

    testWidgets('직접 설정을 누르면 세 항목이 나온다', (tester) async {
      await pumpTimer(tester, coachId: 'nyang_halbae');
      await tester.tap(find.text('직접 설정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('시간 설정 변경'), findsOneWidget);
      expect(find.text('작업 시간'), findsOneWidget);
      expect(find.text('쉬는 시간'), findsOneWidget);
      expect(find.text('반복 횟수'), findsOneWidget);
      expect(find.text('이 설정으로 저장'), findsOneWidget);
    });

    testWidgets('기본값은 포모도로이고 총 시간을 보여준다', (tester) async {
      await pumpTimer(tester, coachId: 'nyang_halbae');
      await tester.tap(find.text('직접 설정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 25×4 + 5×3 = 115분. 마지막 휴식은 빠진다.
      expect(find.text('1시간 55분'), findsOneWidget);
    });

    testWidgets('처음 열 때는 되돌리는 길이 없다', (tester) async {
      // 아직 저장한 적이 없으면 끌 것도 없다.
      await pumpTimer(tester, coachId: 'nyang_halbae');
      await tester.tap(find.text('직접 설정'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('반복 끄고'), findsNothing);
    });
  });

  group('프렌즈 타이머', () {
    testWidgets('제목이 그대로고 직접 설정이 없다', (tester) async {
      await pumpTimer(tester, coachId: 'cat');
      // 프렌즈는 카드 자체가 다르다. 제목도 영문이 아니라 '집중 시간'이다.
      expect(find.text('집중 시간'), findsOneWidget);
      expect(find.text('MASTER TIMER'), findsNothing);
      // 반복 설정은 마스터 코치 기능이다.
      expect(find.text('직접 설정'), findsNothing);
      expect(find.text('5분'), findsOneWidget);
    });
  });

  group('저장해둔 설정이 있을 때', () {
    testWidgets('빠른 선택 대신 요약 줄이 뜬다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 25,
        extraPrefs: savedPomodoro,
      );
      expect(find.text('25분 집중 · 5분 휴식 · 4회 반복'), findsOneWidget);
      expect(find.text('설정 변경'), findsOneWidget);
      // 둘을 같이 두면 어느 값으로 시작하는지 헷갈린다.
      expect(find.text('15분'), findsNothing);
      expect(find.text('직접 설정'), findsNothing);
    });

    testWidgets('설정 변경을 누르면 저장한 값이 들어가 있다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 25,
        extraPrefs: savedPomodoro,
      );
      await tester.tap(find.text('설정 변경'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('1시간 55분'), findsOneWidget);
      expect(find.textContaining('반복 끄고'), findsOneWidget);
    });

    testWidgets('프렌즈 코치는 같은 설정이 있어도 쓰지 않는다', (tester) async {
      await pumpTimer(tester, coachId: 'cat', extraPrefs: savedPomodoro);
      expect(find.text('25분 집중 · 5분 휴식 · 4회 반복'), findsNothing);
      expect(find.text('5분'), findsOneWidget);
    });
  });
}
