import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'analytics_service.dart';
import 'api_usage_limit_service.dart';

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
      'mid_change': {
        'chapter': {'title': '', 'description': ''},
        'keywords_axis': [],
        'focus_projects': [],
        'active_experiments': [],
        'environment_variables': [],
      },
      'high_change': {
        'energy_fatigue': '',
        'mood_condition': '',
        'obstacles': '',
        'scenes_insights': [],
      },
      'meta': {'last_batch_run': '', 'history_log': []},
    };
  }

  List<dynamic> dailySummaries = [];
  List<dynamic> longTermMemory = [];

  void _ensureMasterProfileShape() {
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

  Future<void> saveMemoryData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nyang_master_profile', jsonEncode(masterProfile));
    await prefs.setString('nyang_daily_summaries', jsonEncode(dailySummaries));
    await prefs.setString('nyang_long_term_memory', jsonEncode(longTermMemory));

    // Firestore Sync
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'memory': {
            'masterProfile': masterProfile,
            'dailySummaries': dailySummaries,
            'longTermMemory': longTermMemory,
          },
        }, SetOptions(merge: true));
      } catch (e) {
        debugPrint('Firestore Memory sync error: $e');
      }
    }
  }

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

3. 반복 패턴 관찰:
   - 최근 기록에서 '반복되는 패턴'을 탐지하세요.
   - 2주(14일) 이상 지속된 최근 관심사/프로젝트 -> mid_change_updates.add_or_update로 제안.
   - 30일 이상 지속된 장기 성향 -> low_change_candidates로 제안 (사용자에게 승인 요청할 후보).

4. 망각 및 가지치기 (Pruning & Decay):
   - 최근 관심사/프로젝트 중 최근 14일간의 기록에서 전혀 언급되지 않거나 유효하지 않은 항목은 'remove'에 넣으세요.

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
  "mid_change_updates": {
    "add_or_update": [{"type": "keywords_axis|focus_projects", "value": "...", "reason": "..."}],
    "remove": ["삭제할 항목 이름"]
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

      final midUpdates = update['mid_change_updates'];
      if (midUpdates != null) {
        final addOrUpdate = midUpdates['add_or_update'] as List?;
        if (addOrUpdate != null) {
          for (var item in addOrUpdate) {
            final type = item['type'];
            final val = item['value'];
            List list = (type == 'keywords_axis')
                ? masterProfile['mid_change']['keywords_axis']
                : masterProfile['mid_change']['focus_projects'];

            final existingIdx = list.indexWhere((e) {
              if (e is String) return e == val;
              if (e is Map) return e['value'] == val;
              return false;
            });

            if (existingIdx == -1) {
              list.add({
                'value': val,
                'first_seen': todayStr,
                'last_seen': todayStr,
              });
            } else {
              if (list[existingIdx] is Map) {
                list[existingIdx]['last_seen'] = todayStr;
              }
            }
          }
        }

        final removeList = midUpdates['remove'] as List?;
        if (removeList != null) {
          for (var val in removeList) {
            masterProfile['mid_change']['keywords_axis'].removeWhere(
              (k) => k is String ? k == val : (k as Map)['value'] == val,
            );
            masterProfile['mid_change']['focus_projects'].removeWhere(
              (p) => p is String ? p == val : (p as Map)['value'] == val,
            );
          }
        }
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
