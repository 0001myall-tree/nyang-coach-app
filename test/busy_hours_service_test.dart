import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/busy_hours_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('태그 읽기', () {
    test('이름·시간대·요일을 갈라 읽는다', () {
      final hours = BusyHoursService.read('알겠습니다. [BUSY: 회사 일|09:00-19:00|월화수목금]');
      expect(hours!.name, '회사 일');
      expect(hours.start, '09:00');
      expect(hours.end, '19:00');
      expect(hours.days, ['월', '화', '수', '목', '금']);
    });

    test('요일 칸이 비면 매일로 둔다', () {
      expect(BusyHoursService.read('[BUSY: 근무|09:00-18:00|]')!.days, isEmpty);
      expect(BusyHoursService.read('[BUSY: 근무|09:00-18:00]')!.days, isEmpty);
    });

    test('코치가 형식을 조금 어겨도 받아준다', () {
      final loose = BusyHoursService.read('[BUSY: 근무|9시-19시|평일 월화수목금]');
      expect(loose!.start, '09:00');
      expect(loose.end, '19:00');
      expect(loose.days, ['월', '화', '수', '목', '금']);
    });

    test("'평일'의 '일'을 일요일로 읽지 않는다", () {
      expect(BusyHoursService.read('[BUSY: 근무|09:00-19:00|평일]')!.days, [
        '월',
        '화',
        '수',
        '목',
        '금',
      ]);
      expect(BusyHoursService.read('[BUSY: 알바|09:00-18:00|주말]')!.days, [
        '일',
        '토',
      ]);
      expect(BusyHoursService.read('[BUSY: 근무|09:00-19:00|월요일, 수요일]')!.days, [
        '월',
        '수',
      ]);
    });

    test('시간대를 못 알아들으면 저장하지 않는다', () {
      expect(BusyHoursService.read('[BUSY: 근무|낮에|월화수]'), isNull);
      expect(BusyHoursService.read('[BUSY: 근무]'), isNull);
      expect(BusyHoursService.read('[BUSY: 근무|09:00-25:00]'), isNull);
      expect(BusyHoursService.read('오늘은 바쁘시군요'), isNull);
    });

    test('태그는 본문에서 떼어낸다', () {
      expect(
        BusyHoursService.strip('알겠습니다.[BUSY: 근무|09:00-19:00|월화수목금]').trim(),
        '알겠습니다.',
      );
    });
  });

  group('지금이 그 시간인지', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> seed(List<Map<String, dynamic>> entries) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(BusyHoursService.prefsKey, jsonEncode(entries));
    }

    test('요일과 시각이 둘 다 맞아야 이름을 준다', () async {
      await seed([
        {
          'name': '회사 일',
          'start': '09:00',
          'end': '19:00',
          'days': ['월', '화', '수', '목', '금'],
        },
      ]);
      final prefs = await SharedPreferences.getInstance();
      // 2026-09-04는 금요일.
      expect(
        BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 14)),
        '회사 일',
      );
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 21)), isNull);
      // 토요일 같은 시각.
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 5, 14)), isNull);
    });

    test('자정을 넘기는 시간대도 안에 든 것으로 본다', () async {
      await seed([
        {'name': '야간 근무', 'start': '22:00', 'end': '06:00', 'days': []},
      ]);
      final prefs = await SharedPreferences.getInstance();
      expect(
        BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 23)),
        '야간 근무',
      );
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 3)), '야간 근무');
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 12)), isNull);
    });

    test('저장된 게 없거나 깨졌으면 조용히 넘어간다', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 14)), isNull);
      await prefs.setString(BusyHoursService.prefsKey, '{깨진 값');
      expect(BusyHoursService.busyNow(prefs, DateTime(2026, 9, 4, 14)), isNull);
    });
  });

  group('프롬프트에 싣는 모양', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('오늘 걸리는 것만 싣고, 없으면 아무것도 안 싣는다', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(BusyHoursService.promptBlock(prefs, DateTime(2026, 9, 4)), '');

      await prefs.setString(
        BusyHoursService.prefsKey,
        jsonEncode([
          {
            'name': '회사 일',
            'start': '09:00',
            'end': '19:00',
            'days': ['월', '화', '수', '목', '금'],
          },
          {
            'name': '주말 알바',
            'start': '10:00',
            'end': '16:00',
            'days': ['토'],
          },
        ]),
      );
      // 금요일.
      final friday = BusyHoursService.promptBlock(prefs, DateTime(2026, 9, 4));
      expect(friday, contains('회사 일: 오전 9:00 ~ 오후 7:00'));
      expect(friday, isNot(contains('주말 알바')));
    });

    test('한 주치는 요일을 달고 전부 싣는다', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(BusyHoursService.weeklyPromptBlock(prefs), '');

      await prefs.setString(
        BusyHoursService.prefsKey,
        jsonEncode([
          {
            'name': '회사 일',
            'start': '09:00',
            'end': '19:00',
            'days': ['월', '화', '수', '목', '금'],
          },
          {'name': '등원 준비', 'start': '07:00', 'end': '08:30', 'days': []},
        ]),
      );
      final block = BusyHoursService.weeklyPromptBlock(prefs);
      expect(block, contains('회사 일: 월화수목금 오전 9:00 ~ 오후 7:00'));
      expect(block, contains('등원 준비: 매일 오전 7:00 ~ 오전 8:30'));
    });
  });

  group('저장', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('같은 이름은 쌓이지 않고 갈아끼워진다', () async {
      await BusyHoursService.save(
        const BusyHours(
          name: '회사 일',
          start: '09:00',
          end: '19:00',
          days: ['월'],
        ),
      );
      await BusyHoursService.save(
        const BusyHours(
          name: '회사 일',
          start: '10:00',
          end: '17:00',
          days: ['월'],
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(BusyHoursService.prefsKey)!) as List;
      expect(saved, hasLength(1));
      expect(saved.first['start'], '10:00');
    });

    test('설정 화면이 읽던 형식 그대로 쓴다', () async {
      await BusyHoursService.save(
        const BusyHours(
          name: '회사 일',
          start: '09:00',
          end: '19:00',
          days: ['월', '금'],
        ),
      );
      final prefs = await SharedPreferences.getInstance();
      final saved =
          jsonDecode(prefs.getString(BusyHoursService.prefsKey)!) as List;
      expect(saved.first.keys, containsAll(['name', 'start', 'end', 'days']));
    });
  });
}
