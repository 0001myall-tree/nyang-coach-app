import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/life_context_service.dart';
import 'package:nyang_coach/services/master_greeting.dart';

/// 조건을 손으로 지어 넣어 컨텍스트를 만든다. 화면도 prefs도 필요 없다.
MasterGreetingContext ctx({
  required int hour,
  int planTotal = 0,
  int planDone = 0,
  int doneCount = 0,
  int startedCount = 0,
  String? doneLabel,
  List<String> pendingPlans = const [],
  int? daysSinceLastVisit,
  bool lateNight = false,
  bool repeatedLateNights = false,
  bool feltSick = false,
  bool resistedDone = false,
  String? resistedDoneLabel,
  bool offPlanResistance = false,
  String? startPatternLabel,
  String? upcomingPlanName,
  String? upcomingPlanTimeLabel,
}) {
  return MasterGreetingContext(
    now: DateTime(2026, 7, 30, hour, 30),
    daysSinceLastVisit: daysSinceLastVisit,
    planTotal: planTotal,
    planDone: planDone,
    doneCount: doneCount,
    startedCount: startedCount,
    doneLabel: doneLabel,
    pendingPlans: pendingPlans,
    lateNight: lateNight,
    repeatedLateNights: repeatedLateNights,
    feltSick: feltSick,
    resistedDone: resistedDone,
    resistedDoneLabel: resistedDoneLabel,
    offPlanResistance: offPlanResistance,
    startPatternLabel: startPatternLabel,
    upcomingPlanName: upcomingPlanName,
    upcomingPlanTimeLabel: upcomingPlanTimeLabel,
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
  '오후-진척있음': ctx(
    hour: 14,
    planTotal: 4,
    planDone: 2,
    doneCount: 2,
    doneLabel: "'운동'",
  ),
  '오후-완료0': ctx(hour: 14, planTotal: 4),
  '오전-곧시작할일정': ctx(
    hour: 10,
    planTotal: 2,
    upcomingPlanName: '집필',
    upcomingPlanTimeLabel: '오전 11시',
  ),
  '오후-곧시작할일정': ctx(
    hour: 14,
    planTotal: 3,
    upcomingPlanName: '집필',
    upcomingPlanTimeLabel: '오후 3시 30분',
  ),
  '저녁-곧시작할일정': ctx(
    hour: 19,
    planTotal: 2,
    upcomingPlanName: '운동',
    upcomingPlanTimeLabel: '오후 8시',
  ),
  '오후-계획없음': ctx(hour: 14),
  // 주 1회 오전 인사. 계획이 있든 없든 이 이야기가 오전 문구를 대신한다.
  '오전-시작패턴': ctx(hour: 8, startPatternLabel: '오전 8시~10시'),
  '오전-시작패턴-계획있음': ctx(hour: 10, planTotal: 3, startPatternLabel: '오전 8시~10시'),
  '낮-어제늦게잠': ctx(hour: 10, planTotal: 3, lateNight: true),
  '낮-늦은패턴반복': ctx(
    hour: 10,
    planTotal: 3,
    lateNight: true,
    repeatedLateNights: true,
  ),
  '낮-어제아팠음': ctx(hour: 10, planTotal: 3, feltSick: true),
  '낮-아픔이늦밤보다우선': ctx(hour: 10, lateNight: true, feltSick: true),
  '저녁-계획없음': ctx(hour: 20),
  '밤9시-남은게둘': ctx(
    hour: 21,
    planTotal: 4,
    planDone: 1,
    doneCount: 1,
    doneLabel: "'설거지'",
    pendingPlans: ['청소', '집필', '운동'],
  ),
  '저녁-절반이하': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 1,
    pendingPlans: ['설거지', '빨래', '운동'],
  ),
  '저녁-시작0': ctx(hour: 20, planTotal: 4, pendingPlans: ['설거지', '빨래', '운동']),
  // 저녁 초입(18~20시)은 하루가 아직 열려 있는 것으로 본다.
  '저녁초입-완료0': ctx(hour: 18, planTotal: 4, pendingPlans: ['설거지', '빨래', '운동']),
  '저녁초입-거의다': ctx(
    hour: 19,
    planTotal: 10,
    planDone: 9,
    doneCount: 9,
    doneLabel: "'운동' 외 8개",
  ),
  // 완료가 하나라도 있으면 저녁 초입이어도 원래 문구로 간다.
  '저녁초입-완료1개': ctx(
    hour: 18,
    planTotal: 4,
    planDone: 1,
    doneCount: 1,
    pendingPlans: ['설거지', '빨래', '운동'],
  ),
  '저녁-중간': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 3,
    doneCount: 3,
    doneLabel: "'운동' 외 2개",
  ),
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
  // 하기 싫다던 일을 끝낸 날. 완료율이 낮아도 이쪽이 오늘의 이야기다.
  '저녁-싫다던일완료': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 1,
    doneCount: 1,
    doneLabel: "'설거지'",
    pendingPlans: ['빨래', '운동'],
    resistedDone: true,
    resistedDoneLabel: "'설거지'",
  ),
  // 제목이 길면 이름을 빼고 해낸 것만 짚는다.
  '저녁-싫다던일완료-이름김': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 1,
    pendingPlans: ['빨래', '운동'],
    resistedDone: true,
  ),
  // 계획에 없는 일을 싫다고 한 날. 기록으로는 결과를 알 수 없어 직접 묻는다.
  '저녁-계획밖싫다': ctx(
    hour: 20,
    planTotal: 3,
    planDone: 2,
    doneCount: 2,
    doneLabel: "'운동' 외 1개",
    offPlanResistance: true,
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
  '복귀-저녁절반이하': ctx(
    hour: 20,
    planTotal: 4,
    planDone: 1,
    pendingPlans: ['설거지', '빨래', '운동'],
    daysSinceLastVisit: 5,
  ),
  '복귀-새벽': ctx(hour: 3, daysSinceLastVisit: 5),
};

/// 복귀한 날 낮·저녁에 붙는 문구. 슬롯 문구 대신 이걸로 끊는다.
final comebackDayCases = ['복귀-낮', '복귀-아팠음', '복귀-저녁전부완료', '복귀-저녁절반이하'];

/// 주 1회만 나가는 오전 인사. 다른 발화의 두세 문장 한도를 따르지 않는 유일한
/// 자리다 — 인사·알려주기·마무리가 한 덩어리라 여기서 줄이면 셋 중 하나가 빠진다.
final startPatternCases = ['오전-시작패턴', '오전-시작패턴-계획있음'];

final voices = {
  '여비서': MasterGreetingCopy.secretary,
  '냥할배': MasterGreetingCopy.nyangHalbae,
};

