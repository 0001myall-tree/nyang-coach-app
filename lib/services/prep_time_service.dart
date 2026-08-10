/// 약속 시각에서 거꾸로 세어 언제 준비를 시작할지 계산한다.
///
/// 모델에게 맡기면 틀린다. 10시 10분에 나가야 한다는 사용자에게 "한 시간 전인
/// 8시"라고 답한 적이 있다. 출발 시각이 아니라 자기가 앞서 말한 9시에서 뺀
/// 것이다. 오답 위에 오답을 쌓는 거라 프롬프트로는 막히지 않는다.
///
/// 그래서 숫자는 전부 여기서 낸다. 모델은 말에서 값을 주워오고 말하는 일만 한다.
library;

/// 하루를 이렇게 한 줄로 본다.
///
///   준비 시작 ──준비──▶ 출발 ──이동──▶ 약속
///
/// 점 하나와 사이 시간을 알면 나머지 점이 나온다. 사용자가 약속 시각을 말했든
/// 출발 시각을 말했든 계산은 같다.
class PrepPlan {
  /// 약속(도착) 시각. 자정부터의 분.
  final int? appointment;

  /// 집에서 나서는 시각. 자정부터의 분.
  final int? departure;

  /// 이동에 걸리는 분.
  final int? travelMinutes;

  /// 씻고 챙기는 데 걸리는 분.
  final int? prepMinutes;

  /// 오늘따라 안 풀릴 때를 위한 여유. 사용자에게 감추지 않는다.
  ///
  /// 늦는 쪽 손해가 일찍 준비하는 쪽 손해보다 훨씬 크다. 게다가 사람은
  /// 지난 시간을 떠올릴 때도 잘 풀린 날 쪽으로 줄여 말한다.
  final int bufferMinutes;

  /// 시각에 오전/오후가 붙어 있었는지. 답할 때 같은 표현을 쓰려고 들고 있다.
  final bool meridiemKnown;

  /// 사용자가 알고 싶어한 것. 물어볼 순서와 어디까지 물을지가 여기서 갈린다.
  final PrepGoal goal;

  const PrepPlan({
    this.appointment,
    this.departure,
    this.travelMinutes,
    this.prepMinutes,
    this.bufferMinutes = 15,
    this.meridiemKnown = false,
    this.goal = PrepGoal.prepStart,
  });

  PrepPlan copyWith({
    int? appointment,
    int? departure,
    int? travelMinutes,
    int? prepMinutes,
    int? bufferMinutes,
    bool? meridiemKnown,
    PrepGoal? goal,
  }) {
    return PrepPlan(
      appointment: appointment ?? this.appointment,
      departure: departure ?? this.departure,
      travelMinutes: travelMinutes ?? this.travelMinutes,
      prepMinutes: prepMinutes ?? this.prepMinutes,
      bufferMinutes: bufferMinutes ?? this.bufferMinutes,
      meridiemKnown: meridiemKnown ?? this.meridiemKnown,
      goal: goal ?? this.goal,
    );
  }

  /// 약속 시각과 이동 시간이 있으면 출발 시각이 나온다.
  /// 사용자가 출발 시각을 직접 말했으면 그게 우선이다. 본인 말이 추정보다 낫다.
  int? get resolvedDeparture {
    if (departure != null) return departure;
    if (appointment != null && travelMinutes != null) {
      return _wrap(appointment! - travelMinutes!);
    }
    return null;
  }

  /// 출발 시각에서 준비 시간과 여유를 빼면 준비를 시작할 시각이 나온다.
  int? get prepStart {
    final start = resolvedDeparture;
    if (start == null || prepMinutes == null) return null;
    return _wrap(start - prepMinutes! - bufferMinutes);
  }

  /// 준비 시작이 전날로 넘어가는지. 새벽 비행기 같은 경우다.
  bool get crossesMidnight {
    final start = resolvedDeparture;
    if (start == null || prepMinutes == null) return false;
    return start - prepMinutes! - bufferMinutes < 0;
  }

