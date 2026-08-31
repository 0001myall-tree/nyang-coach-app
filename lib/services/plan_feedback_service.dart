import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import '../screens/coach_config.dart';

/// 계획을 구체화하면 좋다는 이야기를 코치가 건네는 자리.
///
/// 한동안은 계획을 저장할 때마다 말을 걸었다. 잘 해내는 사람에게도 매번
/// 참견하게 됐고, 그래서 저장 시점의 개별 참견은 걷어냈다. 지금은 주 1회,
/// 인사 자리에서 한 번만 건넨다 — 그 로테이션과 쿨다운은 채팅 화면 쪽
/// (`chat_screen.dart`의 `_startWeeklyConcretizeTip`류)이 맡고, 이 서비스는
/// 그 자리에서 쓸 문장 하나를 만드는 일만 한다.
///
/// 마스터 플랜 전용이다.
class PlanFeedbackService {
  const PlanFeedbackService._();

  /// 방금 무엇을 두고 먼저 말을 걸었는지. 채팅 화면이 다음 턴에 읽어간다.
  ///
  /// 이 말은 채팅에도 한 줄로 남는다. 그런데 남는 것은 문장뿐이라, 사용자가
  /// "그거 오늘 다 해야 해"라고 답하면 코치는 무엇에 대한 답인지 모른다.
  /// 무슨 일을 두고, 어떤 근거로 꺼낸 말이었는지를 여기 적어둔다.
  static const String lastNudgeKey = 'plan_feedback_last_nudge';

  /// 적어둔 것이 이만큼 지나면 지운다. 그때쯤이면 다른 이야기를 하고 있다.
  static const Duration lastNudgeLife = Duration(hours: 3);

  /// 무엇을 권했는지 며칠 들고 있는 자리.
  ///
  /// [lastNudgeKey]는 방금 한 말을 코치가 알아듣게 하려는 것이라 세 시간이면
  /// 되지만, 이건 그 조언이 먹혔는지 나중에 확인하려고 두는 것이다.
  static const String _adviceLogKey = 'plan_feedback_advice_log';

  /// 조언한 지 이만큼 지나야 결과를 본다. 권한 그날 저녁에 확인하면 아직
  /// 해보지도 않은 것을 두고 묻는 셈이 된다.
  static const Duration adviceRipeAfter = Duration(hours: 20);

  /// 이만큼 지나면 잊는다. 닷새 전 조언을 두고 아는 체하면 그건 이미 지난
  /// 이야기고, 사용자는 무슨 말인지 떠올리지도 못한다.
  static const Duration adviceLogLife = Duration(days: 5);

  /// 콕 집는 조언에 붙는 짧은 표현. 인사 문구에 "~했던"으로 이어 붙는다.
  static const String _pinpointShortAdvice = '어디서 어떻게 할지 정해보자고';

  /// 콕 집었을 때 [lastNudgeKey]에 남기는 화제.
  static const String _pinpointTopic = '막막해 보이는 계획을 짚어준 이야기';

  static final HttpsCallable _chatProxy = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable('chatProxy');

  // ── 오늘 계획 중 막막한 것 콕 집기 (마스터 전용) ──────────
  //
  // 주 1회 자리에서, 로테이션 문구 대신 쓸 수 있으면 쓴다. 확실하지 않으면
  // 반드시 SKIP한다 — 그러면 부르는 쪽이 로테이션 문구로 대신한다.

