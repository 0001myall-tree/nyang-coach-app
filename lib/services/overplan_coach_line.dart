/// 계획이 많아졌을 때 건네는 말을, 이 사람 기록을 근거로 코치가 짓는다.
///
/// 고정 문구는 늘 같은 말을 한다. "다 하려고 하기보다 하나만 먼저 골라볼까"는
/// 맞는 말이지만 **남의 말**이라, 듣는 사람은 동의하고 그대로 여덟 개를 적는다.
/// 동의한 것은 일반론이지 자기 이야기가 아니기 때문이다.
///
/// 부딪히게 하려면 재료가 본인 것이어야 한다. 아침에 두 시간뿐이라고 **본인이**
/// 고른 답, 그날 **본인이** 적은 개수, **본인이** 해낸 개수. 셋을 나란히 놓으면
/// 빠져나갈 구멍이 없다. 코치가 "많다"고 한 적이 없으니 반박할 대상도 없다.
///
/// 말은 세 줄로 짓는다.
/// 1. 사실 - 판단 없이 숫자만
/// 2. 이름 바꾸기 - 성격 이야기를 방식 이야기로
/// 3. 작은 제안 - 하루짜리라 정체성을 건드리지 않는다
///
/// 2번이 이 자리의 핵심이다. 여덟 개 적고 두 개 한 사람은 이미 스스로에게
/// 라벨을 붙여뒀다 - "나 게으르다". 숫자만 보여주면 그 라벨이 더 굳는다.
/// 증거가 하나 더 생기는 셈이기 때문이다. 라벨을 떼주는 것은 코치만 할 수 있다.
///
/// 자리는 계획을 적는 때다. 저녁이 아니다 - 되짚는 말은 그것으로 지금 무언가를
/// 정할 수 있을 때만 뜻이 있는데, 저녁에는 정할 것이 없어서 아프기만 하다.
library;

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'coach_id_service.dart';
import 'day_capacity_service.dart';
import 'overplan_nudge_service.dart';

/// 하루치 근거. 아침 답과 그날 결과가 둘 다 있는 날이다.
@immutable
class OverplanEvidence {
  const OverplanEvidence({
    required this.dateLabel,
    required this.capacityLine,
    required this.planned,
    required this.done,
  });

  /// 사람이 읽을 날 이름. '어제' 또는 '지난 화요일'처럼.
  final String dateLabel;

  /// 그날 아침에 고른 답을 코치에게 넘길 한 줄.
  final String capacityLine;

  final int planned;
  final int done;
}

class OverplanCoachLine {
  const OverplanCoachLine._();

  static const String model = 'gpt-5-mini';

  /// 근거를 이만큼 지난 날까지만 찾는다.
  ///
  /// 2주 전 하루를 꺼내면 "언제 적 이야기냐"가 된다. 그때의 사정은 본인도
  /// 기억나지 않아서, 근거로 내밀어도 남의 이야기처럼 들린다.
  static const int evidenceWithinDays = 10;

  /// 이 자리를 코치가 짓는 코치들.
  ///
  /// 나머지는 고정 문구를 쓴다. 말투를 살려 짓는 데 값이 드는 자리라, 기본
  /// 코치와 마스터에만 연다.
  static bool speaks(String coachId) {
    final id = CoachIdService.normalize(coachId);
    return id == CoachIdService.defaultCoachId || CoachIdService.isMaster(id);
  }

  /// 아침 답과 그날 결과가 둘 다 있는 가장 가까운 날. 없으면 null.
  ///
  /// 아침 질문은 사흘에 한 번만 나가고 답을 안 고르고 넘기는 날도 있어서,
  /// 대부분의 경우 없다. 없는 것이 예외가 아니라 보통이다.
  static Future<OverplanEvidence?> findEvidence({
    required String? historyRaw,
    DateTime? now,
  }) async {
    if (historyRaw == null || historyRaw.isEmpty) return null;
    final answers = await DayCapacityService.recentAnswers();
    if (answers.isEmpty) return null;

    List<dynamic> history;
    try {
      final decoded = jsonDecode(historyRaw);
      if (decoded is! List) return null;
      history = decoded;
    } catch (_) {
      return null;
    }

    final today = now ?? DateTime.now();
    final todayKey = _dateKey(today);
    OverplanEvidence? best;
    var bestDate = '';

    for (final item in history) {
      if (item is! Map) continue;
      final dateKey = item['date']?.toString() ?? '';
      // 오늘은 아직 안 끝났다. 지금까지 해낸 것만 세면 그날 하루를 지켜보지도
      // 않고 못 했다고 적는 셈이다.
      if (dateKey.isEmpty || dateKey == todayKey) continue;
      final answer = answers[dateKey];
      if (answer == null) continue;
      final date = DateTime.tryParse(dateKey);
      if (date == null) continue;
      if (today.difference(date).inDays > evidenceWithinDays) continue;
      final planned = (item['totalCount'] as num?)?.toInt() ?? 0;
      // 적은 것이 몇 개 안 되는 날은 근거가 못 된다. 계획이 많았다는 이야기를
      // 하려는 자리인데 그날은 많지 않았다.
      if (planned < DayCapacityService.asksFromPlanCount) continue;
      if (dateKey.compareTo(bestDate) <= 0) continue;

      bestDate = dateKey;
      best = OverplanEvidence(
        dateLabel: _dayLabel(today, date),
        capacityLine: DayCapacityService.answers[answer] ?? '',
        planned: planned,
        done: (item['doneCount'] as num?)?.toInt() ?? 0,
      );
    }
    return best;
  }

