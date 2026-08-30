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
/// 마스터 플랜 전용. 등록창(할 일 탭)에서 두 번 이어지는 다이얼로그로 묻고,
/// 그 문답을 [recordChatTurns]로 남기면 채팅 화면이 다음에 열릴 때 마치
/// 그 자리에서 대화한 것처럼 재생한다.
class OverplanNudgeService {
  const OverplanNudgeService._();

  /// 오늘 이미 짚었는지. 하루 한 번만 나가야 하므로, 조건을 넘긴 순간
  /// 이 값부터 오늘 날짜로 채운다.
  static const String _lastFiredDateKey = 'overplan_nudge_last_date';

  /// 채팅 화면이 다음에 열릴 때 읽어가는 자리. [isUser]/[text] 순서 그대로인
  /// 문답 목록을 담는다.
  static const String pendingChatKey = 'overplan_nudge_pending_chat';

  /// 최근 실제 완료 최대치보다 이 개수 이상 많이 잡았을 때만 짚는다.
  static const int _overBy = 2;

  /// 오늘 계획이 조건을 넘겼는지 본다. 넘겼으면(오늘 처음이면) 오늘 날짜를
  /// 적어두고 그때의 최근 최대 완료량을 돌려준다. 마스터 플랜이 아니거나,
  /// 오늘 이미 짚었거나, 조건에 못 미치면 null.
  static Future<int?> shouldFire({
    required List<Map<String, dynamic>> todayTasks,
    required String? historyRaw,
  }) async {
    try {
      final userData = await UserDataService.load();
      if (!userData.isPlanActive || userData.planType != 'master') {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final today = _todayKey();
      if (prefs.getString(_lastFiredDateKey) == today) return null;

      final plannedCount = todayTasks.length;
      final recentMax = _recentMaxCompleted(historyRaw);
      if (plannedCount < recentMax + _overBy) return null;

      await prefs.setString(_lastFiredDateKey, today);
      return recentMax;
    } catch (e) {
      debugPrint('overplan nudge check failed: $e');
      return null;
    }
  }

  /// 처음 건네는 말. 최근 최대 완료량([recentMax])을 넣어 "그냥 많다"가
  /// 아니라 "평소보다 이만큼 많다"를 실감하게 한다.
  static String primaryMessage(String coachId, int recentMax) {
    if (coachId == 'sec_female') {
      return '대표님, 최근 잘 해내신 날이 하루 $recentMax개 정도였는데 오늘 계획은 그보다 '
          '훨씬 많으시네요. 할 일을 많이 잡는 게 부지런해 보여도, '
          '실은 시작을 미루는 회피일 때가 있어요. 새로 더하시는 것보다 이미 적어두신 '
          '것 하나를 실행 가능하게 다듬으시는 쪽이 해내실 가능성이 더 높습니다.';
    }
    return '최근 잘 해낸 날이 하루 $recentMax개 정도였는데, 오늘 계획은 '
        '그보다 훨씬 많구나. 할 일을 많이 잡는 건 부지런해 보여도, 실은 시작을 '
        '미루는 회피일 때가 있다냥. 새로 더하는 것보다 이미 적어둔 것 하나를 '
        '실행 가능하게 구체화하는 쪽이 해낼 가능성이 더 높다.';
  }

  /// 첫 물음에 "그렇게 할게"를 골랐을 때 한 번 더 건네는 말.
  static String followupMessage(String coachId) {
    if (coachId == 'sec_female') {
      return '그럼 기존 계획을 구체화해볼까요, 대표님?';
    }
    return '그럼 기존 계획을 구체화해볼까냥?';
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

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }
}
