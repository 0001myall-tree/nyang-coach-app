import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_move.dart';
import 'package:nyang_coach/widgets/active_coaching_dialog.dart';

/// 적극 코칭 팝업.
///
/// 첫 화면은 안드로이드 카드와 같은 넷이다. 한 수(지금 할 수 있는 조각)를
/// 묻는 단계는 하루를 닫는 카드와 부를 일이 없는 카드에서 온 길에 남아 있다.
void main() {
  /// 팝업을 띄우고 닫힐 때의 답을 받아온다.
  Future<ActiveCoachingOutcome?> show(
    WidgetTester tester, {
    required Future<ActiveCoachingMoves?> Function(List<String>, String?)
    askMoves,
    List<ActiveCoachingChoice> otherTasks = const [],
    List<DateTime> timeChoices = const [],
    String taskName = '분기 리포트',
    bool skipReason = false,
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
                  taskName: taskName,
                  skipReason: skipReason,
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

  testWidgets('카드와 같은 넷을 먼저 보여준다', (tester) async {
    await show(tester, askMoves: twoMoves);
    expect(find.textContaining('아직이네'), findsOneWidget);
    for (final label in ['지금 할게', '시간이 안 나', '여기선 못 해', '하기 싫어']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  Future<ActiveCoachingOutcome?> tapFirst(
    WidgetTester tester,
    List<String> labels,
  ) async {
    ActiveCoachingOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await showDialog<ActiveCoachingOutcome>(
                context: context,
                builder: (_) => ActiveCoachingDialog(
                  taskName: '영양제 먹기',
                  askMoves: noMoves,
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
    for (final label in labels) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }
    return outcome;
  }

  testWidgets('지금 할게는 그 일을 시작한다', (tester) async {
    final outcome = await tapFirst(tester, ['지금 할게']);
    expect(outcome?.kind, ActiveCoachingOutcomeKind.start);
    expect(outcome?.taskName, '영양제 먹기');
  });

  testWidgets('하기 싫어는 대화창으로 넘긴다', (tester) async {
    final outcome = await tapFirst(tester, ['하기 싫어']);
    expect(outcome?.kind, ActiveCoachingOutcomeKind.reluctant);
  });

  testWidgets('여기선 못 해 → 내일로 옮길래', (tester) async {
    final outcome = await tapFirst(tester, ['여기선 못 해', '내일로 옮길래']);
    expect(outcome?.kind, ActiveCoachingOutcomeKind.moveTomorrow);
  });

  testWidgets('여기선 못 해 → 오늘은 안 할래', (tester) async {
    final outcome = await tapFirst(tester, ['여기선 못 해', '오늘은 안 할래']);
    expect(outcome?.kind, ActiveCoachingOutcomeKind.notToday);
  });

  testWidgets('시간이 안 나면 한 수 없이 시각으로 간다', (tester) async {
    var asked = false;
    await show(
      tester,
      askMoves: (names, reason) async {
        asked = true;
        return null;
      },
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
    await tester.tap(find.text('시간이 안 나'));
    await tester.pumpAndSettle();
    expect(asked, isFalse);
    expect(find.textContaining('몇 시부터'), findsOneWidget);
  });

  testWidgets('여기선 못 해면 이따·내일·오늘은 안 함을 고른다', (tester) async {
    await show(
      tester,
      askMoves: twoMoves,
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
    await tester.tap(find.text('여기선 못 해'));
    await tester.pumpAndSettle();
    expect(find.text('이따 할게'), findsOneWidget);
    expect(find.text('내일로 옮길래'), findsOneWidget);
    expect(find.text('오늘은 안 할래'), findsOneWidget);

    await tester.tap(find.text('이따 할게'));
    await tester.pumpAndSettle();
    expect(find.textContaining('몇 시부터'), findsOneWidget);
  });

  testWidgets('한 수를 받아오면 둘을 보여준다', (tester) async {
    await show(tester, askMoves: twoMoves, skipReason: true);
    expect(find.text('개요 세 줄 적기'), findsOneWidget);
    expect(find.text('자료 링크 모으기'), findsOneWidget);
    expect(find.text('지금은 둘 다 안 돼'), findsOneWidget);
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
                  skipReason: true,
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
    await tester.tap(find.text('개요 세 줄 적기'));
    await tester.pumpAndSettle();

    expect(outcome?.kind, ActiveCoachingOutcomeKind.start);
    expect(outcome?.taskName, '분기 리포트');
    expect(outcome?.move, '개요 세 줄 적기');
    expect(outcome?.reason, isNull);
  });

  testWidgets('한 수를 물렀는데 남은 일이 있으면 고르게 한다', (tester) async {
    await show(
      tester,
      skipReason: true,
      askMoves: twoMoves,
      otherTasks: const [
        ActiveCoachingChoice(name: '방 정리'),
        ActiveCoachingChoice(name: '운동', timeLabel: '오후 8:00'),
      ],
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
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
      skipReason: true,
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
      skipReason: true,
      askMoves: (names, reason) async {
        asked = names;
        return ActiveCoachingMoves(task: names.first, moves: const ['치우기']);
      },
      otherTasks: const [
        ActiveCoachingChoice(name: '방 정리'),
        ActiveCoachingChoice(name: '메일 답장'),
      ],
    );
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
      skipReason: true,
      askMoves: (names, reason) async =>
          ActiveCoachingMoves(task: names.first, moves: const ['치우기']),
      otherTasks: const [ActiveCoachingChoice(name: '방 정리')],
      timeChoices: [DateTime(2026, 9, 23, 16, 30)],
    );
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
      skipReason: true,
      askMoves: noMoves,
      otherTasks: const [ActiveCoachingChoice(name: '방 정리')],
    );
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
    await tester.tap(find.text('시간이 안 나'));
    await tester.pumpAndSettle();
    // 상대 표현을 쓰지 않는다. "30분 뒤"는 반올림하면 거짓말이 된다.
    await tester.tap(find.text('4:30'));
    await tester.pumpAndSettle();

    expect(outcome?.kind, ActiveCoachingOutcomeKind.promise);
    expect(outcome?.promisedAt, at);
    expect(outcome?.reason, '시간이 안 나');
  });

  testWidgets('시작 카드에서 미룬 사람에게는 이유를 묻지 않는다', (tester) async {
    // 스스로 미루겠다고 말한 참이다. 이유는 약속한 시각에 또 안 했을 때 묻는다.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<ActiveCoachingOutcome>(
              context: context,
              builder: (_) => ActiveCoachingDialog(
                taskName: '분기 리포트',
                askMoves: noMoves,
                askTimeOnly: true,
                timeChoices: [DateTime(2026, 9, 23, 16, 30)],
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('왜 못 했어'), findsNothing);
    expect(find.textContaining('몇 시부터'), findsOneWidget);
    expect(find.text('4:30'), findsOneWidget);
  });

  testWidgets('하루를 닫는 카드에서 온 사람에게는 이유를 묻지 않는다', (tester) async {
    // "10분만 해볼게"를 누르고 온 참이다. 왜 못 했냐고 물으면 앞뒤가 안 맞는다.
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<ActiveCoachingOutcome>(
              context: context,
              builder: (_) => ActiveCoachingDialog(
                taskName: '분기 리포트',
                askMoves: twoMoves,
                skipReason: true,
                timeChoices: const [],
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.textContaining('왜 못 했어'), findsNothing);
    expect(find.text('개요 세 줄 적기'), findsOneWidget);
  });

  testWidgets('목록에서 갈아탄 일에는 표시가 남는다', (tester) async {
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
                  askMoves: (names, reason) async => ActiveCoachingMoves(
                    task: names.first,
                    moves: const ['치우기'],
                  ),
                  otherTasks: const [ActiveCoachingChoice(name: '방 정리')],
                  skipReason: true,
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
    await tester.tap(find.text('지금은 안 되겠어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('방 정리'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('이걸로'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('치우기'));
    await tester.pumpAndSettle();

    expect(outcome?.taskName, '방 정리');
    expect(outcome?.pickedFromList, isTrue);
  });

  testWidgets('밤이라 고를 시각이 없으면 하루를 닫는 말로 간다', (tester) async {
    await show(tester, askMoves: noMoves);
    await tester.tap(find.text('시간이 안 나'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘은 여기까지'), findsOneWidget);
    expect(find.text('직접 고르기'), findsOneWidget);
  });

  testWidgets('코치가 일을 골라주는 동안 빈 따옴표를 띄우지 않는다', (tester) async {
    final pending = Completer<ActiveCoachingMoves?>();
    await show(
      tester,
      taskName: '',
      askMoves: (names, reason) => pending.future,
      otherTasks: const [ActiveCoachingChoice(name: '책 읽기')],
    );
    await tester.tap(find.text('모르겠어, 골라줘'));
    await tester.pump();
    expect(find.text('지금 뭘 해볼까?'), findsOneWidget);
    expect(find.textContaining("''"), findsNothing);
    pending.complete(null);
    await tester.pumpAndSettle();
  });
}
