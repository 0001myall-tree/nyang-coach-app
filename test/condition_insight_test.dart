import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/condition_insight.dart';

/// 주간 리포트의 네 번째 회고가 쓰는 층.
///
/// 여기서 확인하는 것은 "관계를 찾아내는가"가 아니라 **없는 것을 말하지 않는가**다.
/// 조건과 실행을 견주는 일은 재료만 있으면 쉬운데, 재료가 모자랄 때 입을 다무는
/// 것은 따로 만들어야 한다.
void main() {
  /// 하루치 기록 한 줄. [rate]만큼 완료된 할 일 [count]개를 만든다.
  Map<String, dynamic> day(
    String date, {
    required int count,
    required int done,
    int? startHour,
    int routines = 0,
    int routinesDone = 0,
    bool firstDone = true,
    List<int> touchHours = const [],
  }) {
    final tasks = <Map<String, dynamic>>[];
    for (var i = 0; i < routines; i++) {
      tasks.add({
        'text': '루틴$i',
        'category': 'habit',
        'done': i < routinesDone,
      });
    }
    for (var i = 0; i < count; i++) {
      final isDone = i < done;
      tasks.add({
        'text': '할 일$i',
        'category': 'today',
        'done': i == 0 ? firstDone : isDone,
        if (startHour != null)
          'startedAt': '${date}T${startHour.toString().padLeft(2, '0')}:00:00',
        if (i < touchHours.length)
          'completedAt':
              '${date}T${touchHours[i].toString().padLeft(2, '0')}:30:00',
      });
    }
    return {
      'date': date,
      'totalCount': tasks.length,
      'doneCount': tasks.where((t) => t['done'] == true).length,
      'tasks': tasks,
    };
  }

  String history(List<Map<String, dynamic>> days) => jsonEncode(days);

  /// 2026-09-01부터 하루씩. 짝수 날은 적게 잡고 다 해내고, 홀수 날은 많이
  /// 잡고 거의 못 해내는 사람.
  String smallPlanWins(int dayCount) {
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < dayCount; i++) {
      final date = DateTime(2026, 9, 1).add(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      days.add(
        i.isEven
            ? day(key, count: 2, done: 2)
            : day(key, count: 6, done: 1, firstDone: true),
      );
    }
    return history(days);
  }

  group('재료가 모자라면', () {
    test('기록이 없으면 아무 말도 안 한다', () {
      final insights = ConditionInsights.from(null);
      expect(insights.hasEnough, isFalse);
      expect(insights.top, isNull);
    });

    // 열흘이 최저선이다. 이레치는 아무리 잘 갈라도 5대 2라 한쪽이 빈다.
    test('이레치로는 아무 말도 안 한다', () {
      final insights = ConditionInsights.from(smallPlanWins(7));
      expect(insights.evaluatedDays, 7);
      expect(insights.hasEnough, isFalse);
    });

    test('열흘이 모이면 말하기 시작한다', () {
      final insights = ConditionInsights.from(smallPlanWins(10));
      expect(insights.evaluatedDays, 10);
      expect(insights.top, isNotNull);
    });

    // 늘 몰아서 하는 사람은 '나눠서 한 날'이 모이지 않는다. 그 축은 침묵한다.
    test('한쪽에 날이 안 모이면 그 축은 빠진다', () {
      final days = <Map<String, dynamic>>[];
      for (var i = 0; i < 20; i++) {
        final date = DateTime(2026, 9, 1).add(Duration(days: i));
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        // 모든 날이 같은 모양이다 — 견줄 반대편이 없다.
        days.add(day(key, count: 3, done: 2, startHour: 9));
      }
      final insights = ConditionInsights.from(history(days));
      expect(insights.evaluatedDays, 20);
      expect(insights.hasEnough, isFalse);
    });
  });

  group('관계가 뚜렷하면', () {
    test('적게 잡은 날이 나은 것을 짚는다', () {
      final insights = ConditionInsights.from(smallPlanWins(20));
      final top = insights.top;

      expect(top, isNotNull);
      expect(top!.axis, ConditionAxis.smallPlan);
      // "적게 잡은 날"이 아니라 몇 개까지 잡은 날인지가 나와야 다음 주에 쓴다.
      expect(top.cutoff, isNotNull);
      expect(top.label, contains('${top.cutoff}개'));
      expect(top.gap, greaterThan(ConditionInsights.minGap));
      expect(top.whenTrueDays, greaterThanOrEqualTo(5));
      expect(top.whenFalseDays, greaterThanOrEqualTo(5));
    });

    test('제일 센 것 하나만 고른다', () {
      final insights = ConditionInsights.from(smallPlanWins(20));
      expect(insights.top, isNotNull);
      // 여러 축이 걸렸더라도 밖으로 나가는 것은 하나뿐이다.
      expect(insights.findings.length, greaterThanOrEqualTo(1));
    });
  });

  // 앞 절반과 뒤 절반의 방향이 다르면 그건 관계가 아니라 우연이다.
  test('방향이 뒤집히는 관계는 권하지 않는다', () {
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < 20; i++) {
      final date = DateTime(2026, 9, 1).add(Duration(days: i));
      final key =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final firstHalf = i < 10;
      // 앞 절반은 적게 잡은 날이 낫고, 뒤 절반은 반대다.
      if (i.isEven) {
        days.add(
          firstHalf ? day(key, count: 2, done: 2) : day(key, count: 2, done: 0, firstDone: false),
        );
      } else {
        days.add(
          firstHalf ? day(key, count: 6, done: 1) : day(key, count: 6, done: 6),
        );
      }
    }

    final insights = ConditionInsights.from(history(days));
    for (final finding in insights.findings) {
      if (finding.axis == ConditionAxis.smallPlan) {
        expect(finding.consistent, isFalse);
        expect(finding.canSuggest, isFalse);
      }
    }
  });

  group('다음 날을 깎으면', () {
    test('제안하지 않고 주고받기로 남긴다', () {
      // 많이 잡은 날은 그날 다 해내지만 그다음 날이 무너지는 사람.
      final days = <Map<String, dynamic>>[];
      for (var i = 0; i < 20; i++) {
        final date = DateTime(2026, 9, 1).add(Duration(days: i));
        final key =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        days.add(
          i.isEven
              ? day(key, count: 2, done: 2)
              : day(key, count: 2, done: 0, firstDone: false),
        );
      }
      final insights = ConditionInsights.from(history(days));
      final top = insights.top;
      if (top != null && top.borrowsFromTomorrow) {
        expect(top.canSuggest, isFalse);
      }
    });
  });

  // 축마다 무엇을 권할 수 있는지는 미리 정해둔다. 손잡이가 없는 축이
  // 제안까지 가면, 같은 앱의 다른 회고와 반대되는 말이 나간다.
  test('손잡이 없는 축은 제안까지 가지 않는다', () {
    expect(ConditionAxis.spread.suggestable, isFalse);
    expect(ConditionAxis.smallPlan.suggestable, isTrue);
    expect(ConditionAxis.earlyStart.suggestable, isTrue);
  });
}
