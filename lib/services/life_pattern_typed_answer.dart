/// 설문 문항에 버튼 대신 말로 답했을 때, 그 말이 어느 보기인지 가른다.
///
/// 버튼을 눌러야만 답이 저장됐다. "나 혼자 살아"라고 적으면 코치는 그 말에
/// 대답은 하는데 답으로는 안 남았고, 며칠 뒤에 같은 것을 또 물었다. 사용자
/// 입장에서는 답했는데 또 묻는 것이다.
///
/// 키워드로 가르지 않는다. '혼자 살아'는 잡혀도 '자취 중이야'나 '아직 본가'는
/// 놓친다. 사람이 답하는 말을 목록으로 따라잡을 수는 없다.
///
/// 못 물어봤거나 답이 아닌 말이면 아무것도 적지 않는다. 애매한 것을 억지로
/// 고르면 사용자가 고른 적 없는 답이 프로필에 박히고, 그건 안 묻느니만
/// 못하다 — 다시 확인할 때까지 한 달을 틀린 전제로 코칭한다.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'life_pattern_service.dart';
import 'numbered_answer.dart';

class LifePatternTypedAnswer {
  const LifePatternTypedAnswer._();

  /// 보기 하나를 고르는 일이라 작은 모델로 충분하다.
  static const String model = 'gpt-4.1-mini';

  /// 이보다 긴 말은 답이 아니라 하던 이야기로 본다. 문항에 답하는 말은 짧다.
  static const int maxTextLength = 120;

  static const String _system =
      '당신은 사용자의 말이 설문 보기 중 무엇에 해당하는지 가르는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// [text]가 [question]의 어느 보기인지. 고른 말들을 돌려준다.
  ///
  /// 답이 아니거나 애매하면 빈 목록. 못 물어봤으면 null — 둘을 갈라야 한다.
  /// 통신이 한 번 끊긴 것과 "이건 답이 아니다"는 다른 일이다.
  static Future<List<String>?> read({
    required LifePatternQuestion question,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > maxTextLength) return const [];

    final labels = question.labels;
    if (labels.isEmpty) return const [];

    final messages = [
      {'role': 'system', 'content': _system},
      {
        'role': 'user',
        'content': _prompt(question: question, labels: labels, text: trimmed),
      },
    ];

    final picked = await _ask(messages, count: labels.length);
    if (picked == null) return null;
    if (picked.isEmpty) return const [];

    // 하나만 고르는 문항인데 여럿을 골라 왔으면 못 가른 것이다. 아무거나
    // 집어 넣느니 다음에 다시 묻는 편이 낫다.
    if (!question.multi && picked.length > 1) return const [];

    return [
      for (var i = 0; i < labels.length; i++)
        if (picked.contains(i)) labels[i],
    ];
  }

  static String _prompt({
    required LifePatternQuestion question,
    required List<String> labels,
    required String text,
  }) {
    final buffer = StringBuffer('[코치가 물은 것]\n');
    buffer.writeln(question.ask);
    buffer.writeln();
    buffer.writeln('[보기]');
    for (var i = 0; i < labels.length; i++) {
      // 보기에 보이는 말과, 그 보기가 뜻하는 바를 같이 준다. 보이는 말만
      // 주면 짧아서 무슨 뜻인지 판별기마다 다르게 읽는다.
      final note = question.options[labels[i]];
      buffer.writeln(
        note == null || note == labels[i]
            ? '${i + 1}. ${labels[i]}'
            : '${i + 1}. ${labels[i]} — $note',
      );
    }
    buffer.writeln();
    buffer.writeln('[사용자가 한 말]');
    buffer.writeln(text);
    buffer.writeln();
    buffer.writeln(
      question.multi
          ? '이 말에 해당하는 보기의 번호를 쉼표로 적으세요. 해당하는 것이 없으면 NONE만 적으세요. 번호와 쉼표, 또는 NONE 외에는 아무것도 적지 마세요.'
          : '이 말에 해당하는 보기의 번호 하나만 적으세요. 해당하는 것이 없으면 NONE만 적으세요. 번호 하나 또는 NONE 외에는 아무것도 적지 마세요.',
    );
    buffer.writeln();
    buffer.writeln('- 말이 달라도 뜻이 같으면 그 보기입니다. 예: "자취 중이야"는 혼자 산다는 뜻.');
    buffer.writeln('- 되묻거나, 답을 미루거나, 다른 이야기로 넘어간 말이면 NONE입니다.');
    buffer.writeln('- 애매하면 NONE을 적으세요. 고른 적 없는 답이 남는 것이 훨씬 나쁩니다.');
    return buffer.toString();
  }

  /// 못 물어봤으면 null. 해당 없음이면 빈 집합이다.
  static Future<Set<int>?> _ask(
    List<Map<String, String>> messages, {
    required int count,
  }) async {
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
      final picked = NumberedAnswer.read(content, count: count);

      final usageData = data is Map ? data : const {};
      await AnalyticsService.logApiUsage(
        coachId: 'life_pattern_typed_answer',
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
        countAsUserUsage: false,
      );
      return picked;
    } catch (_) {
      // 한도가 찼거나 통신이 끊겼다. 답이 아닌 것이 아니라 모르는 것이라,
      // 그 문항은 안 물어본 채로 남고 다음에 다시 묻는다.
      return null;
    }
  }
}
