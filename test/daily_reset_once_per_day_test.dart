import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/task_completion_service.dart';

/// 자정 정리가 하루에 한 번만 돌게 하는 장치.
///
/// 정리를 돌릴지는 원래 'nyang_last_date' 하나로 정했는데, 그 값은 클라우드로
/// 오가서 오래된 값이 도착하면 되돌아간다. 그러면 이미 끝낸 정리가 낮에 다시
/// 돌았고, 그 순간 오늘 적어둔 것이 어제 칸으로 넘어가 사라졌다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('오늘 정리를 이미 끝냈으면', () {
    test('다시 돌지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        DailyResetService.resetDoneDateKey: '2026-09-05',
        DailyResetService.lastDateKey: '2026-09-05',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        await DailyResetService.alreadyResetToday(prefs, '2026-09-05'),
        isTrue,
      );
    });

    test('클라우드가 되돌린 날짜를 바로잡는다', () async {
      SharedPreferences.setMockInitialValues({
        DailyResetService.resetDoneDateKey: '2026-09-05',
        // 다른 기기에서 온 옛 값이 로컬을 덮은 상태.
        DailyResetService.lastDateKey: '2026-09-04',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        await DailyResetService.alreadyResetToday(prefs, '2026-09-05'),
        isTrue,
      );
      expect(prefs.getString(DailyResetService.lastDateKey), '2026-09-05');
    });
  });

  test('날이 바뀌면 다시 돈다', () async {
    SharedPreferences.setMockInitialValues({
      DailyResetService.resetDoneDateKey: '2026-09-05',
      DailyResetService.lastDateKey: '2026-09-05',
    });
    final prefs = await SharedPreferences.getInstance();

    expect(
      await DailyResetService.alreadyResetToday(prefs, '2026-09-06'),
      isFalse,
    );
  });

  test('한 번도 정리한 적 없으면 돈다', () async {
    SharedPreferences.setMockInitialValues({
      DailyResetService.lastDateKey: '2026-09-04',
    });
    final prefs = await SharedPreferences.getInstance();

    expect(
      await DailyResetService.alreadyResetToday(prefs, '2026-09-05'),
      isFalse,
    );
  });

  group('목록을 다시 만들 때 들고 가는 것', () {
    const today = '2026-09-05';

    test('오늘 손으로 적은 할 일은 들고 간다', () {
      expect(
        DailyResetService.shouldCarryOverTask({
          'id': 1,
          'text': '병원 예약 전화',
          'category': 'today',
          'createdAt': '2026-09-05T09:12:00.000',
        }, today),
        isTrue,
      );
    });

    test('어제 적은 것은 두고 간다', () {
      expect(
        DailyResetService.shouldCarryOverTask({
          'id': 2,
          'text': '어제 일',
          'category': 'today',
          'createdAt': '2026-09-04T21:00:00.000',
        }, today),
        isFalse,
      );
    });

    test('루틴은 루틴 목록에서 다시 만들어지므로 두고 간다', () {
      expect(
        DailyResetService.shouldCarryOverTask({
          'id': 'habit_17_2026-09-05',
          'habitId': '17',
          'text': '영양제 챙겨먹기',
          'category': 'habit',
          'createdAt': '2026-09-05T00:01:00.000',
        }, today),
        isFalse,
      );
    });

    test('캘린더 일정도 두고 간다', () {
      expect(
        DailyResetService.shouldCarryOverTask({
          'id': 'schedule_991',
          'text': '치과',
          'category': 'schedule',
          'createdAt': '2026-09-05T08:00:00.000',
        }, today),
        isFalse,
      );
    });

    test('적은 시각을 모르면 두고 간다', () {
      expect(
        DailyResetService.shouldCarryOverTask({
          'id': 3,
          'text': '언제 적었는지 모를 일',
          'category': 'today',
        }, today),
        isFalse,
      );
    });
  });

  group('방금 보관한 어제 칸은', () {
    test('화면이 빈손이면 저장소 쪽이 남는다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-09-04': [
            {'id': 1, 'text': '어제 목록'},
          ],
        },
        // 화면은 어제 칸을 비어 있는 걸로 알고 있다.
        encoded: const {},
        knownKeys: {'2026-09-04'},
        justArchivedKey: '2026-09-04',
      );

      expect(merged.keys, contains('2026-09-04'));
      expect((merged['2026-09-04'] as List).length, 1);
    });

    test('화면이 고쳤으면 화면 쪽이 남는다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-09-04': [
            {'id': 1, 'text': '옛 목록'},
          ],
        },
        encoded: {
          '2026-09-04': [
            {'id': 2, 'text': '방금 고친 목록'},
          ],
        },
        knownKeys: {'2026-09-04'},
        justArchivedKey: '2026-09-04',
      );

      expect((merged['2026-09-04'] as List).first['text'], '방금 고친 목록');
    });

    test('보관한 날짜가 아니면 화면이 비운 대로 둔다', () {
      final merged = DailyResetService.mergePlannedTasksForSave(
        stored: {
          '2026-09-03': [
            {'id': 1, 'text': '사용자가 지운 목록'},
          ],
        },
        encoded: const {},
        knownKeys: {'2026-09-03'},
        justArchivedKey: '2026-09-04',
      );

      expect(merged.containsKey('2026-09-03'), isFalse);
    });
  });

  group('완료를 어느 날 칸에 찍는지', () {
    test('이 기기가 오늘 정리를 끝냈으면 오늘 칸이다', () async {
      SharedPreferences.setMockInitialValues({
        DailyResetService.resetDoneDateKey: '2026-09-05',
        // 클라우드에서 옛 값이 와서 되돌려진 상태.
        DailyResetService.lastDateKey: '2026-09-04',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        TaskCompletionService.dateKeyForCompletion(
          prefs,
          DateTime(2026, 9, 5, 14),
        ),
        '2026-09-05',
      );
    });

    test('아직 정리 전이면 목록이 든 날, 곧 어제 칸이다', () async {
      SharedPreferences.setMockInitialValues({
        DailyResetService.lastDateKey: '2026-09-04',
      });
      final prefs = await SharedPreferences.getInstance();

      // 자정을 넘겼지만 앱이 아직 정리를 안 돌린 상태. 화면의 목록은 어제 것이다.
      expect(
        TaskCompletionService.dateKeyForCompletion(
          prefs,
          DateTime(2026, 9, 5, 0, 20),
        ),
        '2026-09-04',
      );
    });

    test('적어둔 날짜가 없으면 오늘이다', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(
        TaskCompletionService.dateKeyForCompletion(
          prefs,
          DateTime(2026, 9, 5, 9),
        ),
        '2026-09-05',
      );
    });
  });
}
