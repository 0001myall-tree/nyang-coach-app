import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/task_resistance_event.dart';
import '../models/resistance_group_profile.dart';
import '../models/preemptive_intervention_log.dart';

class PreemptiveInterventionResult {
  final String taskId;
  final String taskText;
  final String groupId;
  final String message;
  final String coachId;

  /// 태스크에 시간(timeStart/time)이 지정돼 있었는지. true면 채팅 화면에서
  /// "지금 여유되면" 톤 대신 "일정 정리/컨디션/시간 확보" 톤 지침을 써야 한다.
  final bool isTimeSpecific;

  PreemptiveInterventionResult({
    required this.taskId,
    required this.taskText,
    required this.groupId,
    required this.message,
    required this.coachId,
    this.isTimeSpecific = false,
  });
}

// 태스크 저항 예측 시스템 저장/조회 로직.
// 설계 근거: 선제개입_저항예측_설계문서.md
//
// 그룹핑 키는 habitId(있으면) → 사전 정의 카테고리 키워드 → 정규화된 태스크텍스트 순으로
// 결정적으로 계산된다 (LLM 분류 불필요). 반복되는 습관/일정은 habitId로 정확히 묶이고,
// 일회성 태스크는 미리 정해둔 소수의 카테고리(집안일/운동/공부 등)에 걸리면 그 카테고리로,
// 안 걸리면 텍스트 일치로만 묶인다.
// (LLM 자유 태그 기반 유사도 풀링은 검토 후 제외: 실제 반복 저항은 대부분 습관/일정 재발생이라
//  habitId만으로 충분히 커버되고, 매번 자유 생성되는 태그는 분류 일관성·LLM 비용·관리 복잡도를
//  감수할 실익이 낮다고 판단. 대신 미리 정한 소수 카테고리는 키워드 사전으로 공짜에 정확하게 처리.)
class TaskResistanceService {
  static const String _eventsKey = 'nyang_resistance_events';
  static const int retentionDays = 60; // 3.4-1: λ=0.1 감쇠 기준 46일 이후 기여 거의 0, 여유있게 60일
  static const int maxEventsPerGroup = 12; // 3.4-2: 그룹당 최근 12건까지만 유지

  /// 사전 정의 카테고리 키워드 (LLM 없이, 대화에서 실제 논의된 것만 시드로 등록).
  /// 여기 안 걸리는 태스크는 그냥 카테고리 없이(habitId/텍스트 단위로만) 추적된다 — 손해는 없고
  /// 이 보너스 하나를 못 받을 뿐이다. 자주 놓치는 항목이 보이면 키워드만 추가하면 된다.
  static const Map<String, List<String>> _categoryKeywords = {
    '집안일': ['청소', '설거지', '빨래', '정리', '분리수거', '화장실', '먼지'],
    '운동': ['운동', '헬스', '조깅', '요가', '스트레칭', '산책'],
    '공부': ['공부', '독서', '강의', '시험', '과제'],
    '콘텐츠 제작': ['SNS', '숏츠', '영상', '카드뉴스', '포스팅', '블로그', '릴스', '유튜브'],
  };

  static String? _matchCategory(String taskText) {
    final lowerText = taskText.toLowerCase();
    for (final entry in _categoryKeywords.entries) {
      if (entry.value.any((keyword) => lowerText.contains(keyword.toLowerCase()))) {
        return entry.key;
      }
    }
    return null;
  }

  /// 우선순위: habitId(가장 정확) > 카테고리 키워드(관련 일회성 태스크끼리 저항 공유) > 정규화 텍스트(그대로 반복될 때만).
  static String computeGroupId({String? habitId, required String taskText}) {
    if (habitId != null && habitId.isNotEmpty) return 'habit_$habitId';
    final category = _matchCategory(taskText);
    if (category != null) return 'category_$category';
    final normalized = taskText.replaceAll(RegExp(r'\s+'), '');
    return 'text_$normalized';
  }

