import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';

/// 오늘 계획한 일이 최근 실제로 해낸 최대치보다 훨씬 많을 때, 그게
/// 부지런함이 아니라 회피일 수 있다고 짚어주는 자리.
///
/// 계획을 많이 세우는 것 자체는 눈에 보이는 성취라, 실제로 해낼 수 있는지와
/// 무관하게 하기 쉽다. 할 일을 추가하기만 하고 구체화하지 않으면 그 일을
/// '언젠가'로 미루는 것과 다르지 않다.
///
/// 문구는 코치를 부르지 않고 고정 문장으로 낸다 - 매번 API를 부를 만큼
/// 중요한 판단이 필요한 자리가 아니다.
///
/// 구독 중인 모든 코치(프렌즈/마스터)에 연다. 등록창(할 일 탭)에서 두 번
/// 이어지는 다이얼로그로 묻고, 그 문답을 [recordChatTurns]로 남기면 채팅
/// 화면이 다음에 열릴 때 마치 그 자리에서 대화한 것처럼 재생한다.
/// 같은 상황에서도 어떤 말투로 짚을지.
enum OverplanTone {
  /// 최근에 하나도 못 해낸 사람이 다시 잡을 때. 숫자를 꺼내지 않고 응원한다.
  restart,

  /// 평소보다 많이 잡았을 때 처음 건네는 말. 하나만 먼저 고르자고 권한다.
  gentle,

  /// 부드럽게 말한 다음에도 또 같은 자리에 왔을 때. 많이 잡으면 오히려
  /// 진짜 중요한 걸 놓칠 수 있다고 짚는다.
  direct,
}

class OverplanNudgeService {
  const OverplanNudgeService._();

  /// 마지막으로 짚은 날짜(yyyy-MM-dd). 조건을 넘긴 순간 이 값부터 채운다.
  static const String _lastFiredDateKey = 'overplan_nudge_last_date';

  /// 마지막으로 어떤 말투로 짚었는지([OverplanTone.name]).
  static const String _lastToneKey = 'overplan_nudge_last_tone';

  /// 한 번 짚은 뒤 다시 짚기까지 비우는 날수.
  ///
  /// 하루 한 번 제한만 있던 동안에는 계획을 크게 잡는 사람이 매일 같은 말을
  /// 들었다. 매일 들으면 조언이 아니라 잔소리가 된다.
  static const int _cooldownDays = 3;

  /// "알아서 할게"를 고른 뒤 이 자리를 쉬는 날수.
  ///
  /// 그건 이 이야기를 지금은 듣고 싶지 않다는 답이다. 사흘 뒤에 또 같은 말을
  /// 꺼내면 답을 못 들은 것처럼 군다.
  static const int _dismissedCooldownDays = 7;

  /// 이 날(yyyy-MM-dd)이 될 때까지는 짚지 않는다. [recordDismissed]가 적는다.
  static const String _snoozeUntilKey = 'overplan_nudge_snooze_until';

  /// 채팅 화면이 다음에 열릴 때 읽어가는 자리. [isUser]/[text] 순서 그대로인
  /// 문답 목록을 담는다.
  static const String pendingChatKey = 'overplan_nudge_pending_chat';

  /// 최근 실제 완료 최대치보다 이 개수 이상 많이 잡았을 때만 짚는다.
  static const int _overBy = 2;

  /// 최근에 하나도 못 해낸 사람에게 짚기 시작하는 개수.
  ///
  /// 완료 최대치가 0이면 [_overBy]만으로는 두 개만 적어도 걸린다. 다시 해보려고
  /// 두 개 적은 사람에게 "두 개만 해도 충분하다"고 말하는 꼴이라, 이쪽은 문턱을
  /// 따로 둔다.
  static const int _restartFireFrom = 4;

  /// 임시 디버그 스위치. true면 쿨다운을 무시하고 매번 다시 짚을 수 있는지만
  /// 본다. 확인 끝나면 반드시 false로 되돌릴 것 - 실제 사용자에게는 절대
  /// 이 상태로 나가면 안 된다.
  static const bool debugIgnoreDailyLimit = false;

