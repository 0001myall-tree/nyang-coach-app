import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/overplan_nudge_service.dart';

/// 계획을 많이 잡았을 때 건네는 말.
///
/// 최근에 하나도 못 해낸 사람에게 "잘 해낸 날도 하루 0개"라고 들이대면,
/// 다시 해보려는 사람에게 못 한 날을 세어 보이는 말이 된다.
void main() {
  const coachIds = [
    'cat',
    'sec_female',
    'boyfriend',
    'halmae',
    'bro',
    'nyang_halbae',
  ];

  group('다시 시작하는 사람', () {
    test('완료가 0이면 숫자를 꺼내지 않고 응원부터 한다', () {
      for (final coachId in coachIds) {
        final message = OverplanNudgeService.primaryMessage(
          coachId,
          0,
          tone: OverplanTone.restart,
        );
        expect(message.contains('0개'), isFalse, reason: '$coachId: $message');
        expect(message.contains('회피'), isFalse, reason: '$coachId: $message');
      }
    });

    test('해낸 날이 있으면 평소보다 많다고 짚는다', () {
      final message = OverplanNudgeService.primaryMessage(
        'cat',
        3,
        tone: OverplanTone.direct,
      );
      expect(message.contains('3개'), isTrue);
    });
  });

  group('말투 번갈아 내기', () {
    test('완료가 0이면 언제나 응원', () {
      expect(OverplanNudgeService.nextTone(0, null), OverplanTone.restart);
      expect(
        OverplanNudgeService.nextTone(0, OverplanTone.gentle.name),
        OverplanTone.restart,
      );
    });

    test('처음에는 부드럽게', () {
      expect(OverplanNudgeService.nextTone(3, null), OverplanTone.gentle);
    });

    test('부드럽게 말한 다음에야 짚는다', () {
      expect(
        OverplanNudgeService.nextTone(3, OverplanTone.gentle.name),
        OverplanTone.direct,
      );
    });

    test('짚은 다음에는 다시 부드럽게 - 회피 이야기는 되풀이하지 않는다', () {
      expect(
        OverplanNudgeService.nextTone(3, OverplanTone.direct.name),
        OverplanTone.gentle,
      );
    });
  });

  group('부드러운 문구', () {
    test('회피 이야기를 꺼내지 않는다', () {
      for (final coachId in coachIds) {
        final message = OverplanNudgeService.primaryMessage(
          coachId,
          3,
          tone: OverplanTone.gentle,
        );
        expect(message.contains('회피'), isFalse, reason: '$coachId: $message');
        expect(message.contains('3개'), isFalse, reason: '$coachId: $message');
      }
    });
  });

  group('쿨다운', () {
    String dateOf(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    test('짚은 적이 없으면 막지 않는다', () {
      expect(OverplanNudgeService.withinCooldown(null), isFalse);
      expect(OverplanNudgeService.withinCooldown(''), isFalse);
    });

    test('오늘과 이튿날은 막는다', () {
      final now = DateTime.now();
      expect(OverplanNudgeService.withinCooldown(dateOf(now)), isTrue);
      expect(
        OverplanNudgeService.withinCooldown(
          dateOf(now.subtract(const Duration(days: 2))),
        ),
        isTrue,
      );
    });

    test('사흘이 지나면 다시 짚을 수 있다', () {
      final past = DateTime.now().subtract(const Duration(days: 3));
      expect(OverplanNudgeService.withinCooldown(dateOf(past)), isFalse);
    });

    test('예전 형식으로 적힌 값은 막지 않는다', () {
      expect(OverplanNudgeService.withinCooldown('2026-9-3'), isFalse);
    });
  });

  group('알아서 할게', () {
    String dateOf(DateTime date) =>
        '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

    test('고른 적이 없으면 막지 않는다', () {
      expect(OverplanNudgeService.isSnoozed(null), isFalse);
      expect(OverplanNudgeService.isSnoozed(''), isFalse);
    });

    test('일주일 동안 막는다', () {
      final now = DateTime.now();
      expect(
        OverplanNudgeService.isSnoozed(dateOf(now.add(const Duration(days: 6)))),
        isTrue,
      );
    });

    test('그날이 되면 다시 짚을 수 있다', () {
      expect(OverplanNudgeService.isSnoozed(dateOf(DateTime.now())), isFalse);
    });
  });

  group('짚을 평소가 있는지', () {
    String recordOf(DateTime date) =>
        '[{"date":"${date.toIso8601String()}","tasks":[]}]';

    test('최근 기록이 아예 없으면 짚을 것이 없다', () {
      expect(OverplanNudgeService.hasRecentRecord(null), isFalse);
      expect(OverplanNudgeService.hasRecentRecord('[]'), isFalse);
      expect(OverplanNudgeService.hasRecentRecord('망가진 값'), isFalse);
    });

    test('오늘 기록만 있는 것도 평소가 아니다', () {
      expect(
        OverplanNudgeService.hasRecentRecord(recordOf(DateTime.now())),
        isFalse,
      );
    });

    test('이레 안에 하루라도 있으면 평소가 있다', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(OverplanNudgeService.hasRecentRecord(recordOf(yesterday)), isTrue);
    });

    test('이레보다 오래된 기록은 세지 않는다', () {
      final longAgo = DateTime.now().subtract(const Duration(days: 30));
      expect(OverplanNudgeService.hasRecentRecord(recordOf(longAgo)), isFalse);
    });
  });
}
