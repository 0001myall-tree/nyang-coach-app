import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';
import 'tasks_sync_service.dart';

class MemoryService {
  static final MemoryService _instance = MemoryService._internal();
  factory MemoryService() => _instance;
  MemoryService._internal();

  Map<String, dynamic> masterProfile = _defaultMasterProfile();

  static Map<String, dynamic> _defaultMasterProfile() {
    return {
      'low_change': {
        'identity': '',
        'decision_pattern': '',
        'success_failure_formula': '',
        'communication_protocol': '',
        'intervention_rules': '',
      },
      'execution_resistance_profile': {
        'frequent_resisted_task_types': [],
        'common_blockers': [],
        'effective_interventions': [],
        'rejected_interventions': [],
        'recent_rejected_interventions': [],
        'preferred_choice_count': null,
        'task_specific_notes': [],
        'last_updated': '',
      },
      // mid_change 칸이 여기 있었다. 챕터는 증류가 돌려주는 항목에 아예 없어서
      // 값이 들어간 적이 없고(코치는 "챕터:  ()"라는 빈 줄을 받았다), 관심 축은
      // 하루 요약의 '요즘 신경 쓰는 일'과 하는 일이 겹쳤다. focus_projects와
      // active_experiments, environment_variables는 코치에게 보내는 선조차
      // 없었다. 요즘 무엇을 붙들고 있는지는 7일치 '신경'과 '같이 정한 것'이
      // 들고 있다.
      'high_change': {
        'energy_fatigue': '',
        'mood_condition': '',
        'obstacles': '',
        'scenes_insights': [],
      },
      // history_log도 같은 이유로 뺐다. 쓰는 곳도 읽는 곳도 없었다.
      'meta': {'last_batch_run': ''},
    };
  }

  List<dynamic> dailySummaries = [];
  List<dynamic> longTermMemory = [];

  /// 쓰이지 않게 된 칸들. 이미 쓰던 사람의 프로필에는 남아 있어서, 불러올 때
  /// 같이 걷어낸다. 그냥 두면 증류할 때마다 프로필을 통째로 프롬프트에 붙이므로
  /// 아무도 안 보는 값에 매주 토큰을 낸다.
  static const Map<String, List<String>> _retiredFields = {
    'meta': ['history_log'],
  };

  /// 통째로 쓰이지 않게 된 칸.
  static const List<String> _retiredSections = ['mid_change'];

  void _ensureMasterProfileShape() {
    for (final section in _retiredSections) {
      masterProfile.remove(section);
    }
    for (final entry in _retiredFields.entries) {
      final section = masterProfile[entry.key];
      if (section is Map) {
        for (final field in entry.value) {
          section.remove(field);
        }
      }
    }

    final defaults = _defaultMasterProfile();
    for (final entry in defaults.entries) {
      masterProfile.putIfAbsent(entry.key, () => entry.value);
      if (entry.value is Map && masterProfile[entry.key] is Map) {
        final target = masterProfile[entry.key] as Map;
        for (final nested in (entry.value as Map).entries) {
          target.putIfAbsent(nested.key, () => nested.value);
        }
      }
    }
  }

  Future<void> loadMemoryData() async {
    final prefs = await SharedPreferences.getInstance();

    final mpStr = prefs.getString('nyang_master_profile');
    if (mpStr != null && mpStr.isNotEmpty) {
      try {
        masterProfile = jsonDecode(mpStr);
      } catch (_) {}
    }
    _ensureMasterProfileShape();

    final dsStr = prefs.getString('nyang_daily_summaries');
    if (dsStr != null && dsStr.isNotEmpty) {
      try {
        dailySummaries = jsonDecode(dsStr);
      } catch (_) {}
    }

    final ltStr = prefs.getString('nyang_long_term_memory');
    if (ltStr != null && ltStr.isNotEmpty) {
      try {
        longTermMemory = jsonDecode(ltStr);
      } catch (_) {}
    }
  }

