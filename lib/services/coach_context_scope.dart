/// 이번 턴에 사용자 기록을 어디까지 실어 보낼지 정한다.
///
/// 조회 자체는 기기 안에서 읽는 거라 공짜다. 값이 나가는 건 읽은 걸 프롬프트에
/// 실어 보낼 때다. 토큰값보다 큰 문제는 지시가 묻히는 것이다. 잡담 한 마디에
/// 7일 기록과 비전까지 딸려 나가면, 그날 꼭 지켜야 할 한 줄이 그 사이에 파묻힌다.
///
/// 판단은 세 단계다.
/// - full: 이번 말이 직접 목표·방향을 물었다. 7일 기록, 실행률, 비전 메모까지 전부.
/// - light: 직전 말이 목표 얘기였거나 귀찮다고 했다. 목표 제목만.
/// - none: 그 외. 아무것도 싣지 않는다.
///
/// 예전에는 이번 말과 직전 말을 한 줄로 이어 붙여 한 번에 검사했다. 그래서
/// "오늘 뭐부터 하지?" 다음 턴에 "아 배고파"라고만 해도 전부 다시 실렸다.
/// 직전 말을 상속하는 것 자체는 맞다 — 코치가 되물었을 때 "응 그거"처럼 짧게
/// 답하는 턴에서 맥락이 뚝 끊기면 안 되니까. 다만 상속받은 신호로 full까지
/// 여는 건 과하다. 상속은 light까지만 연다.
library;

/// 목표·비전·기록을 어디까지 실을지.
enum GoalContextScope {
  /// 싣지 않음.
  none,

  /// 목표 제목만. 지금 하는 이야기와 목표가 이어질 때 짧게 짚을 수 있을 만큼.
  light,

  /// 7일 기록, 평균 실행률, 마일스톤 메모까지 전부.
  full,
}

/// 한 턴에 실을 범위.
class CoachContextScope {
  const CoachContextScope({
    required this.goal,
    required this.tasks,
    required this.avoidanceLink,
    this.allowsGoals = false,
  });

  /// 목표·비전·기록의 범위.
  final GoalContextScope goal;

  /// 오늘 할 일 목록을 실을지.
  final bool tasks;

  /// 이 코치가 목표·비전을 볼 수 있는지. 마스터 코치만 true.
  ///
  /// 프렌즈 코치는 오늘 하루만 다룬다. 장기 목표를 쥐여주면 압박 없는 자리라는
  /// 전제가 깨진다. 화면 쪽 조립부에도 코치 구분이 따로 걸려 있지만, 범위를
  /// 넓히는 길에서도 막아둔다. 한쪽 가드가 빠져도 비전이 새지 않게.
  final bool allowsGoals;

  /// [귀찮음 상황의 목표 연결 규칙]을 붙일지.
  ///
  /// 목표를 얇게 싣는 이유가 두 가지(귀찮음 / 직전 말 상속)라서 따로 둔다.
  /// 귀찮다고 한 적 없는 턴에 "귀찮아하는 일과 목표를 연결하라"는 지시가
  /// 붙으면, 코치가 없는 감정을 있다고 치고 말을 건다.
  final bool avoidanceLink;

  bool get needsFullGoal => goal == GoalContextScope.full;
  bool get needsLightGoal => goal == GoalContextScope.light;
  bool get needsAnyGoal => goal != GoalContextScope.none;

  /// 코치가 정보가 모자라다고 알려왔을 때 범위를 넓힌다. 좁히지는 않는다.
  ///
  /// 목표를 볼 수 없는 코치에게는 목표 요청이 아무 일도 하지 않는다.
  CoachContextScope escalated({bool goals = false, bool tasks = false}) {
    final openGoals = goals && allowsGoals;
    return CoachContextScope(
      goal: openGoals ? GoalContextScope.full : goal,
      tasks: this.tasks || tasks || openGoals,
      avoidanceLink: avoidanceLink,
      allowsGoals: allowsGoals,
    );
  }

