/// 쏟아낸 말을 코치가 항목으로 쪼개고 오늘 하루를 짜준 결과.
///
/// 머리가 복잡할 때는 항목으로 쪼개는 일 자체가 부하다. 말은 나오는데 목록으로
/// 는 안 써진다. 그래서 주절거린 것을 그대로 받아 코치가 쪼갠다.
///
/// 쪼개기만 하면 할 일 탭에 적는 것과 다를 게 없다. 여기서 값어치가 나는 곳은
/// 두 군데다.
///
/// **이미 있는 것을 짚어준다.** 머리가 복잡한 이유 중 하나가 뭘 해뒀는지
/// 기억이 안 나서다. 쏟아내다 보면 오늘 이미 끝낸 것도 같이 나온다. 그걸
/// 알려주면 덜어내는 것보다 가볍다 - 할 일이 줄어드는 게 아니라 이미 줄어
/// 있었다는 걸 알게 되는 것이다.
///
/// **두 가지 안을 내놓는다.** 열 개를 하나씩 판단하는 대신 둘 중 하나를 고르게
/// 한다. 그것도 남이 낸 안을 고르는 것이라 부담이 훨씬 적다. 두 안은 순서만
/// 달라서는 안 되고 전략이 달라야 한다 - 급한 것부터 가는 길과 만만한 것부터
/// 가는 길은 날마다 맞는 쪽이 다르다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

/// 쏟아낸 것 중 이미 처리돼 있던 항목.
@immutable
class BrainDumpKnown {
  const BrainDumpKnown({
    required this.name,
    required this.kind,
    this.note = '',
  });

  final String name;

  /// done(오늘 끝냄) · started(손댔음) · listed(오늘 목록에 있음) ·
  /// routine(루틴으로 돌고 있음) · planned(다른 날에 잡아둠)
  final String kind;

  /// "아침 8시에", "내일로 옮겨둠"처럼 덧붙일 한마디.
  final String note;

  static BrainDumpKnown? from(Map<String, dynamic> raw) {
    final name = raw['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    return BrainDumpKnown(
      name: name,
      kind: raw['kind']?.toString().trim() ?? 'listed',
      note: raw['note']?.toString().trim() ?? '',
    );
  }
}

/// 오늘을 지나갈 한 가지 방법.
@immutable
class BrainDumpPlanOption {
  const BrainDumpPlanOption({
    required this.label,
    required this.why,
    required this.today,
  });

  /// "급한 것부터"처럼 이 안이 어떤 길인지.
  final String label;

  /// 왜 이 길인지 한 줄. 이게 없으면 고를 근거가 없다.
  final String why;

  /// 오늘 할 것을 할 순서대로.
  final List<String> today;

  static BrainDumpPlanOption? from(Map<String, dynamic> raw) {
    final today = (raw['today'] as List?)
        ?.map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (today == null || today.isEmpty) return null;
    return BrainDumpPlanOption(
      label: raw['label']?.toString().trim() ?? '',
      why: raw['why']?.toString().trim() ?? '',
      today: today,
    );
  }
}

@immutable
class BrainDumpPlan {
  const BrainDumpPlan({
    required this.options,
    this.known = const [],
    this.batchMinutes,
    this.batch = const [],
    this.later = const [],
    this.drop = '',
  });

  /// 고를 수 있는 안. 둘이 보통이고, 하나뿐이면 고르는 자리 없이 그것만 낸다.
  final List<BrainDumpPlanOption> options;

  /// 이미 끝냈거나 목록에 있던 것들.
  final List<BrainDumpKnown> known;

  /// 묶어서 한 번에 해치울 것들과 거기 줄 시간.
  final int? batchMinutes;
  final List<String> batch;

  /// 오늘 말고 다른 날로 미뤄둘 것들.
  final List<String> later;

  /// 빼도 될 것 같아 물어볼 항목 하나. 없으면 빈 문자열.
  ///
  /// 하나만 둔다. "이것도 저것도 뺄까?"는 또 여러 번 결정이다.
  final String drop;

  bool get isUsable => options.isNotEmpty;

  /// 이 안을 고르면 오늘 목록에 들어갈 것들. 순서 그대로.
  List<String> todayNamesOf(BrainDumpPlanOption option) => [
    ...option.today,
    ...batch,
  ];
}

class BrainDumpPlanner {
  const BrainDumpPlanner._();

  static const String model = 'gpt-5-mini';

