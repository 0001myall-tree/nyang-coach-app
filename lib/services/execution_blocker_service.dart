import 'package:shared_preferences/shared_preferences.dart';

/// 시작을 막는 것이 무엇인지. 막힌 그 순간에 본인에게 묻는다.
///
/// 앱은 이미 막힘을 일곱 갈래로 나눠 두고 있다. 다만 그 칸을 채우는 일을
/// 배치가 대화를 요약해 짐작으로 했다. 며칠에 한 번 돌고, 틀려도 아무도
/// 모른다.
///
/// 성격 검사로 받는 방법도 있는데, 그건 평소의 자기 이미지를 답하게 된다.
/// 지금 막혀 있는 사람에게 지금 무엇이 걸리는지 물으면 그 자리에서 정확한
/// 답이 나오고, 답하는 동안 본인도 그 일을 한 번 들여다보게 된다.
class ExecutionBlockerService {
  const ExecutionBlockerService._();

  /// 이 기기에서만 뜻이 있는 값이라 'nyang_' 접두어를 쓰지 않는다.
  static const String _key = 'execution_blocker';
  static const String _freeKey = 'execution_blocker_free';
  static const String _atKey = 'execution_blocker_at';

  /// 한 번 물으면 이만큼은 다시 묻지 않는다. 막힐 때마다 물으면 그것부터가
  /// 막는 일이 된다.
  static const Duration askInterval = Duration(days: 14);

  /// 답을 이만큼만 들고 있는다. 막히는 자리는 하는 일에 따라 바뀐다.
  static const Duration answerLife = Duration(days: 21);

  /// 고를 수 있는 답과, 코치에게 넘길 한 줄.
  ///
  /// 기억 저장소가 쓰는 갈래와 같은 것들이다. 이름만 사람 말로 바꿨다.
  static const Map<String, String> answers = {
    '뭐부터 할지 모르겠어': '무엇부터 손댈지 정하는 데서 막힘. 고를 것이 여럿일 때 못 움직임.',
    '첫 동작이 안 잡혀': '그 일의 첫 동작이 그려지지 않아 못 움직임. 무엇을 하는 것인지가 흐림.',
    '결과가 신경 쓰여': '잘 안 나올까 봐 시작을 못 함. 손대는 순간 결과를 마주해야 해서 미룸.',
    '기운이 없어': '몸이 안 따라줘서 못 움직임. 의지의 문제가 아님.',
    '계속 딴짓을 하게 돼': '다른 것에 붙들려 그 일로 넘어오지 못함. 일 자체가 아니라 넘어오는 자리가 문제.',
    '자리에 앉기가 싫어': '그 일을 하는 자리나 준비 과정이 걸림. 일 자체보다 그 앞이 싫음.',
  };

  /// 막는 것마다 먼저 꺼낼 개입.
  ///
  /// 개입을 순번대로만 돌리면, 뭐부터 할지 모르겠다는 사람에게 "5분만 해보자"가
  /// 나오고 기운 없는 사람에게 "둘 중 골라"가 나온다. 둘 다 틀린 짝이다.
  ///
  /// 지목일 뿐 고정이 아니다. 이번 대화에서 이미 꺼냈으면 순번으로 넘어가고,
  /// 사용자가 싫다고 하면 그다음 것으로 간다.
  static const Map<String, String> _preferred = {
    // 고를 것이 많아 못 정하는 사람에게는 코치가 정해주지 말고 둘로 좁혀준다.
    '뭐부터 할지 모르겠어': 'let_user_choose',
    // 첫 동작이 안 그려지면 그 일의 제일 작은 한 칸을 짚어준다.
    '첫 동작이 안 잡혀': 'narrow_scope',
    // 잘 나올까 봐 못 시작하는 것이라, 잘 안 해도 된다는 쪽으로 기준을 내린다.
    '결과가 신경 쓰여': 'allow_rough',
    // 몸이 안 따라주는 사람에게는 그 일의 조각도 무겁다. 그 아래 층부터.
    '기운이 없어': 'wake_body',
    // 넘어오는 자리가 문제니 시작에 신호를 만든다.
    '계속 딴짓을 하게 돼': 'start_signal',
    // 일이 아니라 그 앞이 싫은 것이라, 앉는 순간을 다르게 만든다.
    '자리에 앉기가 싫어': 'music_start',
  };

  /// 그 답에 짝지은 개입. 없으면 null. 테스트가 이 자리로 들어온다.
  static String? interventionFor(String label) => _preferred[label];

  /// 이번 턴에 먼저 꺼낼 개입. 답이 없거나 오래됐으면 null.
  static Future<String?> preferredInterventionId() async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.tryParse(prefs.getString(_atKey) ?? '');
    if (at == null || DateTime.now().difference(at) > answerLife) return null;
    // 직접 적은 답에는 짝지을 개입이 없다. 그건 코치가 읽고 판단한다.
    if ((prefs.getString(_freeKey) ?? '').isNotEmpty) return null;
    return _preferred[prefs.getString(_key)];
  }

  /// 목록에 없다고 할 때. 이건 답이 아니라 적겠다는 표시다.
  static const String otherLabel = '다른 게 걸려';

  static List<String> get labels => [...answers.keys, otherLabel];

  /// 아직 물어본 적이 없거나, 물어본 지 한참 지났는지.
  static Future<bool> mayAsk() async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.tryParse(prefs.getString(_atKey) ?? '');
    if (at == null) return true;
    return DateTime.now().difference(at) >= askInterval;
  }

  /// 물어봤다는 것만 남긴다. 답을 안 골라도 물어본 것은 물어본 것이다.
  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_atKey, DateTime.now().toIso8601String());
  }

  static Future<void> saveAnswer(String answer) async {
    if (!answers.containsKey(answer)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, answer);
    await prefs.remove(_freeKey);
    await markAsked();
  }

  /// 직접 적은 답. 목록에 없는 것이 그 사람에게는 제일 큰 것일 수 있다.
  ///
  /// 너무 길면 담지 않는다. 그건 막힘을 말한 것이 아니라 다른 이야기로
  /// 넘어간 것이고, 그걸 막힘이라고 들고 다니면 코치가 엉뚱한 것을 짚는다.
  static Future<void> saveFreeAnswer(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 120) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_freeKey, trimmed);
    await markAsked();
  }

  /// 코치에게 넘길 한 줄. 아직 모르거나 오래됐으면 빈 문자열.
  static Future<String> promptLine() async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.tryParse(prefs.getString(_atKey) ?? '');
    if (at == null || DateTime.now().difference(at) > answerLife) return '';

    final free = prefs.getString(_freeKey);
    if (free != null && free.isNotEmpty) {
      return '- 시작을 막는 것(사용자가 직접 한 말): "$free"';
    }
    final line = answers[prefs.getString(_key)];
    if (line == null) return '';
    return '- 시작을 막는 것(사용자가 직접 고른 것): $line';
  }

  /// 화면에 그대로 보여줄 답. 없으면 빈 목록.
  static Future<List<String>> pickedLabels() async {
    final prefs = await SharedPreferences.getInstance();
    final at = DateTime.tryParse(prefs.getString(_atKey) ?? '');
    if (at == null || DateTime.now().difference(at) > answerLife) {
      return const [];
    }
    final free = prefs.getString(_freeKey);
    if (free != null && free.isNotEmpty) return [free];
    final picked = prefs.getString(_key);
    if (picked == null || !answers.containsKey(picked)) return const [];
    return [picked];
  }
}
