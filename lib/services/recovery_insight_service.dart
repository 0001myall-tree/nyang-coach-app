import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LowActivationSummary {
  final int evaluatedDays;
  final int lowActivationDays;
  final int thresholdDays;
  final int minTotalCount;
  final int maxStartedCount;
  final double maxCompletionRate;

  const LowActivationSummary({
    required this.evaluatedDays,
    required this.lowActivationDays,
    required this.thresholdDays,
    required this.minTotalCount,
    required this.maxStartedCount,
    required this.maxCompletionRate,
  });

  bool get hasStrongSignal => lowActivationDays >= thresholdDays;
}

class RecoveryInsightService {
  static const String strategyKey = 'nyang_recovery_strategy';
  static const String fatigueSignalCountsKey = 'nyang_fatigue_signal_counts';
  static const String causePlanningOverload = 'planning_overload';
  static const String causeMotivationDrop = 'motivation_drop';
  static const String causePhysicalFatigue = 'physical_fatigue';
  static const String sourceRestDeclineRiskControl =
      'rest_decline_risk_control';
  static const String sourceLowActivationRestart = 'low_activation_restart';

  static const int lowActivationWindowDays = 7;
  static const int lowActivationThresholdDays = 3;
  static const int minTotalCount = 3;
  static const int maxStartedCount = 1;
  static const double maxCompletionRate = 0.2;
  static const int performanceDropWindowDays = 7;
  static const int performanceDropHighDays = 2;
  static const int performanceDropRecentDays = 2;
  static const double performanceDropHighCompletionRate = 0.8;
  static const double performanceDropLowCompletionRate = 0.35;
  static const int restDeclineRiskControlDays = 1;
  static const int lowActivationRestartDays = 1;
  static const int physicalFatigueLateWindowDays = 3;
  static const int physicalFatigueLateThresholdDays = 2;
  static const int fatigueSignalWindowDays = 3;
  static const int fatigueSignalThresholdCount = 4;
  static const int restOfferFatigueWindowDays = 3;
  static const int restOfferFatigueThresholdCount = 5;

  static const List<String> _highCognitiveKeywords = [
    '공부',
    '기획',
    '창작',
    '전략',
    '문제',
    '해결',
    '분석',
    '정리',
    '글',
    '작성',
    '개발',
    '코딩',
    '설계',
    '회의',
    '자료',
    '리서치',
    '논문',
    '강의',
    '시험',
    '아이디어',
  ];

