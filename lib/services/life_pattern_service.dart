/// 프렌즈 코치가 자기 담당 영역을 이 사람의 하루 어디에 넣을지 정하는 데
/// 쓰는 것들.
///
/// 이 앱은 이미 행동을 다 기록하고 있다. 요일별로 얼마나 해내는지, 몇 시에
/// 첫 발을 떼는지, 어떤 루틴이 어느 요일에 무너지는지. 그래서 그건 묻지
/// 않는다 — 기록이 더 정확하고, 물으면 사용자는 앱이 자기 기록을 안 보고
/// 있다고 느낀다.
///
/// 여기서 묻는 것은 앱이 절대 알 수 없는 것뿐이다. 혼자 사는지, 집안일을
/// 누가 하는지, 앉아서 일하는지, 앞으로 어떻게 하고 싶은지. 맥락과 바람이다.
///
/// 한 번에 다 묻지 않는다. 코치를 처음 여는 자리에서 다섯 턴을 물으면 거기가
/// 이탈 지점이 된다. 처음에는 [firstAskLimit]개까지만 묻고, 나머지는 첫 제안을
/// 할 때 그 제안이 서는 근거로 필요해지면 하나씩 묻는다.
///
/// 냥냥이는 빠진다. 범용 플래너 코치라 담당 영역이라는 것이 없다. 마스터 둘도
/// 해당 없다 — 그쪽은 영역을 가리지 않고 실행 전반을 본다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 코치가 맡는 영역.
enum LifeDomain {
  /// 청소, 정리, 빨래, 설거지, 장보기, 분리수거.
  housework,

  /// 운동, 걷기, 스트레칭.
  activity,

  /// 건강, 위생, 그루밍, 자기 전에 하는 것들.
  selfCare,
}

/// 설문 한 문항.
class LifePatternQuestion {
  const LifePatternQuestion({
    required this.id,
    required this.ask,
    required this.options,
    this.multi = false,
  });

  /// 저장할 때 쓰는 이름.
  final String id;

  /// 사용자에게 보일 물음. 코치 말투는 화면 쪽에서 입힌다.
  final String ask;

  /// 버튼에 보일 말 → 코치에게 넘길 한 줄.
  ///
  /// 보이는 말을 그대로 저장한다. 코드용 값을 따로 두면 문구를 손볼 때마다
  /// 저장된 옛 값과 어긋나고, 그 어긋남은 조용히 답을 잃는 모양으로 나온다.
  final Map<String, String> options;

  /// 여러 개를 고를 수 있는지.
  final bool multi;

  List<String> get labels => options.keys.toList(growable: false);
}

class LifePatternService {
  const LifePatternService._();

  /// 클라우드로 실어야 기기를 바꿔도 남는다. 접두어만으로는 부족하고
  /// 동기화 키 목록에도 들어가 있어야 한다.
  static const String storeKey = 'nyang_life_pattern';

  /// 처음 들어왔을 때 물을 문항 수.
  static const int firstAskLimit = 3;

  /// 처음 파악한 것을 다시 확인하기까지.
  static const Duration reviewInterval = Duration(days: 30);

  /// 첫 확인만 이르게 한다.
  ///
  /// 처음 켠 사람에게 한 달 동안 아무 일도 안 일어나면 이 기능이 있는 줄도
  /// 모른다. 첫 판단은 기록이 적어 틀리기도 쉬워서 일찍 한 번 맞춰보는 편이
  /// 낫다.
  static const Duration firstReviewInterval = Duration(days: 14);

  /// 이 기능을 쓰는 코치와 담당 영역.
  static const Map<String, LifeDomain> domains = {
    'halmae': LifeDomain.housework,
    'bro': LifeDomain.activity,
    'boyfriend': LifeDomain.selfCare,
  };

  static bool handles(String coachId) => domains.containsKey(coachId);

