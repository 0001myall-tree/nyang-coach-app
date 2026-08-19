import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/task_completion_service.dart';

/// 화면 없이 완료 처리가 되는지 본다.
///
/// 이 일은 원래 플래너 화면 안에만 있어서, 앱 밖에서 완료를 눌러도 그 화면을
/// 열기 전까지는 아무 데도 반영되지 않았다. 이제 저장된 데이터만 보고 고친다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> task(
    String id,
    String text, {
    bool done = false,
    String? habitId,
    int elapsedSeconds = 0,
    String? runStartedAt,
  }) => {
    'id': id,
    'text': text,
    'category': 'today',
    'done': done,
    if (habitId != null) 'habitId': habitId,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    if (runStartedAt != null) 'runStartedAt': runStartedAt,
  };

  Map<String, dynamic> record(String date, {int total = 2, int done = 0}) => {
    'date': date,
    'totalCount': total,
    'doneCount': done,
    'success': done > 0,
    'isVacation': false,
    'tasks': <Map<String, dynamic>>[],
  };

  List<Map<String, dynamic>> readList(SharedPreferences prefs, String key) =>
      (jsonDecode(prefs.getString(key) ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  Map<String, dynamic> readMap(SharedPreferences prefs, String key) =>
      Map<String, dynamic>.from(
        jsonDecode(prefs.getString(key) ?? '{}') as Map,
      );

  group('오늘 할 일을 완료로 바꾼다', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task('1', '집필'),
          task('2', '청소'),
        ]),
        'nyang_last_date': '2026-08-19',
        TaskCompletionService.historyKey: jsonEncode([record('2026-08-19')]),
      });
      prefs = await SharedPreferences.getInstance();
    });

    test('완료 표시와 시각이 남는다', () async {
      final applied = await TaskCompletionService.completeStoredTask(
        taskId: '1',
      );
      expect(applied, isTrue);

      final tasks = readList(prefs, TaskCompletionService.tasksKey);
      expect(tasks.first['done'], isTrue);
      expect(tasks.first['completedAt'], isNotNull);
      expect(tasks.first['inProgress'], isFalse);
      // 손대지 않은 것은 그대로다.
      expect(tasks[1]['done'], isFalse);
    });

    test('그날 기록의 완료 개수가 다시 세어진다', () async {
      await TaskCompletionService.completeStoredTask(taskId: '1');

      final history = readList(prefs, TaskCompletionService.historyKey);
      final today = history.firstWhere((h) => h['date'] == '2026-08-19');
      expect(today['doneCount'], 1);
      expect(today['totalCount'], 2);
      expect(today['success'], isTrue);
    });

    test('두 번 불러도 개수가 부풀지 않는다', () async {
      await TaskCompletionService.completeStoredTask(taskId: '1');
      final again = await TaskCompletionService.completeStoredTask(taskId: '1');
      expect(again, isFalse);

      final history = readList(prefs, TaskCompletionService.historyKey);
      expect(history.first['doneCount'], 1);
    });

    test('없는 일은 아무것도 바꾸지 않는다', () async {
      final applied = await TaskCompletionService.completeStoredTask(
        taskId: '없음',
      );
      expect(applied, isFalse);
    });

    test('바뀐 시각을 남겨서 열려 있던 화면이 다시 읽게 한다', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 1));
      await TaskCompletionService.completeStoredTask(taskId: '1');
      expect(await TaskCompletionService.changedSince(before), isTrue);
    });
  });

  group('실행 시간', () {
    test('돌고 있던 구간까지 더해 굳힌다', () async {
      final startedAt = DateTime.now().subtract(const Duration(minutes: 10));
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task(
            '1',
            '집필',
            elapsedSeconds: 300,
            runStartedAt: startedAt.toIso8601String(),
          ),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final saved = readList(prefs, TaskCompletionService.tasksKey).first;
      // 쌓여 있던 5분 + 돌던 10분.
      expect((saved['actualSeconds'] as int) >= 890, isTrue);
      expect(saved['runStartedAt'], isNull);
    });

    test('잠깐 멈춤은 완료로 만들지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task('1', '집필', elapsedSeconds: 60),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.pauseStoredTask(taskId: '1');

      final saved = readList(prefs, TaskCompletionService.tasksKey).first;
      expect(saved['done'], isFalse);
      expect(saved['inProgress'], isFalse);
    });
  });

  group('같이 따라가는 것들', () {
    test('핵심 일정에도 같은 표시가 남는다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([task('1', '집필')]),
        TaskCompletionService.coreTasksKey: jsonEncode([task('1', '집필')]),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final core = readList(prefs, TaskCompletionService.coreTasksKey).first;
      expect(core['done'], isTrue);
    });

    test('습관이면 그날 도장이 찍힌다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task('1', '운동', habitId: 'h1'),
        ]),
        'nyang_last_date': '2026-08-19',
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final logs = readMap(prefs, TaskCompletionService.habitLogsKey);
      expect(logs['h1']['2026-08-19']['done'], isTrue);
    });

    test('앱에서 이미 적어둔 도장은 덮어쓰지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task('1', '운동', habitId: 'h1'),
        ]),
        'nyang_last_date': '2026-08-19',
        TaskCompletionService.habitLogsKey: jsonEncode({
          'h1': {
            '2026-08-19': {'done': true, 'count': 30, 'unit': '분'},
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final logs = readMap(prefs, TaskCompletionService.habitLogsKey);
      expect(logs['h1']['2026-08-19']['count'], 30);
    });

    test('주 n회 습관은 한 날만 분모에 넣는다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([
          task('1', '집필'),
          task('2', '헬스', habitId: 'h1'),
        ]),
        TaskCompletionService.habitsKey: jsonEncode([
          {'id': 'h1', 'name': '헬스', 'freq': 'weekly_count'},
        ]),
        'nyang_last_date': '2026-08-19',
        TaskCompletionService.historyKey: jsonEncode([record('2026-08-19')]),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final today = readList(
        prefs,
        TaskCompletionService.historyKey,
      ).firstWhere((h) => h['date'] == '2026-08-19');
      // 오늘 안 한 주 n회 습관은 빠져서 1개 중 1개가 된다.
      expect(today['totalCount'], 1);
      expect(today['doneCount'], 1);
    });

    test('기록에 있던 이월·마일스톤 항목은 그대로 둔다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([task('1', '집필')]),
        'nyang_last_date': '2026-08-19',
        TaskCompletionService.historyKey: jsonEncode([
          {
            'date': '2026-08-19',
            'totalCount': 2,
            'doneCount': 1,
            'success': true,
            'tasks': [
              {'text': '어제 못한 것', 'done': true, 'deferred': true},
              {'text': '1장 마치기', 'done': false, 'category': 'milestone'},
            ],
          },
        ]),
      });
      final prefs = await SharedPreferences.getInstance();

      await TaskCompletionService.completeStoredTask(taskId: '1');

      final today = readList(prefs, TaskCompletionService.historyKey).first;
      final texts = (today['tasks'] as List)
          .map((e) => e['text'])
          .toList(growable: false);
      expect(texts, contains('어제 못한 것'));
      expect(texts, contains('1장 마치기'));
      // 이월 완료 1 + 오늘 완료 1.
      expect(today['doneCount'], 2);
    });
  });

  group('며칠 지나 도착한 완료', () {
    test('보관 중인 지난 날에서 찾아 채운다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([task('9', '오늘 할 일')]),
        DailyResetService.plannedTasksByDateKey: jsonEncode({
          '2026-08-17': [task('1', '집필')],
        }),
        TaskCompletionService.historyKey: jsonEncode([record('2026-08-17')]),
      });
      final prefs = await SharedPreferences.getInstance();

      final applied = await TaskCompletionService.completeStoredTask(
        taskId: '1',
        at: DateTime(2026, 8, 19, 9),
      );
      expect(applied, isTrue);

      final byDate = readMap(
        prefs,
        DailyResetService.plannedTasksByDateKey,
      );
      expect((byDate['2026-08-17'] as List).first['done'], isTrue);

      final past = readList(
        prefs,
        TaskCompletionService.historyKey,
      ).firstWhere((h) => h['date'] == '2026-08-17');
      expect(past['doneCount'], 1);
    });

    test('앞으로 세워둔 계획은 건드리지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        TaskCompletionService.tasksKey: jsonEncode([task('9', '오늘 할 일')]),
        DailyResetService.plannedTasksByDateKey: jsonEncode({
          '2026-08-25': [task('1', '다음주 집필')],
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final applied = await TaskCompletionService.completeStoredTask(
        taskId: '1',
        at: DateTime(2026, 8, 19, 9),
      );
      expect(applied, isFalse);

      final byDate = readMap(prefs, DailyResetService.plannedTasksByDateKey);
      expect((byDate['2026-08-25'] as List).first['done'], isFalse);
    });
  });
}
