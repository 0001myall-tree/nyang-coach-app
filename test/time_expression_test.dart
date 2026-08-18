import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/time_expression.dart';

/// 시각을 떼어낸 자리에 뭐가 남는지 본다. 여기 남은 조사가 그대로 카드 이름이
/// 되기 때문에, "9시부터 운동"이 '부터 운동'으로 등록되던 일이 여기서 걸린다.
String stripTime(String input) {
  final match =
      kTimeRangeRegex.firstMatch(input) ?? kSingleTimeRegex.firstMatch(input);
  if (match == null) return input.trim();
  return input.replaceFirst(match.group(0)!, '').replaceAll('  ', ' ').trim();
}

void main() {
  group('시각 뒤 조사', () {
    test('부터는 시각의 일부다', () {
      expect(stripTime('9시부터 운동 시작'), '운동 시작');
      expect(stripTime('오후 3시부터 회의'), '회의');
      expect(stripTime('9시 반부터 산책'), '산책');
    });

    test('원래 알아듣던 조사도 그대로', () {
      expect(stripTime('9시에 운동'), '운동');
      expect(stripTime('9시쯤 운동'), '운동');
      expect(stripTime('9시 30분에 운동'), '운동');
    });

    test('부턴, 엔, 에서부터 같은 변형', () {
      expect(stripTime('9시부턴 운동'), '운동');
      expect(stripTime('9시엔 운동'), '운동');
      expect(stripTime('9시부터는 운동'), '운동');
      expect(stripTime('9시에서부터 운동'), '운동');
    });

    test('조사가 없어도 된다', () {
      expect(stripTime('9시 운동'), '운동');
    });

    test('시각이 없으면 건드리지 않는다', () {
      expect(stripTime('운동하기'), '운동하기');
    });
  });

  group('시각 범위', () {
    test('끝 시각까지 통째로 떼어낸다', () {
      expect(stripTime('9시부터 10시까지 운동'), '운동');
      expect(stripTime('오후 2시~4시 회의'), '회의');
      expect(stripTime('오전 9시에서 11시 스터디'), '스터디');
    });

    test('시작과 끝을 각각 읽는다', () {
      final m = kTimeRangeRegex.firstMatch('오전 9시 30분부터 오후 5시까지 근무')!;
      expect(m.group(1)!.trim(), '오전');
      expect(m.group(2), '9');
      expect(m.group(3), '30');
      expect(m.group(4)!.trim(), '오후');
      expect(m.group(5), '5');
    });
  });

  group('반', () {
    test('시작의 반이 끝으로 옮겨붙지 않는다', () {
      final segments = splitTimeRange('9시 반부터 10시까지');
      expect(minuteFrom(null, segments.start), 30);
      expect(minuteFrom(null, segments.end), 0);
    });

    test('끝의 반도 마찬가지', () {
      final segments = splitTimeRange('9시부터 10시 반까지');
      expect(minuteFrom(null, segments.start), 0);
      expect(minuteFrom(null, segments.end), 30);
    });

    test('적어준 분이 있으면 그게 우선', () {
      expect(minuteFrom('45', '9시 45분'), 45);
    });

    test('범위가 아니면 양쪽이 같은 글자', () {
      final segments = splitTimeRange('9시 반에');
      expect(segments.start, segments.end);
      expect(minuteFrom(null, segments.start), 30);
    });
  });
}
