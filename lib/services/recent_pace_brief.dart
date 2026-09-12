/// 최근 며칠을 어떻게 지냈는지, 그리고 오늘이 지금 어디까지 왔는지.
///
/// 코치가 "오늘은 이렇게 해보시죠"를 스스로 정하도록 넘기는 재료다. 무엇을
/// 올릴지도, 얼마나 올릴지도, 올릴지 유지할지도 여기서 정하지 않는다. 앱이
/// 규칙을 박으면 그 규칙이 틀리는 사람이 반드시 나오고, 틀린 줄도 모른다 —
/// 문턱으로 유형을 나누던 때가 정확히 그랬다.
///
/// 그래서 이 파일이 하는 일은 세는 것뿐이다. 판단하는 낱말을 쓰지 않는다.
///
/// **분모를 조심해야 한다.** 완료는 **손댄 것 중** 몇을 끝냈는지로 센다.
/// 적어둔 것 대비로 재면 "적게 시작한 것"과 "시작했는데 못 끝낸 것"이 한
/// 숫자에 섞여, 앞뒤가 정반대인 두 사람이 같은 값으로 나온다.
library;

import 'dart:convert';

import 'package:intl/intl.dart';

/// 하루치 셈.
class PaceDay {
  const PaceDay({
    required this.date,
    required this.planned,
    required this.touched,
    required this.done,
    required this.firstStartHour,
    required this.lastDoneHour,
    required this.doneNames,
    required this.leftNames,
  });

  final String date;

  /// 그날 목록에 있던 개수.
  final int planned;

  /// 그중 한 번이라도 손댄 개수. 끝낸 것도 손댄 것에 든다.
  final int touched;

  final int done;

  /// 그날 가장 이른 시작 시각. 시작 표시가 없으면 null.
  ///
  /// 시작 시각은 시작 버튼을 누른 일에만 남는다. 체크만 하는 사람은 늘 빈다.
  final int? firstStartHour;

  /// 그날 마지막으로 끝낸 시각. 끝낸 것이 없으면 null.
  ///
  /// 시작 시각과 달리 체크만 하는 사람에게도 남는다 — 완료를 미는 순간 찍히기
  /// 때문이다. 그래서 시작 표시를 안 쓰는 사람에게는 시간을 말할 수 있는 유일한
  /// 값이다.
  ///
  /// 첫 완료가 아니라 마지막 완료를 본다. 하루가 어디서 끝났는지가 궁금한
  /// 자리다 — 밤 11시에 몰아서 끝내는 사람과 저녁에 접는 사람은 같은 개수를
  /// 끝내도 다르게 지낸 것이다.
  final int? lastDoneHour;

  final List<String> doneNames;
  final List<String> leftNames;
}

class RecentPaceBrief {
  const RecentPaceBrief._();

  /// 최근 며칠을 짚을지. 오늘은 세지 않는다.
  ///
  /// 하루만 보면 표본이 하나다 — 어제 아팠던 사람에게 어제 하루로 처방하면
  /// 빗나간다. 이틀이면 "둘 다 그랬다"와 "어제만 그랬다"를 가를 수 있다.
  static const int recentDays = 2;

  /// 기준선을 며칠에서 낼지.
  ///
  /// 이틀이 평소와 같은지 다른지는 이틀만 보고는 알 수 없다. 이틀이 주인공이고
  /// 이 값은 자막이다.
  static const int baselineDays = 7;

  /// 한 날에 이름을 몇 개까지 적을지. 목록을 통째로 실으면 이 한 턴이 평소의
  /// 몇 배가 된다.
  static const int maxNamesPerDay = 4;

  /// 이름 하나의 길이 상한. 긴 제목은 잘라 적는다.
  static const int maxNameLength = 24;

  /// [historyRaw]에서 오늘 이전 [days]일을 뽑는다. 기록이 없는 날은 건너뛴다.
  ///
  /// 날짜를 거꾸로 세지 않고 기록에 있는 날 중 최근 것을 고른다. 주말을 건너뛴
  /// 사람에게 "이틀 전"을 따지면 빈손으로 돌아오는데, 그 사람에게도 최근에
  /// 지낸 이틀은 있다.
  static List<PaceDay> recent(
    String? historyRaw, {
    DateTime? now,
    int days = recentDays,
  }) {
    final today = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
    final records = _records(historyRaw)
        .where(
          (record) => (record['date']?.toString() ?? '').compareTo(today) < 0,
        )
        .toList();
    records.sort(
      (a, b) => b['date'].toString().compareTo(a['date'].toString()),
    );

    final out = <PaceDay>[];
    for (final record in records) {
      if (out.length >= days) break;
      final day = _dayOf(record);
      if (day == null) continue;
      out.add(day);
    }
    return out;
  }

