import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import '../screens/coach_config.dart';
import 'coach_say_service.dart';

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
  static const String _handledKey = 'plan_feedback_handled';
  static const String _restUntilKey = 'plan_feedback_rest_until';

  /// 말을 거는 간격. 매일이면 계획을 적을 때마다 검사받는 기분이 된다.
  static const Duration interval = Duration(days: 2);

  /// 해내고 있는 사람에게 말을 거는 간격.
  ///
  /// 아예 침묵하는 것보다 낫다. 완료율이 높아도 계획을 뭉뚱그려 적는 버릇은
  /// 남아 있을 수 있고, 그건 언젠가 일이 커졌을 때 걸린다. 다만 잘 굴러가는
  /// 사람에게 이틀마다는 참견이라 하루를 더 띄운다.
  static const Duration steadyInterval = Duration(days: 3);

  /// 이미 짚은 이름을 몇 개까지 기억할지. 여기 있는 이름에는 말을 걸지 않는다.
  static const int handledMemory = 7;

  /// "알아서 할게"를 누르면 이만큼 쉰다.
  ///
  /// 이틀에 한 번 오는 말이라, 한 번 사양하면 일주일을 사는 셈이다. 그 정도는
  /// 되어야 누르는 쪽이 가볍다.
  static const Duration restLength = Duration(days: 7);

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

  static final HttpsCallable _chatProxy = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable('chatProxy');

  /// 오늘의 핵심으로 하나를 새로 지정했다.
  ///
  /// 적을 때마다 말을 걸던 때는 '미용실 가기'에까지 조언이 붙었다. 사용자가
  /// 스스로 중요하다고 고른 일은 대개 한 번에 안 끝나는 일이라, 계획을 다듬는
  /// 이야기가 실제로 쓸모 있는 자리다.
  ///
  /// 실패해도 조용히 지나간다. 계획을 적는 일이 이것 때문에 막히면 안 된다.
  static Future<void> onCoreTaskSet({
    required String coachId,
    required String taskText,
    required bool hasTime,
  }) async {
    try {
      await _speak(
        coachId: coachId,
        taskText: taskText.trim(),
        hasTime: hasTime,
        onlyTooMany: false,
      );
    } catch (e) {
      debugPrint('plan feedback failed: $e');
    }
  }

  /// 그냥 할 일 하나를 저장했다.
  ///
  /// 핵심을 고르지 않는 사람에게도 도울 자리가 하나는 있어야 한다. 다만 여기서는
  /// 그날 잡은 양이 평소 해내던 것보다 훨씬 많을 때만 말한다 — 그건 항목 하나를
  /// 두고 하는 판단이 아니라 하루 전체를 보는 이야기라, '미용실 가기'에 조언이
  /// 붙던 종류의 참견이 되지 않는다.
  static Future<void> onTaskSaved({
    required String coachId,
    required String taskText,
    required bool hasTime,
  }) async {
    try {
      await _speak(
        coachId: coachId,
        taskText: taskText.trim(),
        hasTime: hasTime,
        onlyTooMany: true,
      );
    } catch (e) {
      debugPrint('plan feedback failed: $e');
    }
  }

  static Future<void> _speak({
    required String coachId,
    required String taskText,
    required bool hasTime,
    required bool onlyTooMany,
  }) async {
    if (taskText.isEmpty) return;

    if (!await _hasMasterPlan()) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final recent = _recentRates(prefs, days: 2);
    // 해내고 있으면 뜸하게. 완료율이 간격을 정한다.
    final gap = recent.hasData && recent.rate > lowRate
        ? steadyInterval
        : interval;
    if (!_maySpeakNow(prefs, gap)) return;
    // 한 번 짚은 항목은 다시 짚지 않는다. 고쳤든 안 고쳤든, 같은 말을 두 번
    // 하는 순간 조언이 잔소리가 된다.
    if ((prefs.getStringList(_handledKey) ?? const []).contains(taskText)) {
      return;
    }

    final today = _todayTasks(prefs);
    final kind = _pickKind(
      prefs: prefs,
      taskText: taskText,
      hasTime: hasTime,
      todayCount: today.length,
      recent: recent,
      onlyTooMany: onlyTooMany,
    );
    if (kind == null) return;

    final line = await _askCoach(
      coachId: coachId,
      kind: kind,
      taskText: taskText,
      hasTime: hasTime,
      todayCount: today.length,
      recent: recent,
    );
    // 코치가 짚을 것이 없다고 했다. 쿨타임은 쓰지 않는다.
    if (line == null || line.isEmpty) return;

    await _remember(prefs, taskText);
    await CoachSayService.say(coachId: coachId, text: line);
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
    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
아침에 사용자가 앱을 열었습니다. 당신은 채팅 밖 말풍선으로 한 마디를 건넵니다. 화면 위에 뜨는 작은 말풍선이라, 두 문장 90자 안에서 끝내세요. 넘으면 뒷말이 잘립니다.

[이번에 할 이야기 - 사전 부검]
어떤 일을 시작하기 전에 "이 계획이 완전히 망했다고 가정하고" 그 원인을 미리 적어보는 방법이 있습니다. 미리 꺼내놓은 위험은 시작 전에 치울 수 있어서, 실패 확률이 눈에 띄게 줄어듭니다.
지난 이레 완료율은 $rate%였습니다.
지난 주가 잘 안 풀린 것을 탓하지 말고, 오늘 계획을 세우기 전에 "무엇 때문에 오늘이 무너질 것 같은지" 두어 개만 먼저 꺼내보자고 권하세요. 이 방법의 이름이나 원리는 한 문장으로만 곁들이세요.

[출력]
- 그 말만 쓰세요. 태그나 따옴표, 머리말 없이 코치의 말투 그대로.''';

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
    await CoachSayService.say(coachId: coachId, text: content);
  }

  /// "알아서 할게"를 눌렀다. 그 말을 그대로 받아 한동안 쉰다.
  ///
  /// 닫기만 있던 때는 말없이 사라지는 것이 유일한 답이었고, 앱은 그 침묵을
  /// 세어 듣기 싫은 것인지 바빴던 것인지 짐작해야 했다. 물어보면 짐작할
  /// 일이 없다.
  static Future<void> onAdviceDeclined() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _restUntilKey,
      DateTime.now().add(restLength).toIso8601String(),
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

  static bool _maySpeakNow(SharedPreferences prefs, Duration gap) {
    final restUntil = DateTime.tryParse(prefs.getString(_restUntilKey) ?? '');
    if (restUntil != null && DateTime.now().isBefore(restUntil)) return false;

    final lastAt = DateTime.tryParse(prefs.getString(_lastSaidAtKey) ?? '');
    if (lastAt == null) return true;
    return DateTime.now().difference(lastAt) >= gap;
  }

  static Future<void> _remember(
    SharedPreferences prefs,
    String taskText,
  ) async {
    await prefs.setString(_lastSaidAtKey, DateTime.now().toIso8601String());
    final handled = <String>[...(prefs.getStringList(_handledKey) ?? const [])];
    handled.add(taskText);
    // 최근 일곱 개만 기억한다. 여기 있는 이름은 건너뛰므로, 이게 그대로 "다시
    // 짚기까지 걸리는 시간"이 된다 — 이틀에 하나씩 채우니 보름쯤이다.
    // 그만큼 지난 계획은 그때의 계획이라, 같은 말을 다시 해볼 만하다.
    if (handled.length > handledMemory) {
      handled.removeRange(0, handled.length - handledMemory);
    }
    await prefs.setStringList(_handledKey, handled);
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
    bool onlyTooMany = false,
  }) {
    // 핵심을 고르지 않은 사람에게는 양 이야기 하나만.
    if (onlyTooMany) {
      if (!recent.hasData || recent.rate > lowRate) return null;
      return todayCount >= recent.doneAverage + tooManyMargin
          ? _PlanFeedbackKind.slack
          : null;
    }

    // 그 이름으로 이미 해내고 있는 일은 건드리지 않는다. 뭉뚱그려 적어도
    // 그 사람에게는 그걸로 충분하다는 뜻이다.
    if (_provenTask(prefs, taskText)) return null;

    // 기록이 아직 없다. 오늘 처음 쓰는 사람이다.
    //
    // 완료율로 재는 두 갈래는 근거가 없어 쓸 수 없다. 다만 시각이 비었다는
    // 것은 지금 보이므로 실행 의도만 연다 — 첫날이 첫인상이라, 계획을 함께
    // 다듬는 장면을 한 번은 보여줄 만하다.
    if (!recent.hasData) {
      return hasTime ? null : _PlanFeedbackKind.when;
    }

    // 해내고 있으면 아무 말도 하지 않는다.
    //
    // 잘하는 사람에게 건넬 말이 없는 것은 아니다(_PlanFeedbackKind.steady에
    // 그 문구가 남아 있다). 다만 코치가 어떤 말투로 그 이야기를 꺼내는지
    // 아직 확인되지 않았고, 다 해내고 있는 사람에게 조언이 붙으면 그게 곧장
    // 참견으로 읽힌다. 캐릭터가 서고 나면 그때 열어도 늦지 않다.
    if (recent.rate > lowRate) return null;

    // 여기서부터는 무엇이 걸리고 있는지를 고른다. 셋 다 완료율이 낮은 사람에게
    // 하는 이야기라, 순서는 그날 무엇이 눈에 띄는지로 정한다.

    // 오늘 잡은 양이 최근에 해내는 양보다 눈에 띄게 많다. 그날의 걸림돌은 총량이다.
    if (todayCount >= recent.doneAverage + tooManyMargin) {
      return _PlanFeedbackKind.slack;
    }

    // 시각이 없다. 언제 할지를 정하는 이야기가 먼저다 — 큰 계획이면 오늘 할
    // 조각부터 고르자는 쪽으로 코치가 갈아탄다.
    if (!hasTime) return _PlanFeedbackKind.when;

    // 시각도 있고 양도 많지 않은데 안 끝난다. 남은 것은 계획 하나의 크기다.
    return _PlanFeedbackKind.shrink;
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

  /// 최근 며칠의 완료율과 하루 평균 완료 개수.
  static _RecentRates _recentRates(
    SharedPreferences prefs, {
    required int days,
  }) {
    final records = _history(prefs, days: days);
    var total = 0;
    var done = 0;
    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        total++;
        if (task['done'] == true) done++;
      }
    }
    if (records.isEmpty || total == 0) {
      return const _RecentRates(hasData: false, rate: 0, doneAverage: 0);
    }
    return _RecentRates(
      hasData: true,
      rate: done / total,
      doneAverage: done / records.length,
    );
  }

  /// 코치에게 한 문장을 부탁한다. 짚을 것이 없으면 null.
  static Future<String?> _askCoach({
    required String coachId,
    required _PlanFeedbackKind kind,
    required String taskText,
    required bool hasTime,
    required int todayCount,
    required _RecentRates recent,
  }) async {
    final coach = CoachConfigs.get(coachId);
    final rate = (recent.rate * 100).round();

    final situation = switch (kind) {
      _PlanFeedbackKind.steady =>
        '''[이번에 할 이야기 - 잘 되고 있는 사람]
최근 이틀 완료율은 $rate%다. 적어둔 것을 대체로 해내는 사람이다.
방금 핵심으로 지정한 일: '$taskText'${hasTime ? '' : ' (시각을 정해두지 않음)'}
오늘 계획은 $todayCount개, 최근 이틀 하루 평균 완료는 ${recent.doneAverage.toStringAsFixed(1)}개.
해내고 있다는 것을 먼저 인정하는 데서 시작하세요.
그다음 무엇이 도움이 될지 하나만 고르세요.
- 하루에 끝날 크기가 아니면: 한 과제로 두지 말고 진도가 보이도록 나눠보자고. 나눠두면 하나씩 지워지는 것이 눈에 보여서 성취감이 더 자주 옵니다.
- 크기는 괜찮은데 언제 할지가 비어 있으면: 시각과 장소까지 정해두자고. 정해둔 사람이 그러지 않은 사람보다 목표 달성률이 두세 배 높았습니다.
- 오늘 잡은 양이 평소 해내던 것보다 눈에 띄게 많으면: 그 차이를 짚고, 오늘 그만큼의 시간과 체력이 실제로 있는지 함께 셈해보자고. 잘 해내던 사람일수록 자기 속도를 높게 잡습니다.
셋 다 해당하지 않으면 SKIP.''',
      _PlanFeedbackKind.when =>
        '''[이번에 할 이야기 - 실행 의도]
심리 연구에 따르면 '언제, 어디서, 어떻게 할 것인지'까지 정해둔 사람은 그러지 않은 사람보다 목표 달성률이 두세 배 높았다. "글을 쓴다"보다 "오전 9시에 책상에 앉아 바로 첫 문장을 쓴다"가 실제로 일어난다.
방금 핵심으로 지정한 일: '$taskText' (시각을 정해두지 않음)
이 계획이 언제 어디서 할지 정해두면 달라질 만한 것이면, 그 연구 이야기를 한 문장으로 곁들이고 시각과 장소를 정해보자고 권하세요.
다만 이 계획이 하루에 끝날 크기가 아니면 — 며칠에서 몇 주에 걸칠 일이면 — 그건 계획이 아니라 목표입니다. 목표에는 눈금이 없어서 오늘 무엇을 했는지 알 수가 없습니다. 이때는 시각보다 먼저 오늘 할 한 조각을 정해보자고 권하세요. 9시에 앉아도 무엇을 하는지 모르면 시각은 쓸모가 없습니다.''',
      _PlanFeedbackKind.slack =>
        '''[이번에 할 이야기 - 계획 오류]
사람은 자기 능력을 과신해서 과거에 실제로 걸린 시간을 무시한다. 그래서 계획에는 20~30%의 여유를 미리 넣어야 실패율이 낮아진다.
방금 핵심으로 지정한 일: '$taskText'
오늘 계획은 $todayCount개인데, 최근 이틀 하루 평균 완료는 ${recent.doneAverage.toStringAsFixed(1)}개였다.
그 차이를 한 문장으로 짚고, 여유 시간과 체력까지 셈에 넣었는지 물어보세요. 계획을 줄이라고 지시하지 말고 물어보는 자리입니다.''',
      _PlanFeedbackKind.shrink =>
        '''[이번에 할 이야기 - 목표 구체화]
거창한 최종 목표보다 당장 오늘 할 구체적인 과제에 집중할 때 실행력이 훨씬 높아진다.
사람들이 세우는 계획은 목표만 거창하고 정작 계획은 없는 경우가 많다. 목표를 할 일의 조각으로 나눠두면 그 조각들이 진도를 재는 눈금이 되고, 성취 동기를 높인다.
방금 핵심으로 지정한 일: '$taskText'
최근 이틀 완료율은 $rate%다.
이 계획이 오늘 손대기에 너무 뭉뚱그려져 있으면, 목표를 눈금이 될 만한 조각으로 나눠 그중 오늘 할 것만 추리자고 권하세요.''',
    };

    final prompt =
        '''${coach.systemPrompt}

[지금 상황]
사용자가 방금 할 일 하나를 오늘의 핵심으로 지정했습니다. 스스로 오늘 중요하다고 고른 일입니다. 당신은 그 옆에서 짧게 한 마디를 건넵니다. 대화창이 아니라 화면 위에 뜨는 작은 말풍선이라, 두 문장 90자 안에서 끝내세요. 넘으면 뒷말이 잘려서 사용자에게 닿지 않습니다.

$situation

[출력]
- 짚을 것이 있으면 그 말만 쓰세요. 태그나 따옴표, 머리말 없이 코치의 말투 그대로.
- 원리만 말하고 끝내면 사용자는 무엇을 바꿔야 할지 모릅니다. 사용자가 방금 쓴 그 계획을 실제로 고쳐 쓴 모습을 하나 보여주거나, 무엇을 정하면 되는지 물어보는 말로 끝내세요.
- 이 계획에 그 이야기가 맞지 않으면 (이미 충분히 구체적이거나, 짚을 것이 없으면) SKIP 한 단어만 출력하세요.''';

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
  /// 잘 되고 있는 사람. 무슨 이야기를 할지는 코치가 고른다.
  steady,

  /// 언제 어디서 할지를 정해보자.
  when,

  /// 여유는 넣었나.
  slack,

  /// 오늘 할 크기로 줄이자.
  shrink,
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
