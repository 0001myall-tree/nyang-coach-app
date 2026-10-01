import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 켜둔 채 날을 넘긴 일은 자정에 멈춘 것으로 친다.
///
/// 그대로 보관하면 어제 기록에 "진행 중"이 남고, 그 일로 냥냥이가 다음 날에도
/// "하는 중이야?"를 묻는다.
void main() {
  final morning = DateTime(2026, 10, 1, 8, 0);

  test('밤 11시에 켜고 잔 일은 자정까지 한 시간으로 남고 멈춘다', () {
    final tasks = <Map<String, dynamic>>[
      {
        'id': 'a',
        'text': '방정리',
        'inProgress': true,
        'inProgressAt': '2026-09-30T22:30:00.000',
        'runStartedAt': '2026-09-30T23:00:00.000',
        'elapsedSeconds': 600,
      },
    ];

    DailyResetService.closeOvernightRuns(tasks, morning);

    final task = tasks.first;
    expect(task['inProgress'], isFalse);
    expect(task['runStartedAt'], isNull);
    // 앞서 쌓인 10분 + 자정까지 1시간.
    expect(task['elapsedSeconds'], 600 + 3600);
    expect(task['pausedAt'], '2026-10-01T00:00:00.000');
    // 처음 시작한 시각은 그대로다.
    expect(task['inProgressAt'], '2026-09-30T22:30:00.000');
  });

  test('오늘 시작한 일은 건드리지 않는다', () {
    final tasks = <Map<String, dynamic>>[
      {
        'id': 'a',
        'inProgress': true,
        'runStartedAt': '2026-10-01T07:30:00.000',
        'elapsedSeconds': 0,
      },
    ];

    DailyResetService.closeOvernightRuns(tasks, morning);

    expect(tasks.first['inProgress'], isTrue);
    expect(tasks.first['runStartedAt'], '2026-10-01T07:30:00.000');
  });

  test('일시정지해둔 일과 끝낸 일은 그대로', () {
    final tasks = <Map<String, dynamic>>[
      {'id': 'paused', 'inProgress': false, 'elapsedSeconds': 300},
      {'id': 'done', 'done': true, 'inProgress': false},
    ];

    DailyResetService.closeOvernightRuns(tasks, morning);

    expect(tasks[0]['elapsedSeconds'], 300);
    expect(tasks[1]['done'], isTrue);
  });

  test('시계 없이 진행 중으로만 찍힌 옛 기록은 멈추기만 한다', () {
    final tasks = <Map<String, dynamic>>[
      {'id': 'old', 'inProgress': true, 'elapsedSeconds': 0},
    ];

    DailyResetService.closeOvernightRuns(tasks, morning);

    expect(tasks.first['inProgress'], isFalse);
    expect(tasks.first['elapsedSeconds'], 0);
  });
}