  /// 쏟아낸 말을 계획으로 바꾼다. 못 만들었으면 null.
  ///
  /// [alreadyBlock]은 앱이 미리 찾아둔 겹침이다. 코치가 지어내지 않도록 앱이
  /// 찾은 것만 넘긴다.
  static Future<BrainDumpPlan?> compose({
    required String coachId,
    required String dumped,
    required String alreadyBlock,
    required int recentMax,
    String urgentNote = '',
    String goalBlock = '',
  }) async {
    if (dumped.trim().isEmpty) return null;

    final coach = CoachConfigs.get(coachId);
    final prompt =
        '''${coach.systemPrompt}

[사용자가 방금 쏟아낸 말]
$dumped

[앱이 찾아둔 것 - 여기 없는 것은 지어내지 마세요]
$alreadyBlock$goalBlock
[참고]
- 이 사람이 최근 이레 동안 하루에 가장 많이 해낸 것은 ${recentMax}개입니다.
${urgentNote.isEmpty ? '' : '- 사용자가 급하다고 말한 것: $urgentNote\n'}
[이번에 할 일]
쏟아낸 말을 할 일 항목으로 쪼개고, 오늘을 지나갈 방법을 두 가지로 짜세요.

- 이름은 짧은 명사형으로 다듬으세요. 말한 그대로 옮기지 마세요.
- [앱이 찾아둔 것]에 있는 항목은 오늘 목록에 다시 넣지 마세요. known에만 적습니다.
- 두 안은 전략이 달라야 합니다. 순서만 바꾼 두 안은 고를 이유가 없습니다.
  - 하나는 급하거나 마음에 걸리는 것부터 가는 길
  - 하나는 만만한 것부터 시동을 걸어 올라가는 길
- 오늘 할 것은 이 사람이 최근에 해내던 양을 크게 넘기지 마세요.
- 짧게 끝나는 것들은 batch로 묶습니다. 두세 가지를 묶고, 묶은 양을 보고 20분이나 30분을 주세요. 하나뿐이면 묶지 말고 오늘 목록에 그냥 두세요.
- 오늘 안 해도 될 것은 later에 넣으세요.
- 아예 안 해도 될 것 같은 게 있으면 drop에 하나만 적으세요. 없으면 비웁니다.
- why는 왜 그 길인지 한 줄입니다. 없으면 고를 근거가 없습니다.

아래 형식의 JSON만 답하세요. 설명이나 인사말을 붙이지 마세요.
{"known":[{"name":"","kind":"done|started|listed|routine|planned","note":""}],
"options":[{"label":"","why":"","today":["",""]},{"label":"","why":"","today":["",""]}],
"batch":{"minutes":0,"names":[]},"later":[],"drop":""}''';

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

      debugPrint('[braindump] 코치에게 보냄 (${dumped.length}자)');
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('chatProxy');
      // 시간 제한을 둔다. 답이 안 오면 로딩 표시가 영영 안 풀려서, 사용자는
      // 다 말해놓고 멈춘 화면만 보게 된다.
      final response = await callable
          .call({
            'messages': messages,
            'model': model,
            'temperature': 0.5,
          })
          .timeout(const Duration(seconds: 45));

      final data = response.data;
      final content = (data is Map ? data['content'] : null)?.toString() ?? '';

      // 사용 기록은 기다리지 않는다. 서버에 적는 일이라, 인터넷이 느리면
      // 여기서 멈춰 로딩 표시가 안 풀린다. 사용자에게 중요한 건 계획이다.
      final usageData = data is Map ? data : const {};
      unawaited(
        AnalyticsService.logApiUsage(
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
          usageSource: 'brain_dump',
        ),
      );

      final plan = parse(content);
      if (plan == null) {
        debugPrint(
          '[braindump] 읽기 실패. 받은 것: '
          '${content.length > 300 ? content.substring(0, 300) : content}',
        );
      } else {
        debugPrint('[braindump] 안 ${plan.options.length}개, 겹침 ${plan.known.length}개');
      }
      return plan;
    } catch (e) {
      debugPrint('[braindump] 실패: $e');
      return null;
    }
  }

  /// 코치 답을 계획으로 읽는다. 못 읽으면 null.
  ///
  /// 앞뒤에 말이 붙어 와도 중괄호 구간만 떼어 읽는다. 형식만 답하라고 해도
  /// "여기 있다냥" 한 줄을 붙이는 일이 있다.
  @visibleForTesting
  static BrainDumpPlan? parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;

    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(raw.substring(start, end + 1));
      if (value is! Map) return null;
      decoded = Map<String, dynamic>.from(value);
    } catch (_) {
      return null;
    }

    final options = <BrainDumpPlanOption>[];
    for (final item in (decoded['options'] as List?) ?? const []) {
      if (item is! Map) continue;
      final option = BrainDumpPlanOption.from(Map<String, dynamic>.from(item));
      if (option != null) options.add(option);
    }
    if (options.isEmpty) return null;

    final known = <BrainDumpKnown>[];
    for (final item in (decoded['known'] as List?) ?? const []) {
      if (item is! Map) continue;
      final entry = BrainDumpKnown.from(Map<String, dynamic>.from(item));
      if (entry != null) known.add(entry);
    }

    final batchRaw = decoded['batch'];
    var batchNames = const <String>[];
    int? batchMinutes;
    if (batchRaw is Map) {
      batchNames = ((batchRaw['names'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final minutes = (batchRaw['minutes'] as num?)?.toInt() ?? 0;
      if (minutes > 0 && batchNames.isNotEmpty) batchMinutes = minutes;
      if (batchNames.isEmpty) batchMinutes = null;
    }

    return BrainDumpPlan(
      options: options,
      known: known,
      batchMinutes: batchMinutes,
      batch: batchNames,
      later: ((decoded['later'] as List?) ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false),
      drop: decoded['drop']?.toString().trim() ?? '',
    );
  }
}
