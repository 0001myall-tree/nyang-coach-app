import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 이 사람의 하루가 무엇으로 차 있는지. 대화에서 주워 담는다.
///
/// 같은 "저녁 8시"라도 6시에 퇴근한 사람에게는 하루의 시작이고, 오후 알바를
/// 마친 사람에게는 이미 지친 시간이다. 그걸 모르면 코치는 시계만 보고
/// 일반론을 말한다.
///
/// 물어보지 않는다. 생활을 캐묻는 것은 코칭이 아니고, 어차피 사람은 대화하다
/// 말한다 — "퇴근하고 할게", "알바 끝나고". 그 말을 흘려보내지 않고 세어둔다.
///
/// 한 번 들은 말로 정하지 않는다. 남의 퇴근 이야기를 옮겼을 수도 있어서,
/// 같은 쪽이 몇 번 쌓이고 다른 쪽보다 뚜렷할 때만 그 사람의 생활로 본다.
class LifeContextService {
  const LifeContextService._();

  /// 이 기기에서만 뜻이 있는 값이라 'nyang_' 접두어를 쓰지 않는다.
  /// 그 접두어는 클라우드 복원이 통째로 덮어쓴다.
  static const String _key = 'life_context_hits';
  static const String _deniedKey = 'life_context_denied';

  /// 이만큼 쌓여야 말을 꺼낸다.
  static const int minHits = 2;

  /// 아니라고 한 생활은 이만큼 세지 않는다.
  ///
  /// 지우기만 하면 다음에 "전 회사에서는" 한 마디에 다시 쌓인다. 그만뒀다고
  /// 말한 사람에게 그 생활을 되씌우는 일이 없도록 한동안 막아둔다.
  static const Duration denyLife = Duration(days: 90);

  /// 2등보다 이만큼은 앞서야 한다. 학생이면서 알바를 하는 사람도 있어서,
  /// 근소한 차이로 하나를 고르면 틀린 쪽으로 굳는다.
  static const int leadOverRunnerUp = 2;

  /// 오래된 셈은 지운다. 졸업하고 취직하면 그 전 이야기는 남의 이야기가 된다.
  static const Duration hitLife = Duration(days: 60);

  /// 무엇으로 하루가 차 있는지. 값마다 코치에게 건넬 한 줄을 들고 있다.
  static const Map<String, String> kinds = {
    'job': '정해진 시간에 출퇴근하는 일이 있음',
    'parttime': '시간제로 일하는 날이 있음 (근무 시간이 날마다 다를 수 있음)',
    'student': '수업이나 학업 일정이 있음',
    'freelance': '일감 단위로 일함 (근무 시간을 스스로 정함)',
    'business': '가게나 사업을 함 (영업 시간에 매여 있음)',
  };

  /// 그 말이 나오면 그 생활로 세는 말들.
  ///
  /// 여러 생활에 걸치는 말은 넣지 않는다. '마감'은 직장인도 프리랜서도
  /// 학생도 쓰고, '회의'는 학생도 한다. 그런 말로 세면 숫자만 늘고 뜻은
  /// 흐려진다. 한쪽에서만 쓰는 말만 남긴다.
  static const Map<String, List<String>> _signals = {
    'job': ['퇴근', '출근', '야근', '회사', '사무실', '연차', '월차', '재택근무', '반차', '주말 근무'],
    'parttime': ['알바', '아르바이트', '시급', '오픈조', '마감조', '주휴'],
    'student': ['수업', '강의', '과제', '시험 기간', '시험기간', '등교', '종강', '개강', '학교 가', '중간고사', '기말'],
    'freelance': ['외주', '클라이언트', '납품', '프리랜서', '작업물 넘기'],
    'business': ['가게', '손님', '영업 시간', '영업시간', '매출', '장사'],
  };

  /// 아니라고 하는 말들. 이 말이 같이 있으면 그 생활을 지운다.
  ///
  /// 사람은 바뀐다. 퇴사하고 학교로 돌아가기도 하고 알바를 그만두기도 하는데,
  /// 세어둔 것만 보면 그 사람은 영영 직장인이다.
  static const List<String> _denials = [
    '안 다녀',
    '안다녀',
    '안 해',
    '안해',
    '그만뒀',
    '그만둬',
    '관뒀',
    '때려치',
    '안 나가',
    '그만둔',
    '접었',
  ];

  /// 그 말 하나로 무엇이 끝났는지까지 알 수 있는 말들.
  ///
  /// '퇴사했어'는 아니라는 말과 무엇인지를 한 낱말에 담고 있다. 이런 말은
  /// 앞의 목록과 짝지을 상대가 필요 없다.
  static const Map<String, String> _endSignals = {
    '퇴사': 'job',
    '졸업했': 'student',
    '자퇴': 'student',
    '휴학': 'student',
    '폐업': 'business',
    '가게 접': 'business',
  };

  /// 이 말에서 "그건 아니다"라고 밝힌 생활들.
  static Set<String> negatedKindsIn(String text) {
    final out = <String>{};
    for (final entry in _endSignals.entries) {
      if (text.contains(entry.key)) out.add(entry.value);
    }
    if (_denials.any(text.contains)) out.addAll(kindsIn(text));
    return out;
  }