  /// 사용자가 알고 싶어한 값이 나왔는지.
  bool get isAnswered => goal == PrepGoal.departure
      ? resolvedDeparture != null
      : prepStart != null;

  /// 계산에 모자란 것. 코치가 물어볼 거리를 여기서 정한다.
  ///
  /// 순서가 곧 물어볼 순서인데, 계산 순서가 아니라 사용자가 물은 순서를 따른다.
  /// 준비를 언제 시작하냐고 물었는데 "거기까지 얼마나 걸려?"부터 되물으면
  /// 딴소리로 들린다. 계산이야 값이 다 모이면 어느 순서로 받았든 똑같다.
  ///
  /// 나가는 시각만 물었으면 준비 시간은 아예 묻지 않는다. 안 물어본 걸
  /// 캐내는 것도 대화를 늘리는 일이다.
  List<PrepMissing> get missing {
    if (appointment == null && departure == null) {
      return const [PrepMissing.anchorTime];
    }
    final result = <PrepMissing>[];
    if (goal == PrepGoal.prepStart && prepMinutes == null) {
      result.add(PrepMissing.prep);
    }
    if (resolvedDeparture == null) result.add(PrepMissing.travel);
    return result;
  }

  bool get isEmpty =>
      appointment == null &&
      departure == null &&
      travelMinutes == null &&
      prepMinutes == null;

  static int _wrap(int minutes) => (minutes % 1440 + 1440) % 1440;
}

/// 사용자가 알고 싶어한 것.
enum PrepGoal {
  /// 집에서 몇 시에 나가야 하는지.
  departure,

  /// 몇 시부터 준비해야 하는지, 몇 시에 일어나야 하는지.
  prepStart,
}

/// 계산에 모자란 값. 코치가 이것만 묻는다.
enum PrepMissing {
  /// 약속 시각도 출발 시각도 모른다.
  anchorTime,

  /// 거기까지 얼마나 걸리는지 모른다.
  travel,

  /// 나가기 전에 준비하는 데 얼마나 걸리는지 모른다.
  prep,
}

/// 자정부터의 분을 "9시 20분"처럼 읽는 말로 바꾼다.
///
/// [withMeridiem]이 참일 때만 오전/오후를 붙인다. 사용자가 그냥 "10시"라고
/// 했으면 코치도 "9시 20분"이라고 해야 자연스럽다. 안 물어본 걸 단정하지 않는다.
String formatClock(int minutes, {bool withMeridiem = false}) {
  final wrapped = PrepPlan._wrap(minutes);
  final hour24 = wrapped ~/ 60;
  final minute = wrapped % 60;
  final label = minute == 0 ? '$hour24시' : '$hour24시 $minute분';
  if (!withMeridiem) return label;
  final isAfternoon = hour24 >= 12;
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final base = minute == 0 ? '$hour12시' : '$hour12시 $minute분';
  return '${isAfternoon ? '오후' : '오전'} $base';
}

/// 분을 "1시간 20분"처럼 읽는 말로 바꾼다.
String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}