  static LowActivationSummary calculateLowActivationSummary(
    List<Map<String, dynamic>> history, {
    DateTime? referenceDate,
  }) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in history) {
      final date = record['date']?.toString();
      if (date == null || date.isEmpty) continue;
      byDate[date] = record;
    }

    final base = _dateOnly(referenceDate ?? DateTime.now());
    var evaluatedDays = 0;
    var lowActivationDays = 0;

    for (var offset = 0; offset < lowActivationWindowDays; offset++) {
      final date = base.subtract(Duration(days: offset));
      final record = byDate[_dateKey(date)];
      if (record == null || record['isVacation'] == true) continue;

      final totalCount = (record['totalCount'] as num?)?.toInt() ?? 0;
      if (totalCount < minTotalCount) continue;

      evaluatedDays++;
      final doneCount = (record['doneCount'] as num?)?.toInt() ?? 0;
      final completionRate = totalCount == 0 ? 0.0 : doneCount / totalCount;
      final startedCount = _startedCount(record);

      if (startedCount <= maxStartedCount &&
          completionRate <= maxCompletionRate) {
        lowActivationDays++;
      }
    }

    return LowActivationSummary(
      evaluatedDays: evaluatedDays,
      lowActivationDays: lowActivationDays,
      thresholdDays: lowActivationThresholdDays,
      minTotalCount: minTotalCount,
      maxStartedCount: maxStartedCount,
      maxCompletionRate: maxCompletionRate,
    );
  }

  static Future<Map<String, dynamic>?> getActiveStrategy() async {
    final prefs = await SharedPreferences.getInstance();
    return activeStrategyFromPrefs(prefs);
  }

  static Map<String, dynamic>? activeStrategyFromPrefs(
    SharedPreferences prefs,
  ) {
    final raw = prefs.getString(strategyKey);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final strategy = Map<String, dynamic>.from(decoded);
      final expiresAt = DateTime.tryParse(
        strategy['expiresAt']?.toString() ?? '',
      );
      if (expiresAt == null || expiresAt.isBefore(DateTime.now())) {
        prefs.remove(strategyKey);
        return null;
      }
      return strategy;
    } catch (_) {
      prefs.remove(strategyKey);
      return null;
    }
  }

  static Future<bool> isRecoveryStrategyActive() async {
    return await getActiveStrategy() != null;
  }

  static Future<void> recordFatigueSignalToday() async {
    final prefs = await SharedPreferences.getInstance();
    final counts = _loadStringIntMap(prefs.getString(fatigueSignalCountsKey));
    final todayKey = _dateKey(_dateOnly(DateTime.now()));
    counts[todayKey] = (counts[todayKey] ?? 0) + 1;

    final cutoff = _dateOnly(
      DateTime.now(),
    ).subtract(const Duration(days: fatigueSignalWindowDays - 1));
    counts.removeWhere((date, _) {
      final parsed = DateTime.tryParse(date);
      return parsed == null || parsed.isBefore(cutoff);
    });

    await prefs.setString(fatigueSignalCountsKey, jsonEncode(counts));
  }

  static Future<bool> hasRecentFatigueSignalBurst() async {
    final prefs = await SharedPreferences.getInstance();
    final counts = _loadStringIntMap(prefs.getString(fatigueSignalCountsKey));
    final base = _dateOnly(DateTime.now());
    var total = 0;
    for (var offset = 0; offset < restOfferFatigueWindowDays; offset++) {
      total += counts[_dateKey(base.subtract(Duration(days: offset)))] ?? 0;
    }
    return total >= restOfferFatigueThresholdCount;
  }

  static Future<void> startMasterRestDeclineRiskControlIfEligible({
    required bool isMasterCoach,
    DateTime? referenceDate,
  }) async {
    if (!isMasterCoach) return;
    final prefs = await SharedPreferences.getInstance();
    final history = _loadHistory(prefs);
    final cause = _inferPrimaryCause(
      prefs,
      history,
      referenceDate: referenceDate,
      includeMotivationDrop: false,
      includePerformanceDropMotivation: true,
    );
    if (cause == null) return;

    final now = DateTime.now();
    final strategy = {
      'primaryCause': cause,
      'startedAt': now.toIso8601String(),
      'expiresAt': now
          .add(const Duration(days: restDeclineRiskControlDays))
          .toIso8601String(),
      'days': restDeclineRiskControlDays,
      'source': sourceRestDeclineRiskControl,
    };
    await prefs.setString(strategyKey, jsonEncode(strategy));
  }

  static Future<void> startMasterLowActivationRestartIfEligible({
    required bool isMasterCoach,
    int? plannerAwayDays,
  }) async {
    if (!isMasterCoach) return;
    final prefs = await SharedPreferences.getInstance();
    if (activeStrategyFromPrefs(prefs) != null) return;

    final history = _loadHistory(prefs);
    final hasLowActivation = _hasRecentLowActivationRestartSignal(history);
    final hasAwaySignal = plannerAwayDays != null && plannerAwayDays >= 3;
    if (!hasLowActivation && !hasAwaySignal) return;

    final now = DateTime.now();
    final strategy = {
      'primaryCause': causeMotivationDrop,
      'startedAt': now.toIso8601String(),
      'expiresAt': now
          .add(const Duration(days: lowActivationRestartDays))
          .toIso8601String(),
      'days': lowActivationRestartDays,
      'source': sourceLowActivationRestart,
    };
    if (plannerAwayDays != null) {
      strategy['plannerAwayDays'] = plannerAwayDays;
    }
    await prefs.setString(strategyKey, jsonEncode(strategy));
  }

  static bool hasRecentPerformanceDrop(
    List<Map<String, dynamic>> history, {
    DateTime? referenceDate,
  }) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in history) {
      final date = record['date']?.toString();
      if (date == null || date.isEmpty) continue;
      byDate[date] = record;
    }

    final base = _dateOnly(referenceDate ?? DateTime.now());
    var highDays = 0;

    for (var offset = 1; offset <= performanceDropWindowDays; offset++) {
      final record = byDate[_dateKey(base.subtract(Duration(days: offset)))];
      final rate = _completionRateForComparableDay(record);
      if (rate != null && rate >= performanceDropHighCompletionRate) {
        highDays++;
      }
    }
    if (highDays < performanceDropHighDays) return false;

    for (var offset = 1; offset <= performanceDropRecentDays; offset++) {
      final record = byDate[_dateKey(base.subtract(Duration(days: offset)))];
      final rate = _completionRateForComparableDay(record);
      if (rate == null || rate > performanceDropLowCompletionRate) {
        return false;
      }
    }

    return true;
  }

  static Future<String?> localInProgressPraise({
    required bool isMasterCoach,
    required String coachId,
  }) async {
    if (!isMasterCoach) return null;
    final strategy = await getActiveStrategy();
    if (strategy?['primaryCause'] != causeMotivationDrop) return null;
    if (coachId == 'sec_female') {
      return '대표님, 지금 시작하신 것만으로도 정말 잘하셨어요. 오늘은 이 작은 시작을 제일 크게 볼게요.';
    }
    return '대표님, 시작하신 것만으로도 충분히 좋은 신호입니다. 오늘은 이 흐름만 살려도 괜찮습니다.';
  }

  static Future<String?> buildMasterRecoveryPromptGuidance() async {
    final prefs = await SharedPreferences.getInstance();
    final strategy = activeStrategyFromPrefs(prefs);
    if (strategy == null) return null;

    final primaryCause = strategy['primaryCause']?.toString();
    final source =
        strategy['source']?.toString() ?? sourceRestDeclineRiskControl;
    final days =
        (strategy['days'] as num?)?.toInt() ??
        (source == sourceLowActivationRestart
            ? lowActivationRestartDays
            : restDeclineRiskControlDays);
    final highCognitiveTasks = _todayHighCognitiveTasks(prefs);
    final taskList = highCognitiveTasks.take(4).join(', ');
    final hasHighCognitiveLoad = highCognitiveTasks.length >= 2;
    final todayTasks = _todayOpenTaskTexts(prefs);
    final hasLowActivationTaskLoad =
        todayTasks.length >= 5 && highCognitiveTasks.length >= 2;
    final restartAction = _restartActionCandidate(todayTasks);
    final lightMovementTasks = _todayLightMovementTasks(prefs);
    final movementList = lightMovementTasks.take(3).join(', ');
    final isLowActivationRestart = source == sourceLowActivationRestart;

    final buffer = StringBuffer()
      ..writeln(
        isLowActivationRestart
            ? '\n[특별 지침: 저활성 후 $days일 재시작 코칭 정책 - 마스터 코치 전용]'
            : '\n[특별 지침: 휴식 제안 거절 후 $days일 위험 완충 코칭 정책 - 마스터 코치 전용]',
      )
      ..writeln(
        isLowActivationRestart
            ? '현재 사용자는 최근 실행 저하 또는 플래너 공백 이후 다시 진입한 상태입니다. 복귀를 반갑게 맞이하는 표현은 사용할 수 있지만, 이 기간에는 선제 대응, 미룬 항목 추궁, 압박 질문을 하지 마세요.'
            : '현재 사용자는 소진 위험 신호로 휴식 제안을 받았지만 휴식 모드에 진입하지 않고 계속 진행하려는 상태입니다. 이 기간에는 선제 대응, 미룬 항목 추궁, "언제 하실 건가요" 식의 압박 질문을 하지 마세요.',
      );

    if (isLowActivationRestart) {
      if (hasLowActivationTaskLoad) {
        buffer.writeln('오늘 남은 할 일이 5개 이상이고 고인지 과제가 2개 이상입니다.');
        buffer.writeln('오늘의 고인지 과제 후보: $taskList');
        buffer.writeln(
          '전체 목록을 압박하지 말고, 고인지 과제 중 하나를 아주 작은 첫 단계로 쪼개 부담을 낮추도록 제안하세요.',
        );
      }
      if (restartAction != null) {
        buffer.writeln('재시작 후보 행동: $restartAction');
        buffer.writeln('성공 가능성이 높은 아주 작은 행동 하나부터 추천하고, 완료보다 시작을 우선 성과로 인정하세요.');
      } else {
        buffer.writeln('성공 가능성이 높은 아주 작은 행동 하나부터 추천하고, 완료보다 시작을 우선 성과로 인정하세요.');
      }
    }

    if (primaryCause == causePlanningOverload) {
      buffer.writeln('대표 원인: 계획 과부하형');
      if (hasHighCognitiveLoad) {
        buffer.writeln('오늘의 고인지 과제 후보: $taskList');
        buffer.writeln(
          '고인지 부담 일정이 2개 이상이면 이를 부드럽게 인식시킨 뒤, 전부 처리하라고 하지 말고 한 가지를 작은 첫 단계로 쪼개 부담을 낮추도록 제안하세요.',
        );
      }
      buffer.writeln('전부 처리하라고 하지 말고, 고인지 과제는 1개만 해도 충분히 멋진 성과라고 안내하세요.');
      buffer.writeln('큰 과제는 작은 첫 단계로 쪼개고, 사용자가 이미 해낸 부분을 먼저 칭찬하세요.');
    } else if (primaryCause == causeMotivationDrop) {
      buffer.writeln('대표 원인: 의욕 저하형');
      buffer.writeln(
        '완료보다 시작을 우선 성과로 인정하세요. 사용자가 진행 중으로 전환한 일이나 작게 시작한 일을 언급하면 완료를 요구하지 말고 시작 자체를 칭찬하세요.',
      );
      buffer.writeln('미룬 항목을 다시 꺼내거나 선제적으로 특정 태스크 수행을 압박하지 마세요.');
    } else if (primaryCause == causePhysicalFatigue) {
      buffer.writeln('대표 원인: 체력 부족형');
      if (hasHighCognitiveLoad) {
        buffer.writeln('오늘의 고인지 과제 후보: $taskList');
        buffer.writeln(
          '고인지 부담 일정이 2개 이상이면 이를 부드럽게 인식시킨 뒤, 전부 처리하라고 하지 말고 한 가지를 작은 첫 단계로 쪼개 부담을 낮추도록 제안하세요.',
        );
      }
      if (lightMovementTasks.isNotEmpty) {
        buffer.writeln('오늘의 가벼운 운동 후보: $movementList');
        buffer.writeln(
          '산책, 스트레칭처럼 이미 일정에 있는 가벼운 운동이 있다면 이를 최우선 회복 행동으로 추천하세요.',
        );
      } else {
        buffer.writeln('일정에 가벼운 운동이 없어도 여유 있을 때 가능한 10분 산책이나 짧은 스트레칭을 추천하세요.');
      }
      buffer.writeln(
        '충분한 수면, 수분 섭취, 이른 취침을 함께 안내하되 고강도 운동이나 고인지 과제 수행을 압박하지 마세요.',
      );
    }

    return buffer.toString();
  }

  static List<Map<String, dynamic>> _loadHistory(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString('nyang_history') ?? '[]');
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  static String? _inferPrimaryCause(
    SharedPreferences prefs,
    List<Map<String, dynamic>> history, {
    DateTime? referenceDate,
    bool includeMotivationDrop = true,
    bool includePerformanceDropMotivation = false,
  }) {
    if (_hasPhysicalFatigueSignal(prefs, referenceDate: referenceDate)) {
      return causePhysicalFatigue;
    }

    if (includePerformanceDropMotivation &&
        hasRecentPerformanceDrop(history, referenceDate: referenceDate)) {
      return causeMotivationDrop;
    }

    if (includeMotivationDrop) {
      final lowActivation = calculateLowActivationSummary(
        history,
        referenceDate: referenceDate,
      );
      if (lowActivation.hasStrongSignal) return causeMotivationDrop;
    }

    if (_hasPlanningOverloadSignal(history, referenceDate: referenceDate)) {
      return causePlanningOverload;
    }
    return null;
  }

  static bool _hasRecentLowActivationRestartSignal(
    List<Map<String, dynamic>> history,
  ) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in history) {
      final date = record['date']?.toString();
      if (date == null || date.isEmpty) continue;
      byDate[date] = record;
    }

    final base = _dateOnly(DateTime.now());
    var evaluatedDays = 0;
    var lowActivationDays = 0;
    for (var offset = 1; offset <= lowActivationWindowDays; offset++) {
      final record = byDate[_dateKey(base.subtract(Duration(days: offset)))];
      if (record == null || record['isVacation'] == true) continue;

      final totalCount = (record['totalCount'] as num?)?.toInt() ?? 0;
      if (totalCount < minTotalCount) continue;

      evaluatedDays++;
      final doneCount = (record['doneCount'] as num?)?.toInt() ?? 0;
      final completionRate = totalCount == 0 ? 0.0 : doneCount / totalCount;
      final startedCount = _startedCount(record);
      if (startedCount <= maxStartedCount &&
          completionRate <= maxCompletionRate) {
        lowActivationDays++;
      }
      if (evaluatedDays >= 2) break;
    }

    return evaluatedDays >= 2 && lowActivationDays >= 2;
  }

  static double? _completionRateForComparableDay(Map<String, dynamic>? record) {
    if (record == null || record['isVacation'] == true) return null;
    final totalCount = (record['totalCount'] as num?)?.toInt() ?? 0;
    if (totalCount < minTotalCount) return null;
    final doneCount = (record['doneCount'] as num?)?.toInt() ?? 0;
    return doneCount / totalCount;
  }

  static bool _hasPhysicalFatigueSignal(
    SharedPreferences prefs, {
    DateTime? referenceDate,
  }) {
    final base = _dateOnly(referenceDate ?? DateTime.now());
    final lateEntries =
        prefs.getStringList('nyang_physical_fatigue_late_entry_dates') ??
        <String>[];
    var lateDays = 0;
    for (var offset = 0; offset < physicalFatigueLateWindowDays; offset++) {
      final key = _dateKey(base.subtract(Duration(days: offset)));
      if (lateEntries.contains(key)) lateDays++;
    }
    if (lateDays >= physicalFatigueLateThresholdDays) return true;

    final counts = _loadStringIntMap(prefs.getString(fatigueSignalCountsKey));
    var fatigueSignals = 0;
    for (var offset = 0; offset < fatigueSignalWindowDays; offset++) {
      final key = _dateKey(base.subtract(Duration(days: offset)));
      fatigueSignals += counts[key] ?? 0;
    }
    return fatigueSignals >= fatigueSignalThresholdCount;
  }

  static bool _hasPlanningOverloadSignal(
    List<Map<String, dynamic>> history, {
    DateTime? referenceDate,
  }) {
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in history) {
      final date = record['date']?.toString();
      if (date == null || date.isEmpty) continue;
      byDate[date] = record;
    }

    final base = _dateOnly(referenceDate ?? DateTime.now());
    var evaluatedDays = 0;
    var highCognitiveCount = 0;
    var completionSum = 0.0;

    for (var offset = 1; offset <= lowActivationWindowDays; offset++) {
      final record = byDate[_dateKey(base.subtract(Duration(days: offset)))];
      if (record == null || record['isVacation'] == true) continue;
      final totalCount = (record['totalCount'] as num?)?.toInt() ?? 0;
      if (totalCount <= 0) continue;

      evaluatedDays++;
      final doneCount = (record['doneCount'] as num?)?.toInt() ?? 0;
      completionSum += doneCount / totalCount;

      final tasks = record['tasks'];
      if (tasks is List) {
        highCognitiveCount += tasks
            .whereType<Map>()
            .where(
              (task) => _isHighCognitiveText(task['text']?.toString() ?? ''),
            )
            .length;
      }
    }

    if (evaluatedDays < 3) return false;
    final averageHighCognitive = highCognitiveCount / evaluatedDays;
    final averageCompletion = completionSum / evaluatedDays;
    return averageHighCognitive >= 2.0 && averageCompletion <= 0.65;
  }

  static List<String> _todayHighCognitiveTasks(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString('nyang_tasks') ?? '[]');
      if (decoded is! List) return <String>[];
      return decoded
          .whereType<Map>()
          .map((task) => task['text']?.toString() ?? '')
          .where((text) => text.trim().isNotEmpty && _isHighCognitiveText(text))
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  static List<String> _todayOpenTaskTexts(SharedPreferences prefs) {
    try {
      final decoded = jsonDecode(prefs.getString('nyang_tasks') ?? '[]');
      if (decoded is! List) return <String>[];
      return decoded
          .whereType<Map>()
          .where((task) => task['done'] != true)
          .map((task) => (task['text']?.toString() ?? '').trim())
          .where((text) => text.isNotEmpty)
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  static String? _restartActionCandidate(List<String> tasks) {
    final candidates = tasks
        .where((task) => !_isHighCognitiveText(task))
        .where((task) => !_isLightMovementText(task))
        .toList();
    final pool = candidates.isNotEmpty ? candidates : tasks;
    if (pool.isEmpty) return null;
    pool.sort((a, b) => a.length.compareTo(b.length));
    final selected = pool.first;
    return selected.length <= 18 ? selected : '$selected의 첫 5분';
  }

  static List<String> _todayLightMovementTasks(SharedPreferences prefs) {
    final result = <String>[];
    final seen = <String>{};

    void addIfMovement(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty || seen.contains(trimmed)) return;
      if (!_isLightMovementText(trimmed)) return;
      seen.add(trimmed);
      result.add(trimmed);
    }

    try {
      final decoded = jsonDecode(prefs.getString('nyang_tasks') ?? '[]');
      if (decoded is List) {
        for (final task in decoded.whereType<Map>()) {
          addIfMovement(task['text']?.toString() ?? '');
        }
      }
    } catch (_) {}

    try {
      final todayKey = _dateKey(_dateOnly(DateTime.now()));
      final decoded = jsonDecode(prefs.getString('nyang_schedules') ?? '{}');
      if (decoded is Map) {
        final todaySchedules = decoded[todayKey];
        if (todaySchedules is List) {
          for (final schedule in todaySchedules.whereType<Map>()) {
            addIfMovement(schedule['text']?.toString() ?? '');
          }
        }
      }
    } catch (_) {}

    return result;
  }

  static bool _isHighCognitiveText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    return _highCognitiveKeywords.any(normalized.contains);
  }

  static bool _isLightMovementText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    const keywords = [
      '산책',
      '걷기',
      '걷',
      '스트레칭',
      '기지개',
      '가벼운운동',
      '가볍게운동',
      '요가',
      '필라테스',
      '마사지',
      '폼롤러',
      '어깨풀',
      '목풀',
      '허리풀',
    ];
    return keywords.any(normalized.contains);
  }

  static Map<String, int> _loadStringIntMap(String? raw) {
    if (raw == null) return <String, int>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, int>{};
      return decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          (value as num?)?.toInt() ?? int.tryParse(value.toString()) ?? 0,
        ),
      );
    } catch (_) {
      return <String, int>{};
    }
  }

  static int _startedCount(Map<String, dynamic> record) {
    final tasks = record['tasks'];
    if (tasks is! List) return (record['doneCount'] as num?)?.toInt() ?? 0;

    var count = 0;
    for (final task in tasks) {
      if (task is! Map) continue;
      final done = task['done'] == true;
      final inProgress = task['inProgress'] == true;
      final startedAt = task['startedAt']?.toString();
      if (done ||
          inProgress ||
          (startedAt != null && startedAt.trim().isNotEmpty)) {
        count++;
      }
    }
    return count;
  }

  static DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  static String _dateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
