import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/user_title_service.dart';
import 'package:nyang_coach/services/analytics_service.dart';
import 'package:nyang_coach/services/api_usage_limit_service.dart';
import 'coach_config.dart';
import 'tasks_screen.dart'; // for HabitItem, etc.

class RecordsScreen extends StatefulWidget {
  final String coachId;
  const RecordsScreen({super.key, required this.coachId});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _history = [];
  Map<String, Map<String, dynamic>> _habitLogs = {};
  List<HabitItem> _habits = [];
  Map<String, dynamic>? _vacationInfo;
  String _userTitle = UserTitleService.defaultTitle;
  String? _weeklyFeedbackText;
  bool _isGeneratingWeeklyFeedback = false;
  String _lastDate = '';
  final HttpsCallable _chatProxy = FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable('chatProxy');

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. History (nyang_history)
    final rawHistory = prefs.getString('nyang_history');
    if (rawHistory != null) {
      final List decoded = jsonDecode(rawHistory);
      _history = decoded.cast<Map<String, dynamic>>();
    }

    // 2. Habits
    final rawHabits = prefs.getString('nyang_habits');
    if (rawHabits != null) {
      final List decoded = jsonDecode(rawHabits);
      _habits = decoded.map((e) => HabitItem.fromJson(e)).toList();
    }

    // 3. Habit Logs
    final rawLogs = prefs.getString('nyang_habit_logs');
    if (rawLogs != null) {
      final Map decoded = jsonDecode(rawLogs);
      _habitLogs = decoded.map(
        (k, v) => MapEntry(
          k.toString(),
          (v as Map).map((k2, v2) => MapEntry(k2.toString(), v2)),
        ),
      );
    }

    // 4. Vacation
    final rawVacation = prefs.getString('nyang_vacation');
    if (rawVacation != null) {
      _vacationInfo = jsonDecode(rawVacation);
    }

    _userTitle = await UserTitleService.getTitle();
    _lastDate = prefs.getString('nyang_last_date') ?? '';
    if (_lastDate.isEmpty) {
      final n = DateTime.now();
      var base = DateTime(n.year, n.month, n.day);
      if (n.hour < 3) {
        base = base.subtract(const Duration(days: 1));
      }
      _lastDate =
          '${base.year}-${base.month.toString().padLeft(2, '0')}-${base.day.toString().padLeft(2, '0')}';
    }

