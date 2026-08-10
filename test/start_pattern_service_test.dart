import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/start_pattern_service.dart';

/// 하루 기록 하나. [startHours]는 그날 할 일들을 처음 누른 시각,
/// [done]은 그중 끝낸 개수다.
Map<String, dynamic> day({
  required String date,
  required List<int> startHours,
  required int done,
  int? total,
  bool vacation = false,
}) {
  final count = total ?? startHours.length;
  return {
    'date': date,
    'isVacation': vacation,
    'tasks': [
      for (var i = 0; i < count; i++)
        {
          'text': '할 일 $i',
          'done': i < done,
          if (i < startHours.length)
            'startedAt':
                '2026-08-${(int.parse(date.split('-').last)).toString().padLeft(2, '0')}T'
                '${startHours[i].toString().padLeft(2, '0')}:30:00.000',
        },
    ],
  };
}

/// 같은 시각에 시작하고 같은 완료율을 낸 날을 n일치 만든다.
List<Map<String, dynamic>> days({
  required int count,
  required int startHour,
  required int done,
  required int total,
  int fromDay = 9,
}) {
  return [
    for (var i = 0; i < count; i++)
      day(
        date: '2026-08-${(fromDay + i).toString().padLeft(2, '0')}',
        startHours: List.filled(total, startHour),
        done: done,
        total: total,
      ),
  ];
}