  /// 이 코치가 무엇을 맡는지, 한 줄로.
  ///
  /// 무엇을 하라고 적지 않고 무엇을 맡는지만 적는다. 할 일을 적어두면 무슨
  /// 말이 들어와도 그것만 하고, 맡은 것만 적어두면 상황마다 다르게 나온다.
  ///
  /// 흩어져 있던 것을 한자리로 모은 자리다. 할매와 형은 담당 영역이 역할에
  /// 아예 없고 청소·운동 이야기가 나올 때만 노하우가 붙었다 — 사용자가 그
  /// 말을 안 꺼내면 자기가 무엇을 맡은 코치인지도 모르는 셈이었다. 반대로
  /// 햇살은 몸 이야기가 늘 실려서, 무슨 말을 하든 그쪽으로 갔다.
  static const Map<LifeDomain, String> _domainRoles = {
    LifeDomain.housework: '살림 — 청소, 정리, 빨래, 설거지, 장보기, 쓰레기',
    LifeDomain.activity: '몸을 움직이는 일 — 운동, 걷기, 스트레칭',
    LifeDomain.selfCare: '몸을 단장하고 컨디션을 챙기는 일 — 씻기, 피부와 머리, 옷차림, 먹고 자는 리듬',
  };

  /// 담당 영역 코치의 역할 한 줄. 맡은 영역이 없으면 빈 문자열.
  ///
  /// "시작부터 완료까지 돕는다"는 모든 코치에게 붙는 공통 줄에 이미 있다.
  /// 여기서 더하는 것은 앞부분이다 — 일상 이야기 속에서 자기 영역을 할 만한
  /// 자리를 알아채는 것. 그게 이 코치들만 하는 일이다.
  ///
  /// 알아채라고만 하면 없는 자리를 만들어낸다. 대상을 찾아야 하는 동사는 이
  /// 앱에서 여러 번 그렇게 됐다. 그래서 안 보이면 그냥 대화하라는 말을 같이
  /// 둔다.
  ///
  /// 분량 이야기는 청소와 운동 노하우에 따로 적혀 있던 것을 여기로 올렸다.
  /// 영역을 가리지 않고 필요한 말이라 세 번 적을 이유가 없었다. "단계별로"라고
  /// 쓰지 않은 것은 일부러다 — 그 말이 있으면 코치가 순서를 늘어놓는데, 목록을
  /// 읊는 대신 상황에 답하게 하려고 노하우에서 순서를 걷어낸 참이다.
  static String roleLine(String coachId) {
    final domain = domains[coachId];
    if (domain == null) return '';
    return '''
- 이 코치가 맡는 것은 ${_domainRoles[domain]}.
- 일상 이야기 속에 그 일을 할 만한 자리가 보이면 알아채고, 거기서부터 완료까지 함께 간다. 안 보이면 그냥 대화한다 — 없는 자리를 만들어내지 않는다.
- 자리를 잡을 때는 새로 만들기 전에 이미 하는 일에 붙일 수 있는지부터 본다. 매일 하는 행동 옆에 얹는 쪽이 잊을 일이 적다. (예: 씻고 나온 김에, 저녁 먹고 바로)
- 어떻게 잡을지는 이 사람이 고른 답을 따른다. 아래 [이 사람의 생활]에 적혀 있으면 그 방식으로 잡고, 없으면 그때 하나만 물어본다.
- 지금 상황과 컨디션에서 할 수 있는 분량을 먼저 판단한다. 모르겠으면 하나만 물어본다. 그 분량이 끝까지 가도록 돕되, 먼저 부담 없이 시작할 수 있는 첫 조각 하나를 짚어준다.''';
  }