  /// 오늘 저장된 계획들을 훑어, 지금 그대로 실행하려 하면 무엇을 해야 할지
  /// 몰라서 시작하지 못할 만큼 막막해 보이는 것이 있는지 코치에게 묻는다.
  ///
  /// 하나라도 확실하면 그 계획 이름과 완성된 멘트를 돌려준다. 확실한 것이
  /// 없으면(코치가 SKIP을 내면) null.
  static Future<({String task, String line})?> pinpointConfusingTask({
    required String coachId,
    required List<Map<String, dynamic>> todayTasks,
  }) async {
    try {
      if (!await _hasMasterPlan()) return null;

      final names = <String>[];
      for (final task in todayTasks) {
        if (task['done'] == true) continue;
        final text = task['text']?.toString().trim() ?? '';
        if (text.isEmpty || names.contains(text)) continue;
        names.add(text);
      }
      if (names.isEmpty) return null;

      final content = await _askPinpoint(coachId: coachId, names: names);
      if (content == null) return null;

      final parsed = _parsePinpointResponse(content, names);
      if (parsed == null) return null;

      final prefs = await SharedPreferences.getInstance();
      await _logAdvice(
        prefs,
        taskText: parsed.task,
        advice: _pinpointShortAdvice,
      );
      await prefs.setString(
        lastNudgeKey,
        jsonEncode({
          'task': parsed.task,
          'topic': _pinpointTopic,
          'at': DateTime.now().toIso8601String(),
        }),
      );
      return parsed;
    } catch (e) {
      debugPrint('plan pinpoint failed: $e');
      return null;
    }
  }

  static Future<String?> _askPinpoint({
    required String coachId,
    required List<String> names,
  }) async {
    final coach = CoachConfigs.get(coachId);
    final listed = names.map((name) => "- $name").join('\n');

    final prompt =
        '''${coach.systemPrompt}

[할 일]
오늘 사용자가 저장한 계획들을 훑어보고, 그중 지금 그대로 실행하려고 하면 무엇을
어떻게 시작해야 할지 몰라서 손을 못 대고 있을 가능성이 뚜렷한 계획이 있는지 봐줘.

오늘 계획 목록:
$listed

[판단 순서 - 반드시 이 순서를 지킬 것]
1. 목록을 하나씩 보며 "이 계획 이름만 보고 이 사람이 지금 당장 무엇을, 어디서,
어떻게 시작해야 할지 알 수 있는가?"를 스스로에게 물을 것.
1-1. 확실한 사례가 여럿 보여도 후보는 반드시 하나만 고를 것. 절대 두 개 이상
쓰지 말 것.
2. 알 수 없어서 막막해 보이는 계획이 있다면, 왜 그런지 이유를 한 줄로 먼저 쓸
것. (예: "'기획서 쓰기'는 무엇부터 손대야 할지, 어디까지 하면 되는지가 전혀 안
드러남")
3. 이유가 자연스럽게 안 써진다면(억지로 짜내야 한다면) 그건 확실한 사례가 아닌
것이다. 그럴 땐 이유를 쓰지 말고 SKIP만 출력할 것. 애매하면 SKIP이 기본값이다.
4. 이유를 실제로 썼을 때만, 그 계획 이름과 함께 멘트를 만들 것.

[멘트를 쓸 때]
- 네 부분을 이 순서로 담을 것.
(1) 계획 이름을 그대로 언급하며 시작. "오늘 '기획서 쓰기' 일정이 있음",
"오늘 일정에 '기획서 쓰기'가 보임", "'기획서 쓰기' 계획이 있음"처럼 뜻만
예시로 참고하고(어미 "~음"은 실제로 쓰지 말 것), 실제 어미는 코치의
말투(존댓말/반말, "~냥" 여부 등)에 정확히 맞춰 바꿔 쓸 것 - 매번 똑같은 한
문장을 반복하지 말고 코치 말투 안에서 표현을 바꿔가며 쓸 것. 어느 쪽이든
"미리 정해두는 게", "주제를 정해두는 게"처럼 무엇을 두고 하는 말인지 안
밝히고 시작하지 말 것.
(2) 이 계획을 보니 무엇을 정해두면 좋을지 조언 - 시간/장소를 정하는 쪽이
맞는지, 오늘 어디까지 할지/범위나 개요를 정하는 쪽이 맞는지는 알아서 고를 것.
(3) "심리학에 따르면"이라는 표현을 문장에 그대로 넣고, 그 뒤에 실제 근거
내용(언제·어디서 할지 미리 정해두는 '실행 의도', 또는 오늘 어디까지 할지를
구체적으로 정하는 것)을 붙일 것. "심리학에 따르면"만 쓰고 근거 없이 넘어가지
말 것. 이 부분을 빼면 안 된다.
(4) "이미 생각해뒀으면 그대로 가면 된다"는 뜻으로 마무리.
- 세 문장 안팎, 150자 안에서 끝낼 것. 네 부분을 다 담으려면 문장이 짧아도
좋으니 (3)을 생략하지 말 것. 태그나 따옴표, 머리말 없이 코치의 말투 그대로
쓸 것.

[출력 형식 - 반드시 이 형식만 지킬 것. 다른 말은 덧붙이지 말 것]
확실한 사례가 없으면 아래 한 단어만:
SKIP

확실한 사례가 있으면 정확히 이 세 줄로:
이유: <한 줄>
계획: <계획 이름 그대로>
말: <완성된 멘트>''';

    final response = await _chatProxy.call({
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
    });

    final content =
        (response.data is Map
                ? (response.data as Map)['content'] as String? ?? ''
                : '')
            .trim();
    return content.isEmpty ? null : content;
  }