  @override
  String toString() =>
      'CoachContextScope(goal: ${goal.name}, tasks: $tasks, '
      'avoidanceLink: $avoidanceLink, allowsGoals: $allowsGoals)';
}

/// 코치가 "이걸론 답을 못 하겠다"고 알려온 요청.
///
/// 앱이 미리 고르는 방식은 사용자가 쓴 말만 보고 정한다. 그래서 예상 밖으로
/// 말하면 필요한 걸 빠뜨린다. 그렇다고 매 턴 따로 판단 호출을 붙이면 잡담
/// 한마디에도 왕복이 하나 더 늘어 전부 느려진다. 그래서 코치가 직접 요청하게
/// 한다. 평소에는 왕복 한 번이고, 실제로 모자란 턴만 두 번이 된다.
class CoachContextRequest {
  const CoachContextRequest({required this.goals, required this.tasks});

  static const CoachContextRequest none = CoachContextRequest(
    goals: false,
    tasks: false,
  );

  final bool goals;
  final bool tasks;

  bool get isEmpty => !goals && !tasks;
  bool get isNotEmpty => !isEmpty;

  static final RegExp _pattern = RegExp(
    r'\[NEED:\s*([a-zA-Z_,\s]+?)\]',
    caseSensitive: false,
  );

  static CoachContextRequest parse(String reply) {
    final matches = _pattern.allMatches(reply);
    if (matches.isEmpty) return none;

    var goals = false;
    var tasks = false;
    for (final match in matches) {
      for (final raw in (match.group(1) ?? '').split(',')) {
        switch (raw.trim().toLowerCase()) {
          case 'goals':
          case 'goal':
            goals = true;
          case 'tasks':
          case 'task':
            tasks = true;
        }
      }
    }
    return CoachContextRequest(goals: goals, tasks: tasks);
  }

