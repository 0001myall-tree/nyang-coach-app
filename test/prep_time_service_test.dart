import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/prep_time_service.dart';

/// "10:10"을 자정부터의 분으로. 기대값을 읽기 쉽게 쓰려고 둔다.
int hm(int hour, int minute) => hour * 60 + minute;

void main() {
  group('역산', () {
    test('출발 시각과 준비 시간에서 준비 시작이 나온다', () {
      // 사용자가 실제로 겪은 그 대화. 10:10 출발에 준비 30분이면 9:40이다.
      final plan = PrepPlan(
        departure: 610, // 10:10
        prepMinutes: 30,
        bufferMinutes: 0,
      );
      expect(plan.prepStart, hm(9, 40));
    });

    test('여유 시간을 더해 앞당긴다', () {
      final plan = PrepPlan(departure: 610, prepMinutes: 40);
      expect(plan.bufferMinutes, 15);
      expect(plan.prepStart, hm(9, 15));
    });

    test('한 시간을 빼도 자기가 앞서 말한 시각이 아니라 출발 시각에서 뺀다', () {
      final plan = PrepPlan(departure: 610, prepMinutes: 60, bufferMinutes: 0);
      expect(plan.prepStart, hm(9, 10));
    });

    test('1시간 20분처럼 시간을 걸쳐 빼도 맞는다', () {
      final plan = PrepPlan(
        departure: hm(8, 30),
        prepMinutes: 80,
        bufferMinutes: 0,
      );
      expect(plan.prepStart, hm(7, 10));
    });

    test('약속 시각과 이동 시간에서 출발 시각이 나온다', () {
      final plan = PrepPlan(appointment: hm(14, 0), travelMinutes: 60);
      expect(plan.resolvedDeparture, hm(13, 0));
    });

    test('약속 시각만 있고 이동을 모르면 출발 시각을 지어내지 않는다', () {
      final plan = PrepPlan(appointment: hm(14, 0));
      expect(plan.resolvedDeparture, isNull);
      expect(plan.prepStart, isNull);
    });

    test('사용자가 말한 출발 시각이 약속에서 역산한 것보다 우선한다', () {
      // 본인이 아는 사정이 있다. 추정으로 덮지 않는다.
      final plan = PrepPlan(
        appointment: hm(14, 0),
        travelMinutes: 60,
        departure: hm(12, 30),
      );
      expect(plan.resolvedDeparture, hm(12, 30));
    });

    test('약속에서 출발, 출발에서 준비 시작까지 한 번에 이어진다', () {
      final plan = PrepPlan(
        appointment: hm(10, 0),
        travelMinutes: 30,
        prepMinutes: 40,
      );
      expect(plan.resolvedDeparture, hm(9, 30));
      expect(plan.prepStart, hm(8, 35));
    });

    test('자정을 넘어가면 전날 시각으로 돌려주고 표시해준다', () {
      final plan = PrepPlan(
        departure: hm(6, 0),
        prepMinutes: 90,
        bufferMinutes: 0,
      );
      expect(plan.prepStart, hm(4, 30));
      expect(plan.crossesMidnight, isFalse);

      final dawn = PrepPlan(
        departure: hm(0, 30),
        prepMinutes: 60,
        bufferMinutes: 0,
      );
      expect(dawn.prepStart, hm(23, 30));
      expect(dawn.crossesMidnight, isTrue);
    });
  });

  group('모자란 정보', () {
    test('아무것도 없으면 기준 시각부터 묻는다', () {
      expect(const PrepPlan().missing, [PrepMissing.anchorTime]);
    });

    test('약속만 알면 준비를 먼저 묻고 이동을 묻는다', () {
      // 계산은 이동이 먼저 필요하지만, 사람이 물은 순서는 준비가 먼저다.
      expect(PrepPlan(appointment: hm(10, 0)).missing, [
        PrepMissing.prep,
        PrepMissing.travel,
      ]);
    });

    test('출발 시각을 알면 이동은 묻지 않는다', () {
      expect(PrepPlan(departure: hm(10, 10)).missing, [PrepMissing.prep]);
    });

    test('다 알면 더 묻지 않는다', () {
      expect(PrepPlan(departure: hm(10, 10), prepMinutes: 40).missing, isEmpty);
    });
  });

  group('시각 읽기', () {
    test('여러 표기를 읽는다', () {
      expect(parseClock('10시 10분에 나가야 해')?.minutes, hm(10, 10));
      expect(parseClock('10:10에 나가야 해')?.minutes, hm(10, 10));
      expect(parseClock('10시에 약속이야')?.minutes, hm(10, 0));
      expect(parseClock('10시반에 나가')?.minutes, hm(10, 30));
    });

    test('오전 오후를 반영한다', () {
      expect(parseClock('오후 2시 약속')?.minutes, hm(14, 0));
      expect(parseClock('저녁 7시에 만나')?.minutes, hm(19, 0));
      expect(parseClock('오전 9시')?.minutes, hm(9, 0));
      expect(parseClock('새벽 5시 비행기')?.minutes, hm(5, 0));
    });

    test('낮 12시와 밤 12시를 구분한다', () {
      expect(parseClock('오후 12시')?.minutes, hm(12, 0));
      expect(parseClock('오전 12시')?.minutes, hm(0, 0));
    });

    test('오전 오후를 말했는지 알려준다', () {
      expect(parseClock('오후 2시')?.meridiemKnown, isTrue);
      expect(parseClock('2시')?.meridiemKnown, isFalse);
    });

    test('시각이 없으면 지어내지 않는다', () {
      expect(parseClock('그냥 좀 늦을 것 같아'), isNull);
      expect(parseClock('30분 걸려'), isNull);
    });
  });

  group('걸리는 시간 읽기', () {
    test('분과 시간을 읽는다', () {
      expect(parseDuration('30분 정도 걸려'), 30);
      expect(parseDuration('1시간 걸려'), 60);
      expect(parseDuration('한시간쯤'), 60);
      expect(parseDuration('1시간 20분'), 80);
      expect(parseDuration('한 시간 반'), 90);
      expect(parseDuration('40분쯤'), 40);
    });

    test('시각에 붙은 분을 걸리는 시간으로 읽지 않는다', () {
      // "10시 10분에 나가야 해"에서 10분을 준비 시간으로 읽으면 안 된다.
      expect(parseDuration('10시 10분에 나가야 해'), isNull);
      expect(parseDuration('10시 30분에 약속'), isNull);
    });

    test('시각과 걸리는 시간이 같이 있으면 걸리는 시간만 읽는다', () {
      expect(parseDuration('10시에 나가는데 준비는 40분 걸려'), 40);
    });

    test('없으면 지어내지 않는다', () {
      expect(parseDuration('잘 모르겠어'), isNull);
    });
  });

  group('읽는 말로 바꾸기', () {
    test('시각을 사용자가 쓴 방식대로 쓴다', () {
      expect(formatClock(hm(9, 20)), '9시 20분');
      expect(formatClock(hm(9, 0)), '9시');
      // 사용자가 오전/오후를 말했을 때만 붙인다.
      expect(formatClock(hm(13, 0), withMeridiem: true), '오후 1시');
      expect(formatClock(hm(9, 20), withMeridiem: true), '오전 9시 20분');
    });

    test('걸리는 시간을 읽기 좋게 쓴다', () {
      expect(formatDuration(40), '40분');
      expect(formatDuration(60), '1시간');
      expect(formatDuration(80), '1시간 20분');
    });
  });

  group('오전 오후 가려내기', () {
    test('지금에서 가장 가까운 쪽으로 읽는다', () {
      // 오후 2시에 "이따가 5시"라고 하면 오후 5시다.
      final at14 = DateTime(2026, 8, 9, 14, 0);
      expect(parseClock('이따가 5시에 만나', now: at14)?.minutes, hm(17, 0));
      // 오전 9시에 "10시"는 오전 10시다.
      final at9 = DateTime(2026, 8, 9, 9, 0);
      expect(parseClock('10시에 나가야 해', now: at9)?.minutes, hm(10, 0));
      // 저녁 8시에 "10시"는 밤 10시다.
      final at20 = DateTime(2026, 8, 9, 20, 0);
      expect(parseClock('10시에 자야지', now: at20)?.minutes, hm(22, 0));
      // 밤 11시에 "1시"는 오후 1시가 아니라 두 시간 뒤 새벽 1시다.
      final at23 = DateTime(2026, 8, 9, 23, 0);
      expect(parseClock('1시에 도착해', now: at23)?.minutes, hm(1, 0));
    });

    test('사용자가 밝힌 오전 오후가 언제나 우선한다', () {
      final at14 = DateTime(2026, 8, 9, 14, 0);
      expect(parseClock('오전 10시에 만나', now: at14)?.minutes, hm(10, 0));
      expect(parseClock('새벽 5시 비행기', now: at14)?.minutes, hm(5, 0));
    });

    test('다른 날 얘기에는 지금과의 거리를 쓰지 않는다', () {
      // 하루 뒤 오전이 늘 더 가까워서, 거리로 재면 "내일 10시"가 밤 10시가 된다.
      final at9 = DateTime(2026, 8, 9, 9, 0);
      expect(parseClock('내일 10시에 나가야 해', now: at9)?.minutes, hm(10, 0));
      // 새벽에 잡을 리 없는 시각만 오후로 본다.
      expect(parseClock('내일 5시에 만나', now: at9)?.minutes, hm(17, 0));
    });

    test('오후 1시 약속이 0시로 새지 않는다', () {
      final at10 = DateTime(2026, 8, 9, 10, 0);
      final talk = _Talk(now: at10);
      talk.say('1시에 약속 있어');
      expect(talk.plan!.appointment, hm(13, 0));
      talk.say('가는 데 10분');
      talk.say('준비 30분');
      // 예전엔 여기서 "0시 15분"이 나왔다.
      expect(talk.plan!.prepStart, hm(12, 5));
      expect(
        formatClock(talk.plan!.prepStart!, withMeridiem: true),
        '오후 12시 5분',
      );
    });
  });

  group('대화 흐름', () {
    test('실제로 틀렸던 그 대화가 이제 맞는다', () {
      final talk = _Talk();
      talk.say('내일 10시 10분에는 문을 열고 나가야 하는데, 몇 시쯤 일어나야 할까?');
      expect(talk.plan!.departure, hm(10, 10));
      expect(talk.plan!.prepMinutes, isNull, reason: '아직 준비 시간을 안 말했다');
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('머리 감는데 30분 정도 걸려.');
      expect(talk.plan!.prepMinutes, 30);
      // 코치가 "8시"라고 했던 자리. 10:10 - 30분 - 여유 15분 = 9:25.
      expect(talk.plan!.prepStart, hm(9, 25));
      expect(talk.lastAsked, isNull, reason: '다 알았으니 더 묻지 않는다');
    });

    test('약속 시각으로 말해도 이동을 물어 출발 시각을 구한다', () {
      final talk = _Talk();
      talk.say('내일 2시에 약속 있어');
      // 새벽 2시에 약속을 잡을 리는 없다.
      expect(talk.plan!.appointment, hm(14, 0));
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('거기까지 30분 걸려');
      expect(talk.plan!.resolvedDeparture, hm(13, 30));
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('씻고 나가는 데 보통 40분');
      expect(talk.plan!.prepStart, hm(12, 35));
    });

    test('한 마디에 다 말하면 아무것도 묻지 않는다', () {
      final talk = _Talk();
      talk.say('오후 3시 약속인데 가는 데 20분 걸려');
      expect(talk.plan!.resolvedDeparture, hm(14, 40));
      talk.say('준비는 1시간');
      expect(talk.plan!.prepStart, hm(13, 25));
      expect(talk.lastAsked, isNull);
    });

    test('시각을 안 말하고 물어봐도 대화를 열고 시각부터 묻는다', () {
      final talk = _Talk();
      talk.say('몇 시에 일어나야 할까?');
      expect(talk.plan, isNotNull);
      expect(talk.lastAsked, PrepMissing.anchorTime);
    });

    test('표시 없는 시간은 직전에 물어본 칸으로 들어간다', () {
      final talk = _Talk();
      talk.say('7시에 나가야 해');
      expect(talk.lastAsked, PrepMissing.prep);
      talk.say('40분쯤');
      expect(talk.plan!.prepMinutes, 40);
      expect(talk.plan!.travelMinutes, isNull);
    });

    test('까지 가야 한다고 말하면 도착 시각으로 읽는다', () {
      final talk = _Talk();
      talk.say('내일 오후 1시까지 신촌 가야 하는데 몇시부터 준비해야 할까?');
      expect(talk.plan, isNotNull, reason: '준비 역산 대화로 열려야 한다');
      expect(talk.plan!.appointment, hm(13, 0));
      expect(talk.plan!.departure, isNull, reason: '1시는 도착 시각이지 출발이 아니다');
      // 준비를 물었으니 준비부터 묻는다.
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('씻고 밥 먹고 나가는 데 50분');
      expect(talk.plan!.prepMinutes, 50);
      expect(talk.lastAsked, PrepMissing.travel);

      talk.say('신촌까지 40분 걸려');
      expect(talk.plan!.resolvedDeparture, hm(12, 20));
      expect(talk.plan!.prepStart, hm(11, 15));
    });

    test('한 문장에 도착 시각과 출발을 묻는 말이 같이 있어도 헷갈리지 않는다', () {
      final talk = _Talk();
      talk.say('내일 오후 1시까지 신촌가야 하는데 집에서 몇시에 나갈까?');
      expect(
        talk.plan!.appointment,
        hm(13, 0),
        reason: '뒤에 나오는 "집에서 나갈까"에 끌려가면 안 된다',
      );
      expect(talk.plan!.departure, isNull);
      expect(talk.lastAsked, PrepMissing.travel);

      talk.say('지하철로 35분');
      expect(talk.plan!.resolvedDeparture, hm(12, 25));
    });

    test('까지 나가야는 출발 시각으로 읽는다', () {
      final talk = _Talk();
      talk.say('10시까지는 나가야 해');
      expect(talk.plan!.departure, hm(10, 0));
      expect(talk.plan!.appointment, isNull);
    });

    test('시각을 말 안 하고 할 일 이름만 불러도 할 일 탭 시각을 쓴다', () {
      final talk = _Talk(
        tasks: [PrepTaskTime(name: '약속', minutes: hm(18, 0))],
      );

      talk.say("'약속' 준비하기 귀찮아..");
      expect(talk.plan, isNull, reason: '푸념만으로 역산을 시작하지 않는다');

      talk.say("몇시부터 '약속' 나갈 준비할까?");
      expect(talk.plan!.appointment, hm(18, 0), reason: '할 일 탭의 6시를 가져온다');
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('거기까지 30분');
      expect(talk.plan!.resolvedDeparture, hm(17, 30));
      talk.say('준비는 40분쯤');
      expect(talk.plan!.prepStart, hm(16, 35));
    });

    test('할 일 이름이 나가는 일이면 출발 시각으로 읽는다', () {
      final talk = _Talk(
        tasks: [PrepTaskTime(name: '집에서 나가기', minutes: hm(9, 0))],
      );
      talk.say('몇시부터 집에서 나가기 준비할까?');
      expect(talk.plan!.departure, hm(9, 0));
      expect(talk.plan!.appointment, isNull);
    });

    test('부르지 않은 할 일 시각을 끌어오지 않는다', () {
      final talk = _Talk(
        tasks: [PrepTaskTime(name: '치과', minutes: hm(18, 0))],
      );
      talk.say('몇시부터 준비할까?');
      expect(talk.plan!.appointment, isNull);
      expect(talk.lastAsked, PrepMissing.anchorTime);
    });

    test('몇시부터 무슨무슨 준비할까 처럼 사이에 말이 끼어도 알아듣는다', () {
      final talk = _Talk();
      talk.say("몇시부터 '약속' 나갈 준비할까?");
      expect(talk.plan, isNotNull);
      expect(talk.lastAsked, PrepMissing.anchorTime);
    });

    test('만나야 한다고 하면 도착 시각으로 읽는다', () {
      final talk = _Talk();
      talk.say('이따가 5시에 집 근처에서 맞선남 만나야 하는데 일하다가 몇시부터 준비할까?');
      expect(talk.plan!.appointment, hm(5, 0));
      // "집 근처에서"가 "집에서"로 잘못 읽히면 도착 시각이 출발 시각이 된다.
      expect(talk.plan!.departure, isNull);
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('씻고 옷 갈아입는 데 30분');
      expect(talk.plan!.prepMinutes, 30);
      expect(talk.lastAsked, PrepMissing.travel);

      talk.say('집 근처라 10분이면 가');
      expect(talk.plan!.resolvedDeparture, hm(4, 50));
      expect(talk.plan!.prepStart, hm(4, 5));
    });

    test('준비 시간을 안 들으면 어떤 시각도 내놓지 않는다', () {
      // 준비에 걸리는 시간은 사람마다 다르다. 기본값을 두면 안 물어보고 답한다.
      final talk = _Talk();
      talk.say('10시 10분에 나가야 해');
      expect(talk.plan!.prepStart, isNull);
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('음 글쎄');
      expect(talk.plan!.prepStart, isNull, reason: '얼버무려도 지어내지 않는다');
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('한 30분?');
      expect(talk.plan!.prepStart, hm(9, 25));
    });

    test('이동 시간도 기본값이 없다', () {
      final talk = _Talk();
      talk.say('오후 3시에 약속 있어');
      expect(talk.plan!.resolvedDeparture, isNull);
      expect(talk.plan!.missing, contains(PrepMissing.travel));
    });

    test('준비를 물으면 준비부터 묻는다', () {
      final talk = _Talk(now: DateTime(2026, 8, 9, 13, 0));
      talk.say('오후 5시 약속 준비 같이 해줘');
      expect(talk.plan!.appointment, hm(17, 0));
      // 사용자가 준비를 물었는데 이동부터 되물으면 딴소리로 들린다.
      expect(talk.lastAsked, PrepMissing.prep);

      talk.say('평소엔 40분쯤 걸려');
      expect(talk.lastAsked, PrepMissing.travel);

      talk.say('집 앞이라 5분이면 가');
      expect(talk.plan!.prepStart, hm(16, 0));
    });

    test('나가는 시각만 물으면 준비는 묻지 않는다', () {
      final talk = _Talk(now: DateTime(2026, 8, 9, 13, 0));
      talk.say('오후 5시 약속인데 몇시에 나가야 할까?');
      expect(talk.lastAsked, PrepMissing.travel);

      talk.say('30분 걸려');
      expect(talk.plan!.resolvedDeparture, hm(16, 30));
      expect(talk.lastAsked, isNull, reason: '묻지도 않은 준비까지 캐지 않는다');
    });

    test('준비와 무관한 대화에서는 켜지지 않는다', () {
      final talk = _Talk();
      talk.say('오늘 너무 피곤해');
      expect(talk.plan, isNull);
      talk.say('30분만 쉬고 싶다');
      expect(talk.plan, isNull);
    });

    test('시각이 있어도 나가는 얘기가 아니면 켜지지 않는다', () {
      final talk = _Talk();
      talk.say('어제 11시에 잤어');
      expect(talk.plan, isNull);
    });
  });
}

/// 대화를 한 줄씩 흘려 넣는다. 화면 없이 실제 흐름을 그대로 따라간다.
class _Talk {
  _Talk({this.tasks = const [], this.now});

  final List<PrepTaskTime> tasks;
  final DateTime? now;
  PrepPlan? plan;
  PrepMissing? lastAsked;

  void say(String text) {
    final next = mergeUtterance(
      plan: plan,
      lastAsked: lastAsked,
      text: text,
      taskTimes: tasks,
      now: now,
    );
    if (next != null) plan = next;
    lastAsked = plan?.missing.isEmpty ?? true ? null : plan!.missing.first;
  }
}
