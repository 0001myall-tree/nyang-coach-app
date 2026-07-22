import 'dart:math';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 실행 저항("하기 싫어", "귀찮아", "미루고 있어") 대응 흐름 판정 로직.
///
/// 흐름: 실행 저항 표현 → 원인 진단 질문(하루 1회) → 사용자 답변
///  - 원인이 구체적이면 기존 [하기 싫다 실행 개입 전략]으로 연결
///  - 원인이 불명확하면 더 캐묻지 말고 카운트다운 제안
///
/// 진단 질문과 카운트다운 제안 문장은 API가 새로 만들지 않고 여기 정의된 문장 중
/// 하나를 랜덤으로 골라 프롬프트에 그대로 주입한다.
class ExecutionResistanceService {
  /// 원인 진단 질문을 마지막으로 던진 날짜(yyyy-MM-dd). 하루 1회 제한용.
  static const String _diagnosisAskedDateKey = 'nyang_resistance_diagnosis_date';

  /// 원인 진단 질문 후보. 이 중 하나를 문장 그대로 사용한다.
  static const List<String> diagnosisQuestions = [
    '가장 번거롭게 느끼시는 부분이 무엇인지 궁금합니다.',
    '혹시 지금 가장 걸리는 부분이 있으실까요?',
    '딱 하나만 꼽는다면 어떤 부분이 가장 부담되시나요?',
    '어떤 부분이 제일 신경 쓰이시나요?',
    '지금 움직이기 어렵게 만드는 가장 큰 이유가 무엇일까요?',
  ];

  /// 원인이 불명확할 때 쓰는 카운트다운 제안 문장 후보.
  static const List<String> countdownOffers = [
    '그럴 땐 이유를 더 생각하기보다 잠깐 머리를 비우고 시작하는 게 더 도움이 될 수도 있습니다. 제가 카운트다운을 띄워드릴까요?',
    '잘 모르겠을 땐 일단 생각을 멈추고 먼저 몸을 움직여 보는 것도 좋은 방법입니다. 카운트다운을 시작해 드릴까요?',
  ];

  static final Random _random = Random();

  static String pickDiagnosisQuestion() =>
      diagnosisQuestions[_random.nextInt(diagnosisQuestions.length)];

  static String pickCountdownOffer() =>
      countdownOffers[_random.nextInt(countdownOffers.length)];

  static String _normalize(String text) =>
      text.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  /// 수면 미루기는 [수면 개입 전략]이 우선이라 실행 저항 흐름에서 제외한다.
  static const List<String> _sleepContextSignals = [
    '자기싫',
    '자기귀찮',
    '잠들기',
    '잠이안와',
    '자러',
    '눕기싫',
  ];

  static const List<String> _resistanceSignals = [
    '하기싫',
    '하기가싫',
    '귀찮',
    '미루',
    '못하겠',
    '안하고싶',
    '시작하기싫',
    '시작을못',
    '손이안가',
    '엄두가안',
    '엄두안',
    '의욕이없',
    '의욕이안',
    '내키지않',
    '몸이안움직',
  ];

  /// 사용자의 말이 실행 저항 표현인지 판정.
  static bool isResistanceExpression(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return false;
    if (_sleepContextSignals.any(normalized.contains)) return false;
    return _resistanceSignals.any(normalized.contains);
  }

  /// 원인을 특정하지 못한 답변인지 판정. 여기서 걸러지지 않으면 구체적인 원인으로 본다.
  static const List<String> _vagueSignals = [
    '모르겠',
    '몰라',
    '모르겄',
    '글쎄',
    '생각이많',
    '생각이너무많',
    '이유를모',
    '이유가없',
    '딱히없',
    '딱히',
    '그냥귀찮',
    '그냥싫',
    '그냥하기싫',
    '다하기싫',
    '다싫',
    '전부싫',
    '아무것도하기싫',
    '설명이안',
    '말로설명',
  ];

  static bool isVagueCauseAnswer(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return true;
    if (_vagueSignals.any(normalized.contains)) return true;
    // "그냥요", "몰겠어" 처럼 아주 짧고 내용이 없는 답변도 원인 불명으로 본다.
    if (normalized.length <= 6 &&
        (normalized.contains('그냥') ||
            normalized.contains('귀찮') ||
            normalized.contains('싫'))) {
      return true;
    }
    return false;
  }

  static String _todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// 오늘 이미 원인 진단 질문을 했는지 확인.
  static Future<bool> hasAskedDiagnosisToday() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_diagnosisAskedDateKey) == _todayKey();
  }

  /// 오늘 원인 진단 질문을 했다고 기록. 날짜 비교라 자정이 지나면 자동으로 풀린다.
  static Future<void> markDiagnosisAskedToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_diagnosisAskedDateKey, _todayKey());
  }
}
