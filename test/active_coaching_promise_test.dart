import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_promise.dart';
import 'package:nyang_coach/services/active_coaching_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "몇 시에 할게"를 적어두는 자리.
///
/// 할 일의 시작 시각에 넣으면 화면·위젯·캘린더·기존 시작 카드가 딸려온다.
/// 원래 시각은 따로 남긴다 — 덮어쓰기만 하면 "3시에 하기로 했다가 못 했다"가
/// 사라지는데, 세 번째 미루는 사람에게는 다른 말을 해야 한다.
void main() {
  final at = DateTime(2026, 9, 23, 16, 30);

  Future<List> storedTasks(SharedPreferences prefs) =>
      Future.value(jsonDecode(prefs.getString('nyang_tasks') ?? '[]') as List);

  void seed(List<Map<String, dynamic>> tasks) {
    SharedPreferences.setMockInitialValues({'nyang_tasks': jsonEncode(tasks)});
  }

  test('할 일의 시작 시각에 넣는다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    expect(await ActiveCoachingPromise.keep(taskId: 'a', at: at), isTrue);

    final tasks = await storedTasks(prefs);
    expect((tasks.first as Map)['timeStart'], '16:30');
    expect(ActiveCoachingStore.readDay(prefs, at).of('a').promisedAt, at);
  });

  test('목록에 보이는 시각도 함께 바꾸고, 약속 표시를 남긴다', () async {
    // 화면은 보여줄 시각을 시작 시각보다 먼저 읽는다. 그 칸이 옛 값이면
    // 약속을 해도 옛 시각이 보인다.
    seed([
      {'id': 'a', 'text': '영양제 먹기', 'timeStart': '09:00', 'time': '오전 9:00'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.keep(taskId: 'a', at: at);

    final task = (await storedTasks(prefs)).first as Map;
    expect(task['time'], '오후 4:30');
    expect(task[ActiveCoachingPromise.promisedStartKey], '16:30');
  });

  test('원래 시각은 첫 약속에서만 챙긴다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트', 'timeStart': '15:00'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.keep(taskId: 'a', at: at);
    await ActiveCoachingPromise.keep(
      taskId: 'a',
      at: DateTime(2026, 9, 23, 18),
    );

    // 두 번째에서 다시 읽으면 첫 약속으로 덮인 값이 "원래 시각"이 된다.
    final tracking = ActiveCoachingStore.readDay(prefs, at).of('a');
    expect(tracking.originalStart, '15:00');
    expect(tracking.promisedAt, DateTime(2026, 9, 23, 18));
  });

  test('끝 시각이 새 시작보다 앞이면 버린다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트', 'timeStart': '14:00', 'timeEnd': '15:00'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.keep(taskId: 'a', at: at);

    final tasks = await storedTasks(prefs);
    expect((tasks.first as Map).containsKey('timeEnd'), isFalse);
  });

  test('뒤에 남는 끝 시각은 그대로 둔다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트', 'timeStart': '14:00', 'timeEnd': '18:00'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.keep(taskId: 'a', at: at);

    final tasks = await storedTasks(prefs);
    expect((tasks.first as Map)['timeEnd'], '18:00');
  });

  test('없는 일에는 아무것도 안 적는다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    expect(await ActiveCoachingPromise.keep(taskId: 'gone', at: at), isFalse);
    expect(ActiveCoachingStore.readDay(prefs, at).tasks, isEmpty);
  });

  test('말 건 횟수를 센다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.noteNudged(taskId: 'a', at: at);
    await ActiveCoachingPromise.noteNudged(taskId: 'a', at: at);

    expect(ActiveCoachingStore.readDay(prefs, at).of('a').nudges, 2);
  });

  test('결정이 나면 그날은 더 안 건드린다', () async {
    seed([
      {'id': 'a', 'text': '분기 리포트'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.keep(taskId: 'a', at: at);
    await ActiveCoachingPromise.decide(
      taskId: 'a',
      decision: ActiveCoachingDecision.notToday,
      at: at,
    );

    final day = ActiveCoachingStore.readDay(prefs, at);
    expect(day.settled, {'a'});
    // 결정이 난 일은 약속 시각에도 다시 부르지 않는다.
    expect(day.promises, isEmpty);
  });

  test('사용자가 직접 고른 일은 표시가 남는다', () async {
    seed([
      {'id': 'a', 'text': '방 정리'},
    ]);
    final prefs = await SharedPreferences.getInstance();

    await ActiveCoachingPromise.notePickedByUser(taskId: 'a', at: at);

    expect(ActiveCoachingStore.readDay(prefs, at).of('a').pickedByUser, isTrue);
  });
}
