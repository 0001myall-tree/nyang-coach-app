import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'coach_id_service.dart';

/// 평소 해내던 것보다 계획이 훨씬 많은 날, 인사 자리에서 건네는 말.
///
/// 예전에는 할 일을 적는 중에 다이얼로그로 끼어들어 "많다"고 했다. 두 가지가
/// 틀려 있었다.
///
/// **적는 것을 말렸다.** 머릿속에 든 것을 다 쏟아내는 일은 오히려 부하를 더는
/// 쪽이다. 쏟아낼 자리가 오늘 목록뿐인데 거기에 대고 그만 적으라고 하면, 도움이
/// 되는 행동에 제동을 거는 셈이 된다.
///
/// **자리가 틀렸다.** 적는 순간은 의욕이 올라와 있어서 무슨 말을 해도 안
/// 들린다. 그 목록을 실제로 마주하는 것은 다음 날 아침이고, 도움이 필요한
/// 것도 그때다.
///
/// 그래서 적는 것은 놔두고, 마주하는 자리에서 말을 건다. 그리고 "줄여라"라고
/// 하지 않는다 - 계획이 많은 이유는 여럿이라 앱이 가릴 수 없다. 진짜 다 해야
/// 하는 사람도 있고, 쏟아낸 것이 섞인 사람도 있고, 놓기 싫어서 못 빼는 사람도
/// 있다. 그 판단은 이 사람 목록을 읽은 코치가 한다.
///
/// 첫 줄만 여기서 고정 문구로 낸다. 상태를 짚고 기다리라고 하는 데까지다.
/// 그 뒤에 코치가 오늘 목록을 보고 구체적으로 잇는다.
class OverplanNudgeService {
  const OverplanNudgeService._();

  /// 한 번 말하면 이만큼 쉰다.
  ///
  /// 매일 조건에 걸리는 사람이 있다. 계획 여덟아홉에 완료 하나둘인 사람은
  /// 열흘 내내 걸리는데, 그러면 같은 자리에서 매일 말을 거는 셈이라 도움이
  /// 아니라 소음이 된다.
  ///
  /// 이레가 아니라 닷새인 이유는 요일이다. 이레면 한 번 걸린 요일에 계속
  /// 걸려서 늘 같은 날에만 들린다. 닷새면 요일이 돌아가 여러 상황에서 걸린다.
  static const int cooldownDays = 5;

  /// 마지막으로 말한 날짜(yyyy-MM-dd).
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 그 접두어는 클라우드 복원이 덮어쓰는데,
  /// 이건 이 기기에서 오늘 말했다는 사실이라 덮이면 안 된다.
  static const String _lastGreetedDateKey = 'overplan_greeted_date';

  /// 최근 실제 완료 최대치보다 이 개수 이상 많을 때만 말한다.
  ///
  /// 한동안 2였다. 그러면 평소 두 개 해내던 사람이 네 개만 적어도 걸려서,
  /// 조금 많은 날까지 매번 짚였다. 5면 진짜 무리한 날만 남는다.
  static const int overBy = 5;

  /// 말을 거는 시간대.
  ///
  /// 오늘을 어떻게 다룰지 이야기라 하루가 남아 있어야 뜻이 있다. 저녁에
  /// "오늘 많네"는 이미 할 수 있는 것이 없는 말이다.
  ///
  /// 이른 아침부터 여는 것은 하루를 그리기 전에 듣는 편이 낫기 때문이다.
  /// 근무 시간인지는 보지 않는다 - 알림이 아니라 앱을 연 사람에게만 보이는
  /// 말이라, 이미 그 사람이 시간을 낸 순간이다.
  static const int fromHour = 7;
  static const int untilHour = 19;

  /// 이 자리를 쓰는 코치.
  ///
  /// 첫 줄 뒤에 코치가 지은 말이 이어지는 자리라, 그 말을 못 짓는 코치에게는
  /// 첫 줄만 남아 "그래서 뭐?"가 된다.
  static bool speaks(String coachId) {
    final id = CoachIdService.normalize(coachId);
    return id == CoachIdService.defaultCoachId || CoachIdService.isMaster(id);
  }

