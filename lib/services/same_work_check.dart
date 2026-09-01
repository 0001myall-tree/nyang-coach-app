import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'numbered_answer.dart';
import 'api_usage_limit_service.dart';

/// 새로 제안된 할 일이 이미 목록에 있는 일인지 뜻을 보고 가른다.
///
/// 글자로는 가를 수 없는 짝이 많다. '지원서 비교견적서 내기'와 '지원서
/// 비교견적서 제출'은 서로를 품고 있지 않고, '책 읽기'와 '독서'는 글자가 하나도
/// 겹치지 않는다. 반대로 '보고서 초안 쓰기'와 '보고서 초안 검토'는 앞이 통째로
/// 같은데 다른 일이다. 글자를 아무리 잘 세어도 이 셋을 동시에 맞힐 수는 없다.
///
/// 그래서 이름 몇 개만 따로 물어본다. 같은 턴 안의 코치에게 맡기지 않는 이유는,
/// 그 프롬프트가 이미 길고 "목록에 있는 건 붙이지 마라"는 한 줄이 그 안에서
/// 자주 묻히기 때문이다. 여기서는 물어보는 것이 그것 하나뿐이다.
///
/// 값은 이름 몇 줄이라 평소 한 턴의 몇십 분의 일이다. 할 일 제안이 있는 턴에만
/// 부른다.
///
/// 못 물어봤으면 아무것도 걸러내지 않는다. 걸러낼 근거가 없는 것이지 같은
/// 일이라는 뜻이 아니다.
class SameWorkCheck {
  const SameWorkCheck._();

  /// 이름 판별에는 작은 모델로 충분하다.
  static const String model = 'gpt-4.1-mini';

  /// 한 번에 견주는 개수. 넘으면 앞에서부터 자른다.
  static const int maxNames = 20;

  static const String _system =
      '당신은 할 일 이름 두 묶음을 견주는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// [candidates] 중 [existing]에 이미 있는 일을 가리키는 것들의 번호(0부터).
  ///
  /// 물어보지 못했거나 답을 못 읽으면 빈 집합이다.
  static Future<Set<int>> alreadyOnList({
    required List<String> existing,
    required List<String> candidates,
  }) async {
    if (existing.isEmpty || candidates.isEmpty) return const {};

    final listed = existing.take(maxNames).toList(growable: false);
    final asked = candidates.take(maxNames).toList(growable: false);

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': _prompt(listed: listed, asked: asked)},
    ];

    try {
      final estimatedPromptTokens = AnalyticsService.estimateChatTokens(
        messages,
        '',
      );
      await ApiUsageLimitService.ensureChatAllowed(
        estimatedTokens: estimatedPromptTokens,
      );

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('chatProxy');
      final response = await callable.call({
        'messages': messages,
        'model': model,
        'temperature': 0,
      });

      final data = response.data;
      final content = (data is Map ? data['content'] : null)?.toString() ?? '';
      final picked = NumberedAnswer.read(content, count: asked.length);

      final usageData = data is Map ? data : const {};
      await AnalyticsService.logApiUsage(
        coachId: 'same_work_check',
        estimatedTokens: estimatedPromptTokens,
        actualTokens: AnalyticsService.readIntValue(usageData, [
          'totalTokens',
          'total_tokens',
          'tokens',
          'usage.totalTokens',
          'usage.total_tokens',
        ]),
        actualCostWon: AnalyticsService.readIntValue(usageData, [
          'costWon',
          'cost_won',
          'estimatedCostWon',
          'estimated_cost_won',
          'usage.costWon',
        ]),
        model: model,
      );
      return picked;
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 걸러낼 근거가 없으니 그대로 둔다.
      return const {};
    }
  }

  /// 견줄 목록을 적는다. 번호는 사람이 세듯 1부터 적고, 읽을 때 0부터로 돌린다.
  static String _prompt({
    required List<String> listed,
    required List<String> asked,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('[이미 목록에 있는 일]');
    for (final name in listed) {
      buffer.writeln('- $name');
    }
    buffer.writeln();
    buffer.writeln('[새로 제안된 일]');
    for (var i = 0; i < asked.length; i++) {
      buffer.writeln('${i + 1}. ${asked[i]}');
    }
    buffer.writeln();
    buffer.writeln(
      '새로 제안된 일 중에서, 이미 목록에 있는 일과 같은 일을 가리키는 것의 번호만 쉼표로 적으세요. '
      '해당하는 것이 없으면 NONE만 적으세요. 번호와 쉼표, 또는 NONE 외에는 아무것도 적지 마세요.',
    );
    buffer.writeln();
    buffer.writeln('같은 일인지 보는 기준:');
    buffer.writeln('- 이름이 달라도 실제로 하는 행동이 같으면 같은 일입니다. 예: "책 읽기"와 "독서".');
    buffer.writeln(
      '- 끝말만 바꿔 적은 것도 같은 일입니다. 예: "지원서 비교견적서 내기"와 "지원서 비교견적서 제출".',
    );
    buffer.writeln(
      '- 앞말이 같아도 하는 행동이 다르면 다른 일입니다. 예: "보고서 초안 쓰기"와 "보고서 초안 검토".',
    );
    buffer.writeln(
      '- 같은 대상을 다루더라도 단계가 다르면 다른 일입니다. 예: "장보기"와 "저녁 만들기".',
    );
    return buffer.toString();
  }

}
