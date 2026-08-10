import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/analytics_service.dart';

/// 실제 토큰 수는 o200k_base(gpt-4o-mini / gpt-4.1-mini의 토크나이저)로 미리
/// 재둔 값이다. Dart에서 토크나이저를 돌릴 수 없으니 측정값을 박아두고,
/// 추정식이 거기서 멀어지면 알아채게 한다.
class _Sample {
  const _Sample(this.label, this.text, this.actualTokens);
  final String label;
  final String text;
  final int actualTokens;
}

const samples = [
  _Sample('짧은 발화', '오늘 뭐부터 하지? 아 배고파. 집중이 너무 안 된다.', 16),
  _Sample('기록 한 덩어리', '''[오늘 할 일 현황]
- [V] [습관] 물 2리터 마시기 (오전 9:00)
- [ ] [일반 할 일] 경쟁 계정 3곳 콘텐츠 특징 5가지 분석하기 (예상 소요시간: 1시간(60분)) / 앱 기록상 미루기 2회
- [~] [일정] 오후 3시 회의 (오후 3:00)''', 100),
  _Sample(
    '지침 한 문단',
    '사용자가 속상함, 피로, 불안, 답답함 등 감정을 토로하면 먼저 충분히 공감하고 달래주세요. '
        '무슨 말을 더 할지 애매하면, 사용자가 쓴 말에 공감하거나 그 말을 다른 표현으로 정리해서 돌려주세요.',
    62,
  ),
];

int estimate(String text) => AnalyticsService.estimateChatTokens([
  {'role': 'system', 'content': text},
], '');

void main() {
  group('한국어 토큰 추정', () {
    for (final sample in samples) {
      test('${sample.label}은 실제 토큰 수의 ±20% 안에 든다', () {
        final estimated = estimate(sample.text);
        expect(
          estimated,
          inInclusiveRange(
            (sample.actualTokens * 0.8).floor(),
            (sample.actualTokens * 1.2).ceil(),
          ),
          reason: '추정 $estimated / 실제 ${sample.actualTokens}',
        );
      });
    }

    test('한도 검사에 쓰는 값이라 절반으로 깎이지는 않는다', () {
      // 예전 3.2로 나누던 식은 실제의 45~55%밖에 안 나왔다. 그 상태로 돌아가면
      // 한 요청이 한도를 넘겨도 통과한다.
      for (final sample in samples) {
        expect(
          estimate(sample.text),
          greaterThan(sample.actualTokens * 0.7),
          reason: sample.label,
        );
      }
    });

    test('메시지와 답변 글자를 모두 센다', () {
      final withReply = AnalyticsService.estimateChatTokens([
        {'role': 'system', 'content': '가나다라마바사'},
      ], '아자차카타파하');
      final withoutReply = estimate('가나다라마바사');
      expect(withReply, greaterThan(withoutReply));
    });
  });
}
