import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/preemptive_nudge_service.dart';

Map<String, dynamic> task(
  String text, {
  bool done = false,
  bool inProgress = false,
  String? inProgressAt,
  int elapsedSeconds = 0,
  int deferredCount = 0,
  String category = 'today',
  String? habitId,
}) {
  return {
    'text': text,
    'done': done,
    'inProgress': inProgress,
    if (inProgressAt != null) 'inProgressAt': inProgressAt,
    if (elapsedSeconds > 0) 'elapsedSeconds': elapsedSeconds,
    if (deferredCount > 0) 'deferredCount': deferredCount,
    'category': category,
    if (habitId != null) 'habitId': habitId,
  };
}

Map<String, dynamic> day(String date, List<String> texts) => {
  'date': date,
  'tasks': texts.map((t) => {'text': t, 'category': 'today'}).toList(),
};

PreemptiveNudge? decide({
  List<dynamic> todayTasks = const [],
  List<dynamic> coreTasks = const [],
  List<dynamic> history = const [],
}) {
  return PreemptiveNudgeService.decide(
    todayTasks: todayTasks,
    coreTasks: coreTasks,
    history: history,
  );
}

void main() {
  group('이미 움직이는 사람은 부르지 않는다', () {
    test('완료한 일이 있으면 조용하다', () {
      expect(decide(todayTasks: [task('청소', done: true)]), isNull);
    });

    test('시작 표시가 있으면 조용하다', () {
      expect(decide(todayTasks: [task('청소', inProgress: true)]), isNull);
    });

    test('시작 버튼을 거쳤다 멈춘 것도 움직인 것이다', () {
      expect(
        decide(todayTasks: [task('청소', inProgressAt: '2026-08-16T09:00:00')]),
        isNull,
      );
    });

    test('타이머만 돌렸어도 조용하다', () {
      expect(decide(todayTasks: [task('청소', elapsedSeconds: 300)]), isNull);
    });
  });

  group('계획이 비어 있을 때', () {
    test('아무것도 없으면 계획을 세우자고 한다', () {
      final nudge = decide();
      expect(nudge?.kind, NudgeKind.noPlan);
      expect(PreemptiveNudgeService.noPlanMessages, contains(nudge!.message));
    });

    test('시작을 거드는 말도 계획 없는 날에 쓸 수 있다', () {
      // "3분만 하자"는 계획이 없는 사람에게도 통한다. 반대로 계획을 청하는
      // 말은 계획을 세워둔 사람에게 쓰면 틀린 말이 된다.
      for (final message in PreemptiveNudgeService.notStartedMessages) {
        expect(PreemptiveNudgeService.noPlanMessages, contains(message));
      }
      for (final message in PreemptiveNudgeService.planMessages) {
        expect(
          PreemptiveNudgeService.notStartedMessages,
          isNot(contains(message)),
        );
      }
    });

    test('습관만 채워져 있는 건 계획을 세운 게 아니다', () {
      final nudge = decide(
        todayTasks: [task('물 마시기', category: 'habit', habitId: 'h1')],
      );
      expect(nudge?.kind, NudgeKind.noPlan);
    });
  });

  group('미뤄놓고 다시 올린 일', () {
    test('그 일 이름을 부르며 줄여주겠다고 한다', () {
      final nudge = decide(
        todayTasks: [task('보고서', deferredCount: 1), task('청소')],
      );
      expect(nudge?.kind, NudgeKind.deferredAgain);
      expect(nudge?.taskName, '보고서');
      expect(nudge?.message, contains('보고서'));
    });

    test('며칠째 넘어간 일에는 미는 말을 쓰지 않는다', () {
      for (var i = 0; i < 30; i++) {
        final nudge = decide(todayTasks: [task('보고서', deferredCount: 2)]);
        expect(
          PreemptiveNudgeService.longDeferredMessages.map(
            (m) => m.replaceAll('{{task}}', '보고서'),
          ),
          contains(nudge!.message),
        );
        expect(nudge.message, isNot(contains('시작해! 시작해!')));
      }
    });

    test('여러 개면 제일 오래 넘어간 것을 부른다', () {
      final nudge = decide(
        todayTasks: [
          task('청소', deferredCount: 1),
          task('보고서', deferredCount: 4),
        ],
      );
      expect(nudge?.taskName, '보고서');
    });

    test('미룬 적 없으면 이 분기가 아니다', () {
      final nudge = decide(todayTasks: [task('보고서')]);
      expect(nudge?.kind, NudgeKind.notStarted);
    });
  });

  group('일정은 있는데 시작을 못 했을 때', () {
    test('핵심으로 찍은 일을 먼저 부른다', () {
      final nudge = decide(
        todayTasks: [task('청소'), task('보고서')],
        coreTasks: [task('보고서')],
      );
      expect(nudge?.kind, NudgeKind.notStarted);
      expect(nudge?.taskName, '보고서');
    });

    test('핵심이 없으면 습관을 부른다', () {
      final nudge = decide(
        todayTasks: [
          task('청소'),
          task('스트레칭', category: 'habit', habitId: 'h1'),
        ],
      );
      expect(nudge?.taskName, '스트레칭');
    });

    test('핵심도 습관도 없으면 요즘 반복되던 일을 부른다', () {
      final nudge = decide(
        todayTasks: [task('장보기'), task('4화 쓰기')],
        history: [
          day('2026-08-10', ['1화 쓰기']),
          day('2026-08-11', ['2화 쓰기']),
          day('2026-08-12', ['3화 쓰기']),
        ],
      );
      expect(nudge?.taskName, '4화 쓰기');
    });

    test('이름을 부를 때는 자리를 채워서 내보낸다', () {
      // 문구에 {{task}} 자리가 남아 있으면 그대로 사용자에게 나간다.
      for (var i = 0; i < 30; i++) {
        final named = decide(
          todayTasks: [task('보고서')],
          coreTasks: [task('보고서')],
        );
        expect(named!.message, isNot(contains('{{task}}')));
        expect(named.message, contains('보고서'));

        final deferred = decide(todayTasks: [task('보고서', deferredCount: 1)]);
        expect(deferred!.message, isNot(contains('{{task}}')));
        expect(deferred.message, contains('보고서'));
      }
    });

    test('부를 근거가 없으면 이름 없이 부른다', () {
      final nudge = decide(todayTasks: [task('장보기')]);
      expect(nudge?.kind, NudgeKind.notStarted);
      expect(nudge?.taskName, isNull);
      expect(
        PreemptiveNudgeService.notStartedMessages,
        contains(nudge!.message),
      );
    });
  });

  group('저장했다 되읽기', () {
    test('보낸 말을 그대로 되살린다', () {
      final nudge = decide(todayTasks: [task('보고서', deferredCount: 2)]);
      final restored = PreemptiveNudge.fromJson(nudge!.toJson());
      expect(restored?.kind, nudge.kind);
      expect(restored?.message, nudge.message);
      expect(restored?.taskName, nudge.taskName);
    });

    test('깨진 값은 없는 것으로 본다', () {
      expect(PreemptiveNudge.fromJson(null), isNull);
      expect(PreemptiveNudge.fromJson({'kind': 'noPlan'}), isNull);
      expect(PreemptiveNudge.fromJson({'message': '안녕'}), isNull);
    });
  });

  /// 유형을 짚는 말과 알아봐주는 말.
  ///
  /// 매일 같은 말이 뜨면 사흘째부터는 알림이 아니라 소음이다. 주에 한 번씩만
  /// 꺼내고, 나머지 날은 평소 문구로 간다.
  group('주에 한 번만 꺼내는 말', () {
    final now = DateTime(2026, 9, 9, 12, 5);

    List<Map<String, dynamic>> historyWith({
      Map<String, int> doneByDate = const {},
      Map<String, int> totalByDate = const {},
    }) => [
      for (final entry in doneByDate.entries)
        {
          'date': entry.key,
          'doneCount': entry.value,
          'totalCount': totalByDate[entry.key] ?? entry.value,
          'success': entry.value > 0,
        },
    ];

    group('유형 짚기', () {
      test('유형이 있으면 그 유형의 말을 쓴다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: const [],
          typeLabel: '계획 편차형',
          now: now,
        );

        expect(nudge!.isPattern, isTrue);
        expect(
          PreemptiveNudgeService.patternPool(
            typeLabel: '계획 편차형',
            hasPlan: false,
          ),
          contains(nudge.message),
        );
      });

      test('일주일이 안 지났으면 평소 문구로 간다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: const [],
          typeLabel: '계획 편차형',
          now: now,
          lastPatternAt: now.subtract(const Duration(days: 6)),
        );

        expect(nudge!.isPattern, isFalse);
        expect(PreemptiveNudgeService.noPlanMessages, contains(nudge.message));
      });

      test('일주일이 지났으면 다시 꺼낸다', () {
        expect(
          PreemptiveNudgeService.canUsePattern(
            typeLabel: '계획 편차형',
            now: now,
            lastPatternAt: now.subtract(const Duration(days: 7)),
          ),
          isTrue,
        );
      });

      test('오늘 적어둔 사람에게는 "왜 안 짜냥"이 안 나간다', () {
        // 같은 유형이라도 자리가 다르면 말이 달라야 한다. 오늘 적어둔 사람에게
        // "계획만 짜면 다 하면서 왜 안 짜냥?"은 그냥 틀린 말이다.
        final noPlan = PreemptiveNudgeService.patternPool(
          typeLabel: '계획 편차형',
          hasPlan: false,
        );
        final hasPlan = PreemptiveNudgeService.patternPool(
          typeLabel: '계획 편차형',
          hasPlan: true,
        );

        expect(noPlan.any((m) => m.contains('왜 안 짜냥')), isTrue);
        expect(hasPlan.any((m) => m.contains('왜 안 짜냥')), isFalse);
      });

      test('목록이 비었으면 "왜 다 오늘이냥"이 안 나간다', () {
        // 가리킬 목록이 없는데 목록을 가리키는 말을 하면 어긋난다.
        final noPlan = PreemptiveNudgeService.patternPool(
          typeLabel: '계획 과다형',
          hasPlan: false,
        );
        final hasPlan = PreemptiveNudgeService.patternPool(
          typeLabel: '계획 과다형',
          hasPlan: true,
        );

        expect(noPlan.any((m) => m.contains('다 오늘이냥')), isFalse);
        expect(hasPlan.any((m) => m.contains('다 오늘이냥')), isTrue);
        expect(noPlan, isNotEmpty);
      });

      test('아직 유형을 말할 수 없는 사람에게는 안 쓴다', () {
        // 셀 것이 적어 '자유형'으로 빠진 사람이다. 앞자락 칭찬이 사실이 아니면
        // 그냥 아픈 말이 된다.
        expect(
          PreemptiveNudgeService.canUsePattern(
            typeLabel: '자유형',
            now: now,
            lastPatternAt: null,
          ),
          isFalse,
        );
        expect(
          PreemptiveNudgeService.canUsePattern(
            typeLabel: null,
            now: now,
            lastPatternAt: null,
          ),
          isFalse,
        );
      });

      test('이름을 부를 일이 있으면 그 일 이야기가 먼저다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [
            {'id': 't1', 'text': '분기 리포트'},
          ],
          coreTasks: const [
            {'id': 't1', 'text': '분기 리포트'},
          ],
          history: const [],
          typeLabel: '계획 편차형',
          now: now,
        );

        expect(nudge!.isPattern, isFalse);
        expect(nudge.message, contains('분기 리포트'));
      });
    });

    group('알아봐주는 말', () {
      test('어제 다 해냈으면 그걸 먼저 말한다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: historyWith(
            doneByDate: {'2026-09-08': 3},
            totalByDate: {'2026-09-08': 3},
          ),
          now: now,
        );

        expect(nudge!.kind, NudgeKind.praise);
        expect(
          PreemptiveNudgeService.praiseYesterdayMessages,
          contains(nudge.message),
        );
      });

      test('어제 남긴 게 있으면 그 말은 안 한다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: historyWith(
            doneByDate: {'2026-09-08': 1},
            totalByDate: {'2026-09-08': 3},
          ),
          now: now,
        );

        expect(nudge!.kind, isNot(NudgeKind.praise));
      });

      test('이번 주 움직인 날이 여럿이면 날수를 말한다', () {
        // 2026-09-09는 수요일. 이번 주 월·화에 움직였다.
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: historyWith(
            doneByDate: {'2026-09-07': 2, '2026-09-08': 1, '2026-09-09': 0},
            totalByDate: {'2026-09-08': 3},
          ),
          now: now,
        );

        // 월·화 이틀뿐이라 아직 문턱 아래다.
        expect(nudge!.kind, isNot(NudgeKind.praise));

        final moved = PreemptiveNudgeService.movedDaysThisWeek(
          history: historyWith(doneByDate: {'2026-09-07': 2, '2026-09-08': 1}),
          now: now,
        );
        expect(moved, 2);
      });

      test('오늘은 세지 않는다', () {
        // 오늘 안 움직였으니 이 말이 나가는 것이다. 오늘을 넣으면 늘 0이 붙는다.
        final moved = PreemptiveNudgeService.movedDaysThisWeek(
          history: historyWith(doneByDate: {'2026-09-09': 5}),
          now: now,
        );
        expect(moved, 0);
      });

      test('지난주 것은 안 센다', () {
        final moved = PreemptiveNudgeService.movedDaysThisWeek(
          history: historyWith(
            doneByDate: {'2026-09-04': 3, '2026-09-05': 2, '2026-09-06': 1},
          ),
          now: now,
        );
        expect(moved, 0);
      });

      test('오랜만에 해낸 날이면 그 일 이름을 부른다', () {
        // 앞 이레가 조용했고 어제 하나 해냈다. 끊겼다 이어진 자리다.
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: [
            {
              'date': '2026-09-08',
              'doneCount': 1,
              'totalCount': 3,
              'tasks': [
                {'text': '분기 리포트', 'done': true},
                {'text': '방 정리', 'done': false},
              ],
            },
          ],
          now: now,
        );

        expect(nudge!.kind, NudgeKind.praise);
        expect(nudge.message, contains('분기 리포트'));
      });

      test('꾸준하던 사람에게는 이어가자고 하지 않는다', () {
        // 이미 하고 있는 사람에게 이어가자고 하면 시키는 말이 된다.
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: [
            for (final day in ['09-02', '09-03', '09-04', '09-05', '09-07'])
              {'date': '2026-$day', 'doneCount': 2, 'totalCount': 2},
            {
              'date': '2026-09-08',
              'doneCount': 2,
              'totalCount': 2,
              'tasks': [
                {'text': '분기 리포트', 'done': true},
              ],
            },
          ],
          now: now,
        );

        expect(nudge!.kind, NudgeKind.praise);
        expect(
          PreemptiveNudgeService.praiseYesterdayMessages,
          contains(nudge.message),
        );
      });

      test('이름이 너무 길면 이름 없이 말한다', () {
        // 잘라 붙이면 무슨 일인지 알아보기 어렵다.
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: [
            {
              'date': '2026-09-08',
              'doneCount': 1,
              'totalCount': 1,
              'tasks': [
                {'text': '분기 리포트 초안 정리해서 팀에 공유하기', 'done': true},
              ],
            },
          ],
          now: now,
        );

        expect(nudge!.kind, NudgeKind.praise);
        expect(
          PreemptiveNudgeService.praiseYesterdayMessages,
          contains(nudge.message),
        );
      });

      test('일주일이 안 지났으면 안 한다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: historyWith(
            doneByDate: {'2026-09-08': 3},
            totalByDate: {'2026-09-08': 3},
          ),
          now: now,
          lastPraiseAt: now.subtract(const Duration(days: 3)),
        );

        expect(nudge!.kind, isNot(NudgeKind.praise));
      });

      test('이미 움직인 사람에게는 아무 말도 안 한다', () {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [
            {'id': 't1', 'text': '분기 리포트', 'done': true},
          ],
          coreTasks: const [],
          history: historyWith(
            doneByDate: {'2026-09-08': 3},
            totalByDate: {'2026-09-08': 3},
          ),
          now: now,
        );

        expect(nudge, isNull);
      });
    });

    test('해낸 적이 있으면 평소 문구에도 그때 느낌이 섞인다', () {
      // 이 말은 자리를 안 가린다. 오래 쉰 사람에게도, 오늘 아직 시작을 못 한
      // 사람에게도 그대로 통한다.
      final history = [
        {'date': '2026-09-01', 'doneCount': 2, 'totalCount': 2},
      ];
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: history,
          now: now,
          // 칭찬 자리를 막아 평소 문구가 나오게 한다.
          lastPraiseAt: now,
        );
        seen.add(nudge!.message);
      }

      expect(
        seen.intersection(PreemptiveNudgeService.doneMemoryMessages.toSet()),
        isNotEmpty,
      );
    });

    test('해낸 적이 없으면 평소 문구에 안 섞인다', () {
      final seen = <String>{};
      for (var i = 0; i < 200; i++) {
        final nudge = PreemptiveNudgeService.decide(
          todayTasks: const [],
          coreTasks: const [],
          history: const [],
          now: now,
        );
        seen.add(nudge!.message);
      }

      expect(
        seen.intersection(PreemptiveNudgeService.doneMemoryMessages.toSet()),
        isEmpty,
      );
    });

    test('모든 문구가 알림 한 줄에 들어간다', () {
      // 안드로이드 알림은 접힌 상태에서 한 줄만 보이고 나머지는 잘린다.
      // 이름을 부르는 말은 그만큼 여유를 더 준다 — 넘치면 뒤의 "이어가자"가
      // 잘리는데, 앞의 알아봐주는 말은 그대로 남아 뜻이 무너지지 않는다.
      const limit = 28;
      const namedLimit = 32;
      final pools = <String, List<String>>{
        // 키가 겹치는 맵을 그냥 펼치면 뒤엣것이 앞엣것을 덮어써서, 안 검사된
        // 문구가 조용히 생긴다. 자리 이름을 붙여 따로 담는다.
        for (final e in PreemptiveNudgeService.patternMessages.entries)
          '공통 ${e.key}': e.value,
        for (final e in PreemptiveNudgeService.patternNoPlanMessages.entries)
          '계획없음 ${e.key}': e.value,
        for (final e
            in PreemptiveNudgeService.patternNotStartedMessages.entries)
          '시작전 ${e.key}': e.value,
        '계획 청하기': PreemptiveNudgeService.planMessages,
        '시작 거들기': PreemptiveNudgeService.notStartedMessages,
        '칭찬(주간)': PreemptiveNudgeService.praiseWeekMessages,
        '칭찬(어제)': PreemptiveNudgeService.praiseYesterdayMessages,
        '칭찬(오랜만)': PreemptiveNudgeService.praiseComebackMessages,
      };
      for (final entry in pools.entries) {
        for (final message in entry.value) {
          final rendered = message
              .replaceAll('{{n}}', '5')
              .replaceAll(
                '{{task}}',
                'ㄱ' * PreemptiveNudgeService.praiseNameLimit,
              );
          expect(
            rendered.contains('\n'),
            isFalse,
            reason: '${entry.key}: 줄바꿈이 있으면 둘째 줄이 잘린다 — $rendered',
          );
          final cap = message.contains('{{task}}') ? namedLimit : limit;
          expect(
            rendered.length,
            lessThanOrEqualTo(cap),
            reason: '${entry.key}: ${rendered.length}자 — $rendered',
          );
        }
      }
    });
  });

  /// 며칠째 안 오는 사람에게.
  ///
  /// 이 알림은 원래 한 칸짜리였다. 예약이 한 번만 걸려서, 떠난 사람은 딱 한 번
  /// 더 불리고 그 뒤로는 조용했다 — 부르는 게 목적인 사람에게만 안 가던 셈이다.
  group('오래 안 온 사람에게 건네는 말', () {
    test('날수를 세지 않는다', () {
      // 사실을 말한 것뿐이어도 출석 체크로 남는다.
      final all = [
        ...PreemptiveNudgeService.absenceMessages,
        ...PreemptiveNudgeService.longAbsenceMessages,
        ...PreemptiveNudgeService.doneMemoryMessages,
        ...PreemptiveNudgeService.longAbsenceNamedMessages,
      ];
      for (final message in all) {
        expect(
          RegExp(r'\d|하루|이틀|사흘|나흘|닷새|엿새|이레|일주일|며칠').hasMatch(message),
          isFalse,
          reason: '날수를 세는 말이다 — $message',
        );
      }
    });

    test('더 오래된 쪽에는 적으라고 하지 않는다', () {
      // 여러 번 어긋난 요구를 또 하면 안 통하던 것을 한 번 더 하는 셈이다.
      for (final message in PreemptiveNudgeService.longAbsenceMessages) {
        expect(message.contains('적'), isFalse, reason: message);
      }
    });

    test('예전에 해낸 일이 있으면 그 이름을 부르며 청한다', () {
      final message = PreemptiveNudgeService.absenceMessage(
        long: true,
        recentDoneName: '방 정리',
      );
      expect(message, contains('방 정리'));
    });

    test('이름은 없어도 해낸 적이 있으면 그때 느낌을 되살린다', () {
      final message = PreemptiveNudgeService.absenceMessage(
        long: true,
        hasEverDone: true,
      );
      expect(PreemptiveNudgeService.doneMemoryMessages, contains(message));
    });

    test('해낸 적이 아예 없으면 아무것도 전제하지 않는다', () {
      // 없던 날을 있었던 것처럼 말하면 안 된다.
      final message = PreemptiveNudgeService.absenceMessage(long: true);
      expect(PreemptiveNudgeService.longAbsenceMessages, contains(message));
    });

    test('해낸 적이 있는지 기록에서 센다', () {
      expect(
        PreemptiveNudgeService.hasEverDone([
          {'date': '2026-01-02', 'doneCount': 0},
          {'date': '2026-01-03', 'doneCount': 2},
        ]),
        isTrue,
      );
      expect(
        PreemptiveNudgeService.hasEverDone([
          {'date': '2026-01-02', 'doneCount': 0},
        ]),
        isFalse,
      );
      expect(PreemptiveNudgeService.hasEverDone(const []), isFalse);
    });

    test('너무 오래된 것은 안 부른다', () {
      // 반년 전 것을 꺼내면 초대가 아니라 "마지막으로 뭘 한 게 언제였더라"가 된다.
      final now = DateTime(2026, 9, 9);
      List<Map<String, dynamic>> historyAt(String date) => [
        {
          'date': date,
          'doneCount': 1,
          'totalCount': 1,
          'tasks': [
            {'text': '방 정리', 'done': true},
          ],
        },
      ];

      expect(
        PreemptiveNudgeService.recentDoneTaskName(
          history: historyAt('2026-08-20'),
          now: now,
        ),
        '방 정리',
      );
      expect(
        PreemptiveNudgeService.recentDoneTaskName(
          history: historyAt('2026-03-20'),
          now: now,
        ),
        isNull,
      );
    });

    test('이름을 부르는 말도 알림 한 줄에 들어간다', () {
      final name = 'ㄱ' * PreemptiveNudgeService.praiseNameLimit;
      for (final message in PreemptiveNudgeService.longAbsenceNamedMessages) {
        final rendered = message.replaceAll('{{task}}', name);
        expect(rendered.length, lessThanOrEqualTo(32), reason: rendered);
      }
    });

    test('알림 한 줄에 들어간다', () {
      final all = [
        ...PreemptiveNudgeService.absenceMessages,
        ...PreemptiveNudgeService.longAbsenceMessages,
        ...PreemptiveNudgeService.doneMemoryMessages,
      ];
      for (final message in all) {
        expect(message.contains('\n'), isFalse, reason: message);
        expect(message.length, lessThanOrEqualTo(28), reason: message);
      }
    });

    test('오래된 쪽과 덜 오래된 쪽이 서로 다른 말을 쓴다', () {
      expect(
        PreemptiveNudgeService.absenceMessages.toSet().intersection(
          PreemptiveNudgeService.longAbsenceMessages.toSet(),
        ),
        isEmpty,
      );
      expect(
        PreemptiveNudgeService.absenceMessage(long: true),
        isIn(PreemptiveNudgeService.longAbsenceMessages),
      );
      expect(
        PreemptiveNudgeService.doneMemoryMessages.toSet().intersection(
          PreemptiveNudgeService.absenceMessages.toSet(),
        ),
        isEmpty,
      );
      expect(
        PreemptiveNudgeService.absenceMessage(long: false),
        isIn(PreemptiveNudgeService.absenceMessages),
      );
    });
  });
}
