import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 오늘 목록에 오늘 루틴이 빠져 있으면 채워 넣는 자리.
///
/// 루틴을 채우는 길은 두 개뿐이었다 - 날짜가 실제로 넘어갈 때 한 번, 그리고
/// 오늘 탭이 열릴 때. 앱이 알림이나 자동 발화로 잠깐 깨어나기만 하고 사용자가
/// 채팅만 한 날에는 둘 다 안 걸려서, 루틴 여덟 개를 등록해둔 사람이 하루 종일
/// 빈 목록을 봤다. 코치도 그 빈 목록을 보고 "오늘은 계획이 없구나"로 말했다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String today() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}'
        '-${now.day.toString().padLeft(2, '0')}';
  }

  Map<String, Object> baseValues({
    required List<Map<String, dynamic>> habits,
    List<Map<String, dynamic>> tasks = const [],
    Map<String, dynamic> logs = const {},
  }) => {
    'nyang_habits': jsonEncode(habits),
    'nyang_tasks': jsonEncode(tasks),
    'nyang_habit_logs': jsonEncode(logs),
    // 복원 대기 중이면 맞추지 않고 지나간다. 그 길로 새지 않게 해둔다.
    'nyang_has_synced_from_cloud': true,
  };

  Map<String, dynamic> dailyHabit(int id, String name) => {
    'id': id,
    'name': name,
    'freq': 'daily',
    'days': <int>[],
    'checkType': 'check',
    'timeType': 'none',
    'tracking': true,
    'createdAt': '2026-09-01T10:00:00.000000',
    'isReminderEnabled': false,
  };

  Future<List<dynamic>> storedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    return jsonDecode(prefs.getString('nyang_tasks') ?? '[]') as List;
  }

  test('빈 목록에 오늘 루틴을 채운다', () async {
    SharedPreferences.setMockInitialValues(
      baseValues(habits: [dailyHabit(1, '영어 회화 공부'), dailyHabit(2, '필사 1단락')]),
    );

    expect(await DailyResetService.ensureTodayHabitTasks(), 2);
    expect((await storedTasks()).length, 2);
  });

  test('이미 있는 루틴은 다시 넣지 않는다', () async {
    final habit = dailyHabit(1, '영어 회화 공부');
    SharedPreferences.setMockInitialValues(
      baseValues(
        habits: [habit],
        tasks: DailyResetService.todayHabitTasks(
          await SharedPreferences.getInstance(),
          today(),
        ),
      ),
    );
    // 위 호출은 빈 저장소를 읽었으므로 직접 만들어 넣는다.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_habits', jsonEncode([habit]));
    await prefs.setString(
      'nyang_tasks',
      jsonEncode(DailyResetService.todayHabitTasks(prefs, today())),
    );

    expect(await DailyResetService.ensureTodayHabitTasks(), 0);
    expect((await storedTasks()).length, 1);
  });

  test('오늘 쉬기로 찍은 루틴은 되살리지 않는다', () async {
    SharedPreferences.setMockInitialValues(
      baseValues(
        habits: [dailyHabit(1, '저녁 식사 후 산책')],
        logs: {
          '1': {
            today(): {'done': false, 'status': 'skipped'},
          },
        },
      ),
    );

    expect(await DailyResetService.ensureTodayHabitTasks(), 0);
    expect(await storedTasks(), isEmpty);
  });

  test('손으로 적은 할 일은 그대로 두고 옆에 더한다', () async {
    SharedPreferences.setMockInitialValues(
      baseValues(
        habits: [dailyHabit(1, '영어 회화 공부')],
        tasks: [
          {
            'id': 'task_manual_1',
            'text': '머리 비우기 메모',
            'category': 'today',
            'done': false,
            'createdAt': DateTime.now().toIso8601String(),
          },
        ],
      ),
    );

    expect(await DailyResetService.ensureTodayHabitTasks(), 1);
    final tasks = await storedTasks();
    expect(tasks.length, 2);
    expect(
      tasks.any((t) => (t as Map)['text'] == '머리 비우기 메모'),
      isTrue,
      reason: '채우기는 더하기만 한다. 아무것도 지우지 않는다.',
    );
  });

  test('오늘 요일이 아닌 루틴은 넣지 않는다', () async {
    // 오늘이 아닌 요일 하나만 고른다.
    final otherDow = (DateTime.now().weekday - 1 + 1) % 7;
    SharedPreferences.setMockInitialValues(
      baseValues(
        habits: [
          {...dailyHabit(1, '출퇴근 책읽기'), 'freq': 'weekly', 'days': [otherDow]},
        ],
      ),
    );

    expect(await DailyResetService.ensureTodayHabitTasks(), 0);
  });
}
