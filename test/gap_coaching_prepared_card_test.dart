import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/gap_coaching_service.dart';

/// 안드로이드 카드에 쓸 문장을 Dart가 미리 만들어 둔다.
///
/// 원래는 카드가 뜨는 순간에 코틀린이 목록을 읽어 직접 만들었다. 앱이 꺼져
/// 있어도 돌아야 해서 그랬는데, 그러면 어떤 일에 어떤 말을 할지가 두 벌 있게
/// 된다 — 한쪽만 고치면 안드로이드와 아이폰이 다른 말을 한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 시계를 못 바꾸므로 시각을 넘겨서 잡는다. 안 그러면 테스트를 저녁에 돌릴 때
  // 늦은 쪽으로 갈려서 앞엣것들이 통째로 깨진다.
  final morning = DateTime(2026, 9, 9, 10);
  final evening = DateTime(2026, 9, 9, 21);

  Future<Map<String, dynamic>> cardFor(List<Map<String, dynamic>> tasks) async {
    SharedPreferences.setMockInitialValues({'nyang_tasks': jsonEncode(tasks)});
    final prefs = await SharedPreferences.getInstance();
    await GapCoachingService.prepareCard(prefs, at: morning);
    return jsonDecode(prefs.getString(GapCoachingService.preparedCardKey)!)
        as Map<String, dynamic>;
  }

  // 아래 테스트들은 파이어베이스가 없는 환경에서 돈다. 조각 요청은 실패하고
  // 사전으로 떨어지므로, 여기서 보는 것은 "무엇을 고르고 어떻게 적어두는가"다.
  // 조각을 받아왔을 때의 문장은 gap_fragment_check_test.dart에서 본다.

  test('고른 일의 이름과 id를 함께 적어둔다', () async {
    // id가 있어야 코틀린이 "그 일이 아직 남아 있나"를 확인할 수 있다.
    final card = await cardFor([
      {'id': 't1', 'text': '분기 리포트'},
    ]);

    expect(card['body'], contains('분기 리포트'));
    expect(card['taskId'], 't1');
    expect(card['button'], GapCoachingService.buttonDefault);
  });

  test('숫자 id도 글자로 적어둔다', () async {
    // 저장소에는 숫자로 들어가는데 코틀린은 글자로 비교한다.
    final card = await cardFor([
      {'id': 1787698863208, 'text': '분기 리포트'},
    ]);

    expect(card['taskId'], '1787698863208');
  });

  test('아무것도 안 적었으면 하나 정하자고 하고 버튼도 그쪽을 가리킨다', () async {
    final card = await cardFor(const []);

    expect(card['body'], GapCoachingService.emptyBody);
    expect(card['button'], GapCoachingService.buttonPlan);
    expect(card.containsKey('taskId'), isFalse);
  });

  test('남은 일은 있는데 부를 이름이 없으면 이름 없이 말한다', () async {
    // 약속은 시각에 가서 하는 것이라 앞당길 자리가 없어 후보에서 빠진다.
    final card = await cardFor([
      {'id': 's1', 'text': '치과 예약', 'category': 'schedule'},
    ]);

    expect(card['body'], GapCoachingService.fallbackBody);
    expect(card['button'], GapCoachingService.buttonDefault);
    expect(card.containsKey('taskId'), isFalse);
  });

  test('손댄 일은 부르지 않는다', () async {
    // 이미 시작한 일에 "미리 해두라"고 할 수는 없다.
    final card = await cardFor([
      {'id': 't1', 'text': '분기 리포트', 'inProgress': true},
      {'id': 't2', 'text': '방 정리', 'elapsedSeconds': 300},
    ]);

    expect(card['body'], GapCoachingService.fallbackBody);
    expect(card.containsKey('taskId'), isFalse);
  });

  test('머리로 하는 일을 먼저 부른다', () async {
    // 15분을 앞당겨 가장 크게 달라지는 쪽이다.
    final card = await cardFor([
      {'id': 't1', 'text': '방 청소'},
      {'id': 't2', 'text': '기획안'},
    ]);

    expect(card['taskId'], 't2');
    expect(card['body'], contains('콘셉트'));
  });

  test('조각을 못 받아오면 사전으로 떨어지고, 그건 아이폰과 같은 문장이다', () async {
    // 테스트에는 파이어베이스가 없어서 조각 요청이 실패한다. 그 길로 떨어졌을
    // 때 나오는 문장이 아이폰이 쓰는 것과 같아야 한다 — 두 폰이 다른 말을
    // 하면 안 된다.
    final tasks = [
      {'id': 't1', 'text': '분기 리포트'},
    ];
    SharedPreferences.setMockInitialValues({'nyang_tasks': jsonEncode(tasks)});
    final prefs = await SharedPreferences.getInstance();
    await GapCoachingService.prepareCard(prefs, at: morning);
    final stored =
        jsonDecode(prefs.getString(GapCoachingService.preparedCardKey)!)
            as Map<String, dynamic>;

    expect(stored['body'], GapCoachingService.bodyFor(tasks, DateTime.now()));
  });

  group('하루에 물어보는 횟수', () {
    // 부를 일이 바뀌면 조각도 다시 받아야 하는데, 그 판단이 앱 열 때마다
    // 돈다. 정작 카드는 하루 두 번까지만 뜨므로 그보다 많이 물어본 몫은
    // 뜨지도 않을 문구를 만든 것이다.
    //
    // (테스트에는 파이어베이스가 없어 요청 자체는 실패한다. 여기서 보는 것은
    // 몇 번 시도하고 어디서 멈추는가다.)
    final now = DateTime(2026, 9, 9, 10);

    Future<SharedPreferences> askFor(List<String> names) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      for (final name in names) {
        await prefs.setString(
          'nyang_tasks',
          jsonEncode([
            {'id': name, 'text': name},
          ]),
        );
        await GapCoachingService.prepareCard(prefs, at: now);
      }
      return prefs;
    }

    test('같은 일이면 한 번만 물어본다', () async {
      final prefs = await askFor(['분기 리포트', '분기 리포트', '분기 리포트']);
      expect(GapCoachingService.fragmentAsksToday(prefs, now), 1);
    });

    test('부를 일이 바뀌면 다시 물어본다', () async {
      // 끝낸 일 이름을 계속 부를 수는 없다.
      final prefs = await askFor(['분기 리포트', '레퍼런스 정리']);
      expect(GapCoachingService.fragmentAsksToday(prefs, now), 2);
    });

    test('하루 상한에서 멈춘다', () async {
      final prefs = await askFor(['하나', '둘', '셋', '넷', '다섯']);
      expect(
        GapCoachingService.fragmentAsksToday(prefs, now),
        GapCoachingService.maxFragmentAsksPerDay,
      );
    });

    test('상한에 걸려도 문구는 나간다', () async {
      // 조각을 못 받으면 사전으로 떨어질 뿐, 카드가 비지는 않는다.
      final prefs = await askFor(['하나', '둘', '셋', '넷', '다섯']);
      final card =
          jsonDecode(prefs.getString(GapCoachingService.preparedCardKey)!)
              as Map<String, dynamic>;
      expect(card['body'].toString(), isNotEmpty);
    });
  });

  group('늦은 시각', () {
    // 이따 할 시간이 없는데 미리 해두라는 말은 이상하다. 그때는 오늘 남은 것을
    // 건지는 쪽으로 간다.
    Future<Map<String, dynamic>> lateCardFor(
      List<Map<String, dynamic>> tasks, {
      List<Map<String, dynamic>> core = const [],
    }) async {
      SharedPreferences.setMockInitialValues({
        'nyang_tasks': jsonEncode(tasks),
        'nyang_core_tasks': jsonEncode(core),
      });
      final prefs = await SharedPreferences.getInstance();
      await GapCoachingService.prepareCard(prefs, at: evening);
      return jsonDecode(prefs.getString(GapCoachingService.preparedCardKey)!)
          as Map<String, dynamic>;
    }

    test('앞당기자는 말 대신 건지는 말이 나간다', () async {
      final card = await lateCardFor([
        {'id': 't1', 'text': '분기 리포트'},
      ]);

      expect(card['body'], contains('핵심'));
      expect(card['body'].toString().contains('15분'), isFalse);
      expect(card['body'].toString().contains('미리'), isFalse);
    });

    test('멈춘 일을 부르면 그 일 id도 적어둔다', () async {
      // 그새 다시 시작했으면 다른 말이 나가야 한다.
      final card = await lateCardFor([
        {'id': 't2', 'text': '분기 리포트', 'elapsedSeconds': 720},
      ]);

      expect(card['body'], contains('분기 리포트'));
      expect(card['taskId'], 't2');
    });
  });

  test('클라우드가 덮지 못하는 자리에 적는다', () {
    // 이 기기에서 방금 만든 값이라, 다른 기기 문장이 내려오면 안 된다.
    expect(GapCoachingService.preparedCardKey.startsWith('nyang_'), isFalse);
  });
}