  /// 오늘 말을 걸 자리인지. 걸 자리면 최근 하루 최대 완료 개수를, 아니면 null.
  ///
  /// 돌려주는 숫자는 코치에게 넘길 근거다. 사용자에게 보이는 첫 줄에는 안
  /// 들어간다.
  static Future<int?> shouldGreet({
    required int plannedCount,
    required String? historyRaw,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    if (at.hour < fromHour || at.hour >= untilHour) return null;

    final prefs = await SharedPreferences.getInstance();
    if (_withinCooldown(prefs.getString(_lastGreetedDateKey), at)) return null;

    // 이제 막 쓰기 시작한 사람에게는 "평소보다 많다"고 할 평소가 없다.
    if (!_hasRecentRecord(historyRaw, at)) return null;

    final recentMax = _recentMaxCompleted(historyRaw, at);
    if (plannedCount < recentMax + overBy) return null;

    debugPrint(
      '[overplan] 오늘 $plannedCount개, 최근 최대 완료 $recentMax개 - 말을 건다',
    );
    return recentMax;
  }

  /// 오늘 말했다고 적는다.
  static Future<void> recordGreeted({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastGreetedDateKey, _dateKey(now ?? DateTime.now()));
  }

  /// 상태를 짚고 기다리라고 하는 첫 줄.
  ///
  /// 숫자를 넣지 않는다. "아홉 개인데 최근 최대가 두 개였어"로 열면 그날 한
  /// 일이 첫 문장에서 지워진다. 숫자는 코치에게만 넘긴다.
  ///
  /// 기다리라는 말로 끝나는 것은 이 줄이 바로 뜨고 코치의 말은 몇 초 뒤에
  /// 오기 때문이다. 그 사이를 그냥 두면 말이 끊긴 것처럼 보인다.
  static String opening(String coachId) {
    switch (CoachIdService.normalize(coachId)) {
      case 'sec_female':
        return '대표님, 지금 평소 해내시던 것보다 계획이 좀 많으시네요. '
            '정신없으실 수 있겠어요.\n잠시만 기다려주세요.';
      case 'nyang_halbae':
        return '지금 평소 해내던 것보다 계획이 많구나, 얘야. 정신없을 만하다.\n'
            '잠깐 기다려보렴.';
      default:
        return '지금 평소 해내던 것보다 계획이 좀 많다냥. 정신없을 수 있겠다냥.\n'
            '잠깐 기다려보라냥.';
    }
  }

  /// 코치가 말을 못 지었을 때 대신 나갈 줄.
  ///
  /// 기다리라고 해놓고 아무것도 안 오는 것이 제일 나쁘다. 뻔한 말이라도 와야
  /// 한다.
  static String fallback(String coachId) {
    switch (CoachIdService.normalize(coachId)) {
      case 'sec_female':
        return '일단 제일 만만한 것 하나만 골라서 시작해보시는 건 어떨까요?';
      case 'nyang_halbae':
        return '일단 제일 만만한 것 하나만 골라보자, 얘야.';
      default:
        return '일단 제일 만만한 것 하나만 골라서 시작해보라냥.';
    }
  }

  /// 마지막으로 말한 날부터 [cooldownDays]가 안 지났는지.
  ///
  /// 예전 형식으로 적힌 값은 날짜로 못 읽는다. 그때는 막지 않는다 - 한 번 더
  /// 나가는 편이, 영영 안 나가는 것보다 낫다.
  @visibleForTesting
  static bool withinCooldown(String? lastGreeted, DateTime now) =>
      _withinCooldown(lastGreeted, now);

  static bool _withinCooldown(String? lastGreeted, DateTime now) {
    if (lastGreeted == null || lastGreeted.isEmpty) return false;
    final at = DateTime.tryParse(lastGreeted);
    if (at == null) return false;
    final days = DateTime(
      now.year,
      now.month,
      now.day,
    ).difference(DateTime(at.year, at.month, at.day)).inDays;
    return days < cooldownDays;
  }

  /// 최근 이레(오늘 제외)에 남은 하루 기록이 하나라도 있는지.
  @visibleForTesting
  static bool hasRecentRecord(String? historyRaw, [DateTime? now]) =>
      _hasRecentRecord(historyRaw, now ?? DateTime.now());

  static bool _hasRecentRecord(String? historyRaw, DateTime now) {
    for (final _ in _recentDays(historyRaw, now)) {
      return true;
    }
    return false;
  }

  /// 최근 이레(오늘 제외) 중 하루에 완료한 개수의 최댓값.
  @visibleForTesting
  static int recentMaxCompleted(String? historyRaw, [DateTime? now]) =>
      _recentMaxCompleted(historyRaw, now ?? DateTime.now());

  static int _recentMaxCompleted(String? historyRaw, DateTime now) {
    var max = 0;
    for (final item in _recentDays(historyRaw, now)) {
      final tasks = (item['tasks'] as List?) ?? const [];
      var done = 0;
      for (final task in tasks) {
        if (task is Map && task['done'] == true) done++;
      }
      if (done > max) max = done;
    }
    return max;
  }

  /// 최근 이레치 하루 기록. 오늘은 빼고 본다 - 아직 안 끝난 날이다.
  static Iterable<Map> _recentDays(String? historyRaw, DateTime now) sync* {
    if (historyRaw == null || historyRaw.isEmpty) return;
    List<dynamic> list;
    try {
      list = jsonDecode(historyRaw) as List<dynamic>;
    } catch (_) {
      return;
    }
    final from = now.subtract(const Duration(days: 7));
    final today = _dateKey(now);
    for (final item in list) {
      if (item is! Map) continue;
      final raw = item['date']?.toString() ?? '';
      if (raw == today) continue;
      final date = DateTime.tryParse(raw);
      if (date == null || date.isBefore(from)) continue;
      yield item;
    }
  }

  static String _dateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