  /// 태그가 답변에 섞여 나왔을 때 지운다. 재시도 뒤에도 남아 있으면 사용자
  /// 화면에 그대로 보이므로, 마지막에 한 번 더 훑는다.
  static String strip(String reply) => reply
      .replaceAll(_pattern, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

class CoachContextScopeService {
  const CoachContextScopeService._();

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 목표·방향·평가를 묻는 말. 걸리면 기록을 전부 싣는다.
  static const List<String> goalSignals = [
    '비전',
    '마일스톤',
    '장기목표',
    '주간목표',
    '월간목표',
    '이번주목표',
    '이번달목표',
    '목표',
    '우선순위',
    '뭐부터',
    '무엇부터',
    '뭘먼저',
    '뭐먼저',
    '어디서부터',
    '먼저해야',
    '뭘해야',
    '뭐해야',
    '해야할지',
    '어떻게해야',
    '뭐하지',
    '추천해',
    '추천받',
    '일정짜',
    '스케줄짜',
    '계획짜',
    '정리해줘',
    '방향잡',
    '잘하고있',
    '잘하고있는',
    '제대로하고',
    '잘해내고',
    '가고있는',
    '맞게가고',
    '맞는방향',
    '제자리',
    '진행상황',
    '성과',
    '평가해',
    '분석해',
    '돌아봐',
    '흐름어때',
    '뒤처',
    '감이안',
  ];

  /// 오늘 할 일 목록이 있어야 답할 수 있는 말.
  static const List<String> taskSignals = [
    '할일',
    '일정',
    '스케줄',
    '습관',
    '타이머',
    '미완료',
    '완료했',
    '끝냈',
    '해야돼',
    '해야해',
  ];

  /// 하기 싫다는 표현. 목표를 얇게 실어서 의미를 짚어줄 수 있게 한다.
  static const List<String> avoidanceSignals = [
    '귀찮',
    '하기싫',
    '못하겠',
    '미루고싶',
    '나중에할',
    '손이안가',
    '시작하기싫',
  ];

  /// 명사와 동사 사이에 끼어드는 조사·부사 자리.
  ///
  /// "계획 짜줘"와 "계획 좀 다시 짜줘"는 같은 말인데, 고정 문자열로 찾으면
  /// 뒤쪽을 통째로 놓친다. 실제로 사용자가 쓰는 문장은 거의 뒤쪽이라
  /// 여기를 비워두면 계획을 짜달라는 말 대부분이 빠져나간다.
  static const String _particleGap =
      r'(?:[을를은는이가도만]|좀|다시|한번|새로|대충|빨리|미리|어떻게|같이|함께|오늘|내일|이번주|이번달|하루|주간|월간|전체|조금|살짝)*';

  /// 고정 문자열로는 못 잡는 목표 신호.
  ///
  /// 지금은 계획 세우기 계열만 있다. 이 계열은 "짜다"와 "세우다"가 섞여 쓰이고
  /// 사이에 부사가 끼는 일이 잦아서 목록으로는 감당이 안 됐다.
  ///
  /// 어간도 여러 형태로 갈린다. "세울까"는 둘째 글자가 '울'이라 '세우'로는
  /// 안 걸린다. 한글은 이렇게 받침이 붙으면 글자 자체가 달라져서, 활용형을
  /// 하나씩 적어줘야 한다.
  static final List<RegExp> _goalPatterns = [
    RegExp('(?:계획|일정|스케줄|플랜)$_particleGap(?:짜|세우|세워|세울|세운|잡아|잡자|만들)'),
  ];

  static bool hasGoalSignal(String text) {
    final normalized = _normalize(text);
    if (goalSignals.any(normalized.contains)) return true;
    return _goalPatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  static bool hasTaskSignal(String text) =>
      taskSignals.any(_normalize(text).contains);

  static bool isAvoidanceMessage(String text) =>
      avoidanceSignals.any(_normalize(text).contains);

  /// [previousUserText]는 이번 말을 뺀 직전 사용자 발화다. 없으면 null.
  ///
  /// 예전 코드는 대화 목록에서 사용자 발화 2개를 꺼내 이번 말과 이어 붙였는데,
  /// 이번 말이 이미 목록에 들어가 있어서 실제로는 이번 말 + 직전 말 하나였다.
  /// 의도했던 창보다 하나 짧았고 같은 문장이 두 번 실렸다. 이제 호출하는 쪽이
  /// 직전 말을 명시적으로 넘긴다.
  static CoachContextScope resolve({
    required bool isMaster,
    required String currentText,
    String? previousUserText,
    bool timerAuthorization = false,
  }) {
    // 프렌즈 코치는 목표를 다루지 않는다. 오늘 하루만 본다.
    if (!isMaster) {
      return const CoachContextScope(
        goal: GoalContextScope.none,
        tasks: true,
        avoidanceLink: false,
        allowsGoals: false,
      );
    }

    final currentGoal = hasGoalSignal(currentText);
    final currentAvoidance = isAvoidanceMessage(currentText);
    final previous = previousUserText ?? '';
    final previousGoal = previous.isNotEmpty && hasGoalSignal(previous);
    final previousAvoidance =
        previous.isNotEmpty && isAvoidanceMessage(previous);

    final GoalContextScope goal;
    if (currentGoal) {
      goal = GoalContextScope.full;
    } else if (currentAvoidance || previousAvoidance || previousGoal) {
      goal = GoalContextScope.light;
    } else {
      goal = GoalContextScope.none;
    }

    return CoachContextScope(
      goal: goal,
      tasks:
          goal != GoalContextScope.none ||
          timerAuthorization ||
          hasTaskSignal(currentText),
      avoidanceLink:
          goal == GoalContextScope.light &&
          (currentAvoidance || previousAvoidance),
      allowsGoals: true,
    );
  }
}
