import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/execution_funnel.dart';

/// 앞뒤가 정반대인 두 사람이 같은 칸에 들어가던 것을 가르는 층이다.
/// 그래서 여기 테스트는 대부분 "같은 완료율인데 다른 진단"의 짝이다.
void main() {
  final now = DateTime(2026, 9, 1); // 화요일

  String key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> task({
    bool done = false,
    bool started = false,
    String category = 'today',
    String? habitId,
    bool deferred = false,
  }) => {
    'text': '할 일',
    'done': done,
    'category': category,
    if (habitId != null) 'habitId': habitId,
    if (deferred) 'deferred': true,
    if (started) 'startedAt': DateTime(2026, 8, 30, 10).toIso8601String(),
  };

  /// 어제부터 거슬러 [days]일치. 하루에 [tasks]를 그대로 넣는다.
  String history(List<Map<String, dynamic>> tasks, {int days = 7}) {
    final records = <Map<String, dynamic>>[];
    for (var back = 1; back <= days; back++) {
      final day = DateTime(now.year, now.month, now.day - back);
      records.add({'date': key(day), 'tasks': tasks});
    }
    return jsonEncode(records);
  }

  /// 날마다 다른 목록을 넣는다. [byBack]의 키는 "며칠 전"이다.
  String historyByDay(Map<int, List<Map<String, dynamic>>> byBack) {
    final records = <Map<String, dynamic>>[];
    for (final entry in byBack.entries) {
      final day = DateTime(now.year, now.month, now.day - entry.key);
      records.add({'date': key(day), 'tasks': entry.value});
    }
    return jsonEncode(records);
  }

  group('셀 것이 모자랄 때', () {
    test('기록이 없으면 아무 말도 안 한다', () {
      final funnel = ExecutionFunnel.from(null, now: now);
      expect(funnel.hasEnough, isFalse);
      expect(funnel.promptBlock(), isEmpty);
    });

    test('이틀치로는 판정하지 않는다', () {
      final funnel = ExecutionFunnel.from(
        history([task()], days: 2),
        now: now,
      );
      expect(funnel.hasEnough, isFalse);
    });

    test('첫 기록 이전은 거른 날로 세지 않는다', () {
      // 사흘 전에 깔았으면 그 앞은 이 사람이 거른 날이 아니다.
      final funnel = ExecutionFunnel.from(
        history([task()], days: 3),
        now: now,
      );
      expect(funnel.evaluatedDays, 3);
      expect(funnel.planPass, 1.0);
    });
  });

  group('같은 완료율, 다른 진단', () {
    // 계획 대비 완료율은 둘 다 25% 언저리인데 해야 할 말이 정반대다.
    // 문턱으로 재던 때는 이 둘이 같은 칸에 들어갔다.
    test('손대면 끝내는 사람 — 새는 곳은 잡는 양', () {
      // 하루 4개 중 1개만 손대고, 손댄 것은 끝낸다. 손은 매일 댄다.
      final funnel = ExecutionFunnel.from(
        history([
          task(done: true, started: true),
          task(),
          task(),
          task(),
        ]),
        now: now,
      );
      expect(funnel.startPass, closeTo(0.25, 0.01));
      expect(funnel.finishPass, 1.0);
      expect(funnel.dayStartPass, 1.0);
      expect(funnel.leak, FunnelLeak.amount);
    });

    test('시작은 잘하는데 못 끝내는 사람 — 새는 곳은 끝까지 가는 것', () {
      // 하루 4개 중 3개에 손대고, 그중 하나만 끝낸다.
      final funnel = ExecutionFunnel.from(
        history([
          task(done: true, started: true),
          task(started: true),
          task(started: true),
          task(),
        ]),
        now: now,
      );
      expect(funnel.startPass, closeTo(0.75, 0.01));
      expect(funnel.finishPass, closeTo(0.33, 0.01));
      expect(funnel.leak, FunnelLeak.finishing);
    });
  });

  group('새는 곳 고르기', () {
    test('목록을 만드는 날이 드물면 거기가 먼저', () {
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: [task(done: true, started: true)],
          2: <Map<String, dynamic>>[],
          3: <Map<String, dynamic>>[],
          4: <Map<String, dynamic>>[],
          5: <Map<String, dynamic>>[],
          6: <Map<String, dynamic>>[],
          7: <Map<String, dynamic>>[],
        }),
        now: now,
      );
      expect(funnel.daysWithPlan, 1);
      expect(funnel.leak, FunnelLeak.planning);
    });

    test('적어두고 손을 안 대면 첫 발이 문제', () {
      // 손대는 날 자체가 드물다. 양이 아니라 시작이다.
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: [task(done: true, started: true), task()],
          2: [task(), task()],
          3: [task(), task()],
          4: [task(), task()],
          5: [task(), task()],
          6: [task(), task()],
          7: [task(), task()],
        }),
        now: now,
      );
      expect(funnel.dayStartPass, closeTo(0.14, 0.02));
      expect(funnel.leak, FunnelLeak.starting);
    });

    test('아무것도 손대지 않았으면 아직 시작 전', () {
      final funnel = ExecutionFunnel.from(history([task(), task()]), now: now);
      expect(funnel.leak, FunnelLeak.notStarted);
    });

    test('다 잘 지나가면 새는 곳이 없다', () {
      final funnel = ExecutionFunnel.from(
        history([task(done: true, started: true), task(done: true, started: true)]),
        now: now,
      );
      expect(funnel.leak, FunnelLeak.none);
    });
  });

  group('시작 표시가 없을 때', () {
    test('시작과 완료를 가르지 않는다', () {
      // ▶를 안 누르고 체크만 하는 사람. 손댄 것과 끝낸 것이 같아진다.
      final funnel = ExecutionFunnel.from(
        history([task(done: true), task(), task(), task()]),
        now: now,
      );
      expect(funnel.canSplitStartAndFinish, isFalse);
      // 완료 축이 100%로 나와도 그걸로 다른 축을 이기게 두지 않는다.
      expect(funnel.leak, isNot(FunnelLeak.finishing));
    });

    test('가를 수 없다는 것을 코치에게 알린다', () {
      final funnel = ExecutionFunnel.from(
        history([task(done: true), task(), task(), task()]),
        now: now,
      );
      expect(funnel.promptBlock(), contains('가를 수 없습니다'));
      expect(funnel.promptBlock(), contains('단정하지 마세요'));
    });
  });

  group('계획 축', () {
    test('루틴만 있어도 목록이 있던 날로 센다', () {
      final funnel = ExecutionFunnel.from(
        history([task(category: 'habit', habitId: 'h1', done: true, started: true)]),
        now: now,
      );
      expect(funnel.planPass, 1.0);
      // 다만 직접 적은 날은 따로 센다. 루틴만 걸어둔 사람과 매일 적는 사람은
      // 다른 사람이다.
      expect(funnel.daysDirectPlan, 0);
    });

    test('평균은 목록이 있던 날로만 나눈다', () {
      // 이레 중 이틀만, 그 이틀엔 다섯 개씩. 안 적은 날까지 나누면 1.4개가
      // 되어 "적게 잡는 사람"으로 읽힌다.
      final five = [for (var i = 0; i < 5; i++) task()];
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: five,
          2: five,
          3: <Map<String, dynamic>>[],
          4: <Map<String, dynamic>>[],
          5: <Map<String, dynamic>>[],
          6: <Map<String, dynamic>>[],
          7: <Map<String, dynamic>>[],
        }),
        now: now,
      );
      expect(funnel.planPerPlannedDay, 5.0);
      expect(funnel.maxPlanInDay, 5);
    });

    test('이월된 항목은 그날 세운 계획이 아니다', () {
      final funnel = ExecutionFunnel.from(
        history([task(done: true, started: true), task(deferred: true)]),
        now: now,
      );
      expect(funnel.planned, 7);
    });
  });

  group('곁들이는 정보', () {
    Map<String, dynamic> startedAt(int hour) => {
      'text': '할 일',
      'done': true,
      'category': 'today',
      'startedAt': DateTime(2026, 8, 30, hour).toIso8601String(),
    };

    test('주로 손대는 시간대를 짚는다', () {
      final funnel = ExecutionFunnel.from(
        history([startedAt(9), startedAt(9)]),
        now: now,
      );
      expect(funnel.busiestStartHour, 8);
      expect(funnel.promptBlock(), contains('오전 8시~오전 10시'));
    });

    test('골고루 퍼져 있으면 시간대라고 하지 않는다', () {
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: [startedAt(7), startedAt(13)],
          2: [startedAt(9), startedAt(15)],
          3: [startedAt(11), startedAt(19)],
          4: [startedAt(21), startedAt(17)],
        }),
        now: now,
      );
      expect(funnel.busiestStartHour, isNull);
    });

    test('표본이 모자라면 말하지 않는다', () {
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: [startedAt(9)],
          2: [startedAt(9)],
          3: [startedAt(9)],
        }),
        now: now,
      );
      expect(funnel.busiestStartHour, isNull);
    });

    test('밤에 몰아서 시작한 날을 센다', () {
      final funnel = ExecutionFunnel.from(
        history([startedAt(23), startedAt(23), startedAt(23)]),
        now: now,
      );
      expect(funnel.lateNightDays, 7);
      expect(funnel.promptBlock(), contains('막판에 몰림'));
    });

    test('하루만 몰렸으면 바쁜 날일 뿐이다', () {
      final funnel = ExecutionFunnel.from(
        historyByDay({
          1: [startedAt(23), startedAt(23), startedAt(23)],
          2: [startedAt(10)],
          3: [startedAt(10)],
          4: [startedAt(10)],
        }),
        now: now,
      );
      expect(funnel.lateNightDays, 1);
      expect(funnel.promptBlock(), isNot(contains('막판에 몰림')));
    });

    test('시간대는 새는 곳을 고르는 데 끼어들지 않는다', () {
      // 밤에 몰아 시작해도 세 단계가 잘 지나가면 새는 곳은 없다.
      final funnel = ExecutionFunnel.from(
        history([startedAt(23), startedAt(23), startedAt(23)]),
        now: now,
      );
      expect(funnel.leak, FunnelLeak.none);
    });
  });

  group('코치에게 넘기는 묶음', () {
    test('유형 이름을 붙이지 않는다', () {
      final block = ExecutionFunnel.from(
        history([task(done: true, started: true), task()]),
        now: now,
      ).promptBlock();
      expect(block, isNot(contains('형')));
    });

    test('새는 곳을 한 줄로 알려준다', () {
      final block = ExecutionFunnel.from(
        history([task(done: true, started: true), task(), task(), task()]),
        now: now,
      ).promptBlock();
      expect(block, contains('제일 많이 새는 곳'));
    });

    test('앱이 쓰는 말로 부른다', () {
      // 지어낸 이름을 쓰면 코치가 그대로 받아 써서, 사용자에게 "첫 발 떼기가
      // 새고 있다" 같은 문장이 나간다.
      for (final name in ExecutionFunnel.leakNames.values) {
        expect(name, isNot(contains('첫 발')));
      }
      expect(
        ExecutionFunnel.leakNames[FunnelLeak.starting],
        startsWith('시작'),
      );
      expect(
        ExecutionFunnel.leakNames[FunnelLeak.finishing],
        startsWith('완료'),
      );
    });

    test('헷갈리는 짝에는 설명을 붙인다', () {
      // '계획한 양'과 '시작'은 둘 다 적어둔 것의 일부만 손댄 모습이라,
      // 이름만으로는 갈리지 않는다.
      expect(ExecutionFunnel.leakNames[FunnelLeak.amount], contains('매일 손은 대는데'));
      expect(ExecutionFunnel.leakNames[FunnelLeak.starting], contains('손도 안 댄 날'));
    });

    test('앱이 센 값이라는 것을 밝힌다', () {
      final block = ExecutionFunnel.from(
        history([task(done: true, started: true)]),
        now: now,
      ).promptBlock();
      expect(block, contains('여기 없는 것은 세지 않았음'));
    });
  });

  group('앞뒤 견주기', () {
    /// 앞 절반(4~7일 전)과 뒤 절반(1~3일 전)에 각각 다른 목록을 깐다.
    String halves({
      required List<Map<String, dynamic>> earlier,
      required List<Map<String, dynamic>> recent,
    }) => historyByDay({
      for (var back = 1; back <= 4; back++) back: recent,
      for (var back = 5; back <= 7; back++) back: earlier,
    });

    test('해내는 양이 늘었는데 목록이 더 크게 늘면 앞서간 것으로 본다', () {
      // 이 사람은 완료가 1개에서 3개로 늘었다. 그런데 계획이 2개에서 9개로
      // 늘어서 완료율은 50%에서 33%로 떨어진다. 완료율만 보면 나빠진 사람이다.
      final funnel = ExecutionFunnel.from(
        halves(
          earlier: [task(done: true, started: true), task(started: true)],
          recent: [
            for (var i = 0; i < 3; i++) task(done: true, started: true),
            for (var i = 0; i < 6; i++) task(started: true),
          ],
        ),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.outpaced);
      expect(funnel.promptBlock(), contains('전보다 더 해내고 있습니다'));
      expect(funnel.promptBlock(), contains('못 끝낸 것을 짚지 말고'));
    });

    test('늘릴수록 덜 해내면 과부하다', () {
      // 위와 완료율 방향은 같은데 완료 개수가 줄었다. 할 말은 정반대다.
      final funnel = ExecutionFunnel.from(
        halves(
          earlier: [
            for (var i = 0; i < 3; i++) task(done: true, started: true),
          ],
          recent: [
            task(done: true, started: true),
            for (var i = 0; i < 8; i++) task(started: true),
          ],
        ),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.overloaded);
    });

    test('목록은 그대로인데 더 해내면 그냥 좋아지는 중', () {
      final funnel = ExecutionFunnel.from(
        halves(
          earlier: [
            task(done: true, started: true),
            task(started: true),
            task(started: true),
          ],
          recent: [
            for (var i = 0; i < 3; i++) task(done: true, started: true),
          ],
        ),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.growing);
    });

    test('둘 다 줄면 힘이 빠지는 중', () {
      final funnel = ExecutionFunnel.from(
        halves(
          earlier: [
            for (var i = 0; i < 4; i++) task(done: true, started: true),
          ],
          recent: [task(done: true, started: true)],
        ),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.fading);
    });

    test('조금 달라진 것은 달라졌다고 하지 않는다', () {
      final funnel = ExecutionFunnel.from(
        history([task(done: true, started: true), task(started: true)]),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.steady);
      expect(funnel.promptBlock(), isNot(contains('추세')));
    });

    test('견줄 만큼 없으면 아무 말도 안 한다', () {
      final funnel = ExecutionFunnel.from(
        history([task(done: true, started: true)], days: 3),
        now: now,
      );
      expect(funnel.trend, FunnelTrend.unknown);
      expect(funnel.promptBlock(), isNot(contains('추세')));
    });

    test('안 적은 날도 추세에는 센다', () {
      // 목록이 있던 날만 세면, 뜸해진 사람이 "남은 날엔 잘하네"로 보인다.
      final funnel = ExecutionFunnel.from(
        historyByDay({
          for (var back = 5; back <= 7; back++)
            back: [for (var i = 0; i < 3; i++) task(done: true, started: true)],
          1: [task(done: true, started: true)],
        }),
        now: now,
      );
      expect(funnel.recentDays, 4);
      expect(funnel.trend, FunnelTrend.fading);
    });
  });

  group('추세만 떼어내기', () {
    String halves({
      required List<Map<String, dynamic>> earlier,
      required List<Map<String, dynamic>> recent,
    }) => historyByDay({
      for (var back = 1; back <= 4; back++) back: recent,
      for (var back = 5; back <= 7; back++) back: earlier,
    });

    test('단계 비교는 빼고 추세만 준다', () {
      // 실행 회고형이 받는 조각이다. 세 축까지 주면 무슨 회고든 유형
      // 이야기가 되어버린다.
      final block = ExecutionFunnel.from(
        halves(
          earlier: [task(done: true, started: true), task(started: true)],
          recent: [
            for (var i = 0; i < 3; i++) task(done: true, started: true),
            for (var i = 0; i < 6; i++) task(started: true),
          ],
        ),
        now: now,
      ).trendBlock();

      expect(block, contains('추세'));
      expect(block, contains('전보다 더 해내고 있습니다'));
      expect(block, isNot(contains('제일 많이 새는 곳')));
      expect(block, isNot(contains('시작  ')));
    });

    test('달라진 것이 없으면 아무것도 안 준다', () {
      final block = ExecutionFunnel.from(
        history([task(done: true, started: true), task(started: true)]),
        now: now,
      ).trendBlock();
      expect(block, isEmpty);
    });

    test('셀 것이 모자라면 아무것도 안 준다', () {
      expect(ExecutionFunnel.from(null, now: now).trendBlock(), isEmpty);
    });
  });
}
