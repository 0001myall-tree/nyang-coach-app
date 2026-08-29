import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 코치가 채팅 밖에서 먼저 건네는 한 마디.
///
/// 사용자가 할 일 창을 열어둔 채로 계획을 쓰고 있을 때, 코치의 말이 채팅에만
/// 도착하면 그 말은 없는 것과 같다. 그래서 같은 문장을 두 곳에 놓는다 —
/// 지금 보고 있는 화면 위에 말풍선으로 한 번, 채팅 기록에 한 줄로 한 번.
/// 만들어내는 것은 한 번뿐이라 값은 한 번만 치른다.
///
/// 말풍선을 못 보고 지나가도 잃어버리지 않는다. 채팅에 남아 있고, 못 본 코치의
/// 탭과 코치 선택 카드에 NEW가 붙어 있다가 그 채팅을 열면 사라진다.
class CoachSayService {
  const CoachSayService._();

  /// 지금 띄워야 할 말풍선. 화면 쪽이 이걸 보고 있다가 뜨면 그린다.
  static final ValueNotifier<CoachSay?> pending = ValueNotifier<CoachSay?>(
    null,
  );

  /// 아직 확인하지 않은 코치들.
  ///
  /// 채팅 기록이 코치마다 나뉘어 있으니 표시도 코치별이다. 냥이가 남긴 말은
  /// 냥이 자리에만 붙고, 냥이 채팅을 열 때만 지워진다.
  static final ValueNotifier<Set<String>> unread = ValueNotifier<Set<String>>(
    const {},
  );

  /// 이 기기에서만 뜻이 있는 값이라 'nyang_' 접두어를 쓰지 않는다.
  /// 그 접두어는 클라우드 복원이 통째로 덮어쓴다.
  static const String _unreadKey = 'coach_say_unread';

  /// 지금 화면에 떠 있는 채팅창. 떠 있으면 그쪽이 받아 적는다.
  ///
  /// 채팅 화면은 저장할 때 자기가 들고 있는 목록을 통째로 덮어쓴다. 그 화면이
  /// 살아 있는데 저장소에 직접 써넣으면, 다음 저장에서 그 줄이 조용히 사라진다.
  static final Map<String, void Function(String text)> _sinks = {};

  static void registerSink(String coachId, void Function(String text) sink) {
    _sinks[coachId] = sink;
  }

  static void unregisterSink(String coachId) {
    _sinks.remove(coachId);
  }

  /// 앱이 시작할 때 한 번. 저장해둔 안 읽음 표시를 되살린다.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    unread.value = (prefs.getStringList(_unreadKey) ?? const []).toSet();
  }

  /// 코치가 한 마디 건넨다.
  ///
  /// [kind]는 사용자가 말을 걸어서 나온 답이 아니라는 표시다. 나중에 코치가
  /// 먼저 건 말이 하루에 몇 번이었는지 셀 때 사용자 대화와 섞이면 안 된다.
  static Future<void> say({
    required String coachId,
    required String text,
    String kind = 'auto:say',
  }) async {
    // 태그가 섞여 나오면 떼어낸다.
    //
    // 이 말은 채팅 화면의 답변 처리를 거치지 않고 곧장 화면에 뜬다. 거기서
    // 태그를 떼어내던 층이 여기에는 없어서, 모델이 습관처럼 [TASK: …]를 붙이면
    // 그대로 말풍선에 보인다.
    final trimmed = text
        .replaceAll(RegExp(r'\[[A-Z_]+(?::[^\]]*)?\]'), '')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
    if (trimmed.isEmpty) return;

    final sink = _sinks[coachId];
    if (sink != null) {
      sink(trimmed);
    } else {
      await _appendToHistory(coachId, trimmed, kind);
    }

    await _setUnread(coachId, true);
    pending.value = CoachSay(coachId: coachId, text: trimmed);
  }

  /// 말풍선을 거뒀다. 채팅에는 그대로 남아 있다.
  static void dismissBubble() {
    pending.value = null;
  }

  /// 그 코치의 채팅을 열었다. NEW를 지운다.
  static Future<void> markRead(String coachId) async {
    if (!unread.value.contains(coachId)) return;
    await _setUnread(coachId, false);
    if (pending.value?.coachId == coachId) pending.value = null;
  }

  static Future<void> _setUnread(String coachId, bool value) async {
    final next = unread.value.toSet();
    if (value) {
      next.add(coachId);
    } else {
      next.remove(coachId);
    }
    if (next.length == unread.value.length &&
        next.containsAll(unread.value)) {
      return;
    }
    unread.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_unreadKey, next.toList());
  }

  /// 채팅 화면이 떠 있지 않을 때. 저장소에 바로 한 줄 얹는다.
  static Future<void> _appendToHistory(
    String coachId,
    String text,
    String kind,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final key = 'nyang_chat_history_$coachId';

    List<dynamic> history;
    try {
      history = jsonDecode(prefs.getString(key) ?? '[]') as List<dynamic>;
    } catch (_) {
      history = [];
    }
    history.add({
      'text': text,
      'isUser': false,
      'time': DateTime.now().toIso8601String(),
      'kind': kind,
    });
    // 채팅 화면이 저장하는 것과 같은 길이로 자른다.
    if (history.length > 100) {
      history = history.sublist(history.length - 100);
    }
    await prefs.setString(key, jsonEncode(history));
  }
}

/// 지금 띄울 말풍선 하나.
class CoachSay {
  const CoachSay({required this.coachId, required this.text});

  final String coachId;
  final String text;
}
