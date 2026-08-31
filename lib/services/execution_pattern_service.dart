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

  /// 이레 중 계획을 아예 안 적은 날이 이만큼이면 "뜸하게 온다"고 말해도 된다.
  /// 이레에 사흘 이하로 적는 사람이 여기 걸린다.
  ///
  /// 이틀로 잡았더니 그 주 사정으로 며칠 거른 사람까지 뜸한 사람이 됐고,
  /// 엿새로 잡으니 아무도 안 걸렸다 — 기록은 앱을 연 날에만 쌓여서, 엿새를
  /// 거르려면 매일 앱을 열면서 계획만 딱 하루 적어야 한다.
  static const int _rarelyPlansDays = 4;

  /// 무난형이라고 부르려면 완료율이 이만큼은 돼야 한다.
  ///
  /// 무난형은 "세 축 중 처지는 곳이 없다"는 말인데, 그 판정은 어느 유형에도
  /// 안 걸렸다는 것뿐이라 완료율을 안 본다. 그래서 문턱을 죄다 아슬아슬하게
  /// 비껴간 사람 - 다 해낸 날이 하루뿐이고, 하루 평균이 2.8개라 과다도 아니고,
  /// 손댄 비율은 낮아 시작 꾸준형도 아닌 - 이 완료율 18%로 "고르게 되고 있음"을
  /// 듣는다.
  static const double _evenEnoughRate = 0.4;

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

  /// [typeLabel]에 붙이는 고정 코칭 한마디. API를 안 쓰는 코치(프렌즈 등급)를
  /// 위한 것이라, 유형마다 미리 써둔 문장 중 하나를 그대로 돌려준다.
  ///
  /// "이대로도 괜찮아"로 끝내지 않는다 - 강점을 먼저 인정하되, 다음에 뭘
  /// 해보면 좋을지까지 한 문장에 담는다. 셀 것이 모자라면 null.
  static String? staticComment(String? historyRaw) {
    switch (typeLabel(historyRaw)) {
      case '안정형':
        return '지금 방식이 잘 맞고 있어. 여기서 하나 더 다지고 싶다면, 하나 끝낸 김에 내일 할 것 하나를 미리 적어두는 습관을 얹어봐.';
      case '편차형':
        return '의욕이 켜지면 계획부터 완료까지 한번에 몰아치고, 꺼지면 아예 손을 놓는 편이야. 그 자체가 나쁜 게 아니라 에너지가 몰아서 도는 리듬인 거고, 관건은 손 놓는 날에도 그 에너지가 완전히 0으로 안 떨어지게 제일 만만한 일 하나만 살짝 걸쳐두는 거야.';
      case '계획 편차형':
        return '계획을 세우는 날 자체가 들쭉날쭉해. 근데 일단 적어두면 웬만하면 다 해내잖아. 완벽하게 다 못 지킬까 봐 아예 안 적는 날이 있는 거니까, 하루에 딱 하나만 적는 걸로 부담을 줄여봐.';
      case '시작 편차형':
        return '계획은 꾸준히 쓰는데, 그중 며칠은 계획해두고도 손을 아예 안 대. 계획 세운 것만으로 이미 만족해버려서 정작 실행할 힘이 빠지는 걸 수도 있어. 할 수 있는 가짓수만 세우고, 그 계획을 실행하기 좋게 구체적으로 뭘 할지까지 세워봐. 귀찮더라도 실행률이 올라갈 거야.';
      case '계획 과다형':
        return '계획한 양이 해내는 양의 갑절이야. 의지가 아니라 양이 많은 거야. 다음엔 하루치를 절반으로 줄여서 다 끝내는 경험부터 만들어봐.';
      case '시작 꾸준형':
        return '완료율은 낮아도 손은 매번 대고 있어. 시작은 이미 되니까, 이번엔 한 번에 걸리는 시간을 짧게 잡아서 끝까지 가보는 것부터 해봐.';
      case '무난형':
        return '계획·시작·완료 중 특별히 처지는 곳 없이 고르게 가고 있어. 셋 다 골고루 된다는 건 지금도 나쁘지 않다는 거지만, 좀 더 발전하고 싶다면 더 과감히 시작하도록 자신감을 조금만 더 붙이면 나머지도 따라올 거야.';
      case '자유형':
        return '플래너에 뜸하게 오고 있어. 잘하고 못하고를 따질 단계는 아니고, 계획 세우는 거, 시작하는 거 너무 무서워하지 마.';
      case '벼락치기형':
        return '밤 10시 넘어서 여러 개를 한꺼번에 몰아서 시작하는 날이 잦아. 막판에도 결국 다 손을 대는 힘은 있다는 뜻이니까, 진짜 마감 하나만 보지 말고 중간중간 가상의 마감을 여러 개 나눠서 잡아봐. 그럼 막판까지 안 미루게 될 거야.';
      default:
        return null;
    }
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
    var noPlanDays = 0;
    var activeDays = 0;
    var crammedDays = 0;
    final startHours = <int>[];

    // 벼락치기: 밤 10시 이후에 시작한 서로 다른 일이 하루에 이 개수 이상.
    // 완료됐는지는 안 본다 - 그 시각까지 미뤄뒀다가 한꺼번에 손을 댔다는
    // 것 자체가 신호라, 다 끝냈어도 벼락치기는 벼락치기다.
    const lateNightHour = 22;
    const crammedTaskThreshold = 3;

    for (final record in records) {
      var dayPlanned = 0;
      var dayDone = 0;
      var dayTouched = 0;
      var lateNightStarts = 0;
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
        if (isDone || startedAt != null) {
          touched++;
          dayTouched++;
        }
        if (startedAt != null) {
          startHours.add(startedAt.hour);
          if (startedAt.hour >= lateNightHour) lateNightStarts++;
        }
      }
      if (lateNightStarts >= crammedTaskThreshold) crammedDays++;
      if (dayPlanned == 0) {
        noPlanDays++;
        continue;
      }
      if (dayDone == dayPlanned) fullDays++;
      // 손을 대긴 했는데 다 못 끝낸 날은 "편차형"의 아예 손 안 댄 날과 다르다.
      // 그건 시작 꾸준형이 이미 맡는 자리라, 여기서는 진짜 미착수만 센다.
      if (dayTouched == 0) {
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
    //
    // 단, 계획 안 세운 날은 이 비율 계산에 아예 안 들어간다(분모 자체가
    // planned라서). 계획을 어쩌다 세우고 세운 날만 다 해내는 사람도 그래서
    // 완료율이 100%로 나오는데, 이 사람은 안정형이 아니라 계획 편차형이다 -
    // 계획 자체를 자주 건너뛰면 안정형으로 덮지 않는다.
    if (rate >= 0.7 && noPlanDays < 2) {
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
    // 날마다 전부 아니면 전무인 사람. 이 사람에게 완료율은 눈금이 못 된다 —
    // 하는 날에는 어차피 100%라, 손대는 날이 하루 늘어도 숫자는 그대로다.
    final lastWeek = _activeDays(_records(historyRaw, weeksBack: 1));
    final improvedNote = (lastWeek > 0 && activeDays > lastWeek)
        ? '다만 지난 이레보다 해낸 날이 늘었음(${lastWeek}일 → $activeDays일). '
              '고칠 거리를 꺼내기 전에 이것부터 알아줄 것'
        : null;

    // 완료율만 보면 절반쯤 하는 사람으로 읽히는데, 날짜별로 보면 다 해낸 날과
    // 아예 손도 안 댄 날로 갈린다. 이 사람에게 계획을 줄이라고 하면 빗나간다 —
    // 하는 날에는 세 개도 다 끝내기 때문이다.
    //
    // 손을 대긴 했는데 다 못 끝낸 날은 이 갈래가 아니다 - 그건 시작은
    // 꾸준하다는 뜻이라 아래 '시작 꾸준형'이 이미 맡고 있고, 시작을 잘하는
    // 사람을 굳이 편차형(불안정하다는 인상)으로 묶어 깎아내릴 이유가 없다.
    final swings = fullDays >= 2 && zeroDays >= 2;

    // 계획 자체가 들쭉날쭉하지만, 일단 세운 날엔 거의 다 해낸다. 병목은
    // "계획을 쓰느냐"이지 실행력이 아니다 - 자기불일치 이론: 촘촘하고
    // 이상적인 계획을 다 못 지킬까 봐, 컨디션 안 좋은 날은 계획 쓰는 것
    // 자체를 회피하는 방어기제일 수 있다.
    final planGated = noPlanDays >= 2 && fullDays >= 2 && zeroDays < 2;

    if (planGated) {
      flags.add(
        '계획 편차형 — 계획을 세우는 날 자체가 들쭉날쭉함(이레 중 계획 없는 '
        '날 $noPlanDays일). 대신 일단 계획을 세운 날엔 거의 다 완료함. 병목은 '
        '실행력이 아니라 계획을 쓰느냐 마느냐 그 자체 - 계획을 다 못 지킬까 '
        '봐 아예 계획 쓰기를 피하는 것일 수 있음(자기불일치 이론)',
      );
      if (improvedNote != null) flags.add(improvedNote);
    } else if (swings) {
      if (noPlanDays < 2) {
        // 계획은 꾸준히 쓰는데, 그중 일부 날은 아예 손을 안 댄다. 계획을
        // 세운 순간 뇌가 이미 해낸 것처럼 느껴서(보상 예측 오류) 정작 실행
        // 동력이 그 자리에서 빠지는 경우일 수 있다.
        flags.add(
          '시작 편차형 — 계획은 꾸준히 쓰지만, 그중 일부 날은 계획해두고도 '
          '아예 손을 안 댐(아예 미착수). 세운 날엔 거의 다 완료하는 걸 보면 '
          '실행력 문제가 아니라, 계획을 세운 것만으로 이미 만족해버려서 '
          '정작 시작할 동력이 빠지는 경우일 수 있음(계획-실행 혼동, 보상 '
          '예측 오류)',
        );
      } else {
        // 계획도 들쭉날쭉, 완료도 들쭉날쭉 - 어느 한 지점을 병목으로 못
        // 좁힌다. 의욕 시스템이 켜지면 계획부터 완료까지 몰아치고, 꺼지면
        // 통째로 쉬는 리듬(BAS/BIS)에 가깝다.
        flags.add(
          '편차형 — 계획을 세우는 날도, 세운 날의 완료도 둘 다 들쭉날쭉함. '
          '하는 날엔 잡은 것을 다 해내고, 아예 손도 안 대는 날이 따로 있음. '
          '의욕이 몰릴 때 확 하고 소진되면 완전히 쉬는 리듬일 수 있음(BAS/BIS)',
        );
      }
      if (improvedNote != null) flags.add(improvedNote);
    }
    if (!swings && planPerDay >= 3 && planPerDay >= donePerDay * 2 && rate <= 0.5) {
      flags.add('계획 과다형 — 계획한 양이 해내는 양의 갑절');
    }
    // 완료율만 보면 안 하는 사람처럼 보이지만, 제일 어려운 시작은 매번 해내고 있다.
    if (touchedRate >= 0.7 && rate < 0.5) {
      flags.add('시작 꾸준형 — 완료율은 낮아도 손은 매번 대고 있음');
    }
    // 늦은 밤에 규칙적으로 하는 저녁형과는 다르다 - 저녁형은 시간대가
    // 퍼져 있고, 이건 자정 전 막판에 여러 개가 한꺼번에 몰린다. 하루만
    // 그러면 바쁜 날일 뿐이라, 반복돼야(이레 중 이틀 이상) 유형으로 본다.
    if (crammedDays >= 2) {
      flags.add(
        '벼락치기형 — 밤 10시 이후에 서로 다른 일 $crammedTaskThreshold개 이상을 '
        '한꺼번에 시작하는 날이 이레 중 $crammedDays일. 다 끝냈는지와 무관하게 '
        '시작 자체가 막판에 몰림',
      );
    }
    // 시간대는 유형과 따로 담는다.
    //
    // 한 목록에 섞으면 다른 유형이 하나도 안 걸린 사람에게 "아침형"이 유일한
    // 표시로 남고, 이름을 뽑아 쓰는 쪽([typeLabel])이 그걸 실행 유형으로
    // 집는다. 배지에 "실행 유형 : 아침형"이 뜨고 그 이름에는 처방도 없다.
    // 아침에 시작하느냐는 실행 방식을 가르는 축이 아니라 곁들이는 정보다.
    final timeFlags = <String>[];
    final timeLine = _startTimeLine(startHours, timeFlags);

    // 이름 붙는 유형에 하나도 안 걸려도 숫자는 이미 다 세어져 있다. 여기서
    // 그냥 버리면 애매하게 걸치는 사람(완료율 55%처럼 어느 문턱에도 안 닿는
    // 경우)은 정보 자체가 사라진다. 계획/시작/완료 세 축의 숫자는 그대로
    // 넘기고, 어디가 낮은지는 코치가 보고 판단하게 둔다.
    //
    // 다만 계획을 거의 안 적은 사람은 무난형으로 보내지 않는다. 무난형은 "세 축
    // 중 처지는 곳이 없다"는 말인데, 이 판정은 완료율만 보고 며칠이나 걸렀는지는
    // 안 본다. 그래서 계획도 안 쓰고 성적도 그저 그런 사람이 "고르게 가고 있다"는
    // 말을 듣는다. 병목이 계획 편차형과 같은 자리(계획을 쓰는 것)인데 "쓴 날엔
    // 다 해낸다"는 강점만 없는 경우라, 결이 가까운 자유형으로 보낸다.
    //
    // 문턱은 높게 잡는다. 자유형 문구가 "플래너에 뜸하게 온다"는 말이라, 이레에
    // 사나흘 적는 사람에게는 맞지 않는다. 여기 걸리는 건 이레에 한 번 적을까
    // 말까 한 사람뿐이다.
    //
    // 완료율이 바닥인 사람도 이리 온다. 적기는 적는데 거의 못 끝내는 쪽이라
    // 결도 가깝고, 무엇보다 그런 사람에게 "고르게 되고 있음"은 틀린 말이다.
    if (flags.isEmpty && (noPlanDays >= _rarelyPlansDays || rate < _evenEnoughRate)) {
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%), 손댄 비율 ${(touchedRate * 100).round()}%$timeLine
→ 자유형 — 이레 중 계획을 아예 안 적은 날이 $noPlanDays일. 완료율로 재기 전에 계획을 적는 리듬부터가 아직 자리를 안 잡음. 돌아오는 자리는 30분 안에 끝나는 것 하나면 충분.${timeFlags.isEmpty ? '' : ' / ${timeFlags.join(' / ')}'}
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }

    // "패턴 없음"이라고 하면 코치가 짚을 말이 마땅치 않아 병목 지적으로
    // 흐르기 쉽다. 세 축이 다 어중간한 것도 그 자체로 하나의 유형(무난형)
    // 이라 이름을 붙여, 지적거리가 아니라 "고르게 가는 중"으로 먼저 읽히게
    // 한다.
    if (flags.isEmpty) {
      return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%), 손댄 비율 ${(touchedRate * 100).round()}%$timeLine
→ 무난형 — 계획(이레 중 ${days - noPlanDays}일 적음) / 시작(손댄 비율 ${(touchedRate * 100).round()}%) / 완료(완료율 ${(rate * 100).round()}%) 세 축 중 특별히 처지는 곳 없이 고르게 되고 있음. 이걸 먼저 알아줄 것. 굳이 하나를 더 다지고 싶다면 세 축 중 가장 낮은 지점에 아주 가벼운 제안 하나만 곁들이되, 지적처럼 들리지 않게 할 것.${timeFlags.isEmpty ? '' : ' / ${timeFlags.join(' / ')}'}
- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.''';
    }

    return '''

[실행 패턴 - 앱이 최근 이레 기록에서 센 값]
계획이 실제로 끝나게 돕는 자리. 계획을 얼마나 잡을지, 한 가지에 걸리는 시간을 어떻게 어림할지, 언제 첫 발을 뗄지, 무엇을 루틴으로 굳힐지 — 그날 대화에 맞는 것을 골라 쓸 것.
하루 평균 계획 ${planPerDay.toStringAsFixed(1)}개 / 완료 ${donePerDay.toStringAsFixed(1)}개 (완료율 ${(rate * 100).round()}%), 손댄 비율 ${(touchedRate * 100).round()}%$timeLine
→ ${[...flags, ...timeFlags].join(' / ')}
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
