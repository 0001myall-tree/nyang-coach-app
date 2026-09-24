/// 적극 코칭 카드에서 "하기 싫어"를 고른 뒤 열리는 작은 대화.
///
/// 하기 싫은 마음은 버튼 몇 개로 풀리지 않는다. 그 일이 무엇인지, 왜 무거운지를
/// 보고 코치가 말을 건네야 한다. 그렇다고 채팅 탭으로 데려가면 거기서 마음먹은
/// 사람이 할 일 창으로 다시 건너와야 하고, 이 앱은 그 한 칸이 안 하게 되는
/// 이유가 된다고 보고 여러 군데서 없애왔다. 그래서 할 일 창 위에서 대화한다.
///
/// 방식은 채팅 탭과 같은 목록에서 앱이 하나만 고른다. 모델에게 여러 방식을
/// 주면 매번 가장 흔한 하나로 수렴하고, 싫다고 해도 같은 것을 다시 민다.
/// 거부하면 다음 방식으로 넘어가고, 순번 자리는 채팅 탭과 함께 쓴다 — 그래야
/// 방금 채팅에서 들은 방식을 여기서 또 듣지 않는다.
///
/// 나눈 말은 채팅 탭 기록에도 남긴다. 나중에 채팅을 열었을 때 코치가 방금 한
/// 얘기를 모르면, 사용자는 같은 말을 처음부터 다시 해야 한다.
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../prompts/coach_prompt.dart';
import '../screens/coach_config.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'chat_store.dart';
import 'execution_blocker_service.dart';
import 'resistance_intervention_service.dart';
import 'tasks_sync_service.dart';
import 'user_title_service.dart';

/// 대화 한 줄.
class ActiveCoachingChatLine {
  const ActiveCoachingChatLine({
    required this.text,
    required this.isUser,
    required this.time,
    this.chips = const [],
  });

  final String text;
  final bool isUser;
  final DateTime time;

  /// 코치가 내민 고를 거리. 코치 줄에만 있다.
  final List<String> chips;

  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'time': time.toIso8601String(),
  };
}

/// 코치의 답 한 번.
class ActiveCoachingChatReply {
  const ActiveCoachingChatReply({required this.text, this.chips = const []});

  final String text;
  final List<String> chips;
}

class ActiveCoachingChat {
  ActiveCoachingChat({
    required this.coachId,
    required this.taskName,
    this.otherTasks = const [],
    this.situation,
  });

  final String coachId;

  /// 하기 싫다고 한 일.
  final String taskName;

  /// 오늘 남은 다른 일들. 순서 바꾸기를 꺼낼 때 코치가 고를 거리다.
  final List<String> otherTasks;

  /// 지금 무엇에 매여 있는지. 없으면 null.
  final String? situation;

  static const String model = 'gpt-5-mini';

  /// 채팅 탭과 함께 쓰는 순번 자리. 채팅 화면의 같은 이름 키와 맞춘다.
  static const String rotationKey = 'nyang_resistance_intervention_rotation';

  /// 코치가 참고하는 오늘 채팅 기록 수. 채팅 탭과 같다.
  static const int historyLimit = 10;

