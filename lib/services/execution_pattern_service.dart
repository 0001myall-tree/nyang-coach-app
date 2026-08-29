import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 이 사람이 어떻게 실행하는 사람인지, 앱이 기록에서 세어 한 줄로 만든다.
///
/// 코치에게 "패턴을 찾아 활용하라"고 시키면 없는 패턴을 지어낸다. 대부분의
/// 턴에는 볼 기록이 실려 있지도 않다. 그래서 세는 일은 앱이 하고, 코치는 그
/// 숫자를 보고 무슨 말을 할지만 정한다.
///
/// 마스터 프로필(모델이 요약해 채우는 자리)에는 넣지 않는다. 거기 적히면
/// 근거 없이 "저녁형"이 박힌 채 몇 주가 지나간다. 셀 수 있는 것은 셀 때마다
/// 세는 편이 낫다.
class ExecutionPatternService {
  const ExecutionPatternService._();

  /// 며칠을 볼지. 한 주면 요일 치우침 없이 리듬이 보인다.
  static const int windowDays = 7;

  /// 이만큼은 쌓여야 패턴이라고 말할 수 있다.
  static const int minRecordedDays = 3;

  /// 시간대 이야기를 하려면 시작 기록이 이만큼은 있어야 한다.
  ///
  /// 시작 시각은 ▶를 누른 사람에게만 남는다. 타이머 없이 체크만 하는 사람은
  /// 이 값이 비는데, 두어 개로 "늦게 시작하는 편"이라고 적으면 없는 패턴이 된다.
  static const int minStartSamples = 5;

  /// 프롬프트에 실을 블록. 셀 것이 모자라면 빈 문자열.
  static Future<String> promptBlock() async {
    final prefs = await SharedPreferences.getInstance();
    return blockFrom(prefs.getString('nyang_history'));
  }

  /// 기록 원문에서 바로 만든다. 테스트가 이 자리로 들어온다.
  static String blockFrom(String? historyRaw) {
    final records = _records(historyRaw);

    // 뜸한 사용자는 완료율로 평가할 것이 아니다. 그것만 말해준다.
    if (records.length <= 2) {
      if (records.isEmpty) return '';
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
최근 이레 중 계획을 적은 날이 ${records.length}일뿐.
→ 뜸한 사용자. 이 숫자로 재는 완료율은 뜻이 없음. 돌아오는 자리는 30분 안에 끝나는 루틴 하나면 충분.
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }
    if (records.length < minRecordedDays) return '';

    var planned = 0;
    var done = 0;
    var touched = 0;
    final startHours = <int>[];

    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        planned++;
        final isDone = task['done'] == true;
        final startedAt = DateTime.tryParse(
          task['startedAt']?.toString() ?? '',
        );
        if (isDone) done++;
        if (isDone || startedAt != null) touched++;
        if (startedAt != null) startHours.add(startedAt.hour);
      }
    }
    if (planned == 0) return '';

    final days = records.length;
    final rate = done / planned;
    final touchedRate = touched / planned;
    final planPerDay = planned / days;
    final donePerDay = done / days;

    final flags = <String>[];

    // 잘 돌아가고 있으면 여기서 끝난다.
    //
    // 다른 패턴과 함께 붙이면 고쳐줄 것이 없는 사람에게 고칠 거리가 하나 붙는다.
    // 완료율 75%인 사람에게 낮 조각을 권할 이유가 없다.
    if (rate >= 0.7) {
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%)
→ 안정형. 지금 방식이 이 사람에게 맞게 돌아가는 중.
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }

    // 무엇을 할지는 적지 않는다.
    //
    // 관찰만 주면 코치는 그날 대화에 맞는 수를 고른다. 여기서 한 수를 정해두면
    // 계획 이야기가 나올 때마다 같은 말이 나가고, 이미 갖고 있는 개입 열댓 가지가
    // 쓰이지 않는다.
    if (planPerDay >= 3 && planPerDay >= donePerDay * 2 && rate <= 0.5) {
      flags.add('계획 과다형 — 계획한 양이 해내는 양의 갑절');
    }
    // 완료율만 보면 안 하는 사람처럼 보이지만, 제일 어려운 시작은 매번 해내고 있다.
    if (touchedRate >= 0.7 && rate < 0.5) {
      flags.add('시작 꾸준형 — 완료율은 낮아도 손은 매번 대고 있음');
    }
    final timeLine = _startTimeLine(startHours, flags);

    if (flags.isEmpty) return '';

    return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%), 손댄 비율 ${(touchedRate * 100).round()}%$timeLine
→ ${flags.join(' / ')}
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
  }

  /// 주로 언제 시작하는지. 표본이 모자라면 빈 문자열.
  ///
  /// 완료 시각이 아니라 시작 시각을 본다. 코칭이 붙는 자리가 시작이라서다 —
  /// 오후 늦게야 첫 발을 떼는 사람과 아침에 시작해놓고 못 끝내는 사람에게 할
  /// 말은 서로 다르다.
  static String _startTimeLine(List<int> startHours, List<String> flags) {
    if (startHours.length < minStartSamples) return '';

    final morning = startHours.where((hour) => hour < 12).length;
    final late = startHours.where((hour) => hour >= 17).length;
    final total = startHours.length;

    if (late / total >= 0.6) {
      flags.add('늦게 시작하는 편 — 첫 발을 주로 오후 늦게 뗌');
      return '\n주로 시작하는 시간대: 오후 5시 이후 (${(late * 100 / total).round()}%)';
    }
    if (morning / total >= 0.6) {
      flags.add('아침형 — 첫 발을 주로 오전에 뗌');
      return '\n주로 시작하는 시간대: 오전 (${(morning * 100 / total).round()}%)';
    }
    return '';
  }

  static List<Map<String, dynamic>> _records(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final from = DateTime.now().subtract(const Duration(days: windowDays));
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }
}
