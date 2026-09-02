/// 코치가 [OPEN: 화면]으로 가리킨 화면을 앱이 아는 이름으로 옮긴다.
///
/// 예전에는 사용자의 말에서 키워드를 주워 화면을 열었다. '어디'와 '할일'이
/// 같이 들어 있으면 열고, 문장이 30자를 넘으면 열지 않는 식이었다. 뜻을 못
/// 보니 "할 일이 너무 많아서 어디서부터 손대야 할지 모르겠어"에도 탭이
/// 열렸고, 그걸 막으려고 길이로 잘랐더니 길게 물어본 사람은 안내를 못 받았다.
///
/// 이제는 코치가 정한다. 남는 일은 코치가 적어 보낸 이름을 앱의 키로 바꾸는
/// 것뿐이라, 여기 있는 것은 사전 하나다.
///
/// 관대하게 받는다. 코치가 '오늘 탭', '캘린더 화면', '목표탭'처럼 적어 보낼
/// 것을 알고 있고, 그때 화면이 안 열리면 코치는 열어주겠다고 말해놓고 아무
/// 일도 일으키지 않은 셈이 된다.
abstract final class ScreenOpenTarget {
  /// 화면 이름 → 앱이 쓰는 키. 키는 기존 화면 이동 경로가 받던 것 그대로다.
  static const Map<String, String> _keys = {
    '오늘': 'today',
    '할일': 'today',
    '캘린더': 'schedule',
    '일정': 'schedule',
    '달력': 'schedule',
    '목표': 'goals',
    '비전': 'vision',
    '장기비전': 'vision',
    '마일스톤': 'vision',
    '루틴': 'habit',
    '습관': 'habit',
    '기록': 'records',
    '통계': 'records',
    '설정': 'settings',
  };

  /// 이름에 붙어 오는 군더더기. 떼고 나서 사전을 본다.
  static final RegExp _trailing = RegExp(r'(탭|텝|화면|창|페이지)$');

  /// 답변에서 첫 [OPEN: ...] 하나를 읽는다. 없거나 모르는 이름이면 null.
  ///
  /// 하나만 읽는 이유는 화면이 하나뿐이기 때문이다. 둘을 적어 보내도 열리는
  /// 것은 마지막 하나이고, 그러면 코치가 말한 첫 번째와 어긋난다.
  static String? read(String reply) {
    final match = RegExp(r'\[OPEN:\s*([^\]]+)\]').firstMatch(reply);
    if (match == null) return null;
    return resolve(match.group(1) ?? '');
  }

  /// 이름 하나를 키로 바꾼다. 모르는 이름이면 null — 화면을 열지 않는다.
  static String? resolve(String rawName) {
    var name = rawName.trim().replaceAll(' ', '');
    if (name.isEmpty) return null;
    // 사전에 그대로 있으면 그걸로 끝낸다. '할일'처럼 뒷말을 떼면 안 되는
    // 이름이 있어서, 떼는 것은 사전에 없을 때만 한다.
    final direct = _keys[name];
    if (direct != null) return direct;
    name = name.replaceFirst(_trailing, '');
    return _keys[name];
  }

  /// 답변 본문에서 태그를 지운다. 남으면 사용자에게 대괄호가 그대로 보인다.
  static String strip(String reply) => reply
      .replaceAll(RegExp(r'\[OPEN:\s*[^\]]*\]'), '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
