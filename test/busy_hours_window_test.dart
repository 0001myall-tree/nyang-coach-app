import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/busy_hours_service.dart';

/// 늘 시간을 못 내는 때가 오늘 몇 시에 끝나는지.
///
/// 묻는 창을 퇴근 뒤까지 밀어주는 데 쓴다. 근무가 그 창을 통째로 먹는 사람이
/// 있어서(평일 9~18시가 낮 질문 창 정오~18시를 다 덮는다), 바쁜 시간에 안
/// 묻기만 하면 그 사람에게는 영영 안 물어보게 된다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 2026-09-16은 수요일.
  final wednesday = DateTime(2026, 9, 16, 10, 0);
  final saturday = DateTime(2026, 9, 19, 10, 0);

  Future<SharedPreferences> prefsWith(List<Map<String, dynamic>> hours) async {
    SharedPreferences.setMockInitialValues({
      BusyHoursService.prefsKey: jsonEncode(hours),
    });
    return SharedPreferences.getInstance();
  }

  test('적어둔 것이 없으면 null', () async {
    final prefs = await prefsWith(const []);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), isNull);
  });

  test('오늘 걸리는 것이 끝나는 시각을 돌려준다', () async {
    final prefs = await prefsWith([
      {'name': '근무', 'start': '09:00', 'end': '18:00', 'days': <String>[]},
    ]);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), 18);
  });

  test('여러 개면 가장 늦게 끝나는 것', () async {
    final prefs = await prefsWith([
      {'name': '근무', 'start': '09:00', 'end': '18:00', 'days': <String>[]},
      {'name': '학원', 'start': '19:00', 'end': '21:00', 'days': <String>[]},
    ]);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), 21);
  });

  test('오늘 걸리지 않는 요일은 세지 않는다', () async {
    final prefs = await prefsWith([
      {
        'name': '근무',
        'start': '09:00',
        'end': '18:00',
        'days': ['월', '화', '수', '목', '금'],
      },
    ]);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), 18);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, saturday), isNull);
  });

  test('분이 남으면 다음 시로 올린다', () async {
    // 18:30에 끝나는 사람의 창을 18시로 닫으면 아직 근무 중에 닫는 셈이다.
    final prefs = await prefsWith([
      {'name': '근무', 'start': '09:00', 'end': '18:30', 'days': <String>[]},
    ]);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), 19);
  });

  test('자정을 넘기는 시간대는 세지 않는다', () async {
    // 야간 근무하는 사람의 "퇴근 뒤"는 다음 날 새벽이라, 오늘 창을 미루는
    // 것으로 풀 일이 아니다.
    final prefs = await prefsWith([
      {'name': '야근무', 'start': '22:00', 'end': '06:00', 'days': <String>[]},
    ]);
    expect(BusyHoursService.latestBusyEndHourToday(prefs, wednesday), isNull);
  });
}
