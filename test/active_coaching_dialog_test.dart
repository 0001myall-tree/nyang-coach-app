import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_move.dart';
import 'package:nyang_coach/widgets/active_coaching_dialog.dart';

/// "못 했어" 다음에 이어지는 팝업.
///
/// 이유 → 한 수 → 갈아타기 → 시각 순서다. 시간부터 물으면 앱이 스누즈 기계가
/// 되고, 왜 못 하는지 모르니 매번 같은 말만 하게 된다.
void main() {
  /// 팝업을 띄우고 닫힐 때의 답을 받아온다.
  Future<ActiveCoachingOutcome?> show(
    WidgetTester tester, {
    required Future<ActiveCoachingMoves?> Function(List<String>, String?)
    askMoves,
    List<ActiveCoachingChoice> otherTasks = const [],
    List<DateTime> timeChoices = const [],
  }) async {
    ActiveCoachingOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await showDialog<ActiveCoachingOutcome>(
                context: context,
                builder: (_) => ActiveCoachingDialog(
                  taskName: '분기 리포트',
                  askMoves: askMoves,
                  otherTasks: otherTasks,
                  timeChoices: timeChoices,
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    return outcome;
  }

  Future<ActiveCoachingMoves?> twoMoves(
    List<String> names,
    String? reason,
  ) async => ActiveCoachingMoves(
    task: names.first,
    moves: const ['개요 세 줄 적기', '자료 링크 모으기'],
  );

  Future<ActiveCoachingMoves?> noMoves(
    List<String> names,
    String? reason,
  ) async => null;

  testWidgets('이유부터 묻는다', (tester) async {
    await show(tester, askMoves: twoMoves);
    expect(find.textContaining('왜 못 했어'), findsOneWidget);
    expect(find.text('머리가 안 돌아가'), findsOneWidget);
  });

  testWidgets('이유를 고르면 한 수 둘을 보여준다', (tester) async {
    await show(tester, askMoves: twoMoves);
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    expect(find.text('개요 세 줄 적기'), findsOneWidget);
    expect(find.text('자료 링크 모으기'), findsOneWidget);
    expect(find.text('지금은 둘 다 안 돼'), findsOneWidget);
  });

  testWidgets('받아둔 이유를 그대로 넘긴다', (tester) async {
    String? seen;
    await show(
      tester,
      askMoves: (names, reason) async {
        seen = reason;
        return ActiveCoachingMoves(task: names.first, moves: const ['개요 적기']);
      },
    );
    await tester.tap(find.text('부담돼서'));
    await tester.pumpAndSettle();
    // 물어놓고 안 넘기면 물어본 의미가 없다.
    expect(seen, '부담돼서');
  });

  testWidgets('자리가 아닌 이유면 한 수를 건너뛰고 시각으로 간다', (tester) async {
    var asked = false;
    await show(
      tester,
      askMoves: (names, reason) async {
        asked = true;
        return null;
      },
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
    await tester.tap(find.text('지금은 시간이 안 나'));
    await tester.pumpAndSettle();
    // 회의 중인 사람에게 쪼개주는 것은 소용이 없다.
    expect(asked, isFalse);
    expect(find.textContaining('몇 시부터'), findsOneWidget);
  });

  testWidgets('한 수를 고르면 그 일을 시작한다', (tester) async {
    ActiveCoachingOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await showDialog<ActiveCoachingOutcome>(
                context: context,
                builder: (_) => ActiveCoachingDialog(
                  taskName: '분기 리포트',
                  askMoves: twoMoves,
                  timeChoices: const [],
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('개요 세 줄 적기'));
    await tester.pumpAndSettle();

    expect(outcome?.kind, ActiveCoachingOutcomeKind.start);
    expect(outcome?.taskName, '분기 리포트');
    expect(outcome?.move, '개요 세 줄 적기');
    expect(outcome?.reason, '머리가 안 돌아가');
  });

  testWidgets('한 수를 물렀는데 남은 일이 있으면 고르게 한다', (tester) async {
    await show(
      tester,
      askMoves: twoMoves,
      otherTasks: const [
        ActiveCoachingChoice(name: '방 정리'),
        ActiveCoachingChoice(name: '운동', timeLabel: '오후 8:00'),
      ],
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 둘 다 안 돼'));
    await tester.pumpAndSettle();

    expect(find.textContaining('지금 조금이라도 할 수 있는 건'), findsOneWidget);
    expect(find.text('방 정리'), findsOneWidget);
    expect(find.text('오후 8:00'), findsOneWidget);
    // 아무것도 안 고른 것과 "모르겠어"는 같은 말이다.
    expect(find.text('모르겠어, 골라줘'), findsOneWidget);
  });

  testWidgets('목록에서 고르면 그 일로 다시 묻는다', (tester) async {
    List<String>? asked;
    await show(
      tester,
      askMoves: (names, reason) async {
        asked = names;
        return ActiveCoachingMoves(
          task: names.first,
          moves: const ['다섯 개만 치우기'],
        );
      },
      otherTasks: const [
        ActiveCoachingChoice(name: '방 정리'),
        ActiveCoachingChoice(name: '메일 답장'),
      ],
    );
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 안 되겠어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방 정리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이걸로'));
    await tester.pumpAndSettle();

    expect(asked, ['방 정리']);
    expect(find.text('다섯 개만 치우기'), findsOneWidget);
  });

  testWidgets('아무것도 안 고르면 남은 일 전부를 넘긴다', (tester) async {
    List<String>? asked;
    await show(
      tester,
      askMoves: (names, reason) async {
        asked = names;
        return ActiveCoachingMoves(task: names.first, moves: const ['치우기']);
      },
      otherTasks: const [
        ActiveCoachingChoice(name: '방 정리'),
        ActiveCoachingChoice(name: '메일 답장'),
      ],
    );
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 안 되겠어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모르겠어, 골라줘'));
    await tester.pumpAndSettle();

    expect(asked, ['방 정리', '메일 답장']);
  });

  testWidgets('갈아탄 뒤에 또 물리면 시각을 묻는다', (tester) async {
    // 한 개입 안에서 갈아타기는 한 번까지. 두 번 넘어가면 심문이 된다.
    await show(
      tester,
      askMoves: (names, reason) async =>
          ActiveCoachingMoves(task: names.first, moves: const ['치우기']),
      otherTasks: const [ActiveCoachingChoice(name: '방 정리')],
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 안 되겠어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('모르겠어, 골라줘'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 안 되겠어'));
    await tester.pumpAndSettle();

    expect(find.textContaining('몇 시부터'), findsOneWidget);
  });

  testWidgets('한 수를 못 받아와도 팝업이 그냥 닫히지 않는다', (tester) async {
    // 한도가 찼거나 통신이 끊긴 경우다. 사용자는 아무것도 못 고른 채 끝나면 안 된다.
    await show(
      tester,
      askMoves: noMoves,
      otherTasks: const [ActiveCoachingChoice(name: '방 정리')],
    );
    await tester.tap(find.text('머리가 안 돌아가'));
    await tester.pumpAndSettle();
    expect(find.textContaining('지금 조금이라도 할 수 있는 건'), findsOneWidget);
  });

  testWidgets('시각을 고르면 약속으로 남는다', (tester) async {
    ActiveCoachingOutcome? outcome;
    final at = DateTime(2026, 9, 23, 16, 30);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await showDialog<ActiveCoachingOutcome>(
                context: context,
                builder: (_) => ActiveCoachingDialog(
                  taskName: '분기 리포트',
                  askMoves: noMoves,
                  timeChoices: [at],
                ),
              );
            },
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지금은 시간이 안 나'));
    await tester.pumpAndSettle();
    // 상대 표현을 쓰지 않는다. "30분 뒤"는 반올림하면 거짓말이 된다.
    await tester.tap(find.text('4:30'));
    await tester.pumpAndSettle();

    expect(outcome?.kind, ActiveCoachingOutcomeKind.promise);
    expect(outcome?.promisedAt, at);
    expect(outcome?.reason, '지금은 시간이 안 나');
  });

  testWidgets('밤이라 고를 시각이 없으면 하루를 닫는 말로 간다', (tester) async {
    await show(tester, askMoves: noMoves);
    await tester.tap(find.text('지금은 시간이 안 나'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘은 여기까지'), findsOneWidget);
    expect(find.text('직접 고르기'), findsOneWidget);
  });
}
