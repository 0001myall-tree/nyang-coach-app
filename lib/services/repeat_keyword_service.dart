/// 핵심으로도 습관으로도 지정하지 않았지만 요즘 자주 하는 일을 찾는다.
///
/// 최근 기록의 할 일 이름에서 반복되는 말을 세어, 오늘 올라온 할 일이 거기
/// 걸리면 코치가 세 번째 순위로 챙긴다. 핵심이 1순위, 습관이 2순위다.
///
/// AI를 부르지 않는다. '소설 집필' 같은 상위 분류를 지어내지 않고, 사용자가
/// 실제로 입력한 말만 센다. 지어낸 분류는 틀렸을 때 고칠 방법이 없다.
library;

/// 반복해서 등장한 말 하나.
class RepeatKeyword {
  final String keyword;

  /// 이 말이 등장한 서로 다른 날의 수. 같은 날 몇 번이든 1로 센다.
  final int days;

  const RepeatKeyword(this.keyword, this.days);

  @override
  String toString() => '$keyword($days일)';
}

class RepeatKeywordService {
  /// 며칠치를 보는지. 주 2회짜리도 [minDays]에 닿도록 두 주를 본다.
  static const windowDays = 14;

  /// 후보가 되기 위한 최소 등장 일수.
  ///
  /// 서로 다른 날로만 세기 때문에 하루에 몰아 적은 날은 1일이다. 2일로 낮추면
  /// 우연히 이틀 겹친 것까지 후보가 된다.
  static const minDays = 3;

  /// 어느 일에나 붙어서 무엇을 하는지 알려주지 못하는 말.
  static const stopwords = {
    '하기', '보기', '정리', '확인', '시작', '완료', '준비',
    '오늘', '내일', '어제', '아침', '점심', '저녁', '시간',
    '그냥', '조금', '다시', '계속', '생각', '하루',
  };

  /// 토큰 뒤에 붙는 조사.
  ///
  /// '이', '가', '의'는 뺐다. 명사의 끝 글자인 경우가 많아서('고양이', '회의')
  /// 떼면 말이 망가진다. 덜 떼는 쪽이 잘못 떼는 쪽보다 낫다.
  static const _particles = [
    '에서', '으로', '이랑', '까지', '부터', '에게', '한테',
    '을', '를', '은', '는', '도', '만', '에', '로', '와', '과', '랑',
  ];

  /// 최근 기록에서 반복되는 말을 등장 일수 내림차순으로.
  ///
  /// [records]는 하루 기록들이다. 각 항목에 `date`와 `tasks`가 있어야 한다.
  static List<RepeatKeyword> analyze(List<dynamic> records) {
    final recent = records.length > windowDays
        ? records.sublist(records.length - windowDays)
        : records;

    final dates = <String, Set<String>>{};
    for (final record in recent) {
      if (record is! Map) continue;
      final date = record['date']?.toString() ?? '';
      if (date.isEmpty) continue;
      final tasks = record['tasks'];
      if (tasks is! List) continue;

      for (final task in tasks) {
        if (task is! Map) continue;
        // 습관에서 자동으로 생기는 할 일은 뺀다. 매일 들어오니까 안 빼면
        // 습관 이름이 무조건 1등이 되는데, 습관은 이미 2순위가 챙긴다.
        if (task['category'] == 'habit') continue;
        for (final keyword in keywordsOf(task['text']?.toString() ?? '')) {
          dates.putIfAbsent(keyword, () => <String>{}).add(date);
        }
      }
    }

    final merged = _mergeBySuffix(dates);
    final found =
        merged.entries
            .where((entry) => entry.value.length >= minDays)
            .map((entry) => RepeatKeyword(entry.key, entry.value.length))
            .toList()
          ..sort((a, b) => b.days.compareTo(a.days));
    return found;
  }

  /// 할 일 이름 하나에서 셀 만한 말들을 뽑는다.
  static Set<String> keywordsOf(String text) {
    final found = <String>{};
    for (final raw in text.split(RegExp(r'[^가-힣a-zA-Z0-9]+'))) {
      final token = _normalize(raw);
      if (token != null) found.add(token);
    }
    return found;
  }

  /// 오늘의 할 일 이름이 후보 중 하나에 걸리는지. 걸리면 그 키워드.
  ///
  /// [candidates]는 [analyze]가 돌려준 순서 그대로여야 한다. 앞쪽이 더 자주
  /// 반복된 말이라 먼저 걸리는 쪽이 더 확실한 근거가 된다.
  static String? matchingKeyword(
    String taskText,
    List<RepeatKeyword> candidates,
  ) {
    final keywords = keywordsOf(taskText);
    for (final candidate in candidates) {
      if (keywords.contains(candidate.keyword)) return candidate.keyword;
      // 후보가 접미사로 합쳐진 말일 수 있다. 후보가 '쓰기'인데 오늘 이름은
      // '글쓰기'인 경우가 여기 걸린다.
      if (keywords.any((k) => k.endsWith(candidate.keyword))) {
        return candidate.keyword;
      }
    }
    return null;
  }

  /// 한 토큰을 셀 수 있는 말로 다듬는다. 셀 게 없으면 null.
  static String? _normalize(String raw) {
    var token = raw.trim();
    if (token.isEmpty) return null;
    // '1화', '2회차'처럼 숫자로 시작하는 토큰은 회차 표시라 셀 것이 없다.
    if (RegExp(r'^[0-9]').hasMatch(token)) return null;
    token = token.replaceAll(RegExp(r'[0-9]'), '');

    for (final particle in _particles) {
      // 떼고 나서도 두 글자는 남아야 뗀다. '회의'에서 '의'를 떼면 '회'만 남는다.
      if (token.length > particle.length + 1 && token.endsWith(particle)) {
        token = token.substring(0, token.length - particle.length);
        break;
      }
    }

    // '하기'는 어느 일에나 붙는다. 떼고 남는 말이 진짜 이름이다.
    // ('운동하기'와 '운동'이 같은 말이 된다.)
    if (token.length >= 4 && token.endsWith('하기')) {
      token = token.substring(0, token.length - 2);
    }

    if (token.length < 2) return null;
    if (stopwords.contains(token)) return null;
    return token;
  }

  /// 끝이 같은 말끼리 합친다. '글쓰기'와 '쓰기'는 같은 말로 본다.
  ///
  /// 한국어는 뒤쪽이 의미의 중심이라 이 방향만 합친다. 앞이 같다고 합치면
  /// '공부'와 '공지'가 엮인다.
  static Map<String, Set<String>> _mergeBySuffix(Map<String, Set<String>> src) {
    final keys = src.keys.toList()
      ..sort((a, b) => a.length.compareTo(b.length));
    final merged = <String, Set<String>>{};
    for (final key in keys) {
      var representative = key;
      for (final shorter in keys) {
        if (shorter.length >= key.length) break;
        if (key.endsWith(shorter)) {
          representative = shorter;
          break;
        }
      }
      merged.putIfAbsent(representative, () => <String>{}).addAll(src[key]!);
    }
    return merged;
  }
}
