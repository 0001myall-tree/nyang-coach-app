/// 이 루틴이 어느 코치의 담당인지 뜻을 보고 가른다.
///
/// 키워드 사전으로 하지 않는다. 이 앱은 같은 방식으로 여러 번 뚫렸다 —
/// '방 정리'는 잡혀도 '분리수거'나 '이불 널기'는 놓친다. 사람이 루틴에 적는
/// 이름을 목록으로 따라잡을 수는 없다.
///
/// 대신 30일에 한 번, 그 코치의 루틴 이름을 통째로 넘겨 한 번만 가른다. 그
/// 주기면 값은 없는 것과 같고, 이름이 어떻게 쓰였든 뜻으로 갈린다.
///
/// 못 물어봤으면 아무것도 적어두지 않는다. "담당이 없다"와 "아직 모른다"를
/// 섞으면, 통신이 한 번 끊긴 것 때문에 한 달 내내 담당 루틴이 없는 사람이 된다.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'life_pattern_service.dart';
import 'numbered_answer.dart';

class RoutineDomainCheck {
  const RoutineDomainCheck._();

  /// 이름 판별에는 작은 모델로 충분하다.
  static const String model = 'gpt-4.1-mini';

  /// 한 번에 가르는 개수. 넘으면 앞에서부터 자른다.
  static const int maxNames = 30;

  static const String _system =
      '당신은 할 일 이름이 어느 영역에 속하는지 가르는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// 영역마다 무엇이 여기 들어가는지.
  ///
  /// 경계를 예시로 보여준다. 목록으로 가두면 거기 없는 이름이 전부 빠지고,
  /// 아무 설명 없이 이름만 주면 어디까지가 그 영역인지가 판별기마다 달라진다.
  static const Map<LifeDomain, String> _descriptions = {
    LifeDomain.housework:
        '살림 — 청소, 정리, 빨래, 설거지, 주방 정리, 장보기, 식사 준비, 쓰레기와 분리수거처럼 집을 굴러가게 하는 일.',
    LifeDomain.activity:
        '신체활동 — 운동, 걷기, 달리기, 스트레칭, 요가, 헬스처럼 몸을 움직이는 일. 잠이나 식사는 여기 들어가지 않음.',
    LifeDomain.selfCare:
        '자기관리 — 씻기, 양치, 피부와 머리 관리, 옷차림, 영양제와 물 마시기, 잠들기 전에 하는 것들처럼 자기 몸을 챙기는 일. 운동은 여기 들어가지 않음.',
  };

  /// [names] 중 [domain]에 속하는 것들의 번호(0부터).
  ///
  /// 못 물어봤으면 null. 빈 집합과 갈라야 한다 — 빈 집합은 "담당인 게 없다"는
  /// 답이고 null은 "아직 모른다"라서, 둘을 섞으면 통신이 한 번 끊긴 것 때문에
  /// 한 달 내내 담당 루틴이 없는 사람이 된다.
  static Future<Set<int>?> pick({
    required LifeDomain domain,
    required List<String> names,
  }) async {
    if (names.isEmpty) return const {};
    final asked = names.take(maxNames).toList(growable: false);

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': _prompt(domain: domain, asked: asked)},
    ];

