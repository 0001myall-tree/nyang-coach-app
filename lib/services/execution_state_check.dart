import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

/// 실행이 막힌 사람이 몸이 안 움직이는 쪽인지, 일이 부담스러운 쪽인지 가른다.
///
/// 둘은 처방이 반대다. 꼼짝도 못 하는 사람에게 "오늘 끝낼 몫을 정하자"는
/// 자책거리가 되고, 엄두가 안 나는 사람에게 "손목부터 돌려보자"는 뜬금없다.
///
/// 단어 목록으로 가르던 자리다. 목록에 있던 열네 개가 전부 몸 얘기(무기력,
/// 방전, 누워만 있어)여서 정작 흔한 "그냥 손이 안 가"가 빠져나갔다. 그렇다고
/// "하기 싫어"를 목록에 넣으면 이번엔 저항을 통째로 삼킨다. 같은 말이 양쪽을
/// 가리키니 글자를 아무리 모아도 못 가른다.
///
/// 그래서 뜻을 따로 물어본다. 같은 턴의 코치에게 맡기지 않는 이유는 그
/// 프롬프트가 이미 길어서 이 한 줄이 그 안에서 묻히기 때문이다. 여기서는
/// 묻는 것이 그것 하나뿐이다.
///
/// 못 물어봤으면 저항으로 둔다. 몸이 안 움직인다고 볼 근거가 없는 것이지
/// 아니라는 뜻은 아니다. 다만 저항이 훨씬 흔해서, 모를 때 그쪽으로 두는 편이
/// 덜 틀린다.
class ExecutionStateCheck {
  const ExecutionStateCheck._();

  /// 상태 하나를 가리는 데는 작은 모델로 충분하다.
  static const String model = 'gpt-4.1-mini';

  /// 보는 말의 개수. 한 마디만 보면 앞 턴에 "너무 지쳤어" 해놓고 이번 턴에
  /// "청소해야 되는데"만 말하는 흐름을 놓친다.
  static const int maxLines = 6;

  static const String _system =
      '당신은 사람의 말에서 지금 상태 하나만 가려내는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// 몸이 안 움직이는 상태로 보이면 true.
  ///
  /// [recentUserLines]는 사용자가 최근에 한 말을 오래된 것부터 담은 것이다.
  static Future<bool> looksLowEnergy(List<String> recentUserLines) async {
    final lines = [
      for (final line in recentUserLines)
        if (line.trim().isNotEmpty) line.trim(),
    ];
    if (lines.isEmpty) return false;
    final asked = lines.length > maxLines
        ? lines.sublist(lines.length - maxLines)
        : lines;

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': promptFor(asked)},
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
        coachId: 'execution_state_check',
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
      return readVerdict(content);
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 가를 근거가 없으니 저항으로 둔다.
      return false;
    }
  }

  /// 답에서 판정을 읽는다. 테스트가 이 자리로 들어온다.
  ///
  /// 형식대로만 답하라고 했어도 앞뒤에 뭔가 붙어 오는 일이 있어서 통문자열로
  /// 비교하지 않는다. 둘 다 없거나 둘 다 있으면 못 읽은 것으로 본다.
  static bool readVerdict(String content) {
    final upper = content.toUpperCase();
    final hasBody = upper.contains('BODY');
    final hasTask = upper.contains('TASK');
    return hasBody && !hasTask;
  }

  /// 물어보는 문구. 테스트가 이 자리로 들어온다.
  static String promptFor(List<String> lines) {
    final buffer = StringBuffer();
    buffer.writeln('[사용자가 최근에 한 말]');
    for (final line in lines) {
      buffer.writeln('- $line');
    }
    buffer.writeln();
    buffer.writeln(
      '이 사람이 지금 어느 쪽인지 하나만 고르세요. BODY 또는 TASK 한 단어만 적고 다른 말은 적지 마세요.',
    );
    buffer.writeln();
    buffer.writeln(
      'BODY: 몸이 안 따라주는 상태. 기운이 바닥이라 무엇을 하든 일어나는 것부터 어렵습니다. '
      '예: "손가락 하나 까딱하기 싫어", "며칠째 누워만 있어", "아무것도 못 하겠어".',
    );
    buffer.writeln(
      'TASK: 움직일 기운은 있는데 그 일이 부담스러워 못 시작하는 상태. 다른 일은 하고 있거나 할 수 있습니다. '
      '예: "청소해야 하는데 엄두가 안 나", "계속 미루고 있어", "딴짓만 하고 있어".',
    );
    buffer.writeln();
    buffer.writeln('가르는 기준:');
    buffer.writeln('- "하기 싫어", "귀찮아"는 양쪽 다 쓰는 말입니다. 그 말만으로 정하지 말고 앞뒤를 보세요.');
    buffer.writeln('- 특정한 일 하나만 무거워 보이면 TASK, 무엇이든 다 버거워 보이면 BODY입니다.');
    buffer.writeln('- 다른 일은 하고 있다고 말하면 몸은 움직이는 것이므로 TASK입니다.');
    buffer.writeln('- 권하는 것마다 못 하겠다고 거듭 물리고 있으면 BODY 쪽입니다.');
    buffer.writeln('- 판단이 서지 않으면 TASK를 고르세요.');
    return buffer.toString();
  }
}