  static final HttpsCallable _proxy =
      FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
        'chatProxy',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );

  /// 이 대화에서 이미 꺼낸 방식들.
  ///
  /// '시작 신호 만들기'는 처음부터 넣어둔다. 채팅 탭 위의 버튼을 가리키는
  /// 방식이라, 이 창에서 권하면 없는 버튼을 누르라는 말이 된다.
  final Set<String> _offered = {'start_signal'};

  /// 직전에 꺼낸 방식. 지금 말이 그 방식을 거절한 것인지 볼 때 쓴다.
  String? _lastOffered;

  /// 이 창에서 오간 말. 코치에게 넘기는 이력의 뒤쪽이 된다.
  final List<ActiveCoachingChatLine> lines = [];

  /// 대화를 여는 사용자 한 마디. 카드에서 누른 버튼을 말로 옮긴 것이다.
  String get openingLine => "'$taskName' 하기 싫어";

  /// 사용자의 말을 받아 코치의 답을 받아온다. 못 받아오면 null.
  ///
  /// 받은 말과 답은 [lines]와 채팅 기록에 함께 남는다. 답을 못 받아도 사용자의
  /// 말은 남긴다 — 한 말이 사라지면 다시 쳐야 한다.
  Future<ActiveCoachingChatReply?> send(String userText) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final userLine = ActiveCoachingChatLine(
      text: userText,
      isUser: true,
      time: DateTime.now(),
    );
    lines.add(userLine);
    await _record(prefs, userLine);
    return _ask(prefs, userText);
  }

  /// 답을 못 받아온 턴을 다시 묻는다. 사용자의 말은 이미 적혀 있으니 또
  /// 적지 않는다 — 두 번 적으면 채팅 탭에 같은 말이 두 줄 남는다.
  Future<ActiveCoachingChatReply?> retry() async {
    if (lines.isEmpty || !lines.last.isUser) return null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return _ask(prefs, lines.last.text);
  }

  Future<ActiveCoachingChatReply?> _ask(
    SharedPreferences prefs,
    String userText,
  ) async {
    final now = DateTime.now();
    final earlier = _todayHistory(prefs, now);
    final systemPrompt = await _systemPrompt(prefs, userText, now);
    final messages = [
      {'role': 'system', 'content': systemPrompt},
      for (final line in [...earlier, ...lines.take(lines.length - 1)])
        {
          'role': line.isUser ? 'user' : 'assistant',
          'content': line.isUser ? '${_clock(line.time)} ${line.text}' : line.text,
        },
      {'role': 'user', 'content': '${_clock(now)} $userText'},
    ];

    final String raw;
    try {
      final estimated = AnalyticsService.estimateChatTokens(messages, '');
      await ApiUsageLimitService.ensureChatAllowed(estimatedTokens: estimated);
      final result = await _proxy.call({
        'messages': messages,
        'model': model,
        'temperature': 0.7,
      });
      final data = result.data;
      raw = (data is Map ? data['content'] : null)?.toString() ?? '';
      await AnalyticsService.logApiUsage(
        coachId: coachId,
        estimatedTokens: AnalyticsService.estimateChatTokens(messages, raw),
        actualTokens: AnalyticsService.readIntValue(data is Map ? data : const {}, [
          'totalTokens',
          'total_tokens',
          'tokens',
          'usage.totalTokens',
          'usage.total_tokens',
        ]),
        actualCostWon: AnalyticsService.readIntValue(
          data is Map ? data : const {},
          [
            'costWon',
            'cost_won',
            'estimatedCostWon',
            'estimated_cost_won',
            'usage.costWon',
          ],
        ),
        model: model,
      );
    } catch (_) {
      // 한도가 찼거나 통신이 끊긴 경우다. 창은 그대로 두고 부르는 쪽이 알린다.
      return null;
    }

    final reply = read(raw);
    if (reply == null) return null;
    final coachLine = ActiveCoachingChatLine(
      text: reply.text,
      isUser: false,
      time: DateTime.now(),
      chips: reply.chips,
    );
    lines.add(coachLine);
    await _record(prefs, coachLine);
    return reply;
  }

  /// 답에서 말과 고를 거리를 떼어낸다. 쓸 말이 없으면 null.
  ///
  /// 이 창은 태그로 할 수 있는 일이 없다. 할 일 등록이나 타이머 태그가 섞여
  /// 오면 떼어내고 말만 남긴다 — 그대로 두면 괄호째 화면에 찍힌다.
  static ActiveCoachingChatReply? read(String raw) {
    final chips = <String>[];
    final chipMatch = RegExp(r'\[CHIPS:\s*([^\]]*)\]').firstMatch(raw);
    if (chipMatch != null) {
      for (final part in chipMatch.group(1)!.split('|')) {
        final chip = part.trim();
        if (chip.isNotEmpty && !chips.contains(chip)) chips.add(chip);
      }
    }
    final text = raw
        .replaceAll(RegExp(r'\[[A-Z_]+(?::[^\]]*)?\]'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (text.isEmpty) return null;
    return ActiveCoachingChatReply(text: text, chips: chips);
  }

  // ── 프롬프트 ────────────────────────────────────────────

  Future<String> _systemPrompt(
    SharedPreferences prefs,
    String userText,
    DateTime now,
  ) async {
    final coach = CoachConfigs.get(coachId);
    final interventionSection = await _interventionSection(
      prefs,
      userText,
      isMaster: coach.isMaster,
    );

    final others = otherTasks
        .where((name) => name.trim().isNotEmpty && name != taskName)
        .take(8)
        .toList(growable: false);

    final prompt =
        '''${coach.systemPrompt}
${Prompts.executionSupportRule}

[지금 상황]
- 시각: ${now.hour}:${now.minute.toString().padLeft(2, '0')}
- ${situation == null ? '매여 있는 시간대가 아님' : '매여 있는 시간대: $situation'}
- 앱이 '$taskName'을(를) 할 때라고 말을 걸었고, 사용자는 "하기 싫어"라고 답했습니다.
- 오늘 남은 다른 일: ${others.isEmpty ? '없음' : others.join(', ')}
- 이 대화는 할 일 창 위에 뜬 작은 창에서 오갑니다. 창 아래에는 '$taskName'을(를) 바로 시작하는 버튼이 있습니다.

[하기 싫다 실행 개입 전략]
- 그 일이 무엇인지 보고, 이 사람에게 그 일이 왜 무거울지를 한 문장으로 짚은 뒤 아래 방식으로 연결하세요.
- 제안하는 행동은 하고 나면 일이 실제로 한 칸 진행되는 행동이어야 합니다.
- 사용자가 해보겠다고 하면 길게 붙잡지 말고, 아래 버튼으로 바로 시작하면 된다고 한 문장으로 닫으세요.

[이번 턴에 쓸 개입]
- 아래는 앱이 고른 방식 하나입니다. 다른 방식으로 바꾸거나 여러 개를 섞지 마세요.
$interventionSection

[출력 규칙]
- 2~3문장. 이 창은 좁습니다.
- [CHIPS]는 위 방식이 붙이라고 한 때만 씁니다. 그 밖의 태그는 쓰지 않습니다.''';

    if (!coach.isMaster) return prompt;
    final title = await UserTitleService.getTitle();
    return prompt.replaceAll(UserTitleService.defaultTitle, title);
  }

  /// 이번 턴에 쓸 방식.
  ///
  /// 첫 턴과 거절한 턴에만 새로 꺼낸다. 그 밖의 턴은 사용자가 방식을 받아들여
  /// 이어가는 중이라, 새 방식을 얹으면 하던 얘기를 끊고 다른 제안을 하게 된다.
  Future<String> _interventionSection(
    SharedPreferences prefs,
    String userText, {
    required bool isMaster,
  }) async {
    final firstTurn = _lastOffered == null && lines.length <= 1;
    final refused =
        _lastOffered != null && ResistanceInterventionService.isRefusal(userText);
    if (!firstTurn && !refused) {
      final current = _lastOffered == null
          ? null
          : ResistanceInterventionService.byId(_lastOffered!);
      return current == null
          ? '- 새 방식을 꺼내지 말고, 사용자의 말을 받아 지금 하던 얘기를 이어가세요.'
          : '- 지금 쓰는 방식을 이어가세요. 사용자의 말을 받아 한 걸음만 더 가세요.\n${current.rule}';
    }

    final next = ResistanceInterventionService.nextIntervention(
      _offered,
      isMaster: isMaster,
      startAfterId: prefs.getString(rotationKey),
      preferredId: await ExecutionBlockerService.preferredInterventionId(),
    );
    if (next == null) {
      _lastOffered = null;
      return ResistanceInterventionService.exhaustedRule;
    }
    _offered.add(next.id);
    _lastOffered = next.id;
    // 순번 밖에서 지목해 꺼낸 것은 자리를 옮기지 않는다. 채팅 탭과 같은 규칙이다.
    if (!next.preferredOnly) await prefs.setString(rotationKey, next.id);
    return refused
        ? '${ResistanceInterventionService.refusedPrefix}\n${next.rule}'
        : next.rule;
  }

  // ── 기록 ────────────────────────────────────────────────

  /// 오늘 채팅 탭에서 오간 말 중 뒤쪽 몇 개. 이 창을 열기 전의 것만.
  List<ActiveCoachingChatLine> _todayHistory(
    SharedPreferences prefs,
    DateTime now,
  ) {
    final today = ChatStore.dateOf({'time': now.toIso8601String()});
    final result = <ActiveCoachingChatLine>[];
    for (final item in ChatStore.sorted(
      ChatStore.decode(prefs.getString(ChatStore.historyKey(coachId))),
    )) {
      if (item is! Map) continue;
      if (ChatStore.dateOf(item) != today) continue;
      if (item['kind'] == 'vision_choice') continue;
      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final time = DateTime.tryParse(item['time']?.toString() ?? '');
      if (time == null) continue;
      // 이 창에서 방금 적은 줄은 [lines]로 따로 넘긴다. 두 번 실리면 코치가
      // 사용자가 같은 말을 두 번 한 것으로 읽는다.
      if (lines.any((line) => line.time == time && line.text == text)) continue;
      result.add(
        ActiveCoachingChatLine(
          text: text,
          isUser: item['isUser'] == true,
          time: time,
        ),
      );
    }
    return result.length > historyLimit
        ? result.sublist(result.length - historyLimit)
        : result;
  }

  /// 채팅 탭 기록에 한 줄 덧붙인다.
  ///
  /// 대화는 덧붙이기만 하는 목록이라 합쳐서 쓴다. 이 창이 떠 있는 동안에는
  /// 채팅 화면이 만들어져 있지 않으므로(본문이 할 일 창이다) 덮어쓸 쪽이 없다.
  Future<void> _record(
    SharedPreferences prefs,
    ActiveCoachingChatLine line,
  ) async {
    final key = ChatStore.historyKey(coachId);
    await prefs.setString(
      key,
      ChatStore.mergedValue([line.toJson()], ChatStore.decode(prefs.getString(key))),
    );
    TasksSyncService.scheduleSyncToCloud();
  }

  static String _clock(DateTime at) =>
      '[${at.hour}:${at.minute.toString().padLeft(2, '0')}]';
}
