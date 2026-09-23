/// 지금 이 일에 손대게 만드는 한 수를 받아온다.
///
/// 틈새 코칭이 쓰던 호출과 같은 자리인데, 형식 제약을 풀었다. 저쪽은 "10분 안에
/// 끝나는 조각 하나"라고 못 박혀 있어서 무슨 일이든 **작게 자르는 답**만 나온다.
/// 그러면 "5분만"이 들키고, 쪼개도 소용없는 사람에게 또 쪼개준다.
///
/// 목적만 준다 — *사용자의 상황에서 이 일에 손대게 만드는 한 수*. 그 안에
/// 쪼개기도 들어가고, 첫 문장을 대신 써주는 것도, 순서를 정해주는 것도, 기준을
/// 낮추는 것도 들어간다. 무엇이 맞는지는 그 일과 그 사람의 오늘이 정한다.
/// 갈래를 앱이 나눠두면 갈래가 안 맞는 사람에게 엉뚱한 말이 나간다.
///
/// **둘까지 받는다.** 앱은 사용자가 지금 어디에 있는지 모른다. 하나만 내면 그
/// 자리가 아닐 때 그걸로 끝나므로, 되는 자리가 다른 둘을 나란히 받아 고르게
/// 한다. 하나만 주면 "할래 말래"가 되고, 둘을 주면 "어느 쪽"이 된다.
///
/// 고르는 일까지 맡길 수도 있다. 사용자가 "모르겠어"라고 했을 때 남은 일을 전부
/// 넘기면, 그중 지금 제일 만만한 것을 골라 한 수까지 붙여 온다.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

/// 넘기는 일 하나.
class ActiveCoachingCandidate {
  const ActiveCoachingCandidate({
    required this.name,
    this.timeLabel,
    this.started = false,
  });

  final String name;

  /// "오후 7:00" 꼴. 시각이 없는 일은 null.
  final String? timeLabel;

  /// 이미 손을 댄 일인지. 이어갈 자리가 있는 것과 아직 첫 발인 것은 다르다.
  final bool started;

  String get line {
    final marks = [if (timeLabel != null) '$timeLabel 시작', if (started) '하는 중'];
    return marks.isEmpty ? name : '$name (${marks.join(', ')})';
  }
}

/// 고른 일과, 지금 그 일에 둘 수 있는 한 수들.
class ActiveCoachingMoves {
  const ActiveCoachingMoves({required this.task, required this.moves});

  /// 넘긴 목록에 있던 이름 그대로.
  final String task;

  /// 한 줄짜리 한 수. 하나 아니면 둘이다.
  final List<String> moves;
}

class ActiveCoachingMove {
  const ActiveCoachingMove._();

  static const String model = 'gpt-5-mini';

  /// 버튼 한 줄에 들어가는 길이. 넘치면 버튼이 두 줄이 되어 고르기가 어려워진다.
  static const int maxMoveLength = 16;

  /// 한 번에 견주는 개수. 넘으면 앞에서부터 자른다.
  static const int maxCandidates = 10;

  /// 한 번에 받는 한 수의 개수.
  ///
  /// 셋이면 고르는 것도 일이 된다. 카드 버튼도 셋이 상한이라 자리가 맞는다.
  static const int maxMoves = 2;

  static const String _system =
      '당신은 지금 손이 안 가는 일 하나에, 그 사람이 지금 있는 자리에서 바로 할 수 '
      '있는 한 수를 내는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// 한 수를 받아온다. 못 받아왔으면 null.
  ///
  /// [candidates]가 하나면 그 일로 고정이고, 여럿이면 고르는 것까지 맡긴다.
  /// [situation]은 그 시각에 무엇에 매여 있는지. [reason]은 사용자가 고른
  /// "왜 못 했는지"다 — 이게 다음 한 수를 가른다. 쪼개면 되는 이유와 자리가
  /// 아닌 이유는 처방이 다르다.
  static Future<ActiveCoachingMoves?> suggest({
    required List<ActiveCoachingCandidate> candidates,
    required DateTime at,
    String? situation,
    String? reason,
  }) async {
    final asked = candidates
        .where((item) => item.name.trim().isNotEmpty)
        .take(maxCandidates)
        .toList(growable: false);
    if (asked.isEmpty) return null;

    final messages = [
      {'role': 'system', 'content': _system},
      {
        'role': 'user',
        'content': _prompt(
          candidates: asked,
          at: at,
          situation: situation,
          reason: reason,
        ),
      },
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
        'temperature': 0.3,
      });

      final data = response.data;
      final content = (data is Map ? data['content'] : null)?.toString() ?? '';

