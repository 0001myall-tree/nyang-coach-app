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

  /// 이번 이레와 지난 이레에 하루라도 해낸 날이 며칠인지.
  ///
  /// 편차형에게 진도를 재는 눈금이다. 완료율로는 안 보인다 — 하는 날에는
  /// 어차피 100%라, 손대는 날이 하루 늘어도 숫자가 그대로다.
  static Future<({int thisWeek, int lastWeek})> activeDayTrend() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('nyang_history');
    return (
      thisWeek: _activeDays(_records(raw)),
      lastWeek: _activeDays(_records(raw, weeksBack: 1)),
    );
  }

  /// 유형 이름만 짧게. 기록 화면에 배지처럼 붙일 때 쓴다. 셀 것이 모자라면
  /// null.
  ///
  /// [blockFrom]이 만드는 "→ 이름 — 설명" 줄에서 이름만 뽑는다. 판단
  /// 기준을 두 곳에 따로 두면 어긋나기 쉬워서, 새로 계산하지 않고 그
  /// 문장에서 그대로 가져온다.
  static String? typeLabel(String? historyRaw) {
    final block = blockFrom(historyRaw);
    if (block.isEmpty) return null;
    final match = RegExp(r'→ ([^—.]+)').firstMatch(block);
    final name = match?.group(1)?.trim();
    return (name == null || name.isEmpty) ? null : name;
  }

  /// 기록 원문에서 바로 만든다. 테스트가 이 자리로 들어온다.
  static String blockFrom(String? historyRaw) {
    final records = _records(historyRaw);

    // 계획을 잘 안 적는(플래너에 뜸하게 오는) 사람은 완료율로 평가할 것이
    // 아니다. 그것만 말해준다. 다른 유형이 전부 "-형"이라 이 사람에게도
    // 이름을 붙인다 - 정해진 틀 없이 오는 사람이라 자유형.
    if (records.length <= 2) {
      if (records.isEmpty) return '';
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
최근 이레 중 계획을 적은 날이 ${records.length}일뿐.
→ 자유형 — 플래너에 뜸하게 옴. 이 숫자로 재는 완료율은 뜻이 없음. 돌아오는 자리는 30분 안에 끝나는 루틴 하나면 충분.
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }
    if (records.length < minRecordedDays) return '';

    var planned = 0;
    var done = 0;
    var touched = 0;
    var fullDays = 0;
    var zeroDays = 0;
    var activeDays = 0;
    final startHours = <int>[];

    for (final record in records) {
      var dayPlanned = 0;
      var dayDone = 0;
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map) continue;
        dayPlanned++;
        if (task['done'] == true) dayDone++;
        planned++;
        final isDone = task['done'] == true;
        final startedAt = DateTime.tryParse(
          task['startedAt']?.toString() ?? '',
        );
        if (isDone) done++;
        if (isDone || startedAt != null) touched++;
        if (startedAt != null) startHours.add(startedAt.hour);
      }
      if (dayPlanned == 0) continue;
      if (dayDone == dayPlanned) fullDays++;
      if (dayDone == 0) {
        zeroDays++;
      } else {
        activeDays++;
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
    // 날마다 전부 아니면 전무인 사람.
    //
    // 완료율만 보면 절반쯤 하는 사람으로 읽히는데, 날짜별로 보면 다 해낸 날과
    // 손도 안 댄 날로 갈린다. 이 사람에게 계획을 줄이라고 하면 빗나간다 —
    // 하는 날에는 세 개도 다 끝내기 때문이다. 그래서 이 표시가 붙으면 양을
    // 두고 하는 판단은 접어둔다.
    final swings = fullDays >= 2 && zeroDays >= 2;
    if (swings) {
      flags.add('편차형 — 하는 날엔 잡은 것을 다 해내고, 아예 손도 안 대는 날이 따로 있음. 양이 걸린 것이 아님');
      // 나아지고 있으면 그것부터 말한다.
      //
      // 이 사람에게 완료율은 눈금이 못 된다. 하는 날에는 어차피 100%라,
      // 손대는 날이 하루 늘어도 숫자는 그대로다. 늘어난 것을 볼 수 있는
      // 자리는 여기뿐이고, 늘었다는 말은 어떤 조언보다 잘 듣는다.
      final lastWeek = _activeDays(_records(historyRaw, weeksBack: 1));
      if (lastWeek > 0 && activeDays > lastWeek) {
        flags.add(
          '다만 지난 이레보다 해낸 날이 늘었음(${lastWeek}일 → $activeDays일). '
          '고칠 거리를 꺼내기 전에 이것부터 알아줄 것',
        );
      }
    }
    if (!swings && planPerDay >= 3 && planPerDay >= donePerDay * 2 && rate <= 0.5) {
      flags.add('계획 과다형 — 계획한 양이 해내는 양의 갑절');
    }
    // 완료율만 보면 안 하는 사람처럼 보이지만, 제일 어려운 시작은 매번 해내고 있다.
    if (touchedRate >= 0.7 && rate < 0.5) {
      flags.add('시작 꾸준형 — 완료율은 낮아도 손은 매번 대고 있음');
    }
    final timeLine = _startTimeLine(startHours, flags);

    // 이름 붙는 유형에 하나도 안 걸려도 숫자는 이미 다 세어져 있다. 여기서
    // 그냥 버리면 애매하게 걸치는 사람(완료율 55%처럼 어느 문턱에도 안 닿는
    // 경우)은 정보 자체가 사라진다. 계획/시작/완료 세 축의 숫자는 그대로
    // 넘기고, 어디가 낮은지는 코치가 보고 판단하게 둔다.
    //
    // "패턴 없음"이라고 하면 코치가 짚을 말이 마땅치 않아 병목 지적으로
    // 흐르기 쉽다. 세 축이 다 어중간한 것도 그 자체로 하나의 유형(무난형)
    // 이라 이름을 붙여, 지적거리가 아니라 "고르게 가는 중"으로 먼저 읽히게
    // 한다.
    if (flags.isEmpty) {
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%), 손댄 비율 ${(touchedRate * 100).round()}%$timeLine
→ 무난형 — 계획(이레 중 $days일 기록) / 시작(손댄 비율 ${(touchedRate * 100).round()}%) / 완료(완료율 ${(rate * 100).round()}%) 세 축 중 특별히 처지는 곳 없이 고르게 되고 있음. 이걸 먼저 알아줄 것. 굳이 하나를 더 다지고 싶다면 세 축 중 가장 낮은 지점에 아주 가벼운 제안 하나만 곁들이되, 지적처럼 들리지 않게 할 것.
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }

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

  static List<Map<String, dynamic>> _records(String? raw, {int weeksBack = 0}) {
    if (raw == null || raw.isEmpty) return const [];
    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
    final from = DateTime.now().subtract(
      Duration(days: windowDays * (1 + weeksBack)),
    );
    final until = DateTime.now().subtract(
      Duration(days: windowDays * weeksBack),
    );
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is! Map) continue;
      final date = DateTime.tryParse(item['date']?.toString() ?? '');
      if (date == null || date.isBefore(from)) continue;
      if (weeksBack > 0 && !date.isBefore(until)) continue;
      out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  /// 하루라도 해낸 날이 며칠인지. 편차형에게는 이게 진도를 재는 눈금이다.
  ///
  /// 완료율로는 나아지는 것이 안 보인다. 하는 날에는 어차피 100%라, 손대는
  /// 날이 하루 늘어도 완료율은 그대로다. 세어야 할 것은 며칠에 손댔느냐다.
  static int _activeDays(List<Map<String, dynamic>> records) {
    var count = 0;
    for (final record in records) {
      for (final task in (record['tasks'] as List?) ?? const []) {
        if (task is! Map || task['done'] != true) continue;
        count++;
        break;
      }
    }
    return count;
  }
}