  /// 기억은 'nyang_' 키로만 저장한다. 클라우드로 올리는 일은 그 접두어를 보고
  /// 도는 [TasksSyncService]가 맡는다.
  ///
  /// 여태 클라우드에 두 벌 저장했다. 여기서 사용자 문서의 memory 칸에 직접
  /// 한 번, 그리고 같은 내용이 'nyang_' 키라서 appData로 또 한 번. 하루 요약을
  /// 만들 때마다 30일치가 두 군데에 쓰였다.
  ///
  /// 문제는 낭비만이 아니었다. memory 칸은 appData가 가진 보호를 하나도 못
  /// 받는다 — 합치기도, 업로드 대기 보호도, 빈 값 덮어쓰기 방지도 없이 그냥
  /// 덮는다. 기기가 둘이면 태블릿에서 쌓은 요약이 폰 때문에 사라질 수 있었다.
  /// 게다가 로그인 순서상 memory에서 읽어온 것을 곧바로 appData가 덮어써서,
  /// 그 저장은 위험만 지고 하는 일이 없었다.
  Future<void> saveMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_master_profile', jsonEncode(masterProfile));
    await prefs.setString('nyang_daily_summaries', jsonEncode(dailySummaries));
    await prefs.setString('nyang_long_term_memory', jsonEncode(longTermMemory));
    TasksSyncService.scheduleSyncToCloud();
  }

  /// 예전에 memory 칸에만 기억이 있는 사람을 위해 읽기는 남겨둔다.
  ///
  /// 로그인할 때 이것이 먼저 돌고 appData 복원이 뒤따른다. appData에 그 키가
  /// 있으면 그쪽이 이기고, 없을 때만 여기서 읽어온 옛 기억이 남는다. 새로
  /// 쓰지는 않으므로 이 칸은 그 자리에 멈춰 있다.
  Future<void> syncFromCloud() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists &&
            doc.data() != null &&
            doc.data()!.containsKey('memory')) {
          final memoryData = doc.data()!['memory'];
          if (memoryData['masterProfile'] != null) {
            masterProfile = memoryData['masterProfile'];
            _ensureMasterProfileShape();
          }
          if (memoryData['dailySummaries'] != null) {
            dailySummaries = List<dynamic>.from(memoryData['dailySummaries']);
          }
          if (memoryData['longTermMemory'] != null) {
            longTermMemory = List<dynamic>.from(memoryData['longTermMemory']);
          }

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
            'nyang_master_profile',
            jsonEncode(masterProfile),
          );
          await prefs.setString(
            'nyang_daily_summaries',
            jsonEncode(dailySummaries),
          );
          await prefs.setString(
            'nyang_long_term_memory',
            jsonEncode(longTermMemory),
          );
        }
      } catch (e) {
        debugPrint('Firestore Memory load error: $e');
      }
    }
  }

  void clearCache() {
    masterProfile = _defaultMasterProfile();
    dailySummaries = [];
    longTermMemory = [];
  }

  /// 그날 요약이 이미 있는지. [loadMemoryData] 뒤에 부른다.
  bool hasDailySummary(String date) => dailySummaries.any(
    (summary) => summary is Map && summary['date']?.toString() == date,
  );

  /// 그날 코치와 함께 만들거나 정한 것. 없으면 빈 문자열.
  /// 이 칸이 생기기 전에 쌓인 요약에는 없으니 빈 값을 견뎌야 한다.
  ///
  /// 요약의 다른 칸은 무엇을 했는지를 적는데, 이 칸만 무엇이 나왔는지를 적는다.
  /// "등장인물 정리"로는 다음 날 이어갈 수 없고, 이름과 설정이 남아야 이어진다.
  ///
  /// 저장되는 이름은 'made' 그대로 둔다. 이름을 바꾸면 지금까지 쌓인 요약의
  /// 이 칸을 못 읽는다.
  static String settledWith(dynamic summary) {
    if (summary is! Map) return '';
    return (summary['made'] ?? '').toString().trim();
  }

  /// 최근 요약들에서 '요즘 신경 쓰는 일' 이름만 모은다. 최근 것이 앞에 온다.
  ///
  /// 지난 요약 전체는 코치가 부를 때만 간다. 그런데 모르는 것은 달라고 할 수가
  /// 없다 — 어제 상견례 이야기를 한 사람이 오늘 "약속 있어"라고만 하면, 코치는
  /// 그 둘이 이어진다는 걸 몰라서 부를 생각도 못 한다.
  ///
  /// 그래서 이름만 늘 보낸다. 목차는 늘 주고 본문은 부를 때 주는 셈이다.
  /// 요약 한 줄이 백 자쯤인데 이름은 한 줄 전체가 서른 자 안쪽이라, 매 턴
  /// 붙어도 값이 거의 안 든다.
  static List<String> recentOnMind(
    List<dynamic> summaries, {
    int days = 7,
    int max = 5,
  }) {
    final recent = summaries.length > days
        ? summaries.sublist(summaries.length - days)
        : summaries;

    // 최근 것부터 담는다. 개수가 찼을 때 남는 쪽이 최근이어야 한다.
    final names = <String>[];
    for (final summary in recent.reversed) {
      if (summary is! Map) continue;
      for (final name in formatOnMind(summary['on_mind']).split(',')) {
        final trimmed = name.trim();
        if (trimmed.isEmpty || names.contains(trimmed)) continue;
        names.add(trimmed);
        if (names.length >= max) return names;
      }
    }
    return names;
  }

  static String formatOnMind(dynamic value) {
    if (value is String) return value.trim();
    if (value is! List) return '';
    return value
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .join(', ');
  }

  Future<void> generateDailySummary(
    String date,
    List<dynamic> chatHistory,
  ) async {
    if (chatHistory.isEmpty) return;
    try {
      // 채팅 기록은 {'isUser','text'} 형식으로 저장된다. (구형 {'role','content'}도 허용)
      final textLogs = chatHistory
          .whereType<Map>()
          .map((m) {
            final role =
                m['role'] ?? ((m['isUser'] == true) ? 'user' : 'assistant');
            final content = m['content'] ?? m['text'] ?? '';
            final coachId = (m['coachId'] ?? '').toString().trim();
            return coachId.isEmpty
                ? '$role: $content'
                : '[$coachId] $role: $content';
          })
          .join('\n');
      final prompt =
          '''당신은 사용자의 하루를 회고하고 기록하는 전문 데이터 분석가입니다. 오늘 대화 내역을 바탕으로 하루를 요약해주세요.

[오늘의 대화 내역]
$textLogs

[규칙]
- 달성: 오늘 이룬 성취, 완료한 일 (간결하게)
- 못함: 계획했지만 미룬 일, 실패한 일
- 컨디션: 신체적, 정신적 피로도나 에너지 레벨
- 고민: 오늘 사용자가 토로한 고민이나 막힌 부분
- 감정: 오늘의 지배적인 감정 키워드
- 요즘 신경 쓰는 일: 오늘 사용자가 입으로 꺼낸 일만 이름으로 적는다. 대화에 없으면 빈 배열로 둔다.
  ("공모전 준비해야 되는데" -> 공모전 / "알바 갔다 왔어" -> 알바 / "이사 짐 싸느라 늦었어" -> 이사 준비)
  대부분의 날은 빈 배열이거나 한 개다. 많아도 두 개.
  힘들다/지친다 같은 평가는 붙이지 않는다. 고민이 아니어도 일상이면 적는다.
- 같이 정한 것(made): 오늘 코치와 함께 만들거나 정한 것의 알맹이. 이름과 설정을 그대로 적는다.
  평소에는 한두 줄이다. 남길 알맹이가 많은 날만 네 줄까지 늘린다. 줄 수를 채우려고
  대화에 없던 말을 덧붙이지 않는다. 며칠 뒤에 "그때 짰던 거 뭐였지" 하고 물었을 때
  이 칸만 보고 답할 수 있으면 그 길이가 맞는 길이다. 줄바꿈으로 나눠 적는다.
  ("이번 달은 소설 말고 에세이로 가기로 함. 주제는 이사 다니며 본 동네들")
  ("주인공: 손해 보기 싫은데 자꾸 손해 보는 성격. 회사에서 매번 총대를 멤
    로맨스 상대 서린: 계산적, 이면 동기는 아버지 회사를 지키는 것
    1화는 둘이 엘리베이터에 갇히는 장면부터 시작하기로 함")
  "등장인물 정리"처럼 무엇을 했는지만 적으면 이어갈 수 없다. 이름과 설정이 있어야 이어진다.
  일을 끝냈다는 이야기뿐이면 빈 문자열로 둔다. 달성 칸과 겹쳐 적지 말 것 — 거기는 무엇을 했는지, 여기는 무엇이 나왔는지다.
  고민 칸과도 겹쳐 적지 말 것 — 거기는 무엇이 막혔는지, 여기는 그 끝에 무엇으로 정했는지다.
- 실행저항: 사용자가 하기 싫어하거나 미룬 과업, 막힌 이유, 수락/거부한 개입이 있으면 행동 기반으로 간결하게 기록. ADHD 등 진단명은 붙이지 말 것.

반드시 아래 JSON 형식으로 응답하세요:
{
  "achieved": "문자열",
  "missed": "문자열",
  "condition": "문자열",
  "concern": "문자열",
  "emotion": "문자열",
  "on_mind": ["문자열"],
  "made": "문자열",
  "execution_resistance": {
    "resisted_task_types": ["cleaning|writing|reading|study|work|self_care|sleep|exercise|other"],
    "blockers": ["task_switching|decision_overload|result_anxiety|low_energy|unclear_first_step|sensory_friction|time_pressure|other"],
    "accepted_interventions": ["two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other"],
    "rejected_interventions": ["two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other"],
    "rejected_intervention_events": [{"intervention": "two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other", "task_type": "cleaning|writing|reading|study|work|self_care|sleep|exercise|other", "reason": "문자열"}],
    "notes": ["문자열"]
  }
}''';

      final messages = [
        {'role': 'system', 'content': '당신은 일일 요약을 생성하는 백그라운드 분석 AI입니다.'},
        {'role': 'user', 'content': prompt},
      ];

      final estimatedPromptTokens = AnalyticsService.estimateChatTokens(
        messages,
        '',
      );
      await ApiUsageLimitService.ensureChatAllowed(
        estimatedTokens: estimatedPromptTokens,
      );

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('chatProxy');
      final response = await callable.call({
        'messages': messages,
        'temperature': 0.2,
      });

      final raw = response.data['content'].toString().trim();
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
      final estimatedTokens = AnalyticsService.estimateChatTokens(
        messages,
        raw,
      );

      AnalyticsService.logApiUsage(
        coachId: 'system',
        estimatedTokens: estimatedTokens,
        actualTokens: actualTokens,
        actualCostWon: actualCostWon,
        usageSource: 'daily_summary',
        countAsUserUsage: false,
      );

      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> summary = jsonDecode(clean);
      summary['date'] = date;

      dailySummaries.removeWhere((s) => s['date'] == date);
      dailySummaries.add(summary);
      dailySummaries.sort(
        (a, b) => (a['date'] as String).compareTo(b['date'] as String),
      );

      if (dailySummaries.length > 30) {
        dailySummaries = dailySummaries.sublist(dailySummaries.length - 30);
      }
      await saveMemoryData();

      // 증류(프로필 재작성)는 가장 무거운 호출이라 요약이 충분히 쌓였고
      // 마지막 증류로부터 7일 이상 지났을 때만 실행한다. (요약은 매일, 증류는 주 1회)
      if (dailySummaries.length >= 7 && _shouldRunDistill(date)) {
        await distillLifeOperationMemory(date);
      }
    } catch (e) {
      print('Daily summary error: $e');
    }
  }

  /// 마지막 증류 실행일(last_batch_run)로부터 7일 이상 지났는지 확인.
  bool _shouldRunDistill(String todayStr) {
    final lastRun =
        masterProfile['meta']?['last_batch_run']?.toString().trim() ?? '';
    if (lastRun.isEmpty) return true;
    final last = DateTime.tryParse(lastRun);
    final today = DateTime.tryParse(todayStr);
    if (last == null || today == null) return true;
    return today.difference(last).inDays >= 7;
  }

  Future<void> distillLifeOperationMemory(String todayStr) async {
    try {
      final recent = dailySummaries.length > 14
          ? dailySummaries.sublist(dailySummaries.length - 14)
          : dailySummaries;
      // on_mind는 일부러 뺀다. 한 주 반짝하는 일상까지 장기 성향으로 굳는 걸 막으려고
      // 하루 요약에만 두는 칸이다. 여기 넣으면 그 문이 다시 열린다.
      final recentSummaries = recent
          .map(
            (s) =>
                '[${s['date']}] 달성:${s['achieved']} / 못함:${s['missed']} / 컨디션:${s['condition']} / 고민:${s['concern']} / 감정:${s['emotion']} / 실행저항:${jsonEncode(s['execution_resistance'] ?? {})}',
          )
          .join('\n');

      final prompt =
          '''당신은 사용자의 삶을 체계적으로 관리하는 수석 비서이자 데이터 분석가입니다. 최근 기록과 현재 메모리를 분석하여 [Life Operation Memory]를 최적화하세요.

[최근 기록]
$recentSummaries

[현재 메모리 상태]
${jsonEncode(masterProfile)}

[분석 및 업데이트 지침]
1. 현재 상태:
   - 실시간 상태(에너지, 기분, 장애물)를 요약하세요.
   - 가장 의미 있었던 [장면/사용자 고유 표현/인사이트]를 최대 3개 추출하세요. (표현은 추후 '언어적 동기화'에 사용됨)

2. 실행 저항 개인화:
   - 사용자가 자주 저항하는 과업, 자주 보이는 막힘, 잘 먹힌 개입, 거부/부담이 컸던 개입을 행동 기반으로 갱신하세요.
   - 단 한 번의 사건으로 단정하지 말고, 최근 기록에서 반복되거나 사용자가 명시적으로 말한 것만 강하게 반영하세요.
   - "ADHD", "우울증" 같은 진단명은 저장하지 말고, "전환 어려움", "선택 과부하", "결과 확인 불안"처럼 관찰 가능한 실행 패턴으로만 저장하세요.
   - 선택지 수 선호가 보이면 preferred_choice_count에 2 또는 3처럼 숫자로 저장하세요. 근거가 없으면 null로 두세요.
   - 글쓰기처럼 종류가 갈리는 과업에서, 기록에 소설과 에세이가 같이 보이면 task_specific_notes에 "글: 소설과 에세이를 오간다"처럼 오간다는 사실을 저장하고, 한 종류만 꾸준히 보일 때만 그 종류를 저장하세요. 어느 쪽이든 그날 대화와 할 일 이름이 우선이라는 뜻입니다.
   - recent_rejected_interventions는 최근 거부한 개입을 최신순으로 최대 5개 저장하세요. 각 항목은 {"intervention":"...", "task_type":"...", "reason":"...", "last_rejected_at":"$todayStr"} 형식으로 두고, 최신 항목일수록 코칭에서 가장 후순위가 됩니다.

3. 오래 가는 성향:
   - 30일 이상 지속된 장기 성향 -> low_change_candidates로 제안 (사용자에게 승인 요청할 후보).

반드시 아래 JSON 형식으로만 응답하세요:
{
  "high_change": {
    "energy_fatigue": "문자열",
    "mood_condition": "문자열",
    "obstacles": "문자열",
    "scenes_insights": [{"scene": "...", "expression": "사용자가 사용한 고유 표현", "insight": "...", "timestamp": "$todayStr"}]
  },
  "execution_resistance_profile": {
    "frequent_resisted_task_types": ["cleaning|writing|reading|study|work|self_care|sleep|exercise|other"],
    "common_blockers": ["task_switching|decision_overload|result_anxiety|low_energy|unclear_first_step|sensory_friction|time_pressure|other"],
    "effective_interventions": ["two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other"],
    "rejected_interventions": ["two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other"],
    "recent_rejected_interventions": [{"intervention": "two_choice_microsteps|playful_mission|single_default|five_min_start|cause_question|countdown_start|body_activation|timer|other", "task_type": "cleaning|writing|reading|study|work|self_care|sleep|exercise|other", "reason": "문자열", "last_rejected_at": "$todayStr"}],
    "preferred_choice_count": 2,
    "task_specific_notes": ["문자열"],
    "last_updated": "$todayStr"
  },
  "low_change_candidates": [{"field": "identity|decision_pattern|formula", "value": "...", "reason": "..."}]
}''';

      final messages = [
        {
          'role': 'system',
          'content': '당신은 정밀한 데이터 승급 및 망각 알고리즘을 수행하는 분석 비서입니다.',
        },
        {'role': 'user', 'content': prompt},
      ];

      final estimatedPromptTokens = AnalyticsService.estimateChatTokens(
        messages,
        '',
      );
      await ApiUsageLimitService.ensureChatAllowed(
        estimatedTokens: estimatedPromptTokens,
      );

      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('chatProxy');
      final response = await callable.call({
        'messages': messages,
        'temperature': 0.3,
      });

      final raw = response.data['content'].toString().trim();
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
      final estimatedTokens = AnalyticsService.estimateChatTokens(
        messages,
        raw,
      );

      AnalyticsService.logApiUsage(
        coachId: 'system',
        estimatedTokens: estimatedTokens,
        actualTokens: actualTokens,
        actualCostWon: actualCostWon,
        usageSource: 'life_memory_distill',
        countAsUserUsage: false,
      );

      final clean = raw.replaceAll('```json', '').replaceAll('```', '').trim();
      final Map<String, dynamic> update = jsonDecode(clean);

      masterProfile['high_change'] =
          update['high_change'] ?? masterProfile['high_change'];

      if (update['execution_resistance_profile'] is Map) {
        masterProfile['execution_resistance_profile'] =
            update['execution_resistance_profile'];
      }

      final candidates = update['low_change_candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        masterProfile['low_change_candidates'] = candidates;
      }

      masterProfile['meta']['last_batch_run'] = todayStr;
      await saveMemoryData();
    } catch (e) {
      print('Life Operation Memory error: $e');
    }
  }
}
