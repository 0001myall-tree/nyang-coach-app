import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/task_move_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 할 일을 다른 날로 옮기는 일을 화면 없이 한다.
///
/// 밤 카드에서 "내일로 옮길래"를 누르면 그 자리에서는 답만 남고, 앱이 켜질 때
/// 여기를 지나며 실제로 옮겨진다.
void main() {
  final tomorrow = DateTime(2026, 9, 24);

  void seed({
    List<Map<String, dynamic>> tasks = const [],
    List<Map<String, dynamic>> cores = const [],
    Map<String, dynamic> schedules = const {},
  }) {
    SharedPreferences.setMockInitialValues({
      'nyang_tasks': jsonEncode(tasks),
      'nyang_core_tasks': jsonEncode(cores),
      'nyang_schedules': jsonEncode(schedules),
    });
  }

  Future<Map> storedSchedules(SharedPreferences prefs) async =>
      jsonDecode(prefs.getString('nyang_schedules') ?? '{}') as Map;

  Future<List> storedTasks(SharedPreferences prefs) async =>
      jsonDecode(prefs.getString('nyang_tasks') ?? '[]') as List;

  test('오늘 목록에서 빠지고 그 날짜 칸으로 들어간다', () async {
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트'},
        {'id': 'b', 'text': '방 정리'},
      ],
    );
    final prefs = await SharedPreferences.getInstance();

    expect(
      await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow),
      isTrue,
    );

    expect((await storedTasks(prefs)).length, 1);
    final day = (await storedSchedules(prefs))['2026-09-24'] as List;
    expect((day.first as Map)['text'], '분기 리포트');
  });

  test('시각도 알람도 없이 넘긴다', () async {
    // 밤에 카드 한 번 누르면서 내일 몇 시에 할지까지 고르게 할 수는 없다.
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트', 'timeStart': '15:00'},
      ],
    );
    final prefs = await SharedPreferences.getInstance();

    await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow);

    final entry =
        ((await storedSchedules(prefs))['2026-09-24'] as List).first as Map;
    expect(entry.containsKey('timeStart'), isFalse);
    expect(entry['isReminderEnabled'], isFalse);
  });

  test('미룬 횟수와 메모는 따라간다', () async {
    // 세 번째 미루는 사람에게는 다른 말을 해야 한다.
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트', 'deferredCount': 2, 'memo': '3장부터'},
      ],
    );
    final prefs = await SharedPreferences.getInstance();

    await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow);

    final entry =
        ((await storedSchedules(prefs))['2026-09-24'] as List).first as Map;
    expect(entry['deferredCount'], 3);
    expect(entry['memo'], '3장부터');
  });

  test('핵심으로 찍혀 있으면 같이 뺀다', () async {
    // 목록에 없는 핵심이 남으면 오늘 탭이 없는 일을 붙들게 된다.
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트'},
      ],
      cores: [
        {'id': 'a', 'text': '분기 리포트'},
      ],
    );
    final prefs = await SharedPreferences.getInstance();

    await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow);

    expect(jsonDecode(prefs.getString('nyang_core_tasks')!), isEmpty);
  });

  test('그 날짜에 이미 있던 것은 그대로 둔다', () async {
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트'},
      ],
      schedules: {
        '2026-09-24': [
          {'id': 'x', 'text': '치과'},
        ],
      },
    );
    final prefs = await SharedPreferences.getInstance();

    await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow);

    final day = (await storedSchedules(prefs))['2026-09-24'] as List;
    expect(day.length, 2);
    expect((day.first as Map)['text'], '치과');
  });

  test('없는 일이나 끝낸 일은 옮기지 않는다', () async {
    seed(
      tasks: [
        {'id': 'a', 'text': '분기 리포트', 'done': true},
      ],
    );
    await SharedPreferences.getInstance();

    expect(
      await TaskMoveService.moveStoredTask(taskId: 'a', to: tomorrow),
      isFalse,
    );
    expect(
      await TaskMoveService.moveStoredTask(taskId: 'gone', to: tomorrow),
      isFalse,
    );
  });
}
