/// 이 사람의 실행 유형이 무엇인지만 코치에게 묻는다.
///
/// 프렌즈 등급은 주간 한마디를 통째로 만들지 않는다. 그런데 판정만은 코치가
/// 하는 편이 낫다 — 문턱으로 이름을 붙이면 앞뒤가 정반대인 두 사람이 같은
/// 이름으로 묶이고, 그 이름에 붙은 고정 문구까지 같이 틀린다.
///
/// 그래서 이름 하나만 받아 온다. 문구는 그 이름에 미리 적어둔 것을 쓴다.
/// 물어보는 것이 하나뿐이라 값은 주 1회 몇 백 토큰이고, 그 주 내내 캐시된다.
///
/// 못 물어봤으면 null. 부르는 쪽이 깔때기가 짚은 자리로 대신 이름을 정한다.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'execution_funnel.dart';
import 'execution_type_labels.dart';

class ExecutionTypeVote {
  const ExecutionTypeVote._();

  /// 이름 하나를 고르는 일이라 작은 모델로 충분하다.
  static const String model = 'gpt-4.1-mini';

  static const String _system =
      '당신은 실행 기록을 보고 유형 이름 하나를 고르는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// [lastLabel]은 지난주에 뭐라고 불렀는지. 같은 사람이 한 주 만에 다른
  /// 사람이 되지는 않아서, 숫자가 뚜렷하게 달라졌을 때만 바꾸게 한다.
  static Future<String?> pick({
    required ExecutionFunnel funnel,
    String? lastLabel,
  }) async {
    if (!funnel.hasEnough) return null;

    final buffer = StringBuffer(funnel.promptBlock());
    buffer.writeln();
    buffer.writeln('위 숫자를 보고 이 사람의 실행 유형 이름을 하나만 고르세요.');
    buffer.writeln('각 이름이 가리키는 모양이 정해져 있으니, 그 뜻과 다른 사람에게 그 이름을 붙이지 마세요.');
    buffer.writeln(ExecutionTypeLabels.listForPrompt);
    buffer.writeln();
    buffer.writeln('- 축은 서로 견주어 보세요. 같은 완료율이라도 앞뒤가 다르면 다른 사람입니다.');
    buffer.writeln('- 지난주에는 `${lastLabel ?? '없음'}`이라고 불렀습니다. 숫자가 뚜렷하게 달라졌을 때만 바꾸세요.');
    buffer.writeln('- 어디에도 맞지 않으면 `유형: 없음`이라고 적으세요.');
    buffer.writeln();
    buffer.writeln('`유형: 이름` 한 줄만 적으세요. 다른 말은 덧붙이지 마세요.');

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': buffer.toString()},
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

      final usageData = data is Map ? data : const {};
      await AnalyticsService.logApiUsage(
        coachId: 'execution_type_vote',
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
        usageSource: 'execution_type_vote',
        countAsUserUsage: false,
      );

      return ExecutionTypeLabels.readFrom(content);
    } catch (e) {
      debugPrint('execution type vote failed: $e');
      return null;
    }
  }
}
