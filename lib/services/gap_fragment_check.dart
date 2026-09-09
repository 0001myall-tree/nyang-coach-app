/// 할 일 이름 하나를 보고, 15분 안에 끝나는 조각 하나를 받아온다.
///
/// 틈새 코칭이 원래 하려던 일이다. "15분만 써봐"가 아니라 "15분 동안 개요만
/// 잡아둘까" — 시간은 좁히되 그 안에서 하나가 완결돼야 한다. 조각을 주되
/// 완성했다는 느낌이 남아야 다음에 또 온다.
///
/// 지금까지는 키워드 사전이 이 일을 했다. 그런데 사전에 없는 이름은 전부
/// "10분만 미리 해두면"으로 떨어져서, 정작 이 기능이 하려던 걸 못 했다.
/// '레퍼런스 정리', '세금계산서', '면접 준비' 같은 것들이다.
///
/// 이 앱은 같은 방식으로 이미 여러 번 뚫렸다 — [RoutineDomainCheck] 첫 줄이
/// 그 반성이고, 거기서는 작은 모델 호출로 옮겼다. 여기도 같은 방식이다.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

class GapFragmentCheck {
  const GapFragmentCheck._();

  /// 이름 하나를 읽는 일이라 작은 모델로 충분하다.
  /// [RoutineDomainCheck]와 같은 모델을 쓴다.
  static const String model = 'gpt-4.1-mini';

  /// 조각 이름이 이보다 길면 카드 한 줄을 혼자 다 먹는다.
  static const int maxFragmentLength = 14;

  static const String _system =
      '당신은 할 일 하나를 보고 15분 안에 끝나는 첫 조각을 정하는 판별기입니다. '
      '설명하지 말고 형식대로만 답합니다.';

  /// 조각 하나. 못 물어봤거나 못 읽었으면 null.
  ///
  /// null과 빈 문자열을 가르지 않는다. 어느 쪽이든 부르는 쪽은 사전으로
  /// 떨어지면 되기 때문이다.
  static Future<String?> fragmentFor(String taskName) async {
    final name = taskName.trim();
    if (name.isEmpty) return null;

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': _prompt(name)},
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
        coachId: 'gap_fragment_check',
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

      return readFragment(content);
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 부르는 쪽이 사전으로 떨어진다.
      return null;
    }
  }

  /// 답에서 조각만 꺼낸다. 쓸 수 없으면 null.
  ///
  /// 모델이 형식을 지킨다는 전제로 좁게 잡지 않는다. 따옴표나 마침표를 붙여
  /// 오는 정도는 흔한데, 그걸로 통째로 버리면 멀쩡한 답이 사전으로 떨어진다.
  static String? readFragment(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    // 여러 줄로 오면 첫 줄만.
    text = text.split('\n').first.trim();
    // 감싼 따옴표와 끝 문장부호를 걷어낸다.
    text = text.replaceAll(RegExp(r'''^["'`\s]+|["'`\s.。!?]+$'''), '');
    if (text.isEmpty) return null;
    if (text.toUpperCase() == 'NONE') return null;
    // 설명을 붙여 오면 조각이 아니다.
    if (text.length > maxFragmentLength) return null;
    return text;
  }

  static String _prompt(String name) {
    final buffer = StringBuffer('[할 일]\n');
    buffer.writeln(name);
    buffer.writeln();
    buffer.writeln(
      '이 일의 첫 조각 하나를 "~하기" 꼴로 적으세요. '
      '$maxFragmentLength자 이내, 조각 외에는 아무것도 적지 마세요. '
      '15분 안에 끝날 조각이 없으면 NONE만 적으세요.',
    );
    buffer.writeln();
    // 무엇이 조각인지를 예시로 보인다. 목록으로 가두면 거기 없는 이름이 전부
    // 빠지고, 설명만 주면 판별기마다 다른 것을 조각이라고 부른다.
    buffer.writeln('- 그 15분 안에 **끝나는** 것이어야 합니다. 시작만 하고 마는 것은 조각이 아닙니다.');
    buffer.writeln('  예: "분기 리포트" → "개요 잡기". "글쓰기 시작하기"는 안 됩니다.');
    buffer.writeln('- 준비가 문턱인 일은 준비 쪽을 고르세요.');
    buffer.writeln('  예: "헬스장 가기" → "운동복 챙기기".');
    buffer.writeln('- 이름만으로 무슨 일인지 알 수 없으면 NONE.');
    buffer.writeln('  예: "그거 하기", "오후 일정".');
    return buffer.toString();
  }
}