  /// 오늘 계획이 조건을 넘겼는지 본다. 넘겼으면 오늘 날짜를 적어두고, 최근 최대
  /// 완료량과 이번에 쓸 말투를 돌려준다. 구독 중이 아니거나, 쿨다운 안이거나,
  /// 조건에 못 미치면 null.
  ///
  /// 마스터뿐 아니라 프렌즈에도 연다 - 토큰을 안 쓰는 고정 문구라 등급을
  /// 가릴 이유가 없다.
  static Future<({int recentMax, OverplanTone tone})?> shouldFire({
    required int plannedCount,
    required String? historyRaw,
  }) async {
    try {
      final userData = await UserDataService.load();
      debugPrint(
        '[overplan] isPlanActive=${userData.isPlanActive} '
        'planType=${userData.planType}',
      );
      if (!userData.isPlanActive) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      final lastFired = prefs.getString(_lastFiredDateKey);
      debugPrint('[overplan] today=$today lastFired=$lastFired');
      if (!debugIgnoreDailyLimit && _withinCooldown(lastFired)) return null;

      final snoozeUntil = prefs.getString(_snoozeUntilKey);
      if (!debugIgnoreDailyLimit && _isSnoozed(snoozeUntil)) {
        debugPrint('[overplan] snoozed until $snoozeUntil');
        return null;
      }

      // 최근 기록이 아예 없으면 짚지 않는다. 이제 막 쓰기 시작한 사람에게는
      // "평소보다 많다"고 할 평소가 없다.
      if (!_hasRecentRecord(historyRaw)) {
        debugPrint('[overplan] no recent record');
        return null;
      }

      final recentMax = _recentMaxCompleted(historyRaw);
      final need = recentMax == 0 ? _restartFireFrom : recentMax + _overBy;
      debugPrint(
        '[overplan] plannedCount=$plannedCount recentMax=$recentMax '
        'need=$need',
      );
      if (plannedCount < need) return null;

      final tone = _nextTone(recentMax, prefs.getString(_lastToneKey));
      await prefs.setString(_lastFiredDateKey, today);
      await prefs.setString(_lastToneKey, tone.name);
      return (recentMax: recentMax, tone: tone);
    } catch (e) {
      debugPrint('overplan nudge check failed: $e');
      return null;
    }
  }

  /// 처음 건네는 말. 최근 최대 완료량([recentMax])을 넣어 "그냥 많다"가
  /// 아니라 "평소보다 이만큼 많다"를 실감하게 한다. 코치마다 말투가 달라
  /// 여섯 갈래로 나뉜다.
  /// 마지막으로 짚은 날([lastFired])로부터 [_cooldownDays]가 안 지났는지.
  ///
  /// 예전 형식('2026-9-3')으로 적힌 값은 날짜로 못 읽는다. 그때는 막지 않는다 -
  /// 한 번 더 나가는 편이, 영영 안 나가는 것보다 낫다.
  @visibleForTesting
  static bool withinCooldown(String? lastFired) => _withinCooldown(lastFired);

  static bool _withinCooldown(String? lastFired) {
    if (lastFired == null || lastFired.isEmpty) return false;
    final at = DateTime.tryParse(lastFired);
    if (at == null) return false;
    final now = DateTime.now();
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    return days < _cooldownDays;
  }

  /// "알아서 할게"를 골랐다. 이 이야기를 일주일 쉰다.
  static Future<void> recordDismissed() async {
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(
      const Duration(days: _dismissedCooldownDays),
    );
    await prefs.setString(_snoozeUntilKey, _dateKey(until));
  }

  /// [until]이 아직 안 왔는지.
  @visibleForTesting
  static bool isSnoozed(String? until) => _isSnoozed(until);

