import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/screens/focus_timer_widget.dart';

/// 남은 시간만큼 진하게 찍힌 발자국 수.
///
/// 진하기로 센다. 사라진 발자국도 자리는 지키고 흐려지기만 하기 때문에,
/// 개수를 세면 언제나 스무 개가 나온다.
int litPaws(WidgetTester tester) {
  return tester
      .widgetList<Opacity>(
        find.ancestor(
          of: find.byType(SvgPicture),
          matching: find.byType(Opacity),
        ),
      )
      .where((o) => o.opacity == 1)
      .length;
}

Future<void> pumpRing(WidgetTester tester, double progress) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: PawRing(progress: progress, size: 300)),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('물이 있어도 발자국 수는 그대로다', (tester) async {
    // 물결은 분위기고 눈금은 발자국이다. 둘이 같은 값을 다르게 말하면 안 된다.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PawRing(
              progress: 0.5,
              size: 300,
              wave: AlwaysStoppedAnimation(0.3),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(litPaws(tester), 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('물결을 꺼도 그려진다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PawRing(progress: 0.5, size: 300, showWater: false),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(litPaws(tester), 10);
  });

  testWidgets('시작할 때는 원이 발자국으로 가득 찬다', (tester) async {
    await pumpRing(tester, 1.0);
    expect(litPaws(tester), 20);
  });

  testWidgets('반쯤 지나면 절반이 사라진다', (tester) async {
    await pumpRing(tester, 0.5);
    expect(litPaws(tester), 10);
  });

  testWidgets('거의 끝나면 몇 개만 남는다', (tester) async {
    await pumpRing(tester, 0.2);
    expect(litPaws(tester), 4);
  });

  testWidgets('다 끝나면 하나도 안 남는다', (tester) async {
    await pumpRing(tester, 0.0);
    expect(litPaws(tester), 0);
  });

  testWidgets('시간이 다 됐는데 하나 남아 보이지 않는다', (tester) async {
    // 반올림하면 0.98개가 1개로 올라가 시계는 00:00인데 발자국이 남는다.
    await pumpRing(tester, 0.03);
    expect(litPaws(tester), 0);
  });

  testWidgets('자리는 늘 스무 개다', (tester) async {
    await pumpRing(tester, 0.5);
    expect(find.byType(SvgPicture), findsNWidgets(20));
  });

  testWidgets('범위를 벗어난 값에도 깨지지 않는다', (tester) async {
    await pumpRing(tester, 1.7);
    expect(litPaws(tester), 20);
    await pumpRing(tester, -0.4);
    expect(litPaws(tester), 0);
    expect(tester.takeException(), isNull);
  });
}
