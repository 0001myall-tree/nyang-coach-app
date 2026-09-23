import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/theme/app_design_tokens.dart';
import 'package:nyang_coach/widgets/banner_answer_dialog.dart';

/// 배너를 눌러 들어왔을 때 뜨는 답변 팝업.
///
/// 보기가 오른쪽에 텍스트로만 붙어 계단처럼 보이던 자리다. 질문은 왼쪽,
/// 보기는 오른쪽이라 눈이 두 번 움직였다.
void main() {
  Future<void> show(
    WidgetTester tester, {
    required String message,
    required List<BannerAnswerAction> actions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BannerAnswerDialog(message: message, actions: actions),
      ),
    );
    await tester.pump();
  }

  final runningActions = [
    const BannerAnswerAction(label: '다 했어', icon: 'circle-check'),
    const BannerAnswerAction(
      label: '계속하는 중',
      icon: 'fa-circle-play-solid',
      isPrimary: true,
    ),
    const BannerAnswerAction(
      label: '다시 시작할게',
      icon: 'fa-arrow-rotate-left-solid',
    ),
  ];

  testWidgets('보기 셋이 같은 너비로 세로로 선다', (tester) async {
    await show(
      tester,
      message: "아까 시작한 '앱 개발',\n지금은 어떻게 하고 있어?",
      actions: runningActions,
    );

    final boxes = [
      for (final label in ['다 했어', '계속하는 중', '다시 시작할게'])
        tester.getRect(
          find
              .ancestor(of: find.text(label), matching: find.byType(Container))
              .first,
        ),
    ];

    // 너비가 같고
    expect(boxes[1].width, boxes[0].width);
    expect(boxes[2].width, boxes[0].width);
    // 왼쪽 끝이 같고
    expect(boxes[1].left, boxes[0].left);
    expect(boxes[2].left, boxes[0].left);
    // 위에서 아래로 선다
    expect(boxes[1].top, greaterThan(boxes[0].bottom));
    expect(boxes[2].top, greaterThan(boxes[1].bottom));
  });

  testWidgets('질문과 보기가 같은 세로선에서 시작한다', (tester) async {
    await show(
      tester,
      message: '아까 시작한 일,\n지금은 어떻게 하고 있어?',
      actions: runningActions,
    );

    final question = tester.getRect(find.textContaining('아까 시작한'));
    final firstAction = tester.getRect(
      find
          .ancestor(of: find.text('다 했어'), matching: find.byType(Container))
          .first,
    );
    expect(question.left, firstAction.left);
  });

  testWidgets('primary는 하나뿐이고 색이 갈린다', (tester) async {
    await show(
      tester,
      message: '아까 시작한 일,\n지금은 어떻게 하고 있어?',
      actions: runningActions,
    );

    Color colorOf(String label) {
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.text(label), matching: find.byType(Container))
            .first,
      );
      return ((container.decoration as BoxDecoration).color)!;
    }

    expect(colorOf('계속하는 중'), AppDesignTokens.brand);
    expect(colorOf('다 했어'), AppDesignTokens.brandSoft);
    expect(colorOf('다시 시작할게'), AppDesignTokens.brandSoft);
    expect(runningActions.where((a) => a.isPrimary).length, 1);
  });

  testWidgets('긴 할 일 이름이 들어와도 넘치지 않는다', (tester) async {
    // 할 일 이름이 그대로 질문에 들어간다. 사용자가 길게 적으면 그만큼 길어진다.
    await show(
      tester,
      message:
          "아까 시작한 '${'아주 긴 할 일 이름을 적어두는 사람도 있다' * 3}',\n"
          '지금은 어떻게 하고 있어?',
      actions: runningActions,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('일정 이름이 길면 팝업도 같이 넓어진다', (tester) async {
    // 늘 최대 폭으로 서 있으면 짧은 질문에도 빈 자리가 넓게 남는다.
    Future<double> widthFor(String message) async {
      await show(tester, message: message, actions: runningActions);
      return tester.getSize(find.text('계속하는 중')).width;
    }

    final short = await widthFor("아까 시작한 '앱 개발',\n지금은 어떻게 하고 있어?");
    final long = await widthFor(
      "아까 시작한 '분기 리포트 초안 정리하고 팀에 공유하기',\n지금은 어떻게 하고 있어?",
    );

    expect(long, greaterThan(short));
  });

  testWidgets('보기가 둘일 때도 같은 모양이다', (tester) async {
    await show(
      tester,
      message: "'앱 개발' 시작할 시간이야.\n준비됐으면 눌러줘.",
      actions: [
        const BannerAnswerAction(
          label: '시작하기',
          icon: 'fa-circle-play-solid',
          isPrimary: true,
        ),
        const BannerAnswerAction(label: '나중에', icon: 'fa-clock-regular'),
      ],
    );

    expect(find.text('시작하기'), findsOneWidget);
    expect(find.text('나중에'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('누르면 팝업이 닫히고 그 일이 일어난다', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => BannerAnswerDialog(
                  message: '아까 시작한 일,\n지금은 어떻게 하고 있어?',
                  actions: [
                    BannerAnswerAction(
                      label: '다 했어',
                      icon: 'circle-check',
                      onTap: () => tapped = true,
                    ),
                  ],
                ),
              ),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('다 했어'));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.text('다 했어'), findsNothing);
  });
}