  /// 코치별 설문. 앞에서부터 중요한 순서다.
  ///
  /// 순서가 곧 무엇을 먼저 물을지다. 첫 세 문항으로 제안 하나는 설 수 있어야
  /// 하고, 뒤로 갈수록 없어도 되는 것이어야 한다.
  static const Map<String, List<LifePatternQuestion>> surveys = {
    // 집안일은 분담부터 묻는다. 남이 주로 하는 집이면 이 코치가 제안할 것이
    // 거의 없어서, 뒤 문항을 물을 이유부터 사라진다.
    'halmae': [
      LifePatternQuestion(
        id: 'share',
        ask: '집안일은 주로 누가 하는 편이야?',
        options: {
          '대부분 내가 해': '집안일을 대부분 본인이 함.',
          '다른 사람과 나눠서 해': '집안일을 다른 사람과 나눠서 함.',
          '다른 사람이 주로 해': '집안일은 주로 다른 사람이 함. 본인 몫이 적음.',
        },
      ),
      LifePatternQuestion(
        id: 'want',
        ask: '요즘 가장 관리하고 싶은 건?',
        multi: true,
        options: {
          '청소·정리': '청소와 정리',
          '빨래': '빨래',
          '설거지·주방': '설거지와 주방',
          '식사·장보기': '식사와 장보기',
          '쓰레기·분리수거': '쓰레기와 분리수거',
          '전반적인 집 관리': '집 관리 전반',
        },
      ),
      LifePatternQuestion(
        id: 'style',
        ask: '앞으로는 어떻게 하고 싶어?',
        options: {
          '조금씩 자주 하고 싶어': '조금씩 자주 하는 쪽을 원함.',
          '몰아서 하고 싶어': '몰아서 하는 쪽을 원함. 매일 조금씩은 이 사람 방식이 아님.',
          '필요할 때 가끔 하고 싶어': '필요할 때만 가끔 하는 쪽을 원함.',
          '잘 모르겠어': '어떻게 하고 싶은지 아직 정하지 않음.',
        },
      ),
      // 여기부터는 첫 진입에서 묻지 않는다. 제안이 설 때 근거로 필요해지면
      // 그때 하나씩.
      LifePatternQuestion(
        id: 'current',
        ask: '지금은 보통 어떻게 하는 편이야?',
        options: {
          '조금씩 자주 하는 편': '지금은 조금씩 자주 하는 편.',
          '몰아서 하는 편': '지금은 몰아서 하는 편.',
          '자주 미루는 편': '지금은 자주 미루는 편.',
          '일정한 방식이 없어': '지금은 정해진 방식 없이 그때그때.',
        },
      ),
      LifePatternQuestion(
        id: 'household',
        ask: '지금 누구와 살고 있어?',
        options: {
          '혼자 살아': '혼자 삶.',
          '가족과 살아': '가족과 함께 삶.',
          '기타': '동거 형태를 따로 밝히지 않음.',
        },
      ),
    ],

    'bro': [
      LifePatternQuestion(
        id: 'posture',
        ask: '평소 하루는 어느 쪽에 가까워?',
        options: {
          '앉아 있는 시간이 많아': '하루 대부분 앉아 있음.',
          '서 있는 시간이 많아': '하루 대부분 서 있음.',
          '걷거나 움직이는 시간이 많아': '하루 중 걷거나 움직이는 시간이 많음.',
          '그날그날 달라': '날마다 활동량이 다름.',
        },
      ),
      LifePatternQuestion(
        id: 'commute',
        ask: '평소 이동은 주로 어떻게 해?',
        options: {
          '자가용을 많이 이용해': '자가용으로 이동함. 오가는 길에 걷는 양이 거의 없음.',
          '대중교통을 많이 이용해': '대중교통으로 이동함. 오가는 길에 이미 걷고 있음.',
          '걷는 편이야': '주로 걸어서 이동함.',
          '집에서 주로 생활해': '집에서 주로 생활함. 밖으로 나가는 일이 적음.',
          '그날그날 달라': '날마다 이동 방식이 다름.',
        },
      ),
      LifePatternQuestion(
        id: 'doing',
        ask: '지금 따로 하는 운동이 있어?',
        options: {
          '따로 안 해': '따로 하는 운동 없음.',
          '걷기 정도 해': '걷기 정도를 하고 있음.',
          '홈트 해': '집에서 하는 운동을 하고 있음.',
          '헬스장·운동시설에 다녀': '헬스장이나 운동시설에 다님.',
          '기타': '위 보기에 없는 운동을 하고 있음.',
        },
      ),
      // 무엇을 권할지 고르는 데만 쓴다. 이 답을 화제로 삼지 않는다 —
      // 몸 이야기는 코치가 먼저 꺼낼 말이 아니다.
      LifePatternQuestion(
        id: 'why',
        ask: '운동하는 가장 큰 이유는 뭐야?',
        options: {
          '건강·체력 관리': '건강과 체력을 위해 함.',
          '몸매 관리': '몸매 관리를 위해 함.',
          '둘 다': '건강과 몸매 둘 다를 위해 함.',
        },
      ),
    ],

    'boyfriend': [
      LifePatternQuestion(
        id: 'habitLevel',
        ask: '평소 자기관리는 어느 쪽에 가까워?',
        options: {
          '웬만한 건 매일 꾸준히 챙겨': '웬만한 것은 매일 챙기고 있음. 이미 잘 되고 있는 쪽.',
          '최소한의 것만 챙기는 편이야': '꼭 필요한 것만 챙기는 편.',
          '어쩌다 생각날 때 하는 편이야': '생각날 때만 챙기는 편.',
          '자주 까먹거나 미뤄': '자주 잊거나 미루는 편.',
        },
      ),
      LifePatternQuestion(
        id: 'want',
        ask: '요즘 더 챙기고 싶은 게 뭐야?',
        multi: true,
        options: {
          // 수면은 앱의 다른 층이 이미 다룬다. 고른 사람에게도 잠 자체를
          // 코칭하지 않고, 자기 전에 하는 일을 어디에 놓을지까지만 본다.
          '수면·생활 리듬': '잠들기 전에 하는 것들 (잠 자체는 앱의 다른 자리에서 다룸)',
          '식사·수분 섭취': '식사와 물 마시기',
          '기본 위생': '기본 위생',
          '피부·헤어 관리': '피부와 머리 관리',
          '옷차림·외모 관리': '옷차림과 겉모습',
          '영양제 등 건강관리': '영양제 같은 건강 관리',
          '딱히 없어': '특별히 챙기고 싶은 것 없음.',
        },
      ),
      LifePatternQuestion(
        id: 'style',
        ask: '자기관리는 어떤 방식이 제일 편해?',
        options: {
          '아침이나 저녁 시간을 정해서': '아침이나 저녁에 시간을 정해두는 쪽이 편함.',
          '특정 요일에 몰아서': '특정 요일에 몰아서 하는 쪽이 편함.',
          '필요할 때 그때그때': '필요할 때 그때그때 하는 쪽이 편함.',
        },
      ),
    ],
  };

