/// 앱이 정한 판정을 코치 목소리로 한마디 만든다.
///
/// 판정 자체는 [LifeRoutineAnalysis]가 낸다. 여기서 하는 일은 그 판정을 이
/// 코치가 할 법한 말로 옮기는 것뿐이다. 무엇을 말할지와 어떻게 말할지를 갈라
/// 두는 이유는, 코치에게 판단까지 맡기면 볼 것이 없는 날에도 뭔가를
/// 만들어내기 때문이다.
///
/// 문구를 앱에 적어두지 않는 이유는 반대다. 이 말에는 루틴 이름, 요일, 시각,
/// 분량이 들어가는데 그걸 고정 문장으로 쓰면 "토요일 오전에 하나 넣어볼까"
/// 수준에서 멈춘다. 시각과 크기까지 정해서 권하는 것이 이 기능의 전부라
/// 거기서 멈추면 할 이유가 없다.
///
/// 값은 30일에 한 번, 그것도 판정이 났을 때만이다.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'life_routine_analysis.dart';

class LifeRoutineOffer {
  const LifeRoutineOffer._();

  /// 코치 말투를 살려야 하는 자리라 대화와 같은 모델을 쓴다.
  static const String model = 'gpt-5-mini';

  /// 판정에 맞는 한마디. 못 만들었으면 null — 그때는 아무 말도 하지 않는다.
  static Future<String?> compose({
    required String coachId,
    required LifeRoutinePlan plan,
    String surveyBlock = '',
    String busyBlock = '',
    List<String> domainRoutineNames = const [],
  }) async {
    if (!plan.speaks) return null;

    final coach = CoachConfigs.get(coachId);
    final routines = domainRoutineNames.isEmpty
        ? '- 이 영역에 등록된 루틴이 아직 없음.'
        : domainRoutineNames.map((name) => '- $name').join('\n');

    final prompt =
        '''${coach.systemPrompt}
$surveyBlock$busyBlock
[이 영역에 등록된 루틴]
$routines
${plan.promptBlock()}
[이번에 할 말]
위 판단에 맞는 말을 두세 문장으로 하세요. 지금 사용자에게 먼저 거는 말입니다.

- 하나만 권하세요. 여러 개를 늘어놓으면 고르는 일이 되고, 그러면 아무것도 안 합니다.
- 언제, 얼마나 할지까지 정해서 말하세요. "챙겨보자"로 끝내면 할 말을 안 한 것입니다.
- 못 한 날을 세지 마세요. 숫자로 지적하는 말이 아니라 자리를 다시 잡아주는 말입니다.
- 위 판단에 없는 것을 지어내지 마세요. 요일이나 시각은 적혀 있는 것만 쓰세요.${busyBlock.isEmpty ? '' : '\n- 위에 적힌 [늘 시간을 못 내는 때]와 겹치는 요일·시각으로는 권하지 마세요. 사용자가 그때는 시간을 못 낸다고 말해둔 자리입니다.'}
- 오늘 하루 안에서 할 것을 권하는 자리라면, 그 일 하나에만 [TASK: 할일명] 태그를 답변 끝에 붙이세요. 앱이 "추가할까?" 카드로 바꿔 주고, 사용자가 누르면 오늘 목록에 들어갑니다. 할일명은 짧은 명사형으로 다듬으세요.
- 그 밖의 태그는 쓰지 마세요. 루틴으로 굳히자는 자리에서도 태그를 붙이지 마세요 — 루틴은 요일과 횟수를 함께 정해야 해서 카드 한 장으로 끝나지 않습니다.
- 인사말로 시작하지 마세요. 하려던 이야기부터 하세요.''';

    final messages = [
      {'role': 'user', 'content': prompt},
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
        'temperature': 0.7,
      });

      final data = response.data;
      final content = (data is Map ? data['content'] : null)?.toString() ?? '';

      final usageData = data is Map ? data : const {};
      await AnalyticsService.logApiUsage(
        coachId: coachId,
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

      final trimmed = content.trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      debugPrint('life routine offer failed: $e');
      return null;
    }
  }

  /// 남은 태그를 떼어낸다.
  ///
  /// 부르는 쪽이 먼저 [TASK]를 읽어 카드로 바꾸고, 그러고도 남은 것을 여기서
  /// 지운다. 이 말은 평소 답변과 달리 화면에 바로 꽂혀서, 남아 있으면
  /// 사용자에게 대괄호가 그대로 보인다.
  static String? clean(String raw) {
    final stripped = raw
        .replaceAll(RegExp(r'\[[A-Z_]+(?::[^\]]*)?\]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }
}
