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

  String buildMemoryContext(String coachTier) {
    String profileCtx = "\n[사용자 마스터 프로필]";

    String formatMidItem(dynamic item) {
      if (item == null) return '';
      if (item is String) return item;
      if (item is Map && item.containsKey('value')) {
        return item['value'].toString();
      }
      return item.toString();
    }

    final highChange = masterProfile['high_change'] ?? {};
    final midChange = masterProfile['mid_change'] ?? {};
    final lowChange = masterProfile['low_change'] ?? {};
    final resistanceProfile =
        masterProfile['execution_resistance_profile'] as Map? ?? {};

    String formatList(dynamic value) {
      if (value is! List || value.isEmpty) return '기록 전';
      final text = value
          .map((e) {
            if (e is Map && e.containsKey('value')) return e['value'];
            if (e is Map && e.containsKey('intervention')) {
              final intervention = e['intervention'] ?? '';
              final taskType = e['task_type'] ?? '';
              final reason = e['reason'] ?? '';
              final rejectedAt = e['last_rejected_at'] ?? '';
              return [
                intervention,
                if (taskType.toString().trim().isNotEmpty) '과업:$taskType',
                if (reason.toString().trim().isNotEmpty) '이유:$reason',
                if (rejectedAt.toString().trim().isNotEmpty) '날짜:$rejectedAt',
              ].join(' / ');
            }
            return e;
          })
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .join(', ');
      return text.trim().isEmpty ? '기록 전' : text;
    }

    String resistanceCtx() {
      final preferredChoiceCount = resistanceProfile['preferred_choice_count']
          ?.toString()
          .trim();
      return '''\n[실행 저항 개인화]
- 자주 막히는 과업: ${formatList(resistanceProfile['frequent_resisted_task_types'])}
- 자주 보이는 막힘: ${formatList(resistanceProfile['common_blockers'])}
- 잘 먹힌 개입: ${formatList(resistanceProfile['effective_interventions'])}
- 거부/부담이 컸던 개입: ${formatList(resistanceProfile['rejected_interventions'])}
- 최근 거부한 개입(최신순): ${formatList(resistanceProfile['recent_rejected_interventions'])}
- 적정 선택지 수: ${preferredChoiceCount == null || preferredChoiceCount.isEmpty ? '기록 전' : preferredChoiceCount}
- 과업별 메모: ${formatList(resistanceProfile['task_specific_notes'])}''';
    }

    if (coachTier == 'friends') {
      profileCtx +=
          '''\n- 실시간 상태: ${highChange['energy_fatigue'] ?? '관찰 중'} / ${highChange['mood_condition'] ?? '기록 전'}
- 오늘의 장애물: ${highChange['obstacles'] ?? '없음'}${resistanceCtx()}''';
    } else if (coachTier == 'pro') {
      profileCtx +=
          '''\n[실시간 상태]\n- 에너지/기분: ${highChange['energy_fatigue']} / ${highChange['mood_condition']}
\n[현재 챕터]\n- 챕터: ${midChange['chapter']?['title']}
- 상세: ${midChange['chapter']?['description']}
\n${resistanceCtx()}
\n[관찰된 패턴]\n- 의사결정 패턴: ${lowChange['decision_pattern']}
- 성공/실패 공식: ${lowChange['success_failure_formula']}''';
    } else {
      final keywords =
          (midChange['keywords_axis'] as List?)
              ?.map((e) => formatMidItem(e))
              .join(', ') ??
          '';
      profileCtx +=
          '''\n${resistanceCtx()}
\n[현재 상태]\n- 상태: ${highChange['energy_fatigue']} / ${highChange['mood_condition']}\n- 장애물: ${highChange['obstacles']}
\n[최근 맥락]\n- 챕터: ${midChange['chapter']?['title']} (${midChange['chapter']?['description']})\n- 관심 축: $keywords
\n[장기 성향 참고]\n- 정체성: ${lowChange['identity']}\n- 의사결정 패턴: ${lowChange['decision_pattern']}\n- 소통 프로토콜: ${lowChange['communication_protocol']}\n- 성공/실패 공식: ${lowChange['success_failure_formula']}
- 개입 규칙: ${lowChange['intervention_rules']}''';

      final scenes = highChange['scenes_insights'] as List?;
      if (scenes != null && scenes.isNotEmpty) {
        profileCtx += '\n\n[코칭 개입 데이터 - 언어적 동기화 용]\n';
        for (var s in scenes) {
          if (s is Map) {
            profileCtx +=
                '- [인상적인 장면]: ${s['scene']}\n  [사용자 고유 표현]: "${s['expression']}"\n  [인사이트]: ${s['insight']}\n';
          }
        }
      }

      final candidates = masterProfile['low_change_candidates'] as List?;
      if (candidates != null && candidates.isNotEmpty) {
        profileCtx += '\n[장기 성향 후보 (30일 지속 패턴 - 승인 요청 필요)]\n';
        for (var c in candidates) {
          if (c is Map) {
            profileCtx +=
                '- ${c['field']}: ${c['value']} (이유: ${c['reason']})\n';
          }
        }
        profileCtx +=
            '\n*위 후보에 대해 "요즘 이런 모습이 자주 보이는데, 제가 기억해두고 계속 챙겨드릴까요?" 혹은 "이건 대표님만의 중요한 루틴인 것 같은데, 제가 잊지 않게 적어둘게요!"와 같이 자연스럽게 제안하세요.';
      }
    }

    String ctx =
        '''
$profileCtx

[코칭 개입 규칙 (매우 중요)]
1. 언어적 동기화 (Linguistic Sync): 
   - [사용자 고유 표현]을 문장 속에 자연스럽게 섞어서 사용하세요. (주 1~2회 빈도 제한)
   - "지난번에 ~라고 하셨잖아요"라는 직접 회상보다는, 사용자의 감정이 담긴 표현을 오늘 상황에 녹여내세요. (예: "오늘도 '숨 쉬는 느낌'이 드는 평온한 하루면 좋겠네요.")
2. 맥락 기반 제언 (Contextual Advice): 
   - [최근 맥락]의 [관심 축]을 활용해 현재 상황의 원인을 짚어주세요. (예: "오늘 피로도가 높은 게, 혹시 요즘 몰입 중인 일본 진출 준비 때문일까요?")
3. 자연스러운 패턴 브레이킹 (Pattern Breaking): 
   - [장기 성향 참고]의 [성공/실패 공식] 감지 시, 진단적인 말투 대신 상황 묘사형으로 부드럽게 개입하세요. (예: "지금 보니까 완벽주의 때문에 오히려 행동이 조금 느려진 상황인 것 같아요. 조금만 힘을 빼볼까요?")
4. 실행 저항 개인화:
   - 실행 저항 상황에서는 [실행 저항 개인화]의 잘 먹힌 개입과 거부/부담이 컸던 개입을 우선 참고하세요.
   - 특정 개입이 싫다고 명시되어 있거나 반복 거부된 경우, 그 방식을 반복하지 말고 더 작은 선택지나 다른 감각 채널로 바꾸세요.
   - [최근 거부한 개입]에 있는 방식은 최신 항목일수록 가장 후순위로 미루고, 다른 방식부터 제안하세요.
5. 실시간(Lite) 모드: 대화 중에는 위 프로필을 '읽기 전용'으로만 참조하며, 직접 프로필 수정을 언급하지 마세요.''';

    if (longTermMemory.isNotEmpty) {
      ctx += '\n\n[이 사용자의 장기 패턴]\n';
      for (int i = 0; i < longTermMemory.length; i++) {
        ctx += '${i + 1}. ${longTermMemory[i]}\n';
      }
    }

    if (dailySummaries.isNotEmpty) {
      final recent = dailySummaries.length > 7
          ? dailySummaries.sublist(dailySummaries.length - 7)
          : dailySummaries;
      ctx += '\n[최근 7일 요약]\n';
      for (var s in recent) {
        if (s is Map) {
          ctx +=
              '${s['date']}: 달성(${s['achieved']}) / 못함(${s['missed']}) / 컨디션(${s['condition']}) / 고민(${s['concern']})\n';
        }
      }
    }

    return ctx;
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
- 실행저항: 사용자가 하기 싫어하거나 미룬 과업, 막힌 이유, 수락/거부한 개입이 있으면 행동 기반으로 간결하게 기록. ADHD 등 진단명은 붙이지 말 것.

반드시 아래 JSON 형식으로 응답하세요:
{
  "achieved": "문자열",
  "missed": "문자열",
  "condition": "문자열",
  "concern": "문자열",
  "emotion": "문자열",
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
