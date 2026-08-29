import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import '../screens/coach_config.dart';
import 'coach_say_service.dart';
import 'execution_pattern_service.dart';
import 'life_context_service.dart';

/// 계획을 적는 자리에서 코치가 한 마디 건네는 자리.
///
/// 계획이 추상적이라고 늘 짚지 않는다. "운동하기"라고만 적어도 매일 해내는
/// 사람에게 시간과 장소를 정하라고 하면 그건 코칭이 아니라 참견이다. 추상적인
/// 것이 문제가 아니라 안 되고 있는 것이 문제다. 그래서 앱은 "말을 걸어도 되는
/// 상황인지"만 보고, 정말 짚을 것이 있는지는 코치가 판단한다.
///
/// 앱이 보는 것: 최근 완료율, 그 이름의 과거 완료율, 오늘 계획 수, 쿨타임.
/// 코치가 보는 것: 그 계획이 실제로 손댈 수 없을 만큼 뭉뚱그려져 있는지.
/// 코치가 아니라고 하면 아무 일도 일어나지 않고 쿨타임도 그대로 남는다.
///
/// 마스터 플랜 전용이다.
class PlanFeedbackService {
  const PlanFeedbackService._();

  /// 이 값들은 이 기기에서만 뜻이 있어 'nyang_' 접두어를 쓰지 않는다.
  static const String _lastSaidAtKey = 'plan_feedback_last_at';

  /// 총량 이야기는 따로 센다.
  ///
  /// 계획 코칭은 그날 첫 계획을 적는 순간에 나가는데, 그때는 목록에 그것
  /// 하나뿐이라 양이 많은지를 볼 수가 없다. 같은 예산을 쓰면 여덟 개 잡은
  /// 날을 영영 못 본다. 종류가 다른 말이라 하루에 한 번씩 따로 둔다.
  static const String _lastVolumeAtKey = 'plan_feedback_volume_at';

  /// 방금 무엇을 두고 먼저 말을 걸었는지. 채팅 화면이 다음 턴에 읽어간다.
  ///
  /// 이 말은 채팅에도 한 줄로 남는다. 그런데 남는 것은 문장뿐이라, 사용자가
  /// "그거 오늘 다 해야 해"라고 답하면 코치는 무엇에 대한 답인지 모른다.
  /// 무슨 일을 두고, 어떤 근거로 꺼낸 말이었는지를 여기 적어둔다.
  static const String lastNudgeKey = 'plan_feedback_last_nudge';

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

  /// 아침에 한 마디만. 어느 이야기가 나가든 그날 아침은 그것으로 끝난다.
  static const String _morningSaidKey = 'plan_feedback_morning_at';

  /// 적어둔 것이 이만큼 지나면 지운다. 그때쯤이면 다른 이야기를 하고 있다.
  static const Duration lastNudgeLife = Duration(hours: 3);
  static const String _restUntilKey = 'plan_feedback_rest_until';

  /// 짚은 이름과 짚은 때를 함께 담는다. 이름만 담던 옛 칸과 형식이 달라
  /// 열쇠를 새로 냈다.
  static const String _handledKey = 'plan_feedback_handled_at';
  static const String _oldHandledKey = 'plan_feedback_handled';

  /// 말을 거는 간격. 이틀에 한 마디까지다.
  ///
  /// 하루에 한 번으로 뒀다가 이틀로 되돌렸다. 갈래가 몇 개뿐이라 매일이면
  /// 며칠 만에 같은 말을 다시 듣게 된다.
  ///
  /// 완료율이 높은 사람에게만 주 한 번으로 벌려두었던 것은 없앴다. 잦아서
  /// 참견이 되는 것을 막는 일은 연속 거절이 맡는다 — 짐작으로 뜸하게 두는
  /// 것보다, 싫다고 말한 사람에게 물러나는 편이 정확하다.
  static const Duration interval = Duration(days: 2);

  /// 한 번 짚은 이름을 이만큼 잊지 않는다. 그동안은 그 계획에 말을 걸지 않는다.
  ///
  /// 개수로 세던 때는 말하는 간격이 바뀔 때마다 이 기간이 같이 흔들렸다.
  /// 일곱 개를 들고 있으면 이틀에 한 번 말할 때는 보름이지만 주 한 번이면
  /// 일곱 주가 된다. 재는 것이 기간이니 기간으로 적는다.
  ///
  /// 닷새다. 하루에 한 번씩 말하게 되면서, 이 기간이 길면 자주 적는 이름
  /// 몇 개가 목록을 채워 할 말이 없어지는 날이 생긴다.
  static const Duration handledLife = Duration(days: 5);

  /// 안전장치일 뿐이다. 재는 것은 기간이고 이건 뚜껑이다.
  ///
  /// 하루에 한 번 말하고 닷새를 기억하니 제대로 굴러가면 다섯을 넘지 않는다.
  /// 딱 다섯으로 두면 뚜껑이 기간보다 먼저 걸려 재는 자리가 뒤바뀐다.
  static const int handledMemory = 8;

  /// 하루에 코치를 불러보는 횟수. 여기 닿으면 그날은 더 묻지 않는다.
  ///
  /// 코치가 SKIP을 내면 쿨타임을 쓰지 않는다. 짚을 것이 없었으니 기회를
  /// 삼키지 않는 것인데, 볼일만 줄줄이 적는 날에는 그 항목마다 코치를
  /// 부르게 된다. 그런 날 조용히 값만 치르지 않도록 뚜껑을 둔다.
  static const int askBudgetPerDay = 3;

  static const String _askCountKey = 'plan_feedback_ask_count';

  /// 이틀 내리 사양했을 때 쉬는 기간.
  ///
  /// 한 번은 그날 사정일 수 있다. 바빴거나, 그 계획에는 할 말이 없었거나.
  /// 이틀 연속이면 그건 지금 이런 말을 듣고 싶지 않다는 뜻이라 물러난다.
  ///
  /// 닷새다. 일주일을 쉬면 그 사이에 계획 쓰는 방식이 바뀌어도 아무 말을
  /// 못 하고, 사양한 쪽에서도 앱이 이 이야기를 그만둔 줄로 알게 된다.
  static const Duration restLength = Duration(days: 5);

  /// 며칠 연속 사양해야 쉬는지.
  static const int restAfterDeclines = 2;

  static const String _declineKey = 'plan_feedback_declines';

  /// 이 아래면 도울 여지가 있다고 본다. 실행 패턴이 "안정형"으로 보는 선과 같다.
  ///
  /// 넘는 사람에게도 입을 닫지는 않는다. 간격이 사흘로 늘고, 근거가 있는
  /// 이야기(시각을 정해두면 수월해진다) 하나만 남는다.
  static const double lowRate = 0.7;