  static bool _isSnoozed(String? until) {
    if (until == null || until.isEmpty) return false;
    final at = DateTime.tryParse(until);
    if (at == null) return false;
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).isBefore(DateTime(at.year, at.month, at.day));
  }

  /// 이번에 쓸 말투.
  ///
  /// 완료가 0인 사람에게는 늘 응원부터 한다. 그 외에는 부드러운 쪽과 짚는 쪽을
  /// 번갈아 낸다 - 회피 이야기는 한 번이면 전해지고, 되풀이하면 잔소리가 된다.
  @visibleForTesting
  static OverplanTone nextTone(int recentMax, String? lastToneName) =>
      _nextTone(recentMax, lastToneName);

  static OverplanTone _nextTone(int recentMax, String? lastToneName) {
    if (recentMax == 0) return OverplanTone.restart;
    return lastToneName == OverplanTone.gentle.name
        ? OverplanTone.direct
        : OverplanTone.gentle;
  }

  /// 채팅 중 코치가 방금 일정을 넣어준 직후에 건네는 말.
  ///
  /// 오늘 탭 쪽([primaryMessage])은 진짜 중요한 걸 놓칠 수 있다는 이야기까지 가지만,
  /// 여기는 코치가 막 추가해준 자리라 그렇게 몰아붙이면 이상하다. "정말 다
  /// 되겠냐"고 가볍게 확인만 한다. 톤을 나누지 않는다 - 방금 하나 늘려준
  /// 참이라 반복해서 짚을 일이 잦지 않다.
  static String chatAddMessage(String coachId) {
    switch (coachId) {
      case 'sec_female':
        return '대표님, 오늘 계획이 평소 완료하시던 것보다 좀 많아 보이네요. '
            '정말 다 해내실 수 있으시겠어요?';
      case 'cat':
        return '집사, 오늘 계획이 평소 완료하던 것보다 좀 많아 보인다냥. 진짜 '
            '다 할 수 있겠냥?';
      case 'boyfriend':
        return '오늘 계획이 평소 완료하던 것보다 좀 많아 보이는데, 진짜 다 '
            '할 수 있겠어?';
      case 'halmae':
        return '오늘 계획이 평소 해내던 것보다 좀 많아 보이는구나. 진짜 다 '
            '할 수 있겠나?';
      case 'bro':
        return '오늘 계획이 평소 해내던 것보다 좀 많은데? 진짜 다 할 수 '
            '있겠어?';
      default:
        return '오늘 계획이 평소 완료하던 것보다 좀 많아 보인다냥. 진짜 다 '
            '할 수 있겠냥?';
    }
  }

  static String primaryMessage(
    String coachId,
    int recentMax, {
    OverplanTone tone = OverplanTone.direct,
  }) {
    if (tone == OverplanTone.restart) return _restartMessage(coachId);
    if (tone == OverplanTone.gentle) return _gentleMessage(coachId);
    switch (coachId) {
      case 'sec_female':
        return '대표님, 최근 잘 해내신 날이 하루 $recentMax개 정도였는데 오늘 계획은 그보다 '
            '훨씬 많으시네요. 할 일을 많이 잡으시면 오히려 정말 중요한 일을 뒤로 '
            '미루게 되실 수도 있어요. 새로 더하시는 것보다 이미 적어두신 '
            '것 하나를 실행 가능하게 다듬으시는 쪽이 해내실 가능성이 더 높습니다.';
      case 'cat':
        return '집사, 최근 잘 해낸 날도 하루 $recentMax개 정도였는데 오늘은 그보다 훨씬 '
            '많다냥. 할 일을 많이 적으면 오히려 진짜 중요한 할 일을 미루게 '
            '될 수도 있다냥. 계획을 늘리기보단 꼭 해야 하는 계획을 실행 '
            '가능하게 구체화하는 쪽이 해낼 가능성이 더 높다냥.';
      case 'boyfriend':
        return '최근 잘 해낸 날도 하루 $recentMax개 정도였는데 오늘은 그보다 훨씬 많네. '
            '할 일을 많이 적으면 오히려 진짜 중요한 걸 미루게 될 수도 있어. '
            '새로 더하기보다 이미 적어둔 것 하나를 구체적으로 어떻게 할지 정해두는 '
            '쪽이 해낼 가능성이 더 높아.';
      case 'halmae':
        return '이 녀석아, 최근 잘한 날도 하루 $recentMax개 정도였는데 오늘은 그보다 '
            '훨씬 많네. 많이 적어둔다고 다 되는 게 아니다 - 오히려 진짜 중요한 걸 '
            '놓칠 수도 있는 기라. 새로 보태지 말고 꼭 해야 하는 것 위주로 '
            '야무지게 계획해서 해보는 건 어떠냐.';
      case 'bro':
        return '야, 최근 잘한 날도 하루 $recentMax개 정도였는데 오늘 계획은 그보다 훨씬 '
            '많다? 계획만 쌓는다고 갓생 되는 거 아니다 - 오히려 진짜 중요한 거 '
            '놓칠 수도 있어. 새로 추가하지 말고 있는 거 하나부터 제대로 구체화해봐. '
            '그게 훨씬 잘 될 확률 높다.';
      default:
        return '최근 잘 해낸 날이 하루 $recentMax개 정도였는데, 오늘 계획은 '
            '그보다 훨씬 많구나. 할 일을 많이 잡으면 오히려 진짜 중요한 할 일을 '
            '미루게 될 수도 있다냥. 새로 더하는 것보다 이미 적어둔 것 하나를 '
            '실행 가능하게 구체화하는 쪽이 해낼 가능성이 더 높다.';
    }
  }

  /// 평소보다 많이 잡았을 때 처음 건네는 말.
  ///
  /// 회피 이야기를 대뜸 꺼내지 않는다. 많이 적는 게 늘 회피인 것도 아니고,
  /// 아직 아무것도 안 해본 사람에게 속을 넘겨짚는 말이 되기도 한다. 여기서는
  /// 다 하려 들지 말고 하나만 먼저 고르자는 데까지만 간다.
  static String _gentleMessage(String coachId) {
    switch (coachId) {
      case 'sec_female':
        return '대표님, 오늘 일정이 평소보다 많으시네요. 다 해내려 하시기보다, 꼭 '
            '끝내고 싶으신 것 하나만 먼저 골라보시는 건 어떨까요?';
      case 'cat':
        return '집사, 오늘 할 일이 평소보다 많다냥. 다 하려고 하기보다, 꼭 끝내고 '
            '싶은 것 하나만 먼저 골라볼까냥?';
      case 'boyfriend':
        return '오늘 할 일이 평소보다 많네. 다 하려고 하기보다, 꼭 끝내고 싶은 것 '
            '하나만 먼저 골라볼까?';
      case 'halmae':
        return '오늘은 적어둔 게 평소보다 많구먼. 다 하려 들지 말고, 꼭 끝내고 싶은 '
            '것 하나만 먼저 골라보자.';
      case 'bro':
        return '오늘 할 일 평소보다 많은데? 다 하려고 하지 말고 꼭 끝내고 싶은 거 '
            '하나만 먼저 골라보자.';
      default:
        return '오늘 할 일이 평소보다 많네. 다 하려고 하기보다, 꼭 끝내고 싶은 것 '
            '하나만 먼저 골라볼까?';
    }
  }

  /// 최근에 하나도 못 해낸 사람이 오늘 많이 잡았을 때.
  ///
  /// "잘 해낸 날도 하루 0개"라고 들이대면, 다시 해보려는 사람에게 못 한 날을
  /// 세어 보이는 말이 된다. 여기서는 숫자를 꺼내지 않고 응원부터 하고, 오늘
  /// 몇 개면 충분한지만 알려준다.
  static String _restartMessage(String coachId) {
    switch (coachId) {
      case 'sec_female':
        return '대표님, 다시 마음을 잡으셨군요. 응원하겠습니다. 다만 처음부터 많이 '
            '잡으시면 금방 지치세요. 오늘은 두 가지 정도만 정하셔도 충분합니다.';
      case 'cat':
        return '집사, 다시 의욕적으로 계획하는 거냥? 냥이는 응원한다냥. 그래도 갑자기 '
            '많이 하면 체한다냥. 오늘은 딱 2개 정도만 골라도 냥이는 충분하다고 본다냥.';
      case 'boyfriend':
        return '오, 다시 해보려는 거야? 좋다. 근데 처음부터 많이 잡으면 금방 지쳐. '
            '오늘은 두 개 정도만 정해도 충분해.';
      case 'halmae':
        return '아이고, 다시 마음 잡았는갑네. 잘했다. 근데 첨부터 욕심내면 탈 나는 '
            '기라. 오늘은 두 개만 딱 정해도 충분하다.';
      case 'bro':
        return '오 다시 시동 거는 거냐? 좋다ㅋㅋ 근데 첨부터 풀로 땡기면 삼일 못 간다. '
            '오늘은 두 개만 잡고 가자.';
      default:
        return '다시 해보려는 거구나. 응원할게. 그래도 갑자기 많이 잡으면 지치기 '
            '쉬워. 오늘은 두 개 정도만 정해도 충분해.';
    }
  }

  /// 첫 물음에 "그렇게 할게"를 골랐을 때 한 번 더 건네는 말.
  static String followupMessage(String coachId) {
    switch (coachId) {
      case 'sec_female':
        return '그럼 기존 계획을 구체화해볼까요, 대표님?';
      case 'cat':
        return '그럼 기존 계획을 구체화해볼까냥?';
      case 'boyfriend':
        return '그럼 기존 계획부터 구체적으로 정해볼까?';
      case 'halmae':
        return '그라믄 있는 거부터 야무지게 정해볼까?';
      case 'bro':
        return '그럼 있는 거부터 제대로 파볼까?';
      default:
        return '그럼 기존 계획을 구체화해볼까냥?';
    }
  }

  /// 다이얼로그에서 오간 문답을 남긴다. [turns]는 `{'isUser': bool, 'text': String}`
  /// 목록이고, 순서가 곧 대화 순서다.
  static Future<void> recordChatTurns(
    List<Map<String, dynamic>> turns,
  ) async {
    if (turns.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingChatKey, jsonEncode(turns));
  }

  /// 채팅 화면 쪽에서 부른다. 남겨둔 문답이 있으면 가져오고, 없으면 null.
  /// 가져오면 지운다 - 한 번만 재생하면 된다.
  static Future<List<Map<String, dynamic>>?> takePendingChatTurns() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pendingChatKey);
    if (raw == null || raw.isEmpty) return null;
    await prefs.remove(pendingChatKey);
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map>().map((e) {
        return e.map((key, value) => MapEntry(key.toString(), value));
      }).toList();
    } catch (_) {
      return null;
    }
  }

  /// 최근 이레(오늘 제외)에 남은 하루 기록이 하나라도 있는지.
  @visibleForTesting
  static bool hasRecentRecord(String? historyRaw) =>
      _hasRecentRecord(historyRaw);

  static bool _hasRecentRecord(String? historyRaw) {
    if (historyRaw == null || historyRaw.isEmpty) return false;
    List<dynamic> list;
    try {
      list = jsonDecode(historyRaw) as List<dynamic>;
    } catch (_) {
      return false;
    }
    final from = DateTime.now().subtract(const Duration(days: 7));
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from) || _isToday(date)) continue;
      return true;
    }
    return false;
  }

  /// 최근 이레(오늘 제외) 중 하루에 완료한 개수의 최댓값.
  static int _recentMaxCompleted(String? historyRaw) {
    if (historyRaw == null || historyRaw.isEmpty) return 0;
    List<dynamic> list;
    try {
      list = jsonDecode(historyRaw) as List<dynamic>;
    } catch (_) {
      return 0;
    }
    final from = DateTime.now().subtract(const Duration(days: 7));
    var max = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from) || _isToday(date)) continue;
      final tasks = (item['tasks'] as List?) ?? const [];
      var done = 0;
      for (final task in tasks) {
        if (task is Map && task['done'] == true) done++;
      }
      if (done > max) max = done;
    }
    return max;
  }

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  /// 쿨다운을 날짜로 재려면 다시 읽을 수 있어야 한다(yyyy-MM-dd).
  static String _todayKey() => _dateKey(DateTime.now());

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