/// 말에서 시각을 뽑는다. 없으면 null.
///
/// "10시 10분", "10:10", "오전 10시", "10시반"을 읽는다. 읽을 수 없으면
/// 억지로 짐작하지 않는다. 못 읽으면 코치가 물어보면 될 일이다.
///
/// [now]를 주면 오전/오후를 안 밝힌 시각을 지금에서 가장 가까운 쪽으로 읽는다.
/// "이따가 5시"를 오후 2시에 말했으면 오후 5시다. 이걸 안 하면 오후 1시 약속에
/// "0시 15분부터 준비해라"처럼 답하게 된다.
ClockReading? parseClock(String text, {DateTime? now}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '');

  // 오전/오후는 숫자 앞에 붙는다. "저녁 7시"처럼 때를 가리키는 말도 함께 본다.
  int? meridiemOffset;
  bool meridiemKnown = false;
  String? meridiemWord;
  for (final entry in _meridiemWords.entries) {
    final index = normalized.indexOf(entry.key);
    if (index < 0) continue;
    // 여러 개가 걸리면 숫자에 가장 가까운 것을 쓴다.
    if (meridiemWord == null || entry.key.length > meridiemWord.length) {
      meridiemWord = entry.key;
      meridiemOffset = entry.value;
      meridiemKnown = true;
    }
  }

  final colon = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(normalized);
  if (colon != null) {
    final hour = int.parse(colon.group(1)!);
    final minute = int.parse(colon.group(2)!);
    if (hour > 23 || minute > 59) return null;
    return _resolve(
      hour: hour,
      minute: minute,
      offset: meridiemOffset,
      explicit: meridiemKnown,
      normalized: normalized,
      now: now,
      tailStart: colon.end,
    );
  }

  // "10시 10분" / "10시반" / "10시"
  final korean = RegExp(
    r'(\d{1,2})시(?:(\d{1,2})분|(반))?',
  ).firstMatch(normalized);
  if (korean == null) return null;
  final hour = int.parse(korean.group(1)!);
  if (hour > 23) return null;
  final minute = korean.group(3) != null
      ? 30
      : int.tryParse(korean.group(2) ?? '0') ?? 0;
  if (minute > 59) return null;
  return _resolve(
    hour: hour,
    minute: minute,
    offset: meridiemOffset,
    explicit: meridiemKnown,
    normalized: normalized,
    now: now,
    tailStart: korean.end,
  );
}

/// 오전인지 오후인지 정한다.
///
/// 사용자가 밝혔으면 그대로 쓴다. 아니면 지금에서 가장 가까운 쪽으로 읽는다.
/// 밤 11시에 "1시"라고 하면 오후 1시가 아니라 두 시간 뒤 새벽 1시다.
///
/// 다른 날 얘기(내일, 모레)에는 지금과의 거리를 쓸 수 없다. 하루 뒤 오전이
/// 늘 더 가깝게 나오기 때문이다. 그때는 새벽에 잡을 리 없는 1~5시만 오후로
/// 보고 나머지는 건드리지 않는다.
ClockReading _resolve({
  required int hour,
  required int minute,
  required int? offset,
  required bool explicit,
  required String normalized,
  required DateTime? now,
  required int tailStart,
}) {
  if (explicit) {
    return ClockReading(
      minutes: _applyMeridiem(hour, offset) * 60 + minute,
      meridiemKnown: true,
      tailStart: tailStart,
    );
  }
  // 13시처럼 24시간 표기면 이미 정해진 것이다.
  if (hour >= 13) {
    return ClockReading(
      minutes: hour * 60 + minute,
      meridiemKnown: true,
      tailStart: tailStart,
    );
  }
  if (hour >= 1 && hour <= 11) {
    if (_otherDayPattern.hasMatch(normalized)) {
      if (hour <= 5) {
        return ClockReading(
          minutes: (hour + 12) * 60 + minute,
          meridiemKnown: true,
          tailStart: tailStart,
        );
      }
    } else if (now != null) {
      final nowMinutes = now.hour * 60 + now.minute;
      final morning = hour * 60 + minute;
      final afternoon = (hour + 12) * 60 + minute;
      int until(int target) => (target - nowMinutes + 1440) % 1440;
      return ClockReading(
        minutes: until(morning) <= until(afternoon) ? morning : afternoon,
        meridiemKnown: true,
        tailStart: tailStart,
      );
    }
  }
  return ClockReading(
    minutes: hour * 60 + minute,
    meridiemKnown: false,
    tailStart: tailStart,
  );
}

/// 오늘이 아닌 날을 가리키는 말.
final _otherDayPattern = RegExp(r'내일|모레|다음주|담주|이번주|주말');

