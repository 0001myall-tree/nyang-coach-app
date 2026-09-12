import 'dart:convert';

import 'package:intl/intl.dart';

/// 대화를 담아두는 자리의 규칙.
///
/// 대화는 **덧붙이기만 하는 목록**이다. 한 번 한 말은 고쳐지지도 지워지지도
/// 않는다. 그래서 두 벌이 마주쳤을 때 덮어쓰기가 아니라 합치기가 맞다 — 덮으면
/// 이긴 쪽에 없는 말이 사라지고, 그건 되돌릴 수 없다.
///
/// 할 일이나 루틴은 이렇게 못 한다. 그쪽은 고치기와 지우기가 있어서 합치면
/// 지운 것이 되살아난다.
class ChatStore {
  /// 코치별 대화가 들어 있는 키.
  static String historyKey(String coachId) => 'nyang_chat_history_$coachId';

  /// 옛 보관함 키 접두사. 지금은 합쳐 들이기 위해서만 본다.
  static const String archivePrefix = 'nyang_chat_archive_';

  /// 대화가 담긴 키인지. 합치기로 다뤄야 하는 키들이다.
  static bool isChatKey(String key) =>
      key.startsWith('nyang_chat_history_') || key.startsWith(archivePrefix);

  /// 대화를 몇 **개의 날짜**까지 남길지.
  ///
  /// "오늘에서 7일 전"이 아니라 "대화한 날 7개"다. 날수로 자르면 열흘 만에 앱을
  /// 여는 사람은 대화가 통째로 없어진다 — 오랜만에 온 사람 앞에 코치가 아무것도
  /// 기억 못 하는 채로 앉는 셈이다. 날짜 개수로 세면 한 달에 세 번 쓰는 사람도
  /// 늘 지난 일곱 번의 대화를 들고 있다.
  static const int keptDates = 7;

  /// 아주 많이 쌓였을 때의 방어적 상한.
  ///
  /// 날짜 7개로 이미 묶여 있지만, 하루에 수천 마디를 주고받는 판이 생기면 값
  /// 하나가 커진다. 클라우드는 값 하나가 1MB를 넘으면 아예 못 올리고, 그때는
  /// 그날부터 동기화가 조용히 실패한다.
  static const int maxEntries = 2000;

  /// 저장된 대화 문자열을 목록으로. 깨져 있으면 빈 목록.
  static List<dynamic> decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : [];
    } catch (_) {
      return [];
    }
  }

  /// 메시지가 어느 날 것인지. 시각을 못 읽으면 null.
  static String? dateOf(dynamic message) {
    final time = DateTime.tryParse(
      (message is Map ? message['time'] : null)?.toString() ?? '',
    );
    return time == null ? null : DateFormat('yyyy-MM-dd').format(time);
  }

  /// 시간순으로 세운다. 시각을 못 읽는 항목은 뒤로 보낸다.
  static List<dynamic> sorted(List<dynamic> messages) {
    final result = List<dynamic>.from(messages);
    result.sort((a, b) {
      final at = DateTime.tryParse(
        (a is Map ? a['time'] : null)?.toString() ?? '',
      );
      final bt = DateTime.tryParse(
        (b is Map ? b['time'] : null)?.toString() ?? '',
      );
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return result;
  }

  /// 대화 두 뭉치를 합친다. 같은 말은 [preferred] 쪽 것만 남는다.
  ///
  /// 같은 말인지는 시각·말한 사람·내용으로 본다. 메시지에 고유 번호가 없고,
  /// 같은 사람이 같은 초에 같은 말을 두 번 하는 일은 없다.
  ///
  /// 어느 쪽을 남기는지가 중요하다. 확인 카드를 누르면 앱은 그 말은 남기고
  /// 버튼만 걷어내는데, 걷어낸 것과 걷어내기 전 것은 글자가 같아서 같은 말로
  /// 읽힌다. 옛 쪽이 이기면 **눌렀던 버튼이 되살아나** 또 누를 수 있게 된다.
  /// 그래서 부르는 쪽은 늘 이 기기의 지금 값을 [preferred]로 준다.
  static List<dynamic> merge(List<dynamic> preferred, List<dynamic> other) {
    final merged = <dynamic>[];
    final seen = <String>{};
    for (final message in [...preferred, ...other]) {
      if (message is! Map) continue;
      final time = message['time']?.toString() ?? '';
      final text = (message['text'] ?? message['content'] ?? '').toString();
      if (!seen.add('$time|${message['isUser'] == true}|$text')) continue;
      merged.add(message);
    }
    return sorted(merged);
  }

  /// 대화한 날 [dates]개만 남기고 그보다 오래된 날은 버린다.
  ///
  /// 시각을 못 읽는 항목은 어느 날 것인지 알 수 없어 그대로 남긴다. 버리는 쪽이
  /// 되돌릴 수 없으니, 모를 때는 남기는 쪽으로 기운다.
  static List<dynamic> keepRecentDates(
    List<dynamic> messages, {
    int dates = keptDates,
    int limit = maxEntries,
  }) {
    final allDates = <String>{};
    for (final message in messages) {
      final date = dateOf(message);
      if (date != null) allDates.add(date);
    }
    Iterable<dynamic> kept = messages;
    if (allDates.length > dates) {
      final sortedDates = allDates.toList()..sort();
      final keptDates = sortedDates.sublist(sortedDates.length - dates).toSet();
      kept = messages.where((message) {
        final date = dateOf(message);
        return date == null || keptDates.contains(date);
      });
    }
    var result = sorted(kept.toList());
    if (result.length > limit) {
      result = result.sublist(result.length - limit);
    }
    return result;
  }

  /// 두 벌을 합치고 오래된 날을 걷어낸 결과를 저장할 문자열로.
  static String mergedValue(List<dynamic> preferred, List<dynamic> other) =>
      jsonEncode(keepRecentDates(merge(preferred, other)));
}
