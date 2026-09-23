import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/overplan_nudge_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 평소 해내던 것보다 계획이 훨씬 많은 날, 인사 자리에서 건네는 말.
///
/// 예전에는 할 일을 적는 중에 다이얼로그로 끼어들었다. 적는 순간은 의욕이
/// 올라와 있어서 무슨 말을 해도 안 들리고, 정작 그 목록을 마주하는 것은 다음
/// 날 아침이다. 게다가 "적지 마라"는 말은 머릿속을 비우는 일 자체를 막는다 -
/// 다 쏟아내는 것은 오히려 부하를 더는 쪽이다.
///
/// 그래서 적는 것은 놔두고, 마주하는 자리에서 어떻게 다룰지를 같이 본다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 기록을 만드는 기준과 판정에 넘기는 기준을 같은 날로 둔다. 예전에는
  // 기록만 진짜 오늘을 썼는데, 자정을 넘기면 하루가 어긋나 테스트가 깨졌다.
  final base = DateTime(2026, 9, 17, 9);

  String key(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';

  /// 며칠 전 하루 기록. [done]개를 해낸 날.
  Map<String, dynamic> day(int daysAgo, int done) {
    final date = base.subtract(Duration(days: daysAgo));
    return {
      'date': key(date),
      'totalCount': done + 2,
      'doneCount': done,
      'tasks': [
        for (var i = 0; i < done; i++) {'text': '해낸 일 $i', 'done': true},
        {'text': '못 한 일', 'done': false},
      ],
    };
  }

  String history(List<Map<String, dynamic>> days) => jsonEncode(days);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('말할 코치', () {
    test('냥냥이와 마스터만 말한다', () {
      expect(OverplanNudgeService.speaks('cat'), isTrue);
      expect(OverplanNudgeService.speaks('nyang_halbae'), isTrue);
      expect(OverplanNudgeService.speaks('sec_female'), isTrue);
    });

    test('프렌즈 코치는 말하지 않는다', () {
      // 뒤에 API 코칭이 이어지는 자리라, 첫 줄만 나가면 "그래서 뭐?"가 된다.
      expect(OverplanNudgeService.speaks('boyfriend'), isFalse);
      expect(OverplanNudgeService.speaks('halmae'), isFalse);
      expect(OverplanNudgeService.speaks('bro'), isFalse);
    });
  });

  group('조건', () {
    test('평소 최대보다 5개 이상 많으면 나간다', () async {
      final raw = history([day(1, 2), day(2, 1)]);
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 7,
          historyRaw: raw,
          now: base,
        ),
        2,
      );
    });

    test('4개 많은 정도로는 안 나간다', () async {
      // 조금 많은 날까지 짚으면 잔소리가 된다.
      final raw = history([day(1, 2), day(2, 1)]);
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 6,
          historyRaw: raw,
          now: base,
        ),
        isNull,
      );
    });

    test('평소가 없으면 나가지 않는다', () async {
      // 이제 막 쓰기 시작한 사람에게는 "평소보다 많다"고 할 평소가 없다.
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 20,
          historyRaw: null,
          now: base,
        ),
        isNull,
      );
    });
  });

  group('시간', () {
    test('7시 전에는 안 나간다', () async {
      final raw = history([day(1, 2)]);
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: base.subtract(const Duration(hours: 3)),
        ),
        isNull,
      );
    });

    test('19시부터는 안 나간다', () async {
      // 오늘을 어떻게 다룰지 이야기라, 하루가 남아 있어야 뜻이 있다.
      final raw = history([day(1, 2)]);
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: base.add(const Duration(hours: 10)),
        ),
        isNull,
      );
    });

    test('낮에는 나간다', () async {
      final raw = history([day(1, 2)]);
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: base.add(const Duration(hours: 5)),
        ),
        isNotNull,
      );
    });
  });

  group('쿨다운', () {
    test('하루에 두 번은 하지 않는다', () async {
      final raw = history([day(1, 2)]);
      final now = base;
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: now,
        ),
        isNotNull,
      );
      await OverplanNudgeService.recordGreeted(now: now);

      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: now.add(const Duration(hours: 5)),
        ),
        isNull,
      );
    });

    test('한 번 말하면 닷새 쉰다', () async {
      // 계획 여덟아홉에 완료 하나둘인 사람은 열흘 내내 조건에 걸린다.
      // 매일 말을 걸면 도움이 아니라 소음이 된다.
      final raw = history([day(1, 2)]);
      final now = base;
      await OverplanNudgeService.recordGreeted(now: now);

      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: now.add(const Duration(days: 4)),
        ),
        isNull,
      );
      expect(
        await OverplanNudgeService.shouldGreet(
          plannedCount: 9,
          historyRaw: raw,
          now: now.add(const Duration(days: 5)),
        ),
        isNotNull,
      );
    });

    test('읽을 수 없는 날짜가 적혀 있으면 막지 않는다', () {
      // 한 번 더 나가는 편이, 영영 안 나가는 것보다 낫다.
      expect(OverplanNudgeService.withinCooldown('예전 형식', base), isFalse);
    });
  });

  group('첫 줄', () {
    test('코치마다 말투가 다르다', () {
      expect(OverplanNudgeService.opening('cat'), contains('냥'));
      expect(OverplanNudgeService.opening('nyang_halbae'), contains('얘야'));
      expect(OverplanNudgeService.opening('sec_female'), contains('대표님'));
    });

    test('숫자를 들이대지 않는다', () {
      // 낮은 숫자를 맨 앞에 두면 그날 한 일이 전부 지워진다. 숫자는 코치에게만
      // 넘기고, 사용자에게 보이는 첫 줄은 상태를 짚는 데까지만 간다.
      for (final id in ['cat', 'nyang_halbae', 'sec_female']) {
        expect(
          OverplanNudgeService.opening(id),
          isNot(matches(RegExp(r'\d'))),
          reason: '$id의 첫 줄에 숫자가 있다',
        );
      }
    });

    test('기다리라는 말로 끝난다', () {
      // 고정 문구는 바로 뜨고 코치의 말은 몇 초 뒤에 온다. 그 사이를 그냥 두면
      // 끊긴 것처럼 보인다.
      for (final id in ['cat', 'nyang_halbae', 'sec_female']) {
        expect(OverplanNudgeService.opening(id), contains('기다'));
      }
    });
  });

  group('못 지었을 때', () {
    test('코치마다 대신 나갈 줄이 있다', () {
      // "기다려 봐" 해놓고 아무것도 안 오는 것이 제일 나쁘다.
      for (final id in ['cat', 'nyang_halbae', 'sec_female']) {
        expect(OverplanNudgeService.fallback(id), isNotEmpty);
      }
    });
  });
}
