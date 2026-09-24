/// 다음 개입을 계산해 저장하고, 그 시각에 깨어나도록 걸어둔다.
///
/// 앱이 열릴 때와 할 일이 바뀔 때마다 돈다. 계산은 Dart가 하고 네이티브는 그
/// 시각에 깨어나 "아직 유효한가"만 본다 — 틈새 카드 문구를 미리 만들어 두는
/// 것과 같은 방식이다. 판단을 두 벌로 두면 한쪽만 고쳤을 때 두 폰이 다르게 군다.
///
/// 미리 만든 계획은 낡을 수 있다. 그 시각이 되기 전에 그 일을 끝냈거나 지웠을
/// 수 있어서, 네이티브가 띄우기 전에 그 일이 아직 남아 있는지 확인한다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import 'active_coaching_plan.dart';
import 'active_coaching_promise.dart';
import 'active_coaching_state.dart';
import 'active_coaching_target.dart';
import 'active_coaching_time.dart';
import 'busy_hours_service.dart';
import 'gap_coaching_service.dart';
import 'nyang_banner_nudge.dart';

class ActiveCoachingSync {
  const ActiveCoachingSync._();

  /// 딴짓 방지·틈새 코칭과 같은 채널을 쓴다. 자리를 하나 더 맡는 것뿐이라
  /// 같은 네이티브 층이 예약과 노출을 함께 관리한다.
  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/ongoing_nudge',
  );

  /// 개입이 실제로 나갔다고 네이티브가 적어두는 자리.
  ///
  /// 걸러져 지나간 차례와 구분해야 한다. 나가지도 않은 개입 때문에 오늘 몫이
  /// 줄면, 정작 말을 걸어야 할 때 코치가 입을 다문다.
  static const String shownKey = 'active_coaching_shown';

  /// 네이티브가 읽어갈 자리.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기에서 방금 만든 계획이라 클라우드가
  /// 덮으면 안 되고, 다른 기기에서 만든 것이 내려와도 뜻이 없다.
  static const String plannedKey = 'active_coaching_plan';

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// "지금 한번 보기"가 기다리는 중인지. 네이티브도 같은 자리를 본다.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기에서 방금 누른 사실이라 클라우드가
  /// 덮으면 안 된다.
  static const String testUntilKey = 'active_coaching_test_until';

  /// 앱을 나갈 때까지 기다려주는 길이.
  static const Duration testWindow = Duration(minutes: 2);

  /// 지금 상태로 다음 개입을 다시 잡는다.
  static Future<void> sync() async {
    if (!GapCoachingService.isSupported) return;

    final held = await SharedPreferences.getInstance();
    await held.reload();
    final testUntil = held.getInt(testUntilKey);
    if (testUntil != null &&
        DateTime.now().millisecondsSinceEpoch < testUntil) {
      // 확인용으로 걸어둔 자리가 기다리는 중이다. 여기서 다시 계산하면 그
      // 계획이 지워져, 눌러도 아무 일이 안 일어난다.
      return;
    }

    final userData = await UserDataService.load();
    final master = userData.isPlanActive && userData.planType == 'master';
    if (!master || !await GapCoachingService.isEnabled()) {
      await _clear();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now();

    await _consumeShown(prefs, now);

    final tasks = _decode(prefs.getString('nyang_tasks'));
    final liveIds = <String>{
      for (final item in tasks)
        if (item is Map && (item['id']?.toString() ?? '').isNotEmpty)
          item['id'].toString(),
    };
    // 지운 일이나 다른 날로 옮긴 일이 추적에 남아 있으면, 부를 일이 없는데도
    // 그 약속이 사다리를 탄다.
    final day = ActiveCoachingStore.readDay(prefs, now).pruneMissing(liveIds);
    await ActiveCoachingStore.writeDay(prefs, day);

    final planned = ActiveCoachingPlanner.queue(
      tasks: tasks,
      now: now,
      day: day,
      budget: ActiveCoachingStore.readBudget(prefs, now),
      coreTasks: _decode(prefs.getString('nyang_core_tasks')),
      onDays: await GapCoachingService.days(),
      busyAt: (at) => BusyHoursService.busyNow(prefs, at) != null,
      busyEndAfter: (at) => BusyHoursService.busyEndAt(prefs, at),
      bedtime: prefs.getString('nyang_premium_min_sleep_time'),
      // 적어둔 여유 시간. 예전에는 이 시각마다 옛 틈새 카드가 따로 나갔는데,
      // 그러면 말투도 내용도 다른 두 카드가 1분 사이에 뜬다.
      gapTimes: [
        for (final time in GapCoachingService.parseTimes(
          prefs.getString(GapCoachingService.timesKey),
        ))
          DateTime(now.year, now.month, now.day, time.hour, time.minute),
      ],
    );
    if (planned.isEmpty) {
      await _clear();
      return;
    }
    // 약속 시각으로 잡힌 계획은 추적에서 나와 이름이 없다. 이름 없이 나가면
    // 부를 일이 있는데도 카드가 "하나 정해볼까?"로 뜬다.
    final plans = [for (final plan in planned) _withName(plan, tasks)];
    final plan = plans.first;

    await prefs.setString(plannedKey, jsonEncode(_queuePayload(prefs, plans)));
    if (!_isAndroid) {
      // 아이폰은 미리 예약하는 것 말고는 길이 없다. 다른 배너와 자리가 겹치는지
      // 함께 봐야 해서 예약은 그쪽 한 곳에서 한다.
      await NyangBannerNudge.sync();
      return;
    }
    try {
      await _channel.invokeMethod('syncActiveCoaching', {
        'atMillis': plan.at.millisecondsSinceEpoch,
      });
    } on PlatformException {
      //
    } on MissingPluginException {
      // 네이티브가 아직 없는 빌드.
    }
  }

  /// 네이티브가 내보낸 개입을 예산에 반영한다.
  ///
  /// 답이 있었는지는 여기서 알 수 없다. 카드를 눌러 앱에 들어왔다면 할 일 창이
  /// 따로 적어주므로, 여기서는 일단 무응답으로 센다. 한 번이라도 답하면
  /// 간격이 되돌아간다.
  static Future<void> _consumeShown(
    SharedPreferences prefs,
    DateTime now,
  ) async {
    final raw = prefs.getString(shownKey);
    if (raw == null || raw.isEmpty) return;
    await prefs.remove(shownKey);
    final List items;
    try {
      final decoded = jsonDecode(raw);
      // 앱을 안 연 사이에 여러 번 나갔을 수 있어 목록으로 쌓인다. 예전 빌드는
      // 하나만 적었다.
      items = decoded is List ? decoded : [decoded];
    } catch (_) {
      return;
    }
    var budget = ActiveCoachingStore.readBudget(prefs, now);
    final nudged = <MapEntry<String, DateTime>>[];
    for (final item in items) {
      if (item is! Map) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (item['at'] as num?)?.toInt() ?? now.millisecondsSinceEpoch,
      );
      // 어제 나간 것이면 어제 예산에서 뺄 일이다. 오늘 몫을 대신 깎으면 안 된다.
      if (ActiveCoachingStore.dateKey(at) != ActiveCoachingStore.dateKey(now)) {
        continue;
      }
      final taskId = item['taskId']?.toString();
      // 하루를 닫는 말은 하루 한 번이다. 나간 것을 안 적으면 앱을 열 때마다
      // 다시 걸린다.
      if (item['night'] == true) budget = budget.wrappedUp(at);
      // 사용자가 정한 시각을 확인한 것도 총량에 넣는다. 그 구분은 계획에 담겨
      // 있지 않고, 덜 부르는 쪽으로 틀리는 편이 낫다. 미리 세우는 차례도 같은
      // 셈으로 세워둔다.
      budget = budget
          .spoke(at, taskId: taskId == null || taskId.isEmpty ? null : taskId)
          .noReply();
      if (taskId != null && taskId.isNotEmpty) {
        nudged.add(MapEntry(taskId, at));
      }
    }
    await ActiveCoachingStore.writeBudget(prefs, budget);
    for (final entry in nudged) {
      await ActiveCoachingPromise.noteNudged(
        taskId: entry.key,
        at: entry.value,
      );
    }
  }

  /// 설정에서 "지금 한번 보기"를 눌렀을 때.
  ///
  /// 예산을 건너뛴다. 두 시간을 기다려야만 확인할 수 있으면 아무도 확인하지
  /// 못한다. 대신 이 차례는 예산에서 빼지도 않는다 — 확인하느라 오늘 몫이
  /// 줄면 정작 말을 걸어야 할 때 조용해진다.
  ///
  /// 부를 일이 없으면 false. 그때는 띄울 말도 없다.
  static Future<bool> showTestNow() async {
    if (!_isAndroid) return false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now();
    // 앱을 나가는 순간 [sync]가 돌면서 이 계획을 지워버린다 — 예산이 잠겨
    // 있으면 "부를 자리 없음"이 되기 때문이다. 확인이 끝날 때까지 비켜준다.
    await prefs.setInt(
      testUntilKey,
      now.add(testWindow).millisecondsSinceEpoch,
    );

    final pick = ActiveCoachingTarget.pick(
      tasks: _decode(prefs.getString('nyang_tasks')),
      now: now,
      coreTasks: _decode(prefs.getString('nyang_core_tasks')),
      settled: ActiveCoachingStore.readDay(prefs, now).settled,
    );
    if (pick.isNone) return false;

    final at = now.add(const Duration(seconds: 5));
    final plan = ActiveCoachingPlan(
      at: at,
      signal: pick.signal,
      taskId: pick.taskId,
      taskText: pick.taskText,
    );
    await prefs.setString(plannedKey, jsonEncode(_queuePayload(prefs, [plan])));
    try {
      await _channel.invokeMethod('testActiveCoaching', {
        'atMillis': at.millisecondsSinceEpoch,
      });
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
    return true;
  }

  static ActiveCoachingPlan _withName(ActiveCoachingPlan plan, List tasks) {
    if ((plan.taskText ?? '').trim().isNotEmpty || plan.taskId == null) {
      return plan;
    }
    for (final item in tasks) {
      if (item is! Map || item['id']?.toString() != plan.taskId) continue;
      return ActiveCoachingPlan(
        at: plan.at,
        signal: plan.signal,
        taskId: plan.taskId,
        taskText: item['text']?.toString().trim(),
      );
    }
    return plan;
  }

  /// 오늘 남은 차례 전부를 담은 한 벌.
  ///
  /// 맨 위에는 첫 차례를 그대로 펼쳐 둔다. 진단 화면이 그 자리를 읽는다.
  /// 네이티브와 아이폰 배너는 [queueKey] 목록을 차례로 쓴다 — 하나가 지나가면
  /// 앱을 열지 않아도 다음 것이 걸린다.
  static Map<String, dynamic> _queuePayload(
    SharedPreferences prefs,
    List<ActiveCoachingPlan> plans,
  ) {
    final entries = [for (final plan in plans) _entry(prefs, plan)];
    return {...entries.first, queueKey: entries};
  }

  static const String queueKey = 'queue';

  static Map<String, dynamic> _entry(
    SharedPreferences prefs,
    ActiveCoachingPlan plan,
  ) => {
    ..._payload(prefs, plan),
    // 밤 카드는 답이 다르다. 그 갈래를 네이티브가 알아야 버튼이 달라진다.
    if (plan.signal == ActiveCoachingSignal.nightWrap) 'kind': 'night',
  };

  /// 네이티브가 읽어갈 계획 한 벌.
  ///
  /// 카드에서 "시간이 안 나"를 누르면 그 자리에서 시각을 내밀어야 한다. 시각을
  /// 고르는 규칙은 Dart에 한 벌만 두고, 카드가 뜰 시각을 기준으로 미리 만들어
  /// 싣는다. 이름도 함께 싣는다 — 약속을 걸면 그 시각의 시작 카드가 이 이름으로
  /// 부른다.
  static Map<String, dynamic> _payload(
    SharedPreferences prefs,
    ActiveCoachingPlan plan,
  ) {
    final times = plan.taskId == null
        ? const <DateTime>[]
        : ActiveCoachingTime.choices(
            plan.at,
            bedtime: prefs.getString('nyang_premium_min_sleep_time'),
            busyAt: (at) => BusyHoursService.busyNow(prefs, at) != null,
          );
    return {
      'date': ActiveCoachingStore.dateKey(plan.at),
      'at': plan.at.millisecondsSinceEpoch,
      'title': titleFor(plan),
      if (plan.taskId != null) 'taskId': plan.taskId,
      if ((plan.taskText ?? '').trim().isNotEmpty)
        'taskText': plan.taskText!.trim(),
      if (times.isNotEmpty)
        'times': times.map(ActiveCoachingTime.format).toList(),
    };
  }

  /// 사용자가 답했다고 적는다. 벌어졌던 간격이 되돌아온다.
  static Future<void> noteReplied(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await ActiveCoachingStore.writeBudget(
      prefs,
      ActiveCoachingStore.readBudget(prefs, now).replied(),
    );
  }

  /// 카드에 적을 한 줄.
  ///
  /// 왜 부르는지에 따라 갈린다. 이름을 부를 수 있으면 부른다 — "할 일 하나"라고만
  /// 하면 무엇을 말하는지 떠오르지 않는다.
  @visibleForTesting
  static String titleFor(ActiveCoachingPlan plan) {
    final name = _shorten(plan.taskText ?? '');
    if (name.isEmpty) {
      return plan.signal == ActiveCoachingSignal.nightWrap
          ? nightAskTitle
          : askTitle;
    }
    return switch (plan.signal) {
      // 사용자가 정한 시각이다. 재촉이 아니라 약속을 확인하는 말이라야 한다.
      ActiveCoachingSignal.promised => "'$name' 할 시간이라고 했지.\n지금 할까?",
      ActiveCoachingSignal.paused => "'$name' 하다 멈췄네.\n조금만 더 해볼까?",
      // 하루를 닫는 말. "오늘 결국 못 했네"는 판결문이라, 못 한 것을 짚지 않고
      // 남은 시간에 할 수 있는 크기만 내민다.
      ActiveCoachingSignal.nightWrap => "'$name'\n오늘 10분만 손대볼까?",
      _ => "'$name' 아직이네.\n지금 조금이라도 해볼까?",
    };
  }

  /// 부를 일이 정해지지 않은 자리. 고르는 것은 사용자다.
  static const String askTitle = '지금 조금이라도 할 수 있는 거,\n하나 정해볼까?';

  /// 밤에 부를 일이 정해지지 않았을 때.
  static const String nightAskTitle = '오늘 10분만 손대볼 거,\n하나 정해볼까?';

  /// 카드 한 줄에 들어가는 이름 길이.
  static const int _nameLimit = 14;

  static String _shorten(String name) {
    final trimmed = name.trim();
    if (trimmed.length <= _nameLimit) return trimmed;
    return '${trimmed.substring(0, _nameLimit)}…';
  }

  static Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(plannedKey);
    if (!_isAndroid) {
      await NyangBannerNudge.sync();
      return;
    }
    try {
      await _channel.invokeMethod('clearActiveCoaching');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  static List _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }
}
