import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 자정 정리가 어제 목록을 하루만 남기는지 확인한다.
/// '오늘' 탭에서 어제를 열어 완료 표시를 채우려면 이 보관이 전제다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<Map<String, dynamic>> archived(SharedPreferences prefs) async {
    final raw = prefs.getString(DailyResetService.plannedTasksByDateKey) ?? '{}';
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  test('어제 목록은 보관함에 남는다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-18',
      today: '2026-08-19',
      tasksJson: [
        {'id': 1, 'text': '집필', 'done': false},
      ],
    );

    final map = await archived(prefs);
    expect(map.keys, contains('2026-08-18'));
    expect((map['2026-08-18'] as List).length, 1);
  });

  test('이틀 전 계획은 같이 지운다', () async {
    SharedPreferences.setMockInitialValues({
      DailyResetService.plannedTasksByDateKey: jsonEncode({
        '2026-08-17': [
          {'id': 9, 'text': '옛날 일'},
        ],
      }),
    });
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-18',
      today: '2026-08-19',
      tasksJson: [
        {'id': 1, 'text': '집필'},
      ],
    );

    final map = await archived(prefs);
    expect(map.keys, isNot(contains('2026-08-17')));
    expect(map.keys, contains('2026-08-18'));
  });

  test('미래 계획은 건드리지 않는다', () async {
    SharedPreferences.setMockInitialValues({
      DailyResetService.plannedTasksByDateKey: jsonEncode({
        '2026-08-25': [
          {'id': 7, 'text': '다음주 계획'},
        ],
      }),
    });
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-18',
      today: '2026-08-19',
      tasksJson: const [],
    );

    final map = await archived(prefs);
    expect(map.keys, contains('2026-08-25'));
  });

  test('며칠 만에 앱을 열면 남길 어제가 없다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-15',
      today: '2026-08-19',
      tasksJson: [
        {'id': 3, 'text': '나흘 전 일'},
      ],
    );

    final map = await archived(prefs);
    expect(map, isEmpty);
  });
}
