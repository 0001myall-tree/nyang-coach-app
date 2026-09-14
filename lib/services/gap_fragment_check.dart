/// 오늘 남은 일 목록을 보고, 지금 10분으로 오늘 완료율을 올릴 한 조각을
/// 골라온다.
///
/// 틈새 코칭이 하려는 일이 그것이다. 일을 끝내라는 말이 아니라, 10분을 써서
/// 나중에 손대기 쉬워지게 만드는 자리다. "10분만 써봐"가 아니라 "10분 동안
/// 개요만 잡아둘까" — 시간은 좁히되 그 안에서 하나가 완결돼야 한다.
///
/// 처음에는 키워드 사전이 이 일을 했다. 사전에 없는 이름은 전부 "10분만 미리
/// 해두면"으로 떨어져서 정작 하려던 걸 못 했다 — '레퍼런스 정리',
/// '세금계산서', '면접 준비' 같은 것들이다.
///
/// 그다음에는 앱이 일 하나를 고르고 그 이름만 넘겼다. 이번엔 고르는 쪽이
/// 틀렸다. 머리로 하는 일인지를 또 사전으로 갈랐고, 무엇보다 '사당역 19시'
/// 같은 약속을 쪼개라고 넘겼다. 약속은 그 시각에 가서 하는 것이라 앞당길
/// 자리가 없다.
///
/// 그래서 목적만 주고 고르는 것까지 넘긴다. 앱이 무엇을 어떻게 쪼갤지 갈래를
/// 만들지 않는다 — 앞당길 것과 이어갈 것을 앱이 갈라두면, 갈래마다 다른 말을
/// 시키게 되고 그 말이 그 사람의 오늘과 안 맞는다. 목록과 상황을 넘기고
/// 무엇이 10분짜리인지는 코치가 본다.
library;

import 'package:cloud_functions/cloud_functions.dart';

import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

/// 코치에게 넘기는 일 하나. 시각과 지금 상태를 함께 넘긴다.
///
/// 시각을 주는 이유는 무엇을 먼저 할지가 그것으로 갈리기 때문이다. 한 시간
/// 뒤에 시작하는 일과 언제 해도 되는 일은 지금 해둘 만한 것이 다르다.
///
/// 손을 댔는지도 함께 준다. 아직 안 건드린 일에는 시작이 쉬워지는 준비가,
/// 하는 중인 일에는 이어갈 다음 조각이 맞는다. 무엇이 맞는지를 앱이 갈라
/// 정해주지 않고 사실만 넘긴다.
class GapCandidate {
  const GapCandidate({
    required this.name,
    this.timeLabel,
    this.started = false,
  });

  final String name;

  /// "오후 7:00" 꼴. 시각이 없는 일은 null.
  final String? timeLabel;

  /// 이미 손을 댄 일인지.
  final bool started;

  String get line {
    final marks = [if (timeLabel != null) '$timeLabel 시작', if (started) '하는 중'];
    return marks.isEmpty ? name : '$name (${marks.join(', ')})';
  }
}

/// 고른 일과, 지금 그 일에 해둘 10분짜리 한 조각.
class GapPrep {
  const GapPrep({required this.task, required this.prep});

  /// 넘긴 목록에 있던 이름 그대로. 부르는 쪽이 이걸로 그 일을 다시 찾는다.
  final String task;

  /// 10분 안에 끝나는 조각. '개요 잡기'처럼 짧은 이름이다.
  final String prep;
}

class GapFragmentCheck {
  const GapFragmentCheck._();

  /// 대화에 쓰는 모델과 같은 것을 쓴다. 무엇을 준비해두면 오늘이 수월해지는지는
  /// 이름 하나를 읽는 일이 아니라 목록 전체를 견주는 일이다.
  static const String model = 'gpt-5-mini';

  /// 조각 이름이 이보다 길면 카드 한 줄을 혼자 다 먹는다.
  static const int maxFragmentLength = 14;

  /// 한 번에 견주는 개수. 넘으면 앞에서부터 자른다.
  static const int maxCandidates = 10;

  static const String _system =
      '당신은 오늘 남은 일들을 보고, 지금 10분으로 오늘 완료율을 올릴 한 조각을 '
      '고르는 판별기입니다. 설명하지 말고 형식대로만 답합니다.';

  /// 조각 하나. 못 물어봤거나 고를 것이 없으면 null.
  ///
  /// [cores]는 오늘의 핵심으로 고른 일들이다. 비어 있을 수 있다.
  /// [situation]은 그 시각에 무엇에 매여 있는지. 매인 것이 없으면 null이다.
  static Future<GapPrep?> suggest({
    required List<GapCandidate> candidates,
    required DateTime at,
    List<String> cores = const [],
    String? situation,
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
          cores: cores,
          at: at,
          situation: situation,
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

      return readPick(
        content,
        asked.map((item) => item.name).toList(growable: false),
      );
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 부르는 쪽이 사전으로 떨어진다.
      return null;
    }
  }

