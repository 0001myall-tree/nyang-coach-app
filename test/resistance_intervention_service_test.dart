import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/resistance_intervention_service.dart';

void main() {
  test('거부하면 같은 방식이 다시 나오지 않는다', () {
    // "커서 봐" → "싫어" → 또 "커서 봐"가 반복되던 게 이 로직을 만든 이유다.
    final offered = <String>[];
    final first = ResistanceInterventionService.nextIntervention(
      offered,
      isMaster: true,
    )!;
    offered.add(first.id);

    final second = ResistanceInterventionService.nextIntervention(
      offered,
      isMaster: true,
    )!;
    expect(second.id, isNot(first.id));
    offered.add(second.id);

    final third = ResistanceInterventionService.nextIntervention(
      offered,
      isMaster: true,
    )!;
    expect(third.id, isNot(first.id));
    expect(third.id, isNot(second.id));
  });

  test('한 대화에서 모든 방식을 한 번씩만 꺼낸다', () {
    final offered = <String>[];
    final seen = <String>[];
    while (true) {
      final next = ResistanceInterventionService.nextIntervention(
        offered,
        isMaster: true,
      );
      if (next == null) break;
      seen.add(next.id);
      offered.add(next.id);
    }
    expect(seen.length, ResistanceInterventionService.interventions.length);
    expect(seen.toSet().length, seen.length, reason: '중복 없이 나와야 한다');
  });

  test('다 쓰면 더 밀지 않고 닫는다', () {
    final allIds = ResistanceInterventionService.interventions
        .map((i) => i.id)
        .toList();
    expect(
      ResistanceInterventionService.nextIntervention(allIds, isMaster: true),
      isNull,
    );
    expect(ResistanceInterventionService.exhaustedRule, contains('다시 밀지 마세요'));
  });

  group('코치가 못 쓰는 기능은 안내하지 않는다', () {
    // 빠른 실행은 마스터 코치 화면에만 있다. 프렌즈 코치가 이걸 권하면
    // 사용자는 있지도 않은 버튼을 찾게 된다.
    test('프렌즈에게는 마스터 전용 개입이 나오지 않는다', () {
      final offered = <String>[];
      while (true) {
        final next = ResistanceInterventionService.nextIntervention(
          offered,
          isMaster: false,
        );
        if (next == null) break;
        expect(next.masterOnly, isFalse, reason: next.id);
        offered.add(next.id);
      }
      expect(offered, isNot(contains('start_signal')));
    });

    test('마스터에게는 나온다', () {
      final offered = ResistanceInterventionService.interventions
          .where((i) => i.id != 'start_signal')
          .map((i) => i.id)
          .toList();
      final next = ResistanceInterventionService.nextIntervention(
        offered,
        isMaster: true,
      );
      expect(next?.id, 'start_signal');
    });

    test('시작 신호는 묻기 전에 띄우지 않는다', () {
      final signal = ResistanceInterventionService.byId('start_signal')!;
      expect(signal.rule, contains('한 번만 물으세요'));
      expect(signal.rule, contains('묻기도 전에 먼저 붙이지 마세요'));
    });
  });

  group('거절당한 턴', () {
    test('규칙은 두 줄로 유지한다', () {
      // 새 방식이 나가는 자리다. "거절당한 걸 변호하지 마라"까지 적을 필요가
      // 없다 — 같은 종류를 다시 꺼내지 말라는 첫 줄이 이미 그걸 막는다.
      // 새 제안에 이유를 붙이는 건 개입 머리말 규칙이 맡는다.
      final lines = ResistanceInterventionService.refusedPrefix.trim().split(
        '\n',
      );
      expect(lines.length, 2);
    });

    test('같은 종류를 다시 꺼내지 않는다', () {
      expect(
        ResistanceInterventionService.refusedPrefix,
        contains('같은 종류의 제안을 다시 하지 마세요'),
      );
    });
  });

  test('거부 표현 판정', () {
    for (final t in [
      '그것도 싫어',
      '안 할래',
      '별로야',
      '그건 좀',
      '다른 거 없어?',
      '내키지 않아',
      '지금은 안 할래',
    ]) {
      expect(ResistanceInterventionService.isRefusal(t), isTrue, reason: t);
    }
    for (final t in ['응 했어', '좋아 해볼게', '그렇게 할게']) {
      expect(ResistanceInterventionService.isRefusal(t), isFalse, reason: t);
    }
  });

  group('대화를 넘어가면 시작 자리가 밀린다', () {
    // 새 대화마다 목록 맨 위('시간 낮추기' = 5분)로 돌아가던 게 이 로테이션을
    // 만든 이유다. 매번 같은 말로 시작하면 금방 질린다.
    test('마지막에 꺼낸 것 다음부터 시작한다', () {
      final all = ResistanceInterventionService.interventions;
      for (var i = 0; i < all.length; i++) {
        final next = ResistanceInterventionService.nextIntervention(
          const [],
          isMaster: true,
          startAfterId: all[i].id,
        );
        expect(next?.id, all[(i + 1) % all.length].id, reason: all[i].id);
      }
    });

    test('한 바퀴 돌면 처음으로 돌아온다', () {
      final all = ResistanceInterventionService.interventions;
      var cursor = all.first.id;
      final seen = <String>[];
      // 대화 하나에 개입 하나씩, 목록 길이만큼 새 대화를 연다.
      for (var i = 0; i < all.length; i++) {
        final next = ResistanceInterventionService.nextIntervention(
          const [],
          isMaster: true,
          startAfterId: cursor,
        )!;
        seen.add(next.id);
        cursor = next.id;
      }
      expect(seen.toSet().length, all.length, reason: '한 바퀴 안에 중복이 없어야 한다');
      expect(seen.last, all.first.id, reason: '끝에 닿으면 위로 돌아온다');
    });

    test('시작 자리가 목록에 없으면 맨 위부터', () {
      // 개입을 지우면 저장돼 있던 id가 목록에 없는 값이 된다.
      final next = ResistanceInterventionService.nextIntervention(
        const [],
        isMaster: true,
        startAfterId: 'removed_long_ago',
      );
      expect(next?.id, ResistanceInterventionService.interventions.first.id);
    });

    test('중간에서 시작해도 한 대화에서 모든 방식을 한 번씩 꺼낸다', () {
      final offered = <String>[];
      while (true) {
        final next = ResistanceInterventionService.nextIntervention(
          offered,
          isMaster: true,
          startAfterId: 'connect_purpose',
        );
        if (next == null) break;
        offered.add(next.id);
      }
      expect(offered.length, ResistanceInterventionService.interventions.length);
      expect(offered.toSet().length, offered.length);
    });

    test('프렌즈는 마스터 전용 자리에서 시작해도 그걸 건너뛴다', () {
      final next = ResistanceInterventionService.nextIntervention(
        const [],
        isMaster: false,
        startAfterId: 'reorder',
      );
      expect(next?.id, isNot('start_signal'));
      expect(next?.masterOnly, isFalse);
    });
  });

  test('어느 개입도 앞이 막혔다는 걸 전제로 말하지 않는다', () {
    // 로테이션은 아무거나 첫 마디로 꺼낸다. "앞의 방식들이 안 먹혔습니다"가
    // 들어 있으면 아무것도 제안하지 않은 대화의 첫 줄에서 거짓말이 된다.
    for (final intervention in ResistanceInterventionService.interventions) {
      expect(intervention.rule, isNot(contains('연달아')), reason: intervention.id);
      expect(
        intervention.rule,
        isNot(contains('앞의 방식')),
        reason: intervention.id,
      );
    }
  });

  test('id는 서로 겹치지 않고 지시문은 비어 있지 않다', () {
    final ids = ResistanceInterventionService.interventions
        .map((i) => i.id)
        .toList();
    expect(ids.toSet().length, ids.length);
    for (final intervention in ResistanceInterventionService.interventions) {
      expect(intervention.rule.trim(), isNotEmpty, reason: intervention.id);
      // 어느 방식인지 첫 줄에 이름이 박혀 있어야 한다. "다른 방식 섞지 마라"는
      // 프롬프트 머리말이 한 번만 말하고, 개입마다 반복하지 않는다.
      expect(
        intervention.rule,
        startsWith('[${intervention.label}]'),
        reason: intervention.id,
      );
    }
  });

  test('상상 훈련은 잘하는 모습이 아니라 하고 있는 모습이다', () {
    final imagine = ResistanceInterventionService.byId('imagine_doing')!;
    expect(imagine.rule, contains('이미 하고 있는 모습'));
    expect(imagine.rule, contains('결과가 좋은 장면은 그리게 하지 마세요'));
  });
}