      final usageData = data is Map ? data : const {};
      await AnalyticsService.logApiUsage(
        coachId: 'active_coaching_move',
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

      return read(
        content,
        asked.map((item) => item.name).toList(growable: false),
      );
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 부르는 쪽이 한 수 없이 간다.
      return null;
    }
  }

  /// 답에서 고른 일과 한 수들을 꺼낸다. 쓸 수 없으면 null.
  ///
  /// 목록에 없는 이름은 버린다. 지어낸 일을 카드가 불러주면 사용자는 적은 적
  /// 없는 일을 보게 된다.
  static ActiveCoachingMoves? read(String raw, List<String> candidates) {
    final lines = raw
        .split('\n')
        .map(_unwrap)
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return null;
    if (lines.first.toUpperCase() == 'NONE') return null;
    if (lines.length < 2) return null;

    final task = lines.first;
    if (!candidates.contains(task)) return null;

    final moves = <String>[];
    for (final line in lines.skip(1)) {
      final move = readMove(line);
      if (move == null) continue;
      // 같은 말을 두 번 내놓으면 고를 것이 없는 것과 같다.
      if (moves.contains(move)) continue;
      moves.add(move);
      if (moves.length >= maxMoves) break;
    }
    if (moves.isEmpty) return null;
    return ActiveCoachingMoves(task: task, moves: moves);
  }

  /// 한 줄에서 한 수만 꺼낸다. 쓸 수 없으면 null.
  ///
  /// 형식을 지킨다는 전제로 좁게 잡지 않는다. 따옴표나 마침표, 앞에 붙는 번호
  /// 정도는 흔한데 그걸로 통째로 버리면 멀쩡한 답이 사라진다.
  static String? readMove(String raw) {
    var text = _unwrap(raw);
    if (text.isEmpty) return null;
    // "1. 개요 잡기", "- 개요 잡기"처럼 앞에 붙여 오는 것들.
    text = _unwrap(text.replaceFirst(RegExp(r'^\s*(?:[-*·]|\d+[.)])\s*'), ''));
    if (text.isEmpty) return null;
    if (text.toUpperCase() == 'NONE') return null;
    // 설명을 붙여 오면 버튼에 안 들어간다.
    if (text.length > maxMoveLength) return null;
    return text;
  }

  /// "오후 3:30".
  static String _clock(DateTime at) {
    final meridiem = at.hour >= 12 ? '오후' : '오전';
    final hour = at.hour > 12 ? at.hour - 12 : (at.hour == 0 ? 12 : at.hour);
    return '$meridiem $hour:${at.minute.toString().padLeft(2, '0')}';
  }

  static String _unwrap(String raw) =>
      raw.trim().replaceAll(RegExp(r'''^["'`\s]+|["'`\s.。!?]+$'''), '');

  static String _prompt({
    required List<ActiveCoachingCandidate> candidates,
    required DateTime at,
    String? situation,
    String? reason,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('[지금]');
    buffer.writeln('- 시각: ${_clock(at)}');
    buffer.writeln(
      situation == null ? '- 매여 있는 시간대가 아님' : '- 매여 있는 시간대: $situation',
    );
    // 이유가 처방을 가른다. 머리가 안 돌아가는 사람에게는 손댈 자리를 만들어
    // 주면 되고, 회의 중인 사람에게는 무엇을 해줘도 소용없다. 물어놓고 안
    // 넘기면 물어본 의미가 없다.
    if (reason != null && reason.trim().isNotEmpty) {
      buffer.writeln('- 사용자가 말한 못 한 이유: ${reason.trim()}');
    }
    buffer.writeln();

    if (candidates.length == 1) {
      buffer.writeln('[이 일]');
    } else {
      buffer.writeln('[남은 일]');
    }
    for (final item in candidates) {
      buffer.writeln('- ${item.line}');
    }
    buffer.writeln();

    buffer.writeln(
      '사용자가 이 일에 손을 못 대고 있습니다. 지금 있는 자리에서 바로 시작할 수 있는 '
      '한 수를 내는 것이 목적입니다. 일을 끝내라는 말이 아니라, 지금 이 순간 손이 '
      '움직이게 만드는 첫 동작을 정해주는 자리입니다.',
    );
    buffer.writeln();
    if (candidates.length > 1) {
      // 고르는 기준은 중요도가 아니다. 무엇이 중요한지는 앱도 모르고, 지금
      // 필요한 것은 실제로 시작되는 하나다.
      buffer.writeln('- 남은 일 중 **지금 제일 만만한** 하나를 고르세요. 중요도로 고르지 마세요.');
    }
    buffer.writeln('- 쪼개기, 첫 문장 대신 써주기, 순서 정해주기, 기준 낮추기 무엇이든 됩니다.');
    buffer.writeln('  그 일과 지금 상황에 맞는 것으로 고르세요.');
    buffer.writeln('- 지금 있는 자리에서 되는 것만. 예: 회사에 매여 있으면 "운동복 챙기기"는 안 됩니다.');
    buffer.writeln('- 손만 대고 마는 것이 아니라, 그 한 수가 끝나면 끝났다고 말할 수 있어야 합니다.');
    buffer.writeln('  예: "분기 리포트" → "개요 세 줄 적기". "글쓰기 시작하기"는 안 됩니다.');
    buffer.writeln();
    buffer.writeln('[답하는 형식]');
    buffer.writeln(
      candidates.length == 1
          ? '첫 줄에 [이 일]에 적힌 이름을 그대로 옮겨 적으세요.'
          : '첫 줄에 고른 일 이름을 [남은 일]에 적힌 그대로 옮겨 적으세요.',
    );
    buffer.writeln('괄호 안의 표시는 빼고, 이름만 적으세요.');
    buffer.writeln('그다음 줄부터 한 수를 한 줄에 하나씩, 많아야 $maxMoves줄 적으세요.');
    buffer.writeln('각 줄은 "~하기" 꼴로 $maxMoveLength자 이내.');
    // 되는 자리가 갈리지 않는 일에 억지로 둘을 만들면 지어낸 말이 나온다.
    // '방 정리'에 폰으로 되는 버전을 붙이면 그게 더 이상하다.
    buffer.writeln('두 줄을 적을 때는 **되는 자리가 서로 다른 것**으로 적으세요.');
    buffer.writeln('  예: 하나는 책상에 앉아야 되는 것, 하나는 폰으로 되는 것.');
    buffer.writeln('자리가 갈리지 않는 일이면 한 줄만 적으세요.');
    buffer.writeln('낼 것이 없으면 NONE 한 줄만 적으세요.');
    buffer.writeln('그 외에는 아무것도 적지 마세요.');
    return buffer.toString();
  }
}