/// 한 코치의 문구 전부. 풀을 새로 만들면 여기에도 더해야 검사에 걸린다.
List<String> allTemplates(GreetingVoice v) => [
  ...v.dawn,
  ...v.earlyMorning,
  ...v.earlyStart,
  ...v.earlyQuestions,
  ...v.morningPlan,
  ...v.morningNoPlan,
  ...v.startPatternMorning,
  ...v.afternoonBehind,
  ...v.afternoonNoPlan,
  ...v.upcomingPlan,
  ...v.eveningLow,
  ...v.eveningMid,
  ...v.eveningHigh,
  ...v.earlyEveningNone,
  ...v.earlyEveningHigh,
  ...v.eveningNoStartMinimum,
  ...v.eveningMinimumBar,
  ...v.eveningAll,
  ...v.eveningNoPlan,
  ...v.eveningOffPlanAsk,
  ...v.offPlanDoneReply,
  ...v.coreAsk,
  ...v.coreAskStartedReply,
  ...v.coreAskAlreadyReply,
  ...v.coreAskBusyReply,
  ...v.repeatingAsk,
  ...v.stalledAsk,
  ...v.inProgressAck,
  ...v.inProgressAckOnly,
  ...v.inProgressAckSpent,
  ...v.inProgressAckSpentOnly,
  ...v.stalledDoneReply,
  ...v.stalledAlreadyDoneReply,
  ...v.stalledBusyReply,
  ...v.comeback,
  ...v.comebackSupport,
  ...v.afterLateNight,
  ...v.afterRepeatedLateNights,
  ...v.afterSick,
  for (final pool in [
    v.encStarted,
    v.encStrong,
    v.encFlow,
    v.encEvening,
    v.eveningResistedDone,
  ])
    for (final pair in pool) ...[pair.$1, pair.$2],
];

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
            // 주 1회 시작 패턴 인사만 예외다([startPatternCases] 참고).
            expect(
              sentenceCount(result.text),
              lessThanOrEqualTo(startPatternCases.contains(entry.key) ? 5 : 3),
              reason: where,
            );
          }
        });
      }
    }
  });

  group('복귀한 날은 뭘 했고 뭐가 남았는지 짚지 않는다', () {
    for (final voice in voices.entries) {
      test(voice.key, () {
        for (final name in comebackDayCases) {
          for (var seed = 0; seed < 50; seed++) {
            final result = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(cases[name]!);
            final where = '$name 씨앗 $seed: ${result.text}';

            expect(
              voice.value.comebackSupport.any(result.text.endsWith),
              isTrue,
              reason: where,
            );
            // 완료 항목 이름도, 미완료를 고르게 하는 카드도 나오지 않는다.
            expect(result.text, isNot(contains("'")), reason: where);
            expect(result.choices, isEmpty, reason: where);
            expect(sentenceCount(result.text), 2, reason: where);
          }
        }
      });
    }
  });

  group('주 1회 시작 패턴 인사', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 시간대를 그대로 알려준다', () {
        for (final name in startPatternCases) {
          for (var seed = 0; seed < 50; seed++) {
            final result = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(cases[name]!);
            final where = '$name 씨앗 $seed: ${result.text}';

            expect(result.text, contains('오전 8시~10시'), reason: where);
            // 화면은 이 값으로 주 1회를 센다. 꺼졌으면 다음 날 또 나간다.
            expect(result.usedStartPattern, isTrue, reason: where);
            // 시간대 이름은 앱이 계산해 붙인 것이라 인용부호로 묶지 않는다.
            expect(result.text, isNot(contains("'오전")), reason: where);
          }
        }
      });

      // 컨디션이 앞선다. 아픈 날 아침에 완료율 이야기를 꺼낼 수는 없고,
      // 오후에 "좋은 아침"이라고 할 수도 없다.
      test('${voice.key} / 아픈 날과 오후에는 나오지 않는다', () {
        final blocked = {
          '아팠던 다음 날': ctx(
            hour: 9,
            feltSick: true,
            startPatternLabel: '오전 8시~10시',
          ),
          '늦게 잔 다음 날': ctx(
            hour: 9,
            lateNight: true,
            startPatternLabel: '오전 8시~10시',
          ),
          '오후': ctx(hour: 14, planTotal: 2, startPatternLabel: '오전 8시~10시'),
        };
        for (final entry in blocked.entries) {
          for (var seed = 0; seed < 20; seed++) {
            final result = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(entry.value);
            expect(
              result.usedStartPattern,
              isFalse,
              reason: '${entry.key} 씨앗 $seed: ${result.text}',
            );
          }
        }
      });
    }
  });

  // 상황 문장과 질문 문장을 각각 두면 둘이 같은 말을 하게 된다. 실제로
  // "막히는 점 있으면 말씀해 주세요. 필요하신 게 있으면 말씀해 주세요."가 나갔다.
  group('늦게 잔 다음 날 첫 낮 인사', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 체력을 묻고 최소 성공 기준을 허용한다', () {
        final context = ctx(hour: 10, planTotal: 3, lateNight: true);
        for (var seed = 0; seed < 50; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context).text;
          final where = '씨앗 $seed: $text';

          expect(text, contains('최소 성공 기준'), reason: where);
          expect(
            text.contains('체력') || text.contains('컨디션'),
            isTrue,
            reason: where,
          );
        }
      });
    }
  });

  group('늦은 패턴이 반복된 다음 날 첫 낮 인사', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 일을 늘리기보다 체력 활동을 제안한다', () {
        final context = ctx(
          hour: 10,
          planTotal: 3,
          lateNight: true,
          repeatedLateNights: true,
        );
        for (var seed = 0; seed < 50; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context).text;
          final where = '씨앗 $seed: $text';

          expect(text, contains('체력'), reason: where);
          expect(text, contains('일정'), reason: where);
          expect(
            text.contains('일을 더 늘리기보다') ||
                text.contains('계획을 더 늘리기보다') ||
                text.contains('할 일을 더 보태기보다'),
            isTrue,
            reason: where,
          );
        }
      });
    }
  });

  group('9시 뒤 낮 발화는 한 문장이다', () {
    final dayCases = [
      '오전-계획있음',
      '오전-계획없음',
      '오전-완료1개',
      '오전-완료3개',
      '오후-진척있음',
      '오후-완료0',
      '오후-계획없음',
    ];
    for (final voice in voices.entries) {
      test(voice.key, () {
        for (final name in dayCases) {
          for (var seed = 0; seed < 50; seed++) {
            final text = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(cases[name]!).text;
            expect(sentenceCount(text), 1, reason: '$name 씨앗 $seed: $text');
          }
        }
      });
    }
  });

  // 문구가 여럿이어도 실제로 한 가지만 나오면 밑천이 하나인 것과 같다.
  group('갈래', () {
    // 지문이 짧으면 반복 회피가 헐거워진다. 갈래를 촘촘히 넣다가 고정 부분을
    // 다 없애면 같은 틀이 이틀 연속 나올 수 있으므로 길이를 지킨다.
    test('모든 틀에 알아볼 만한 지문이 남아 있다', () {
      for (final voice in voices.entries) {
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (final pool in [
          voice.value.earlyStart,
          voice.value.earlyQuestions,
          voice.value.morningPlan,
          voice.value.morningNoPlan,
          voice.value.startPatternMorning,
          voice.value.afternoonBehind,
          voice.value.afternoonNoPlan,
          voice.value.upcomingPlan,
          voice.value.dawn,
          voice.value.earlyMorning,
          voice.value.eveningLow,
          voice.value.eveningMid,
          voice.value.eveningHigh,
          voice.value.earlyEveningNone,
          voice.value.earlyEveningHigh,
          voice.value.eveningNoStartMinimum,
          voice.value.eveningMinimumBar,
          voice.value.eveningAll,
          voice.value.eveningNoPlan,
          voice.value.eveningOffPlanAsk,
          voice.value.offPlanDoneReply,
          voice.value.afterRepeatedLateNights,
        ]) {
          for (final template in pool) {
            expect(
              builder.anchor(template).length,
              greaterThanOrEqualTo(4),
              reason: '${voice.key}: $template',
            );
          }
        }
      }
    });

    // '{...하루|...날}였는지'처럼 갈래 바로 뒤에 받침을 타는 어미가 오면, 갈래
    // 후보에 따라 문장이 깨진다('어떤 날였는지'). 씨앗을 훑어도 조합 운에 걸리는
    // 종류라 문구를 훑어서 구조로 잡는다.
    test('갈래 뒤에 붙는 어미가 받침을 타지 않는다', () {
      // 앞 글자 받침에 따라 형태가 갈리는 조사·어미의 첫 글자.
      const risky = {'였', '을', '를', '은', '는', '이', '가', '와', '과', '로', '으'};
      // 한글 음절은 (초성, 중성, 종성)이 한 글자에 담긴다. 종성 자리가 0이면 받침이 없다.
      bool endsWithConsonant(String option) {
        final code = option.runes.last;
        if (code < 0xAC00 || code > 0xD7A3) return false;
        return (code - 0xAC00) % 28 != 0;
      }

      final group = RegExp(r'\{([^{}]*\|[^{}]*)\}');
      for (final voice in voices.entries) {
        for (final template in allTemplates(voice.value)) {
          for (final match in group.allMatches(template)) {
            final after = match.end < template.length
                ? template[match.end]
                : '';
            if (!risky.contains(after)) continue;
            final endings = match
                .group(1)!
                .split('|')
                .where((option) => option.isNotEmpty)
                .map(endsWithConsonant)
                .toSet();
            expect(
              endings.length,
              lessThanOrEqualTo(1),
              reason: "${voice.key}: '$after' 앞 갈래의 받침이 갈린다 — $template",
            );
          }
        }
      }
    });

    test('갈래 표기가 펼쳐지지 않고 새어 나가지 않는다', () {
      for (final voice in voices.values) {
        for (final entry in cases.entries) {
          for (var seed = 0; seed < 50; seed++) {
            final text = MasterGreetingBuilder(
              voice: voice,
              random: Random(seed),
            ).build(entry.value).text;
            expect(text, isNot(contains('{')), reason: text);
            expect(text, isNot(contains('|')), reason: text);
            expect(text, isNot(contains('}')), reason: text);
          }
        }
      }
    });

    test('아침 인사가 열 가지 넘게 나온다', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        seen.add(
          MasterGreetingBuilder(
            voice: MasterGreetingCopy.secretary,
            random: Random(seed),
          ).build(cases['이른아침-완료없음']!).text,
        );
      }
      // 갈래 이전에는 earlyStart 4 × earlyQuestions 3 = 12가지가 전부였다.
      expect(seen.length, greaterThan(30), reason: '${seen.length}가지');
    });

    // 저녁과 새벽은 한 발화에 문구 하나만 나가므로 풀 크기가 곧 밑천이다.
    // 갈래를 넣기 전에는 새벽 3가지, 저녁 완주 3가지가 전부였다.
    test('새벽과 저녁도 문구 수보다 많이 나온다', () {
      for (final voice in voices.entries) {
        final pools = {
          '새벽': cases['새벽-아직안잠']!,
          '이른아침': cases['새벽-일찍깸']!,
          '저녁-전부완료': cases['저녁-전부완료']!,
          '저녁-계획없음': cases['저녁-계획없음']!,
          // 뒷문장이 고정이라 앞머리를 갈라 넓혀둔 자리다. 갈래가 줄면 여기서 걸린다.
          '저녁초입-완료0': cases['저녁초입-완료0']!,
        };
        for (final entry in pools.entries) {
          final seen = <String>{};
          for (var seed = 0; seed < 200; seed++) {
            seen.add(
              MasterGreetingBuilder(
                voice: voice.value,
                random: Random(seed),
              ).build(entry.value).text,
            );
          }
          expect(
            seen.length,
            greaterThan(5),
            reason: '${voice.key} ${entry.key}: ${seen.length}가지',
          );
        }
      }
    });
  });

  test('복귀 인사가 한 가지로 굳어 있지 않다', () {
    final seen = <String>{};
    for (var seed = 0; seed < 50; seed++) {
      seen.add(
        MasterGreetingBuilder(
          voice: MasterGreetingCopy.secretary,
          random: Random(seed),
        ).build(cases['복귀-낮']!).text,
      );
    }
    // 복귀 3 × 도움 제안 3 = 9가지가 가능하다.
    expect(seen.length, greaterThanOrEqualTo(6), reason: seen.join('\n'));
  });

  test('복귀해도 새벽에는 재우는 말을 한다', () {
    for (var seed = 0; seed < 50; seed++) {
      final result = MasterGreetingBuilder(
        voice: MasterGreetingCopy.secretary,
        random: Random(seed),
      ).build(cases['복귀-새벽']!);
      expect(
        MasterGreetingCopy.secretary.comebackSupport.any(
          (line) => result.text.contains(line),
        ),
        isFalse,
        reason: '씨앗 $seed: ${result.text}',
      );
    }
  });

  // 18시에 하루가 딱 끊기면 "수고하셨습니다"가 이르다. 20시 전까지는 아직
  // 열려 있는 하루로 말하는지, 20시부터는 원래 마무리 문구로 돌아오는지 본다.
  // 시각을 정해둔 일정이 곧 시작하는데 "가벼운 것부터 하나 잡아볼까요"가 나가면,
  // 이미 정해둔 사람에게 딴 데를 가리키는 말이 된다.
  group('곧 시작할 일정이 있으면 그것을 짚는다', () {
    final upcomingCases = ['오전-곧시작할일정', '오후-곧시작할일정', '저녁-곧시작할일정'];
    for (final voice in voices.entries) {
      test('${voice.key} / 시각과 일 이름을 그대로 말한다', () {
        for (final name in upcomingCases) {
          final context = cases[name]!;
          for (var seed = 0; seed < 30; seed++) {
            final text = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(context).text;
            final where = '$name 씨앗 $seed: $text';
            expect(
              text,
              contains(context.upcomingPlanTimeLabel!),
              reason: where,
            );
            expect(
              text,
              contains("'${context.upcomingPlanName!}'"),
              reason: where,
            );
          }
        }
      });

      // 아직 시각이 오지 않았으니 지금 쉬는 게 맞다. 코치는 그래도 된다고만 한다.
      test('${voice.key} / 지금 시작하라고 재촉하지 않는다', () {
        const pushy = ['시작해보', '잡아볼까', '골라드릴까', '골라줄까', '열어볼까', '늦지 않'];
        for (final name in upcomingCases) {
          for (var seed = 0; seed < 30; seed++) {
            final text = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(cases[name]!).text;
            for (final word in pushy) {
              expect(
                text,
                isNot(contains(word)),
                reason: '$name 씨앗 $seed: $text',
              );
            }
          }
        }
      });
    }

    // 준비를 짚는 것까지가 이 자리의 목적이지만, 그 말로 문장을 끝내면 숙제가
    // 된다. 마지막은 반드시 쉬어도 된다는 말이어야 한다.
    for (final voice in voices.entries) {
      test('${voice.key} / 문장이 쉬어도 된다는 말로 끝난다', () {
        for (final template in voice.value.upcomingPlan) {
          for (var seed = 0; seed < 20; seed++) {
            final text = GreetingLinePicker(
              random: Random(seed),
            ).fillUpcoming([template], name: '집필', timeLabel: '오후 3시');
            final last = text
                .split(RegExp(r'(?<=[.?!])\s+'))
                .where((s) => s.trim().isNotEmpty)
                .last;
            expect(
              ['쉬', '편히', '가볍게', '놀'].any(last.contains),
              isTrue,
              reason: '${voice.key} 씨앗 $seed: $last',
            );
          }
        }
      });
    }

    // 하나라도 해낸 사람에게는 원래 흐름대로 말한다. 이 문구는 아직 아무것도
    // 못 한 사람을 위한 자리다.
    test('완료가 하나라도 있으면 나오지 않는다', () {
      final context = ctx(
        hour: 14,
        planTotal: 3,
        planDone: 1,
        doneCount: 1,
        doneLabel: "'설거지'",
        upcomingPlanName: '집필',
        upcomingPlanTimeLabel: '오후 3시 30분',
      );
      for (final voice in voices.values) {
        for (var seed = 0; seed < 30; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice,
            random: Random(seed),
          ).build(context).text;
          expect(text, isNot(contains('오후 3시 30분')), reason: '씨앗 $seed: $text');
        }
      }
    });
  });

  // 냥냥이는 슬롯 인사를 쓰지 않는다. 이 한 자리만 앱이 만들어 내보낸다.
  group('냥냥이가 곧 시작할 일정을 짚는 말', () {
    final picker = GreetingLinePicker(random: Random(0));

    test('시각과 일 이름을 그대로 말한다', () {
      for (var seed = 0; seed < 30; seed++) {
        final text = GreetingLinePicker(random: Random(seed)).fillUpcoming(
          MasterGreetingCopy.catUpcomingPlan,
          name: '집필',
          timeLabel: '오후 3시 30분',
        );
        expect(text, contains('오후 3시 30분'), reason: '씨앗 $seed: $text');
        expect(text, contains("'집필'"), reason: '씨앗 $seed: $text');
        expect(text, isNot(contains('{')), reason: '씨앗 $seed: $text');
        expect(text, isNot(contains('{{')), reason: '씨앗 $seed: $text');
      }
    });

    test('재촉하거나 숙제를 주지 않는다', () {
      // 준비를 짚는 말은 막지 않는다 — 그건 이 자리의 목적이다.
      // 막는 것은 지금 시작하라고 미는 말이다.
      const pushy = ['시작해보', '잡아볼까', '골라줄까', '열어볼까', '늦지 않'];
      for (var seed = 0; seed < 30; seed++) {
        final text = GreetingLinePicker(random: Random(seed)).fillUpcoming(
          MasterGreetingCopy.catUpcomingPlan,
          name: '집필',
          timeLabel: '오후 3시 30분',
        );
        for (final word in pushy) {
          expect(text, isNot(contains(word)), reason: '씨앗 $seed: $text');
        }
      }
    });

    test('냥냥이 말투로 끝난다', () {
      for (final template in MasterGreetingCopy.catUpcomingPlan) {
        expect(picker.anchor(template).length, greaterThanOrEqualTo(4));
        for (var seed = 0; seed < 20; seed++) {
          final text = GreetingLinePicker(
            random: Random(seed),
          ).fillUpcoming([template], name: '집필', timeLabel: '오후 3시');
          expect(text.contains('냥'), isTrue, reason: text);
        }
      }
    });
  });

  group('냥냥이가 늦게 잔 다음 날 최소 성공 기준을 잡는 말', () {
    test('무리하지 말고 기준을 낮추자고 짧게 말한다', () {
      for (final template
          in MasterGreetingCopy.catAfterLateNightMinimumSuccess) {
        final text = GreetingLinePicker(random: Random(1)).pickLine([template]);
        expect(text, contains('냥'), reason: text);
        expect(text, contains('최소 성공 기준'), reason: text);
        expect(
          text.contains('무리하지') || text.contains('에너지와 체력에 맞게'),
          isTrue,
          reason: text,
        );
        expect(sentenceCount(text), lessThanOrEqualTo(3), reason: text);
      }
    });

    test('저녁에는 남은 체력 기준으로 하나만 보자고 말한다', () {
      for (final template
          in MasterGreetingCopy.catAfterLateNightEveningMinimum) {
        final text = GreetingLinePicker(random: Random(1)).pickLine([template]);
        expect(text, contains('냥'), reason: text);
        expect(text, contains('체력'), reason: text);
        expect(text, contains('하나'), reason: text);
        expect(
          text.contains('쪼개') || text.contains('작게'),
          isTrue,
          reason: text,
        );
        expect(sentenceCount(text), lessThanOrEqualTo(3), reason: text);
      }
    });
  });

  // 밤 9시에 "남은 걸 다 하자"는 말은 쓸모가 없다. 대신 계획을 좁히게 돕는다.
  group('밤 9시대에 남은 게 둘 이상이면 기준을 좁히자고 한다', () {
    final context = cases['밤9시-남은게둘']!;

    for (final voice in voices.entries) {
      test('${voice.key} / 하나를 줄여서 다시 잡자고 말한다', () {
        for (var seed = 0; seed < 30; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context).text;
          final where = '씨앗 $seed: $text';
          // 핵심은 계획을 고쳐 잡는 것이다. 하나를 고르라는 말만으로는 부족하다.
          expect(
            ['줄여', '작게', '고쳐', '바꿔', '조각'].any(text.contains),
            isTrue,
            reason: where,
          );
          expect(['하나', '최소 성공'].any(text.contains), isTrue, reason: where);
        }
      });

      // 남은 것을 다 해내라는 말이 섞이면 이 자리의 뜻이 뒤집힌다.
      test('${voice.key} / 남은 걸 다 하라고 하지 않는다', () {
        const pushy = ['다 끝내', '남김없이', '전부 마치', '마저 하'];
        for (var seed = 0; seed < 30; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context).text;
          for (final word in pushy) {
            expect(text, isNot(contains(word)), reason: '씨앗 $seed: $text');
          }
        }
      });
    }

    // '성공 기준'이라고만 하면 기준을 낮춘 것이 되어, 계속 타협하다 영영 밀릴까
    // 걱정하게 된다. '최소'는 바닥을 두는 말이라 그 걱정을 막는다.
    // 줄인다는 게 어떤 모양인지는 전후를 나란히 보여줘야 잡힌다.
    test('줄인 전후를 예로 보여준다', () {
      for (final pool in [
        ...voices.values.map((v) => v.eveningMinimumBar),
        MasterGreetingCopy.catEveningMinimumBar,
      ]) {
        expect(
          pool.any((line) => line.contains('1화 개요만 쓰기')),
          isTrue,
          reason: '줄인 뒤가 어떤 모양인지 보여주는 문구가 없다',
        );
      }
    });

    // 빈자리가 그대로 나가면 사용자에게 {{task}}가 보인다.
    test('채우지 못한 자리가 남아 있지 않다', () {
      for (final pool in [
        ...voices.values.map((v) => v.eveningMinimumBar),
        MasterGreetingCopy.catEveningMinimumBar,
      ]) {
        for (final template in pool) {
          expect(template, isNot(contains('{{')), reason: template);
        }
      }
    });

    test('모든 문구가 최소 성공이라고 말한다', () {
      for (final pool in [
        ...voices.values.map((v) => v.eveningMinimumBar),
        MasterGreetingCopy.catEveningMinimumBar,
      ]) {
        for (final template in pool) {
          expect(template, contains('최소 성공'), reason: template);
        }
      }
    });

    test('냥냥이도 같은 말을 한다', () {
      for (var seed = 0; seed < 30; seed++) {
        final text = GreetingLinePicker(
          random: Random(seed),
        ).pickLine(MasterGreetingCopy.catEveningMinimumBar);
        expect(text.contains('냥'), isTrue, reason: '씨앗 $seed: $text');
        expect(text, isNot(contains('{')), reason: '씨앗 $seed: $text');
      }
    });

    // 하나만 남았어도 나간다. 그 하나가 너무 커서 못 하고 있는 것일 수 있다.
    test('하나만 남아도 나오고, 절반을 넘겼으면 나오지 않는다', () {
      final onlyOne = ctx(
        hour: 21,
        planTotal: 2,
        planDone: 1,
        doneCount: 1,
        pendingPlans: ['청소'],
      );
      final mostlyDone = ctx(
        hour: 21,
        planTotal: 4,
        planDone: 3,
        doneCount: 3,
        pendingPlans: ['청소'],
      );
      final nothingLeft = ctx(
        hour: 21,
        planTotal: 2,
        planDone: 2,
        doneCount: 2,
      );
      expect(onlyOne.needsMinimumBar, isTrue);
      expect(mostlyDone.needsMinimumBar, isFalse);
      expect(nothingLeft.needsMinimumBar, isFalse);
    });

    // 계획을 고치는 건 사용자 몫이다. 코치가 "이렇게 하자"고 정해주면
    // 줄이라는 말이 또 하나의 지시가 된다.
    test('정해주지 않고 물어본다', () {
      for (final pool in [
        ...voices.values.map((v) => v.eveningMinimumBar),
        MasterGreetingCopy.catEveningMinimumBar,
      ]) {
        for (final template in pool) {
          expect(
            ['어때', '어떨', '어떠', '어떻'].any(template.contains),
            isTrue,
            reason: template,
          );
        }
      }
    });

    test('11시가 넘으면 아무 말도 하지 않는다', () {
      final late = ctx(hour: 23, planTotal: 4, pendingPlans: ['청소', '집필']);
      expect(late.needsMinimumBar, isFalse);
      for (final voice in voices.values) {
        expect(MasterGreetingBuilder(voice: voice).build(late).text, isEmpty);
      }
    });
  });

  group('저녁 초입은 하루를 접지 않는다', () {
    /// 발화가 이 풀의 어느 틀에서 나왔는지. 펼친 문장은 매번 달라서 지문으로 본다.
    bool camefrom(GreetingVoice voice, List<String> pool, String text) {
      final builder = MasterGreetingBuilder(voice: voice);
      return pool.any((t) => text.contains(builder.anchor(t)));
    }

    for (final voice in voices.entries) {
      test('${voice.key} / 완료 0이면 재촉 대신 아직 늦지 않았다고 한다', () {
        for (var seed = 0; seed < 50; seed++) {
          String build(String name) => MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases[name]!).text;

          final early = build('저녁초입-완료0');
          expect(
            camefrom(voice.value, voice.value.earlyEveningNone, early),
            isTrue,
            reason: '씨앗 $seed: $early',
          );
          // 하나라도 했거나 20시를 넘으면 원래대로 뭐가 걸렸는지 묻는다.
          for (final name in ['저녁초입-완료1개', '저녁-절반이하']) {
            final text = build(name);
            expect(
              camefrom(voice.value, voice.value.eveningLow, text),
              isTrue,
              reason: '$name 씨앗 $seed: $text',
            );
          }
        }
      });

      test('${voice.key} / 거의 끝났으면 코치도 기분이 좋다고 한다', () {
        for (var seed = 0; seed < 50; seed++) {
          final early = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases['저녁초입-거의다']!);
          expect(
            camefrom(voice.value, voice.value.earlyEveningHigh, early.text),
            isTrue,
            reason: '씨앗 $seed: ${early.text}',
          );
          // 뒤에 격려가 한 문장 더 붙으므로 여기서 늘어지면 세 문장이 된다.
          expect(
            sentenceCount(early.text),
            2,
            reason: '씨앗 $seed: ${early.text}',
          );

          final late = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases['저녁-거의다']!).text;
          expect(
            camefrom(voice.value, voice.value.eveningHigh, late),
            isTrue,
            reason: '씨앗 $seed: $late',
          );
        }
      });
    }
  });

  group('20시 이후 시작 기록이 없으면 성공 기준을 다시 잡는다', () {
    /// 발화가 이 풀의 어느 틀에서 나왔는지. 펼친 문장은 매번 달라서 지문으로 본다.
    bool camefrom(GreetingVoice voice, List<String> pool, String text) {
      final builder = MasterGreetingBuilder(voice: voice);
      return pool.any((t) => text.contains(builder.anchor(t)));
    }

    for (final voice in voices.entries) {
      test('${voice.key} / 에너지와 체력에 맞게 최소 성공 기준을 잡자고 한다', () {
        final context = ctx(
          hour: 20,
          planTotal: 3,
          pendingPlans: ['설거지', '빨래', '운동'],
        );
        for (var seed = 0; seed < 50; seed++) {
          final result = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context);
          final where = '씨앗 $seed: ${result.text}';

          expect(
            camefrom(
              voice.value,
              voice.value.eveningNoStartMinimum,
              result.text,
            ),
            isTrue,
            reason: where,
          );
          expect(result.text, contains('에너지와 체력에 맞게'), reason: where);
          expect(result.text, contains('오늘의 최소 성공 기준'), reason: where);
          expect(result.choices, isEmpty, reason: where);
        }
      });

      test('${voice.key} / 시작 흔적이 있으면 이 문구로 가지 않는다', () {
        final context = ctx(
          hour: 20,
          planTotal: 3,
          startedCount: 1,
          pendingPlans: ['설거지', '빨래', '운동'],
        );
        for (var seed = 0; seed < 20; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(context).text;
          expect(
            camefrom(voice.value, voice.value.eveningNoStartMinimum, text),
            isFalse,
            reason: '씨앗 $seed: $text',
          );
        }
      });
    }
  });

  group('하기 싫다던 일을 끝낸 저녁', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 해낸 것을 짚고 다음에도 돕겠다고 한다', () {
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (var seed = 0; seed < 50; seed++) {
          final named = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases['저녁-싫다던일완료']!);
          final where = '씨앗 $seed: ${named.text}';

          // 완료율이 25%라 원래는 뭐가 걸렸는지 묻고 카드를 띄우던 자리다.
          expect(
            voice.value.eveningResistedDone.any(
              (pair) => named.text.contains(
                builder.anchor(pair.$1.replaceAll('{{task}}', "'설거지'")),
              ),
            ),
            isTrue,
            reason: where,
          );
          expect(named.text, contains("'설거지'"), reason: where);
          expect(named.choices, isEmpty, reason: where);
          expect(sentenceCount(named.text), 2, reason: where);

          // 이름이 길어 못 넣는 날도 축하는 나가야 한다.
          final unnamed = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases['저녁-싫다던일완료-이름김']!);
          expect(
            voice.value.eveningResistedDone.any(
              (pair) => unnamed.text.contains(builder.anchor(pair.$2)),
            ),
            isTrue,
            reason: '씨앗 $seed: ${unnamed.text}',
          );
          expect(unnamed.choices, isEmpty, reason: '씨앗 $seed: ${unnamed.text}');
        }
      });
    }
  });

  group('계획에 없어 확인할 길이 없는 일', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 물어보고 두 버튼을 준다', () {
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (var seed = 0; seed < 50; seed++) {
          final result = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).build(cases['저녁-계획밖싫다']!);
          final where = '씨앗 $seed: ${result.text}';

          expect(
            voice.value.eveningOffPlanAsk.any(
              (t) => result.text.contains(builder.anchor(t)),
            ),
            isTrue,
            reason: where,
          );
          // 일정 이름이 아니라 대답 버튼이 붙는다.
          expect(result.choices, [
            MasterGreetingCopy.offPlanDoneLabel,
            MasterGreetingCopy.offPlanNotYetLabel,
          ], reason: where);
          expect(sentenceCount(result.text), 1, reason: where);
        }
      });

      test('${voice.key} / 했다고 하면 코치가 자기 기분을 말한다', () {
        final seen = <String>{};
        for (var seed = 0; seed < 100; seed++) {
          seen.add(
            MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).pickLine(voice.value.offPlanDoneReply),
          );
        }
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (final line in seen) {
          // 진척을 짚는 게 아니라 코치가 자기 기분을 말하는 자리다.
          expect(line, matches(RegExp('후련|시원')), reason: line);
          expect(
            voice.value.offPlanDoneReply.any(
              (t) => line.contains(builder.anchor(t)),
            ),
            isTrue,
            reason: line,
          );
        }
        expect(seen.length, greaterThan(2), reason: '${seen.length}가지');
      });
    }
  });

  test('저녁 절반 이하에서만 선택 카드가 붙는다', () {
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      random: Random(1),
    );
    for (final entry in cases.entries) {
      final result = builder.build(entry.value);
      final expectsCard = const {
        '저녁-절반이하',
        '저녁초입-완료0',
        '저녁초입-완료1개',
        '저녁-계획밖싫다',
      }.contains(entry.key);
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

  test('최근에 쓴 틀은 다시 고르지 않는다', () {
    final pool = MasterGreetingCopy.secretary.earlyStart;
    final plain = MasterGreetingBuilder(voice: MasterGreetingCopy.secretary);
    // 마지막 틀만 빼고 전부 최근에 나온 것으로 둔다. 최근 목록에는 실제 발화가
    // 담기므로, 틀이 아니라 펼친 문장을 넣어야 실제와 같은 조건이 된다.
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      recentLines: pool
          .take(pool.length - 1)
          .map(plain.expand)
          .toList(growable: false),
    );
    final left = plain.anchor(pool.last);
    for (var i = 0; i < 20; i++) {
      expect(builder.pickLine(pool), contains(left));
    }
  });

  test('풀이 전부 최근에 나왔으면 굳이 침묵하지 않는다', () {
    final pool = MasterGreetingCopy.secretary.earlyStart;
    final plain = MasterGreetingBuilder(voice: MasterGreetingCopy.secretary);
    final builder = MasterGreetingBuilder(
      voice: MasterGreetingCopy.secretary,
      recentLines: pool.map(plain.expand).toList(growable: false),
    );
    final line = builder.pickLine(pool);
    expect(
      pool.any((t) => line.contains(plain.anchor(t))),
      isTrue,
      reason: line,
    );
  });

  test('씨앗이 같으면 같은 문장이 나온다', () {
    MasterGreetingResult run() => MasterGreetingBuilder(
      voice: MasterGreetingCopy.nyangHalbae,
      random: Random(7),
    ).build(cases['오전-계획있음']!);
    expect(run().text, run().text);
  });

  group('습관도 완료율에 넣는다', () {
    MasterGreetingContext eveningWith({
      required int planTotal,
      required int planDone,
      required int habitTotal,
      required int habitDone,
    }) => MasterGreetingContext(
      now: DateTime(2026, 8, 8, 21, 0),
      daysSinceLastVisit: null,
      planTotal: planTotal,
      planDone: planDone,
      habitTotal: habitTotal,
      habitDone: habitDone,
      doneCount: planDone + habitDone,
      doneLabel: null,
      pendingPlans: const [],
      lateNight: false,
      feltSick: false,
    );

    for (final voice in voices.entries) {
      // 일정만 끝내고 습관이 통째로 남았는데 "전부 마치셨다"고 할 수 없다.
      test('${voice.key} / 습관이 남았으면 다 마쳤다고 하지 않는다', () {
        final text =
            MasterGreetingBuilder(voice: voice.value, random: Random(1))
                .build(
                  eveningWith(
                    planTotal: 2,
                    planDone: 2,
                    habitTotal: 5,
                    habitDone: 0,
                  ),
                )
                .text;
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (final line in voice.value.eveningAll) {
          expect(text, isNot(contains(builder.anchor(line))), reason: text);
        }
      });

      test('${voice.key} / 일정과 습관을 다 끝내면 완주로 본다', () {
        final text =
            MasterGreetingBuilder(voice: voice.value, random: Random(1))
                .build(
                  eveningWith(
                    planTotal: 2,
                    planDone: 2,
                    habitTotal: 3,
                    habitDone: 3,
                  ),
                )
                .text;
        final builder = MasterGreetingBuilder(voice: voice.value);
        expect(
          voice.value.eveningAll.any(
            (line) => text.contains(builder.anchor(line)),
          ),
          isTrue,
          reason: text,
        );
      });
    }

    // 습관은 자정 리셋이 자동으로 채워 넣는다. 완료율에만 넣고 계획 유무에는
    // 넣지 않아야 "오늘 계획이 없네요" 분기가 살아 있다.
    test('습관만 있는 날은 여전히 계획 없음으로 본다', () {
      final context = eveningWith(
        planTotal: 0,
        planDone: 0,
        habitTotal: 3,
        habitDone: 1,
      );
      expect(context.hasPlan, isFalse);
    });
  });

  group('늦은 밤에는 아무 말도 하지 않는다', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 23시부터 자정까지는 조용하다', () {
        for (var hour = 23; hour <= 23; hour++) {
          for (var seed = 0; seed < 20; seed++) {
            final result = MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).build(ctx(hour: hour, planTotal: 5, planDone: 2, doneCount: 2));
            expect(result.text, isEmpty, reason: '$hour시: ${result.text}');
            expect(result.choices, isEmpty);
          }
        }
      });

      // 반가움은 하루를 관리하는 말이 아니라서 늦은 시간에도 나간다.
      test('${voice.key} / 오래 만에 돌아온 날은 늦은 밤에도 반긴다', () {
        final result = MasterGreetingBuilder(
          voice: voice.value,
          random: Random(1),
        ).build(ctx(hour: 23, daysSinceLastVisit: 5));
        expect(result.text, isNotEmpty);
      });

      test('${voice.key} / 22시까지는 저녁 인사가 나온다', () {
        final result = MasterGreetingBuilder(
          voice: voice.value,
          random: Random(1),
        ).build(ctx(hour: 22, planTotal: 5, planDone: 4, doneCount: 4));
        expect(result.text, isNotEmpty);
      });

      // 자정을 넘기면 새벽 문구가 받는다. 그때는 재우는 말이라 나가는 게 맞다.
      test('${voice.key} / 자정 넘으면 다시 말을 건다', () {
        final result = MasterGreetingBuilder(
          voice: voice.value,
          random: Random(1),
        ).build(ctx(hour: 1));
        expect(result.text, isNotEmpty);
      });
    }
  });

  group('핵심 일정을 시작했는지 묻는 말', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 일정 이름을 따옴표로 넣어 묻는다', () {
        for (var seed = 0; seed < 50; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).buildCoreAsk('글쓰기');
          expect(text, contains("'글쓰기'"), reason: text);
          // 치환이 새면 말풍선에 {{task}}가 그대로 뜬다.
          expect(text, isNot(contains('task')), reason: text);
        }
      });

      test('${voice.key} / 갈래 표기가 새어 나가지 않는다', () {
        for (var seed = 0; seed < 50; seed++) {
          for (final text in [
            MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).buildCoreAsk('글쓰기'),
            for (final pool in [
              voice.value.coreAskStartedReply,
              voice.value.coreAskAlreadyReply,
              voice.value.coreAskBusyReply,
            ])
              MasterGreetingBuilder(
                voice: voice.value,
                random: Random(seed),
              ).pickLine(pool),
          ]) {
            expect(text, isNot(contains('{')), reason: text);
            expect(text, isNot(contains('|')), reason: text);
            expect(text, isNot(contains('}')), reason: text);
          }
        }
      });

      test('${voice.key} / 한 가지로 굳어 있지 않다', () {
        final seen = <String>{};
        for (var seed = 0; seed < 100; seed++) {
          seen.add(
            MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).buildCoreAsk('글쓰기'),
          );
        }
        expect(seen.length, greaterThan(5), reason: '${seen.length}가지');
      });

      // 표시를 대신 켰을 때와 이미 켜져 있을 때는 서로 다른 말이어야 한다.
      // 안 한 일을 했다고 하거나, 한 일을 또 했다고 하면 신뢰가 깨진다.
      test('${voice.key} / 표시를 켠 답과 이미 켜져 있던 답이 겹치지 않는다', () {
        expect(
          voice.value.coreAskStartedReply.toSet().intersection(
            voice.value.coreAskAlreadyReply.toSet(),
          ),
          isEmpty,
        );
      });
    }
  });

  group('시작해두고 멈춘 것 같은 일을 묻는 말', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 일정 이름을 따옴표로 넣어 묻는다', () {
        for (var seed = 0; seed < 50; seed++) {
          final text = MasterGreetingBuilder(
            voice: voice.value,
            random: Random(seed),
          ).buildStalledAsk('보고서 정리');
          expect(text, contains("'보고서 정리'"), reason: text);
          expect(text, isNot(contains('task')), reason: text);
        }
      });

      test('${voice.key} / 갈래 표기가 새어 나가지 않는다', () {
        for (var seed = 0; seed < 50; seed++) {
          for (final text in [
            MasterGreetingBuilder(
              voice: voice.value,
              random: Random(seed),
            ).buildStalledAsk('보고서 정리'),
            for (final pool in [
              voice.value.stalledDoneReply,
              voice.value.stalledAlreadyDoneReply,
              voice.value.stalledBusyReply,
            ])
              MasterGreetingBuilder(
                voice: voice.value,
                random: Random(seed),
              ).pickLine(pool),
          ]) {
            expect(text, isNot(contains('{')), reason: text);
            expect(text, isNot(contains('|')), reason: text);
            expect(text, isNot(contains('}')), reason: text);
          }
        }
      });

      // 완료로 바꿔준 날과 이미 완료였던 날은 서로 다른 말이어야 한다.
      // 안 바꿨는데 바꿨다고 하면 사용자가 기록을 못 믿게 된다.
      test('${voice.key} / 바꿔준 답과 이미 완료였던 답이 겹치지 않는다', () {
        expect(
          voice.value.stalledDoneReply.toSet().intersection(
            voice.value.stalledAlreadyDoneReply.toSet(),
          ),
          isEmpty,
        );
      });
    }
  });

  group('진행 중인 일을 인정하는 말', () {
    for (final voice in voices.entries) {
      test('${voice.key} / 자리를 남김없이 채운다', () {
        final builder = MasterGreetingBuilder(voice: voice.value);
        // 문구 풀에서 무엇이 뽑히든 자리표가 남아 있으면 안 된다.
        for (var i = 0; i < 50; i++) {
          for (final next in [null, '4화 쓰기']) {
            for (final spent in [null, '2시간']) {
              final text = builder.buildInProgressAck(
                '보고서',
                next,
                spentLabel: spent,
              );
              expect(text, isNot(contains('{{')));
              expect(text, contains('보고서'));
              if (next != null) expect(text, contains(next));
            }
          }
        }
      });

      test('${voice.key} / 남길 것이 없으면 다음 일을 지어내지 않는다', () {
        final builder = MasterGreetingBuilder(voice: voice.value);
        for (var i = 0; i < 50; i++) {
          final text = builder.buildInProgressAck('보고서', null);
          expect(text, isNot(contains('끝나시면')));
          expect(text, isNot(contains('끝나면')));
        }
      });
    }
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
    // 저장된 값에 남아 있는 옛 id. 여기서 갈리면 냥할배가 존댓말을 하게 된다.
    expect(
      MasterGreetingCopy.forCoach('sec_male'),
      same(MasterGreetingCopy.nyangHalbae),
    );
  });

  group('실행 유형 처방', () {
    final voices = {
      '비서': MasterGreetingCopy.secretary,
      '냥할배': MasterGreetingCopy.nyangHalbae,
    };

    test('두 코치 모두 모든 유형에 계획 있는 날/없는 날 문구를 갖고 있다', () {
      // 유형은 앱이 세어 붙이는 이름이라, 한쪽 코치에만 문구가 빠져 있으면
      // 그 코치는 그날 아무 말도 못 하고 조용히 넘어간다.
      final types = MasterGreetingCopy.secretary.typeAdvice.keys.toSet();
      expect(types, isNotEmpty);
      for (final entry in voices.entries) {
        expect(entry.value.typeAdvice.keys.toSet(), types, reason: entry.key);
        expect(
          entry.value.typeAdviceNoPlan.keys.toSet(),
          types,
          reason: entry.key,
        );
      }
    });

    test('계획 개수를 앞에 짚고, 없는 날은 없다고 말한다', () {
      for (final entry in voices.entries) {
        final builder = MasterGreetingBuilder(voice: entry.value);
        for (final type in entry.value.typeAdvice.keys) {
          final withPlan = builder.buildTypeAdvice(type, planCount: 5)!;
          expect(withPlan, contains('5가지'), reason: '${entry.key}/$type');
          expect(withPlan, isNot(contains('{{count}}')));

          final noPlan = builder.buildTypeAdvice(type, planCount: 0)!;
          expect(noPlan, isNot(contains('5가지')));
          // 적어둔 게 없다고 해놓고 "적어두신 것만으로"가 이어지면 어긋난다.
          expect(
            noPlan,
            isNot(contains('적어두신 것만으로')),
            reason: '${entry.key}/$type',
          );
          expect(
            noPlan,
            isNot(contains('적어둔 것만으로')),
            reason: '${entry.key}/$type',
          );
        }
      }
    });

    test('두 코치 모두 되는 날 조건 보기 전부에 문구를 갖고 있다', () {
      // 조건은 사용자가 고른 답이라 앱이 이름을 정한다. 한쪽 코치에 문구가
      // 빠져 있으면 그 사람은 그 자리에서 조건 처방을 영영 못 받는다.
      final answers = LifeContextService.conditionAnswers.keys.toSet();
      expect(answers, isNotEmpty);
      for (final entry in voices.entries) {
        expect(
          entry.value.conditionAdvice.keys.toSet(),
          answers,
          reason: entry.key,
        );
      }
    });

    test('조건 처방도 계획 개수를 앞에 짚는다', () {
      for (final entry in voices.entries) {
        final builder = MasterGreetingBuilder(voice: entry.value);
        for (final answer in entry.value.conditionAdvice.keys) {
          final withPlan = builder.buildConditionAdvice(answer, planCount: 5)!;
          expect(withPlan, contains('5가지'), reason: '${entry.key}/$answer');
          expect(
            builder.buildConditionAdvice(answer, planCount: 0)!,
            isNot(contains('5가지')),
          );
        }
      }
    });

    test('안 골라둔 조건이면 조용히 넘어간다', () {
      final builder = MasterGreetingBuilder(
        voice: MasterGreetingCopy.secretary,
      );
      expect(builder.buildConditionAdvice('없는답', planCount: 3), isNull);
    });

    test('문구를 안 채운 유형이면 조용히 넘어간다', () {
      final builder = MasterGreetingBuilder(
        voice: MasterGreetingCopy.secretary,
      );
      expect(builder.buildTypeAdvice('없는유형', planCount: 3), isNull);
      expect(builder.buildTypeAdvice('없는유형', planCount: 0), isNull);
    });
  });
}
