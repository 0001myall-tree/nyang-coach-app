import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:nyang_coach/services/task_resistance_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 저항 이벤트는 "하기 싫다고 했고 결국 해냈다"는 저녁 인사의 근거가 된다.
/// 여기가 틀리면 크래시 없이 코치가 하지도 않은 일을 축하한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// 할 일 목록을 심는다. 저항 감지는 이 목록만 보고 판정한다.
  void seedTasks(List<Map<String, dynamic>> tasks) {
    SharedPreferences.setMockInitialValues({'nyang_tasks': jsonEncode(tasks)});
  }

  Map<String, dynamic> task(
    String id,
    String text, {
    bool done = false,
    String category = 'today',
  }) => {'id': id, 'text': text, 'category': category, 'done': done};

  test('계획에 없는 일은 하기 싫다고 해도 기록하지 않는다', () async {
    // 설거지는 계획에 아예 없다. 완료도 미완료도 아닌 상태다.
    seedTasks([task('1', '빨래')]);

    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫어');

    // 이벤트가 없으니 "결국 해냈다"고 말할 근거도 생기지 않는다.
    // 이 경우는 저녁 인사가 직접 물어본다(eveningOffPlanAsk).
    expect(await TaskResistanceService.getAllEvents(), isEmpty);
  });

  test('계획에 있는 일은 기록하되 완료로 치지 않는다', () async {
    seedTasks([task('1', '설거지')]);

    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫어');

    final events = await TaskResistanceService.getAllEvents();
    expect(events, hasLength(1));
    expect(events.single.taskText, '설거지');
    expect(events.single.signalType, 'explicit');
    // 말만 한 시점에는 아직 아무것도 하지 않았다.
    expect(events.single.completedEventually, isFalse);
  });

  test('실제로 완료해야 완료로 바뀐다', () async {
    seedTasks([task('1', '설거지')]);
    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫어');

    await TaskResistanceService.onTaskCompleted(
      taskId: '1',
      date: today(),
      completionOrder: 1,
      totalTasksThatDay: 1,
    );

    final events = await TaskResistanceService.getAllEvents();
    expect(events.single.completedEventually, isTrue);
  });

  test('다른 일을 완료해도 싫다던 일이 완료로 바뀌지 않는다', () async {
    seedTasks([task('1', '설거지'), task('2', '빨래')]);
    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫어');

    await TaskResistanceService.onTaskCompleted(
      taskId: '2',
      date: today(),
      completionOrder: 1,
      totalTasksThatDay: 2,
    );

    final events = await TaskResistanceService.getAllEvents();
    expect(events.single.taskText, '설거지');
    expect(events.single.completedEventually, isFalse);
  });

  test('이미 끝낸 일을 두고 한 말은 저항으로 기록하지 않는다', () async {
    seedTasks([task('1', '설거지', done: true)]);

    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫었어');

    expect(await TaskResistanceService.getAllEvents(), isEmpty);
  });

  test('같은 일을 하루에 여러 번 싫다고 해도 한 건이다', () async {
    seedTasks([task('1', '설거지')]);

    await TaskResistanceService.detectAndRecordFromMessage('설거지 하기 싫어');
    await TaskResistanceService.detectAndRecordFromMessage('설거지 진짜 하기 싫다');

    expect(await TaskResistanceService.getAllEvents(), hasLength(1));
  });
}