  /// 사용자가 한 말에서 생활의 자취를 줍는다. 대개는 아무 일도 없다.
  ///
  /// 코치가 한 말은 넣지 않는다. 코치가 "퇴근하고 하자"고 말한 것을 세면
  /// 자기가 한 말을 근거로 삼는 셈이 된다.
  static Future<void> noteFromUserText(String text) async {
    final denied = negatedKindsIn(text);
    final found = denied.isEmpty ? kindsIn(text) : const <String>{};
    if (denied.isEmpty && found.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();

    if (denied.isNotEmpty) {
      // 아니라고 했으니 세어둔 것을 지우고, 한동안 다시 세지 않는다.
      final marks = _denied(prefs);
      for (final kind in denied) {
        marks[kind] = now;
      }
      await prefs.setString(
        _deniedKey,
        jsonEncode(marks.map((k, v) => MapEntry(k, v.toIso8601String()))),
      );
      final kept = [
        for (final hit in _hits(prefs))
          if (!denied.contains(hit.kind)) hit,
      ];
      await _save(prefs, kept);
      return;
    }

    final hits = _hits(prefs);
    for (final kind in found) {
      hits.add(LifeHit(kind: kind, at: now));
    }
    await _save(prefs, hits);
  }

  static Map<String, DateTime> _denied(SharedPreferences prefs) {
    final raw = prefs.getString(_deniedKey);
    if (raw == null || raw.isEmpty) return {};
    final from = DateTime.now().subtract(denyLife);
    final out = <String, DateTime>{};
    try {
      for (final entry in (jsonDecode(raw) as Map).entries) {
        final at = DateTime.tryParse(entry.value?.toString() ?? '');
        if (at == null || at.isBefore(from)) continue;
        out[entry.key.toString()] = at;
      }
    } catch (_) {
      return {};
    }
    return out;
  }

  /// 이 말에서 읽히는 생활들. 없으면 빈 집합.
  static Set<String> kindsIn(String text) {
    final found = <String>{};
    for (final entry in _signals.entries) {
      for (final word in entry.value) {
        if (text.contains(word)) {
          found.add(entry.key);
          break;
        }
      }
    }
    return found;
  }

  /// 지금까지 센 것으로 본 생활. 아직 모르면 null.
  static Future<String?> resolve() async {
    final prefs = await SharedPreferences.getInstance();
    return resolveFrom(_hits(prefs));
  }

  /// 프롬프트에 실을 한 줄. 아직 모르면 모른다고 적는다.
  ///
  /// 비워두지 않는 이유가 있다. 아무 말도 없으면 코치는 이 사람이 종일
  /// 한가한 줄 알고 말한다. 모른다는 것을 알려주면 "낮에 따로 일이 있는지는
  /// 모르겠지만" 하고 열어두고 말할 수 있다.
  static Future<String> promptLine() async {
    final kind = await resolve();
    if (kind == null) {
      return '- 생활 형태: 아직 모름. 낮에 일이나 수업이 있는지 알 수 없으니, 단정하지 말고 열어두고 말할 것.';
    }
    return '- 생활 형태: ${kinds[kind]}';
  }

  static String? resolveFrom(List<LifeHit> hits) {
    final counts = <String, int>{};
    for (final hit in hits) {
      counts[hit.kind] = (counts[hit.kind] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;

    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first;
    if (top.value < minHits) return null;
    final runnerUp = sorted.length > 1 ? sorted[1].value : 0;
    if (top.value - runnerUp < leadOverRunnerUp) return null;
    return top.key;
  }

  static List<LifeHit> _hits(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final denied = _denied(prefs);
    final from = DateTime.now().subtract(hitLife);
    final out = <LifeHit>[];
    try {
      for (final item in (jsonDecode(raw) as List).whereType<Map>()) {
        final kind = item['kind']?.toString() ?? '';
        final at = DateTime.tryParse(item['at']?.toString() ?? '');
        if (!kinds.containsKey(kind) || at == null || at.isBefore(from)) {
          continue;
        }
        if (denied.containsKey(kind)) continue;
        out.add(LifeHit(kind: kind, at: at));
      }
    } catch (_) {
      return [];
    }
    return out;
  }

  static Future<void> _save(SharedPreferences prefs, List<LifeHit> hits) async {
    // 오래된 것부터 밀어낸다. 이 값으로 하는 일이 한 줄 쓰는 것뿐이라
    // 길게 들고 있을 이유가 없다.
    if (hits.length > 60) hits.removeRange(0, hits.length - 60);
    await prefs.setString(
      _key,
      jsonEncode([
        for (final hit in hits)
          {'kind': hit.kind, 'at': hit.at.toIso8601String()},
      ]),
    );
  }
}

/// 생활의 자취 하나. 언제 들었는지까지 들고 있어야 오래된 것을 지운다.
class LifeHit {
  const LifeHit({required this.kind, required this.at});

  final String kind;
  final DateTime at;
}
