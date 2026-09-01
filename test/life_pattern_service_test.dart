import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/life_pattern_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SharedPreferences.getInstance();
  });

  Future<Map<String, dynamic>> stored() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final raw = prefs.getString(LifePatternService.storeKey) ?? '{}';
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  group('이 기능을 쓰는 코치', () {
    test('담당 영역이 있는 셋만', () {
      expect(LifePatternService.handles('halmae'), isTrue);
      expect(LifePatternService.handles('bro'), isTrue);
      expect(LifePatternService.handles('boyfriend'), isTrue);
    });

    test('범용 코치와 마스터는 빠진다', () {
      // 냥냥이는 담당 영역이라는 것이 없고, 마스터는 영역을 안 가린다.
      expect(LifePatternService.handles('cat'), isFalse);
      expect(LifePatternService.handles('nyang_halbae'), isFalse);
      expect(LifePatternService.handles('sec_female'), isFalse);
    });

    test('맡지 않는 코치에는 아무것도 쓰지 않는다', () async {
      await LifePatternService.update('cat', {'answers': {}});
      expect(await stored(), isEmpty);
    });
  });

  group('설문', () {
    test('코치마다 문항이 있다', () {
      for (final coachId in LifePatternService.domains.keys) {
        expect(
          LifePatternService.questionsFor(coachId),
          isNotEmpty,
          reason: coachId,
        );
      }
    });

    test('문항 id는 코치 안에서 겹치지 않는다', () {
      for (final coachId in LifePatternService.domains.keys) {
        final ids = LifePatternService.questionsFor(
          coachId,
        ).map((q) => q.id).toList();
        expect(ids.toSet().length, ids.length, reason: coachId);
      }
    });

    test('보기마다 코치에게 넘길 말이 붙어 있다', () {
      for (final coachId in LifePatternService.domains.keys) {
        for (final question in LifePatternService.questionsFor(coachId)) {
          expect(question.options, isNotEmpty, reason: question.id);
          for (final entry in question.options.entries) {
            expect(entry.value.trim(), isNotEmpty, reason: entry.key);
          }
        }
      }
    });

    test('집안일은 분담부터 묻는다', () {
      // 남이 주로 하는 집이면 뒤 문항을 물을 이유부터 사라진다.
      expect(LifePatternService.questionsFor('halmae').first.id, 'share');
    });
  });

  group('첫 진입에는 세 문항까지', () {
    test('아무것도 안 물었으면 셋을 준다', () async {
      final ask = await LifePatternService.firstAsk('halmae');
      expect(ask.length, LifePatternService.firstAskLimit);
      expect(ask.first.id, 'share');
    });

    test('문항이 셋보다 적은 코치는 있는 만큼만', () async {
      final ask = await LifePatternService.firstAsk('boyfriend');
      expect(ask.length, lessThanOrEqualTo(LifePatternService.firstAskLimit));
    });

    test('하나 답하면 남은 몫만큼만 준다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      final ask = await LifePatternService.firstAsk('halmae');
      expect(ask.length, LifePatternService.firstAskLimit - 1);
      expect(ask.any((q) => q.id == 'share'), isFalse);
    });

    test('셋을 채우면 더 묻지 않는다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      await LifePatternService.saveAnswer('halmae', 'want', ['빨래']);
      await LifePatternService.saveAnswer('halmae', 'style', ['몰아서 하고 싶어']);
      expect(await LifePatternService.firstAsk('halmae'), isEmpty);
      expect(await LifePatternService.readyToCoach('halmae'), isTrue);
    });

    test('나머지는 제안할 때 하나씩', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      await LifePatternService.saveAnswer('halmae', 'want', ['빨래']);
      await LifePatternService.saveAnswer('halmae', 'style', ['몰아서 하고 싶어']);
      final next = await LifePatternService.nextFollowUp('halmae');
      expect(next?.id, 'current');
    });
  });

  group('답을 적는다', () {
    test('고른 말이 그대로 남는다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      expect((await LifePatternService.answers('halmae'))['share'], '대부분 내가 해');
    });

    test('복수 선택은 목록으로', () async {
      await LifePatternService.saveAnswer('halmae', 'want', ['빨래', '청소·정리']);
      expect((await LifePatternService.answers('halmae'))['want'], [
        '빨래',
        '청소·정리',
      ]);
    });

    test('목록에 없는 말은 받지 않는다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['아무 말']);
      expect(await LifePatternService.answers('halmae'), isEmpty);
    });

    test('없는 문항도 받지 않는다', () async {
      await LifePatternService.saveAnswer('halmae', '없는문항', ['대부분 내가 해']);
      expect(await LifePatternService.answers('halmae'), isEmpty);
    });

    test('코치끼리 섞이지 않는다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      await LifePatternService.saveAnswer('bro', 'posture', ['앉아 있는 시간이 많아']);
      expect((await LifePatternService.answers('halmae')).containsKey('posture'), isFalse);
      expect((await LifePatternService.answers('bro')).containsKey('share'), isFalse);
    });
  });

  group('다시 확인할 때', () {
    Future<void> answerFirstThree() async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      await LifePatternService.saveAnswer('halmae', 'want', ['빨래']);
      await LifePatternService.saveAnswer('halmae', 'style', ['몰아서 하고 싶어']);
    }

    test('첫 진입도 안 끝났으면 확인할 것이 없다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      expect(await LifePatternService.dueForReview('halmae'), isFalse);
    });

    test('막 답한 사람에게는 묻지 않는다', () async {
      await answerFirstThree();
      expect(await LifePatternService.dueForReview('halmae'), isFalse);
    });

    test('첫 확인은 2주 뒤', () async {
      await answerFirstThree();
      final later = DateTime.now().add(
        LifePatternService.firstReviewInterval + const Duration(hours: 1),
      );
      expect(
        await LifePatternService.dueForReview('halmae', now: later),
        isTrue,
      );
    });

    test('한 번 확인한 뒤에는 30일', () async {
      await answerFirstThree();
      final firstCheck = DateTime.now().add(
        LifePatternService.firstReviewInterval,
      );
      await LifePatternService.markReviewed('halmae', now: firstCheck);

      final twoWeeksLater = firstCheck.add(
        LifePatternService.firstReviewInterval,
      );
      expect(
        await LifePatternService.dueForReview('halmae', now: twoWeeksLater),
        isFalse,
      );

      final aMonthLater = firstCheck.add(
        LifePatternService.reviewInterval + const Duration(hours: 1),
      );
      expect(
        await LifePatternService.dueForReview('halmae', now: aMonthLater),
        isTrue,
      );
    });

    test('바뀌기 쉬운 답만 읽어준다', () async {
      await answerFirstThree();
      await LifePatternService.saveAnswer('halmae', 'household', ['혼자 살아']);
      final summary = await LifePatternService.reviewSummary('halmae');
      expect(summary, contains('빨래'));
      expect(summary, contains('몰아서 하고 싶어'));
      // 동거 형태는 몇 달째 그대로일 값이라 30일마다 확인할 이유가 없다.
      expect(summary, isNot(contains('혼자 살아')));
    });
  });

  group('역할 한 줄', () {
    test('맡은 영역이 있는 코치에만 붙는다', () {
      for (final coachId in LifePatternService.domains.keys) {
        expect(LifePatternService.roleLine(coachId), isNotEmpty, reason: coachId);
      }
      expect(LifePatternService.roleLine('cat'), isEmpty);
      expect(LifePatternService.roleLine('sec_female'), isEmpty);
    });

    test('코치마다 맡는 것이 다르다', () {
      final lines = LifePatternService.domains.keys
          .map(LifePatternService.roleLine)
          .toSet();
      expect(lines.length, LifePatternService.domains.length);
    });

    test('기회가 안 보이면 그냥 대화하라고 해둔다', () {
      // 대상을 찾아야 하는 동사는 이 앱에서 여러 번 지어내기로 이어졌다.
      for (final coachId in LifePatternService.domains.keys) {
        expect(
          LifePatternService.roleLine(coachId),
          contains('안 보이면 그냥 대화한다'),
          reason: coachId,
        );
      }
    });

    test('분량을 안 정했으면 더 갈지 멈출지 그때 정한다', () {
      // 무조건 끄는 것도 무조건 미는 것도 앱이 미리 정할 수 있는 것이 아니다.
      for (final coachId in LifePatternService.domains.keys) {
        expect(
          LifePatternService.roleLine(coachId),
          contains('그때 정한다'),
          reason: coachId,
        );
      }
    });

    test('이미 하는 일에 붙이는 쪽을 먼저 보게 한다', () {
      for (final coachId in LifePatternService.domains.keys) {
        expect(
          LifePatternService.roleLine(coachId),
          contains('이미 하는 일에 붙일 수 있는지'),
          reason: coachId,
        );
      }
    });
  });

  group('담당으로 가려둔 루틴', () {
    test('아직 안 갈랐으면 빈 집합', () async {
      expect(await LifePatternService.domainHabitIds('halmae'), isEmpty);
    });

    test('적어두면 그대로 읽힌다', () async {
      await LifePatternService.saveDomainHabitIds('halmae', {'h1', 'h4'});
      expect(await LifePatternService.domainHabitIds('halmae'), {'h1', 'h4'});
    });

    test('가른 시각도 함께 남는다', () async {
      await LifePatternService.saveDomainHabitIds('halmae', {'h1'});
      expect(
        (await LifePatternService.profile('halmae'))['analyzedAt'],
        isNotNull,
      );
    });

    test('설문 답을 덮어쓰지 않는다', () async {
      await LifePatternService.saveAnswer('halmae', 'share', ['대부분 내가 해']);
      await LifePatternService.saveDomainHabitIds('halmae', {'h1'});
      expect((await LifePatternService.answers('halmae'))['share'], '대부분 내가 해');
    });
  });

  group('코치에게 넘기는 묶음', () {
    test('답이 없으면 아무것도 안 싣는다', () async {
      expect(await LifePatternService.promptBlock('halmae'), isEmpty);
    });

    test('고른 말이 아니라 풀어 쓴 말이 실린다', () async {
      await LifePatternService.saveAnswer('bro', 'commute', ['대중교통을 많이 이용해']);
      final block = await LifePatternService.promptBlock('bro');
      expect(block, contains('이미 걷고 있음'));
    });

    test('본인이 고른 답이라는 것을 밝힌다', () async {
      await LifePatternService.saveAnswer('bro', 'posture', ['앉아 있는 시간이 많아']);
      expect(await LifePatternService.promptBlock('bro'), contains('본인이 고른 답'));
    });

    test('그 방식대로 잡으라고 못박는다', () async {
      // 실어주기만 하면 코치는 이 답을 읽고도 자기가 아는 일반적인 방법을
      // 권한다. 그 사람이 아니라고 말해둔 방식으로.
      await LifePatternService.saveAnswer('halmae', 'style', ['몰아서 하고 싶어']);
      final block = await LifePatternService.promptBlock('halmae');
      expect(block, contains('언제 어떻게 넣을지도 이 답 안에서'));
      expect(block, contains('어긋나게 권하지 마세요'));
    });

    test('맡지 않는 코치에는 실리지 않는다', () async {
      expect(await LifePatternService.promptBlock('cat'), isEmpty);
    });
  });
}
