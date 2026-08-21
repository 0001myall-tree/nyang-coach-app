import 'package:shared_preferences/shared_preferences.dart';

/// 코치가 마지막으로 보낸 답변을 태그가 붙은 그대로 적어둔다.
///
/// 화면에 나오는 말은 태그를 떼어낸 뒤라, 코치가 태그를 붙였는지 아닌지를 볼
/// 길이 없었다. 그래서 조작이 안 될 때마다 원인이 둘로 갈렸다 — 코치가 안
/// 붙인 것과, 붙였는데 앱이 못 알아본 것. 이 둘은 고칠 데가 완전히 다른데
/// 구분할 수 없어서 양쪽을 번갈아 고치게 됐다.
///
/// 한 번만 열어보면 갈린다. `[MOVE: 집필]`이 보이면 앱이 버린 것이고,
/// 안 보이면 코치가 안 뱉은 것이다.
///
/// 'nyang_'으로 시작하지 않는 키를 쓴다. 그 접두어는 클라우드 복원이 덮어쓰는데,
/// 이건 이 기기에서 방금 일어난 일이라 기기마다 달라야 한다.
class LastReplyLog {
  static const String _textKey = 'last_coach_reply_raw';
  static const String _atKey = 'last_coach_reply_at';

  /// 너무 긴 답변은 앞부분만 남긴다. 태그는 대개 끝에 붙지만, 통째로 담아두면
  /// 저장소가 답변 하나에 오래 묶인다.
  static const int _maxLength = 2000;

  static Future<void> record(String raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = raw.length > _maxLength
          ? '${raw.substring(0, _maxLength)}…(잘림)'
          : raw;
      await prefs.setString(_textKey, text);
      await prefs.setString(_atKey, DateTime.now().toIso8601String());
    } catch (_) {
      // 기록을 못 남겼다고 대화가 막히면 안 된다.
    }
  }

  /// 설정에서 보여줄 내용. 아직 없으면 null.
  static Future<String?> read() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final text = prefs.getString(_textKey);
    if (text == null || text.isEmpty) return null;
    final at = DateTime.tryParse(prefs.getString(_atKey) ?? '');
    final when = at == null
        ? ''
        : '${at.month}월 ${at.day}일 '
              '${at.hour.toString().padLeft(2, '0')}:'
              '${at.minute.toString().padLeft(2, '0')}\n\n';
    return '$when$text';
  }
}
