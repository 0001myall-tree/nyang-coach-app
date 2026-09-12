import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/recent_pace_brief.dart';

/// 최근 며칠을 어떻게 지냈는지 세어 코치에게 넘기는 자리.
///
/// 여기서 정하지 않는 것이 많다 — 무엇을 올릴지, 얼마나, 올릴지 유지할지는
/// 전부 코치가 정한다. 앱이 규칙을 박으면 그 규칙이 틀리는 사람이 반드시
/// 나오는데 틀린 줄도 모른다. 그래서 이 테스트는 **세는 것만** 지킨다.
void main() {
  final now = DateTime(2026, 9, 16, 10, 30); // 수요일 오전

  Map<String, dynamic> task(
    String text, {
    bool done = false,
    String? startedAt,
    String? completedAt,
    int elapsedSeconds = 0,
  }) => {
    'text': text,
    'done': done,
    if (startedAt != null) 'startedAt': startedAt,
    if (completedAt != null) 'completedAt': completedAt,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
  };

  Map<String, dynamic> day(String date, List<Map<String, dynamic>> tasks) => {
    'date': date,
    'tasks': tasks,
  };

  String history(List<Map<String, dynamic>> days) => jsonEncode(days);

  group('최근 며칠 고르기', () {
    test('오늘은 세지 않는다', () {
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-16', [task('오늘 것')]),
          day('2026-09-15', [task('어제 것')]),
        ]),
        now: now,
      );

      expect(days.length, 1);
      expect(days.first.date, '2026-09-15');
    });

    test('기록이 없는 날은 건너뛰고 있는 날 중 최근 둘을 고른다', () {
      // 주말을 건너뛴 사람에게 "이틀 전"을 따지면 빈손으로 돌아온다. 그 사람에게도
      // 최근에 지낸 이틀은 있다.
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-11', [task('목요일')]),
          day('2026-09-15', [task('화요일')]),
        ]),
        now: now,
      );

      expect(days.map((d) => d.date), ['2026-09-15', '2026-09-11']);
    });

    test('기록이 없으면 빈 목록', () {
      expect(RecentPaceBrief.recent(null, now: now), isEmpty);
      expect(RecentPaceBrief.recent('[]', now: now), isEmpty);
    });
  });

  group('하루치 셈', () {
    test('끝낸 것도 손댄 것에 든다', () {
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [
            task('끝냄', done: true),
            task('손만 댐', elapsedSeconds: 300),
            task('안 건드림'),
          ]),
        ]),
        now: now,
      );

      final d = days.single;
      expect(d.planned, 3);
      expect(d.touched, 2);
      expect(d.done, 1);
    });

    test('이름이 빈 항목도 셈에는 들어간다', () {
      // 셈이 이름 고르는 안쪽에 있던 동안에는, 이름이 빈 항목은 끝냈어도
      // 완료로 세지지 않았다.
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [
            {'text': '  ', 'done': true},
            task('이름 있는 것', done: true),
          ]),
        ]),
        now: now,
      );

      expect(days.single.done, 2);
      expect(days.single.tasks.map((t) => t.name), ['이름 있는 것']);
    });

    test('일정마다 끝낸 시각을 그 줄에 달아둔다', () {
      // 시각만 따로 모으면 그게 무엇의 시각인지가 지워진다.
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [
            task('늦게', done: true, completedAt: '2026-09-15T20:00:00'),
            task('일찍', done: true, completedAt: '2026-09-15T11:00:00'),
          ]),
        ]),
        now: now,
      );

      final tasks = days.single.tasks;
      expect(tasks.map((t) => t.name), ['늦게', '일찍']);
      expect(tasks.map((t) => t.doneHour), [20, 11]);
    });

    test('자정을 넘겨 찍힌 완료는 그날 시각으로 쓰지 않는다', () {
      // 그대로 쓰면 그날이 새벽에 끝난 것처럼 읽힌다.
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [
            task('새벽에', done: true, completedAt: '2026-09-16T01:00:00'),
          ]),
        ]),
        now: now,
      );

      expect(days.single.done, 1);
      expect(days.single.tasks.single.doneHour, isNull);
    });

    test('첫 시작 시각은 그날 가장 이른 것', () {
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [
            task('늦게', startedAt: '2026-09-15T21:00:00'),
            task('이르게', startedAt: '2026-09-15T09:00:00'),
          ]),
        ]),
        now: now,
      );

      expect(days.single.firstStartHour, 9);
    });

    test('시작 표시가 없으면 시각은 비운다', () {
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [task('체크만', done: true)]),
        ]),
        now: now,
      );

      expect(days.single.firstStartHour, isNull);
    });

    test('줄은 몇 개까지만 적고 총량은 그대로 센다', () {
      final days = RecentPaceBrief.recent(
        history([
          day('2026-09-15', [for (var i = 0; i < 20; i++) task('남은 일 $i')]),
        ]),
        now: now,
      );

      expect(days.single.planned, 20);
      expect(days.single.tasks.length, RecentPaceBrief.maxTasksPerDay);
    });
  });

  group('넘기는 블록', () {
    test('셀 것이 없으면 빈 문자열', () {
      expect(
        RecentPaceBrief.block(historyRaw: null, todayTasks: const [], now: now),
        isEmpty,
      );
    });

    test('지금 시각과 오늘 진행을 함께 적는다', () {
      // 오후에 열었는데 오늘 이미 해둔 것을 모르면, 코치가 오늘을 백지로 놓고
      // 말하게 된다.
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [task('어제 것', done: true)]),
        ]),
        todayTasks: [task('오늘 끝냄', done: true), task('오늘 남음')],
        now: now,
      );

      expect(block, contains('오전 10시'));
      expect(block, contains('적은 것 2개'));
      expect(block, contains('끝낸 것 1개'));
    });

    test('시각을 두고 하지 말라는 줄은 넣지 않는다', () {
      // 없는 숫자로는 말할 수도 없다. 금지 줄을 얹으면 자리만 차지한다.
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [task('체크만', done: true)]),
        ]),
        todayTasks: const [],
        now: now,
      );

      expect(block, isNot(contains('*')));
    });

    test('일정마다 어떻게 됐는지 한 줄씩 적는다', () {
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [
            task('운동', done: true, completedAt: '2026-09-15T22:30:00'),
            task('보고서', startedAt: '2026-09-15T14:00:00'),
            task('장보기'),
          ]),
        ]),
        todayTasks: const [],
        now: now,
      );

      expect(block, contains('운동 — 끝냄(오후 10시)'));
      expect(block, contains('보고서 — 손만 댐(오후 2시 시작)'));
      expect(block, contains('장보기 — 그대로'));
    });

    test('줄이 잘린 날은 몇 개가 빠졌는지 적는다', () {
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [for (var i = 0; i < 12; i++) task('일 $i')]),
        ]),
        todayTasks: const [],
        now: now,
      );

      expect(block, contains('…외 4개'));
    });

    test('시작 표시가 있으면 그 문구는 넣지 않는다', () {
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [task('눌렀음', startedAt: '2026-09-15T09:00:00')]),
        ]),
        todayTasks: const [],
        now: now,
      );

      expect(block, isNot(contains('하지 마세요')));
      expect(block, contains('첫 시작 오전 9시'));
    });

    test('못 쓰는 시간대는 알려준 대로 적는다', () {
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [task('어제 것')]),
        ]),
        todayTasks: const [],
        now: now,
        busyNow: '근무',
      );

      expect(block, contains('근무'));
    });

    test('남은 시간을 적는다', () {
      final block = RecentPaceBrief.block(
        historyRaw: history([
          day('2026-09-15', [task('어제 것')]),
        ]),
        todayTasks: const [],
        now: now,
        minutesLeft: 750,
      );

      expect(block, contains('12시간 30분'));
    });
  });
}
