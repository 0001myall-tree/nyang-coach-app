/// 최근 며칠을 어떻게 지냈는지, 그리고 오늘이 지금 어디까지 왔는지.
///
/// 코치가 "오늘은 이렇게 해보시죠"를 스스로 정하도록 넘기는 재료다. 무엇을
/// 올릴지도, 얼마나 올릴지도, 올릴지 유지할지도 여기서 정하지 않는다. 앱이
/// 규칙을 박으면 그 규칙이 틀리는 사람이 반드시 나오고, 틀린 줄도 모른다 —
/// 문턱으로 유형을 나누던 때가 정확히 그랬다.
///
/// 그래서 이 파일이 하는 일은 세는 것뿐이다. 판단하는 낱말을 쓰지 않는다.
///
/// **적은 일정마다 한 줄씩 적는다.** 합친 숫자만 주면 무엇이 끝났는지가
/// 지워지고, 시각만 따로 모아 주면 그게 무엇의 시각인지가 지워진다. 큰 일은
/// 안 끝나고 짧은 일만 끝나는 사람과 그 반대인 사람은 개수로는 같아 보인다.
///
/// **분모를 조심해야 한다.** 완료는 **손댄 것 중** 몇을 끝냈는지로 센다.
/// 적어둔 것 대비로 재면 "적게 시작한 것"과 "시작했는데 못 끝낸 것"이 한
/// 숫자에 섞여, 앞뒤가 정반대인 두 사람이 같은 값으로 나온다.
///
/// 일부러 안 넣은 것 둘.
///
/// **더 긴 기준선**(이레 평균)을 곁들인 적이 있다. 맞출 기준이 둘이면 어느 쪽에
/// 맞추라는 말인지 흐려지고, 평균과 견주는 자리는 "평소보다 못하시네요"로
/// 흐르기 쉽다. 대신 이틀이 유독 조용했던 사람과 원래 조용한 사람을 못 가른다 —
/// 코치가 그 이틀을 이 사람의 수준으로 다루기 시작하면 되돌릴 자리다.
///
/// **시각을 두고 하지 말라는 줄.** 없는 시각으로는 말할 수도 없어서 "여기 없는
/// 것은 세지 않았음"이 이미 그 일을 한다. 완료 시각만 있는 사람도 막지 않는다 —
/// 줄마다 "끝냄"이라 적혀 있어 시작으로 읽을 자리가 아니다.
library;

import 'dart:convert';

import 'package:intl/intl.dart';

/// 적어둔 일 하나가 그날 어떻게 됐는지.
class PaceTask {
  const PaceTask({
    required this.name,
    required this.done,
    required this.started,
    required this.startHour,
    required this.doneHour,
  });

  final String name;
  final bool done;

  /// 한 번이라도 손댔는지. 끝낸 것도 손댄 것에 든다.
  final bool started;

  /// 손댄 시각. 시작 버튼을 누른 일에만 남는다 — 체크만 하는 사람은 늘 빈다.
  final int? startHour;

  /// 끝낸 시각. 완료를 미는 순간 찍히므로 체크만 하는 사람에게도 남는다.
  /// 그래서 시작 표시를 안 쓰는 사람에게 시간을 말할 수 있는 유일한 값이다.
  final int? doneHour;
}

/// 하루치.
class PaceDay {
  const PaceDay({
    required this.date,
    required this.planned,
    required this.touched,
    required this.done,
    required this.firstStartHour,
    required this.tasks,
    this.hasRecord = true,
  });

  /// 앱에 그날 흔적이 아예 없을 때.
  const PaceDay.noRecord(this.date)
    : planned = 0,
      touched = 0,
      done = 0,
      firstStartHour = null,
      tasks = const [],
      hasRecord = false;

  final String date;

  /// 앱에 그날 기록이 있었는지.
  ///
  /// 없는 날도 빼지 않고 적는다. 사흘을 쉰 사람에게 코치가 어제 일처럼 이어
  /// 말하면 그 사흘이 없던 일이 된다.
  ///
  /// "기록 없음"은 "아무것도 안 한 날"이 아니다. 기록은 앱을 열었을 때만
  /// 쌓인다.
  final bool hasRecord;

