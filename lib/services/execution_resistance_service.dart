import 'dart:math';

import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 실행 저항("하기 싫어", "귀찮아", "미루고 있어", "실패할까 봐 무서워")
/// 대응 흐름 판정 로직.
///
/// 흐름: 실행 저항 표현 → 원인 진단 질문(하루 1회) → 사용자 답변
///  - 원인이 구체적이면 기존 [하기 싫다 실행 개입 전략]으로 연결
///  - 원인이 불명확하면 더 캐묻지 말고 가장 작은 실행 조각 제안
///
/// 진단 질문은 API가 새로 만들지 않고 여기 정의된 문장 중 하나를 랜덤으로
/// 골라 프롬프트에 그대로 주입한다.
class ExecutionResistanceService {
  /// 원인 진단 질문을 마지막으로 던진 날짜(yyyy-MM-dd). 하루 1회 제한용.
  static const String _diagnosisAskedDateKey =
      'nyang_resistance_diagnosis_date';

  /// 원인 진단 질문 후보. 이 중 하나를 문장 그대로 사용한다.
  static const List<String> diagnosisQuestions = [
    '가장 번거롭게 느끼시는 부분이 무엇인지 궁금합니다.',
    '혹시 지금 가장 걸리는 부분이 있으실까요?',
    '딱 하나만 꼽는다면 어떤 부분이 가장 부담되시나요?',
    '어떤 부분이 제일 신경 쓰이시나요?',
    '지금 움직이기 어렵게 만드는 가장 큰 이유가 무엇일까요?',
  ];

  static final Random _random = Random();

  static String pickDiagnosisQuestion() =>
      diagnosisQuestions[_random.nextInt(diagnosisQuestions.length)];

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

  /// "미루"는 회고("미루던 거 다 했어요")에도 쓰이므로 지금 미루고 있다는
  /// 의도가 드러나는 형태만 신호로 본다.
  static const List<String> _resistanceSignals = [
    '하기싫',
    '하기가싫',
    '귀찮',
    '미루고싶',
    '미루고있',
    '미루게되',
    '미루게돼',
    '자꾸미루',
    '계속미루',
    '자꾸미뤄',
    '계속미뤄',
    '미루는중',
    '못하겠',
    '안하고싶',
    '시작하기싫',
    '시작을못',
    '실패할까봐',
    '망할까봐',
    '망할까봐무서',
    '결과보는게무서',
    '결과가무서',
    '결과확인',
    '결과보기무서',
    '결과를보기무서',
    '결과를확인하기무서',
    '잘안될까봐',
    '안될까봐',
    '기력이없',
    '기운이없',
    '손이안가',
    '엄두가안',
    '엄두안',
    '의욕이없',
    '의욕이안',
    '내키지않',
    '몸이안움직',
  ];

  /// 동사 자리를 비워 둔 저항 표현.
  ///
  /// "하기 싫어"를 통문자열로 찾고 있었다. 그래서 '하다'로 끝나는 동사만 걸렸다
  /// — 청소하기 싫어는 잡히고 방 치우기 싫어는 빠져나갔다. 하필 앱이 만들어 준
  /// 칩이 뒤쪽이었고, 원고 쓰기 싫어도 글 쓰기 싫어도 전부 통과했다.
  ///
  /// '~기 싫다'와 '못 ~겠다'는 어느 동사에나 붙는 자리라 목록으로는 못 채운다.
  /// 집중력 저하 쪽에서 부사 자리를 비워 둔 것과 같은 처방이다.
  static final List<RegExp> _resistancePatterns = [
    RegExp(r'[가-힣]기(?:가|는|도|를)?싫'),
    RegExp(r'못[가-힣]{1,3}겠'),
  ];

  /// 저항 단어를 부정하는 표현. ("안 귀찮아", "미루지 않았어")
  static const List<String> _negatedResistanceSignals = [
    '안귀찮',
    '귀찮지않',
    '하나도귀찮',
    '별로귀찮',
    '미루지않',
    '안미루',
  ];

  /// 위 패턴을 부정하는 형태. ("치우기 싫지 않아")
  static final List<RegExp> _negatedResistancePatterns = [
    RegExp(r'[가-힣]기(?:가|는|도|를)?싫(?:지|진|은|던)?않'),
  ];

  /// 완료 보고 표현. 저항 단어보다 뒤에 나오면 "미루던 걸 해냈다"는 뜻이다.
  static const List<String> _completionSignals = [
    '했어',
    '했다',
    '했습니다',
    '했네',
    '했음',
    '했지',
    '다했',
    '해냈',
    '끝냈',
    '끝났',
    '마쳤',
    '완료',
  ];

  /// 부분 실행 보고 표현. 전체 완료로 단정하지 않고 "시작/진행"으로 받아야
  /// 하는 턴에만 [완료/부분 실행 반응 원칙]을 프롬프트에 넣기 위해 쓴다.
  static const List<String> _partialExecutionSignals = [
    '시작했',
    '시작함',
    '해봤',
    '해보았',
    '조금했',
    '좀했',
    '살짝했',
    '반쯤',
    '절반',
    '진행했',
    '진행중',
    '손댔',
    '손댐',
    '열었',
    '켜봤',
  ];

  static int _firstIndexOf(String text, List<String> signals) {
    var found = -1;
    for (final signal in signals) {
      final index = text.indexOf(signal);
      if (index >= 0 && (found < 0 || index < found)) found = index;
    }
    return found;
  }

  /// 저항 표현이 처음 나오는 자리. 없으면 -1.
  static int _firstResistanceIndex(String text) {
    var found = _firstIndexOf(text, _resistanceSignals);
    for (final pattern in _resistancePatterns) {
      final match = pattern.firstMatch(text);
      if (match != null && (found < 0 || match.start < found)) {
        found = match.start;
      }
    }
    return found;
  }

  static int _lastIndexOf(String text, List<String> signals) {
    var found = -1;
    for (final signal in signals) {
      final index = text.lastIndexOf(signal);
      if (index > found) found = index;
    }
    return found;
  }

  /// 사용자의 말이 실행 저항 표현인지 판정.
  static bool isResistanceExpression(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return false;
    if (_sleepContextSignals.any(normalized.contains)) return false;
    if (_negatedResistanceSignals.any(normalized.contains)) return false;
    if (_negatedResistancePatterns.any((p) => p.hasMatch(normalized))) {
      return false;
    }

    final signalIndex = _firstResistanceIndex(normalized);
    if (signalIndex < 0) return false;

    // 저항 표현 뒤에 완료 표현이 오면 이미 해낸 일에 대한 회고다.
    // ("귀찮은 일 다 끝냈어요", "하기 싫었는데 했어요")
    // 반대 순서라면 지금의 저항으로 본다. ("다 했는데 이건 하기 싫어")
    final completionIndex = _lastIndexOf(normalized, _completionSignals);
    if (completionIndex > signalIndex) return false;

    return true;
  }

  /// 사용자가 어떤 일을 완료했거나 일부 실행했다고 보고하는 턴인지 판정.
  static bool isCompletionOrPartialExecutionReport(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return false;
    if (_completionSignals.any(normalized.contains)) return true;
    return _partialExecutionSignals.any(normalized.contains);
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
