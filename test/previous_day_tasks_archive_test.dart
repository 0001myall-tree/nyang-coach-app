import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 자정 정리가 지난 목록을 며칠 남기는지 확인한다.
/// '오늘' 탭에서 어제를 열어 완료 표시를 채우고, 뒤늦게 도착한 냥냥이의 답을
/// 채워 넣으려면 이 보관이 전제다.
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

  test('사흘 안쪽은 남기고 그보다 오래된 것만 지운다', () async {
    SharedPreferences.setMockInitialValues({
      DailyResetService.plannedTasksByDateKey: jsonEncode({
        // 오늘이 8-19면 8-16까지가 보관 범위다.
        '2026-08-16': [
          {'id': 9, 'text': '사흘 전 일'},
        ],
        '2026-08-15': [
          {'id': 8, 'text': '나흘 전 일'},
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
    expect(map.keys, contains('2026-08-16'));
    expect(map.keys, contains('2026-08-18'));
    expect(map.keys, isNot(contains('2026-08-15')));
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

  test('보관 범위를 넘겨 오랜만에 열면 남길 것이 없다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-14',
      today: '2026-08-19',
      tasksJson: [
        {'id': 3, 'text': '닷새 전 일'},
      ],
    );

    final map = await archived(prefs);
    expect(map, isEmpty);
  });

  test('사흘 전에 쓰던 목록은 아직 받아준다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await DailyResetService.archivePreviousDayTasks(
      prefs: prefs,
      fromDate: '2026-08-16',
      today: '2026-08-19',
      tasksJson: [
        {'id': 4, 'text': '사흘 전 집필'},
      ],
    );

    final map = await archived(prefs);
    expect(map.keys, contains('2026-08-16'));
  });

  // 자정 정리는 두 곳에서 따로 돈다. 화면이 표를 읽어둔 사이에 저장소에만 어제가
  // 들어오면, 화면이 자기 표를 그대로 저장할 때 그 어제가 사라진다.
  group('저장할 때 저장소에 있던 날짜를 지우지 않는다', () {
    test('화면이 모르는 날짜는 남는다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-08-18': [
            {'id': 1, 'text': '어제 집필'},
          ],
          '2026-08-25': [
            {'id': 2, 'text': '다음주 계획'},
          ],
        },
        encoded: {
          '2026-08-25': [
            {'id': 2, 'text': '다음주 계획'},
          ],
        },
        knownKeys: {'2026-08-25'},
      );

      expect(merged.keys, contains('2026-08-18'));
      expect(merged.keys, contains('2026-08-25'));
    });

    // 지운 것이 되살아나면 안 된다. 화면이 아는 날짜는 비어 있어도 화면이 이긴다.
    test('화면이 비운 날짜는 되살아나지 않는다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-08-25': [
            {'id': 2, 'text': '지운 계획'},
          ],
        },
        encoded: const {},
        knownKeys: {'2026-08-25'},
      );

      expect(merged.keys, isEmpty);
    });

    test('화면이 고친 날짜는 화면 쪽이 남는다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-08-25': [
            {'id': 2, 'text': '옛 이름'},
          ],
        },
        encoded: {
          '2026-08-25': [
            {'id': 2, 'text': '새 이름'},
          ],
        },
        knownKeys: {'2026-08-25'},
      );

      expect((merged['2026-08-25'] as List).first['text'], '새 이름');
    });
  });
}
