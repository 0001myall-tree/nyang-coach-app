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

  /// 지금 상태로 다음 개입을 다시 잡는다.
  static Future<void> sync() async {
    if (!GapCoachingService.isSupported) return;

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

    final plan = ActiveCoachingPlanner.next(
      tasks: tasks,
      now: now,
      day: day,
      budget: ActiveCoachingStore.readBudget(prefs, now),
      coreTasks: _decode(prefs.getString('nyang_core_tasks')),
      onDays: await GapCoachingService.days(),
      busyAt: (at) => BusyHoursService.busyNow(prefs, at) != null,
      busyEndAfter: (at) => BusyHoursService.busyEndAt(prefs, at),
    );
    if (plan == null) {
      await _clear();
      return;
    }

    await prefs.setString(
      plannedKey,
      jsonEncode({
        'date': ActiveCoachingStore.dateKey(now),
        'at': plan.at.millisecondsSinceEpoch,
        'title': titleFor(plan),
        if (plan.taskId != null) 'taskId': plan.taskId,
      }),
    );
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
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final at = DateTime.fromMillisecondsSinceEpoch(
        (decoded['at'] as num?)?.toInt() ?? now.millisecondsSinceEpoch,
      );
      // 어제 나간 것이면 어제 예산에서 뺄 일이다. 오늘 몫을 대신 깎으면 안 된다.
      if (ActiveCoachingStore.dateKey(at) != ActiveCoachingStore.dateKey(now)) {
        return;
      }
      final taskId = decoded['taskId']?.toString();
      final budget = ActiveCoachingStore.readBudget(prefs, now);
      await ActiveCoachingStore.writeBudget(
        prefs,
        budget
            .spoke(
              at,
              taskId: taskId == null || taskId.isEmpty ? null : taskId,
              // 사용자가 정한 시각을 확인한 것은 총량에서 뺀다. 그 구분은
              // 계획에 담겨 있지 않으므로, 여기서는 전부 총량에 넣는다 —
              // 덜 부르는 쪽으로 틀리는 편이 낫다.
            )
            .noReply(),
      );
      if (taskId != null && taskId.isNotEmpty) {
        await ActiveCoachingPromise.noteNudged(taskId: taskId, at: at);
      }
    } catch (_) {
      //
    }
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
    if (name.isEmpty) return askTitle;
    return switch (plan.signal) {
      // 사용자가 정한 시각이다. 재촉이 아니라 약속을 확인하는 말이라야 한다.
      ActiveCoachingSignal.promised => "'$name' 할 시간이라고 했지.\n지금 할까?",
      ActiveCoachingSignal.paused => "'$name' 하다 멈췄네.\n조금만 더 붙을까?",
      _ => "'$name' 아직이네.\n지금 조금이라도 해볼까?",
    };
  }

  /// 부를 일이 정해지지 않은 자리. 고르는 것은 사용자다.
  static const String askTitle = '지금 조금이라도 할 수 있는 거,\n하나 정해볼까?';

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