  static List<LifePatternQuestion> questionsFor(String coachId) =>
      surveys[coachId] ?? const [];

  static LifePatternQuestion? questionById(String coachId, String id) {
    for (final question in questionsFor(coachId)) {
      if (question.id == id) return question;
    }
    return null;
  }

  // ── 저장소 ────────────────────────────────────

  static Future<Map<String, dynamic>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(storeKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  /// 그 코치의 프로필. 아직 없으면 빈 map.
  static Future<Map<String, dynamic>> profile(String coachId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final all = await _readAll(prefs);
    final mine = all[coachId];
    return mine is Map ? Map<String, dynamic>.from(mine) : {};
  }

  /// 프로필의 일부만 바꿔 쓴다. 다른 코치의 것은 건드리지 않는다.
  static Future<void> update(
    String coachId,
    Map<String, dynamic> changes,
  ) async {
    if (!handles(coachId)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final all = await _readAll(prefs);
    final mine = all[coachId];
    final merged = <String, dynamic>{
      if (mine is Map) ...Map<String, dynamic>.from(mine),
      ...changes,
    };
    all[coachId] = merged;
    await prefs.setString(storeKey, jsonEncode(all));
  }

  // ── 설문 진행 ─────────────────────────────────

  /// 지금까지 받은 답. 문항 id → 고른 말(복수면 목록).
  static Future<Map<String, dynamic>> answers(String coachId) async {
    final saved = (await profile(coachId))['answers'];
    return saved is Map ? Map<String, dynamic>.from(saved) : {};
  }

  /// 답 하나를 적는다. 목록에 없는 말은 받지 않는다.
  static Future<void> saveAnswer(
    String coachId,
    String questionId,
    List<String> picked,
  ) async {
    final question = questionById(coachId, questionId);
    if (question == null || picked.isEmpty) return;
    final valid = picked
        .where(question.options.containsKey)
        .toList(growable: false);
    if (valid.isEmpty) return;

    final current = await answers(coachId);
    current[questionId] = question.multi ? valid : valid.first;
    await update(coachId, {
      'answers': current,
      'askedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 아직 안 물어본 문항들. 순서는 설문에 적힌 그대로.
  static Future<List<LifePatternQuestion>> unanswered(String coachId) async {
    final saved = await answers(coachId);
    return questionsFor(coachId)
        .where((question) => !saved.containsKey(question.id))
        .toList(growable: false);
  }

  /// 처음 들어왔을 때 물을 문항들. 이미 물은 게 있으면 그만큼 줄어든다.
  ///
  /// 세 개까지만 준다. 나머지는 첫 제안을 할 때 하나씩 묻는다.
  static Future<List<LifePatternQuestion>> firstAsk(String coachId) async {
    final saved = await answers(coachId);
    if (saved.length >= firstAskLimit) return const [];
    final remaining = await unanswered(coachId);
    return remaining
        .take(firstAskLimit - saved.length)
        .toList(growable: false);
  }

  /// 첫 진입 몫을 다 물었는지. 이걸 넘겨야 제안을 시작한다.
  static Future<bool> readyToCoach(String coachId) async {
    final saved = await answers(coachId);
    final total = questionsFor(coachId).length;
    return saved.length >= (total < firstAskLimit ? total : firstAskLimit);
  }

  /// 제안이 설 때 하나만 더 물을 문항. 없으면 null.
  static Future<LifePatternQuestion?> nextFollowUp(String coachId) async {
    final remaining = await unanswered(coachId);
    return remaining.isEmpty ? null : remaining.first;
  }

  /// 이 사람에게 루틴이 도구인지.
  ///
  /// 루틴은 앞으로 계속 하겠다는 약속이라 무겁다. 필요할 때만 하고 싶다고 한
  /// 사람에게 반복 약속을 권하면, 권한 쪽은 도와준 셈이지만 받는 쪽은 안 지킬
  /// 것을 하나 더 떠안는다.
  ///
  /// 모르겠으면 null. 그때는 가벼운 쪽(오늘 하나)부터 간다 — 루틴이 맞는
  /// 사람이라면 오늘 한 번 해본 뒤에 스스로 반복으로 만든다.
  static bool? prefersRoutineFrom(String coachId, Map<String, dynamic> saved) {
    switch (coachId) {
      case 'halmae':
        return switch (saved['style']) {
          // 몰아서 하는 것도 반복이다. 주말 한 번짜리 루틴이 그 사람 모양이다.
          '조금씩 자주 하고 싶어' || '몰아서 하고 싶어' => true,
          '필요할 때 가끔 하고 싶어' => false,
          _ => null,
        };
      case 'boyfriend':
        return switch (saved['style']) {
          '아침이나 저녁 시간을 정해서' || '특정 요일에 몰아서' => true,
          '필요할 때 그때그때' => false,
          _ => null,
        };
      case 'bro':
        // 운동은 방식을 따로 묻지 않는다. 이미 뭔가 하고 있으면 반복이 도구인
        // 사람이고, 아무것도 안 하는 사람에게 주 몇 회부터 권할 일은 아니다.
        return switch (saved['doing']) {
          null || '따로 안 해' => null,
          _ => true,
        };
      default:
        return null;
    }
  }

  // ── 담당으로 가려둔 루틴 ──────────────────────

  /// 이 코치 담당으로 가려둔 루틴들. 아직 안 갈랐으면 빈 집합.
  static Future<Set<String>> domainHabitIds(String coachId) async {
    final saved = (await profile(coachId))['routineIds'];
    if (saved is! List) return const {};
    return saved.map((e) => e.toString()).toSet();
  }

  static Future<void> saveDomainHabitIds(
    String coachId,
    Set<String> ids, {
    DateTime? now,
  }) => update(coachId, {
    'routineIds': ids.toList(growable: false),
    'analyzedAt': (now ?? DateTime.now()).toIso8601String(),
  });

  // ── 다시 확인할 때 ────────────────────────────

  /// 파악한 것을 다시 확인할 때가 됐는지.
  ///
  /// 한 번도 확인한 적 없으면 첫 간격(2주), 그다음부터 30일이다.
  static Future<bool> dueForReview(String coachId, {DateTime? now}) async {
    if (!await readyToCoach(coachId)) return false;
    final saved = await profile(coachId);
    final reviewed = DateTime.tryParse(
      saved['reviewedAt']?.toString() ?? '',
    );
    final asked = DateTime.tryParse(saved['askedAt']?.toString() ?? '');
    final at = now ?? DateTime.now();

    if (reviewed == null) {
      if (asked == null) return false;
      return at.difference(asked) >= firstReviewInterval;
    }
    return at.difference(reviewed) >= reviewInterval;
  }

  /// 확인했다는 표시. 답이 그대로였든 바뀌었든 확인은 확인이다.
  static Future<void> markReviewed(String coachId, {DateTime? now}) =>
      update(coachId, {
        'reviewedAt': (now ?? DateTime.now()).toIso8601String(),
      });

  /// 다시 확인할 때 보여줄 말.
  ///
  /// 설문을 다시 돌리지 않는다. 지난번에 뭐라고 답했는지를 그대로 읽어주고
  /// 바뀐 게 있는지만 한 번 묻는다.
  ///
  /// 바뀌기 쉬운 것만 읽어준다. 동거 형태나 이동 수단은 몇 달째 그대로일
  /// 값이라 30일마다 확인할 이유가 없고, 안 바뀌는 것까지 매번 확인하면 그
  /// 자체가 잔소리가 된다.
  static const Set<String> _worthReviewing = {'want', 'style', 'doing'};

  /// 다시 확인할 만한 문항들. 바뀐 게 있다고 할 때 이것부터 다시 묻는다.
  static List<LifePatternQuestion> reviewableQuestions(String coachId) =>
      questionsFor(coachId)
          .where((question) => _worthReviewing.contains(question.id))
          .toList(growable: false);

  static Future<String> reviewSummary(String coachId) async {
    final saved = await answers(coachId);
    final parts = <String>[];
    for (final question in questionsFor(coachId)) {
      if (!_worthReviewing.contains(question.id)) continue;
      final value = saved[question.id];
      if (value == null) continue;
      final picked = value is List
          ? value.map((e) => e.toString()).toList()
          : [value.toString()];
      if (picked.isEmpty) continue;
      parts.add(picked.map((label) => "'$label'").join(', '));
    }
    return parts.join(', ');
  }

  // ── 코치에게 넘길 것 ──────────────────────────

  /// 프롬프트에 실을 묶음. 답이 하나도 없으면 빈 문자열.
  static Future<String> promptBlock(String coachId) async {
    if (!handles(coachId)) return '';
    final saved = await answers(coachId);
    if (saved.isEmpty) return '';

    final buffer = StringBuffer('\n[이 사람의 생활 - 본인이 직접 고른 답]\n');
    for (final question in questionsFor(coachId)) {
      final value = saved[question.id];
      if (value == null) continue;
      final picked = value is List
          ? value.map((e) => e.toString()).toList()
          : [value.toString()];
      final notes = picked
          .map((label) => question.options[label])
          .whereType<String>()
          .toList(growable: false);
      if (notes.isEmpty) continue;
      buffer.writeln('- ${notes.join(' / ')}');
    }
    buffer.writeln('*짐작이 아니라 본인이 고른 답입니다. 무엇을 권할지도, 언제 어떻게 넣을지도 이 답 안에서 정하세요.');
    // 실어주기만 하고 어떻게 쓰라는 말이 없으면, 코치는 이 답을 읽고도 자기가
    // 아는 일반적인 방법을 권한다. 그 사람이 아니라고 말해둔 방식으로.
    buffer.writeln(
      '*고른 방식과 어긋나게 권하지 마세요. 몰아서 하고 싶다고 한 사람에게 매일 조금씩은 그 사람의 방식이 아니고, 필요할 때 그때그때 하고 싶다고 한 사람에게 정해진 시각을 만들어 주면 안 지킬 약속이 하나 느는 것뿐입니다.',
    );
    return buffer.toString();
  }
}
