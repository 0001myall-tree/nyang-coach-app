import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 자정 정리가 "어느 날 목록을 정리하는 것인지" 어떻게 정하는가.
///
/// 원래는 'nyang_last_date' 하나로 정했다. 그 값은 클라우드로 오간다. 그래서
/// 두 기기를 쓰면, 먼저 연 기기가 정리를 끝내고 오늘 날짜를 올리는 순간 늦게
/// 여는 기기는 "저장된 날짜가 이미 오늘"이라며 자기가 들고 있는 어제 목록을
/// 보관하지 않고 지나갔다. 2026-09-08과 09-09 목록이 보관함에 없던 이유다.
///
/// 목록을 옮기는 일이니, 어느 날 것인지는 옮길 목록에게 묻는다.
void main() {
  Map<String, dynamic> habitTask(String habitId, String date) => {
    'id': 'habit_${habitId}_$date',
    'habitId': habitId,
    'text': '영양제 챙겨먹기',
    'category': 'habit',
  };

  group('목록이 어느 날 것인지', () {
    test('루틴 항목의 id에 박힌 날짜로 안다', () {
      expect(
        DailyResetService.listDateOf([habitTask('1788307997240', '2026-09-09')]),
        '2026-09-09',
      );
    });

    test('루틴이 없으면 손으로 적은 할 일의 적은 날을 본다', () {
      expect(
        DailyResetService.listDateOf([
          {
            'id': 't1',
            'text': '집필',
            'category': 'today',
            'createdAt': '2026-09-09T21:30:00.000',
          },
        ]),
        '2026-09-09',
      );
    });

    // 일정을 만든 날은 그 일정이 놓인 날이 아니다. 지난달에 잡아둔 약속이
    // 목록을 지난달 것으로 만들면, 보관 범위 밖이라 통째로 버려진다.
    test('일정을 만든 날은 보지 않는다', () {
      expect(
        DailyResetService.listDateOf([
          {
            'id': 'schedule_9',
            'text': '치과',
            'category': 'schedule',
            'createdAt': '2026-08-01T10:00:00.000',
          },
        ]),
        isNull,
      );
    });

    // 어제 목록에 오늘 아침 적은 할 일이 하나 섞여도, 루틴이 어제라고 하면
    // 어제 것이다. 여기서 오늘로 읽으면 어제 목록이 통째로 보관을 건너뛴다.
    test('루틴 날짜가 손으로 적은 날짜보다 먼저다', () {
      expect(
        DailyResetService.listDateOf([
          habitTask('1', '2026-09-09'),
          {
            'id': 't1',
            'text': '집필',
            'category': 'today',
            'createdAt': '2026-09-10T08:00:00.000',
          },
        ]),
        '2026-09-09',
      );
    });

    // 화면은 정리와 상관없이 오늘 루틴을 목록에 채워 넣는다. 그래서 어제
    // 목록에 오늘 만든 루틴 하나가 얹힐 수 있다. 늦은 쪽을 따르면 이 목록이
    // "오늘 것"이 되어 어제가 통째로 보관을 건너뛴다.
    test('날짜가 섞이면 이른 날을 따른다', () {
      expect(
        DailyResetService.listDateOf([
          habitTask('1', '2026-09-09'),
          habitTask('2', '2026-09-10'),
        ]),
        '2026-09-09',
      );
    });

    test('빈 목록은 아무 말도 하지 않는다', () {
      expect(DailyResetService.listDateOf(const []), isNull);
    });
  });

  group('정리할 날짜를 고를 때', () {
    // 이 문제 전체가 여기 한 줄에 담긴다.
    test('클라우드가 올려둔 오늘 날짜에 밀리지 않는다', () {
      final from = DailyResetService.resetFromDate(
        tasks: [habitTask('1', '2026-09-09')],
        localListDate: null,
        lastDate: '2026-09-10', // 다른 기기가 먼저 정리하고 올린 값
        today: '2026-09-10',
      );

      expect(from, '2026-09-09');
    });

    test('목록이 말이 없으면 이 기기에 적어둔 날짜를 쓴다', () {
      final from = DailyResetService.resetFromDate(
        tasks: const [],
        localListDate: '2026-09-09',
        lastDate: '2026-09-10',
        today: '2026-09-10',
      );

      expect(from, '2026-09-09');
    });

    test('그것마저 없을 때에만 오가는 값을 쓴다', () {
      final from = DailyResetService.resetFromDate(
        tasks: const [],
        localListDate: null,
        lastDate: '2026-09-09',
        today: '2026-09-10',
      );

      expect(from, '2026-09-09');
    });

    test('아무 데도 날짜가 없으면 정리할 것이 없다', () {
      final from = DailyResetService.resetFromDate(
        tasks: const [],
        localListDate: null,
        lastDate: null,
        today: '2026-09-10',
      );

      expect(from, isNull);
    });

    // 목록이 이미 오늘 것이면 옮길 것이 없다. 다른 기기가 오늘 목록을
    // 만들어 올렸고 이 기기가 그걸 받은 경우다 — 여기서 정리를 한 번 더
    // 돌리면 오늘 목록이 어제 칸으로 넘어간다.
    test('받아온 목록이 이미 오늘 것이면 오늘로 읽는다', () {
      final from = DailyResetService.resetFromDate(
        tasks: [habitTask('1', '2026-09-10')],
        localListDate: '2026-09-09',
        lastDate: '2026-09-09',
        today: '2026-09-10',
      );

      expect(from, '2026-09-10');
    });
  });

  // 폰 시계가 앞서 있거나 시차가 다른 곳에서 만든 목록이 넘어오면 목록 전체가
  // 아직 오지 않은 날짜일 수 있다. 그 날짜로 정리를 돌리면 "지난 날 보관"이
  // 성립하지 않아 목록이 보관 없이 버려진다.
  group('아직 오지 않은 날짜는', () {
    test('오늘로 읽어 아무것도 옮기지 않는다', () {
      final from = DailyResetService.resetFromDate(
        tasks: [habitTask('1', '2026-09-11')],
        localListDate: null,
        lastDate: null,
        today: '2026-09-10',
      );

      expect(from, '2026-09-10');
    });

    test('적어둔 날짜가 앞서 있어도 마찬가지다', () {
      final from = DailyResetService.resetFromDate(
        tasks: const [],
        localListDate: '2026-09-12',
        lastDate: null,
        today: '2026-09-10',
      );

      expect(from, '2026-09-10');
    });

    // 섞여 있으면 이른 날을 따르므로 지난 날이 살아남는다. 미래 하나 때문에
    // 어제 목록이 통째로 버려지면 안 된다.
    test('지난 날과 섞여 있으면 지난 날이 이긴다', () {
      final from = DailyResetService.resetFromDate(
        tasks: [habitTask('1', '2026-09-09'), habitTask('2', '2026-09-11')],
        localListDate: null,
        lastDate: null,
        today: '2026-09-10',
      );

      expect(from, '2026-09-09');
    });
  });
}
