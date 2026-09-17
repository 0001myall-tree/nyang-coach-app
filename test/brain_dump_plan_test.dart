import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/brain_dump_plan.dart';

/// 쏟아낸 말을 코치가 계획으로 바꿔 보낸 것을 앱이 읽는 자리.
///
/// 형식만 답하라고 해도 앞뒤에 한마디를 붙여 오는 일이 있고, 칸을 비워 보내는
/// 일도 있다. 읽다 실패하면 사용자는 "다 말해봐" 해놓고 아무 답도 못 받는다.
void main() {
  test('두 가지 안을 읽는다', () {
    final plan = BrainDumpPlanner.parse('''
{"known":[],
"options":[
 {"label":"급한 것부터","why":"걸리는 걸 먼저 털면 가벼워진다","today":["거래처 전화","투고 준비"]},
 {"label":"만만한 것부터","why":"가벼운 걸로 시동을 건다","today":["투고 준비","거래처 전화"]}],
"batch":{"minutes":20,"names":["병원 예약","세금 정리"]},
"later":["책장 정리"],"drop":"블로그 글감 정리"}
''');

    expect(plan, isNotNull);
    expect(plan!.options.length, 2);
    expect(plan.options.first.today, ['거래처 전화', '투고 준비']);
    expect(plan.batchMinutes, 20);
    expect(plan.later, ['책장 정리']);
    expect(plan.drop, '블로그 글감 정리');
  });

  test('앞뒤에 말이 붙어 와도 읽는다', () {
    final plan = BrainDumpPlanner.parse(
      '정리했다냥.\n{"options":[{"label":"","why":"","today":["청소"]}]}\n이렇게 해보자냥',
    );
    expect(plan, isNotNull);
    expect(plan!.options.single.today, ['청소']);
  });

  test('이미 있는 것을 읽는다', () {
    final plan = BrainDumpPlanner.parse('''
{"known":[
 {"name":"영어 공부","kind":"done","note":"아침 8시에"},
 {"name":"투고 준비","kind":"started","note":"30분 했음"}],
"options":[{"label":"","why":"","today":["청소"]}]}
''');
    expect(plan!.known.length, 2);
    expect(plan.known.first.kind, 'done');
    expect(plan.known.first.note, '아침 8시에');
  });

  group('쓸 수 없는 답', () {
    test('안이 없으면 null', () {
      expect(BrainDumpPlanner.parse('{"options":[],"later":["청소"]}'), isNull);
    });

    test('오늘 할 것이 빈 안은 버린다', () {
      final plan = BrainDumpPlanner.parse(
        '{"options":[{"label":"A","why":"","today":[]},'
        '{"label":"B","why":"","today":["청소"]}]}',
      );
      expect(plan!.options.length, 1);
      expect(plan.options.single.label, 'B');
    });

    test('JSON이 아니면 null', () {
      expect(BrainDumpPlanner.parse('오늘은 청소부터 해보자냥'), isNull);
    });

    test('빈 답이면 null', () {
      expect(BrainDumpPlanner.parse(''), isNull);
    });
  });

  group('묶음', () {
    test('이름이 없으면 시간도 버린다', () {
      // "30분 잡고 몰아서 해라"인데 무엇을 몰아서 할지가 없으면 할 말이 안 된다.
      final plan = BrainDumpPlanner.parse(
        '{"options":[{"label":"","why":"","today":["청소"]}],'
        '"batch":{"minutes":30,"names":[]}}',
      );
      expect(plan!.batchMinutes, isNull);
      expect(plan.batch, isEmpty);
    });

    test('시간이 0이면 묶음으로 치지 않는다', () {
      final plan = BrainDumpPlanner.parse(
        '{"options":[{"label":"","why":"","today":["청소"]}],'
        '"batch":{"minutes":0,"names":["전화","메일"]}}',
      );
      expect(plan!.batchMinutes, isNull);
    });
  });

  test('고른 안에 묶음까지 더해 오늘 목록이 된다', () {
    final plan = BrainDumpPlanner.parse(
      '{"options":[{"label":"","why":"","today":["거래처 전화"]}],'
      '"batch":{"minutes":20,"names":["병원 예약","세금 정리"]}}',
    )!;
    expect(plan.todayNamesOf(plan.options.single), [
      '거래처 전화',
      '병원 예약',
      '세금 정리',
    ]);
  });
}