  /// 그날 목록에 있던 개수.
  final int planned;

  /// 그중 한 번이라도 손댄 개수.
  final int touched;

  final int done;

  /// 그날 가장 이른 시작 시각. 시작 표시가 없으면 null.
  ///
  /// 아래 줄들에서도 보이지만 따로 둔다. 줄은 상한에 걸려 잘릴 수 있는데 이
  /// 값은 잘리지 않는다.
  final int? firstStartHour;

  /// 적어둔 일들. 적은 순서 그대로. 많으면 앞에서 상한까지만.
  final List<PaceTask> tasks;
}

class RecentPaceBrief {
  const RecentPaceBrief._();

  /// 최근 며칠을 짚을지. 오늘은 세지 않는다.
  ///
  /// 하루만 보면 표본이 하나다 — 어제 아팠던 사람에게 어제 하루로 처방하면
  /// 빗나간다. 이틀이면 "둘 다 그랬다"와 "어제만 그랬다"를 가를 수 있다.
  static const int recentDays = 2;

  /// 한 날에 줄을 몇 개까지 적을지.
  ///
  /// 루틴을 여러 개 돌리는 사람은 하루에 열다섯 줄이 나온다. 목록을 통째로
  /// 실으면 이 한 턴이 평소의 몇 배가 된다. 잘린 개수는 따로 적어준다.
  static const int maxTasksPerDay = 8;

  /// 이름 하나의 길이 상한. 긴 제목은 잘라 적는다.
  static const int maxNameLength = 24;

  /// 기록 있는 날을 [days]개 찾을 때까지 거슬러 볼 날수 상한.
  ///
  /// 기록이 없는 날도 적어야 하니 날짜를 하루씩 거슬러 센다. 상한이 없으면
  /// 한 달 만에 돌아온 사람에게 "기록 없음" 서른 줄이 나간다.
  static const int maxLookbackDays = 7;

