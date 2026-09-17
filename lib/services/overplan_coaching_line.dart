/// 계획이 평소보다 훨씬 많은 날, 그 목록을 어떻게 다룰지 코치가 짓는다.
///
/// 앞에 고정 문구가 먼저 나간다([OverplanNudgeService.opening]). 거기서는
/// 상태를 짚고 기다리라고만 하고, 무엇을 어떻게 할지는 여기서 짓는다.
///
/// 고정 문구로 못 쓰는 자리다. 이 말에는 오늘 목록에 실제로 들어 있는 일
/// 이름과 소요 시간이 들어가야 한다. "하나만 골라보자" 수준으로 쓸 거면
/// 애초에 할 이유가 없다 - 그건 이미 사용자도 아는 말이다.
///
/// **줄이라고 하지 않는다.** 계획이 많은 이유는 여럿이고 앱은 그것을 가릴 수
/// 없다. 진짜 다 해야 하는 사람에게 "줄여라"는 틀린 말이고, 머릿속을 다
/// 쏟아낸 사람에게는 목록이 문제가 아니라 섞여 있다는 것이 문제다. 그 판단은
/// 이 사람 목록을 읽고 코치가 한다.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

/// 오늘 목록에 든 일 하나. 코치에게 넘길 만큼만 담는다.
@immutable
class OverplanTask {
  const OverplanTask({
    required this.name,
    required this.isRoutine,
    this.done = false,
    this.started = false,
    this.duration,
    this.time,
  });

  final String name;

  /// 루틴에서 온 줄인지. 루틴은 매일 돌아오는 것이라 하루 미루는 뜻이 다르다.
  final bool isRoutine;

  final bool done;

  /// 끝내지는 못했어도 오늘 손을 댄 일인지.
  ///
  /// 손댄 일과 손도 안 댄 일은 무게가 다르다. 이미 붙잡고 있는 것을 밀라고
  /// 하면 방금까지 한 일을 없던 것으로 만드는 말이 된다.
  final bool started;

  /// '30분'처럼 적어둔 소요 시간. 없으면 null.
  final String? duration;

  /// 시각이 붙어 있으면 그 표시.
  final String? time;

  String get promptLine {
    final marks = <String>[
      if (isRoutine) '루틴',
      if (time != null && time!.isNotEmpty) time!,
      if (duration != null && duration!.isNotEmpty) duration!,
      if (done)
        '오늘 끝냄'
      else if (started)
        '오늘 손댔지만 아직 안 끝남',
    ];
    return marks.isEmpty ? '- $name' : '- $name (${marks.join(', ')})';
  }
}

class OverplanCoachingLine {
  const OverplanCoachingLine._();

  static const String model = 'gpt-5-mini';

  /// 건넬 말. 못 지었으면 null - 그때는 부르는 쪽이 고정 문구로 마무리한다.
  static Future<String?> compose({
    required String coachId,
    required List<OverplanTask> tasks,
    required int recentMax,
  }) async {
    final remaining = tasks.where((task) => !task.done).toList();
    if (remaining.isEmpty) return null;
    final doneCount = tasks.length - remaining.length;

    final coach = CoachConfigs.get(coachId);
    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
- 오늘 목록은 ${tasks.length}개이고, 그중 ${doneCount}개를 끝냈습니다.
- 이 사람이 최근 이레 동안 하루에 가장 많이 해낸 것은 ${recentMax}개입니다.
- 방금 "평소보다 계획이 많네, 정신없겠다. 잠깐 기다려봐"라고 말해둔 참입니다.

[오늘 목록]
${tasks.map((task) => task.promptLine).join('\n')}

[앱이 할 수 있는 것]
- 할 일은 다른 날짜로 옮길 수 있습니다. 오늘 탭에서 그 줄을 길게 누르면 됩니다.
- 할 일마다 걸릴 시간을 정해둘 수 있습니다.
- 답변 끝에 [OPEN: 오늘]을 붙이면 오늘 탭이 열립니다. 사용자가 바로 손을 대야 할 때만 붙이세요.

[이번에 할 말]
위 목록을 보고, 오늘을 어떻게 지나갈지 말하세요.

- **한 문장에 여러 가지를 넣지 마세요.** 옮기고 시간 정하고 몰아서 하라는 말을 한 문장에 이어 붙이면 읽다가 앞을 잊습니다. 하나씩 끊어서 말하세요.
- 일 이름을 불러 가며 말하세요. 위 목록에 있는 이름만 씁니다.
- "줄여라"라고 하지 마세요. 무엇을 덜지는 사용자가 정합니다. 코치는 어떻게 다룰지를 말합니다.
- 개수나 퍼센트를 들이대지 마세요. 앞줄에서 이미 많다고 말했습니다.
- 루틴은 매일 돌아오는 것이라 하루 건너뛰어도 사라지지 않습니다. 손으로 적은 일과 무게가 다릅니다.
- 이미 손댄 일을 뒤로 미루라고 하지 마세요. 붙잡고 있던 것을 놓게 하면 오늘 한 일이 없던 것이 됩니다.
- 끝낸 일은 다시 하라고 하지 마세요.
- 다 해내라고 몰아붙이지도, 포기하라고 하지도 마세요.
- 인사말로 시작하지 마세요. 하려던 이야기부터 하세요.
- 말끝을 겹쳐 쓰지 마세요. 이 코치의 말투 그대로 한 번만 맺습니다.''';

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
        usageSource: 'overplan_greeting',
      );

      final cleaned = content.trim();
      return cleaned.isEmpty ? null : cleaned;
    } catch (e) {
      debugPrint('overplan coaching line failed: $e');
      return null;
    }
  }
}