void main() {
  group('보여줄 만큼 쌓였는지', () {
    test('기록이 없으면 아무것도 못 말한다', () {
      final result = StartPatternService.analyze([]);
      expect(result.confidence, StartPatternConfidence.notEnough);
      expect(result.hasResult, isFalse);
    });

    test('이틀치로는 단정하지 않는다', () {
      final result = StartPatternService.analyze(
        days(count: 2, startHour: 9, done: 4, total: 5),
      );
      expect(result.confidence, StartPatternConfidence.notEnough);
      expect(result.dayCount, 2);
    });

    test('사흘부터 조심스럽게 보여준다', () {
      final result = StartPatternService.analyze(
        days(count: 3, startHour: 9, done: 4, total: 5),
      );
      expect(result.confidence, StartPatternConfidence.emerging);
      expect(result.hasResult, isTrue);
    });

    test('엿새까지는 아직 조심스럽다', () {
      final result = StartPatternService.analyze(
        days(count: 6, startHour: 9, done: 4, total: 5),
      );
      expect(result.confidence, StartPatternConfidence.emerging);
    });

    test('이레부터 패턴이라고 부른다', () {
      final result = StartPatternService.analyze(
        days(count: 7, startHour: 9, done: 4, total: 5),
      );
      expect(result.confidence, StartPatternConfidence.established);
    });
  });

  group('어느 시간대가 좋았는지', () {
    test('완료율이 가장 높았던 구간을 고른다', () {
      final result = StartPatternService.analyze([
        ...days(count: 3, startHour: 8, done: 9, total: 10),
        ...days(count: 3, startHour: 13, done: 3, total: 10, fromDay: 20),
      ]);
      expect(result.window, const StartWindow(8));
      expect(result.completionPercent, 90);
    });

    test('두 시간 단위로 묶는다', () {
      // 8시 반과 9시 반은 같은 구간이다.
      final result = StartPatternService.analyze([
        ...days(count: 2, startHour: 8, done: 10, total: 10),
        ...days(count: 2, startHour: 9, done: 10, total: 10, fromDay: 20),
      ]);
      expect(result.window, const StartWindow(8));
      expect(result.dayCount, 4);
    });

    test('그날 가장 이른 시작을 하루의 시작으로 본다', () {
      final result = StartPatternService.analyze([
        day(date: '2026-08-09', startHours: [15, 9, 20], done: 3),
        day(date: '2026-08-10', startHours: [14, 9, 21], done: 3),
        day(date: '2026-08-21', startHours: [16, 8, 22], done: 3),
      ]);
      expect(result.window, const StartWindow(8));
    });

    test('완료율이 같으면 더 여러 날 그랬던 구간을 고른다', () {
      final result = StartPatternService.analyze([
        ...days(count: 4, startHour: 8, done: 5, total: 10),
        ...days(count: 1, startHour: 14, done: 5, total: 10, fromDay: 20),
      ]);
      expect(result.window, const StartWindow(8));
    });
  });

  group('셈에서 빼는 날', () {
    test('휴식 모드인 날은 평가하지 않는다', () {
      final result = StartPatternService.analyze([
        ...days(count: 3, startHour: 9, done: 5, total: 5),
        day(date: '2026-08-21', startHours: [14], done: 0, vacation: true),
      ]);
      expect(result.dayCount, 3);
    });

    test('아무것도 시작하지 않은 날은 셈에 넣지 않는다', () {
      final result = StartPatternService.analyze([
        ...days(count: 3, startHour: 9, done: 5, total: 5),
        {
          'date': '2026-08-11',
          'tasks': [
            {'text': '손도 안 댄 일', 'done': false},
          ],
        },
      ]);
      expect(result.dayCount, 3);
    });

    test('할 일이 하나도 없던 날은 셈에 넣지 않는다', () {
      final result = StartPatternService.analyze([
        ...days(count: 3, startHour: 9, done: 5, total: 5),
        {'date': '2026-08-11', 'tasks': []},
      ]);
      expect(result.dayCount, 3);
    });

    test('이월된 일은 그날 할 일로 세지 않는다', () {
      final result = StartPatternService.analyze([
        {
          'date': '2026-08-09',
          'tasks': [
            {
              'text': '오늘 일',
              'done': true,
              'startedAt': '2026-08-09T09:00:00.000',
            },
            {'text': '어제 일', 'done': false, 'deferred': true},
          ],
        },
        ...days(count: 2, startHour: 9, done: 1, total: 1, fromDay: 20),
      ]);
      // 이월된 일까지 셌다면 완료율이 50%로 떨어진다.
      expect(result.completionPercent, 100);
    });
  });

  group('믿을 수 없는 옛 기록', () {
    // 2026-08-08 배포 전에는 습관에만 시작 시각이 남았다. 그래서 아침부터
    // 일한 날도 밤에 한 운동이 "하루의 시작"으로 잡혔다.
    test('기준일 앞의 날은 세지 않는다', () {
      final result = StartPatternService.analyze([
        day(date: '2026-08-03', startHours: [23], done: 1),
        day(date: '2026-08-05', startHours: [23], done: 1),
        day(date: '2026-08-06', startHours: [22], done: 1),
        day(date: '2026-08-07', startHours: [23], done: 1),
      ]);
      expect(result.dayCount, 0);
      expect(result.confidence, StartPatternConfidence.notEnough);
    });

    test('옛 기록이 섞여 있어도 새 기록만 본다', () {
      final result = StartPatternService.analyze([
        // 밤에 한 습관만 남은 옛날 기록
        day(date: '2026-08-05', startHours: [23], done: 1),
        day(date: '2026-08-06', startHours: [23], done: 1),
        day(date: '2026-08-07', startHours: [23], done: 1),
        // 모든 할 일이 시각을 남기기 시작한 뒤
        ...days(count: 3, startHour: 9, done: 5, total: 5, fromDay: 9),
      ]);
      expect(result.dayCount, 3);
      expect(result.window, const StartWindow(8));
    });
  });

  group('시간대 이름', () {
    test('오전과 오후를 시작 시각 기준으로 붙인다', () {
      expect(const StartWindow(8).label, '오전 8시~10시');
      expect(const StartWindow(10).label, '오전 10시~12시');
      expect(const StartWindow(12).label, '오후 12시~2시');
      expect(const StartWindow(14).label, '오후 2시~4시');
      expect(const StartWindow(22).label, '오후 10시~12시');
    });

    test('이른 새벽은 새벽이라고 부른다', () {
      expect(const StartWindow(0).label, '새벽 0시~2시');
      expect(const StartWindow(4).label, '새벽 4시~6시');
    });
  });
}