  /// 기준선. 오늘 이전 [days]일 중 목록이 있던 날의 평균 개수와 완료 개수.
  ///
  /// 판단이 아니라 값이다. 이틀이 이보다 낮은지 높은지는 코치가 견준다.
  static ({int daysCounted, double plannedPerDay, double donePerDay})? baseline(
    String? historyRaw, {
    DateTime? now,
    int days = baselineDays,
  }) {
    final all = recent(historyRaw, now: now, days: days);
    final withPlan = all.where((day) => day.planned > 0).toList();
    if (withPlan.isEmpty) return null;
    var planned = 0;
    var done = 0;
    for (final day in withPlan) {
      planned += day.planned;
      done += day.done;
    }
    return (
      daysCounted: withPlan.length,
      plannedPerDay: planned / withPlan.length,
      donePerDay: done / withPlan.length,
    );
  }

  /// 프롬프트에 실을 블록. 셀 것이 없으면 빈 문자열.
  ///
  /// [todayTasks]는 오늘 목록, [now]는 지금, [minutesLeft]는 잠들기까지 남은
  /// 시간(모르면 null), [busyNow]는 지금이 못 쓰는 시간대면 그 이름.
  static String block({
    required String? historyRaw,
    required List<dynamic> todayTasks,
    required DateTime now,
    int? minutesLeft,
    String? busyNow,
  }) {
    final days = recent(historyRaw, now: now);
    if (days.isEmpty) return '';

    final buffer = StringBuffer('\n[최근 - 앱이 기록에서 센 값]\n');
    for (final day in days) {
      buffer.writeln(_dayLine(day));
      if (day.doneNames.isNotEmpty) {
        buffer.writeln('  끝낸 것: ${day.doneNames.join(', ')}');
      }
      if (day.leftNames.isNotEmpty) {
        buffer.writeln('  남은 것: ${day.leftNames.join(', ')}');
      }
    }

    final base = baseline(historyRaw, now: now);
    if (base != null) {
      buffer.writeln(
        '기준선  최근 ${base.daysCounted}일 중 목록이 있던 날 평균 '
        '${base.plannedPerDay.toStringAsFixed(1)}개 적고 '
        '${base.donePerDay.toStringAsFixed(1)}개 끝냄',
      );
    }

    // 시각을 말할 근거가 하나도 없으면 그렇다고 적는다. 시작 표시를 안 쓰는
    // 사람에게 "늦게 시작하시네요"는 없는 패턴을 지어내는 말이다.
    //
    // 완료 시각은 따로 본다. 그건 체크만 하는 사람에게도 남아서, 시작 시각이
    // 비어 있어도 "하루가 몇 시에 끝났는지"는 말할 수 있다. 둘을 한 덩어리로
    // 묶으면 방금 넘긴 완료 시각을 쓰지 말라고 하는 셈이 된다.
    final noStart = days.every((day) => day.firstStartHour == null);
    final noDone = days.every((day) => day.lastDoneHour == null);
    if (noStart && noDone) {
      buffer.writeln('*시각이 남은 날이 없습니다. 시간 이야기는 하지 마세요.');
    } else if (noStart) {
      buffer.writeln(
        '*시작 시각이 남은 날이 없습니다. 시작 버튼을 안 쓰고 체크만 하는 '
        '사람일 수 있으니 언제 시작했는지는 말하지 마세요. 완료 시각은 써도 됩니다.',
      );
    }

    buffer.write(_todayBlock(todayTasks, now, minutesLeft, busyNow));
    buffer.writeln('- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.');
    return buffer.toString();
  }

  static String _dayLine(PaceDay day) {
    final parts = [
      '적은 것 ${day.planned}개',
      '손댄 것 ${day.touched}개',
      '끝낸 것 ${day.done}개',
    ];
    if (day.firstStartHour != null) {
      parts.add('첫 시작 ${_clock(day.firstStartHour!)}');
    }
    if (day.lastDoneHour != null) {
      parts.add('마지막 완료 ${_clock(day.lastDoneHour!)}');
    }
    return '${day.date}  ${parts.join(' / ')}';
  }

