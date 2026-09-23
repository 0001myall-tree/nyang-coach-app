import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/active_coaching_time.dart';

/// "좀 더 있다가 언제?"에 내놓는 시각들.
///
/// 상대 표현을 쓰지 않는다. 3시 12분에 "30분 뒤 · 3:30"은 18분 뒤라 거짓말이
/// 된다. 반듯한 시각이라야 약속처럼 들리기도 한다.
void main() {
  group('자리 잡기', () {
    test('30분·1시간 지점에서 가장 가까운 정각이나 반', () {
      expect(ActiveCoachingTime.choices(DateTime(2026, 9, 23, 15, 12)), [
        DateTime(2026, 9, 23, 15, 30),
        DateTime(2026, 9, 23, 16),
      ]);
      expect(ActiveCoachingTime.choices(DateTime(2026, 9, 23, 15, 20)), [
        DateTime(2026, 9, 23, 16),
        DateTime(2026, 9, 23, 16, 30),
      ]);
    });

    test('둘이 같은 칸에 떨어지면 뒤엣것을 한 칸 민다', () {
      // 같은 시각 버튼 둘은 고를 것이 하나인 것과 같다.
      final picked = ActiveCoachingTime.choices(DateTime(2026, 9, 23, 15, 50));
      expect(picked.length, 2);
      expect(picked[0], isNot(picked[1]));
    });

    test('고른 시각은 늘 지금보다 뒤다', () {
      for (var minute = 0; minute < 60; minute++) {
        final now = DateTime(2026, 9, 23, 15, minute);
        for (final at in ActiveCoachingTime.choices(now)) {
          expect(at.isAfter(now), isTrue, reason: '$now → $at');
        }
      }
    });

    test('반올림은 0~14분 정각, 15~44분 반, 45분부터 다음 정각', () {
      expect(
        ActiveCoachingTime.round(DateTime(2026, 9, 23, 15, 14)),
        DateTime(2026, 9, 23, 15),
      );
      expect(
        ActiveCoachingTime.round(DateTime(2026, 9, 23, 15, 15)),
        DateTime(2026, 9, 23, 15, 30),
      );
      expect(
        ActiveCoachingTime.round(DateTime(2026, 9, 23, 15, 45)),
        DateTime(2026, 9, 23, 16),
      );
    });
  });

  group('주지 않는 자리', () {
    test('취침 시각을 넘으면 뺀다', () {
      // 10시 반에 "한 시간 뒤"를 주면 11시 반에 부르게 된다.
      final picked = ActiveCoachingTime.choices(
        DateTime(2026, 9, 23, 22, 20),
        bedtime: '23:00',
      );
      expect(picked, isEmpty);
    });

    test('취침을 안 정해뒀으면 23시가 경계', () {
      expect(
        ActiveCoachingTime.choices(DateTime(2026, 9, 23, 22, 20)),
        isEmpty,
      );
      expect(ActiveCoachingTime.choices(DateTime(2026, 9, 23, 21, 40)), [
        DateTime(2026, 9, 23, 22),
        DateTime(2026, 9, 23, 22, 30),
      ]);
    });

    test('늦게 자는 사람에게는 밤 10시도 이르다', () {
      // 새벽 1시에 자는 사람에게 밤 10시는 아직 세 시간이 남은 시각이다.
      final picked = ActiveCoachingTime.choices(
        DateTime(2026, 9, 23, 22, 20),
        bedtime: '01:00',
      );
      expect(picked.length, 2);
    });

    test('매인 시간대는 내밀지 않는다', () {
      // 근무 중으로 미뤄봐야 그 시각에 할 수 없다. [직접 고르기]로 굳이
      // 고르는 것은 본인 선택이라 거기서는 막지 않는다.
      final picked = ActiveCoachingTime.choices(
        DateTime(2026, 9, 23, 15, 12),
        busyAt: (at) => at.hour == 16,
      );
      expect(picked, [DateTime(2026, 9, 23, 15, 30)]);
    });
  });

  test('저장할 모양은 두 자리씩', () {
    expect(ActiveCoachingTime.format(DateTime(2026, 9, 23, 9, 5)), '09:05');
    expect(ActiveCoachingTime.format(DateTime(2026, 9, 23, 16, 30)), '16:30');
  });
}
