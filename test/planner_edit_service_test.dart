import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/planner_action.dart';
import 'package:nyang_coach/services/planner_edit_service.dart';

String _key(DateTime d) => PlannerEditService.dateKey(d);

Map<String, dynamic> _task(
  String id,
  String text, {
  String? timeStart,
  bool done = false,
  bool reminder = false,
}) => {
  'id': id,
  'text': text,
  'category': 'today',
  'done': done,
  'isReminderEnabled': reminder,
  if (timeStart != null) 'timeStart': timeStart,
  'createdAt': DateTime.now().toIso8601String(),
};

Future<SharedPreferences> _prefsWith({
  List<Map<String, dynamic>>? today,
  Map<String, dynamic>? schedules,
  Map<String, dynamic>? planned,
}) async {
  SharedPreferences.setMockInitialValues({
    if (today != null) 'nyang_tasks': jsonEncode(today),
    if (schedules != null) 'nyang_schedules': jsonEncode(schedules),
    if (planned != null)
      DailyResetService.plannedTasksByDateKey: jsonEncode(planned),
  });
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('찾기', () {
    test('그런 이름이 없다', () async {
      await _prefsWith(today: [_task('1', '집필')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(
          kind: PlannerActionKind.done,
          target: '뜨개질',
        ),
      );
      expect(r.status, PlannerActionStatus.notFound);
    });

    test('같은 이름이 둘이면 고르지 않는다', () async {
      await _prefsWith(today: [_task('1', '운동'), _task('2', '운동')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '운동'),
      );
      expect(r.status, PlannerActionStatus.multiple);
    });

    test('찾은 이름을 그대로 돌려준다', () async {
      await _prefsWith(today: [_task('1', '아침 운동')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '운동'),
      );
      expect(r.isOk, isTrue);
      expect(r.label, '아침 운동');
    });
  });

  group('시각 옮기기', () {
    test('미리보기는 아무것도 바꾸지 않는다', () async {
      final prefs = await _prefsWith(today: [_task('1', '집필', timeStart: '19:00')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(
          kind: PlannerActionKind.move,
          target: '집필',
          time: (hour: 20, minute: 0),
        ),
      );
      expect(r.isOk, isTrue);
      expect(r.detail, '오후 8시');
      await prefs.reload();
      final stored = jsonDecode(prefs.getString('nyang_tasks')!) as List;
      expect(stored.first['timeStart'], '19:00');
    });

    test('실행하면 시각이 바뀐다', () async {
      final prefs = await _prefsWith(today: [_task('1', '집필', timeStart: '19:00')]);
      final r = await PlannerEditService.apply(
        const PlannerAction(
          kind: PlannerActionKind.move,
          target: '집필',
          time: (hour: 20, minute: 30),
        ),
      );
      expect(r.isOk, isTrue);
      await prefs.reload();
      final stored = jsonDecode(prefs.getString('nyang_tasks')!) as List;
      expect(stored.first['timeStart'], '20:30');
      expect(stored.first['time'], '오후 8:30');
    });

    test('끝 시각이 시작보다 앞서면 비운다', () async {
      final prefs = await _prefsWith(
        today: [
          {..._task('1', '회의', timeStart: '09:00'), 'timeEnd': '10:00'},
        ],
      );
      await PlannerEditService.apply(
        const PlannerAction(
          kind: PlannerActionKind.move,
          target: '회의',
          time: (hour: 14, minute: 0),
        ),
      );
      await prefs.reload();
      final stored = jsonDecode(prefs.getString('nyang_tasks')!) as List;
      expect(stored.first.containsKey('timeEnd'), isFalse);
    });
  });

  group('날짜 옮기기', () {
    test('오늘 할 일이 내일 계획으로 간다', () async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final prefs = await _prefsWith(today: [_task('1', '집필')]);
      final r = await PlannerEditService.apply(
        PlannerAction(
          kind: PlannerActionKind.move,
          target: '집필',
          date: tomorrow,
        ),
      );
      expect(r.isOk, isTrue);
      await prefs.reload();
      expect(jsonDecode(prefs.getString('nyang_tasks')!), isEmpty);
      final planned = jsonDecode(
        prefs.getString(DailyResetService.plannedTasksByDateKey)!,
      ) as Map;
      final moved = (planned[_key(tomorrow)] as List).first;
      expect(moved['text'], '집필');
      expect(moved['deferredCount'], 1);
    });

    test('옮긴 일은 다시 안 한 것이 된다', () async {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final prefs = await _prefsWith(
        today: [
          {
            ..._task('1', '집필'),
            'inProgress': true,
            'runStartedAt': DateTime.now().toIso8601String(),
          },
        ],
      );
      await PlannerEditService.apply(
        PlannerAction(
          kind: PlannerActionKind.move,
          target: '집필',
          date: tomorrow,
        ),
      );
      await prefs.reload();
      final planned = jsonDecode(
        prefs.getString(DailyResetService.plannedTasksByDateKey)!,
      ) as Map;
      final moved = (planned[_key(tomorrow)] as List).first;
      expect(moved['inProgress'], isFalse);
      expect(moved.containsKey('runStartedAt'), isFalse);
    });

    test('일정은 일정끼리 날짜를 옮긴다', () async {
      final today = DateTime.now();
      final tomorrow = today.add(const Duration(days: 1));
      final prefs = await _prefsWith(
        schedules: {
          _key(today): [
            {
              'id': 's1',
              'text': '병원',
              'timeStart': '10:00',
              'isRecurring': true,
              'recurrenceGroupId': 'g1',
            },
          ],
        },
      );
      await PlannerEditService.apply(
        PlannerAction(
          kind: PlannerActionKind.move,
          target: '병원',
          date: tomorrow,
        ),
      );
      await prefs.reload();
      final all = jsonDecode(prefs.getString('nyang_schedules')!) as Map;
      expect(all.containsKey(_key(today)), isFalse);
      final moved = (all[_key(tomorrow)] as List).first;
      expect(moved['text'], '병원');
      // 반복에서 떼어낸다. 안 그러면 다음 계산에서 원래 날로 돌아온다.
      expect(moved['isRecurring'], isFalse);
      expect(moved.containsKey('recurrenceGroupId'), isFalse);
    });
  });

  group('알람', () {
    test('시각이 없으면 켤 수 없다', () async {
      await _prefsWith(today: [_task('1', '집필')]);
      final r = await PlannerEditService.apply(
        const PlannerAction(
          kind: PlannerActionKind.remind,
          target: '집필',
          enabled: true,
        ),
      );
      expect(r.status, PlannerActionStatus.failed);
    });

    test('이미 켜져 있으면 바꿀 것이 없다', () async {
      await _prefsWith(
        today: [_task('1', '집필', timeStart: '19:00', reminder: true)],
      );
      final r = await PlannerEditService.apply(
        const PlannerAction(
          kind: PlannerActionKind.remind,
          target: '집필',
          enabled: true,
        ),
      );
      expect(r.status, PlannerActionStatus.noChange);
    });

    test('켜진다', () async {
      final prefs = await _prefsWith(
        today: [_task('1', '집필', timeStart: '19:00')],
      );
      await PlannerEditService.apply(
        const PlannerAction(
          kind: PlannerActionKind.remind,
          target: '집필',
          enabled: true,
        ),
      );
      await prefs.reload();
      final stored = jsonDecode(prefs.getString('nyang_tasks')!) as List;
      expect(stored.first['isReminderEnabled'], isTrue);
    });
  });

  group('완료', () {
    test('이미 완료면 바꿀 것이 없다', () async {
      await _prefsWith(today: [_task('1', '운동', done: true)]);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '운동'),
      );
      expect(r.status, PlannerActionStatus.noChange);
    });

    test('지난 날의 계획도 완료로 적는다', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final prefs = await _prefsWith(
        today: [],
        planned: {
          _key(yesterday): [_task('9', '청소')],
        },
      );
      final r = await PlannerEditService.apply(
        PlannerAction(
          kind: PlannerActionKind.done,
          target: '청소',
          date: yesterday,
        ),
      );
      expect(r.isOk, isTrue);
      await prefs.reload();
      final planned = jsonDecode(
        prefs.getString(DailyResetService.plannedTasksByDateKey)!,
      ) as Map;
      expect((planned[_key(yesterday)] as List).first['done'], isTrue);
    });
  });
}