  /// 최근에 해내던 양보다 이만큼 넘게 잡았을 때만 총량 이야기를 꺼낸다.
  ///
  /// 둘로 두면 자기모순이 된다. 목표 구체화가 "조각으로 나눠보자"고 권하면
  /// 개수는 늘 수밖에 없는데, 그 조언을 따른 것만으로 다음 날 "너무 많다"는
  /// 말을 듣게 된다. 조각내기로 늘어나는 만큼은 넘겨준다.
  static const int tooManyMargin = 4;

  /// 그 이름을 과거에 이만큼 해냈으면 건드리지 않는다.
  static const double provenRate = 0.6;

  /// 켜두면 할 일을 적을 때마다 말풍선이 뜬다. 완료율도, 쿨타임도, 이미 짚은
  /// 이름인지도, 하루 호출 상한도 보지 않는다.
  ///
  /// 문구를 확인할 때만 쓴다. 실제로 어떻게 뜨는지 보려면 조건이 맞는 날을
  /// 기다려야 하는데, 그 조건이 곧 이 기능의 요점이라 낮춰서 확인할 수가 없다.
  /// 코치가 SKIP을 내는 것까지는 막지 않는다 — 그건 확인하려는 대상이다.
  static const bool debugAlwaysSpeak = false;

  static final HttpsCallable _chatProxy = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable('chatProxy');

  /// 할 일 하나를 저장했다. 코치가 말을 거는 유일한 자리다.
  ///
  /// 한동안은 핵심을 고르는 자리에서 말했다. 사용자가 스스로 중요하다고
  /// 고른 자리라 계획을 다듬는 이야기가 쓸모 있을 것 같았는데, 정작 그
  /// 화면을 못 보고 지나가는 날이 많았다. 계획을 적는 자리가 사람이 실제로
  /// 머무는 곳이라, 같은 말도 여기서 해야 닿는다.
  ///
  /// 한동안은 그날 잡은 양이 많을 때만 말했다. '미용실 가기'에 조언이 붙는
  /// 것이 무서워서였는데, 그건 이제 갈래를 고르는 규칙이 막는다 — 가서 하고
  /// 오면 끝나는 볼일에는 코치가 SKIP을 낸다.
  static Future<void> onTaskSaved({
    required String coachId,
    required String taskText,
    required bool hasTime,
  }) async {
    try {
      // 오늘 잡은 양 이야기가 먼저다. 그날 전체를 보는 말이라 항목 하나를
      // 다듬는 이야기보다 앞선다. 한 번 저장에 두 마디를 하지는 않는다.
      if (await _speakVolume(coachId)) return;
      await _speak(
        coachId: coachId,
        taskText: taskText.trim(),
        hasTime: hasTime,
      );
    } catch (e) {
      debugPrint('plan feedback failed: $e');
    }
  }