  /// 답에서 고른 일과 준비를 꺼낸다. 쓸 수 없으면 null.
  ///
  /// 목록에 없는 이름은 버린다. 지어낸 일을 카드가 불러주면 사용자는 적은
  /// 적 없는 일을 보게 된다.
  static GapPrep? readPick(String raw, List<String> candidates) {
    final lines = raw
        .split('\n')
        .map((line) => _unwrap(line))
        .where((line) => line.isNotEmpty)
        .toList(growable: false);
    if (lines.isEmpty) return null;
    if (lines.first.toUpperCase() == 'NONE') return null;
    if (lines.length < 2) return null;

    final task = lines[0];
    final prep = readFragment(lines[1]);
    if (prep == null) return null;
    if (!candidates.contains(task)) return null;
    return GapPrep(task: task, prep: prep);
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
    text = _unwrap(text);
    if (text.isEmpty) return null;
    if (text.toUpperCase() == 'NONE') return null;
    // 설명을 붙여 오면 조각이 아니다.
    if (text.length > maxFragmentLength) return null;
    return text;
  }

  /// "오후 3:30".
  static String _clock(DateTime at) {
    final meridiem = at.hour >= 12 ? '오후' : '오전';
    final hour = at.hour > 12 ? at.hour - 12 : (at.hour == 0 ? 12 : at.hour);
    return '$meridiem $hour:${at.minute.toString().padLeft(2, '0')}';
  }

  /// 감싼 따옴표와 끝 문장부호를 걷어낸다.
  static String _unwrap(String raw) =>
      raw.trim().replaceAll(RegExp(r'''^["'`\s]+|["'`\s.。!?]+$'''), '');

  static String _prompt({
    required List<GapCandidate> candidates,
    required List<String> cores,
    required DateTime at,
    String? situation,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('[지금]');
    buffer.writeln('- 시각: ${_clock(at)}');
    // 무엇을 지금 할 수 있는지가 이 한 줄로 갈린다. 회사에 있는 사람에게
    // 운동복을 챙기라고 하면 안 된다.
    buffer.writeln(
      situation == null ? '- 매여 있는 시간대가 아님' : '- 매여 있는 시간대: $situation',
    );
    buffer.writeln();
    if (cores.isNotEmpty) {
      buffer.writeln('[오늘의 핵심]');
      for (final name in cores) {
        buffer.writeln('- $name');
      }
      buffer.writeln();
    }
    buffer.writeln('[오늘 남은 일]');
    for (final item in candidates) {
      buffer.writeln('- ${item.line}');
    }
    buffer.writeln();

    // 목적을 밝히고 맡긴다. 무엇을 어떻게 쪼갤지를 여기서 갈래로 나눠 정해주면,
    // 그 갈래가 안 맞는 사람에게 엉뚱한 말이 나간다.
    buffer.writeln(
      '지금 10분쯤 여유가 있습니다. 이 10분을 써서 오늘 남은 일을 하나라도 더 끝낼 수 '
      '있게 만드는 것이 목적입니다. 일을 끝내라는 말이 아니라, 나중에 손대기 쉬워지도록 '
      '지금 떼어낼 수 있는 한 조각을 고르는 자리입니다.',
    );
    buffer.writeln();
    if (cores.isNotEmpty) {
      // 핵심을 먼저 보되 억지로 붙이지는 않게 한다. 핵심이 '헬스장 가기'면
      // 10분에 할 것이 별로 없는데, 그런 날 억지 조각을 내놓으면 아무 말도
      // 안 하느니만 못하다.
      buffer.writeln('- [오늘의 핵심]에 있는 일부터 봅니다.');
      buffer.writeln('  다만 핵심에 지금 할 자리가 마땅치 않으면 남은 일에서 고르세요.');
    }
    // 무엇이 한 조각인지를 예시로 보인다. 목록으로 가두면 거기 없는 이름이
    // 전부 빠지고, 설명만 주면 판별기마다 다른 것을 조각이라고 부른다.
    buffer.writeln('- 그 10분 안에 **끝나는** 것이어야 합니다. 손만 대고 마는 것은 조각이 아닙니다.');
    buffer.writeln('  예: "분기 리포트" → "개요 잡기". "글쓰기 시작하기"는 안 됩니다.');
    buffer.writeln('- 그 일 전체를 해내라는 말이 되면 안 됩니다. 10분에 떼어낼 수 있는 크기만.');
    buffer.writeln('- "하는 중"인 일은 이미 시작한 자리에서 이어갈 다음 한 조각을 고르세요.');
    buffer.writeln(
      '- 정해진 시각에 가서 하는 약속은 앞당길 자리가 없습니다. 챙겨 갈 것을 미리 '
      '준비하는 정도만 되고, 그것도 마땅치 않으면 다른 일을 고르세요.',
    );
    buffer.writeln('- 지금 있는 자리에서 할 수 있는 것만 고르세요.');
    buffer.writeln('  예: 회사에 매여 있는 사람은 "운동복 챙기기"를 지금 할 수 없습니다.');
    buffer.writeln('- 이름만으로 무슨 일인지 알 수 없는 것은 고르지 마세요.');
    buffer.writeln('  예: "그거 하기", "오후 일정".');
    buffer.writeln();
    buffer.writeln('[답하는 형식]');
    buffer.writeln('첫 줄에 고른 일 이름을 [오늘 남은 일]에 적힌 그대로 옮겨 적으세요.');
    buffer.writeln('괄호 안의 표시는 빼고, 이름만 적으세요.');
    buffer.writeln('둘째 줄에 조각 하나를 "~하기" 꼴, $maxFragmentLength자 이내로 적으세요.');
    buffer.writeln('고를 것이 없으면 NONE 한 줄만 적으세요.');
    buffer.writeln('두 줄 외에는 아무것도 적지 마세요.');
    return buffer.toString();
  }
}
