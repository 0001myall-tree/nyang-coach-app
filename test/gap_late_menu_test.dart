import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/gap_late_menu.dart';

/// 하루가 얼마 안 남았을 때 건네는 한 수.
///
/// 이른 시각에는 "앞 15분을 지금 해두자"가 통하지만 늦은 시각에는 안 통한다 —
/// 이따 할 시간이 없는데 미리 해두라는 말이 된다.
void main() {
  group('언제부터 늦은 쪽인가', () {
    test('취침을 안 정해뒀으면 19시부터', () {
      expect(GapLateMenu.isLate(DateTime(2026, 9, 9, 18, 59)), isFalse);
      expect(GapLateMenu.isLate(DateTime(2026, 9, 9, 19)), isTrue);
      expect(GapLateMenu.isLate(DateTime(2026, 9, 9, 22)), isTrue);
    });

    test('취침을 정해뒀으면 네 시간 전부터', () {
      // 23시에 자는 사람은 19시부터. 안 정해둔 사람과 같은 자리에서 갈린다.
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 18, 59), bedtime: '23:00'),
        isFalse,
      );
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 19), bedtime: '23:00'),
        isTrue,
      );
    });

    test('늦게 자는 사람에게는 저녁이 아직 이르다', () {
      // 새벽 1시에 자는 사람에게 저녁 9시는 네 시간이 남은 시각이다.
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 20), bedtime: '01:00'),
        isFalse,
      );
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 21, 30), bedtime: '01:00'),
        isTrue,
      );
    });

    test('일찍 자는 사람에게는 오후가 이미 늦다', () {
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 18), bedtime: '21:00'),
        isTrue,
      );
    });

    test('읽을 수 없는 취침 시각은 없는 것으로 본다', () {
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 15), bedtime: '언젠가'),
        isFalse,
      );
      expect(
        GapLateMenu.isLate(DateTime(2026, 9, 9, 20), bedtime: '25:00'),
        isTrue,
      );
    });
  });

  group('무엇을 건네나', () {
    test('하고 있는 사람에게는 아무 말도 안 한다', () {
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't1', 'text': '분기 리포트', 'inProgress': true},
        ],
        coreTasks: const [],
      );
      expect(suggestion, isNull);
    });

    test('하다 멈춘 일이 제일 먼저다', () {
      // 오늘 가장 가까이 갔던 일이라 다시 붙는 문턱이 제일 낮다.
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't1', 'text': '방 정리'},
          {'id': 't2', 'text': '분기 리포트', 'elapsedSeconds': 720},
        ],
        coreTasks: const [],
      );

      expect(suggestion!.body, contains('분기 리포트'));
      expect(suggestion.body, contains('12분'));
      expect(suggestion.taskId, 't2');
    });

    test('얼마나 했는지 모르면 시간을 말하지 않는다', () {
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't2', 'text': '분기 리포트', 'elapsedSeconds': 30},
        ],
        coreTasks: const [],
      );

      expect(suggestion!.body, contains('분기 리포트'));
      expect(suggestion.body, contains('하다 멈췄다냥'));
      expect(suggestion.body.contains('0분'), isFalse);
    });

    test('멈춘 게 없고 핵심도 안 정했으면 핵심을 짚자고 한다', () {
      // 핵심은 알림이 붙어 오늘 완료율에 제일 곧게 닿는다.
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't1', 'text': '방 정리'},
        ],
        coreTasks: const [],
      );

      expect(suggestion!.body, contains('핵심'));
      expect(suggestion.taskId, isNull);
    });

    test('핵심을 이미 정했으면 하나 고르자고 한다', () {
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't1', 'text': '방 정리'},
        ],
        coreTasks: const [
          {'id': 't1', 'text': '방 정리'},
        ],
      );

      expect(suggestion!.body, contains('하나만'));
      expect(suggestion.body.contains('핵심'), isFalse);
    });

    test('오늘 건질 게 없으면 내일 것을 정하자고 한다', () {
      // 이 시각에 "오늘 뭘 할지 정하자"는 늦었다.
      final suggestion = GapLateMenu.suggest(
        tasks: const [],
        coreTasks: const [],
      );

      expect(suggestion!.body, contains('내일'));
    });

    test('건네는 말은 전부 폰으로 되는 일이다', () {
      // 틈새 코칭은 사용자가 지금 어디 있는지 모른다. "루틴 지금 해라"는
      // 헬스장에 있어야 하는 사람에게 무리다.
      final bodies = [
        for (final pair in [
          (const <Map>[], const <Map>[]),
          (
            const [
              {'id': 't1', 'text': '방 정리'},
            ],
            const <Map>[],
          ),
          (
            const [
              {'id': 't1', 'text': '방 정리'},
            ],
            const [
              {'id': 't1', 'text': '방 정리'},
            ],
          ),
        ])
          GapLateMenu.suggest(tasks: pair.$1, coreTasks: pair.$2)!.body,
      ];

      for (final body in bodies) {
        expect(body, startsWith('집사'));
        expect(body.contains('\n'), isFalse);
      }
    });

    test('이름이 길면 줄여서 넣는다', () {
      final suggestion = GapLateMenu.suggest(
        tasks: const [
          {'id': 't1', 'text': '분기 리포트 초안 정리해서 팀에 공유하기', 'elapsedSeconds': 600},
        ],
        coreTasks: const [],
      );

      expect(suggestion!.body, contains('…'));
    });
  });
}