  static Future<List<TaskResistanceEvent>> _loadAll(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_eventsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (e) => TaskResistanceEvent.fromJson(Map<String, dynamic>.from(e)),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAll(
    SharedPreferences prefs,
    List<TaskResistanceEvent> events,
  ) async {
    await prefs.setString(
      _eventsKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  /// 3.4-1: 60일 지난 이벤트 삭제 (감쇠공식상 기여가 사실상 0이라 보관 의미 없음)
  static List<TaskResistanceEvent> _pruneExpired(
    List<TaskResistanceEvent> events,
  ) {
    final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
    return events.where((e) {
      final d = DateTime.tryParse(e.date);
      if (d == null) return true;
      return d.isAfter(cutoff);
    }).toList();
  }

  /// 3.4-2: 그룹당 최근 12건 초과분은 오래된 것부터 삭제.
  static List<TaskResistanceEvent> _enforcePerGroupCap(
    List<TaskResistanceEvent> events,
  ) {
    final byGroup = <String, List<TaskResistanceEvent>>{};
    for (final e in events) {
      byGroup.putIfAbsent(e.groupId, () => []).add(e);
    }
    final result = <TaskResistanceEvent>[];
    for (final group in byGroup.values) {
      group.sort((a, b) => a.date.compareTo(b.date)); // 오래된 순
      final overflow = group.length - maxEventsPerGroup;
      result.addAll(overflow > 0 ? group.sublist(overflow) : group);
    }
    return result;
  }

  /// 명시적 저항신호 1건 기록. 같은 taskId+date 조합이 이미 있으면 무시 (3.4-3 하루 중복 방지).
  /// 그룹 프로필(점수/신뢰도)도 같은 호출 안에서 즉시 갱신된다 — LLM 호출이 없어 동기적으로 처리 가능.
  static Future<void> recordExplicitSignal({
    required String taskId,
    required String taskText,
    required String date,
    String? habitId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var events = _pruneExpired(await _loadAll(prefs));

    final alreadyLoggedToday = events.any(
      (e) => e.taskId == taskId && e.date == date,
    );
    if (alreadyLoggedToday) return;

    final groupId = computeGroupId(habitId: habitId, taskText: taskText);

    final newEvent = TaskResistanceEvent(
      id: 'evt_${DateTime.now().millisecondsSinceEpoch}_${taskId.hashCode}',
      taskId: taskId,
      taskText: taskText,
      groupId: groupId,
      date: date,
      signalType: 'explicit',
      intensity: 1.0,
      // 신호가 발생한 시점엔 아직 완료 여부를 모름. 실제 완료 시 updateCompletionOutcome으로 갱신.
      completedEventually: false,
      totalTasksThatDay: 0,
    );
    events.add(newEvent);

    final capped = _enforcePerGroupCap(events);
    await _saveAll(prefs, capped);
    await _upsertGroupProfile(groupId, taskText, capped);
  }

  /// 사용자 메시지에서 오늘 미완료 태스크 중 언급된 게 있는지 정규화 부분일치로 판별해 기록.
  /// 기존 _normalizeRestText와 동일한 방식(공백 제거)을 써서 판정 기준을 통일한다.
  /// 태스크 목록은 직접 로드하므로 호출부는 메시지 텍스트만 넘기면 된다.
  static Future<void> detectAndRecordFromMessage(String message) async {
    final normalizedMessage = message.replaceAll(RegExp(r'\s+'), '');
    if (normalizedMessage.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks == null) return;

    List<dynamic> tasksList;
    try {
      tasksList = jsonDecode(rawTasks) as List;
    } catch (_) {
      return;
    }

    final todayTasks = tasksList.whereType<Map>().where(
      (t) =>
          t['category'] == 'today' ||
          t['category'] == 'habit' ||
          t['category'] == 'schedule',
    );
    final incompleteTasks = todayTasks.where((t) => t['done'] != true);

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    for (final task in incompleteTasks) {
      final taskText = task['text'] as String?;
      final taskId = task['id']?.toString();
      if (taskText == null || taskId == null || taskText.trim().length < 2) {
        continue; // 너무 짧은 텍스트는 오탐 위험이 커서 스킵
      }

      final normalizedTaskText = taskText.replaceAll(RegExp(r'\s+'), '');
      if (normalizedMessage.contains(normalizedTaskText)) {
        await recordExplicitSignal(
          taskId: taskId,
          taskText: taskText,
          date: today,
          habitId: task['habitId'] as String?,
        );
      }
    }
  }

  /// 태스크가 실제로 완료됐을 때, 오늘 날짜로 남아있는 저항이벤트의 결과를 갱신.
  /// [onTaskCompleted]에서 호출한다 (tasks_screen.dart `_toggleTask` 완료 처리 지점에 연결됨).
  static Future<void> updateCompletionOutcome({
    required String taskId,
    required String date,
    required int completionOrder,
    required int totalTasksThatDay,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final events = await _loadAll(prefs);

    var changed = false;
    final updated = events.map((e) {
      if (e.taskId == taskId && e.date == date && !e.completedEventually) {
        changed = true;
        return TaskResistanceEvent(
          id: e.id,
          taskId: e.taskId,
          taskText: e.taskText,
          groupId: e.groupId,
          date: e.date,
          signalType: e.signalType,
          intensity: e.intensity,
          completedEventually: true,
          completionOrder: completionOrder,
          totalTasksThatDay: totalTasksThatDay,
        );
      }
      return e;
    }).toList();

    if (changed) await _saveAll(prefs, updated);
  }

  // ── 6장 결과 관찰 & 상태머신 (폐루프) ──────────────────────────

  /// 태스크 완료 시 호출하는 진입점. 이벤트 결과 갱신 + (해당되면) 선제개입 상태머신 전이까지 처리.
  static Future<void> onTaskCompleted({
    required String taskId,
    required String date,
    required int completionOrder,
    required int totalTasksThatDay,
  }) async {
    await updateCompletionOutcome(
      taskId: taskId,
      date: date,
      completionOrder: completionOrder,
      totalTasksThatDay: totalTasksThatDay,
    );
    await _resolvePendingInterventionForTask(taskId: taskId, date: date);
  }

  /// 이 태스크에 대해 오늘 'pending' 상태인 선제개입 로그가 있으면, 저항 지속 여부를 판정해
  /// 로그 outcome을 갱신하고 6.2 상태머신을 전이시킨다. 없으면 아무것도 하지 않는다.
  ///
  /// 저항 지속 여부는 "오늘 이 태스크에 대한 저항 이벤트가 하나라도 있는가"로 판정한다.
  /// 상태머신은 "오늘도 여전히 말썽이었는가"만 알면 되므로, 개입 전/후 순서를 구분할 필요는 없다.
  static Future<void> _resolvePendingInterventionForTask({
    required String taskId,
    required String date,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await _loadPreemptiveLogs(prefs);
    final logIdx = logs.indexWhere(
      (l) => l.taskId == taskId && l.date == date && l.outcome == 'pending',
    );
    if (logIdx == -1) return;

    final events = await getAllEvents();
    final resisted = events.any((e) => e.taskId == taskId && e.date == date);
    final outcome = resisted
        ? 'resolved_high_resistance'
        : 'resolved_low_resistance';

    final log = logs[logIdx];
    logs[logIdx] = PreemptiveInterventionLog(
      id: log.id,
      groupId: log.groupId,
      taskId: log.taskId,
      date: log.date,
      message: log.message,
      coachId: log.coachId,
      outcome: outcome,
    );
    await _savePreemptiveLogs(prefs, logs);

    await _transitionInterventionMode(groupId: log.groupId, resisted: resisted);
  }

  /// 6.2 상태머신: active → tapering_test → faded, 재발 시 즉시 active 복귀.
  static Future<void> _transitionInterventionMode({
    required String groupId,
    required bool resisted,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _loadGroupProfiles(prefs);
    final idx = profiles.indexWhere((g) => g.groupId == groupId);
    if (idx == -1) return;
    final g = profiles[idx];

    var newMode = g.interventionMode;
    var newCount = g.consecutiveSuccessCount;
    var newTaperingConsumed = g.taperingTestConsumed;

    switch (g.interventionMode) {
      case 'active':
        if (!resisted) {
          newCount++;
          if (newCount >= 3) {
            newMode = 'tapering_test';
            newCount = 0;
            newTaperingConsumed = false;
          }
        } else {
          newCount = 0;
        }
        break;
      case 'tapering_test':
        newMode = resisted ? 'active' : 'faded';
        newCount = 0;
        newTaperingConsumed = false;
        break;
      case 'faded':
        if (resisted) {
          newMode = 'active';
          newCount = 0;
        }
        break;
    }

    profiles[idx] = ResistanceGroupProfile(
      groupId: g.groupId,
      sampleText: g.sampleText,
      // resistanceScore/confidence는 4장 공식(raw 신호)으로만 갱신됨 — 여기서 건드리지 않음 (6.1 원칙)
      resistanceScore: g.resistanceScore,
      confidence: g.confidence,
      interventionMode: newMode,
      consecutiveSuccessCount: newCount,
      taperingTestConsumed: newTaperingConsumed,
      lastUpdated: g.lastUpdated,
      eventCount: g.eventCount,
    );
    await _saveGroupProfiles(prefs, profiles);
  }

  static Future<List<TaskResistanceEvent>> getAllEvents() async {
    final prefs = await SharedPreferences.getInstance();
    return _pruneExpired(await _loadAll(prefs));
  }

  // ── 4.1 저항점수/신뢰도 계산 ─────────────────────────────────

  static const String _groupsKey = 'nyang_resistance_groups';
  static const int maxActiveGroups = 5; // 3.2
  static const double _lambda = 0.1; // 4.1 감쇠상수
  static const double _confidenceK = 10.0; // 4.1 신뢰도 기준 누적가중치

  static Future<List<ResistanceGroupProfile>> _loadGroupProfiles(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_groupsKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (e) => ResistanceGroupProfile.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveGroupProfiles(
    SharedPreferences prefs,
    List<ResistanceGroupProfile> profiles,
  ) async {
    await prefs.setString(
      _groupsKey,
      jsonEncode(profiles.map((g) => g.toJson()).toList()),
    );
  }

  /// 3.2: 그룹 프로필 갱신. 활성 그룹 5개 캡 도달 시, 신규 후보 점수가
  /// 현재 최하위 슬롯보다 높을 때만 교체한다.
  static Future<void> _upsertGroupProfile(
    String groupId,
    String sampleText,
    List<TaskResistanceEvent> allEvents,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    var profiles = await _loadGroupProfiles(prefs);

    final matchingEvents = allEvents
        .where((e) => e.groupId == groupId)
        .toList();
    final score = _computeResistScore(matchingEvents);
    final confidence = _computeConfidence(matchingEvents);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final existingIdx = profiles.indexWhere((g) => g.groupId == groupId);
    if (existingIdx != -1) {
      final existing = profiles[existingIdx];
      profiles[existingIdx] = ResistanceGroupProfile(
        groupId: groupId,
        sampleText: sampleText,
        resistanceScore: score,
        confidence: confidence,
        interventionMode: existing.interventionMode,
        consecutiveSuccessCount: existing.consecutiveSuccessCount,
        taperingTestConsumed: existing.taperingTestConsumed,
        lastUpdated: today,
        eventCount: matchingEvents.length,
      );
      await _saveGroupProfiles(prefs, profiles);
      return;
    }

    final candidate = ResistanceGroupProfile(
      groupId: groupId,
      sampleText: sampleText,
      resistanceScore: score,
      confidence: confidence,
      lastUpdated: today,
      eventCount: matchingEvents.length,
    );

    if (profiles.length < maxActiveGroups) {
      profiles.add(candidate);
      await _saveGroupProfiles(prefs, profiles);
      return;
    }

    profiles.sort((a, b) => a.resistanceScore.compareTo(b.resistanceScore));
    if (candidate.resistanceScore > profiles.first.resistanceScore) {
      profiles[0] = candidate;
      await _saveGroupProfiles(prefs, profiles);
    }
    // 넘지 못하면 활성 목록엔 안 들어감. 원본 이벤트(3.1)엔 groupId가 이미 붙어있어
    // 나중에 다시 문제되면 재계산으로 복귀 가능 (3.2 참고).
  }

  static double _computeResistScore(List<TaskResistanceEvent> events) {
    if (events.isEmpty) return 0.0;
    final now = DateTime.now();
    double weightedSum = 0.0;
    double weightTotal = 0.0;
    for (final e in events) {
      final d = DateTime.tryParse(e.date);
      final daysSince = d == null ? 0 : now.difference(d).inDays;
      final wRecency = exp(-_lambda * daysSince);
      final wType = e.signalType == 'explicit' ? 1.0 : 0.4;
      weightedSum += wRecency * wType;
      weightTotal += wType;
    }
    return weightTotal == 0 ? 0.0 : weightedSum / weightTotal;
  }

  static double _computeConfidence(List<TaskResistanceEvent> events) {
    double weightTotal = 0.0;
    for (final e in events) {
      weightTotal += e.signalType == 'explicit' ? 1.0 : 0.4;
    }
    return (weightTotal / _confidenceK).clamp(0.0, 1.0);
  }

  static Future<List<ResistanceGroupProfile>> getActiveGroupProfiles() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadGroupProfiles(prefs);
  }

  // ── 5장 개입 판단 & 쿨다운, 선제 메시지 생성 ──────────────────────

  static const double _floor = 0.5; // 5.1: 바닥값, 이 밑이면 그날은 개입 후보 없음
  static const double _minConfidence = 0.3; // 4.1: 신뢰도 낮으면 점수 높아도 보류
  static const String _preemptiveLogKey = 'nyang_preemptive_log';

  /// 오늘 선제개입할 그룹+태스크가 있는지 판단만 한다 (로그 기록 없음, 순수 조회).
  /// 하루 안에서 여러 턴에 걸쳐 반복 호출될 수 있으므로, 실제로 코치가 화제를 꺼낸 게
  /// 확인됐을 때만 [confirmPreemptiveIntervention]을 별도로 호출해 그날의 기회를 소진시킨다.
  static Future<PreemptiveInterventionResult?> findPreemptiveInterventionTarget({
    required String coachId,
  }) async {
    if (await _isVacationMode()) return null; // 번아웃 휴식모드와 충돌 방지 (5장)
    if (await _hasAnyPreemptiveLogToday()) return null; // 하루 최대 1회 (전역, 그룹 무관)

    final prefs = await SharedPreferences.getInstance();
    final profiles = await _loadGroupProfiles(prefs);

    // 5.1: 바닥값 + 신뢰도를 넘는 후보 중 최고점 하나만
    final candidates = profiles
        .where((g) => g.resistanceScore >= _floor && g.confidence >= _minConfidence)
        .toList();
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.resistanceScore.compareTo(a.resistanceScore));
    final target = candidates.first;

    final cooldownDays = _cooldownDaysFor(target.interventionMode);
    if (await _hasRecentPreemptiveLog(target.groupId, withinDays: cooldownDays)) {
      return null;
    }

    // tapering_test: 이번 회차는 개입을 건너뛰고 결과만 관찰 (6.2 상태머신 입력용)
    if (target.interventionMode == 'tapering_test' &&
        !target.taperingTestConsumed) {
      await _markTaperingTestConsumed(target.groupId);
      return null;
    }

    final matchedTask = await _findMatchingTodayTask(target.groupId);
    if (matchedTask == null) return null; // 오늘 이 그룹에 해당하는 태스크가 없으면 개입 안 함

    final taskText = matchedTask['text'] as String;
    final taskId = matchedTask['id'].toString();

    // 시간 지정형이면, 대화 중 자연스러운 체크인도 시간 지정형 체크인과 동일한 창(시작
    // 30분 전~5분 후)에서만 발동하고 톤도 다르게 쓴다. 창 밖이면 이번 턴엔 발동 안 함.
    final scheduledTime = _parseTaskTime(matchedTask);
    final isTimeSpecific = scheduledTime != null;
    if (isTimeSpecific) {
      final now = DateTime.now();
      final windowStart = scheduledTime.subtract(
        const Duration(minutes: _scheduledCheckInLeadMinutes),
      );
      final windowEnd = scheduledTime.add(
        const Duration(minutes: _scheduledCheckInGraceMinutes),
      );
      if (now.isBefore(windowStart) || now.isAfter(windowEnd)) return null;
    }

    final message = isTimeSpecific
        ? _generateScheduledCheckInMessage(taskText)
        : _generatePreemptiveMessage(coachId, taskText);

    return PreemptiveInterventionResult(
      taskId: taskId,
      taskText: taskText,
      groupId: target.groupId,
      message: message,
      coachId: coachId,
      isTimeSpecific: isTimeSpecific,
    );
  }

  /// 태스크의 timeStart(우선)/time 필드를 오늘 날짜 기준 DateTime으로 파싱. 없거나 "HH:mm" 형식이
  /// 아니면 null (시간 미정형으로 취급).
  static DateTime? _parseTaskTime(Map task) {
    final timeStr = (task['timeStart'] as String?) ?? (task['time'] as String?);
    if (timeStr == null) return null;
    final parts = timeStr.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 코치의 실제 응답 텍스트에 대상 태스크가 언급됐는지 정규화 부분일치로 확인하고,
  /// 언급됐을 때만 로그를 남겨 그날의 선제개입 기회를 소진시킨다.
  /// 언급 안 됐으면 아무것도 하지 않으며, 같은 날 다른 턴에서 다시 시도될 수 있다.
  static Future<bool> confirmPreemptiveIntervention({
    required PreemptiveInterventionResult target,
    required String responseText,
  }) async {
    final normalizedResponse = responseText.replaceAll(RegExp(r'\s+'), '');
    final normalizedTaskText = target.taskText.replaceAll(RegExp(r'\s+'), '');
    if (normalizedTaskText.isEmpty ||
        !normalizedResponse.contains(normalizedTaskText)) {
      return false;
    }

    await _logPreemptiveIntervention(
      groupId: target.groupId,
      taskId: target.taskId,
      message: target.message,
      coachId: target.coachId,
    );
    return true;
  }

  static Future<bool> _isVacationMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('nyang_vacation') != null;
  }

  /// 그룹별 재개입 쿨다운. active/tapering_test는 근거 없는 임의 대기시간을 두지 않고
  /// 전역 1일 1회 캡에만 맡긴다. faded만 "3회 연속 성공"이라는 근거가 있으므로 쿨다운을 둔다.
  static int _cooldownDaysFor(String interventionMode) {
    return interventionMode == 'faded' ? 5 : 0;
  }

  /// 오늘 날짜로 이미 선제개입 로그가 하나라도 있으면 true (그룹 무관, 전역 1일 1회 제한).
  /// 로그는 코치가 실제로 화제를 꺼낸 게 확인됐을 때만 기록되므로([confirmPreemptiveIntervention]),
  /// 이 체크는 "오늘 이미 실제로 성공한 적이 있는가"를 의미한다.
  static Future<bool> _hasAnyPreemptiveLogToday() async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await _loadPreemptiveLogs(prefs);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return logs.any((l) => l.date == today);
  }

  /// 대상 그룹과 같은 groupId를 갖는 오늘의 미완료 태스크를 찾는다.
  /// habitId가 같으면 무조건 일치, 아니면 정규화된 텍스트가 완전히 같아야 일치한다.
  /// 선례 없는 완전히 새로운 문구의 일회성 태스크는 매칭되지 않아 개입 대상에서 자연히 제외된다.
  static Future<Map<String, dynamic>?> _findMatchingTodayTask(
    String targetGroupId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks == null) return null;

    List<dynamic> tasksList;
    try {
      tasksList = jsonDecode(rawTasks) as List;
    } catch (_) {
      return null;
    }

    // done이 아니어도 이미 진행 중(inProgress)인 태스크는 제외 — 사용자가 이미 시작한 일에
    // "언제 하실 생각이세요?"라고 묻는 건 어색하다.
    final eligibleTasks = tasksList.whereType<Map>().where(
      (t) =>
          (t['category'] == 'today' ||
              t['category'] == 'habit' ||
              t['category'] == 'schedule') &&
          t['done'] != true &&
          t['inProgress'] != true,
    );

    for (final task in eligibleTasks) {
      final text = task['text'] as String?;
      if (text == null || text.trim().isEmpty) continue;
      final groupId = computeGroupId(
        habitId: task['habitId'] as String?,
        taskText: text,
      );
      if (groupId == targetGroupId) return Map<String, dynamic>.from(task);
    }
    return null;
  }

  static String _generatePreemptiveMessage(String coachId, String taskText) {
    // 기존 _restOfferMessage()/_vacationActivatedMessage() 패턴 재사용 (페르소나별 하드코딩, LLM 호출 없음)
    return switch (coachId) {
      'boyfriend' => '오늘 $taskText 있던데, 언제쯤 할 생각이야? 괜찮아?',
      'girlfriend' => '오빠, 오늘 $taskText 있던데 언제쯤 할 생각이야? 괜찮아? 🩷',
      'halmae' => '우리 새끼, 오늘 $taskText 있던데 언제쯤 할 생각이니?',
      'bro' => '야, 오늘 $taskText 있던데 언제 할 거냐?',
      'sec_male' => '오늘 $taskText 일정이 있으신데, 언제쯤 진행하실 계획이신가요?',
      'sec_female' => '대표님, 오늘 $taskText 있으신데 언제쯤 하실 생각이세요?',
      _ => '오늘 $taskText 있는데 언제쯤 하실 생각이세요?',
    };
  }

  static Future<List<PreemptiveInterventionLog>> _loadPreemptiveLogs(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_preemptiveLogKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .whereType<Map>()
          .map(
            (e) => PreemptiveInterventionLog.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _savePreemptiveLogs(
    SharedPreferences prefs,
    List<PreemptiveInterventionLog> logs,
  ) async {
    await prefs.setString(
      _preemptiveLogKey,
      jsonEncode(logs.map((l) => l.toJson()).toList()),
    );
  }

  static Future<bool> _hasRecentPreemptiveLog(
    String groupId, {
    required int withinDays,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await _loadPreemptiveLogs(prefs);
    final cutoff = DateTime.now().subtract(Duration(days: withinDays));
    return logs.any((l) {
      if (l.groupId != groupId) return false;
      final d = DateTime.tryParse(l.date);
      if (d == null) return false;
      return d.isAfter(cutoff);
    });
  }

  static Future<void> _logPreemptiveIntervention({
    required String groupId,
    required String taskId,
    required String message,
    required String coachId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final logs = await _loadPreemptiveLogs(prefs);
    logs.add(
      PreemptiveInterventionLog(
        id: 'pi_${DateTime.now().millisecondsSinceEpoch}',
        groupId: groupId,
        taskId: taskId,
        date: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        message: message,
        coachId: coachId,
      ),
    );
    await _savePreemptiveLogs(prefs, logs);
  }

  static Future<void> _markTaperingTestConsumed(String groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final profiles = await _loadGroupProfiles(prefs);
    final idx = profiles.indexWhere((g) => g.groupId == groupId);
    if (idx == -1) return;
    final g = profiles[idx];
    profiles[idx] = ResistanceGroupProfile(
      groupId: g.groupId,
      sampleText: g.sampleText,
      resistanceScore: g.resistanceScore,
      confidence: g.confidence,
      interventionMode: g.interventionMode,
      consecutiveSuccessCount: g.consecutiveSuccessCount,
      taperingTestConsumed: true,
      lastUpdated: g.lastUpdated,
      eventCount: g.eventCount,
    );
    await _saveGroupProfiles(prefs, profiles);
  }

  // ── 시간 지정형 선제 체크인 (마스터 전용, 배지 알림) ────────────────
  // 대화형 선제개입(findPreemptiveInterventionTarget)과 별개의 독립 예산으로 동작한다.
  // 마스터 코치 채팅 화면에 있지 않아도(코치선택/프렌즈 코치 화면) 놓치지 않도록,
  // 시작 30분 전~5분 후 창에서 정적 문구를 바로 채팅 기록에 심어두고 배지로 알린다.
  // LLM 호출이 없어 "생략될 위험" 자체가 없다 — 창에 들어오면 반드시 메시지가 있다.

  static const int _scheduledCheckInLeadMinutes = 30;
  static const int _scheduledCheckInGraceMinutes = 5;
  static const String _scheduledCheckInDeliveredKey =
      'nyang_scheduled_checkin_delivered';
  static const String _scheduledCheckInUnreadKey =
      'nyang_scheduled_checkin_unread';

  static Future<void> checkForScheduledCheckIn({
    required String masterCoachId,
  }) async {
    if (await _isVacationMode()) return;

    final prefs = await SharedPreferences.getInstance();
    final profiles = await _loadGroupProfiles(prefs);
    final candidates = profiles
        .where(
          (g) => g.resistanceScore >= _floor && g.confidence >= _minConfidence,
        )
        .toList();
    if (candidates.isEmpty) return;
    candidates.sort((a, b) => b.resistanceScore.compareTo(a.resistanceScore));

    final rawTasks = prefs.getString('nyang_tasks');
    if (rawTasks == null) return;
    List<dynamic> tasksList;
    try {
      tasksList = jsonDecode(rawTasks) as List;
    } catch (_) {
      return;
    }

    final now = DateTime.now();
    final eligibleTasks = tasksList.whereType<Map>().where(
      (t) =>
          (t['category'] == 'today' ||
              t['category'] == 'habit' ||
              t['category'] == 'schedule') &&
          t['done'] != true &&
          t['inProgress'] != true,
    );

    for (final group in candidates) {
      // 같은 그룹을 대화형 선제개입과 이중으로 찌르지 않도록 쿨다운을 공유한다.
      final cooldownDays = _cooldownDaysFor(group.interventionMode);
      if (await _hasRecentPreemptiveLog(
        group.groupId,
        withinDays: cooldownDays,
      )) {
        continue;
      }

      for (final task in eligibleTasks) {
        final text = task['text'] as String?;
        final taskId = task['id']?.toString();
        if (text == null || text.trim().isEmpty || taskId == null) continue;

        final groupId = computeGroupId(
          habitId: task['habitId'] as String?,
          taskText: text,
        );
        if (groupId != group.groupId) continue;

        final scheduled = _parseTaskTime(task);
        if (scheduled == null) continue; // 시간 미정형은 이 기능 대상 아님
        final windowStart = scheduled.subtract(
          const Duration(minutes: _scheduledCheckInLeadMinutes),
        );
        final windowEnd = scheduled.add(
          const Duration(minutes: _scheduledCheckInGraceMinutes),
        );
        if (now.isBefore(windowStart) || now.isAfter(windowEnd)) continue;

        final fireKey = '${taskId}_${DateFormat('yyyy-MM-dd').format(now)}';
        final delivered =
            prefs.getStringList(_scheduledCheckInDeliveredKey) ?? [];
        if (delivered.contains(fireKey)) continue;

        final message = _generateScheduledCheckInMessage(text);
        await _appendStaticMessageToCoachHistory(masterCoachId, message);

        delivered.add(fireKey);
        await prefs.setStringList(_scheduledCheckInDeliveredKey, delivered);
        await prefs.setString(
          _scheduledCheckInUnreadKey,
          jsonEncode({
            'taskId': taskId,
            'coachId': masterCoachId,
            'fireKey': fireKey,
          }),
        );

        await _logPreemptiveIntervention(
          groupId: group.groupId,
          taskId: taskId,
          message: message,
          coachId: masterCoachId,
        );
        return; // 한 번 전달했으면 이번 체크는 종료
      }
    }
  }

  static String _generateScheduledCheckInMessage(String taskText) {
    final templates = [
      '대표님, 이따 $taskText 있으신데 다른 일정은 정리되고 계세요?',
      '대표님, $taskText 앞두고 계신데 컨디션은 괜찮으세요?',
      '대표님, 이따 시간 확보는 괜찮으신가요? $taskText 일정이 있으셔서요.',
    ];
    return templates[Random().nextInt(templates.length)];
  }

  /// LLM 호출 없이, 지정된 코치의 채팅 기록에 코치 발화를 직접 추가한다.
  /// 저장 스키마는 ChatMessage.toJson()과 동일하게 맞춘다 (text/isUser/time).
  static Future<void> _appendStaticMessageToCoachHistory(
    String coachId,
    String message,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'nyang_chat_history_$coachId';
    final raw = prefs.getString(key);
    List<dynamic> history = [];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) history = decoded;
      } catch (_) {}
    }
    history.add({
      'text': message,
      'isUser': false,
      'time': DateTime.now().toIso8601String(),
    });
    final trimmed = history.length > 100
        ? history.sublist(history.length - 100)
        : history;
    await prefs.setString(key, jsonEncode(trimmed));
  }

  /// 배지를 띄울지 여부.
  static Future<bool> hasUnreadScheduledCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_scheduledCheckInUnreadKey) != null;
  }

  /// 배지를 눌러 확인 처리하고, 이동할 코치 id를 반환한다 (없으면 null).
  static Future<String?> consumeUnreadScheduledCheckIn() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scheduledCheckInUnreadKey);
    if (raw == null) return null;
    await prefs.remove(_scheduledCheckInUnreadKey);
    try {
      final decoded = jsonDecode(raw) as Map;
      return decoded['coachId'] as String?;
    } catch (_) {
      return null;
    }
  }
}
