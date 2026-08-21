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
}) => {
  'id': id,
  'text': text,
  'category': 'today',
  'done': done,
  if (timeStart != null) 'timeStart': timeStart,
  'createdAt': DateTime.now().toIso8601String(),
};

Map<String, dynamic> _habit(String id, String name) => {
  'id': id,
  'name': name,
  'freq': 'daily',
  'createdAt': DateTime.now().toIso8601String(),
};

Map<String, dynamic> _injected(String id, String name, String habitId) => {
  ..._task(id, name),
  'category': 'habit',
  'isHabit': true,
  'habitId': habitId,
};

Future<void> _prefsWith({
  List<Map<String, dynamic>>? today,
  Map<String, dynamic>? schedules,
  Map<String, dynamic>? planned,
  List<Map<String, dynamic>>? habits,
}) async {
  SharedPreferences.setMockInitialValues({
    if (today != null) 'nyang_tasks': jsonEncode(today),
    if (schedules != null) 'nyang_schedules': jsonEncode(schedules),
    if (habits != null) 'nyang_habits': jsonEncode(habits),
    if (planned != null)
      DailyResetService.plannedTasksByDateKey: jsonEncode(planned),
  });
  await SharedPreferences.getInstance();
}

const _move = PlannerAction(
  kind: PlannerActionKind.move,
  target: '운동',
  time: (hour: 20, minute: 0),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('무엇을 가리키는지 찾는다', () {
    test('그런 이름이 없다', () async {
      await _prefsWith(today: [_task('1', '집필')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '뜨개질'),
      );
      expect(r.status, PlannerActionStatus.notFound);
    });

    test('같은 이름이 둘이면 고르지 않는다', () async {
      await _prefsWith(today: [_task('1', '운동'), _task('2', '운동')]);
      final r = await PlannerEditService.preview(_move);
      expect(r.status, PlannerActionStatus.multiple);
    });

    test('찾은 이름을 목록에 적힌 그대로 돌려준다', () async {
      await _prefsWith(today: [_task('1', '아침 운동')]);
      final r = await PlannerEditService.preview(_move);
      expect(r.isOk, isTrue);
      expect(r.label, '아침 운동');
    });

    test('이름이 비어 있으면 찾지 않는다', () async {
      await _prefsWith(today: [_task('1', '운동')]);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.move, target: '  '),
      );
      expect(r.status, PlannerActionStatus.notFound);
    });
  });

  group('어느 저장소에 있든 찾는다', () {
    test('날짜별 일정', () async {
      final today = DateTime.now();
      await _prefsWith(
        schedules: {
          _key(today): [
            {'id': 's1', 'text': '병원', 'timeStart': '10:00'},
          ],
        },
      );
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.move, target: '병원'),
      );
      expect(r.isOk, isTrue);
      expect(r.label, '병원');
    });

    test('지난 날의 계획', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await _prefsWith(
        today: [],
        planned: {
          _key(yesterday): [_task('9', '청소')],
        },
      );
      final r = await PlannerEditService.preview(
        PlannerAction(
          kind: PlannerActionKind.done,
          target: '청소',
          date: yesterday,
        ),
      );
      expect(r.isOk, isTrue);
    });
  });

  group('루틴은 따로 알려준다', () {
    test('오늘 목록에 내려온 루틴', () async {
      await _prefsWith(
        habits: [_habit('h1', '운동')],
        today: [_injected('1', '운동', 'h1')],
      );
      final r = await PlannerEditService.preview(_move);
      expect(r.status, PlannerActionStatus.routine);
      expect(r.label, '운동');
    });

    test('끝냈다는 말은 루틴이라도 오늘치 체크다', () async {
      await _prefsWith(
        habits: [_habit('h1', '운동')],
        today: [_injected('1', '운동', 'h1')],
      );
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '운동'),
      );
      // 루틴 탭에는 오늘 체크할 자리가 없다.
      expect(r.isOk, isTrue);
      expect(r.status, isNot(PlannerActionStatus.routine));
    });

    test('오늘 안 하는 루틴', () async {
      await _prefsWith(habits: [_habit('h1', '스트레칭')], today: []);
      final r = await PlannerEditService.preview(
        const PlannerAction(kind: PlannerActionKind.done, target: '스트레칭'),
      );
      expect(r.status, PlannerActionStatus.routine);
    });

    test('루틴과 오늘치를 둘로 세지 않는다', () async {
      await _prefsWith(
        habits: [_habit('h1', '운동')],
        today: [_injected('1', '운동', 'h1')],
      );
      final r = await PlannerEditService.preview(_move);
      expect(r.status, isNot(PlannerActionStatus.multiple));
    });
  });

  group('아무것도 바꾸지 않는다', () {
    test('찾아도 저장소는 그대로다', () async {
      await _prefsWith(today: [_task('1', '운동', timeStart: '19:00')]);
      await PlannerEditService.preview(_move);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final stored = jsonDecode(prefs.getString('nyang_tasks')!) as List;
      expect(stored.first['timeStart'], '19:00');
      expect(stored.first['done'], isFalse);
    });
  });

  group('사람에게 보여줄 말', () {
    test('로 / 으로', () {
      expect(PlannerEditService.roJosa('오후 8시'), '로');
      expect(PlannerEditService.roJosa('오늘'), '로');
      expect(PlannerEditService.roJosa('내일(8월 22일)'), '로');
      expect(PlannerEditService.roJosa('오후 8시 30분'), '으로');
    });

    test('이 / 가', () {
      expect(PlannerEditService.iGaJosa('글쓰기'), '가');
      expect(PlannerEditService.iGaJosa('운동'), '이');
    });

    test('을 / 를', () {
      expect(PlannerEditService.eulReulJosa('글쓰기'), '를');
      expect(PlannerEditService.eulReulJosa('운동'), '을');
    });
  });
}