  /// 오늘 잡은 양이 평소 해내던 것보다 많으면 한 마디. 말했으면 true.
  static Future<bool> _speakVolume(String coachId) async {
    if (!await _hasMasterPlan()) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final recent = _recentRates(prefs, days: 8);
    if (!recent.hasData) return false;

    final today = _todayTasks(prefs);
    if (today.length < recent.doneAverage + tooManyMargin) return false;

    if (!debugAlwaysSpeak) {
      if (!_maySpeakNow(prefs, interval, atKey: _lastVolumeAtKey)) return false;
      if (_asksToday(prefs) >= askBudgetPerDay) return false;
    }

    await _countAsk(prefs);
    CoachSayService.startThinking(coachId);
    String? line;
    try {
      line = await _askCoach(
        coachId: coachId,
        kind: _PlanFeedbackKind.slack,
        taskText: '',
        hasTime: false,
        todayCount: today.length,
        recent: recent,
        todaySummary: _todaySummary(today, ''),
        historyNote: '',
        whenNote: _whenNote(prefs, recent),
      );
    } catch (_) {
      CoachSayService.stopThinking();
      rethrow;
    }
    if (line == null || line.isEmpty) {
      CoachSayService.stopThinking();
      return false;
    }

    await prefs.setString(
      _lastVolumeAtKey,
      DateTime.now().toIso8601String(),
    );
    await prefs.setString(
      lastNudgeKey,
      jsonEncode({
        'task': '오늘 잡은 일 전체',
        'topic': _PlanFeedbackKind.slack.topic,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    await CoachSayService.say(coachId: coachId, text: line);
    return true;
  }

  static Future<void> _speak({
    required String coachId,
    required String taskText,
    required bool hasTime,
  }) async {
    if (taskText.isEmpty) return;

    if (!await _hasMasterPlan()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final recent = _recentRates(prefs, days: 8);
    if (!debugAlwaysSpeak) {
      if (!_maySpeakNow(prefs, interval)) return;
      // 한 번 짚은 항목은 한동안 다시 짚지 않는다. 고쳤든 안 고쳤든, 같은
      // 말을 곧바로 두 번 하는 순간 조언이 잔소리가 된다.
      if (_handledNames(prefs).contains(taskText)) return;
      // 오늘 물어볼 만큼 물어봤다.
      if (_asksToday(prefs) >= askBudgetPerDay) return;
    }

    final today = _todayTasks(prefs);
    final kind = _pickKind(
      prefs: prefs,
      taskText: taskText,
      hasTime: hasTime,
      todayCount: today.length,
      recent: recent,
    );
    if (kind == null) return;

    // 여기서부터 몇 초가 걸린다. 코치가 SKIP을 내도 값은 치렀으니 여기서 센다.
    await _countAsk(prefs);
    // 기다리는 동안 자리를 잡아둔다.
    CoachSayService.startThinking(coachId);
    String? line;
    try {
      line = await _askCoach(
        coachId: coachId,
        kind: kind,
        taskText: taskText,
        hasTime: hasTime,
        todayCount: today.length,
        recent: recent,
        todaySummary: _todaySummary(today, taskText),
        historyNote: _taskHistoryNote(prefs, taskText),
        whenNote: _whenNote(prefs, recent),
      );
    } catch (_) {
      CoachSayService.stopThinking();
      rethrow;
    }
    // 코치가 짚을 것이 없다고 했다. 쿨타임은 쓰지 않는다.
    if (line == null || line.isEmpty) {
      CoachSayService.stopThinking();
      return;
    }

    await _remember(prefs, taskText);
    await _logAdvice(prefs, taskText: taskText, kind: kind);
    await prefs.setString(
      lastNudgeKey,
      jsonEncode({
        'task': taskText,
        'topic': kind.topic,
        'at': DateTime.now().toIso8601String(),
      }),
    );
    await CoachSayService.say(coachId: coachId, text: line);
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

  /// 권한 뒤에 실제로 끝난 일. 없으면 null.
  static ({String task, String advice})? _adviceThatWorked(
    SharedPreferences prefs,
  ) {
    final now = DateTime.now();
    final records = _history(prefs, days: adviceLogLife.inDays + 1);
    for (final advice in _adviceLog(prefs).reversed) {
      // 권한 그날 저녁에 확인하면 아직 해보지도 않은 것을 묻는 셈이 된다.
      if (now.difference(advice.at) < adviceRipeAfter) continue;
      if (now.difference(advice.at) > adviceLogLife) continue;

      for (final record in records) {
        final date = DateTime.tryParse(record['date']?.toString() ?? '');
        if (date == null || date.isBefore(advice.at)) continue;
        for (final task in (record['tasks'] as List?) ?? const []) {
          if (task is! Map || task['done'] != true) continue;
          if (task['text']?.toString().trim() != advice.task) continue;
          final kind = _PlanFeedbackKind.values
              .where((value) => value.name == advice.kind)
              .firstOrNull;
          return (
            task: advice.task,
            advice: kind?.shortAdvice ?? '계획을 좀 다듬어보자고',
          );
        }
      }
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
              'kind': item.kind,
              'at': item.at.toIso8601String(),
            },
      ]),
    );
  }

  // ── 주간 실행 패턴 코칭 ────────────────────────
  //
  // 하루치 이야기만 하면 매번 같은 자리를 맴돈다. 한 주에 한 번은 그 주가
  // 어떻게 흘렀는지를 두고 말한다 — 언제 첫 발을 뗐는지, 잡은 양과 해낸 양이
  // 얼마나 벌어졌는지.
  //
  // 아침에 꺼낸다. 하루가 아직 안 정해진 시간이라야 오늘 무엇을 바꿔볼지
  // 이야기가 되고, 저녁에 꺼내면 지나간 일에 대한 평가가 된다.

  static const String _patternAtKey = 'plan_feedback_pattern_at';

  static const Duration patternInterval = Duration(days: 7);
  static const int patternFromHour = 5;
  static const int patternUntilHour = 12;

  /// 아침에 앱을 열었을 때 한 번 본다. 셀 것이 모자라면 아무 일도 없다.
  static Future<void> maybeWeeklyPattern({required String coachId}) async {
    try {
      await _maybeWeeklyPattern(coachId);
    } catch (e) {
      debugPrint('weekly pattern failed: $e');
    }
  }

  static Future<void> _maybeWeeklyPattern(String coachId) async {
    if (coachId != 'nyang_halbae' && coachId != 'sec_female') return;

    final hour = DateTime.now().hour;
    if (hour < patternFromHour || hour >= patternUntilHour) return;

    if (!await _hasMasterPlan()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (_morningTaken(prefs)) return;

    final lastAt = DateTime.tryParse(prefs.getString(_patternAtKey) ?? '');
    if (lastAt != null &&
        DateTime.now().difference(lastAt) < patternInterval) {
      return;
    }

    // 앱이 센 것이 없으면 할 말도 없다. 없는 패턴을 지어내게 두지 않는다.
    final pattern = await ExecutionPatternService.promptBlock();
    if (pattern.isEmpty) return;

    final coach = CoachConfigs.get(coachId);
    final life = await LifeContextService.promptLine();
    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
아침에 사용자가 앱을 열었음. 채팅 밖 말풍선으로 한 마디를 건네는 자리임. 화면 위에 뜨는 작은 말풍선이라, 세 문장 130자 안에서 끝낼 것.

[이번에 할 이야기 - 한 주의 실행 패턴]
아래는 앱이 최근 이레 기록에서 센 값임. 한 주에 한 번 하는 이야기라, 오늘 하루가 아니라 그 주가 어떻게 흘렀는지를 두고 말할 것.
$pattern

[이 사람의 생활]
$life
*생활 형태를 알면 그것에 비추어 말할 것. 예를 들어 낮에 일이 있는 사람이 밤에만 첫 발을 뗀다면, 밤에 처음부터 다 하려 하지 말고 낮에 십 분만 내어 얼개만 잡아두자고 권할 수 있음.
*모르면 단정하지 말 것. "낮에 따로 일이 있는지는 모르겠지만" 하고 열어두고 말할 것.

[출력]
- 그 말만 쓸 것. 태그나 따옴표, 머리말 없이 코치의 말투 그대로.
- 위 지시문의 말투를 따라 쓰지 말 것. 지시문은 설명일 뿐이고, 실제로 쓸 말투는 위에 주어진 코치의 말투임.
- 숫자를 늘어놓지 말 것. 센 값은 무엇을 말할지 고르는 데 쓰고, 문장에는 눈에 띄는 하나만 짚을 것.
- 지난 한 주를 평가하지 말 것. 오늘 무엇을 조금 바꿔볼지로 끝낼 것.
- 한 가지만 말할 것.''';

    final response = await _chatProxy.call({
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
    });
    final content = (response.data is Map
            ? (response.data as Map)['content'] as String? ?? ''
            : '')
        .trim();
    if (content.isEmpty) return;

    await prefs.setString(_patternAtKey, DateTime.now().toIso8601String());
    await _takeMorning(prefs);
    await CoachSayService.say(coachId: coachId, text: content);
  }

  // ── 사전 부검 ────────────────────────────────
  //
  // "이 계획이 완전히 망했다고 치고, 왜 망했을지 미리 적어보기". 위험을 미리
  // 꺼내놓으면 그중 몇 개는 시작 전에 치울 수 있다.
  //
  // 계획을 막 세운 사람 옆에서 꺼내면 안 되는 말이다. 방금 적어놓은 것을 두고
  // 망한다고 가정하자는 말은 응원이 아니라 초를 치는 것이 된다. 그래서 이건
  // 저장하는 자리가 아니라 아침에, 그것도 한 주가 계속 안 풀린 사람에게만
  // 꺼낸다.

  static const String _preMortemAtKey = 'plan_feedback_premortem_at';

  /// 이 아래로 내려간 주에만. 한 주 내내 안 됐다는 뜻이다.
  static const double preMortemRate = 0.3;

  static const Duration preMortemInterval = Duration(days: 7);
  static const int preMortemFromHour = 5;
  static const int preMortemUntilHour = 11;

  /// 아침에 앱을 열었을 때 한 번 본다. 대개는 아무 일도 없다.
  static Future<void> maybeMorningPreMortem({required String coachId}) async {
    try {
      await _maybeMorningPreMortem(coachId);
    } catch (e) {
      debugPrint('pre-mortem failed: $e');
    }
  }

  static Future<void> _maybeMorningPreMortem(String coachId) async {
    // 마스터 코치만. 위험을 미리 적어보자는 말은 오늘 하루를 함께 보는
    // 프렌즈 코치의 자리가 아니다.
    if (coachId != 'nyang_halbae' && coachId != 'sec_female') return;

    final hour = DateTime.now().hour;
    if (hour < preMortemFromHour || hour >= preMortemUntilHour) return;

    if (!await _hasMasterPlan()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (_morningTaken(prefs)) return;

    final lastAt = DateTime.tryParse(prefs.getString(_preMortemAtKey) ?? '');
    if (lastAt != null &&
        DateTime.now().difference(lastAt) < preMortemInterval) {
      return;
    }

    // 지난 이레를 본다. 하루 이틀 무너진 것과 한 주가 통째로 안 풀린 것은
    // 다른 이야기다.
    final week = _recentRates(prefs, days: 7);
    if (!week.hasData || week.rate > preMortemRate) return;

    final coach = CoachConfigs.get(coachId);
    final rate = (week.rate * 100).round();
    final stuck = _stuckNames(prefs);
    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
아침에 사용자가 앱을 열었음. 채팅 밖 말풍선으로 한 마디를 건네는 자리임. 화면 위에 뜨는 작은 말풍선이라, 두 문장 90자 안에서 끝낼 것. 넘으면 뒷말이 잘림.

[이번에 할 이야기 - 사전 부검]
어떤 일을 시작하기 전에 "이 계획이 완전히 망했다고 가정하고" 그 원인을 미리 적어보는 방법이 있음. 미리 꺼내놓은 위험은 시작 전에 치울 수 있어서, 실패 확률이 눈에 띄게 줄어듦.
지난 이레 완료율 $rate%.
$stuck
지난 주가 잘 안 풀린 것을 탓하지 말고, 오늘 계획을 세우기 전에 "무엇 때문에 오늘이 무너질 것 같은지" 두어 개만 먼저 꺼내보자고 할 것. 이 방법의 이름이나 원리는 한 문장으로만 곁들일 것.
*끝나지 않은 일이 위에 적혀 있으면 그중 하나를 이름으로 짚을 것. 무엇을 두고 하는 이야기인지가 분명해야 사용자도 떠올릴 것이 생김. 여러 개를 늘어놓지는 말 것.

[출력]
- 그 말만 쓸 것. 태그나 따옴표, 머리말 없이 코치의 말투 그대로.
- 위 지시문의 말투를 따라 쓰지 말 것. 지시문은 설명일 뿐이고, 실제로 쓸 말투는 위에 주어진 코치의 말투임.''';

    final response = await _chatProxy.call({
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
    });
    final content = (response.data is Map
            ? (response.data as Map)['content'] as String? ?? ''
            : '')
        .trim();
    if (content.isEmpty) return;

    await prefs.setString(_preMortemAtKey, DateTime.now().toIso8601String());
    await _takeMorning(prefs);
    await CoachSayService.say(coachId: coachId, text: content);
  }

  /// "알아서 할게"를 눌렀다.
  ///
  /// 닫기만 있던 때는 말없이 사라지는 것이 유일한 답이었고, 앱은 그 침묵을
  /// 세어 듣기 싫은 것인지 바빴던 것인지 짐작해야 했다. 물어보면 짐작할
  /// 일이 없다.
  ///
  /// 한 번으로는 쉬지 않는다. 그날 바빴을 수도 있고 그 계획에 할 말이
  /// 없었을 수도 있다. 어제도 사양했으면 그때 물러난다.
  static Future<void> onAdviceDeclined() async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayKey();
    final yesterday = _dayKey(
      DateTime.now().subtract(const Duration(days: 1)),
    );

    final parts = (prefs.getString(_declineKey) ?? '').split('|');
    final lastDay = parts.length == 2 ? parts.first : '';
    final lastCount = parts.length == 2 ? int.tryParse(parts.last) ?? 0 : 0;
    // 오늘 이미 셌으면 그대로 두고, 어제 셌으면 이어서 센다.
    final count = lastDay == today
        ? lastCount
        : lastDay == yesterday
        ? lastCount + 1
        : 1;
    await prefs.setString(_declineKey, '$today|$count');

    if (count < restAfterDeclines) return;
    await prefs.setString(
      _restUntilKey,
      DateTime.now().add(restLength).toIso8601String(),
    );
  }

  /// "그렇게 해볼게"를 눌렀다. 세어둔 사양은 없던 일이 된다.
  static Future<void> onAdviceAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_declineKey);
  }

