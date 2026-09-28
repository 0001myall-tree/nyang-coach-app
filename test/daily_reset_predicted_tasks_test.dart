import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 아이폰이 전날 밤에 다음 날 오전 적극 코칭을 걸 때 쓰는 목록 짐작.
///
/// 재료는 자정 정리와 같다. 그날 요일의 루틴, 그날 캘린더 일정, 그날로
/// 미리 옮겨둔 할 일. 짐작만 하고 아무것도 저장하지 않는다.
void main() {
  // 2026-09-29는 화요일이다.
  const tomorrow = '2026-09-29';

  test('그날 루틴·일정·옮겨둔 일을 모은다', () async {
    SharedPreferences.setMockInitialValues({
      'nyang_habits': jsonEncode([
        {'id': 'h1', 'name': '영양제', 'freq': 'daily'},
        // 월요일만. 화요일엔 안 뜬다.
        {
          'id': 'h2',
          'name': '분리수거',
          'freq': 'weekly',
          'days': [0],
        },
      ]),
      'nyang_schedules': jsonEncode({
        tomorrow: [
          {'id': 's1', 'text': '치과', 'timeStart': '10:00'},
        ],
      }),
      'nyang_today_tasks_by_date': jsonEncode({
        tomorrow: [
          {'id': 't1', 'text': '방정리', 'category': 'today'},
        ],
        '2026-09-30': [
          {'id': 't2', 'text': '모레 일', 'category': 'today'},
        ],
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('nyang_today_tasks_by_date');

    final tasks = DailyResetService.predictedTasksFor(prefs, tomorrow);

    expect(tasks.map((t) => t['text']), ['영양제', '치과', '방정리']);
    expect(tasks[1]['id'], 'schedule_s1');
    // 짐작만 한다. 옮겨둔 일을 꺼내 가지 않는다.
    expect(prefs.getString('nyang_today_tasks_by_date'), before);
  });

  test('재료가 없으면 빈 목록', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    expect(DailyResetService.predictedTasksFor(prefs, tomorrow), isEmpty);
  });
}