  /// 건넬 말. 못 지었으면 null - 그때는 부르는 쪽이 고정 문구로 간다.
  static Future<String?> compose({
    required String coachId,
    required int plannedCount,
    required int recentMax,
    required OverplanTone tone,
    OverplanEvidence? evidence,
    String typeLine = '',
  }) async {
    if (!speaks(coachId)) return null;

    final coach = CoachConfigs.get(coachId);
    final evidenceBlock = evidence == null
        ? '- 오늘 ${plannedCount}개를 적었음. 최근에 실제로 해낸 하루 최대치는 ${recentMax}개.\n'
        : '- 오늘 ${plannedCount}개를 적었음. 최근에 실제로 해낸 하루 최대치는 ${recentMax}개.\n'
              '- ${evidence.dateLabel} 아침에 사용자가 직접 고른 답: ${evidence.capacityLine}\n'
              '- 그런데 ${evidence.dateLabel} 적은 것은 ${evidence.planned}개였고, '
              '해낸 것은 ${evidence.done}개.\n';

    final prompt =
        '''${coach.systemPrompt}
$typeLine
[지금 상황 - 사용자가 오늘 할 일을 적고 있는 중]
$evidenceBlock${_toneLine(tone)}

[이번에 할 말]
세 줄로 말하세요. 한 줄씩 역할이 다릅니다.

1. 사실. 위 숫자를 그대로 되읽어 주세요. 판단이나 평가는 붙이지 않습니다.
2. 이름 바꾸기. 사용자는 스스로를 "게으르다", "의지가 없다", "끈기가 없다"고 여기고 있을 가능성이 큽니다. 성격이 아니라 방식의 문제라고 바꿔 말해 주세요. 성격은 못 바꾸지만 방식은 내일 바꿔볼 수 있습니다.
3. 작은 제안. 오늘 하루만 해볼 크기로 권하세요. 앞으로 계속 그러라는 말은 사람을 바꾸라는 말이라 거부당합니다.

말투 예시입니다. 길이와 결을 이만큼으로 맞추세요.
- "어제 두 시간밖에 없다고 했는데 8개 적었고 2개 했었어. 게을러서가 아니라 그냥 많이 적은 거야. 오늘은 3개만 적고 시작해볼래?"
- "너 게으른 거 아니야. 그냥 하루에 너무 많이 적어."
- "끈기 없는 거 아니고, 한 번에 하려는 게 너무 커."

비유는 쓰지 않습니다. "첫 칸이 무겁다", "한 덩이가 크다" 같은 말은 사람이 쓰지 않는 말이라 바로 티가 납니다. 있는 말로 짧게 쓰세요.
위에 적힌 숫자만 쓰고, 없는 숫자는 만들지 마세요. 태그는 붙이지 않습니다.''';

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

      return clean(content);
    } catch (e) {
      debugPrint('overplan coach line failed: $e');
      return null;
    }
  }

  /// 남은 태그를 떼어낸다. 빈손이면 null.
  ///
  /// 이 말은 다이얼로그에 그대로 꽂혀서, 대괄호가 남으면 사용자에게 그대로
  /// 보인다.
  @visibleForTesting
  static String? clean(String raw) {
    final stripped = raw
        .replaceAll(RegExp(r'\[[A-Z_]+(?::[^\]]*)?\]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return stripped.isEmpty ? null : stripped;
  }

  static String _toneLine(OverplanTone tone) => switch (tone) {
    OverplanTone.restart =>
      '- 최근에 해낸 날이 거의 없다가 다시 잡는 중입니다. 숫자로 지적하지 말고, '
          '다시 시작하는 것을 먼저 반겨 주세요.',
    OverplanTone.gentle => '- 이 이야기를 처음 꺼내는 자리입니다.',
    OverplanTone.direct =>
      '- 부드럽게 말한 적이 있는데 또 같은 자리에 왔습니다. 조금 더 분명하게 말해도 됩니다.',
  };

  /// '어제' 또는 '지난 화요일'.
  static String _dayLabel(DateTime today, DateTime date) {
    final days = DateTime(
      today.year,
      today.month,
      today.day,
    ).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days == 1) return '어제';
    if (days == 2) return '그저께';
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    return '지난 ${names[date.weekday - 1]}요일';
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';
}
