import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/master_greeting.dart';

/// 조건을 손으로 지어 넣어 컨텍스트를 만든다. 화면도 prefs도 필요 없다.
MasterGreetingContext ctx({
  required int hour,
  int planTotal = 0,
  int planDone = 0,
  int doneCount = 0,
  String? doneLabel,
  List<String> pendingPlans = const [],
  int? daysSinceLastVisit,
  bool lateNight = false,
  bool feltSick = false,
}) {
  return MasterGreetingContext(
    now: DateTime(2026, 7, 30, hour, 30),
    daysSinceLastVisit: daysSinceLastVisit,
    planTotal: planTotal,
    planDone: planDone,
    doneCount: doneCount,
    doneLabel: doneLabel,
    pendingPlans: pendingPlans,
    lateNight: lateNight,
    feltSick: feltSick,
  );
}

/// 발화 하나가 몇 문장인지. 문장 부호로 센다.
int sentenceCount(String text) =>
    text.split(RegExp(r'[.?!]')).where((s) => s.trim().isNotEmpty).length;

/// 모든 분기를 한 번씩 지나는 표. 이름은 실패했을 때 어느 칸인지 알아보려고 붙인다.
final cases = <String, MasterGreetingContext>{
  '새벽-아직안잠': ctx(hour: 3),
  '새벽-일찍깸': ctx(hour: 6),
  '이른아침-완료없음': ctx(hour: 8),
  '이른아침-완료있음': ctx(hour: 8, doneCount: 1, doneLabel: "'스트레칭'"),
  '오전-계획있음': ctx(hour: 10, planTotal: 3),
  '오전-계획없음': ctx(hour: 10),
  '오전-완료1개': ctx(hour: 10, planTotal: 3, doneCount: 1, doneLabel: "'설거지'"),
  '오전-완료3개': ctx(
    hour: 10,
    planTotal: 4,
    planDone: 3,
    doneCount: 3,
    doneLabel: "'설거지' 외 2개",
  ),
  '오후-진척있음': ctx(hour: 14, planTotal: 4, planDone: 2, doneCount: 2, doneLabel: "'운동'"),
  '오후-완료0': ctx(hour: 14, planTotal: 4),
  '오후-계획없음': ctx(hour: 14),
  '낮-어제늦게잠': ctx(hour: 10, planTotal: 3, lateNight: true),
  '낮-어제아팠음': ctx(hour: 10, planTotal: 3, feltSick: true),
  '낮-아픔이늦밤보다우선': ctx(hour: 10, lateNight: true, feltSick: true),
  '저녁-계획없음': ctx(hour: 20),
  '저녁-절반이하': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 1,
    pendingPlans: ['설거지', '빨래', '운동'],
  ),
  '저녁-중간': ctx(hour: 20, planTotal: 4, planDone: 3, doneCount: 3, doneLabel: "'운동' 외 2개"),
  '저녁-거의다': ctx(
    hour: 20,
    planTotal: 10,
    planDone: 9,
    doneCount: 9,
    doneLabel: "'운동' 외 8개",
  ),
  '저녁-전부완료': ctx(
    hour: 20,
    planTotal: 3,
    planDone: 3,
    doneCount: 3,
    doneLabel: "'운동' 외 2개",
  ),
  '복귀-낮': ctx(hour: 10, planTotal: 2, daysSinceLastVisit: 5),
  // 컨디션 문구는 그 자체로 두 문장이라 복귀 인사가 붙으면 한도에 딱 닿는다.
  '복귀-아팠음': ctx(hour: 10, planTotal: 2, daysSinceLastVisit: 5, feltSick: true),
  '복귀-저녁전부완료': ctx(
    hour: 20,
    planTotal: 2,
    planDone: 2,
    doneCount: 2,
    doneLabel: "'운동' 외 1개",
    daysSinceLastVisit: 5,
  ),
};

final voices = {
  '여비서': MasterGreetingCopy.secretary,
  '냥할배': MasterGreetingCopy.nyangHalbae,
};

void main() {
  group('모든 분기가 말이 되는 문장을 낸다', () {
    for (final voice in voices.entries) {
      for (final entry in cases.entries) {
        // 씨앗 하나만 보면 그 조합만 통과하고 넘어간다. 문구 풀을 골고루
        // 뽑도록 씨앗을 훑어서, 어떤 조합이 나와도 성립하는지 본다.
        test('${voice.key} / ${entry.key}', () {
          for (var seed = 0; seed < 50; seed++) {
            final result = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(entry.value);
            final where = '씨앗 $seed: ${result.text}';

            expect(result.text.trim(), isNotEmpty, reason: where);
            // 치환이 빠진 자리가 그대로 나가면 사용자에게 {{task}}가 보인다.
            expect(result.text, isNot(contains('{{')), reason: where);
            expect(result.text, isNot(contains('  ')), reason: where);
            // 복귀 인사가 붙어도 세 문장을 넘지 않는다.
            expect(
              sentenceCount(result.text),
              lessThanOrEqualTo(3),
              reason: where,
            );
          }
        });
      }
    }
  });

  test('저녁 절반 이하에서만 선택 카드가 붙는다', () {
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      random: Random(1),
    );
    for (final entry in cases.entries) {
      final result = builder.build(entry.value);
      final expectsCard = entry.key == '저녁-절반이하';
      expect(
        result.choices.isNotEmpty,
        expectsCard,
        reason: '${entry.key}: ${result.choices}',
      );
    }
  });

  group('저녁 선택 버튼', () {
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      random: Random(1),
    );

    test('3개까지는 그대로 세운다', () {
      expect(builder.eveningChoices(['가', '나', '다']), ['가', '나', '다']);
    });

    test("넘치면 3개만 세우고 '그 외'로 접는다", () {
      expect(builder.eveningChoices(['가', '나', '다', '라']), [
        '가',
        '나',
        '다',
        MasterGreetingCopy.secretary.otherChoiceLabel,
      ]);
    });

    test('미완료가 없으면 카드를 안 만든다', () {
      expect(builder.eveningChoices([]), isEmpty);
    });
  });

  test('최근에 쓴 문장은 다시 고르지 않는다', () {
    final pool = MasterGreetingCopy.secretary.earlyStart;
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      recentLines: pool.take(pool.length - 1).toList(),
    );
    // 하나만 남으므로 여러 번 골라도 그 하나여야 한다.
    for (var i = 0; i < 20; i++) {
      expect(builder.pickLine(pool), pool.last);
    }
  });

  test('풀이 전부 최근에 나왔으면 굳이 침묵하지 않는다', () {
    final pool = MasterGreetingCopy.secretary.earlyStart;
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      recentLines: pool,
    );
    expect(pool, contains(builder.pickLine(pool)));
  });

  test('씨앗이 같으면 같은 문장이 나온다', () {
    MasterGreetingResult run() => MasterGreetingBuilder(
      voice: MasterGreetingCopy.nyangHalbae,
      random: Random(7),
    ).build(cases['오전-계획있음']!);
    expect(run().text, run().text);
  });

  test('코치 id로 문구를 고른다', () {
    expect(
      MasterGreetingCopy.forCoach('nyang_halbae'),
      same(MasterGreetingCopy.nyangHalbae),
    );
    expect(
      MasterGreetingCopy.forCoach('nyang_secretary'),
      same(MasterGreetingCopy.secretary),
    );
  });
}