  /// 마스터 플랜 전용이다. 틈새 코칭과 같은 자리다.
  ///
  /// 말하는 코치는 지금 쓰는 코치 그대로다. 마스터 플랜이어도 냥이와 대화
  /// 중이면 냥이가 건넨다.
  static Future<bool> _hasMasterPlan() async {
    final userData = await UserDataService.load();
    return userData.isPlanActive && userData.planType == 'master';
  }

  static bool _maySpeakNow(
    SharedPreferences prefs,
    Duration gap, {
    String atKey = _lastSaidAtKey,
  }) {
    final restUntil = DateTime.tryParse(prefs.getString(_restUntilKey) ?? '');
    if (restUntil != null && DateTime.now().isBefore(restUntil)) return false;

    final lastAt = DateTime.tryParse(prefs.getString(atKey) ?? '');
    if (lastAt == null) return true;
    return DateTime.now().difference(lastAt) >= gap;
  }

  /// 아직 잊지 않은 이름들. 일주일 지난 것은 목록에서 빠진다.
  ///
  /// 그만큼 지난 계획은 그때의 계획이라, 같은 말을 다시 해볼 만하다.
  static Set<String> _handledNames(SharedPreferences prefs) {
    final from = DateTime.now().subtract(handledLife);
    final out = <String>{};
    for (final entry in _handledEntries(prefs)) {
      if (entry.at.isAfter(from)) out.add(entry.text);
    }
    return out;
  }