    return _ask(messages, count: asked.length, tag: 'routine_domain_check');
  }

  /// [names] 중 무슨 운동인지 이름만 보고 알 수 있는 것들의 번호(0부터).
  ///
  /// 설문에서 "지금 따로 하는 운동이 있어?"를 물을 때 쓴다. '요가'나 '수영'은
  /// 보기에 채워 확인만 받으면 되지만, '운동 30분'처럼 종목이 안 적힌 이름이
  /// 훨씬 흔하다. 그때는 문항을 그대로 묻는 편이 낫다 — 애매한 이름을 보기로
  /// 내밀면 사용자가 무엇을 고르는 건지 알 수 없다.
  static Future<Set<int>?> namedSports(List<String> names) async {
    if (names.isEmpty) return const {};
    final asked = names.take(maxNames).toList(growable: false);

    final buffer = StringBuffer('[할 일 이름]\n');
    for (var i = 0; i < asked.length; i++) {
      buffer.writeln('${i + 1}. ${asked[i]}');
    }
    buffer.writeln();
    buffer.writeln(
      '이 중에서 무슨 운동인지 이름만 보고 알 수 있는 것의 번호만 쉼표로 적으세요. '
      '해당하는 것이 없으면 NONE만 적으세요. 번호와 쉼표, 또는 NONE 외에는 아무것도 적지 마세요.',
    );
    buffer.writeln();
    buffer.writeln('- 종목이 드러나면 알 수 있는 것입니다. 예: "요가", "수영", "아침 달리기".');
    buffer.writeln('- 종목 없이 분량이나 시간만 적힌 것은 알 수 없는 것입니다. 예: "운동 30분", "홈트".');
    buffer.writeln('- 운동이 아닌 이름은 고르지 마세요.');

    final messages = [
      {'role': 'system', 'content': _system},
      {'role': 'user', 'content': buffer.toString()},
    ];

    return _ask(messages, count: asked.length, tag: 'named_sports_check');
  }

  /// 그 코치 담당인 루틴을 다시 가르고 프로필에 적는다.
  ///
  /// 못 물어봤으면 적어두지 않고 지난번에 가른 것을 그대로 돌려준다. 다음
  /// 기회에 다시 묻게 된다.
  static Future<Set<String>> refresh({
    required String coachId,
    required List<Map<String, dynamic>> habits,
    DateTime? now,
  }) async {
    final domain = LifePatternService.domains[coachId];
    if (domain == null) return const {};

    final usable = habits
        .where((habit) => (habit['name']?.toString().trim() ?? '').isNotEmpty)
        .where((habit) => (habit['id']?.toString() ?? '').isNotEmpty)
        .take(maxNames)
        .toList(growable: false);
    if (usable.isEmpty) {
      await LifePatternService.saveDomainHabitIds(coachId, {}, now: now);
      return const {};
    }

    final picked = await pick(
      domain: domain,
      names: usable
          .map((habit) => habit['name'].toString())
          .toList(growable: false),
    );
    // 못 물어봤으면 적어두지 않는다. 적어두면 가른 시각이 찍혀서 한 달 동안
    // 다시 묻지 않게 되고, 그동안 이 코치는 담당 루틴이 하나도 없는 채로 돈다.
    if (picked == null) return LifePatternService.domainHabitIds(coachId);
    final ids = <String>{
      for (var i = 0; i < usable.length; i++)
        if (picked.contains(i)) usable[i]['id'].toString(),
    };
    await LifePatternService.saveDomainHabitIds(coachId, ids, now: now);
    return ids;
  }

  static String _prompt({
    required LifeDomain domain,
    required List<String> asked,
  }) {
    final buffer = StringBuffer('[영역]\n');
    buffer.writeln(_descriptions[domain] ?? '');
    buffer.writeln();
    buffer.writeln('[할 일 이름]');
    for (var i = 0; i < asked.length; i++) {
      buffer.writeln('${i + 1}. ${asked[i]}');
    }
    buffer.writeln();
    buffer.writeln(
      '이 중에서 위 영역에 속하는 것의 번호만 쉼표로 적으세요. '
      '해당하는 것이 없으면 NONE만 적으세요. 번호와 쉼표, 또는 NONE 외에는 아무것도 적지 마세요.',
    );
    buffer.writeln();
    buffer.writeln('- 이름이 달라도 하는 일이 그 영역이면 속합니다. 예: "이불 널기"는 살림.');
    buffer.writeln('- 두 영역에 걸치면 더 가까운 쪽 하나만 고르세요.');
    buffer.writeln('- 애매하면 고르지 마세요. 남의 영역에 참견하는 것보다 조용한 편이 낫습니다.');
    return buffer.toString();
  }

  /// 못 물어봤으면 null. 답을 못 읽었으면 빈 집합이다.
  static Future<Set<int>?> _ask(
    List<Map<String, String>> messages, {
    required int count,
    required String tag,
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
        coachId: tag,
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
      // 한도가 찼거나 통신이 끊긴 경우다. 담당이 없는 것이 아니라 모르는
      // 것이라, 부르는 쪽이 다음에 다시 묻게 둔다.
      return null;
    }
  }
}
