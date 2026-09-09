import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/calendar_pullback_cleanup.dart';

/// 아이폰 캘린더를 되읽던 시절이 남긴 것을 치운다.
///
/// 그 길은 되읽은 시각이 내보낸 값과 조금이라도 다르면 "옮겼다"로 읽어, 그날을
/// 쉬기로 찍고 그 자리에 일회성 할 일을 하나 만들었다. 루틴은 90일치를 미리
/// 내보내므로 한 루틴이 계속 어긋나면 90일이 통째로 쉬는 날이 됐다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const today = '2026-09-09';
  final now = DateTime(2026, 9, 9, 15, 49);

  Future<SharedPreferences> seed(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues({
      // 복원이 끝난 상태여야 치운다.
      'nyang_has_synced_from_cloud': true,
      ...values,
    });
    return SharedPreferences.getInstance();
  }

  test('유령 할 일은 오늘 목록에서 치운다', () async {
    final prefs = await seed({
      'nyang_tasks': jsonEncode([
        {'id': 'habit_1_$today', 'text': 'sns 글쓰기'},
        {'id': 'habit_exception_2_$today', 'text': '영양제 챙겨먹기'},
      ]),
    });

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isTrue,
    );
    final kept = jsonDecode(prefs.getString('nyang_tasks')!) as List;
    expect(kept.map((t) => t['id']), ['habit_1_$today']);
  });

  test('날짜별 보관의 유령 할 일도, 그 날짜 칸까지 치운다', () async {
    final prefs = await seed({
      'nyang_today_tasks_by_date': jsonEncode({
        '2026-09-07': [
          {'id': 'task_9', 'text': '손으로 적은 것'},
        ],
        '2026-09-10': [
          {'id': 'habit_exception_2_2026-09-10', 'text': '영양제 챙겨먹기'},
        ],
        '2026-09-11': [
          {'id': 'habit_exception_2_2026-09-11', 'text': '영양제 챙겨먹기'},
        ],
      }),
    });

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isTrue,
    );
    final byDate =
        jsonDecode(prefs.getString('nyang_today_tasks_by_date')!) as Map;
    expect(byDate.keys, ['2026-09-07']);
  });

  test('아직 오지 않은 날의 쉬기는 치운다', () async {
    // 앱에는 미래를 미리 쉬는 날로 정하는 기능이 없다. 남아 있는 것은 전부
    // 되읽기가 적은 것이다.
    final prefs = await seed({
      'nyang_habit_logs': jsonEncode({
        '2': {
          '2026-09-10': {'done': false, 'status': 'skipped'},
          '2026-12-07': {'done': false, 'status': 'skipped'},
        },
      }),
    });

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isTrue,
    );
    final logs = jsonDecode(prefs.getString('nyang_habit_logs')!) as Map;
    expect((logs['2'] as Map), isEmpty);
  });

  test('오늘과 지난 날의 쉬기는 그대로 둔다', () async {
    // 사용자가 직접 누른 것일 수 있다.
    final prefs = await seed({
      'nyang_habit_logs': jsonEncode({
        '2': {
          '2026-09-08': {'done': false, 'status': 'skipped'},
          today: {'done': false, 'status': 'skipped'},
        },
      }),
    });

    await CalendarPullbackCleanup.runOnce(now: now, cloudRestorePending: false);
    final logs = jsonDecode(prefs.getString('nyang_habit_logs')!) as Map;
    expect((logs['2'] as Map).keys, containsAll(['2026-09-08', today]));
  });

  test('완료 기록은 미래 날짜라도 건드리지 않는다', () async {
    final prefs = await seed({
      'nyang_habit_logs': jsonEncode({
        '2': {
          '2026-09-10': {'done': true, 'status': 'done'},
        },
      }),
    });

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isFalse,
    );
    final logs = jsonDecode(prefs.getString('nyang_habit_logs')!) as Map;
    expect((logs['2'] as Map).keys, ['2026-09-10']);
  });

  test('한 번 돌면 다시 돌지 않는다', () async {
    final prefs = await seed({
      'nyang_tasks': jsonEncode([
        {'id': 'habit_exception_2_$today', 'text': '영양제 챙겨먹기'},
      ]),
    });

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isTrue,
    );
    expect(prefs.getBool(CalendarPullbackCleanup.doneKey), isTrue);
    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: false,
      ),
      isFalse,
    );
  });

  test('클라우드 복원 전에는 끝냈다고 적지 않는다', () async {
    // 여기서 끝냈다고 적으면, 잠시 뒤 도착하는 값은 영영 안 치워진다.
    SharedPreferences.setMockInitialValues({
      'nyang_has_synced_from_cloud': false,
      'nyang_tasks': jsonEncode([
        {'id': 'habit_exception_2_$today', 'text': '영양제 챙겨먹기'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();

    expect(
      await CalendarPullbackCleanup.runOnce(
        now: now,
        cloudRestorePending: true,
      ),
      isFalse,
    );
    expect(prefs.getBool(CalendarPullbackCleanup.doneKey), isNull);
  });
}