  static String _todayBlock(
    List<dynamic> todayTasks,
    DateTime now,
    int? minutesLeft,
    String? busyNow,
  ) {
    final buffer = StringBuffer('\n[오늘 - 지금까지]\n');
    var planned = 0;
    var touched = 0;
    var done = 0;
    for (final task in todayTasks) {
      if (task is! Map) continue;
      planned++;
      if (task['done'] == true) {
        done++;
        touched++;
        continue;
      }
      if (_isStarted(task)) touched++;
    }
    buffer.writeln(
      '지금 ${_clockMinutes(now)} / 적은 것 $planned개 / 손댄 것 $touched개 / 끝낸 것 $done개',
    );
    if (minutesLeft != null && minutesLeft > 0) {
      final hours = minutesLeft ~/ 60;
      final mins = minutesLeft % 60;
      buffer.writeln(
        '잠들기까지 약 ${hours > 0 ? '$hours시간' : ''}'
        '${mins > 0 ? '${hours > 0 ? ' ' : ''}$mins분' : ''}',
      );
    }
    if (busyNow != null && busyNow.isNotEmpty) {
      buffer.writeln('지금은 $busyNow 시간대라고 알려주셨습니다.');
    }
    return buffer.toString();
  }

  static bool _isStarted(Map task) {
    if (task['inProgress'] == true) return true;
    if ((task['elapsedSeconds'] as num?) != null &&
        (task['elapsedSeconds'] as num) > 0) {
      return true;
    }
    return task['startedAt'] != null;
  }

  static PaceDay? _dayOf(Map<String, dynamic> record) {
    final date = record['date']?.toString();
    if (date == null || date.isEmpty) return null;
    final tasks = (record['tasks'] as List?) ?? const [];
    if (tasks.isEmpty) {
      return PaceDay(
        date: date,
        planned: 0,
        touched: 0,
        done: 0,
        firstStartHour: null,
        lastDoneHour: null,
        doneNames: const [],
        leftNames: const [],
      );
    }

    var planned = 0;
    var touched = 0;
    var done = 0;
    int? firstStartHour;
    int? lastDoneHour;
    final doneNames = <String>[];
    final leftNames = <String>[];

    for (final task in tasks) {
      if (task is! Map) continue;
      planned++;
      final isDone = task['done'] == true;
      final started = _isStarted(task);
      if (isDone || started) touched++;
      if (isDone) done++;
      final startedAt = DateTime.tryParse(task['startedAt']?.toString() ?? '');
      if (startedAt != null &&
          (firstStartHour == null || startedAt.hour < firstStartHour)) {
        firstStartHour = startedAt.hour;
      }
      final completedAt = DateTime.tryParse(
        task['completedAt']?.toString() ?? '',
      );
      // 자정을 넘겨 끝낸 것은 다음 날 시각으로 찍힌다. 그걸 그대로 "마지막
      // 완료"로 쓰면 그날이 새벽에 끝난 것처럼 읽혀서, 그날 것만 본다.
      if (completedAt != null &&
          DateFormat('yyyy-MM-dd').format(completedAt) == date &&
          (lastDoneHour == null || completedAt.hour > lastDoneHour)) {
        lastDoneHour = completedAt.hour;
      }
      // 이름을 못 읽는 항목도 셈에는 들어간다. 아래는 적어 보낼 이름만 고르는
      // 자리다 — 예전에는 셈이 이 안에 있어서, 이름이 빈 항목은 끝냈어도
      // 완료로 세지지 않았다.
      final name = _shortName(task['text']?.toString());
      if (name == null) continue;
      if (isDone) {
        if (doneNames.length < maxNamesPerDay) doneNames.add(name);
      } else if (leftNames.length < maxNamesPerDay) {
        leftNames.add(name);
      }
    }

    return PaceDay(
      date: date,
      planned: planned,
      touched: touched,
      done: done,
      firstStartHour: firstStartHour,
      lastDoneHour: lastDoneHour,
      doneNames: doneNames,
      leftNames: leftNames,
    );
  }

  static String? _shortName(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    return text.length <= maxNameLength
        ? text
        : '${text.substring(0, maxNameLength)}…';
  }

  static List<Map<String, dynamic>> _records(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// "오후 2시"처럼. 화면 표기와 같은 모양.
  static String _clock(int hour) {
    final wrapped = hour % 24;
    final prefix = wrapped < 6
        ? '새벽'
        : wrapped < 12
        ? '오전'
        : '오후';
    final h = wrapped % 12 == 0 ? 12 : wrapped % 12;
    return '$prefix $h시';
  }

  static String _clockMinutes(DateTime at) =>
      '${_clock(at.hour)} ${at.minute}분';
}