    setState(() => _isLoading = false);
    if (_isMaster) {
      _loadOrGenerateWeeklyFeedback();
    }
  }

  bool get _isMaster =>
      widget.coachId == 'sec_male' || widget.coachId == 'sec_female';
  CoachConfig get _coach => CoachConfigs.get(widget.coachId);

  // ── 최근 7일(또는 30일) 데이터 계산 ─────────────────────
  List<Map<String, dynamic>> _getLast7Records() {
    final baseDateParts = _lastDate.split('-');
    DateTime baseDate;
    if (baseDateParts.length >= 3) {
      final y = int.tryParse(baseDateParts[0]) ?? DateTime.now().year;
      final m = int.tryParse(baseDateParts[1]) ?? DateTime.now().month;
      final d = int.tryParse(baseDateParts[2]) ?? DateTime.now().day;
      baseDate = DateTime(y, m, d);
    } else {
      final n = DateTime.now();
      baseDate = DateTime(n.year, n.month, n.day);
      if (n.hour < 3) {
        baseDate = baseDate.subtract(const Duration(days: 1));
      }
    }

    final List<Map<String, dynamic>> last7 = [];
    for (int i = 6; i >= 0; i--) {
      final d = baseDate.subtract(Duration(days: i));
      final dateStr =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

      // history에서 찾기
      final existing = _history.where((r) => r['date'] == dateStr).toList();
      if (existing.isNotEmpty) {
        final record = Map<String, dynamic>.from(existing.last);
        record['isVacation'] = _isVacationDate(dateStr);
        last7.add(record);
      } else {
        // 기록이 없으면 빈 데이터
        last7.add({
          'date': dateStr,
          'totalCount': 0,
          'doneCount': 0,
          'success': false,
          'isVacation': _isVacationDate(dateStr),
          'tasks': [],
        });
      }
    }
    return last7;
  }

  String _getWeekMondayStr() {
    final baseDateParts = _lastDate.split('-');
    DateTime baseDate;
    if (baseDateParts.length >= 3) {
      final y = int.tryParse(baseDateParts[0]) ?? DateTime.now().year;
      final m = int.tryParse(baseDateParts[1]) ?? DateTime.now().month;
      final d = int.tryParse(baseDateParts[2]) ?? DateTime.now().day;
      baseDate = DateTime(y, m, d);
    } else {
      final n = DateTime.now();
      baseDate = DateTime(n.year, n.month, n.day);
      if (n.hour < 3) {
        baseDate = baseDate.subtract(const Duration(days: 1));
      }
    }
    final monday = baseDate.subtract(Duration(days: baseDate.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _visibleRecordTasks(Map<String, dynamic> record) {
    final rawTasks = (record['tasks'] as List?) ?? [];
    return rawTasks
        .whereType<Map>()
        .map((task) => Map<String, dynamic>.from(task))
        .where((task) => task['deferred'] != true)
        .toList();
  }

  int _recordTotalCount(Map<String, dynamic> record) {
    final visibleTasks = _visibleRecordTasks(record);
    if (visibleTasks.isNotEmpty) return visibleTasks.length;
    return (record['totalCount'] as num?)?.toInt() ?? 0;
  }

  int _recordDoneCount(Map<String, dynamic> record) {
    final visibleTasks = _visibleRecordTasks(record);
    if (visibleTasks.isNotEmpty) {
      return visibleTasks.where((task) => task['done'] == true).length;
    }
    return (record['doneCount'] as num?)?.toInt() ?? 0;
  }

  int _selectFeedbackType(SharedPreferences prefs, String weekMonday) {
    final thisMonday = DateTime.parse(weekMonday);
    final lastWeekMonday = thisMonday.subtract(const Duration(days: 7));
    final twoWeeksAgoMonday = thisMonday.subtract(const Duration(days: 14));

    String fmt(DateTime d) =>
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

    final usedTypes = <int>{};
    try {
      final d1 = prefs.getString('nyang_coach_weekly_feedback_sec_male');
      if (d1 != null) {
        final m = jsonDecode(d1) as Map<String, dynamic>;
        if (m['weekMonday'] == fmt(lastWeekMonday) && m['type'] != null) {
          usedTypes.add(m['type'] as int);
        }
      }
      final d2 = prefs.getString('nyang_feedback_prev_week');
      if (d2 != null) {
        final m = jsonDecode(d2) as Map<String, dynamic>;
        if (m['weekMonday'] == fmt(twoWeeksAgoMonday) && m['type'] != null) {
          usedTypes.add(m['type'] as int);
        }
      }
    } catch (_) {}

    final available = [0, 1, 2].where((t) => !usedTypes.contains(t)).toList()
      ..shuffle();
    return available.first;
  }

  Future<void> _loadOrGenerateWeeklyFeedback() async {
    if (_isGeneratingWeeklyFeedback) return;
    final prefs = await SharedPreferences.getInstance();
    final weekMonday = _getWeekMondayStr();
    final cacheKey = 'nyang_coach_weekly_feedback_sec_male';
    final cachedData = prefs.getString(cacheKey);

    try {
      if (cachedData != null) {
        final cached = jsonDecode(cachedData) as Map<String, dynamic>;
        if (cached['weekMonday'] == weekMonday &&
            (cached['text'] as String?)?.trim().isNotEmpty == true) {
          if (!mounted) return;
          setState(() {
            _weeklyFeedbackText = cached['text'] as String;
          });
          return;
        }
      }
    } catch (_) {}

    final feedbackType = _selectFeedbackType(prefs, weekMonday);
    await _triggerWeeklyFeedback(weekMonday, cacheKey, feedbackType);
  }

  Future<void> _triggerWeeklyFeedback(
    String weekMonday,
    String cacheKey,
    int feedbackType,
  ) async {
    if (_isGeneratingWeeklyFeedback) return;
    _isGeneratingWeeklyFeedback = true;
    if (mounted) {
      setState(() {
        _weeklyFeedbackText = null;
      });
    }

    try {
      final prompt = await _buildWeeklyFeedbackPrompt(feedbackType);
      final estimatedPromptTokens = AnalyticsService.estimateChatTokens([
        {'content': prompt},
      ], '');
      final limit = await ApiUsageLimitService.checkChatAllowance(
        estimatedTokens: estimatedPromptTokens,
      );
      if (!limit.allowed) {
        if (mounted) {
          setState(() {
            _weeklyFeedbackText = limit.message;
          });
        }
        return;
      }

      final response = await _chatProxy.call({
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.5,
      });
      final feedbackText = (response.data['content'] as String? ?? '')
          .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
          .replaceAll(RegExp(r'\*(.*?)\*'), r'$1')
          .replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '')
          .trim();

      if (feedbackText.isEmpty) return;

      // API 사용 기록 (주간 리포트 생성에 따른 토큰/비용 집계)
      final estimatedTokens = AnalyticsService.estimateChatTokens([
        {'content': prompt},
      ], feedbackText);
      final usageData = response.data is Map ? response.data as Map : const {};
      final actualTokens = AnalyticsService.readIntValue(usageData, [
        'totalTokens',
        'total_tokens',
        'tokens',
        'usage.totalTokens',
        'usage.total_tokens',
      ]);
      final actualCostWon = AnalyticsService.readIntValue(usageData, [
        'costWon',
        'cost_won',
        'estimatedCostWon',
        'estimated_cost_won',
        'usage.costWon',
      ]);

      AnalyticsService.logApiUsage(
        coachId: widget.coachId,
        estimatedTokens: estimatedTokens,
        actualTokens: actualTokens,
        actualCostWon: actualCostWon,
        usageSource: 'weekly_feedback',
        countAsUserUsage: false,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'weekMonday': weekMonday,
          'text': feedbackText,
          'type': feedbackType,
        }),
      );
      await prefs.setString(
        'nyang_feedback_prev_week',
        jsonEncode({'weekMonday': weekMonday, 'type': feedbackType}),
      );

      if (!mounted) return;
      setState(() {
        _weeklyFeedbackText = feedbackText;
      });
    } catch (e) {
      debugPrint('주간 코치 피드백 생성 실패: $e');
      if (!mounted) return;
      setState(() {
        _weeklyFeedbackText = _getMasterPatternFeedback(_getLast7Records());
      });
    } finally {
      _isGeneratingWeeklyFeedback = false;
    }
  }

  Future<String> _buildWeeklyFeedbackPrompt(int feedbackType) async {
    final prefs = await SharedPreferences.getInstance();
    final records = _getLast7Records();
    final visibleVisions = _formatVisionText(prefs.getString('nyang_visions'));
    final weekGoalText = _formatGoalText(prefs.getString('nyang_week_goals'));
    final monthGoalText = _formatGoalText(prefs.getString('nyang_month_goals'));

    final allTaskTexts = <String>{};
    for (final record in records) {
      if (record['isVacation'] == true) continue;
      final tasks = (record['tasks'] as List?) ?? [];
      for (final task in tasks) {
        final text = (task as Map?)?['text']?.toString().trim();
        if (text != null && text.isNotEmpty) allTaskTexts.add(text);
      }
    }

    final resumedTasks = <String>[];
    final consistentTasks = <String>[];
    for (final text in allTaskTexts) {
      final dailyStatus = records
          .where((record) => record['isVacation'] != true)
          .map((record) {
            final tasks = (record['tasks'] as List?) ?? [];
            return tasks.any((task) {
              final map = task as Map?;
              return map?['text'] == text && map?['done'] == true;
            });
          })
          .toList();

      if (dailyStatus.length >= 7 &&
          dailyStatus[4] &&
          dailyStatus[5] &&
          dailyStatus[6]) {
        consistentTasks.add(text);
      }

      var currentFalseStreak = 0;
      var doneAfterFalse = false;
      for (final done in dailyStatus) {
        if (!done) {
          currentFalseStreak++;
        } else {
          if (currentFalseStreak >= 3) doneAfterFalse = true;
          currentFalseStreak = 0;
        }
      }
      if (doneAfterFalse && !consistentTasks.contains(text)) {
        resumedTasks.add(text);
      }
    }

    final recordBuffer = StringBuffer();
    for (final record in records) {
      if (record['isVacation'] == true) {
        recordBuffer.writeln(
          '- ${record['date']}: 휴무일(회복일)로 설정됨. 완료/미완료 평가에서 제외.',
        );
        continue;
      }

      final tasks = (record['tasks'] as List?) ?? [];
      final done = tasks
          .where((task) => (task as Map?)?['done'] == true)
          .map((task) => (task as Map)['text'].toString())
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      final undone = tasks
          .where((task) => (task as Map?)?['done'] != true)
          .map((task) {
            final map = task as Map;
            final isDeferred = map['deferred'] == true;
            return map['text'].toString() + (isDeferred ? ' (다른 날로 이월함)' : '');
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      recordBuffer.writeln(
        '- ${record['date']}: 완료한 일[${done.isEmpty ? '없음' : done}], 완료하지 못한 일[${undone.isEmpty ? '없음' : undone}]',
      );
    }

    final isMale = widget.coachId == 'sec_male' || _isMaster;
    final title = _userTitle;

    final trackingHabits = _habits.where((h) => h.tracking == true).toList();
    final habitFreqBuffer = StringBuffer();
    if (trackingHabits.isEmpty) {
      habitFreqBuffer.writeln('설정된 습관 없음');
    } else {
      const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
      for (final h in trackingHabits) {
        final freqLabel = h.freq == 'daily'
            ? '매일'
            : h.days.map((d) => dayNames[d]).join(', ');
        habitFreqBuffer.writeln('- ${h.name}: $freqLabel');
      }
    }

    // 장기 비전형 작성을 위한 마일스톤 상세 데이터
    List<VisionItem> visionItems = [];
    try {
      final visionsRaw = prefs.getString('nyang_visions');
      if (visionsRaw != null) {
        visionItems = (jsonDecode(visionsRaw) as List)
            .map((e) => VisionItem.fromJson(e))
            .toList();
      }
    } catch (_) {}

    DateTime? parseDotDate(String? s) {
      if (s == null || s.isEmpty) return null;
      final parts = s.split('.');
      if (parts.length != 3) return null;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) return null;
      return DateTime(y, m, d);
    }

    final weekStart =
        DateTime.tryParse(records.first['date']) ?? DateTime.now();
    final weekEnd = DateTime.tryParse(records.last['date']) ?? DateTime.now();
    final todayNormalized = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );

    final completedThisWeekMilestones = <String>[];
    final recentlyUpdatedVisionNotes = <String>[];
    final overdueMilestones = <String>[];
    String? nearestUpcomingLabel;
    DateTime? nearestUpcomingDate;

    for (final v in visionItems) {
      final updatedAt = DateTime.tryParse(v.updatedAt);
      if (updatedAt != null &&
          !updatedAt.isBefore(weekStart) &&
          !updatedAt.isAfter(weekEnd.add(const Duration(days: 1)))) {
        final memoedMilestone = v.milestones.where(
          (m) =>
              (m.memo?.isNotEmpty ?? false) ||
              (m.memoSections?.isNotEmpty ?? false),
        );
        if (memoedMilestone.isNotEmpty) {
          recentlyUpdatedVisionNotes.add(
            '${v.name} - "${memoedMilestone.first.text}" 관련 메모 추가/수정됨',
          );
        } else {
          recentlyUpdatedVisionNotes.add('${v.name} 비전이 최근 업데이트됨');
        }
      }

      for (final m in v.milestones) {
        if (m.done) {
          final achieved = parseDotDate(m.achievedDate);
          if (achieved != null &&
              !achieved.isBefore(weekStart) &&
              !achieved.isAfter(weekEnd)) {
            completedThisWeekMilestones.add('${v.name} - ${m.text}');
          }
        } else {
          final deadline = (m.date?.isNotEmpty ?? false)
              ? DateTime.tryParse(m.date!)
              : null;
          if (deadline != null) {
            if (deadline.isBefore(todayNormalized)) {
              overdueMilestones.add('${v.name} - ${m.text} (마감: ${m.date})');
            } else if (nearestUpcomingDate == null ||
                deadline.isBefore(nearestUpcomingDate)) {
              nearestUpcomingDate = deadline;
              nearestUpcomingLabel = '${v.name} - ${m.text} (마감: ${m.date})';
            }
          }
        }
      }
    }

    return '''당신은 사용자의 한 주간 성과를 분석하는 수석 비서이자 전문 코치입니다.
사용자의 지난 7일간의 실제 할 일 완료 내역과 현재 설정된 목표/비전을 바탕으로, $title께 드리는 주간 코칭 한마디를 격식 있게 작성해 주세요.

[사용자의 지난 7일간 할 일 완료 현황]
$recordBuffer

[분석 참고 데이터]
- 꾸준히 해낸 일 (3일 이상 연속 완료): ${consistentTasks.join(', ').isEmpty ? '없음' : consistentTasks.join(', ')}
- 미루다 다시 시작한 일 (3일 이상 연속으로 미루다 최근 다시 시작): ${resumedTasks.join(', ').isEmpty ? '없음' : resumedTasks.join(', ')}

[사용자의 현재 목표 및 장기 비전]
- 주간 목표: $weekGoalText
- 월간 목표: $monthGoalText
- 장기 비전: $visibleVisions

[장기 비전 상세 데이터]
- 이번 주 완료된 마일스톤: ${completedThisWeekMilestones.isEmpty ? '없음' : completedThisWeekMilestones.join(', ')}
- 최근 새로 추가/수정된 장기비전 메모나 마일스톤: ${recentlyUpdatedVisionNotes.isEmpty ? '없음' : recentlyUpdatedVisionNotes.join(' / ')}
- 가장 가까운 마감 예정 마일스톤: ${nearestUpcomingLabel ?? '없음'}
- 마감일이 지난 미완료 마일스톤: ${overdueMilestones.isEmpty ? '없음' : overdueMilestones.join(', ')}

[현재 설정된 습관 트래킹 빈도]
${habitFreqBuffer.toString().trim()}

[회고 유형: ${feedbackType == 0
        ? '실행 회고형'
        : feedbackType == 1
        ? '장기 비전형'
        : '컨디션 회고형'}]

[작성 지침]
1. 어투: ${isMale ? '남비서로서 차분하고 신뢰감 있는 "$title" 호칭의 격식체 (~했습니다, ~하십시오).' : '여비서로서 지적이고 부드러운 "$title" 호칭의 격식체 (~했어요, ~어떨까요).'}
2. 공통 원칙:
   - 휴무일(회복일)은 미완료나 실패로 해석하지 말고, 필요한 회복을 일정에 포함한 것으로 자연스럽게 존중해 주세요.
   - [현재 설정된 습관 트래킹 빈도]를 반드시 참고하세요. 특정 요일에만 하기로 한 습관이라면 그 빈도에 맞게 평가해 주세요.
3. 유형별 작성 방식:
${feedbackType == 0
        ? '''   [실행 회고형]
   - 사용자가 실제로 무엇을 했고, 무엇을 미뤘으며, 무엇이 개선되었는지를 중심으로 회고합니다.
   - 완료한 일들 중 목표/비전과 연결되는 중요한 활동 1~2개를 콕 집어 구체적으로 칭찬하세요. (추상적 칭찬 금지)
   - 3일 이상 미루다 다시 시작한 항목이 있다면 특별히 언급해 주세요.
   - 반복적으로 밀린 중요한 일이 있다면 부드럽게 지적하고 다음 주 우선순위로 권유하세요.'''
        : feedbackType == 1
        ? '''   [장기 비전형]
   - 현재 장기 비전과 마일스톤을 중심으로 회고합니다. [장기 비전 상세 데이터]를 반드시 참고하세요.
   - 이번 주 완료된 마일스톤이 있다면 구체적으로 언급하며 칭찬하세요.
   - 최근 새로 추가/수정된 장기비전 메모나 마일스톤이 있다면, 미래를 준비하고 있다는 점을 자연스럽게 언급하세요. (예: "최근에는 '앱 출시 준비' 관련 메모도 추가했네요. 실행뿐 아니라 방향까지 구상하시는 점이 인상적입니다.")
   - 가장 가까운 마감 예정 마일스톤이 있다면 다음 준비 대상으로 안내하세요.
   - 마감일이 지난 미완료 마일스톤이 있다면 부드럽게 확인을 권유하세요.
   - 장기 비전이 비어 있다면, 장기 비전을 작성하면 매주 실행과 연결해 점검할 수 있다고 안내하세요.
   - 마지막으로 미래를 응원하는 한마디로 마무리하세요.'''
        : '''   [컨디션 회고형]
   - 실행이나 성장보다 이번 주의 컨디션 흐름에 초점을 맞춥니다.
   - 완료율, 휴무일 패턴, 할 일 밀도 등을 바탕으로 체력/휴식/회복 측면을 분석하세요.
   - 무리한 주였는지, 잘 쉰 주였는지, 회복이 더 필요한지를 부드럽게 짚어주세요.
   - 꾸준히 해낸 일이 있다면 컨디션 속에서도 놓치지 않았다는 점을 자연스럽게 언급해 주세요.
   - 다음 주 컨디션 관리를 위한 한 가지 제안으로 마무리하세요.'''}
4. 분량: 3~4문장으로 간결하게. JSON이나 마크다운 없이 순수 텍스트로만 답변해 주세요.
5. 가독성: 문장 앞에 접속어가 올 때는 그 접속어 앞에서 한 줄을 비우고, 들여쓰기 없이 문단을 시작해 주세요. 예: "또한,", "특히,", "다만,", "하지만,", "그리고,", "앞으로,".''';
  }

  String _formatCoachCommentForDisplay(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return trimmed;

    final connectorPattern = RegExp(
      r'\s+(특히|또한|다만|하지만|그러나|그리고|그래서|따라서|그러므로|한편|반면|더불어|아울러|앞으로|다음으로),',
    );

    final formatted = trimmed
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAllMapped(connectorPattern, (match) => '\n\n${match.group(1)},')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    // 첫 인사말("소연님," 등)과 본문 사이의 줄바꿈을 없애 한 문장처럼 붙인다.
    return formatted.replaceFirstMapped(
      RegExp(r'^([가-힣]{1,12}(?:님|께),)\s*\n+\s*'),
      (m) => '${m.group(1)} ',
    );
  }

  String _formatGoalText(String? raw) {
    if (raw == null) return '없음';
    try {
      final decoded = jsonDecode(raw) as List;
      final text = decoded
          .map((goal) {
            final map = goal as Map;
            final status = map['done'] == true ? '완료' : '진행중';
            return '[$status] ${map['text'] ?? ''}';
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      return text.isEmpty ? '없음' : text;
    } catch (_) {
      return '없음';
    }
  }

  String _formatVisionText(String? raw) {
    if (raw == null) return '없음';
    try {
      final decoded = jsonDecode(raw) as List;
      final text = decoded
          .map((vision) {
            final map = vision as Map;
            // VisionItem은 비전 제목을 'name'에 저장한다. ('text'는 과거 호환용)
            final name = (map['name'] ?? map['text'] ?? '').toString().trim();
            final desc = (map['desc'] ?? '').toString().trim();
            if (name.isEmpty) return '';
            return desc.isEmpty ? name : '$name ($desc)';
          })
          .where((text) => text.trim().isNotEmpty)
          .join(', ');
      return text.isEmpty ? '없음' : text;
    } catch (_) {
      return '없음';
    }
  }

  bool _isVacationDate(String dateStr) {
    if (_vacationInfo == null) return false;
    final date = DateTime.tryParse(dateStr);
    if (date == null) return false;

    final normalized = DateTime(date.year, date.month, date.day);
    final type = _vacationInfo!['type']?.toString();

    if (type == 'today') {
      final target = DateTime.tryParse(
        _vacationInfo!['date']?.toString() ?? '',
      );
      if (target == null) return false;
      return normalized == DateTime(target.year, target.month, target.day);
    }

    if (type == 'range') {
      final start = DateTime.tryParse(
        _vacationInfo!['start']?.toString() ?? '',
      );
      final end = DateTime.tryParse(_vacationInfo!['end']?.toString() ?? '');
      if (start == null || end == null) return false;

      final startDay = DateTime(start.year, start.month, start.day);
      final endDay = DateTime(end.year, end.month, end.day);
      return !normalized.isBefore(startDay) && !normalized.isAfter(endDay);
    }

    if (type == 'regular') {
      final days = (_vacationInfo!['days'] as List?) ?? [];
      final dayIndex = normalized.weekday % 7; // Sunday = 0
      return days.any((day) => day == dayIndex);
    }

    return false;
  }

  String _getDayLabel(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return '';
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return days[dt.weekday % 7];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final records = _getLast7Records();
    int successDays = 0;
    int streak = 0;
    final vacationDays = records.where((r) => r['isVacation'] == true).length;
    final trackableDays = records.length - vacationDays;
    for (final r in records) {
      if (r['isVacation'] == true) continue;
      if (_recordDoneCount(r) > 0) {
        successDays++;
      }
    }
    // 휴무일은 연속 기록을 끊지 않고 건너뜁니다.
    for (int i = records.length - 1; i >= 0; i--) {
      if (records[i]['isVacation'] == true) continue;
      if (_recordDoneCount(records[i]) > 0) {
        streak++;
      } else {
        break;
      }
    }
    final flowPct = trackableDays == 0
        ? 100
        : ((successDays / trackableDays) * 100).round();

    return Container(
      color: _isMaster ? Colors.transparent : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 타이틀
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.bar_chart_rounded,
                        size: 22,
                        color: Color(0xFF3D3A4E),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '나의 기록',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF3D3A4E),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '최근 7일 ▾',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ],
              ),
            ),
            // 스크롤 영역
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    // 4칸 통계 요약 (패턴 써머리) -> 2칸으로 축소됨
                    _buildSummaryGrid(
                      successDays,
                      flowPct,
                      streak,
                      vacationDays,
                    ),
                    const SizedBox(height: 4),

                    // 코치의 한마디
                    _buildCoachCommentCard(records),
                    const SizedBox(height: 20),

                    // 이번 주 기록 (차트)
                    _buildWeeklyChartCard(records),
                    const SizedBox(height: 20),

                    // 습관 트래킹
                    _buildHabitTrackingCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryGrid(
    int successDays,
    int flowPct,
    int streak,
    int restDays,
  ) {
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      children: [
        _summaryCard(
          '연속 출석',
          '$streak일',
          '최고 -일',
          Icons.local_fire_department_outlined,
          _coach.accentColor,
          true,
        ),
        _summaryCard(
          '쉬는 날',
          '$restDays일',
          '-',
          Icons.bedtime_outlined,
          const Color(0xFF6EBF8B),
          false,
        ),
      ],
    );
  }

  Widget _summaryCard(
    String title,
    String value,
    String sub,
    IconData icon,
    Color color,
    bool isAccent,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isAccent ? color : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isAccent ? color : const Color(0xFFE8E3F8)),
        boxShadow: isAccent
            ? [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: isAccent ? Colors.white : color, size: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: GoogleFonts.notoSansKr(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: isAccent ? Colors.white : const Color(0xFF3D3A4E),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: GoogleFonts.notoSansKr(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: isAccent
                      ? Colors.white.withOpacity(0.9)
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getPatternFeedback(List<Map<String, dynamic>> records) {
    final activeRecords = records
        .where((r) => r['isVacation'] != true)
        .toList();
    final vacationCount = records.length - activeRecords.length;
    if (activeRecords.isEmpty) {
      return vacationCount > 0
          ? '이번 주는 쉬어가는 흐름이야. 잘 쉬는 것도 루틴을 오래 가져가는 방법이야.'
          : '아직 기록이 부족해. 오늘 하나만 완료하면 패턴이 시작돼.';
    }

    int total = 0;
    int successDays = 0;
    int zeros = 0;
    Map<String, dynamic> best = activeRecords[0];
    double bestRate = -1;

    for (var r in activeRecords) {
      final int count = _recordDoneCount(r);
      final int recordTotal = _recordTotalCount(r);
      total += count;
      if (count > 0) successDays++;
      if (count == 0) zeros++;
      if (recordTotal > 0) {
        final double rate = count / recordTotal;
        if (rate > bestRate) {
          bestRate = rate;
          best = r;
        }
      }
    }

    if (total == 0) {
      return vacationCount > 0
          ? '휴무일은 잘 쉬어가고 있어. 다시 시작하는 날엔 오늘 하나만 잡아도 충분해.'
          : '아직 기록이 부족해. 오늘 하나만 완료하면 패턴이 시작돼.';
    }

    final bestDay = _getDayLabel(best['date'] ?? '');

    if (successDays >= 5) {
      return '이번 주 $successDays일 성공. 흐름이 꽤 안정적이야. 특히 $bestDay요일에 강해.';
    }
    if (zeros >= 3) {
      return '끊긴 날이 조금 보여. 지금은 큰 계획보다 하루 1개 완료를 기준으로 잡는 게 좋아.';
    }
    return '$bestDay요일에 제일 잘했어. 그 시간대나 환경을 다시 써먹으면 좋아.';
  }

  String _getMasterPatternFeedback(List<Map<String, dynamic>> records) {
    final bool isMale = widget.coachId == 'sec_male' || _isMaster;
    final activeRecords = records
        .where((r) => r['isVacation'] != true)
        .toList();
    final vacationCount = records.length - activeRecords.length;
    int total = 0;
    int successDays = 0;
    int totalTaskCount = 0;
    for (var r in activeRecords) {
      final int doneCount = _recordDoneCount(r);
      final int totCount = _recordTotalCount(r);
      total += doneCount;
      totalTaskCount += totCount;
      if (doneCount > 0) successDays++;
    }

    if (total == 0) {
      if (vacationCount > 0) {
        final feedback = isMale
            ? '이번 주에는 회복을 선택하신 날이 있습니다. 쉬는 날을 일정의 일부로 두신 점도 좋은 관리입니다, 대표님.'
            : '이번 주에는 회복을 선택하신 날이 있어요. 잘 쉬는 것도 일정 관리의 일부예요, 대표님.';
        return feedback.replaceAll(UserTitleService.defaultTitle, _userTitle);
      }
      final feedback = isMale
          ? '아직 이번 주 기록이 없습니다. 오늘부터 시작하시면 됩니다, 대표님.'
          : '아직 이번 주 기록이 없어요. 오늘 하나만 시작해보는 건 어떨까요, 대표님?';
      return feedback.replaceAll(UserTitleService.defaultTitle, _userTitle);
    }

    List<String> parts = [];
    if (successDays >= 5) {
      parts.add(
        isMale ? '이번 주도 성실하게 움직이신 한 주였습니다.' : '이번 주도 열심히 달리신 한 주였어요, 대표님!',
      );
    } else {
      parts.add(
        isMale
            ? '장기 목표를 설정해두시면 더 의미 있게 연결해드릴 수 있습니다.'
            : '장기 목표를 설정해두시면 더 잘 챙겨드릴 수 있어요!',
      );
    }

    bool isOverloaded = totalTaskCount >= 35;
    if (isOverloaded && successDays >= 4) {
      parts.add(
        isMale
            ? '이번 주 할 일이 꽤 많으셨는데 잘 버텨내셨습니다. 다음 주엔 체력 관리도 함께 챙겨주세요.'
            : '이번 주 할 일이 많으셨는데도 잘 해내셨어요. 다음 주엔 체력 관리도 함께 챙겨주세요.',
      );
    }

    return parts
        .join(' ')
        .replaceAll(UserTitleService.defaultTitle, _userTitle);
  }

  Widget _buildCoachCommentCard(List<Map<String, dynamic>> records) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: AssetImage(
              _isMaster
                  ? 'assets/images/sec_male.png'
                  : 'assets/images/${widget.coachId}.png',
            ),
            backgroundColor: const Color(0xFFF3F0FF),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMaster ? '코치의 한마디' : '코치의 한마디',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _isMaster
                        ? CoachConfigs.get('sec_male').accentColor
                        : _coach.accentColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isMaster
                      ? _formatCoachCommentForDisplay(
                          _weeklyFeedbackText ??
                              '이번 주 활동과 목표를 분석하여 $_userTitle께 드릴 한마디를 작성하고 있습니다. 약 5초 정도만 잠시 기다려주십시오...',
                        )
                      : _getPatternFeedback(records),
                  style: GoogleFonts.notoSansKr(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3D3A4E),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyChartCard(List<Map<String, dynamic>> records) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/chart-simple.svg',
                width: 17,
                height: 17,
                colorFilter: ColorFilter.mode(
                  _coach.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '이번 주 기록',
                style: GoogleFonts.notoSansKr(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: records.map((r) {
              final isVacation = r['isVacation'] == true;
              final doneCount = _recordDoneCount(r);
              final totalCount = _recordTotalCount(r);
              final pct = totalCount > 0
                  ? ((doneCount / totalCount) * 100).round()
                  : 0;
              final isToday =
                  r['date'] ==
                  "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

              return Column(
                children: [
                  Text(
                    isVacation ? '쉼' : (pct > 0 ? '$pct%' : '-'),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: isVacation
                          ? const Color(0xFF6EBF8B)
                          : const Color(0xFFA0A0B0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 24,
                    height: 100,
                    decoration: BoxDecoration(
                      color: isVacation
                          ? const Color(0xFFEAF7EF)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 24,
                      height: isVacation ? 100 : 100.0 * (pct / 100.0),
                      decoration: BoxDecoration(
                        color: isVacation
                            ? const Color(0xFF6EBF8B)
                            : _coach.accentColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getDayLabel(r['date']),
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                      color: isVacation
                          ? const Color(0xFF6EBF8B)
                          : isToday
                          ? _coach.accentColor
                          : const Color(0xFF6B7280),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildHabitTrackingCard() {
    final trackingHabits = _habits.where((h) => h.tracking == true).toList();
    if (trackingHabits.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8E3F8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SvgPicture.asset(
                    'assets/icons/seedling.svg',
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(
                      _coach.accentColor,
                      BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '습관 트래킹',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF3D3A4E),
                    ),
                  ),
                ],
              ),
              Text(
                _isMaster ? '최근 30일' : '최근 7일',
                style: GoogleFonts.notoSansKr(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFA0A0B0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...trackingHabits.map((h) {
            // 임시로 달성률 계산 (habitLogs 사용)
            final days = _isMaster ? 30 : 7;
            int hSuccess = 0;
            int hTotal = 0;
            final logs = _habitLogs[h.id.toString()] ?? {};

            final now = DateTime.now();
            DateTime? createdAtDate;
            try {
              final parsed = DateTime.parse(h.createdAt);
              createdAtDate = DateTime(parsed.year, parsed.month, parsed.day);
            } catch (_) {}

            DateTime periodEnd = DateTime(now.year, now.month, now.day);
            DateTime periodStart = now.subtract(Duration(days: days - 1));
            periodStart = DateTime(
              periodStart.year,
              periodStart.month,
              periodStart.day,
            );

            if (createdAtDate != null && periodStart.isBefore(createdAtDate)) {
              periodStart = createdAtDate;
            }

            String formatYYMMDD(DateTime d) {
              return '${d.year.toString().substring(2)}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
            }

            String formatMMDD(DateTime d) {
              return '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
            }

            String periodText;
            if (periodStart.year == periodEnd.year) {
              periodText =
                  '${formatYYMMDD(periodStart)}~${formatMMDD(periodEnd)}';
            } else {
              periodText =
                  '${formatYYMMDD(periodStart)}~${formatYYMMDD(periodEnd)}';
            }

            for (int i = 0; i < days; i++) {
              final d = now.subtract(Duration(days: i));
              final dNormalized = DateTime(d.year, d.month, d.day);

              // 생성일 이전은 카운트 제외
              if (createdAtDate != null &&
                  dNormalized.isBefore(createdAtDate)) {
                continue;
              }

              // 요일 체크 (주간 반복일 경우 지정된 요일만 카운트)
              if (h.freq == 'weekly' && h.days.isNotEmpty) {
                if (!h.days.contains(d.weekday - 1)) {
                  continue;
                }
              }

              hTotal++;
              final dateStr =
                  "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
              if (logs[dateStr]?['done'] == true) hSuccess++;
            }
            final hPct = hTotal == 0 ? 0 : ((hSuccess / hTotal) * 100).round();

            const dayNames = ['월', '화', '수', '목', '금', '토', '일'];
            final freqLabel = h.freq == 'daily'
                ? '매일'
                : h.days.map((d) => dayNames[d]).join('/');

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                h.name,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF3D3A4E),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                freqLabel,
                                style: GoogleFonts.notoSansKr(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF6B7280),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '$hPct%',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _coach.accentColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: hPct / 100.0,
                      minHeight: 6,
                      backgroundColor: const Color(0xFFF3F4F6),
                      valueColor: AlwaysStoppedAnimation(_coach.accentColor),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '(트래킹 기간 : $periodText)',
                        style: GoogleFonts.notoSansKr(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFA0A0B0),
                        ),
                      ),
                    ],
                  ),
                  if (_isMaster) ...[
                    const SizedBox(height: 12),
                    _buildHabitPattern(h),
                  ],
                ],
              ),
            );
          }),
          if (!_isMaster) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: SvgPicture.asset(
                    'assets/icons/crown.svg',
                    width: 11,
                    height: 11,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF8B7CFF),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '마스터 코치 기록탭에서는 30일치 습관 달성률과 습관 달성 패턴까지 확인할 수 있습니다.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFA0A0B0),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHabitPattern(HabitItem h) {
    final logs = _habitLogs[h.id.toString()] ?? {};
    final validLogs = <Map<String, dynamic>>[];

    DateTime? createdAtDate;
    try {
      final parsed = DateTime.parse(h.createdAt);
      createdAtDate = DateTime(parsed.year, parsed.month, parsed.day);
    } catch (_) {}

    final now = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final d = now.subtract(Duration(days: i));
      final dNormalized = DateTime(d.year, d.month, d.day);

      if (createdAtDate != null && dNormalized.isBefore(createdAtDate)) {
        continue;
      }
      final dateStr =
          "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

      final log = logs[dateStr];
      if (log != null && log['done'] == true && log['completedAt'] != null) {
        validLogs.add({
          'dateStr': dateStr,
          'completedAt': log['completedAt'],
          // 예전 기록은 진행중 시작 시각이 없으니 완료 시각으로 대체
          'startedAt': log['startedAt'] ?? log['completedAt'],
        });
      }
    }

    if (validLogs.length < 3) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '아직 분석하기에 충분한 기록이 쌓이지 않았어요.\n조금만 더 이어가시면 습관 패턴을 찾아드릴게요.',
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B7280),
            height: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    final timeCounts = <int, int>{};
    final dayCounts = <int, int>{};
    final priorTaskCounts = <String, int>{};

    for (final log in validLogs) {
      try {
        final dt = DateTime.parse(log['completedAt']);
        // Time slot (2-hour windows) - 완료로 이어진 "진행중 시작" 시각 기준
        final startDt = DateTime.parse(log['startedAt']);
        final slot = startDt.hour ~/ 2;
        timeCounts[slot] = (timeCounts[slot] ?? 0) + 1;

        // Weekday (1=Mon..7=Sun)
        dayCounts[dt.weekday] = (dayCounts[dt.weekday] ?? 0) + 1;

        // Prior task
        final dateStr = log['dateStr'];
        final dayHistory = _history.where((r) => r['date'] == dateStr).toList();
        if (dayHistory.isNotEmpty) {
          final tasks = (dayHistory.last['tasks'] as List?) ?? [];
          final completedTasks = tasks
              .where((t) {
                if (t is! Map) return false;
                if (t['done'] != true || t['completedAt'] == null) return false;
                if (t['text'] == h.name) return false;
                return true;
              })
              .map((t) => t as Map<String, dynamic>)
              .toList();

          completedTasks.sort((a, b) {
            final ta = DateTime.parse(a['completedAt']);
            final tb = DateTime.parse(b['completedAt']);
            return ta.compareTo(tb);
          });

          for (int j = completedTasks.length - 1; j >= 0; j--) {
            final taskTime = DateTime.parse(completedTasks[j]['completedAt']);
            if (taskTime.isBefore(dt)) {
              // 가장 직전에 완료한 단 1개의 할 일만 확인
              if (dt.difference(taskTime).inMinutes <= 180) {
                final text = completedTasks[j]['text'].toString();
                priorTaskCounts[text] = (priorTaskCounts[text] ?? 0) + 1;
              }
              break; // 3시간 이내든 아니든 직전 1개만 보고 루프 종료
            }
          }
        }
      } catch (_) {}
    }

    // Top time
    int bestSlot = 0;
    int maxSlotCount = -1;
    timeCounts.forEach((slot, count) {
      if (count > maxSlotCount) {
        maxSlotCount = count;
        bestSlot = slot;
      }
    });

    final slotNames = {
      0: '밤 12시~2시',
      1: '새벽 2시~4시',
      2: '새벽 4시~6시',
      3: '아침 6시~8시',
      4: '오전 8시~10시',
      5: '오전 10시~12시',
      6: '낮 12시~2시',
      7: '오후 2시~4시',
      8: '오후 4시~6시',
      9: '저녁 6시~8시',
      10: '밤 8시~10시',
      11: '밤 10시~12시',
    };
    final bestTimeStr = slotNames[bestSlot] ?? '알 수 없음';

    // Top days
    int maxDayCount = -1;
    dayCounts.forEach((day, count) {
      if (count > maxDayCount) maxDayCount = count;
    });
    final bestDays = dayCounts.entries
        .where((e) => e.value == maxDayCount)
        .map((e) => e.key)
        .toList();
    bestDays.sort();

    final dayNames = {1: '월', 2: '화', 3: '수', 4: '목', 5: '금', 6: '토', 7: '일'};
    String bestDayStr = bestDays.map((d) => dayNames[d]!).join(' · ');
    if (bestDays.length == 2 && bestDays.contains(6) && bestDays.contains(7)) {
      bestDayStr = '주말';
    } else if (bestDays.length == 5 &&
        !bestDays.contains(6) &&
        !bestDays.contains(7)) {
      bestDayStr = '평일';
    } else if (bestDays.length == 7) {
      bestDayStr = '매일';
    } else {
      bestDayStr += '요일';
    }

    // Top prior task
    String? bestPriorTask;
    if (validLogs.length >= 5) {
      int maxPriorCount = -1;
      priorTaskCounts.forEach((text, count) {
        if (count >= 2 && count > maxPriorCount) {
          maxPriorCount = count;
          bestPriorTask = text;
        }
      });
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SvgPicture.asset(
                'assets/icons/seedling.svg',
                width: 14,
                height: 14,
                colorFilter: ColorFilter.mode(
                  _coach.accentColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '습관 패턴',
                style: GoogleFonts.notoSansKr(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF3D3A4E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _patternRow('🕒', '성공 시작 시간', bestTimeStr),
          const SizedBox(height: 6),
          _patternRow('📅', '주로 완료한 요일', bestDayStr),
          if (bestPriorTask != null) ...[
            const SizedBox(height: 6),
            _patternRow('🔄', '습관 전에 자주 한 일', bestPriorTask!),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('💡', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '최근에는 $bestDayStr $bestTimeStr에 시작했을 때 완료로 가장 잘 이어졌어요.\n비슷한 시간에 시작해보세요.',
                    style: GoogleFonts.notoSansKr(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF4B5563),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _patternRow(String emoji, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.notoSansKr(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.notoSansKr(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF3D3A4E),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