/// 말에서 걸리는 시간을 뽑는다. 없으면 null.
///
/// "30분", "1시간", "한시간", "1시간 20분", "40분쯤"을 읽는다.
/// 시각("10시에")과 헷갈리지 않게, 시각으로 읽히는 자리는 피한다.
int? parseDuration(String text) {
  final normalized = text
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('한시간', '1시간')
      .replaceAll('두시간', '2시간')
      .replaceAll('세시간', '3시간')
      .replaceAll('반시간', '30분');

  // "1시간 20분" / "1시간반" / "1시간"
  final hourMatch = RegExp(
    r'(\d{1,2})시간(?:(\d{1,2})분|(반))?',
  ).firstMatch(normalized);
  if (hourMatch != null) {
    final hours = int.parse(hourMatch.group(1)!);
    final rest = hourMatch.group(3) != null
        ? 30
        : int.tryParse(hourMatch.group(2) ?? '0') ?? 0;
    return hours * 60 + rest;
  }

  // "30분". 단 "10시 30분"의 30분은 시각의 일부라 빼야 한다.
  for (final m in RegExp(r'(\d{1,3})분').allMatches(normalized)) {
    final before = normalized.substring(0, m.start);
    if (before.endsWith('시')) continue;
    if (RegExp(r'\d{1,2}시$').hasMatch(before)) continue;
    final value = int.parse(m.group(1)!);
    if (value > 0 && value < 600) return value;
  }
  return null;
}

/// 읽어낸 시각.
///
/// [tailStart]는 공백을 지운 문장에서 이 시각 표현이 끝나는 자리다. 시각이
/// 무엇을 가리키는지는 바로 뒤에 붙는 말로 갈리기 때문에 위치를 들고 다닌다.
class ClockReading {
  final int minutes;
  final bool meridiemKnown;
  final int tailStart;

  const ClockReading({
    required this.minutes,
    required this.meridiemKnown,
    required this.tailStart,
  });
}

/// 한 발화에서 읽어낸 값을 기존 계획에 합친다. 준비 대화가 아니면 null.
///
/// 출발 시각은 첫 마디에, 준비 시간은 몇 턴 뒤에 나온다. 그래서 계획을 들고
/// 다니며 값이 나올 때마다 채운다.
///
/// [lastAsked]는 직전에 코치가 물어본 항목이다. "40분쯤" 같은 답에는 무엇에
/// 대한 답인지가 안 붙어 있어서, 물어본 쪽으로 넣는다.
PrepPlan? mergeUtterance({
  required PrepPlan? plan,
  required PrepMissing? lastAsked,
  required String text,
  List<PrepTaskTime> taskTimes = const [],
  DateTime? now,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), '');
  final clock = parseClock(text, now: now);
  final duration = parseDuration(text);

  final role = clock == null ? null : _clockRole(normalized, clock);
  final saysDeparture = role == _ClockRole.departure;
  final saysAppointment = role == _ClockRole.appointment;
  final askMatch = _askPattern.firstMatch(normalized);
  final asksBackward = askMatch != null;

  var current = plan;
  // 준비 대화를 새로 여는 조건. 아무 대화에서나 켜지면 안 된다.
  if (current == null) {
    final opens =
        (clock != null && (saysDeparture || saysAppointment)) || asksBackward;
    if (!opens) return null;
    current = const PrepPlan();
  }

  // 무엇을 물었는지에 따라 어디까지 물어볼지가 달라진다. 나가는 시각만
  // 궁금한 사람에게 준비 시간까지 캐물으면 대화가 길어지기만 한다.
  final asked = _goalOf(normalized, askMatch);
  if (asked != null) current = current.copyWith(goal: asked);

  if (clock != null) {
    if (saysDeparture) {
      current = current.copyWith(
        departure: clock.minutes,
        meridiemKnown: clock.meridiemKnown,
      );
    } else if (saysAppointment) {
      current = current.copyWith(
        appointment: clock.minutes,
        meridiemKnown: clock.meridiemKnown,
      );
    }
  } else if (asksBackward &&
      current.appointment == null &&
      current.departure == null) {
    // 시각을 말하지 않고 "몇시부터 '약속' 준비할까?"처럼 할 일 이름만 부를 때가
    // 있다. 그 시각은 할 일 탭에 이미 적혀 있으니 사용자에게 다시 묻지 않는다.
    final named = _namedTask(normalized, taskTimes);
    if (named != null) {
      current =
          _departurePattern.hasMatch(named.name.replaceAll(RegExp(r'\s+'), ''))
          ? current.copyWith(departure: named.minutes, meridiemKnown: true)
          : current.copyWith(appointment: named.minutes, meridiemKnown: true);
    }
  }

  if (duration != null) {
    final saysPrep = _prepPattern.hasMatch(normalized);
    final saysTravel =
        _travelPattern.hasMatch(normalized) ||
        (!saysPrep && _weakTravelPattern.hasMatch(normalized));
    // 표시가 없으면 직전에 물어본 쪽으로 넣는다. 그것도 없으면 비어 있는 칸에
    // 넣되, 나가는 시각을 아직 모르면 이동부터 채운다.
    final target = saysTravel
        ? PrepMissing.travel
        : saysPrep
        ? PrepMissing.prep
        : lastAsked ??
              (current.resolvedDeparture == null
                  ? PrepMissing.travel
                  : PrepMissing.prep);
    current = switch (target) {
      PrepMissing.travel => current.copyWith(travelMinutes: duration),
      PrepMissing.prep => current.copyWith(prepMinutes: duration),
      PrepMissing.anchorTime => current,
    };
  }

  if (current.isEmpty && !asksBackward) return null;
  return current;
}