  /// 오늘 이전 며칠을 뽑는다. **기록이 없는 날도 그대로 담는다.**
  ///
  /// 기록 있는 날만 골라 오던 자리다. 그러면 사흘 쉰 것이 지워져서, 코치가
  /// 어제 일처럼 이어 말한다. 빈 날을 담으면 "오랜만이네요" 쪽으로 갈 수 있다.
  ///
  /// 기록 있는 날 [days]개를 찾으면 멈춘다. 그 앞에 있던 빈 날은 함께 담기고,
  /// [maxLookbackDays]까지 거슬러도 하나도 못 찾으면 빈 목록을 돌려준다 —
  /// 이레 내내 흔적이 없으면 오늘 페이스를 말할 근거가 없다.
  static List<PaceDay> recent(
    String? historyRaw, {
    DateTime? now,
    int days = recentDays,
  }) {
    final base = now ?? DateTime.now();
    final byDate = <String, Map<String, dynamic>>{};
    for (final record in _records(historyRaw)) {
      final date = record['date']?.toString();
      if (date != null && date.isNotEmpty) byDate[date] = record;
    }

    final out = <PaceDay>[];
    var found = 0;
    for (var back = 1; back <= maxLookbackDays && found < days; back++) {
      final date = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(base.year, base.month, base.day - back));
      final record = byDate[date];
      if (record == null) {
        out.add(PaceDay.noRecord(date));
        continue;
      }
      final day = _dayOf(record);
      if (day == null) {
        out.add(PaceDay.noRecord(date));
        continue;
      }
      out.add(day);
      found++;
    }
    // 뒤에 붙은 빈 날은 떼어낸다. 찾은 것보다 뒤라 볼 일이 없고, 이레 내내
    // 빈손인 사람에게 "기록 없음" 일곱 줄만 남는 것도 막는다.
    while (out.isNotEmpty && !out.last.hasRecord) {
      out.removeLast();
    }
    return found == 0 ? const [] : out;
  }

  /// 프롬프트에 실을 블록. 셀 것이 없으면 빈 문자열.
  ///
  /// [todayTasks]는 오늘 목록, [now]는 지금, [minutesLeft]는 잠들기까지 남은
  /// 시간(모르면 null), [busyBlock]은 늘 시간을 못 내는 때를 적어둔 블록.
  ///
  /// [busyBlock]은 "지금이 바쁜지"가 아니라 하루 전체를 담는다. 지금만 넘기던
  /// 동안에는 오전에 연 사람에게 오후 근무가 안 보여서, 못 쓰는 시간에 하라는
  /// 말이 나올 수 있었다.
  static String block({
    required String? historyRaw,
    required List<dynamic> todayTasks,
    required DateTime now,
    int? minutesLeft,
    String busyBlock = '',
  }) {
    final days = recent(historyRaw, now: now);
    if (days.isEmpty) return '';

    final buffer = StringBuffer('\n[최근 - 앱이 기록에서 센 값]\n');
    for (final day in days) {
      buffer.writeln(_dayLine(day));
      for (final task in day.tasks) {
        buffer.writeln('  ${_taskLine(task)}');
      }
      final hidden = day.planned - day.tasks.length;
      if (hidden > 0) buffer.writeln('  …외 $hidden개');
    }
    // 빈 날을 "아무것도 안 한 날"로 읽으면 틀린 말이 된다. 기록은 앱을 열었을
    // 때만 쌓이므로, 앱 밖에서 한 일은 어차피 여기 없다.
    if (days.any((day) => !day.hasRecord)) {
      buffer.writeln('*기록 없는 날은 앱을 안 열었을 수 있습니다. 아무것도 안 했다고 보지 마세요.');
    }

    buffer.write(_todayBlock(todayTasks, now, minutesLeft));
    buffer.writeln('- 위 숫자는 앱이 기록에서 센 값. 여기 없는 것은 세지 않았음.');
    buffer.write(busyBlock);
    return buffer.toString();
  }

  /// 오늘 목록을 항목마다 한 줄씩. 목록이 비면 그렇다고 적는다.
  ///
  /// [block]의 오늘 칸은 개수만 센다. 그쪽은 오늘 어디까지 왔는지를 보는 자리라
  /// 그걸로 충분하고, 이쪽은 어느 항목에 무엇을 해보라고 말하는 자리라 항목이
  /// 필요하다.
  ///
  /// 시각을 정해둔 일은 그 시각을 함께 적는다. 몇 시에 하기로 해뒀는지를 모르면
  /// "지금 해보세요"가 그 시각 전에 나갈 수 있다.
  static String todayListBlock({
    required List<dynamic> tasks,
    required DateTime now,
    int limit = maxTasksPerDay,
  }) {
    final lines = <String>[];
    var planned = 0;
    var touched = 0;
    var done = 0;
    for (final task in tasks) {
      if (task is! Map) continue;
      planned++;
      final isDone = task['done'] == true;
      final started = _isStarted(task);
      if (isDone || started) touched++;
      if (isDone) done++;
      final name = _shortName(task['text']?.toString());
      if (name == null || lines.length >= limit) continue;
      final at = _hhmmLabel(task['timeStart']?.toString());
      final state = isDone
          ? '끝냄${_doneAtLabel(task['completedAt'])}'
          : started
          ? '손만 댐'
          : '그대로';
      lines.add('- $name${at == null ? '' : '($at)'} — $state');
    }

    final buffer = StringBuffer('\n[오늘 목록 - 지금 ${_clockMinutes(now)}]\n');
    if (planned == 0) {
      buffer.writeln('아직 적어둔 것이 없습니다.');
      return buffer.toString();
    }
    buffer.writeln('적은 것 $planned개 / 손댄 것 $touched개 / 끝낸 것 $done개');
    for (final line in lines) {
      buffer.writeln(line);
    }
    final hidden = planned - lines.length;
    if (hidden > 0) buffer.writeln('…외 $hidden개');
    return buffer.toString();
  }

  static String _doneAtLabel(Object? raw) {
    final at = DateTime.tryParse(raw?.toString() ?? '');
    return at == null ? '' : '(${_clock(at.hour)})';
  }

  /// "14:00"을 "오후 2시"로. 못 읽으면 null.
  static String? _hhmmLabel(String? hhmm) {
    final parts = (hhmm ?? '').split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    if (hour == null) return null;
    final minute = int.tryParse(parts[1]) ?? 0;
    return minute == 0
        ? _clock(hour)
        : '${_clock(hour)} ${minute.toString().padLeft(2, '0')}분';
  }

  static String _dayLine(PaceDay day) {
    if (!day.hasRecord) return '${day.date}  기록 없음';
    final parts = [
      '적은 것 ${day.planned}개',
      '손댄 것 ${day.touched}개',
      '끝낸 것 ${day.done}개',
    ];
    if (day.firstStartHour != null) {
      parts.add('첫 시작 ${_clock(day.firstStartHour!)}');
    }
    return '${day.date}  ${parts.join(' / ')}';
  }

  /// "보고서 — 끝냄(밤 11시)" 한 줄.
  static String _taskLine(PaceTask task) {
    if (task.done) {
      final when = task.doneHour == null ? '' : '(${_clock(task.doneHour!)})';
      return '${task.name} — 끝냄$when';
    }
    if (task.started) {
      final when = task.startHour == null
          ? ''
          : '(${_clock(task.startHour!)} 시작)';
      return '${task.name} — 손만 댐$when';
    }
    return '${task.name} — 그대로';
  }

  static String _todayBlock(
    List<dynamic> todayTasks,
    DateTime now,
    int? minutesLeft,
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
    // 오늘 날짜를 같이 적는다. 위 날짜들과 견줘야 "며칠 만에"가 나온다.
    buffer.writeln(
      '${DateFormat('yyyy-MM-dd').format(now)} ${_clockMinutes(now)} / '
      '적은 것 $planned개 / 손댄 것 $touched개 / 끝낸 것 $done개',
    );
    if (minutesLeft != null && minutesLeft > 0) {
      final hours = minutesLeft ~/ 60;
      final mins = minutesLeft % 60;
      buffer.writeln(
        '잠들기까지 약 ${hours > 0 ? '$hours시간' : ''}'
        '${mins > 0 ? '${hours > 0 ? ' ' : ''}$mins분' : ''}',
      );
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

    var planned = 0;
    var touched = 0;
    var done = 0;
    int? firstStartHour;
    final out = <PaceTask>[];

    for (final task in (record['tasks'] as List?) ?? const []) {
      if (task is! Map) continue;
      planned++;
      final isDone = task['done'] == true;
      final started = _isStarted(task);
      if (isDone || started) touched++;
      if (isDone) done++;

      final startHour = _hourOnDate(task['startedAt'], date);
      if (startHour != null &&
          (firstStartHour == null || startHour < firstStartHour)) {
        firstStartHour = startHour;
      }

      // 이름을 못 읽는 항목은 줄로 적지 않는다. 셈에는 이미 들어갔다 — 예전에는
      // 셈이 이름 고르는 안쪽에 있어서, 이름이 빈 항목은 끝냈어도 완료로
      // 세지지 않았다.
      final name = _shortName(task['text']?.toString());
      if (name == null || out.length >= maxTasksPerDay) continue;
      out.add(
        PaceTask(
          name: name,
          done: isDone,
          started: started,
          startHour: startHour,
          doneHour: _hourOnDate(task['completedAt'], date),
        ),
      );
    }

    return PaceDay(
      date: date,
      planned: planned,
      touched: touched,
      done: done,
      firstStartHour: firstStartHour,
      tasks: out,
    );
  }

  /// 그날 것인 시각만 시로 돌려준다.
  ///
  /// 자정을 넘겨 찍힌 것은 다음 날 시각이다. 그걸 그날 것으로 세면 하루가
  /// 새벽에 끝난 것처럼 읽힌다.
  static int? _hourOnDate(Object? raw, String date) {
    final at = DateTime.tryParse(raw?.toString() ?? '');
    if (at == null) return null;
    return DateFormat('yyyy-MM-dd').format(at) == date ? at.hour : null;
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