  static ({String task, String line})? _parsePinpointResponse(
    String content,
    List<String> validNames,
  ) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.toUpperCase().startsWith('SKIP')) return null;

    final taskMatch = RegExp(
      r'^계획\s*[:：]\s*(.+)$',
      multiLine: true,
    ).firstMatch(trimmed);
    final lineMatch = RegExp(
      r'^말\s*[:：]\s*([\s\S]+)$',
      multiLine: true,
    ).firstMatch(trimmed);
    if (taskMatch == null || lineMatch == null) return null;

    final task = taskMatch.group(1)!.trim();
    final line = _firstPinpointLineBlock(lineMatch.group(1)!);
    if (task.isEmpty || line.isEmpty) return null;
    // 목록에 없는 이름을 지어냈으면 믿지 않는다.
    if (!validNames.contains(task)) return null;
    return (task: task, line: line);
  }

  @visibleForTesting
  static ({String task, String line})? parsePinpointResponseForTest(
    String content,
    List<String> validNames,
  ) {
    return _parsePinpointResponse(content, validNames);
  }

  static String _firstPinpointLineBlock(String raw) {
    final nextLabel = RegExp(
      r'^\s*(?:이유|계획|말)\s*[:：]',
      multiLine: true,
    ).firstMatch(raw);
    final block = nextLabel == null ? raw : raw.substring(0, nextLabel.start);
    return block.trim();
  }

  // ── 조언이 먹혔는지 ──────────────────────────
  //
  // 사람이 "얘가 나를 안다"고 느끼는 것은 관찰을 들을 때가 아니라, 저번에 한
  // 말을 기억하고 물어볼 때다.
  //
  // 됐을 때만 말한다. 안 됐을 때 꺼내면 아침부터 추궁이 되고, 그러면 다음
  // 조언은 듣기도 전에 부담이 된다. 확인은 앱이 한다 — "어떻게 됐어?"라고
  // 묻기만 하면 그것도 숙제가 된다.

  /// 권한 대로 해낸 일. 아침 인사에서 그 이야기를 꺼내는 데 쓴다. 없으면 null.
  ///
  /// 문장은 여기서 만들지 않는다. 코치에게 물어보면 말이 매번 달라지는 값은
  /// 있지만, 한 주에 한 번 있을까 한 자리에 값을 치를 만한 일은 아니다.
  /// 무엇을 권했는지만 넘기고 문장은 인사 문구가 맡는다.
  static Future<({String task, String advice})?> adviceThatWorked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (!await _hasMasterPlan()) return null;

      final done = _adviceThatWorked(prefs);
      if (done == null) return null;
      // 같은 조언으로 두 번 우쭐하지 않는다.
      await _dropAdvice(prefs, done.task);
      return done;
    } catch (e) {
      debugPrint('advice follow-up failed: $e');
      return null;
    }
  }

  /// 권한 뒤에 어제 끝낸 일. 없으면 null.
  ///
  /// 어제 것만 본다. 사흘 전에 끝낸 일을 오늘 아침에 꺼내면 뜬금없고,
  /// 조언과 이어진 일로도 들리지 않는다.
  static ({String task, String advice})? _adviceThatWorked(
    SharedPreferences prefs,
  ) {
    final yesterday = _dayKey(DateTime.now().subtract(const Duration(days: 1)));
    final done = <String>{};
    for (final record in _history(prefs, days: 3)) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null || _dayKey(date) != yesterday) continue;
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map || task['done'] != true) continue;
        final text = task['text']?.toString().trim() ?? '';
        if (text.isNotEmpty) done.add(text);
      }
    }
    if (done.isEmpty) return null;

    // 예전엔 "그렇게 해볼게" 버튼을 눌러야만(accepted) 여기 잡혔다. 그
    // 버튼이 뜨던 말풍선 팝업(CoachSayService.say)은 이제 어디서도 부르지
    // 않아 완전히 죽은 경로가 됐다 — pinpoint는 주 1회 인사 자리에 조용히
    // 채팅 메시지로만 들어간다. 그래서 수락 여부를 더 이상 보지 않고,
    // 짚어준 계획이 다음날 끝났으면 그것만으로 축하한다.
    final ripeBefore = DateTime.now().subtract(adviceRipeAfter);
    for (final advice in _adviceLog(prefs).reversed) {
      // 권하자마자 끝낸 것은 세지 않는다. 아침에 꺼낼 이야기는 하루가 지난
      // 일이고, 그래야 권한 것과 해낸 것 사이에 하루가 놓인다.
      if (!advice.at.isBefore(ripeBefore)) continue;
      if (!done.contains(advice.task)) continue;

      return (task: advice.task, advice: advice.advice);
    }
    return null;
  }

  static Future<void> _dropAdvice(
    SharedPreferences prefs,
    String taskText,
  ) async {
    await prefs.setString(
      _adviceLogKey,
      jsonEncode([
        for (final item in _adviceLog(prefs))
          if (item.task != taskText)
            {
              'task': item.task,
              'advice': item.advice,
              'at': item.at.toIso8601String(),
            },
      ]),
    );
  }

  /// 마스터 플랜 전용이다. 틈새 코칭과 같은 자리다.
  ///
  /// 말하는 코치는 지금 쓰는 코치 그대로다. 마스터 플랜이어도 냥이와 대화
  /// 중이면 냥이가 건넨다.
  static Future<bool> _hasMasterPlan() async {
    final userData = await UserDataService.load();
    return userData.isPlanActive && userData.planType == 'master';
  }

  static Future<void> _logAdvice(
    SharedPreferences prefs, {
    required String taskText,
    required String advice,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(adviceLogLife);
    final kept = [
      for (final item in _adviceLog(prefs))
        if (item.at.isAfter(from) && item.task != taskText) item,
      _Advice(task: taskText, advice: advice, at: now),
    ];
    if (kept.length > 5) kept.removeRange(0, kept.length - 5);
    await _saveAdviceLog(prefs, kept);
  }

  static Future<void> _saveAdviceLog(
    SharedPreferences prefs,
    List<_Advice> log,
  ) async {
    await prefs.setString(
      _adviceLogKey,
      jsonEncode([
        for (final item in log)
          {
            'task': item.task,
            'advice': item.advice,
            'at': item.at.toIso8601String(),
          },
      ]),
    );
  }

  static List<_Advice> _adviceLog(SharedPreferences prefs) {
    final raw = prefs.getString(_adviceLogKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final out = <_Advice>[];
      for (final item in (jsonDecode(raw) as List).whereType<Map>()) {
        final task = item['task']?.toString() ?? '';
        final at = DateTime.tryParse(item['at']?.toString() ?? '');
        if (task.isEmpty || at == null) continue;
        out.add(
          _Advice(
            task: task,
            advice: item['advice']?.toString() ?? '계획을 다듬어보자고',
            at: at,
          ),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static String _dayKey(DateTime at) => '${at.year}-${at.month}-${at.day}';

  static List<Map<String, dynamic>> _history(
    SharedPreferences prefs, {
    required int days,
  }) {
    final raw = prefs.getString('nyang_history');
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final from = DateTime.now().subtract(Duration(days: days));
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }
}

/// 짚은 계획 하나와 짚은 때, 그때 건넨 짧은 조언.
class _Advice {
  const _Advice({required this.task, required this.advice, required this.at});

  final String task;

  /// 인사 문구에 끼워 넣을 짧은 표현("~했던"으로 이어짐).
  final String advice;

  final DateTime at;
}
