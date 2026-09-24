import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'busy_hours_service.dart';
import 'gap_fragment_check.dart';
import 'gap_late_menu.dart';
import 'nyang_banner_nudge.dart';

/// 여유 있어 보이는 시각에 냥냥이가 한 마디만 건네는 자리.
///
/// 딴짓 방지 코칭과 하는 일이 반대다. 저쪽은 이미 시작한 일에서 새어 나갔을 때
/// 부르지만, 이쪽은 아무것도 안 하고 있을 때 "이따 할 일을 조금 가볍게 해둘래?"
/// 하고 물어본다. 그래서 일정 이름을 말하지 않고, 무엇을 할지도 정해주지 않는다.
///
/// 재촉이 아니다. 무시해도 다시 부르지 않고, 했는지 세지도 않는다. 쉬는 시간을
/// 새 일정으로 만드는 기능이 아니라서, 그 순간을 놓치면 그냥 지나간다.
///
/// 마스터 플랜 전용이다.
class GapCoachingService {
  /// 딴짓 방지 코칭과 같은 채널을 쓴다. 안드로이드에서 자리를 하나 더 맡는
  /// 것뿐이라, 같은 네이티브 층이 예약과 노출을 함께 관리한다.
  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/ongoing_nudge',
  );

  /// 이 세 값은 'nyang_'으로 시작한다.
  ///
  /// 모닝콜 시각과 같은 성격의 사용자 설정이라 기기를 바꿔도 따라와야 한다.
  /// 반대로 "오늘 이미 나갔는지" 같은 이 기기에서만 뜻이 있는 값은 네이티브가
  /// 접두어 없는 키에 따로 적는다 — 그건 클라우드 복원에 덮이면 안 된다.
  static const String enabledKey = 'nyang_gap_coaching_enabled';
  static const String timesKey = 'nyang_gap_coaching_times';

  /// 참견할 요일. "1,2,3,4,5" 꼴로 월=1 ... 일=7.
  ///
  /// 매일 참견받으면 지친다는 말에서 나온 자리다. 주말엔 놔뒀으면 하는 사람이
  /// 스위치를 통째로 끄는 것 말고는 방법이 없었다.
  static const String daysKey = 'nyang_gap_coaching_days';

  /// 하루에 셋까지.
  static const int maxTimes = 3;

  /// 처음 켤 때 하나만 준다. 두 번째는 필요한 사람이 직접 더한다.
  static const TimeOfDay defaultTime = TimeOfDay(hour: 15, minute: 30);

  /// 아무것도 안 정해뒀을 때의 요일. 월~일 전부다.
  ///
  /// 이 설정이 생기기 전부터 켜둔 사람이 갑자기 조용해지면 안 된다. 켜둔 적도
  /// 없는 요일 설정 때문에 기능이 멈춘 것은 사용자 눈에 고장과 구별되지 않는다.
  static const Set<int> defaultDays = {1, 2, 3, 4, 5, 6, 7};

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(enabledKey) ?? false;
  }

  static Future<List<TimeOfDay>> times() async {
    final prefs = await SharedPreferences.getInstance();
    return parseTimes(prefs.getString(timesKey));
  }

  static List<TimeOfDay> parseTimes(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    final result = <TimeOfDay>[];
    for (final part in raw.split(',')) {
      final time = parseTime(part.trim());
      if (time != null) result.add(time);
      if (result.length >= maxTimes) break;
    }
    return result;
  }

  static TimeOfDay? parseTime(String raw) {
    final parts = raw.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static Future<Set<int>> days() async {
    final prefs = await SharedPreferences.getInstance();
    return parseDays(prefs.getString(daysKey));
  }

  /// "1,3,5"를 요일 집합으로. 비어 있거나 못 읽으면 매일로 본다.
  static Set<int> parseDays(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaultDays;
    final result = <int>{};
    for (final part in raw.split(',')) {
      final day = int.tryParse(part.trim());
      if (day == null || day < 1 || day > 7) continue;
      result.add(day);
    }
    // 하나도 못 읽었으면 저장이 깨진 것이다. 그대로 비워두면 켜져 있는데
    // 영영 안 나가는 상태가 된다.
    return result.isEmpty ? defaultDays : result;
  }

  static String formatDays(Set<int> days) => (days.toList()..sort()).join(',');

  /// 그날 참견하는 요일인지. 네이티브도 같은 규칙을 본다.
  static bool runsOn(DateTime date, Set<int> days) =>
      days.contains(date.weekday);

  /// 설정 줄에 쓸 요일 표기. "매일" / "평일만" / "월·수·금".
  static String daysLabel(Set<int> days) {
    if (days.length == 7) return '매일';
    if (days.length == 5 && const {1, 2, 3, 4, 5}.every(days.contains)) {
      return '평일만';
    }
    if (days.length == 2 && const {6, 7}.every(days.contains)) return '주말만';
    const names = ['월', '화', '수', '목', '금', '토', '일'];
    return (days.toList()..sort()).map((day) => names[day - 1]).join('·');
  }

  static String formatTime(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';

  /// 설정 줄에 쓸 표기. "오전 10:30 · 오후 3:30".
  static String label(TimeOfDay time) {
    final ampm = time.hour < 12 ? '오전' : '오후';
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    return '$ampm $hour12:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 남은 일은 있는데 이름을 부를 만한 것이 없을 때.
  static const String fallbackBody = '이따 할 일, 10분만 먼저 해두면 훨씬 가벼워질 거라냥.';

  /// 오늘 아무것도 적어두지 않았을 때.
  ///
  /// 앞당길 대상이 없는 사람에게 "미리 해두라"고 하면 없는 일을 하라는 말이 된다.
  /// 이때 도움이 되는 것은 하나 정해두는 쪽이다.
  static const String emptyBody =
      '오늘 뭘 할지 아직 안 정했다냥. 10분만 써서 하나만 정해둬도 훨씬 수월해질 거라냥.';

  /// 카드·배너 한 줄에 들어가는 이름 길이.
  static const int _nameLimit = 14;

  /// 카드 한 줄 전체가 넘지 않는 길이.
  ///
  /// 고정 문구 중 가장 긴 [emptyBody]와 같은 자리에 둔다. 그 문구가 카드에서
  /// 멀쩡하게 보이니, 거기까지는 늘어나도 된다는 뜻이다.
  ///
  /// 이름과 조각이 둘 다 길면 넘긴다 — 조각은 코치가 지은 말이라 자를 수
  /// 없으니, 넘치는 만큼 이름 쪽을 더 줄인다.
  static const int bodyLimit = 48;

  /// 만들기 전에 무엇을 만들지부터 정해야 하는 일.
  static const List<String> _conceptWords = [
    '기획',
    '아이디어',
    '콘텐츠',
    '카드뉴스',
    '디자인',
    '영상',
    '캠페인',
    '컨셉',
    '콘셉',
    '시안',
    '네이밍',
    '브레인',
    '로고',
    '굿즈',
    '썸네일',
  ];

  /// 첫 줄이 안 나와서 미루게 되는 일.
  static const List<String> _firstLineWords = [
    '글',
    '원고',
    '에세이',
    '블로그',
    '메일',
    '편지',
    '일기',
    '소설',
    '후기',
    '리뷰',
    '대본',
    '스크립트',
    '기사',
    '자소서',
  ];

  /// 무슨 말을 어떤 순서로 할지가 반인 일.
  ///
  /// [_firstLineWords]와 겹쳐 보이지만 하는 일이 다르다. 저쪽은 시작 장벽을
  /// 없애는 말이고 이쪽은 구조를 미리 잡는 말이다 — 발표 자료에 "첫문장만
  /// 준비해둬"는 약하고, 일기에 "개요 잡아둬"는 과하다.
  static const List<String> _outlineWords = [
    '보고서',
    '리포트',
    '발표',
    '제안',
    '논문',
    '계획서',
    '문서',
    '강의',
    '수업',
    '이력서',
    '정리해서',
    '회의록',
  ];

  /// 머리가 아니라 몸이 움직여야 하는 일.
  ///
  /// 이런 일은 생각이 막는 게 아니라 나가는 것이 막는다. 미리 해두라고 하면
  /// 그냥 지금 하라는 말이 되니, 문턱인 준비 쪽만 한 칸 앞당긴다.
  static const List<String> _bodyWords = [
    '운동',
    '헬스',
    '러닝',
    '조깅',
    '요가',
    '필라테스',
    '산책',
    '수영',
    '등산',
    '스트레칭',
    '청소',
    '설거지',
    '빨래',
    '장보기',
    '마트',
    '외출',
    '이사',
    '정리정돈',
  ];

  /// 그 시각에 건넬 한 줄. 안드로이드의 GapCoachingCopy와 같은 규칙이다.
  ///
  /// "이따 할 일"이라고만 하면 아무 일도 떠오르지 않는다. 이름을 불러줘야 무엇을
  /// 10분 앞당길지가 눈앞에 선다. 말투도 그 일에 맞춘다 — 기획하는 일에 "미리
  /// 해두라"고 하면 무엇을 하라는 건지 알 수 없고, 반대로 설거지에 "개요를
  /// 생각해두라"고 하면 웃긴다.
  static String bodyFor(List tasks, DateTime at, {bool plannedAhead = false}) {
    final name = _pickTaskName(tasks, at);
    if (name == null) {
      // 이름 부를 것이 없어도 남아 있는 일이 있으면 "이따 할 일"이다.
      // 아예 비어 있을 때만 정하자고 권한다.
      return hasAnyRemaining(tasks) || plannedAhead ? fallbackBody : emptyBody;
    }
    if (_conceptWords.any(name.contains)) {
      return _fit(name, (n) => "이따 할 '$n' 10분간 콘셉트만 생각해둬도 훨씬 가벼워질 거라냥.");
    }
    if (_outlineWords.any(name.contains)) {
      return _fit(name, (n) => "이따 할 '$n' 10분간 개요만 대충 잡아둬도 훨씬 가벼워질 거라냥.");
    }
    if (_firstLineWords.any(name.contains)) {
      return _fit(name, (n) => "이따 할 '$n' 10분간 첫문장만 준비해둬도 훨씬 가벼워질 거라냥.");
    }
    if (_bodyWords.any(name.contains)) {
      return _fit(name, (n) => "이따 할 '$n' 10분간 뭐부터 준비할지만 정해둬도 훨씬 움직이기 좋을 거라냥.");
    }
    return _fit(name, (n) => "이따 할 '$n' 10분만 미리 해두면 훨씬 가벼워질 거라냥.");
  }

  /// [bodyLimit] 안에 들어가는 한 줄. 넘치면 이름을 더 줄여서 다시 짓는다.
  ///
  /// 틀마다 뒤에 붙는 말의 길이가 달라서, 이름 길이 하나로 맞출 수는 없다.
  /// 짧은 이름은 그대로 두고, 넘칠 때만 한 글자씩 물러난다.
  static String _fit(String name, String Function(String shown) build) {
    for (var limit = _nameLimit; limit > _nameFloor; limit--) {
      final line = build(_shorten(name, limit: limit));
      if (line.length <= bodyLimit) return line;
    }
    return build(_shorten(name, limit: _nameFloor));
  }

  /// 아무리 줄여도 여기까지만. 이보다 짧으면 무슨 일인지 알 수 없다.
  static const int _nameFloor = 6;

  /// 머리로 하는 일인지. 10분을 앞당겨 얻는 것이 가장 큰 쪽이다.
  static bool _isMindWork(String name) =>
      _conceptWords.any(name.contains) ||
      _outlineWords.any(name.contains) ||
      _firstLineWords.any(name.contains);

  static String _shorten(String text, {int limit = _nameLimit}) =>
      text.length <= limit ? text : '${text.substring(0, limit)}…';

  /// 아직 안 끝낸 일이 하나라도 있는지. 약속도 센다.
  static bool hasAnyRemaining(List tasks) =>
      tasks.any((item) => item is Map && item['done'] != true);

  /// 오늘 할 일을 다 끝냈는지.
  ///
  /// 다 한 사람에게 여유 있냐고 묻는 것은 칭찬이 아니라 잔소리다. 그날 그 시각은
  /// 그냥 지나간다. 아무것도 적어두지 않은 사람과는 구분해야 한다 — 그쪽에는
  /// 하나 정해두자고 권할 말이 있다.
  static bool isDayFinished(List tasks) =>
      !hasAnyRemaining(tasks) &&
      tasks.any((item) => item is Map && item['done'] == true);

  /// 이름을 불러줄 일 하나.
  ///
  /// 머리로 하는 일이 하나라도 있으면 그것부터 부른다. 10분을 앞당겨 가장 크게
  /// 달라지는 쪽이라서다 — 콘셉트든 개요든 첫 줄이든, 미리 굴려둔 것이 있으면
  /// 그 뒤가 통째로 수월해진다. 몸으로 하는 일은 그 10분이 준비 한 칸을
  /// 앞당기는 정도다.
  ///
  /// 같은 갈래 안에서는 [at] 뒤에 오는 시각이 정해진 일이 먼저다.
  static String? _pickTaskName(List tasks, DateTime at) =>
      _pickTask(tasks, at)?['text']?.toString().trim();

  /// 이름을 불러줄 일 하나. 항목째로 돌려준다 — 안드로이드에 넘길 때 그 일이
  /// 아직 그대로인지 확인할 id가 필요하다.
  static Map? _pickTask(List tasks, DateTime at) {
    // 사전 문구는 전부 "이따 할 ~ 미리 해두면"이라, 이미 손댄 일에는 못 쓴다.
    final items = _candidates(
      tasks,
      at,
    ).where((item) => !_touched(item)).toList(growable: false);
    if (items.isEmpty) return null;
    return items.firstWhere(
      (item) => _isMindWork(item['text']?.toString() ?? ''),
      orElse: () => items.first,
    );
  }

  /// 이름을 부를 수 있는 일들. 부르고 싶은 순서대로.
  ///
  /// 손댄 일도 넣는다. 아직 안 건드린 일에는 시작이 쉬워지는 준비가, 하는
  /// 중인 일에는 이어갈 다음 조각이 맞는데 — 그 판단은 코치가 한다. 앱이
  /// 갈라두면 갈래가 안 맞는 사람에게 엉뚱한 말이 나간다.
  ///
  /// 약속(schedule)은 시각에 가서 하는 것이라 10분을 앞당길 자리가 없어 뺀다.
  static List<Map> _candidates(List tasks, DateTime at) {
    final atMinutes = at.hour * 60 + at.minute;
    final untimed = <Map>[];
    final timed = <MapEntry<int, Map>>[];

    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['category'] == 'schedule') continue;
      final text = item['text']?.toString().trim() ?? '';
      if (text.isEmpty) continue;

      final parts = (item['timeStart']?.toString() ?? '').split(':');
      final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
      final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
      if (hour == null || minute == null) {
        untimed.add(item);
        continue;
      }
      final minutes = hour * 60 + minute;
      // 시각이 지났는데 손도 안 댄 일은 "이따"가 아니다. 손댄 일은 시각이
      // 지났어도 지금 붙잡고 있는 일이라 그대로 둔다.
      if (minutes <= atMinutes && !_touched(item)) continue;
      timed.add(MapEntry(minutes, item));
    }

    timed.sort((a, b) => a.key.compareTo(b.key));
    return [...timed.map((e) => e.value), ...untimed];
  }

  /// 한 번이라도 손댄 일인지.
  ///
  /// 도는 중인 것과 쌓인 시간만 보던 자리다. 눌렀다가 곧바로 멈춘 일은 둘 다
  /// 0으로 남아서 "아예 안 건드린 일"로 통과했다. 시작 표시가 남아 있으면
  /// 그것도 손댄 것이다 — 채팅 쪽 인사가 보는 표시와 같은 것을 본다.
  static bool _touched(Map item) {
    if (item['inProgress'] == true) return true;
    if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) return true;
    final inProgressAt = item['inProgressAt']?.toString().trim() ?? '';
    final runStartedAt = item['runStartedAt']?.toString().trim() ?? '';
    return inProgressAt.isNotEmpty || runStartedAt.isNotEmpty;
  }

  /// 안드로이드 카드가 읽어갈 자리.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기에서 방금 만든 값이라 클라우드가
  /// 덮으면 안 되고, 다른 기기에서 만든 문장이 내려와도 뜻이 없다.
  /// 네이티브에서는 'flutter.' 가 붙은 이름으로 읽는다.
  static const String preparedCardKey = 'gap_coaching_card';

  /// 안드로이드 카드에 쓸 문장을 미리 만들어 저장한다.
  ///
  /// 원래는 알림이 뜨는 순간에 네이티브가 목록을 읽어 직접 만들었다. 앱이 꺼져
  /// 있어도 돌아야 해서 그랬는데, 그러면 같은 판단이 Dart와 코틀린에 두 벌
  /// 있게 된다 — 한쪽만 고치면 두 폰이 다른 말을 한다.
  ///
  /// 아이폰은 어차피 미리 만들 수밖에 없다. 알림을 예약할 때 문구가 굳어서
  /// 그 시각에는 앱 코드가 낄 자리가 없기 때문이다. 그래서 양쪽을 미리 만드는
  /// 쪽으로 맞추고, 판단은 여기 한 곳에만 둔다.
  ///
  /// 미리 만든 문장은 낡을 수 있다. 아침에 만든 "'분기 리포트' 개요 잡을까"를
  /// 그 일을 끝낸 오후에 띄우면 엉뚱하다. 그래서 고른 일의 id를 함께 적어두고,
  /// 네이티브는 띄우기 전에 그 일이 아직 남아 있는지만 확인한다. 확인이
  /// 목록 하나만 보면 되므로 판단이 두 벌로 늘지 않는다.
  ///
  /// 만든 날짜도 같이 적는다. id만 보면 어제 일이 오늘까지 넘어온 경우를
  /// 못 거른다 — 앱을 하루 종일 안 연 사람에게 어제 만든 말이 그대로 나간다.
  static Future<void> prepareCard(
    SharedPreferences prefs, {
    DateTime? at,
  }) async {
    final tasks = _decodeTasks(prefs.getString('nyang_tasks'));
    final now = at ?? DateTime.now();
    final late = lateSuggestionFor(prefs, tasks, now);
    final prep = late == null ? await _prepFor(prefs, tasks, now) : null;

    // 코치가 고른 일이 있으면 그 일의 id를 적어둔다. 문장이 부르는 일과
    // 네이티브가 확인하는 일이 다르면, 끝낸 일 이름을 그대로 띄우게 된다.
    final picked = late == null
        ? (_taskNamed(tasks, prep?.task) ?? _pickTask(tasks, now))
        : null;

    // 전날 밤에 짜둔 계획은 아직 오늘 목록에 없다. 그걸 안 보면 계획을 다
    // 짜둔 사람에게 "아직 안 정했다"고 말하고, 버튼도 정하자는 쪽을 가리킨다.
    final ahead = plannedAhead(prefs, now);

    final body =
        late?.body ?? bodyWithPrep(prep, tasks, now, plannedAhead: ahead);
    final name = picked?['text']?.toString().trim();
    final button = late == null && (name == null || name.isEmpty)
        ? (hasAnyRemaining(tasks) || ahead ? buttonDefault : buttonPlan)
        : buttonDefault;

    // 늦은 쪽 문장이 부른 일도 함께 적어둔다. 그 일을 그새 끝냈으면 다른 말이
    // 나가야 한다.
    final taskId = late?.taskId ?? picked?['id']?.toString();

    await prefs.setString(
      preparedCardKey,
      jsonEncode({
        'date': _dateKey(now),
        'body': body,
        'button': button,
        if (taskId != null) 'taskId': taskId,
      }),
    );
  }

  /// 그 시각에 건넬 한 줄.
  ///
  /// 조각을 받아왔으면 그걸 쓰고, 못 받아왔으면 사전으로 떨어진다. 두 폰이
  /// 같은 자리를 지나가야 서로 다른 말을 하지 않는다.
  ///
  /// [mayAsk]가 참일 때만 모델에게 물어본다. 아이폰은 자리를 여러 개 한꺼번에
  /// 거는데, 자리마다 물어보면 하루 한 번이 네 번이 된다. 그래서 물어보는 것은
  /// "지금" 한 번뿐이고, 나머지 자리는 그 답이 자기 일과 맞을 때만 가져다 쓴다.
  static Future<String> bodyForSlot(
    SharedPreferences prefs,
    List tasks,
    DateTime at, {
    bool mayAsk = false,
  }) async {
    // 하루가 얼마 안 남았으면 앞당기자는 말이 안 통한다. 이따 할 시간이
    // 없는데 미리 해두라는 말이 되기 때문이다.
    final late = lateSuggestionFor(prefs, tasks, at);
    if (late != null) return late.body;

    final prep = mayAsk
        ? await _prepFor(prefs, tasks, at)
        : _cachedPrep(prefs, tasks, at);
    return bodyWithPrep(prep, tasks, at, plannedAhead: plannedAhead(prefs, at));
  }

  /// 이름을 부르지 않는 한 줄. 목록이 낡았을 수 있는 자리에서 쓴다.
  ///
  /// 안드로이드 네이티브가 낡은 카드를 버리고 떨어지는 자리와 같은 문장이다.
  static String namelessBody(
    SharedPreferences prefs,
    List tasks,
    DateTime at,
  ) => hasAnyRemaining(tasks) || plannedAhead(prefs, at)
      ? fallbackBody
      : emptyBody;

  /// 그날 하기로 미리 적어둔 것이 있는지.
  ///
  /// 오늘 목록만 보면 안 된다. 전날 밤에 짜둔 계획은 날짜별 보관함에 들어가
  /// 있다가, 그날 앱을 처음 열 때 오늘 목록으로 옮겨진다. 그 전에 카드가
  /// 뜨면 계획을 다 짜둔 사람에게 "아직 안 정했다"고 말하게 된다.
  ///
  /// 안드로이드 GapCoachingCopy도 같은 자리를 본다.
  static bool plannedAhead(SharedPreferences prefs, DateTime at) {
    final raw = prefs.getString(_plannedByDateKey);
    if (raw == null || raw.isEmpty) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final planned = decoded[_dateKey(at)];
      if (planned is! List) return false;
      return planned.any((item) => item is Map && item['done'] != true);
    } catch (_) {
      return false;
    }
  }

  /// 날짜별 계획 보관함. `DailyResetService.plannedTasksByDateKey`와 같은 이름이다.
  static const String _plannedByDateKey = 'nyang_today_tasks_by_date';

  /// 코치가 고른 조각이 있으면 그걸로, 없으면 사전으로.
  static String bodyWithPrep(
    GapPrep? prep,
    List tasks,
    DateTime at, {
    bool plannedAhead = false,
  }) {
    if (prep != null) {
      return fragmentBody(name: prep.task, fragment: prep.prep);
    }
    // 사전 문구는 아직 시작 안 한 일에만 쓰는 말들이라, 남은 게 전부 손댄
    // 일이면 거기로 갈 수 없다.
    if (_pickTask(tasks, at) == null && _candidates(tasks, at).isNotEmpty) {
      return finishFallbackBody;
    }
    return bodyFor(tasks, at, plannedAhead: plannedAhead);
  }

  /// 이름이 같은 일. 없으면 null.
  static Map? _taskNamed(List tasks, String? name) {
    if (name == null || name.isEmpty) return null;
    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['text']?.toString().trim() == name) return item;
    }
    return null;
  }

  /// 카드 아래 버튼에 적을 말. 코틀린 쪽과 같은 값이라 여기서 넘긴다.
  static const String buttonDefault = '이따 할 일 바로 보기';
  static const String buttonPlan = '오늘 할 일 정하기';

  /// 조각을 받아왔을 때 쓰는 문장.
  ///
  /// 조각 자리에 무엇이 들어와도 말이 되게 "~에 쓸까"로 받는다. 사전이 쓰던
  /// "개요만 잡아둬도"류는 조각 모양이 정해져 있을 때만 되는 틀이라, 모델이
  /// 만들어 오는 말에는 안 맞는다.
  ///
  /// "이따 할"을 빼둔다. 하는 중인 일도 코치가 고르는데, 그 일에 '이따 할'을
  /// 붙이면 이미 붙잡고 있는 일을 나중 일로 만든다.
  ///
  /// 10분이다. 그보다 길면 조각이 아니라 또 하나의 일이 된다.
  static String fragmentBody({
    required String name,
    required String fragment,
  }) => _fit(name, (n) => "'$n' 지금 10분만 $fragment에 써볼까냥?");

  /// 남은 일에 다 손은 댔을 때. 조각을 못 받아왔을 때 쓴다.
  ///
  /// "먼저 해두면 가벼워진다"는 아직 시작 안 한 사람에게 하는 말이라, 시작을
  /// 다 해둔 사람에게는 이미 한 일을 또 하라는 말이 된다.
  static const String finishFallbackBody =
      '시작해둔 게 있다냥. 지금 10분만 더 붙이면 훨씬 수월해질 거라냥.';

  /// 늦은 시각이면 그때 건넬 한 수. 이른 시각이거나 건넬 것이 없으면 null.
  static GapLateSuggestion? lateSuggestionFor(
    SharedPreferences prefs,
    List tasks,
    DateTime at,
  ) {
    if (!GapLateMenu.isLate(
      at,
      bedtime: prefs.getString('nyang_premium_min_sleep_time'),
    )) {
      return null;
    }
    return GapLateMenu.suggest(
      tasks: tasks,
      coreTasks: _decodeTasks(prefs.getString('nyang_core_tasks')),
    );
  }

  /// 오늘 조각을 받아둔 자리. `{"date","taskId","fragment","asked"}`.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기에서 오늘 물어봤다는 사실이라
  /// 클라우드가 덮으면 안 된다.
  static const String fragmentCacheKey = 'gap_fragment_cache';

  /// 하루에 물어볼 수 있는 횟수.
  ///
  /// 부를 일이 바뀌면 조각도 다시 받아야 한다 — 끝낸 일 이름을 계속 부를 수는
  /// 없다. 그런데 그 판단이 앱을 열 때마다 돌아서, 하루에 일을 여럿 끝내는
  /// 사람은 그만큼 물어보게 된다.
  ///
  /// 정작 카드는 하루 두 번까지만 뜬다. 그보다 많이 물어본 몫은 뜨지도 않을
  /// 문구를 만든 것이라 그냥 버려진다. 한 번쯤 여유를 두고 셋에서 끊는다.
  static const int maxFragmentAsksPerDay = 3;

  /// 준비 하나. 오늘 같은 목록으로 이미 물어봤으면 그걸 다시 쓴다.
  ///
  /// [GapCoachingService.sync]는 앱을 열 때마다 돈다. 여기서 그냥 물어보면
  /// 하루에 앱 연 횟수만큼 결제된다 — 하루 30번 열면 서른 번이다. 그래서
  /// 하루 한 번, 그것도 목록이 바뀌었을 때만 묻는다.
  static Future<GapPrep?> _prepFor(
    SharedPreferences prefs,
    List tasks,
    DateTime now,
  ) async {
    final candidates = _candidates(tasks, now);
    if (candidates.isEmpty) return null;
    final names = _namesOf(candidates);
    final cores = _coreNames(prefs, names);

    // 그 시각에 무엇에 매여 있는지. 회사에 있는 사람과 집에 있는 사람은 지금
    // 해둘 수 있는 것이 다르다.
    final situation = BusyHoursService.situationAt(prefs, now);
    final signature = _signature(
      names: names,
      cores: cores,
      situation: situation,
    );

    final today = _dateKey(now);
    if (_hasFragmentAnswer(prefs, signature, now)) {
      return _cachedPrep(prefs, tasks, now);
    }

    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    final askedToday = cached != null && cached['date'] == today
        ? (int.tryParse(cached['asked'] ?? '') ?? 0)
        : 0;
    if (askedToday >= maxFragmentAsksPerDay) return null;

    final prep = await GapFragmentCheck.suggest(
      candidates: candidates
          .map(
            (item) => GapCandidate(
              name: item['text']?.toString().trim() ?? '',
              timeLabel: _timeLabel(item['timeStart']?.toString()),
              started: _touched(item),
            ),
          )
          .toList(growable: false),
      at: now,
      cores: cores,
      situation: situation,
    );
    // 못 받아온 것도 적어둔다. 안 적으면 통신이 끊긴 날 앱을 열 때마다 다시
    // 물어보게 된다.
    await prefs.setString(
      fragmentCacheKey,
      jsonEncode({
        'date': today,
        'taskId': signature,
        'asked': askedToday + 1,
        if (prep != null) 'task': prep.task,
        if (prep != null) 'fragment': prep.prep,
      }),
    );
    return prep;
  }

  static List<String> _namesOf(List<Map> items) => items
      .map((item) => item['text']?.toString().trim() ?? '')
      .where((name) => name.isNotEmpty)
      .toList(growable: false);

  /// "07:30" -> "오전 7:30". 시각이 없으면 null.
  static String? _timeLabel(String? hhmm) {
    final parts = (hhmm ?? '').split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    final meridiem = hour >= 12 ? '오후' : '오전';
    final shown = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$meridiem $shown:${minute.toString().padLeft(2, '0')}';
  }

  /// 오늘의 핵심 중 위 목록에 남아 있는 것들.
  ///
  /// 이미 끝냈거나 손댄 핵심은 빠진다. 끝낸 일을 "먼저 보라"고 넘기면 코치가
  /// 그 일을 고르고, 카드는 다 한 일을 불러준다.
  static List<String> _coreNames(
    SharedPreferences prefs,
    List<String> candidates,
  ) => _decodeTasks(prefs.getString('nyang_core_tasks'))
      .map((item) => item is Map ? item['text']?.toString().trim() ?? '' : '')
      .where(candidates.contains)
      .toList(growable: false);

  /// 같은 목록으로 또 묻지 않으려고 적어두는 값.
  static String _signature({
    required List<String> names,
    required List<String> cores,
    String? situation,
  }) => '${situation ?? ''}>${cores.join('|')}>${names.join('|')}';

  /// 오늘 몇 번 물어봤는지. 테스트와 진단용.
  @visibleForTesting
  static int fragmentAsksToday(SharedPreferences prefs, DateTime now) {
    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    if (cached == null || cached['date'] != _dateKey(now)) return 0;
    return int.tryParse(cached['asked'] ?? '') ?? 0;
  }

  /// 오늘 이 목록으로 이미 물어봤는지. 못 받아온 것도 물어본 것으로 센다.
  static bool _hasFragmentAnswer(
    SharedPreferences prefs,
    String signature,
    DateTime now,
  ) {
    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    return cached != null &&
        cached['date'] == _dateKey(now) &&
        cached['taskId'] == signature;
  }

  /// 오늘 받아둔 준비. 없으면 null. 물어보지 않는다.
  ///
  /// 고른 일이 목록에서 사라졌으면(끝냈거나 지웠으면) 없는 셈 친다. 아이폰은
  /// 자리를 여러 개 한꺼번에 거는데, 그새 끝낸 일을 오후 카드가 다시 부르면
  /// 안 된다.
  static GapPrep? _cachedPrep(
    SharedPreferences prefs,
    List tasks,
    DateTime at,
  ) {
    final names = _namesOf(_candidates(tasks, at));
    if (names.isEmpty) return null;
    final signature = _signature(
      names: names,
      cores: _coreNames(prefs, names),
      situation: BusyHoursService.situationAt(prefs, at),
    );
    if (!_hasFragmentAnswer(prefs, signature, at)) return null;

    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    final task = cached?['task'] ?? '';
    final prep = cached?['fragment'] ?? '';
    if (task.isEmpty || prep.isEmpty) return null;
    if (!names.contains(task)) return null;
    return GapPrep(task: task, prep: prep);
  }

  static Map<String, String>? _readFragmentCache(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  static String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static List _decodeTasks(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded;
      return const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save({
    required bool enabled,
    required List<TimeOfDay> times,
    Set<int>? days,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    // 요일을 하나도 안 남기고 저장하면 켜져 있는데 영영 안 나간다. 화면에서도
    // 마지막 하나는 못 끄게 막지만, 저장하는 쪽에서도 받아주지 않는다.
    await prefs.setString(
      daysKey,
      formatDays(days == null || days.isEmpty ? defaultDays : days),
    );
    // 같은 시각을 두 번 저장하지 않는다. 그대로 두면 두 자리가 같은 시각에
    // 예약되고, 먼저 온 하나만 나간 뒤 나머지는 조용히 버려진다 — 사용자에게는
    // 두 번째 시각을 정해둔 적이 없는 것처럼 보인다.
    final trimmed = <String>[];
    for (final time in times) {
      final formatted = formatTime(time);
      if (trimmed.contains(formatted)) continue;
      trimmed.add(formatted);
      if (trimmed.length >= maxTimes) break;
    }
    await prefs.setBool(enabledKey, enabled && trimmed.isNotEmpty);
    await prefs.setString(timesKey, trimmed.join(','));
    await sync();
  }

  /// 카드가 다음에 뜰 시각. 오늘 남은 자리가 없으면 내일 첫 자리다.
  ///
  /// 문장은 '지금'이 아니라 '그 카드가 뜰 때'를 보고 지어야 한다. 아침에 앱을
  /// 열어 만든 문장이 오후 3시에 뜨는데, 그 사람이 3시에 회사에 있는지 집에
  /// 있는지는 3시를 봐야 안다.
  /// 고른 요일도 함께 본다. 화요일만 켜둔 사람의 문장을 월요일 저녁 상황으로
  /// 지어두면, 정작 화요일에 뜨는 카드가 어제 이야기를 한다.
  @visibleForTesting
  static DateTime nextSlot(
    List<TimeOfDay> slots, {
    DateTime? now,
    Set<int> days = defaultDays,
  }) {
    final at = now ?? DateTime.now();
    final sorted = slots.map((t) => t.hour * 60 + t.minute).toList()..sort();
    // 오늘부터 이레를 본다. 요일을 하나라도 골라뒀으면 그 안에 반드시 걸린다.
    for (var ahead = 0; ahead <= 7; ahead++) {
      final date = DateTime(
        at.year,
        at.month,
        at.day,
      ).add(Duration(days: ahead));
      if (!runsOn(date, days)) continue;
      for (final minutes in sorted) {
        final slot = date.add(Duration(minutes: minutes));
        if (slot.isAfter(at)) return slot;
      }
    }
    // 여기까지 오는 것은 요일이 통째로 비었을 때뿐이다. [parseDays]가 막고
    // 있지만, 막지 못한 값이 들어와도 시각 자체는 돌려준다.
    final tomorrow = DateTime(
      at.year,
      at.month,
      at.day,
    ).add(const Duration(days: 1));
    return tomorrow.add(Duration(minutes: sorted.first));
  }

  /// 걸어뒀던 옛 틈새 자리를 걷어낸다.
  ///
  /// 이 기능이 정해둔 시각마다 따로 카드를 띄우던 때의 자리다. 지금은 적극
  /// 코칭이 그 시각을 후보로 받아 하나로 묶어 부른다 — 둘 다 두면 말투도
  /// 내용도 다른 카드가 1분 사이에 두 번 뜬다.
  ///
  /// 여유 시간 설정 자체는 그대로 쓴다. "이때 들러줘"라는 말은 여전히 유효하고,
  /// 그 값을 읽어가는 쪽이 적극 코칭으로 바뀌었을 뿐이다.
  static Future<void> sync() async {
    if (!isSupported) return;

    if (_isAndroid) {
      try {
        await _channel.invokeMethod('clearGapCoaching');
      } on PlatformException {
        //
      } on MissingPluginException {
        // 네이티브가 아직 없는 빌드.
      }
      return;
    }

    // 다른 배너와 시간이 겹치는지 함께 봐야 해서 예약은 그쪽 한 곳에서 한다.
    await NyangBannerNudge.sync();
  }
}
