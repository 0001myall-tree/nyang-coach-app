import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 카드가 튀는 모양. 화면 없이 값만 확인한다.
///
/// 눈으로 보기 전에 숫자로라도 확인해두는 것은, 이 곡선을 잘못 쓰면 카드가
/// 제자리로 안 돌아오거나 아래로 파고들기 때문이다.
double _dy(double t) => TweenSequence<double>([
  TweenSequenceItem(tween: ConstantTween<double>(0), weight: 10),
  TweenSequenceItem(tween: Tween<double>(begin: 0, end: -10), weight: 12),
  TweenSequenceItem(tween: Tween<double>(begin: -10, end: 0), weight: 16),
  TweenSequenceItem(tween: Tween<double>(begin: 0, end: -6), weight: 10),
  TweenSequenceItem(tween: Tween<double>(begin: -6, end: 0), weight: 14),
  TweenSequenceItem(tween: ConstantTween<double>(0), weight: 38),
]).transform(t);

void main() {
  test('시작과 끝은 제자리다', () {
    expect(_dy(0), 0);
    expect(_dy(1), 0);
  });

  test('아래로는 내려가지 않는다', () {
    for (var i = 0; i <= 100; i++) {
      expect(_dy(i / 100), lessThanOrEqualTo(0.0001), reason: 't=${i / 100}');
    }
  });

  test('두 번 튀고, 두 번째가 더 작다', () {
    double peakIn(double from, double to) {
      var lowest = 0.0;
      for (var i = 0; i <= 100; i++) {
        final t = from + (to - from) * i / 100;
        if (_dy(t) < lowest) lowest = _dy(t);
      }
      return lowest;
    }

    final first = peakIn(0.10, 0.38);
    final second = peakIn(0.38, 0.62);
    expect(first, closeTo(-10, 0.5));
    expect(second, closeTo(-6, 0.5));
    expect(second, greaterThan(first));
  });

  test('마지막 3분의 1은 가만히 있는다', () {
    for (var i = 65; i <= 100; i++) {
      expect(_dy(i / 100), closeTo(0, 0.0001));
    }
  });
}