  static List<_Handled> _handledEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_handledKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final out = <_Handled>[];
      for (final item in (jsonDecode(raw) as List).whereType<Map>()) {
        final text = item['text']?.toString() ?? '';
        final at = DateTime.tryParse(item['at']?.toString() ?? '');
        if (text.isEmpty || at == null) continue;
        out.add(_Handled(text: text, at: at));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _logAdvice(
    SharedPreferences prefs, {
    required String taskText,
    required _PlanFeedbackKind kind,
  }) async {
    final now = DateTime.now();
    final from = now.subtract(adviceLogLife);
    final kept = [
      for (final item in _adviceLog(prefs))
        if (item.at.isAfter(from) && item.task != taskText) item,
      _Advice(task: taskText, kind: kind.name, at: now),
    ];
    if (kept.length > 5) kept.removeRange(0, kept.length - 5);
    await prefs.setString(
      _adviceLogKey,
      jsonEncode([
        for (final item in kept)
          {
            'task': item.task,
            'kind': item.kind,
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
          _Advice(task: task, kind: item['kind']?.toString() ?? '', at: at),
        );
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// 오늘 아침에 이미 한 마디 했는지.
  ///
  /// 아침에 나갈 수 있는 이야기가 셋이다. 따로 세면 어떤 날은 아침부터
  /// 세 마디를 듣는다.
  static bool _morningTaken(SharedPreferences prefs) {
    final at = DateTime.tryParse(prefs.getString(_morningSaidKey) ?? '');
    return at != null && _isToday(at);
  }

  static Future<void> _takeMorning(SharedPreferences prefs) =>
      prefs.setString(_morningSaidKey, DateTime.now().toIso8601String());

  /// 오늘 코치를 몇 번 불렀는지. 날짜가 바뀌면 0부터다.
  static int _asksToday(SharedPreferences prefs) {
    final raw = prefs.getString(_askCountKey) ?? '';
    final parts = raw.split('|');
    if (parts.length != 2 || parts.first != _todayKey()) return 0;
    return int.tryParse(parts.last) ?? 0;
  }

  static Future<void> _countAsk(SharedPreferences prefs) async {
    await prefs.setString(
      _askCountKey,
      '${_todayKey()}|${_asksToday(prefs) + 1}',
    );
  }

  static bool _isToday(DateTime at) => _dayKey(at) == _todayKey();

  static String _todayKey() => _dayKey(DateTime.now());

  static String _dayKey(DateTime at) => '${at.year}-${at.month}-${at.day}';

  static Future<void> _remember(
    SharedPreferences prefs,
    String taskText,
  ) async {
    await prefs.setString(_lastSaidAtKey, DateTime.now().toIso8601String());

    final now = DateTime.now();
    final from = now.subtract(handledLife);
    final handled = [
      // 지난 것은 여기서 떨어져 나간다. 같은 이름을 다시 짚었으면 새 시각으로.
      for (final entry in _handledEntries(prefs))
        if (entry.at.isAfter(from) && entry.text != taskText) entry,
      _Handled(text: taskText, at: now),
    ];
    if (handled.length > handledMemory) {
      handled.removeRange(0, handled.length - handledMemory);
    }
    await prefs.setString(
      _handledKey,
      jsonEncode([
        for (final entry in handled)
          {'text': entry.text, 'at': entry.at.toIso8601String()},
      ]),
    );
    // 이름만 담던 옛 칸은 이제 아무도 읽지 않는다.
    await prefs.remove(_oldHandledKey);
  }

  /// 어느 이야기를 꺼낼지. 없으면 null.
  ///
  /// 완료율이 갈림길이 아니라 관문이다. 해내고 있는 사람에게는 계획이 많든
  /// 시각이 비었든 말을 걸지 않는다.
  static _PlanFeedbackKind? _pickKind({
    required SharedPreferences prefs,
    required String taskText,
    required bool hasTime,
    required int todayCount,
    required _RecentRates recent,
  }) {
    // 임시로 열어둔 동안에는 아래 두 관문을 건너뛴다. 갈래를 고르는 규칙은
    // 그대로 두고, "이 사람에게 말을 걸 자리인가"만 넘긴다.
    if (!debugAlwaysSpeak) {
      // 그 이름으로 이미 해내고 있는 일은 건드리지 않는다. 뭉뚱그려 적어도
      // 그 사람에게는 그걸로 충분하다는 뜻이다.
      if (_provenTask(prefs, taskText)) return null;

      // 기록이 아직 없다. 오늘 처음 쓰는 사람이다.
      //
      // 완료율로 재는 갈래는 근거가 없어 쓸 수 없고, 첫마디부터 계획을
      // 뜯어보는 것도 아니다. 처음 만난 자리라 알아주는 말이 먼저다.
      if (!recent.hasData) {
        return hasTime ? null : _PlanFeedbackKind.firstDay;
      }
    }

    // 시각을 적어둔 일은 건드리지 않는다.
    //
    // 언제 할지를 정해둔 것 자체가 이미 계획을 구체화한 것이다. 거기다 대고
    // 더 다듬자고 하면 그건 도움이 아니라 검사다. 코치에게 맡기지 않고
    // 여기서 가른다 — 판단이 아니라 사실이라 흔들릴 이유가 없다.
    //
    // 오늘 잡은 양 이야기는 여기 없다. 그건 항목 하나가 아니라 하루 전체를
    // 보는 말이라 [_speakVolume]이 따로 맡는다.
    if (hasTime) return null;

    // 해내고 있으면 인정부터 하고 시작한다.
    if (recent.rate > lowRate) return _PlanFeedbackKind.steady;

    // 언제 할지가 비어 있다. 큰 계획이면 오늘 할 몫부터 정하자는 쪽으로
    // 코치가 갈아탄다.
    return _PlanFeedbackKind.when;
  }

  /// 주로 언제 손을 대는 사람인지. 표본이 모자라면 빈 문자열.
  ///
  /// 밤에 시작해서 밤에 끝내는 사람이 있다. 그 사람에게 "오늘 안에 될까"라고
  /// 묻는 것과 "오늘도 밤에 시작하려나"라고 묻는 것은 다르다. 뒤엣말은 그
  /// 사람을 보고 하는 말이다.
  static String _whenNote(SharedPreferences prefs, _RecentRates recent) {
    final hours = <int>[];
    for (final record in _history(prefs, days: 14)) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        final at = DateTime.tryParse(
          task['startedAt']?.toString() ??
              task['completedAt']?.toString() ??
              '',
        );
        if (at != null) hours.add(at.hour);
      }
    }
    // 두엇으로 "밤형"이라고 적으면 없는 버릇을 지어내는 것이 된다.
    if (hours.length < 4) return '';
    final night = hours.where((hour) => hour >= 19 || hour < 4).length;
    final morning = hours.where((hour) => hour >= 5 && hour < 12).length;
    final struggling = recent.hasData && recent.rate <= lowRate;
    if (night / hours.length >= 0.6) {
      // 같은 저녁형이라도 해내고 있는 사람과 아닌 사람에게 할 말이 다르다.
      // 그 리듬으로 끝내고 있는 사람에게 당기라고 하면 남의 리듬을 권하는
      // 것이 되고, 밤마다 못 끝내는 사람에게는 시간이 모자란 것이 원인이다.
      return struggling
          ? '주로 저녁이나 밤에 손을 대는데 끝나는 비율은 낮음.\n'
                '*시작을 30분에서 한 시간쯤 당겨 미리 정해두자고 권할 수 있음. 밤에는 남은 시간이 적어서 한 번 밀리면 그날이 끝나버림.'
          : '주로 저녁이나 밤에 손을 대는 편. 그 리듬으로 해내고 있으니 당기라고 하지 말 것.';
    }
    if (morning / hours.length >= 0.6) {
      return '주로 오전에 손을 대는 편.';
    }
    return '';
  }

  /// 지난 이레에 여러 번 올라왔는데 끝나지 않은 일들.
  ///
  /// "한 주가 안 풀렸다"는 말만으로는 무엇을 두고 하는 이야기인지 알 수 없다.
  /// 이름을 짚어주면 사전 부검이 막연한 반성이 아니라 그 일에 대한 이야기가
  /// 된다.
  static String _stuckNames(SharedPreferences prefs) {
    final planned = <String, int>{};
    final done = <String, int>{};
    for (final record in _history(prefs, days: 7)) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        final text = task['text']?.toString().trim() ?? '';
        if (text.isEmpty) continue;
        planned[text] = (planned[text] ?? 0) + 1;
        if (task['done'] == true) done[text] = (done[text] ?? 0) + 1;
      }
    }
    final stuck = <String>[];
    for (final entry in planned.entries) {
      if (entry.value < 2) continue;
      final finished = done[entry.key] ?? 0;
      if (finished >= entry.value / 2) continue;
      stuck.add("'${entry.key}' (${entry.value}번 중 $finished번 완료)");
      if (stuck.length >= 3) break;
    }
    if (stuck.isEmpty) return '';
    return '여러 번 올라왔는데 끝나지 않은 일: ${stuck.join(', ')}';
  }

  /// 그 이름이 최근에 어떻게 굴러갔는지. 코치가 아는 체할 거리다.
  ///
  /// 이력을 세는 일은 원래도 하고 있었다. 다만 "건드릴까 말까"를 정하는 데만
  /// 쓰고 버렸다. 같은 숫자를 코치에게 넘기면 "요즘 자주 올라오는데 잘 안
  /// 되네" 같은 말이 되고, 그 한 마디가 있고 없고에 따라 조언이 남 얘기처럼
  /// 들리는지가 갈린다.
  static String _taskHistoryNote(SharedPreferences prefs, String taskText) {
    if (taskText.isEmpty) return '';
    final records = _history(prefs, days: 14);
    var appeared = 0;
    var done = 0;
    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        if (task['text']?.toString().trim() != taskText) continue;
        appeared++;
        if (task['done'] == true) done++;
      }
    }
    if (appeared == 0) {
      return '이 이름은 최근 2주 기록에 없음. 처음 적는 계획이거나 오랜만인 것.';
    }
    return '이 이름은 최근 2주에 $appeared번 올라왔고 그중 $done번 끝냈음.';
  }

  /// 그 이름을 최근에 꾸준히 해냈는지.
  static bool _provenTask(SharedPreferences prefs, String taskText) {
    final records = _history(prefs, days: 14);
    var appeared = 0;
    var done = 0;
    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        if (task['text']?.toString().trim() != taskText) continue;
        appeared++;
        if (task['done'] == true) done++;
      }
    }
    if (appeared < 3) return false;
    return done / appeared >= provenRate;
  }

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
      if (item['isVacation'] == true) continue;
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  static List<Map<String, dynamic>> _todayTasks(SharedPreferences prefs) {
    final raw = prefs.getString('nyang_tasks');
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((task) => Map<String, dynamic>.from(task))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 오늘 목록에 무엇이 더 있는지. 코치가 지금 상황에 대고 말하도록 넘긴다.
  ///
  /// 계획 이름 한 줄만 보고 하는 말은 어느 날에 해도 맞는 말이라, 두어 번만
  /// 들어도 판박이가 된다. 오늘 다른 일이 몇 개 있고 무엇이 끝났는지를 알면
  /// 같은 조언도 오늘의 말이 된다.
  static String _todaySummary(
    List<Map<String, dynamic>> tasks,
    String taskText,
  ) {
    final others = <String>[];
    var done = 0;
    for (final task in tasks) {
      if (task['done'] == true) done++;
      final text = task['text']?.toString().trim() ?? '';
      if (text.isEmpty || text == taskText) continue;
      if (others.length < 8) {
        others.add('${task['done'] == true ? 'V' : ' '} $text');
      }
    }
    if (others.isEmpty) return '오늘 목록에는 이것 하나뿐임.';
    return '오늘 목록의 나머지(V는 끝낸 것): ${others.join(', ')}. '
        '${tasks.length}개 중 $done개 끝냄.';
  }

  /// 지금이 하루의 어디쯤인지. 밤에 적은 계획에 "오늘 어디까지"를 물으면
  /// 그건 오늘 얘기가 아니게 된다.
  static String _clockNote(DateTime now) {
    final hour = now.hour;
    final label = hour < 6
        ? '새벽'
        : hour < 12
        ? '오전'
        : hour < 18
        ? '오후'
        : hour < 22
        ? '저녁'
        : '밤';
    final left = hour >= 21
        ? ' 오늘 안에 손댈 시간은 거의 남지 않았음. 오늘 하라는 말은 하지 말 것.'
        : hour >= 18
        ? ' 오늘 남은 시간이 많지 않음.'
        : '';
    return '지금 $label $hour시.$left';
  }

  /// 최근 며칠의 완료율과 하루 평균 완료 개수. 오늘은 빼고 센다.
  ///
  /// 오늘 것은 아직 끝나지 않았다. 진행 중인 일을 실패로 세면 하루가 저물기
  /// 전에는 누구나 완료율이 낮은 사람이 된다.
  ///
  /// 평균을 낼 때는 계획을 적은 날만 분모에 넣는다. 안 적은 날까지 나누면
  /// 며칠에 한 번 적고 그날은 다 해내는 사람이 "하루 0.6개 하는 사람"이
  /// 되어, 다섯 개만 잡아도 많다는 말을 듣는다.
  static _RecentRates _recentRates(
    SharedPreferences prefs, {
    required int days,
  }) {
    final today = _todayKey();
    var total = 0;
    var done = 0;
    var plannedDays = 0;
    for (final record in _history(prefs, days: days)) {
      final date = DateTime.tryParse(record['date']?.toString() ?? '');
      if (date == null || _dayKey(date) == today) continue;
      final tasks = (record['tasks'] as List?) ?? const [];
      if (tasks.isEmpty) continue;
      plannedDays++;
      for (final task in tasks) {
        if (task is! Map) continue;
        total++;
        if (task['done'] == true) done++;
      }
    }
    if (total == 0) {
      return const _RecentRates(hasData: false, rate: 0, doneAverage: 0);
    }
    return _RecentRates(
      hasData: true,
      rate: done / total,
      doneAverage: done / plannedDays,
    );
  }

  /// 총량 이야기에서 할 말. 앱이 번갈아 고른다.
  ///
  /// 프롬프트에 둘을 나란히 두고 코치에게 고르라고 하면 늘 앞엣것이 나온다.
  /// 호출이 매번 독립이라 코치는 지난번에 무엇을 골랐는지 모르고, "매번
  /// 다르게"라는 말은 그래서 아무 일도 하지 않는다. 기억이 있는 쪽이 고른다.
  static const List<String> _slackAdvices = [
    '- 하루 평균 완료 개수에서 한둘 더한 정도가 알맞아 보인다고 짚어줄 것. 몇 개에서 몇 개 사이라고 수를 밝힐 것. 다만 몇 분이면 끝나는 잡무는 그 셈에서 빼자고 덧붙일 것 — 잡무까지 세면 정작 손이 많이 가는 일이 밀려남.',
    '- 급하지 않은 것은 아예 요일을 정해 옮겨두자고 할 것. 무엇이 급한지는 사용자가 앎. 어느 것을 옮기라고 짚지는 말 것. 뇌는 하던 일에서 다른 일로 넘어갈 때마다 다시 올라타는 시간을 씀. 하루에 조금씩 여러 가지를 흩어놓으면 그 시간만 늘어나서, 같은 양을 해도 더 오래 걸리고 더 지침.',
    '- 오늘 그만큼의 시간과 체력이 정말 있는지 물어보고, 20% 정도는 여유로 남겨두자고 할 것. 예상 못한 일은 늘 생기고, 꽉 채운 계획은 하나만 밀려도 뒤가 전부 밀림.',
  ];

  /// 나눠보자는 말을 꺼내는 여러 방식. 이것도 앱이 번갈아 고른다.
  ///
  /// 같은 말이 매번 나오면 두어 번 만에 판박이로 읽힌다. 뜻은 하나지만
  /// 입는 옷은 여러 벌이다.
  static const List<String> _splitPhrases = [
    "'오늘 할 양을 두세 단계로 나눠보면'",
    "'할 일을 두세 갈래로 나눠보면'",
    "'오늘 몫을 두세 토막으로 끊어보면'",
    "'오늘 어디까지 할지 두세 번에 나눠 잡아보면'",
  ];

  static const String _slackAdviceKey = 'plan_feedback_slack_advice';
  static const String _splitPhraseKey = 'plan_feedback_split_phrase';

  static Future<String> _nextSlackAdvice() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_slackAdviceKey) ?? -1;
    final next = (last + 1) % _slackAdvices.length;
    await prefs.setInt(_slackAdviceKey, next);
    return _slackAdvices[next];
  }

  static Future<String> _nextSplitPhrase() async {
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_splitPhraseKey) ?? -1;
    final next = (last + 1) % _splitPhrases.length;
    await prefs.setInt(_splitPhraseKey, next);
    return _splitPhrases[next];
  }

  /// 코치에게 한 문장을 부탁한다. 짚을 것이 없으면 null.
  static Future<String?> _askCoach({
    required String coachId,
    required _PlanFeedbackKind kind,
    required String taskText,
    required bool hasTime,
    required int todayCount,
    required _RecentRates recent,
    required String todaySummary,
    required String historyNote,
    required String whenNote,
  }) async {
    final coach = CoachConfigs.get(coachId);
    final rate = (recent.rate * 100).round();
    final slackAdvice = await _nextSlackAdvice();
    final splitPhrase = await _nextSplitPhrase();

    final situation = switch (kind) {
      _PlanFeedbackKind.steady =>
        '''[이번에 할 이야기 - 잘 되고 있는 사람]
최근 이레 완료율 $rate% (오늘 제외). 적어둔 것을 대체로 해내는 사람임.
방금 적은 일: '$taskText'${hasTime ? '' : ' (시각을 정해두지 않음)'}
오늘 계획 $todayCount개, 계획을 적은 날 기준 하루 평균 완료 ${recent.doneAverage.toStringAsFixed(1)}개.
해내고 있다는 것을 먼저 인정하는 데서 시작할 것.
그다음 무엇이 도움이 될지 하나만 고를 것.
- 가서 하고 오면 끝나는 볼일('미용실 가기', '병원 가기', '장 보기')이면 손댈 것 없음. SKIP.
- 얼마나 할지가 비어 있는 일('독서', '공부하기', '글쓰기'): 계획을 구체화할 필요가 있어 보인다고 짚고, 오늘은 어디까지 할지부터 정해보자고 할 것. 이때 무리가 되지 않는 최소선으로 잡자고 할 것. 넉넉히 잡아둔 양은 미루는 이유가 되지만, 가볍게 잡아둔 양은 일단 시작하게 만들고 대개 거기서 더 감. 얼마로 정할지는 사용자가 앎. 대신 정해주지 말 것.
- 할 일은 정해졌는데 한 번에 하기 벅찬 일('기획서 쓰기', '홍보 방향 점검', '줄넘기 1000번'): 오늘 할 몫을 두세 개로 나눠보자고 할 것. 나눠두면 그 조각들이 진도를 재는 눈금이 됨. 눈금이 있으면 하나 끝낼 때마다 해냈다는 신호가 와서, 끝까지 붙어 있기가 쉬워짐. 나누는 것도 사용자가 함.
  나눠보자는 말은 이렇게 꺼낼 것: $splitPhrase
- 크기는 괜찮은데 언제 할지가 비어 있음: 몇 시에 할지 정해두자고 할 것. 정해둔 사람이 그러지 않은 사람보다 목표 달성률이 두세 배 높았음. 장소는 어디서 하느냐에 따라 그 일이 실제로 달라질 때만 같이 물을 것. 어디서 하든 똑같은 일이면 묻지 말 것.
어느 것도 해당하지 않으면 SKIP.''',
      _PlanFeedbackKind.firstDay =>
        '''[이번에 할 이야기 - 처음 적은 계획]
이 사람이 이 앱에 계획을 적은 것이 오늘이 처음임. 아직 기록이 없어 어떻게 실행하는 사람인지 알 수 없음.
방금 적은 일: '$taskText' (시각을 정해두지 않음)
고칠 거리를 찾지 말 것. 처음 만난 자리에서 계획부터 뜯어보면 검사받는 기분이 됨.
1) 무엇을 하려는 사람인지 그 계획에서 읽히는 것을 한 마디로 알아줄 것. 계획 이름을 그대로 불러주되, 그 사람이 왜 그것을 적었을지 짐작해서 단정하지는 말 것.
2) 그다음 몇 시에 할지 물어볼 것. 시각이나 상황이 정해져 있으면 실제로 일어날 확률이 훨씬 높아진다는 것을 짧게 곁들여도 좋음.
크기가 큰지 작은지, 얼마나 할지가 비었는지는 오늘 말하지 말 것. 그건 며칠 지켜본 뒤에 할 이야기임.''',
      _PlanFeedbackKind.when =>
        '''[이번에 할 이야기 - 실행 의도]
심리 연구에 따르면 '언제, 어디서, 어떻게 할 것인지'까지 정해둔 사람은 그러지 않은 사람보다 목표 달성률이 두세 배 높았음. "글을 쓴다"보다 "오전 9시에 책상에 앉아 바로 첫 문장을 쓴다"가 실제로 일어남.
방금 적은 일: '$taskText' (시각을 정해두지 않음)
먼저 그 계획에서 읽히는 것을 한 마디로 알아줄 것. 무엇을 하려는 사람인지 짚어주는 정도면 됨. 잘하고 있다는 말은 하지 말 것 — 사실이 아니면 빈말로 들리고, 그 뒤에 붙는 말까지 같이 가벼워짐.
그다음 이 계획이 어느 쪽인지 보고, 그중 하나만 말할 것.
- 무엇을 어디서 할지가 이미 분명하고 한 번에 끝나는 일('미용실 가기', '병원 가기', '장 보기')이면 손댈 것 없음. SKIP.
- 무엇을 얼마나 할지가 비어 있는 일('글쓰기', '공부하기', '홍보 점검'): 오늘 그 일에서 무엇을 어디까지 할지부터 정해보자고 하되 무리가 되지 않는 최소선으로 잡자고 할 것. 넉넉히 잡아둔 양은 미루는 이유가 됨. 시각 이야기는 꺼내지 말 것 — 무엇을 할지 모르는 채로 시각부터 잡는 것은 순서가 뒤바뀐 데다, 한 번에 두 가지를 물으면 어느 쪽에도 답하기 어려움.
- 할 일은 정해졌는데 한 번에 하기 벅찬 일('기획서 쓰기', '줄넘기 1000번'): 오늘 할 몫을 두세 개로 나눠보자고 할 것. 나눠두면 그 조각들이 진도를 재는 눈금이 됨. 눈금이 있으면 하나 끝낼 때마다 해냈다는 신호가 와서, 끝까지 붙어 있기가 쉬워짐. 어떻게 나눌지는 사용자가 정함.
- 무엇을 얼마나 할지는 분명한데 언제 할지만 비어 있음: 그 연구 이야기를 한 문장으로 곁들이고 몇 시에 할지 정해보자고 할 것. 장소는 어디서 하느냐에 따라 그 일이 실제로 달라질 때만 같이 물을 것(집에서 할지 헬스장에 갈지). 어디서 하든 똑같은 일이면 묻지 말 것(약 먹기).
- 결과물까지 여러 단계를 거치거나 며칠 넘게 걸릴 일('소설 1화 완성', '신작 준비')이면 그건 오늘의 계획이 아니라 목표임. 목표에는 눈금이 없어 오늘 무엇을 했는지 알 수가 없으니, 오늘 할 한 조각을 정해보자고 할 것.''',
      _PlanFeedbackKind.slack =>
        '''[이번에 할 이야기 - 오늘 계획한 양]
오늘 계획 $todayCount개. 계획을 적은 날 기준 하루 평균 완료는 ${recent.doneAverage.toStringAsFixed(1)}개임.
숫자를 들이대며 "당신은 평균 몇 개"라고 하지 말 것. 그건 성적표를 읽어주는 말이 됨. 대신 계획 수가 많으면 완료율이 떨어지더라는 이야기를 먼저 꺼내고, 그다음에 이 사람의 숫자를 근거로 제안할 것.
$slackAdvice
줄이라고 지시하지 말고, 어떻게 생각하는지 물으며 끝낼 것.''',
    };

    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
사용자가 방금 오늘 할 일 하나를 적음. 그 옆에서 짧게 한 마디를 건네는 자리임. 대화창이 아니라 화면 위에 뜨는 작은 말풍선이라, 두 문장 100자 안에서 끝낼 것.

[지금 상태]
${_clockNote(DateTime.now())}
$todaySummary
*이건 무엇을 말할지 고르는 데만 쓸 것. 문장에 옮기지 말 것.

[이 계획의 지난 자취]
$historyNote
$whenNote
*여기 적힌 것이 있으면 알아주는 자리에 쓸 것. 요즘 자주 올라오는 일인지, 처음 적는 일인지를 아는 체하면 남 얘기처럼 들리지 않음. 숫자를 그대로 읊지는 말 것.
*주로 손을 대는 시간대가 적혀 있으면 그것도 쓸 수 있음. "오늘도 밤에 시작하려나?"처럼 묻는 자리에 어울림. 다만 늦다고 나무라는 말로는 쓰지 말 것 — 그 시간에 해내고 있는 사람이면 그게 그 사람의 리듬임.

$situation

[출력]
- 짚을 것이 있으면 그 말만 쓸 것. 태그나 따옴표, 머리말 없이 코치의 말투 그대로.
- 위 지시문의 말투를 따라 쓰지 말 것. 지시문은 설명일 뿐이고, 실제로 쓸 말투는 위에 주어진 코치의 말투임.
- 무엇이 비었는지 짚기만 하지 말고 무엇을 하면 되는지까지 말한 뒤, 물어보는 말로 끝낼 것.
- 왜 그렇게 하면 나은지를 반드시 한 조각 곁들일 것. 근거가 있어야 사용자가 따를 가능성이 높아짐. 다만 심플한 한 마디로 언급할 것.
- 한 가지만 말할 것. 짚을 것도 하나, 권할 것도 하나. 여러 개를 담으면 무엇을 하라는 말인지 흐려짐.
- 이 계획에 그 이야기가 맞지 않으면(이미 충분히 구체적이거나, 짚을 것이 없으면) SKIP 한 단어만 출력할 것.''';

    final response = await _chatProxy.call({
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
      'temperature': 0.7,
    });

    final content = (response.data is Map
            ? (response.data as Map)['content'] as String? ?? ''
            : '')
        .trim();
    if (content.isEmpty) return null;
    if (content.toUpperCase().startsWith('SKIP')) return null;
    return content;
  }
}

enum _PlanFeedbackKind {
  /// 오늘 처음 적어보는 사람. 고칠 거리보다 알아주는 말이 먼저다.
  firstDay('처음 적은 계획을 반기고, 몇 시에 할지 물어본 이야기', '몇 시에 할지 정해보자고'),

  /// 잘 되고 있는 사람. 무슨 이야기를 할지는 코치가 고른다.
  steady('그 계획을 오늘 할 만한 크기로 다듬는 이야기', '오늘 할 몫을 나눠보자고'),

  /// 언제 어디서 할지를 정해보자.
  when(
    '그 계획을 오늘 할 만한 크기로 다듬거나, 몇 시에 할지 정하는 이야기',
    '오늘 어디까지 할지 정해보자고',
  ),

  /// 여유는 넣었나.
  slack('오늘 잡은 일이 평소 해내던 양보다 많아 보인다는 이야기', '오늘 잡은 양을 줄여보자고');

  const _PlanFeedbackKind(this.topic, this.shortAdvice);

  /// 다음 턴에 코치가 읽을 한 줄. 무슨 얘기를 꺼냈던 것인지 알려준다.
  final String topic;

  /// 인사 문구에 끼워 넣을 짧은 표현. "~했던"으로 이어진다.
  final String shortAdvice;
}

/// 짚은 계획 하나와 짚은 때.
/// 언제 무엇을 두고 무슨 조언을 했는지.
class _Advice {
  const _Advice({required this.task, required this.kind, required this.at});

  final String task;
  final String kind;
  final DateTime at;
}

class _Handled {
  const _Handled({required this.text, required this.at});

  final String text;
  final DateTime at;
}

class _RecentRates {
  const _RecentRates({
    required this.hasData,
    required this.rate,
    required this.doneAverage,
  });

  final bool hasData;
  final double rate;
  final double doneAverage;
}