enum _ClockRole { departure, appointment }

/// 이 시각이 나가는 시각인지 도착해야 하는 시각인지 가른다.
///
/// 문장 전체를 훑으면 안 된다. "1시까지 신촌 가야 하는데 집에서 몇 시에
/// 나갈까"에는 도착 얘기와 나가는 얘기가 같이 들어 있는데, 뒤엣말에 끌려가면
/// 도착 시각을 출발 시각으로 넣어버린다. 그러면 이동 시간만큼 통째로 늦는다.
///
/// 그래서 시각 바로 뒤 한 마디만 본다. 거기서 못 가리면 문장 전체로 넓힌다.
_ClockRole? _clockRole(String normalized, ClockReading clock) {
  final tail = normalized.substring(clock.tailStart);
  // "~하는데", "~인데"에서 끊는다. 그 뒤는 대개 딸린 질문이다.
  final clause = tail.split(RegExp(r'하는데|인데|는데|,')).first;

  // 나가는 얘기를 먼저 본다. "10시까지 나가야 해"에는 '까지'와 '나가'가 같이
  // 있는데, '까지'는 아무 마감에나 붙지만 '나가'는 뜻이 하나뿐이다.
  for (final scope in [clause, tail]) {
    if (_departurePattern.hasMatch(scope)) return _ClockRole.departure;
    if (_appointmentPattern.hasMatch(scope)) return _ClockRole.appointment;
  }
  return null;
}

/// 집에서 나서는 시각을 가리키는 말.
final _departurePattern = RegExp(r'나가|나서|출발|집에서');

/// 도착해야 하는 시각을 가리키는 말. 이쪽이면 이동 시간을 더 빼야 한다.
///
/// "가야"는 "나가야"에도 들어 있어서 앞에 '나'가 오면 뺀다. 앞에서 나가는
/// 얘기를 먼저 보긴 하지만, 여기서도 막아두는 편이 안전하다.
final _appointmentPattern = RegExp(
  r'약속|도착|만나|회의|수업|면접|예약|비행기|기차|공연|까지|(?<!나)가야|와야',
);

/// 할 일 탭에 적힌 시각. 사용자가 시각 대신 할 일 이름만 부를 때 쓴다.
class PrepTaskTime {
  final String name;

  /// 자정부터의 분.
  final int minutes;

  const PrepTaskTime({required this.name, required this.minutes});
}

