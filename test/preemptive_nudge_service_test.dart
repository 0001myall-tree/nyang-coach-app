import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/preemptive_nudge_service.dart';

Map<String, dynamic> task(
  String text, {
  bool done = false,
  bool inProgress = false,
  String? inProgressAt,
  int elapsedSeconds = 0,
  int deferredCount = 0,
  String category = 'today',
  String? habitId,
}) {
  return {
    'text': text,
    'done': done,
    'inProgress': inProgress,
    if (inProgressAt != null) 'inProgressAt': inProgressAt,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    if (deferredCount > 0) 'deferredCount': deferredCount,
    'category': category,
    if (habitId != null) 'habitId': habitId,
  };
}

Map<String, dynamic> day(String date, List<String> texts) => {
  'date': date,
  'tasks': texts.map((t) => {'text': t, 'category': 'today'}).toList(),
};

PreemptiveNudge? decide({
  List<dynamic> todayTasks = const [],
  List<dynamic> coreTasks = const [],
  List<dynamic> history = const [],
}) {
  return PreemptiveNudgeService.decide(
    todayTasks: todayTasks,
    coreTasks: coreTasks,
    history: history,
  );
}

void main() {
  group('이미 움직이는 사람은 부르지 않는다', () {
    test('완료한 일이 있으면 조용하다', () {
      expect(decide(todayTasks: [task('청소', done: true)]), isNull);
    });

    test('시작 표시가 있으면 조용하다', () {
      expect(decide(todayTasks: [task('청소', inProgress: true)]), isNull);
    });

    test('시작 버튼을 거쳤다 멈춘 것도 움직인 것이다', () {
      expect(
        decide(todayTasks: [task('청소', inProgressAt: '2026-08-16T09:00:00')]),
        isNull,
      );
    });

    test('타이머만 돌렸어도 조용하다', () {
      expect(decide(todayTasks: [task('청소', elapsedSeconds: 300)]), isNull);
    });
  });

  group('계획이 비어 있을 때', () {
    test('아무것도 없으면 계획을 세우자고 한다', () {
      final nudge = decide();
      expect(nudge?.kind, NudgeKind.noPlan);
      expect(PreemptiveNudgeService.noPlanMessages, contains(nudge!.message));
    });

    test('시작을 거드는 말도 계획 없는 날에 쓸 수 있다', () {
      // "3분만 하자"는 계획이 없는 사람에게도 통한다. 반대로 계획을 청하는
      // 말은 계획을 세워둔 사람에게 쓰면 틀린 말이 된다.
      for (final message in PreemptiveNudgeService.notStartedMessages) {
        expect(PreemptiveNudgeService.noPlanMessages, contains(message));
      }
      for (final message in PreemptiveNudgeService.planMessages) {
        expect(
          PreemptiveNudgeService.notStartedMessages,
          isNot(contains(message)),
        );
      }
    });

    test('습관만 채워져 있는 건 계획을 세운 게 아니다', () {
      final nudge = decide(
        todayTasks: [task('물 마시기', category: 'habit', habitId: 'h1')],
      );
      expect(nudge?.kind, NudgeKind.noPlan);
    });
  });

  group('미뤄놓고 다시 올린 일', () {
    test('그 일 이름을 부르며 줄여주겠다고 한다', () {
      final nudge = decide(
        todayTasks: [task('보고서', deferredCount: 1), task('청소')],
      );
      expect(nudge?.kind, NudgeKind.deferredAgain);
      expect(nudge?.taskName, '보고서');
      expect(nudge?.message, contains('보고서'));
    });

    test('며칠째 넘어간 일에는 미는 말을 쓰지 않는다', () {
      for (var i = 0; i < 30; i++) {
        final nudge = decide(todayTasks: [task('보고서', deferredCount: 2)]);
        expect(
          PreemptiveNudgeService.longDeferredMessages.map(
            (m) => m.replaceAll('{{task}}', '보고서'),
          ),
          contains(nudge!.message),
        );
        expect(nudge.message, isNot(contains('시작해! 시작해!')));
      }
    });

    test('여러 개면 제일 오래 넘어간 것을 부른다', () {
      final nudge = decide(
        todayTasks: [
          task('청소', deferredCount: 1),
          task('보고서', deferredCount: 4),
        ],
      );
      expect(nudge?.taskName, '보고서');
    });

    test('미룬 적 없으면 이 분기가 아니다', () {
      final nudge = decide(todayTasks: [task('보고서')]);
      expect(nudge?.kind, NudgeKind.notStarted);
    });
  });

  group('일정은 있는데 시작을 못 했을 때', () {
    test('핵심으로 찍은 일을 먼저 부른다', () {
      final nudge = decide(
        todayTasks: [task('청소'), task('보고서')],
        coreTasks: [task('보고서')],
      );
      expect(nudge?.kind, NudgeKind.notStarted);
      expect(nudge?.taskName, '보고서');
    });

    test('핵심이 없으면 습관을 부른다', () {
      final nudge = decide(
        todayTasks: [
          task('청소'),
          task('스트레칭', category: 'habit', habitId: 'h1'),
        ],
      );
      expect(nudge?.taskName, '스트레칭');
    });

    test('핵심도 습관도 없으면 요즘 반복되던 일을 부른다', () {
      final nudge = decide(
        todayTasks: [task('장보기'), task('4화 쓰기')],
        history: [
          day('2026-08-10', ['1화 쓰기']),
          day('2026-08-11', ['2화 쓰기']),
          day('2026-08-12', ['3화 쓰기']),
        ],
      );
      expect(nudge?.taskName, '4화 쓰기');
    });

    test('이름을 부를 때는 자리를 채워서 내보낸다', () {
      // 문구에 {{task}} 자리가 남아 있으면 그대로 사용자에게 나간다.
      for (var i = 0; i < 30; i++) {
        final named = decide(
          todayTasks: [task('보고서')],
          coreTasks: [task('보고서')],
        );
        expect(named!.message, isNot(contains('{{task}}')));
        expect(named.message, contains('보고서'));

        final deferred = decide(todayTasks: [task('보고서', deferredCount: 1)]);
        expect(deferred!.message, isNot(contains('{{task}}')));
        expect(deferred.message, contains('보고서'));
      }
    });

    test('부를 근거가 없으면 이름 없이 부른다', () {
      final nudge = decide(todayTasks: [task('장보기')]);
      expect(nudge?.kind, NudgeKind.notStarted);
      expect(nudge?.taskName, isNull);
      expect(
        PreemptiveNudgeService.notStartedMessages,
        contains(nudge!.message),
      );
    });
  });

  group('저장했다 되읽기', () {
    test('보낸 말을 그대로 되살린다', () {
      final nudge = decide(todayTasks: [task('보고서', deferredCount: 2)]);
      final restored = PreemptiveNudge.fromJson(nudge!.toJson());
      expect(restored?.kind, nudge.kind);
      expect(restored?.message, nudge.message);
      expect(restored?.taskName, nudge.taskName);
    });

    test('깨진 값은 없는 것으로 본다', () {
      expect(PreemptiveNudge.fromJson(null), isNull);
      expect(PreemptiveNudge.fromJson({'kind': 'noPlan'}), isNull);
      expect(PreemptiveNudge.fromJson({'message': '안녕'}), isNull);
    });
  });
}
