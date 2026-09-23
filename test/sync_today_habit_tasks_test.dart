import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 오늘 목록의 루틴 줄을 루틴 목록에 맞춘다.
///
/// 이 일은 두 벌로 있었다. 화면은 메모리에 든 목록을 고치고, 서비스는 저장소를
/// 고쳤다. 같은 규칙을 두 군데 적어두면 한쪽만 고쳐지는 날이 오고, 실제로
/// 루틴이 하루 종일 안 뜨는 날이 그렇게 생겼다. 한 벌로 모은다.
///
/// 셋을 한다 - 빠진 것 더하기, 없어진 것 빼기, 바뀐 이름·시각 반영.
/// 그중 빼기가 위험하다. 루틴 목록을 못 읽은 순간에 돌면 멀쩡한 줄이 통째로
/// 사라진다. 그래서 못 읽었으면 아무것도 하지 않는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  String rowId(int habitId) => 'habit_${habitId}_${today()}';

  Map<String, dynamic> habit(
    int id,
    String name, {
    String freq = 'daily',
    List<int> days = const [],
    String? timeStart,
    String? duration = '30분',
  }) => {
    'id': id,
    'name': name,
    'freq': freq,
    'days': days,
    'checkType': 'check',
    'timeType': timeStart == null ? 'duration' : 'single',
    'tracking': true,
    if (timeStart != null) 'timeStart': timeStart,
    if (timeStart == null && duration != null) 'habitDuration': duration,
    'createdAt': '2026-09-01T10:00:00.000000',
    'isReminderEnabled': false,
  };

  /// 이미 목록에 들어가 있는 루틴 줄. 앱이 만드는 것과 같은 칸을 갖춘다.
  Map<String, dynamic> habitRow(
    int id,
    String name, {
    String? duration = '30분',
    String? timeStart,
  }) => {
    'id': rowId(id),
    'habitId': '$id',
    'text': name,
    'category': 'habit',
    'done': false,
    'isHabit': true,
    'time': null,
    'duration': duration,
    'timeStart': timeStart,
    'timeEnd': null,
    'createdAt': DateTime.now().toIso8601String(),
  };

  Map<String, dynamic> plainRow(String id, String text) => {
    'id': id,
    'text': text,
    'category': 'today',
    'done': false,
    'createdAt': DateTime.now().toIso8601String(),
  };

  void seed({
    Object? habits,
    List<Map<String, dynamic>> tasks = const [],
    Map<String, dynamic> logs = const {},
  }) {
    SharedPreferences.setMockInitialValues({
      if (habits != null)
        'nyang_habits': habits is String ? habits : jsonEncode(habits),
      'nyang_tasks': jsonEncode(tasks),
      'nyang_habit_logs': jsonEncode(logs),
      'nyang_has_synced_from_cloud': true,
    });
  }

  Future<List<Map<String, dynamic>>> storedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    return (jsonDecode(prefs.getString('nyang_tasks') ?? '[]') as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  group('더하기', () {
    test('빠진 루틴을 채운다', () async {
      seed(habits: [habit(1, '영어 회화 공부'), habit(2, '필사 1단락')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      expect((await storedTasks()).length, 2);
    });

    test('이미 있으면 더하지 않는다', () async {
      seed(habits: [habit(1, '영어 회화 공부')], tasks: [habitRow(1, '영어 회화 공부')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect((await storedTasks()).length, 1);
    });

    test('오늘 쉬기로 찍은 것은 되살리지 않는다', () async {
      seed(
        habits: [habit(1, '저녁 식사 후 산책')],
        logs: {
          '1': {
            today(): {'done': false, 'status': 'skipped'},
          },
        },
      );
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect(await storedTasks(), isEmpty);
    });

    test('오늘 요일이 아니면 더하지 않는다', () async {
      final otherDow = (DateTime.now().weekday - 1 + 1) % 7;
      seed(
        habits: [
          habit(1, '출퇴근 책읽기', freq: 'weekly', days: [otherDow]),
        ],
      );
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect(await storedTasks(), isEmpty);
    });
  });

  group('빼기', () {
    test('지워진 루틴의 줄을 뺀다', () async {
      seed(habits: [habit(1, '영어 회화 공부')], tasks: [habitRow(9, '없어진 루틴')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      final tasks = await storedTasks();
      expect(tasks.length, 1);
      expect(tasks.single['habitId'], '1');
    });

    test('오늘 요일이 아닌 줄을 뺀다', () async {
      final otherDow = (DateTime.now().weekday - 1 + 1) % 7;
      seed(
        habits: [
          habit(1, '출퇴근 책읽기', freq: 'weekly', days: [otherDow]),
        ],
        tasks: [habitRow(1, '출퇴근 책읽기')],
      );
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      expect(await storedTasks(), isEmpty);
    });

    test('손으로 적은 할 일은 건드리지 않는다', () async {
      seed(habits: [], tasks: [plainRow('manual_1', '머리 비우기 메모')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect((await storedTasks()).single['text'], '머리 비우기 메모');
    });

    test('루틴 목록을 못 읽으면 아무것도 지우지 않는다', () async {
      // 클라우드 복원 전이거나 값이 깨졌을 때. 여기서 빼기가 돌면 멀쩡한
      // 줄이 통째로 사라진다. 실제로 그렇게 하루가 비어버린 적이 있다.
      seed(habits: null, tasks: [habitRow(1, '영어 회화 공부')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect((await storedTasks()).length, 1);
    });

    test('루틴 목록이 깨져 있어도 아무것도 지우지 않는다', () async {
      seed(habits: '{망가진 값', tasks: [habitRow(1, '영어 회화 공부')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isFalse);
      expect((await storedTasks()).length, 1);
    });

    test('루틴을 전부 지운 사람의 줄은 뺀다', () async {
      // 빈 목록은 읽기에 성공한 것이다. 못 읽은 것과 다르다.
      seed(habits: [], tasks: [habitRow(1, '영어 회화 공부')]);
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      expect(await storedTasks(), isEmpty);
    });
  });

  group('고치기', () {
    test('바뀐 이름을 반영한다', () async {
      seed(
        habits: [habit(1, '영어 회화 공부 30분')],
        tasks: [habitRow(1, '영어 회화 공부')],
      );
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      expect((await storedTasks()).single['text'], '영어 회화 공부 30분');
    });

    test('붙은 시각을 반영한다', () async {
      seed(
        habits: [habit(1, '저녁 식사 후 산책', timeStart: '19:30')],
        tasks: [habitRow(1, '저녁 식사 후 산책')],
      );
      expect(await DailyResetService.syncTodayHabitTasks(), isTrue);
      expect((await storedTasks()).single['timeStart'], '19:30');
    });

    test('완료 표시는 그대로 둔다', () async {
      final done = {
        ...habitRow(1, '영어 회화 공부'),
        'done': true,
        'completedAt': '2026-09-17T08:00:00.000',
      };
      seed(habits: [habit(1, '영어 회화 공부 30분')], tasks: [done]);
      await DailyResetService.syncTodayHabitTasks();
      final row = (await storedTasks()).single;
      expect(row['done'], isTrue);
      expect(row['completedAt'], '2026-09-17T08:00:00.000');
      expect(row['text'], '영어 회화 공부 30분');
    });
  });
}
