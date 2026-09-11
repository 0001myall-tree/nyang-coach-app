/// 매일 루틴을 요일로 어떻게 나눌지 코치가 짜서 제안한다.
///
/// 원래는 앱이 자주 비는 루틴을 골라 보기로 내밀고, 사용자가 하나를 누르면
/// 정해진 요일(화·목)로 바꿨다. 어느 루틴이든 같은 요일이 붙었다는 뜻이다.
/// 아침 운동과 저녁 스트레칭이 같은 날로 몰려도 앱은 그것을 모른다.
///
/// 무엇이 매일이어야 하는지도 코드로는 가를 수 없다. 영양제와 물 마시기는
/// 나누면 뜻이 없어지고, 운동과 독서는 나눠도 된다. 그 판단은 이름을 읽어야
/// 나온다.
///
/// 그래서 나누는 안 자체를 코치가 짠다. 대신 **짜기만 한다** - 실제로 바꾸는
/// 것은 사용자가 그러자고 한 뒤다. 매일 쌓는 중인 일을 코치가 말없이 주 2회로
/// 바꿔버리면 되돌린다고 없던 일이 되지 않는다.
///
/// 값은 14일에 한 번, 그것도 금요일에 조건이 맞았을 때만이다.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'routine_spread_plan.dart';

@immutable
class RoutineSpreadProposal {
  const RoutineSpreadProposal({required this.message, required this.assignments});

  /// 코치가 건넬 말. 태그는 이미 떼어낸 상태다.
  final String message;

  /// 나누자고 제안한 루틴들. 비어 있으면 제안이 아니다.
  final List<RoutineDayAssignment> assignments;
}

class RoutineSpreadOffer {
  const RoutineSpreadOffer._();

  static const String model = 'gpt-5-mini';

  /// 한 번에 이만큼까지만 나눈다.
  ///
  /// 다섯 개를 한꺼번에 바꾸자고 하면 그건 제안이 아니라 개편이다. 무엇이
  /// 어떻게 되는지 한눈에 안 들어오면 사용자는 "그대로 둘게"를 누른다.
  static const int maxAssignments = 3;

  static final RegExp _tag = RegExp(r'\[SPREAD:\s*([^\]]+)\]');

  /// 제안을 만든다. 못 만들었으면 null - 그때는 부르는 쪽이 원래 길로 간다.
  static Future<RoutineSpreadProposal?> compose({
    required String coachId,
    required String routinesBlock,
    String busyBlock = '',
  }) async {
    if (routinesBlock.isEmpty) return null;

    final coach = CoachConfigs.get(coachId);
    final prompt =
        '''${coach.systemPrompt}
$busyBlock$routinesBlock
[이번에 할 말]
매일 하는 루틴이 여럿이라 하루에 다 얹혀 있습니다. 총량이 문제가 아니라 한 날에 몰려 있는 것이 문제입니다. 요일로 나누면 같은 양을 하면서도 채운 날이 생깁니다.

위 목록을 매일 그대로 둘 것과 요일을 정해 나눌 것으로 갈라, 두세 문장으로 제안하세요.

- 매일이어야 뜻이 서는 것은 그대로 두세요. 영양제, 약, 물 마시기처럼 거르면 의미가 없어지는 것들입니다. 그런 루틴은 매일 두자고 한마디 짚어주면 사용자가 안심합니다.
- 나눌 것은 한 번에 ${maxAssignments}개까지 고르세요. 자주 비는 것부터입니다.
- 나누는 것끼리 같은 요일에 몰리지 않게 흩으세요. 월·수·금에 하나, 화·목에 하나처럼요.
- 만든 지 일주일이 안 된 루틴은 아직 그대로 둡니다. 지킬 자리가 없었을 뿐입니다.
- 며칠 비었는지는 숫자로 말하지 마세요. 자리를 다시 잡아주는 말이지 못 한 날을 세는 말이 아닙니다.

답변 끝에 [SPREAD: 루틴이름|요일들; 루틴이름|요일들] 형식으로 나눌 것만 적으세요. 요일은 월화수목금토일 중에서 붙여 씁니다. 예: [SPREAD: 아침 운동|월수금; 독서|화목]
루틴 이름은 위 목록에 적힌 그대로 쓰세요. 매일 그대로 둘 루틴은 태그에 넣지 않습니다.
나눌 것이 없다고 판단하면 태그 없이 그 이유만 한 문장으로 답하세요.''';

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

      return parse(content);
    } catch (e) {
      debugPrint('routine spread offer failed: $e');
      return null;
    }
  }

  /// 답변에서 말과 배정을 갈라낸다. 배정이 하나도 없으면 null.
  ///
  /// 이름이 실제로 있는 루틴인지는 여기서 보지 않는다. [RoutineSpreadApply]가
  /// 이름으로 찾으면서 못 찾은 것을 건너뛴다.
  @visibleForTesting
  static RoutineSpreadProposal? parse(String raw) {
    final match = _tag.firstMatch(raw);
    if (match == null) return null;

    final assignments = <RoutineDayAssignment>[];
    final seen = <String>{};
    for (final part in (match.group(1) ?? '').split(';')) {
      final bar = part.indexOf('|');
      if (bar < 0) continue;
      final name = part.substring(0, bar).trim();
      if (name.isEmpty) continue;
      final days = _days(part.substring(bar + 1));
      // 요일이 하나도 없으면 그 루틴은 오늘 탭에서 영영 사라진다. 사용자에게는
      // 지워진 것과 구별되지 않는다.
      if (days.isEmpty) continue;
      // 이레 내내를 요일로 적어 보내는 일이 있다. 그건 나눈 것이 아니다.
      if (days.length >= RoutineSpreadPlan.dayNames.length) continue;
      if (!seen.add(name)) continue;
      assignments.add(RoutineDayAssignment(name: name, days: days));
      if (assignments.length >= maxAssignments) break;
    }
    if (assignments.isEmpty) return null;

    final message = raw.replaceAll(_tag, '').trim();
    if (message.isEmpty) return null;
    return RoutineSpreadProposal(message: message, assignments: assignments);
  }

  /// '월수금' -> [0, 2, 4]. 적힌 순서가 아니라 요일 순으로 돌려준다.
  static List<int> _days(String raw) {
    final found = <int>{};
    for (final char in raw.trim().split('')) {
      final index = RoutineSpreadPlan.dayNames.indexOf(char);
      if (index >= 0) found.add(index);
    }
    final days = found.toList()..sort();
    return days;
  }
}
