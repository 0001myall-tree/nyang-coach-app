import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/day_capacity_service.dart';
import 'package:nyang_coach/services/overplan_coach_line.dart';

/// 계획이 많아졌을 때 코치가 내밀 근거를 고르는 자리.
///
/// 여기서 엉뚱한 날을 집으면 코치가 사실이 아닌 말을 한다. 그건 틀린 조언보다
/// 나쁘다 - 조언은 안 따르면 그만이지만, 없던 일을 있다고 하면 그 뒤로 코치 말을
/// 믿지 않는다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String history(List<Map<String, Object>> days) => jsonEncode(days);

  Map<String, Object> day(String date, int planned, int done) => {
    'date': date,
    'totalCount': planned,
    'doneCount': done,
  };

  final now = DateTime(2026, 9, 11);

  group('근거로 쓸 날을 고를 때', () {
    test('아침 답과 그날 결과가 둘 다 있는 날을 집는다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-09-10': '두세 시간 정도'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-10', 8, 2)]),
        now: now,
      );

      expect(evidence, isNotNull);
      expect(evidence!.dateLabel, '어제');
      expect(evidence.planned, 8);
      expect(evidence.done, 2);
      expect(evidence.capacityLine, DayCapacityService.answers['두세 시간 정도']);
    });

    test('아침에 안 물어본 날은 근거가 아니다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-09-05': '두세 시간 정도'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-10', 8, 2)]),
        now: now,
      );

      expect(evidence, isNull);
    });

    test('가장 가까운 날을 집는다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({
          '2026-09-07': '거의 없어',
          '2026-09-10': '두세 시간 정도',
        }),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-07', 9, 1), day('2026-09-10', 8, 2)]),
        now: now,
      );

      expect(evidence!.dateLabel, '어제');
      expect(evidence.planned, 8);
    });

    test('오늘은 집지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-09-11': '두세 시간 정도'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-11', 8, 2)]),
        now: now,
      );

      expect(evidence, isNull);
    });

    test('많이 적지 않았던 날은 근거가 아니다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-09-10': '두세 시간 정도'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-10', 2, 2)]),
        now: now,
      );

      expect(evidence, isNull);
    });

    test('너무 오래된 날은 꺼내지 않는다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-08-20': '두세 시간 정도'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-08-20', 8, 1)]),
        now: now,
      );

      expect(evidence, isNull);
    });

    test('쌓인 답이 없으면 근거도 없다', () async {
      SharedPreferences.setMockInitialValues({});

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-10', 8, 2)]),
        now: now,
      );

      expect(evidence, isNull);
    });

    test('며칠 전이면 요일로 부른다', () async {
      SharedPreferences.setMockInitialValues({
        DayCapacityService.logKey: jsonEncode({'2026-09-07': '거의 없어'}),
      });

      final evidence = await OverplanCoachLine.findEvidence(
        historyRaw: history([day('2026-09-07', 8, 1)]),
        now: now,
      );

      expect(evidence!.dateLabel, '지난 월요일');
    });
  });

  group('이 말을 코치가 짓는 자리인지', () {
    test('냥이와 마스터는 짓는다', () {
      expect(OverplanCoachLine.speaks('cat'), isTrue);
      expect(OverplanCoachLine.speaks('nyang_halbae'), isTrue);
      expect(OverplanCoachLine.speaks('sec_female'), isTrue);
    });

    test('옛 이름으로 들어와도 알아본다', () {
      expect(OverplanCoachLine.speaks('sec_male'), isTrue);
    });

    test('나머지 프렌즈는 고정 문구로 간다', () {
      expect(OverplanCoachLine.speaks('bro'), isFalse);
      expect(OverplanCoachLine.speaks('halmae'), isFalse);
      expect(OverplanCoachLine.speaks('boyfriend'), isFalse);
    });
  });

  group('지은 말을 다듬을 때', () {
    test('남은 태그를 떼어낸다', () {
      expect(
        OverplanCoachLine.clean('오늘은 3개만 적어볼래? [TASK: 글쓰기]'),
        '오늘은 3개만 적어볼래?',
      );
    });

    test('빈손이면 null', () {
      expect(OverplanCoachLine.clean('   '), isNull);
    });
  });
}
