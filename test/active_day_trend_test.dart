import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/execution_pattern_service.dart';

/// 이번 이레와 지난 이레에 하루라도 해낸 날이 며칠인지.
///
/// 완료율로는 안 보이는 값이다 — 하는 날에는 어차피 100%라, 손대는 날이 하루
/// 늘어도 숫자가 그대로다. 편차형에게 나아졌다고 말할 근거는 이쪽뿐이다.
///
/// 이 파일이 이 서비스에 남은 유일한 기능을 지킨다. 유형에 이름을 붙이던 옛
/// 코드는 걷어냈다 — 선을 그어 칸을 나누던 방식이라, 앞뒤가 정반대인 두 사람이
/// 같은 칸에 들어갔다. 이름은 이제 세 단계를 서로 견주는 깔때기가 정한다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> day(int daysAgo, {required int done, int planned = 2}) {
    final date = DateTime.now().subtract(Duration(days: daysAgo));
    return {
      'date':
          '${date.year}-${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}',
      'tasks': [
        for (var i = 0; i < planned; i++) {'text': '할 일 $i', 'done': i < done},
      ],
    };
  }

  Future<({int thisWeek, int lastWeek})> trendOf(
    List<Map<String, dynamic>> days,
  ) async {
    SharedPreferences.setMockInitialValues({'nyang_history': jsonEncode(days)});
    return ExecutionPatternService.activeDayTrend();
  }

  test('기록이 없으면 양쪽 다 0', () async {
    SharedPreferences.setMockInitialValues({});
    final trend = await ExecutionPatternService.activeDayTrend();
    expect(trend.thisWeek, 0);
    expect(trend.lastWeek, 0);
  });

  test('하나라도 끝낸 날을 센다. 몇 개 끝냈는지는 세지 않는다', () async {
    final trend = await trendOf([
      day(1, done: 1),
      day(2, done: 2),
      day(3, done: 0),
    ]);

    expect(trend.thisWeek, 2);
  });

  test('지난 이레는 따로 센다', () async {
    final trend = await trendOf([
      day(1, done: 1),
      day(9, done: 1),
      day(10, done: 1),
    ]);

    expect(trend.thisWeek, 1);
    expect(trend.lastWeek, 2);
  });

  test('두 이레보다 오래된 날은 어느 쪽에도 안 들어간다', () async {
    final trend = await trendOf([day(20, done: 2)]);

    expect(trend.thisWeek, 0);
    expect(trend.lastWeek, 0);
  });
}
