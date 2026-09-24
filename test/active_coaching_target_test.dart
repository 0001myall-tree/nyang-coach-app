import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_target.dart';

/// 적극 코칭이 지금 말을 걸 일 하나를 고르는 자리.
///
/// 고르는 일을 모델에게 맡기지 않으므로, 같은 목록이면 늘 같은 답이 나와야
/// 한다. 여기서 모든 경우를 지어 넣고 무엇을 잡는지 확인한다.
void main() {
  final now = DateTime(2026, 9, 23, 15, 0);

  Map task(
    String id, {
    String? text,
    bool done = false,
    bool inProgress = false,
    String? timeStart,
    int elapsedSeconds = 0,
    String? pausedAt,
    String category = 'today',
    String? createdAt,
  }) => {
    'id': id,
    'text': text ?? '할 일 $id',
    'done': done,
    if (inProgress) 'inProgress': true,
    if (timeStart != null) 'timeStart': timeStart,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    if (pausedAt != null) 'pausedAt': pausedAt,
    'category': category,
    if (createdAt != null) 'createdAt': createdAt,
  };

  group('말을 걸지 않는 때', () {
    test('지금 붙잡고 있는 일이 있으면 아무것도 안 잡는다', () {
      // 다른 일이 아무리 밀려 있어도, 하고 있는 사람에게 말을 거는 것은 방해다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('a', inProgress: true),
          task('b', timeStart: '10:00'),
        ],
        now: now,
      );
      expect(pick.isNone, isTrue);
    });

    test('오늘 할 일을 다 끝냈으면 그날은 조용하다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', done: true), task('b', done: true)],
        now: now,
      );
      expect(pick.isNone, isTrue);
    });

    test('적어둔 것이 아예 없는 날도 돌지 않는다', () {
      // 계획을 세우자고 권하는 말은 낮 알림과 아침 인사가 맡는다.
      final pick = ActiveCoachingTarget.pick(tasks: const [], now: now);
      expect(pick.isNone, isTrue);
    });

    test('약속은 대상이 아니다', () {
      // 그 시각에 가서 하는 것이라 지금 당겨 할 자리가 없다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', category: 'schedule', timeStart: '10:00')],
        now: now,
      );
      expect(pick.isNone, isTrue);
    });

    test('이미 결정이 난 일은 빼고 본다', () {
      // "오늘은 안 하기로" 한 일을 다시 짚으면 그 결정을 못 들은 것이 된다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', timeStart: '10:00')],
        now: now,
        settled: {'a'},
      );
      expect(pick.isNone, isTrue);
    });
  });

  group('사다리 순서', () {
    test('약속한 시각이 됐으면 그것이 가장 먼저', () {
      // 시작 시각이 훨씬 오래 지난 일이 있어도, 사용자가 직접 정한 시각이 먼저다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('late', timeStart: '09:00'),
          task('promised'),
        ],
        now: now,
        promises: {'promised': DateTime(2026, 9, 23, 14, 30)},
      );
      expect(pick.signal, ActiveCoachingSignal.promised);
      expect(pick.taskId, 'promised');
    });

    test('아직 약속 시각 전이면 그 일은 안 잡는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('promised')],
        now: now,
        promises: {'promised': DateTime(2026, 9, 23, 16, 0)},
      );
      // 남은 일이 그것 하나라 물어볼 것도 없다. 약속한 시각까지 기다린다.
      expect(pick.isNone, isTrue);
    });

    test('시작 시각 30분이 지나야 잡는다', () {
      final tasks = [task('a', timeStart: '14:31')];
      // 29분 지난 시점에는 아직 아니다.
      expect(ActiveCoachingTarget.pick(tasks: tasks, now: now).isNone, isTrue);
      // 딱 30분이 되면 잡는다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', timeStart: '14:30')],
        now: now,
      );
      expect(pick.signal, ActiveCoachingSignal.lateStart);
      expect(pick.taskId, 'a');
    });

    test('한 번이라도 손댄 일은 시작 놓침이 아니라 멈춘 일이다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', timeStart: '10:00', elapsedSeconds: 720)],
        now: now,
      );
      expect(pick.signal, ActiveCoachingSignal.paused);
    });

    test('눌렀다 곧바로 멈춘 일도 멈춘 일로 센다', () {
      // 쌓인 시간이 0이라 시작 표시만 보면 "안 건드린 일"로 새어 나간다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', pausedAt: '2026-09-23T13:00:00')],
        now: now,
      );
      expect(pick.signal, ActiveCoachingSignal.paused);
    });

    test('시작 놓침이 멈춘 일보다 먼저다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('paused', elapsedSeconds: 600),
          task('late', timeStart: '13:00'),
        ],
        now: now,
      );
      expect(pick.taskId, 'late');
    });

    test('멈춘 일이 핵심보다 먼저다', () {
      // 핵심이라도 손도 안 댄 일보다, 이미 손댄 일이 문턱이 낮다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('core'), task('paused', elapsedSeconds: 600)],
        now: now,
        coreTasks: [task('core')],
      );
      expect(pick.signal, ActiveCoachingSignal.paused);
      expect(pick.taskId, 'paused');
    });

    test('신호가 핵심뿐이면 핵심을 잡는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('core'), task('etc')],
        now: now,
        coreTasks: [task('core')],
      );
      expect(pick.signal, ActiveCoachingSignal.core);
      expect(pick.taskId, 'core');
    });

    test('시각을 적어둔 핵심은 그 시각 전에 안 짚는다', () {
      // 저녁 8시에 하기로 한 일을 오후 3시에 "아직 그대로네"라고 하면 틀린 말이다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('core', timeStart: '20:00'),
          task('etc'),
        ],
        now: now,
        coreTasks: [task('core', timeStart: '20:00')],
      );
      expect(pick.signal, ActiveCoachingSignal.askUser);
    });

    test('핵심은 이름으로도 찾는다', () {
      // 핵심 목록이 id 없이 이름만 들고 있는 경우가 있다.
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', text: '보고서')],
        now: now,
        coreTasks: const [
          {'text': '보고서'},
        ],
      );
      expect(pick.signal, ActiveCoachingSignal.core);
    });
  });

  group('앱이 고르지 않는 자리', () {
    test('신호가 하나도 없으면 남은 일을 들고 물어본다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a'), task('b'), task('c', done: true)],
        now: now,
      );
      expect(pick.needsUserPick, isTrue);
      expect(pick.task, isNull);
      expect(pick.candidates.map((item) => item['id']), ['a', 'b']);
    });

    test('남은 일이 하나뿐이면 고르라고 묻지 않고 그 일을 부른다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a'), task('b', done: true)],
        now: now,
      );
      expect(pick.signal, ActiveCoachingSignal.onlyLeft);
      expect(pick.taskId, 'a');
    });

    test('하나뿐이어도 시각을 적어둔 일은 그 시각 전에 당겨 부르지 않는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', timeStart: '20:00')],
        now: now,
      );
      expect(pick.isNone, isTrue);
    });

    test('핵심을 안 찍어둔 사람에게 잡무를 골라 짚지 않는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a'), task('b')],
        now: now,
        coreTasks: const [],
      );
      expect(pick.signal, ActiveCoachingSignal.askUser);
    });
  });

  group('같은 일만 계속 잡지 않기', () {
    test('바로 앞에서 다룬 일은 한 번 건너뛴다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('a', timeStart: '09:00'),
          task('b', timeStart: '10:00'),
        ],
        now: now,
        skipTaskId: 'a',
      );
      expect(pick.signal, ActiveCoachingSignal.lateStart);
      expect(pick.taskId, 'b');
    });

    test('건너뛰고 나니 남는 것이 없으면 말을 걸지 않는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [task('a', timeStart: '09:00')],
        now: now,
        skipTaskId: 'a',
      );
      expect(pick.isNone, isTrue);
    });
  });

  group('같은 칸에 여럿일 때', () {
    test('시각이 이른 것을 잡는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('later', timeStart: '13:00'),
          task('earlier', timeStart: '09:00'),
        ],
        now: now,
      );
      expect(pick.taskId, 'earlier');
    });

    test('시각이 같으면 먼저 적은 것을 잡는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('new', timeStart: '09:00', createdAt: '2026-09-23T08:00:00'),
          task('old', timeStart: '09:00', createdAt: '2026-09-23T07:00:00'),
        ],
        now: now,
      );
      expect(pick.taskId, 'old');
    });

    test('멈춘 지 오래된 것을 잡는다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('recent', elapsedSeconds: 60, pausedAt: '2026-09-23T14:00:00'),
          task('old', elapsedSeconds: 60, pausedAt: '2026-09-23T11:00:00'),
        ],
        now: now,
      );
      expect(pick.taskId, 'old');
    });

    test('멈춘 시각을 모르는 일은 뒤로 보낸다', () {
      final pick = ActiveCoachingTarget.pick(
        tasks: [
          task('unknown', elapsedSeconds: 60),
          task('known', elapsedSeconds: 60, pausedAt: '2026-09-23T14:00:00'),
        ],
        now: now,
      );
      expect(pick.taskId, 'known');
    });
  });
}
