import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/day_record_builder.dart';

/// 저장된 목표에서 그날 이정표를 골라 기록용 줄로 옮기기까지.
List<Map<String, dynamic>> _entriesFor(String? visionsJson, String dateKey) =>
    DayRecordBuilder.milestoneEntries(
      DayRecordBuilder.milestonesForDate(visionsJson, dateKey),
    );

void main() {
  group('DayRecordBuilder.taskEntry', () {
    test('시작 표시가 기록으로 따라간다', () {
      // 채팅에서 시작을 누른 그대로의 모양.
      final entry = DayRecordBuilder.taskEntry({
        'id': 1789882644933,
        'text': '시놉시스',
        'category': 'today',
        'done': false,
        'inProgress': true,
        'inProgressAt': '2026-09-20T14:37:32.024709',
        'runStartedAt': '2026-09-20T14:37:32.024709',
      });

      expect(entry['inProgress'], isTrue);
      expect(entry['startedAt'], '2026-09-20T14:37:32.024709');
      expect(entry['text'], '시놉시스');
      expect(entry['deferred'], isFalse);
    });

    test('시작하지 않은 할 일에는 시작 시각이 붙지 않는다', () {
      final entry = DayRecordBuilder.taskEntry({
        'text': '퇴고(1화)',
        'category': 'today',
        'done': false,
      });

      expect(entry['inProgress'], isFalse);
      expect(entry.containsKey('startedAt'), isFalse);
      expect(entry.containsKey('completedAt'), isFalse);
    });

    test('기록에 남기는 칸은 이게 전부다', () {
      // 읽는 데가 없는 칸을 늘리지 않으려고 못 박아둔다.
      final entry = DayRecordBuilder.taskEntry({
        'id': 1,
        'text': '회의',
        'category': 'today',
        'done': true,
        'inProgress': false,
        'completedAt': '2026-09-20T11:00:00.000',
        'timeStart': '10:00',
        'isHabit': false,
        'deferredCount': 0,
        'memo': '안 따라가는 칸',
      });

      expect(entry.keys.toSet(), {
        'text',
        'done',
        'inProgress',
        'completedAt',
        'category',
        'deferred',
      });
    });

    test('완료 시각도 따라간다', () {
      final entry = DayRecordBuilder.taskEntry({
        'text': '청소기 돌리기',
        'done': true,
        'completedAt': '2026-09-20T15:10:00.000',
      });

      expect(entry['done'], isTrue);
      expect(entry['completedAt'], '2026-09-20T15:10:00.000');
    });

    test('이미 기록 모양인 줄을 다시 옮겨도 시작 표시가 안 없어진다', () {
      // 이월 목록은 기록 모양(`startedAt`)으로 저장돼 있다.
      final entry = DayRecordBuilder.taskEntry({
        'text': '어제 못 끝낸 것',
        'done': false,
        'inProgress': true,
        'startedAt': '2026-09-19T21:00:00.000',
      }, deferred: true);

      expect(entry['startedAt'], '2026-09-19T21:00:00.000');
      expect(entry['deferred'], isTrue);
    });

    test('category가 없으면 today로 둔다', () {
      expect(DayRecordBuilder.taskEntry({'text': '무엇'})['category'], 'today');
    });
  });

  group('DayRecordBuilder.milestoneEntry', () {
    test('이정표는 milestone으로 갈린다', () {
      final entry = DayRecordBuilder.milestoneEntry(text: '1장 마감', done: true);

      expect(entry['category'], 'milestone');
      expect(entry['done'], isTrue);
      expect(entry['deferred'], isFalse);
    });
  });

  group('DayRecordBuilder.buildDayRecord', () {
    test('채팅에서 시작만 한 하루도 시작 표시를 남긴다', () {
      // 그 사람의 하루 그대로다 — 쏟아내기로 셋을 적고 하나를 시작했다.
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: [
          {
            'text': '시놉시스',
            'category': 'today',
            'done': false,
            'inProgress': true,
            'inProgressAt': '2026-09-20T14:37:32.024709',
          },
          {'text': '퇴고(1화)', 'category': 'today', 'done': false},
          {'text': '퇴고(2~5)', 'category': 'today', 'done': false},
        ],
        milestones: const [],
      );

      expect(record['totalCount'], 3);
      expect(record['doneCount'], 0);
      final entries = record['tasks'] as List;
      expect(entries.first['inProgress'], isTrue);
      expect(entries.first['startedAt'], '2026-09-20T14:37:32.024709');
    });

    test('끝낸 이정표가 분자와 분모에 함께 들어간다', () {
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: [
          {'text': '청소기', 'done': false},
        ],
        milestones: [
          {'text': '1장 마감', 'done': true, 'date': '2026-09-20'},
        ],
      );

      expect(record['totalCount'], 2);
      expect(record['doneCount'], 1);
      expect(record['success'], isTrue);
    });

    test('이정표만 끝낸 날도 해낸 날이다', () {
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: const [],
        milestones: [
          {'text': '1장 마감', 'done': true, 'date': '2026-09-20'},
        ],
      );

      expect(record['success'], isTrue);
      expect(record['doneCount'], 1);
    });

    test('이월된 일은 분모에 안 들어가되 시작 표시는 데려간다', () {
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: [
          {'text': '오늘 것', 'done': true},
        ],
        milestones: const [],
        deferred: [
          {
            'text': '어제 넘어온 것',
            'done': false,
            'startedAt': '2026-09-19T21:00:00.000',
          },
        ],
      );

      expect(record['totalCount'], 1);
      final entries = (record['tasks'] as List).cast<Map>();
      final carried = entries.firstWhere((e) => e['deferred'] == true);
      expect(carried['startedAt'], '2026-09-19T21:00:00.000');
    });

    test('주 몇 회 루틴은 안 한 날 분모에서 빠진다', () {
      final tasks = [
        {'text': '헬스', 'habitId': 'h1', 'done': false},
        {'text': '설거지', 'done': false},
      ];
      const freq = {'h1': 'weekly_count'};

      expect(
        DayRecordBuilder.buildDayRecord(
          date: '2026-09-20',
          tasks: tasks,
          milestones: const [],
          habitFreqById: freq,
        )['totalCount'],
        1,
      );

      // 끝낸 날에는 다시 분모로 들어온다.
      expect(
        DayRecordBuilder.buildDayRecord(
          date: '2026-09-20',
          tasks: [
            {'text': '헬스', 'habitId': 'h1', 'done': true},
            {'text': '설거지', 'done': false},
          ],
          milestones: const [],
          habitFreqById: freq,
        )['totalCount'],
        2,
      );
    });

    test('분모에서 빠진 루틴도 목록에는 남는다', () {
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: [
          {'text': '헬스', 'habitId': 'h1', 'done': false},
        ],
        milestones: const [],
        habitFreqById: const {'h1': 'weekly_count'},
      );

      expect(record['totalCount'], 0);
      expect((record['tasks'] as List).length, 1);
    });

    test('아무것도 없는 날', () {
      final record = DayRecordBuilder.buildDayRecord(
        date: '2026-09-20',
        tasks: const [],
        milestones: const [],
      );

      expect(record['totalCount'], 0);
      expect(record['doneCount'], 0);
      expect(record['success'], isFalse);
      expect(record['tasks'], isEmpty);
      expect(record['date'], '2026-09-20');
    });
  });

  group('DayRecordBuilder.milestonesForDate', () {
    const visions = '''
[
  {
    "name": "웹소설 연재",
    "milestones": [
      {"text": "1장 마감", "done": true, "date": "2026-09-20",
       "achievedDate": "2026-09-20T18:00:00.000"},
      {"text": "2장 마감", "done": false, "date": "2026-09-21"}
    ]
  },
  {
    "name": "체력",
    "milestones": [
      {"text": "5km 뛰기", "done": false, "date": "2026-09-20"}
    ]
  }
]
''';

    test('그날 걸린 것만 목표를 넘나들며 모은다', () {
      final entries = _entriesFor(
        visions,
        '2026-09-20',
      );

      expect(entries.map((e) => e['text']), ['1장 마감', '5km 뛰기']);
      expect(entries.every((e) => e['category'] == 'milestone'), isTrue);
    });

    test('끝낸 이정표는 달성 시각을 들고 온다', () {
      final entries = _entriesFor(
        visions,
        '2026-09-20',
      );

      expect(entries.first['done'], isTrue);
      expect(entries.first['completedAt'], '2026-09-20T18:00:00.000');
      expect(entries.last.containsKey('completedAt'), isFalse);
    });

    test('걸린 게 없는 날은 빈손', () {
      expect(
        _entriesFor(visions, '2026-09-22'),
        isEmpty,
      );
    });

    test('목표가 없거나 깨져 있어도 기록 쓰기를 막지 않는다', () {
      expect(
        _entriesFor(null, '2026-09-20'),
        isEmpty,
      );
      expect(_entriesFor('', '2026-09-20'), isEmpty);
      expect(
        _entriesFor('{깨진', '2026-09-20'),
        isEmpty,
      );
      expect(
        _entriesFor('{"a":1}', '2026-09-20'),
        isEmpty,
      );
    });

    test('이정표가 없는 목표는 건너뛴다', () {
      expect(
        _entriesFor(
          '[{"name":"그냥 목표"},{"name":"빈 것","milestones":[]}]',
          '2026-09-20',
        ),
        isEmpty,
      );
    });

    test('이름 없는 이정표는 세지 않는다', () {
      expect(
        _entriesFor(
          '[{"milestones":[{"text":"","done":true,"date":"2026-09-20"}]}]',
          '2026-09-20',
        ),
        isEmpty,
      );
    });
  });
}
