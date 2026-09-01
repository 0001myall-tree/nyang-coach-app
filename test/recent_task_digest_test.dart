import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/recent_task_digest.dart';

/// 담당 영역이 있는 코치에게 주는 목록이다. 어느 것이 그 코치 영역인지는
/// 앱이 가르지 않고 코치가 고른다. 앱이 하는 일은 이름별로 세는 것까지다.
void main() {
  final now = DateTime(2026, 9, 1, 12);

  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> task(
    String name, {
    bool done = false,
    int? startedHour,
    int? completedHour,
    bool routine = false,
    bool deferred = false,
  }) => {
    'text': name,
    'done': done,
    'category': routine ? 'habit' : 'today',
    if (routine) 'habitId': 'h1',
    if (deferred) 'deferred': true,
    if (startedHour != null)
      'startedAt': DateTime(2026, 8, 30, startedHour).toIso8601String(),
    if (completedHour != null)
      'completedAt': DateTime(2026, 8, 30, completedHour).toIso8601String(),
  };

  /// [byBack]의 키는 "며칠 전"이다.
  String history(Map<int, List<Map<String, dynamic>>> byBack) {
    final records = <Map<String, dynamic>>[];
    for (final entry in byBack.entries) {
      final day = DateTime(now.year, now.month, now.day - entry.key);
      records.add({'date': key(day), 'tasks': entry.value});
    }
    return jsonEncode(records);
  }

  group('이름별로 센다', () {
    test('같은 이름은 묶어서 센다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('설거지', done: true)],
          2: [task('설거지', done: true)],
          3: [task('설거지')],
        }),
        now: now,
      );
      expect(tallies.single.name, '설거지');
      expect(tallies.single.planned, 3);
      expect(tallies.single.done, 2);
    });

    test('손은 댔는데 못 끝낸 것도 따로 센다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('빨래', startedHour: 14)],
          2: [task('빨래', done: true, startedHour: 14)],
        }),
        now: now,
      );
      expect(tallies.single.done, 1);
      expect(tallies.single.startedOnly, 1);
    });

    test('루틴에서 온 것은 표시한다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('스트레칭', routine: true, done: true)],
        }),
        now: now,
      );
      expect(tallies.single.isRoutine, isTrue);
    });

    test('이월된 항목은 세지 않는다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('청소'), task('청소', deferred: true)],
        }),
        now: now,
      );
      expect(tallies.single.planned, 1);
    });

    test('창 밖의 날은 세지 않는다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('청소')],
          40: [task('청소')],
        }),
        now: now,
      );
      expect(tallies.single.planned, 1);
    });

    test('잦은 것부터 나온다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('가끔'), task('자주')],
          2: [task('자주')],
          3: [task('자주')],
        }),
        now: now,
      );
      expect(tallies.first.name, '자주');
    });
  });

  group('주로 손댄 때', () {
    test('한 시간대에 몰려 있으면 짚는다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('설거지', done: true, startedHour: 20)],
          2: [task('설거지', done: true, startedHour: 21)],
        }),
        now: now,
      );
      expect(tallies.single.usualHour, 20);
    });

    test('한 번뿐이면 짚지 않는다', () {
      // 한 번 저녁에 했다고 저녁에 하는 사람이라고 하면 없는 패턴을 만든다.
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('설거지', done: true, startedHour: 20)],
        }),
        now: now,
      );
      expect(tallies.single.usualHour, isNull);
    });

    test('흩어져 있으면 짚지 않는다', () {
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('설거지', done: true, startedHour: 7)],
          2: [task('설거지', done: true, startedHour: 14)],
          3: [task('설거지', done: true, startedHour: 21)],
          4: [task('설거지', done: true, startedHour: 3)],
        }),
        now: now,
      );
      expect(tallies.single.usualHour, isNull);
    });

    test('시작 표시가 없으면 끝낸 시각으로 본다', () {
      // ▶를 안 누르고 체크만 하는 사람이 많다. 그러면 이 칸이 늘 비는데,
      // 자리를 잡아주려면 언제 하는지를 알아야 한다.
      final tallies = RecentTaskDigest.tally(
        history({
          1: [task('설거지', done: true, completedHour: 20)],
          2: [task('설거지', done: true, completedHour: 21)],
        }),
        now: now,
      );
      expect(tallies.single.usualHour, 20);
    });
  });

  group('코치에게 넘기는 묶음', () {
    test('기록이 없으면 아무것도 안 싣는다', () {
      expect(RecentTaskDigest.promptBlock(null, now: now), isEmpty);
    });

    test('자기 영역만 보라고 못박는다', () {
      final block = RecentTaskDigest.promptBlock(
        history({
          1: [task('설거지', done: true)],
        }),
        now: now,
      );
      expect(block, contains('맡는 영역의 것만'));
      expect(block, contains('아는 척하지 마세요'));
    });

    test('짧은 형식으로 적는다', () {
      final block = RecentTaskDigest.promptBlock(
        history({
          1: [task('설거지', routine: true, done: true, startedHour: 20)],
          2: [task('설거지', routine: true, done: true, startedHour: 20)],
        }),
        now: now,
      );
      expect(block, contains('설거지(루틴) 2/2 밤8시'));
    });

    test('손댄 때를 어떻게 읽을지 밝힌다', () {
      final block = RecentTaskDigest.promptBlock(
        history({
          1: [task('설거지', done: true)],
        }),
        now: now,
      );
      expect(block, contains('끝낸 시각으로 대신'));
    });
  });
}
