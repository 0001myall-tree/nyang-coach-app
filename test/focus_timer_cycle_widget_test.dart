import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/screens/focus_timer_widget.dart';
import 'package:nyang_coach/services/focus_cycle.dart';
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
    testWidgets('제목 없이 시계만 있다', (tester) async {
      // 가운데 'MASTER TIMER'와 오른쪽 '전체 보기'가 좁은 기기에서 서로
      // 파고들었다. 카드 안에 시계가 큼직해서 제목 없이도 뭔지 안다.
      await pumpTimer(tester, coachId: 'nyang_halbae');
      expect(find.text('MASTER TIMER'), findsNothing);
      expect(find.text('MIND TIMER'), findsNothing);
    });

    testWidgets('시계가 한 줄로 나온다', (tester) async {
      // 전체 보기를 시계 옆에 뒀을 때 폭을 빼앗겨 "24:40"이 두 줄로 쪼개졌다.
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 25,
        size: const Size(320, 700),
      );
      expect(find.text('25:00'), findsOneWidget);
      final clock = tester.getSize(find.text('25:00'));
      expect(clock.height, lessThan(70), reason: '두 줄로 쪼개졌다');
    });

    testWidgets('전체 보기는 시계 위 오른쪽 끝에 혼자 있다', (tester) async {
      // 좁은 기기에서 제목과 겹치던 자리다. 이제 그 줄에 다른 글자가 없다.
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        size: const Size(320, 700),
      );
      final button = tester.getRect(find.text('전체 보기'));
      final clock = tester.getRect(find.text('15:00'));
      expect(button.bottom, lessThan(clock.top), reason: '시계 위');
      expect(button.center.dx, greaterThan(clock.center.dx), reason: '오른쪽 끝');
    });

    testWidgets('시작 전에는 전체 화면 버튼이 집중 시작이다', (tester) async {
      // 눌러본 적 없는 타이머에 "다시 시작"이라고 하면 자기가 뭘 멈춘 줄 안다.
      await pumpTimer(tester, coachId: 'nyang_halbae');
      await tester.tap(find.text('전체 보기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('집중 시작'), findsOneWidget);
      expect(find.text('다시 시작'), findsNothing);
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

  group('말로 시간을 지정한 판', () {
    // 반복 설정이 있으면 그게 요청한 시간을 이겨서, "5분 타이머 띄워줘"가
    // 설정의 작업 시간으로 바뀌었다. 그래서 설정 시트에 있는 값
    // (10·15·25·30·50·60·90)만 나오는 것처럼 보였다.
    const oneOff = {'focus_timer_one_off': true};

    testWidgets('요약 줄이 반복 대신 이번 판 시간을 적는다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 5,
        extraPrefs: {...savedPomodoro, ...oneOff},
      );
      expect(find.text('이번만 5분'), findsOneWidget);
      expect(find.text('25분 집중 · 5분 휴식 · 4회 반복'), findsNothing);
    });

    testWidgets('설정 시트에 없는 값도 그대로 뜬다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 20,
        extraPrefs: {...savedPomodoro, ...oneOff},
      );
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('이번만 20분'), findsOneWidget);
    });

    // 시작 버튼은 눌러볼 수 없다. 알림 플러그인을 부르는데 테스트에는 없다.
    // 그래서 시작이 따르는 판단만 떼어내 확인한다.
    test('시작은 반복을 비켜가고 지정한 시간으로 돈다', () {
      final manager = FocusTimerManager()
        ..cycleSetting = FocusCycleSetting.pomodoro
        ..stage = 5
        ..oneOffMinutes = true;
      expect(manager.cycleSettingForStart, isNull);

      manager.oneOffMinutes = false;
      expect(manager.cycleSettingForStart, FocusCycleSetting.pomodoro);
    });

    testWidgets('설정을 안 걸어둔 판은 예전처럼 반복으로 돈다', (tester) async {
      await pumpTimer(
        tester,
        coachId: 'nyang_halbae',
        minutes: 5,
        extraPrefs: savedPomodoro,
      );
      expect(find.text('25분 집중 · 5분 휴식 · 4회 반복'), findsOneWidget);
      expect(find.textContaining('이번만'), findsNothing);
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