/// 사용자가 문장에서 부른 할 일을 찾는다. 부르지 않은 할 일은 끌어오지 않는다.
///
/// 이름이 긴 것부터 본다. "약속"과 "약속 준비"가 둘 다 있으면 긴 쪽이 맞다.
PrepTaskTime? _namedTask(String normalized, List<PrepTaskTime> tasks) {
  final candidates =
      tasks
          .where((t) => t.name.replaceAll(RegExp(r'\s+'), '').length >= 2)
          .toList()
        ..sort((a, b) => b.name.length.compareTo(a.name.length));
  for (final task in candidates) {
    if (normalized.contains(task.name.replaceAll(RegExp(r'\s+'), ''))) {
      return task;
    }
  }
  return null;
}

/// 역산 자체를 물어보는 말. 시각을 아직 안 말했어도 대화를 연다.
///
/// 통짜 문구로 두면 "몇시부터 '약속' 나갈 준비할까?"처럼 사이에 말이 끼는
/// 순간 못 알아듣는다. 묻는 말과 행동 사이는 비워둔다.
/// 활용형을 같이 적어둔다. 한글은 어미가 붙으면 글자가 통째로 바뀐다.
/// "나가야"에는 "나가"가 들어 있지만 "나갈까"는 나/갈/까라서 안 들어 있다.
final _askPattern = RegExp(
  r'(몇시|언제).{0,20}?(일어나|일어날|나가|나갈|나서|나설|출발|준비)'
  r'|안늦(을까|으려면)',
);

/// 물음에서 무엇을 알고 싶어하는지 읽는다. 못 읽으면 null이라 기존 값을 지킨다.
///
/// "몇 시에 나가야 해?"는 나가는 시각까지만 답하면 되고, "몇 시부터 준비해?"는
/// 준비 시작까지 가야 한다. 같은 계산이지만 어디서 멈출지가 다르다.
PrepGoal? _goalOf(String normalized, RegExpMatch? askMatch) {
  // "나갈 준비"의 머리는 준비다. 앞에 나온 '나갈'만 보고 나가는 시각으로
  // 읽으면, 준비를 물은 사람에게 준비 얘기를 빼고 답하게 된다.
  if (normalized.contains('준비')) return PrepGoal.prepStart;
  final verb = askMatch?.group(2);
  if (verb != null) {
    return switch (verb) {
      '나가' || '나갈' || '나서' || '나설' || '출발' => PrepGoal.departure,
      _ => PrepGoal.prepStart,
    };
  }
  // "안 늦으려면"은 언제 나서야 하는지를 묻는 말이다.
  if (askMatch != null) return PrepGoal.departure;
  // 물음 형태가 아니어도 준비 얘기를 꺼냈으면 준비까지 보는 게 맞다.
  if (normalized.contains('준비')) return PrepGoal.prepStart;
  return null;
}

/// 이동 시간을 가리키는 말.
///
/// "가는데"는 "나가는데"에도 들어 있다. "씻고 나가는데 40분"은 준비 시간인데
/// 이동으로 새면 출발 시각이 통째로 틀어진다. 그래서 앞에 '나'가 오면 뺀다.
final _travelPattern = RegExp(r'이동|(?<!나)가는데|거기까지|근처|버스|지하철|차로|걸어서|택시');

/// "신촌까지 40분"처럼 목적지에 붙는 '까지'. 혼자서는 약한 단서라 준비를
/// 가리키는 말이 하나도 없을 때만 이동으로 본다. "10시까지 나가야 해"의
/// '까지'는 마감이지 이동이 아니기 때문이다.
final _weakTravelPattern = RegExp(r'까지');

/// 준비 시간을 가리키는 말. "나가는데/나가기까지"는 나서기 전까지 걸리는
/// 시간이라 준비 쪽이다.
final _prepPattern = RegExp(r'준비|씻|샤워|머리|화장|밥|먹|옷|나가는데|나가기까지');

const Map<String, int> _meridiemWords = {
  '오전': 0,
  '아침': 0,
  '새벽': 0,
  '오후': 12,
  '저녁': 12,
  '점심': 12,
  '밤': 12,
};

int _applyMeridiem(int hour, int? offset) {
  if (offset == null) return hour;
  if (hour == 12) return offset == 12 ? 12 : 0;
  if (hour > 12) return hour;
  return hour + offset;
}
