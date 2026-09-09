import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import 'gap_fragment_check.dart';
import 'gap_late_menu.dart';
import 'nyang_banner_nudge.dart';

/// 여유 있어 보이는 시각에 냥냥이가 한 마디만 건네는 자리.
///
/// 딴짓 방지 코치와 하는 일이 반대다. 저쪽은 이미 시작한 일에서 새어 나갔을 때
/// 부르지만, 이쪽은 아무것도 안 하고 있을 때 "이따 할 일을 조금 가볍게 해둘래?"
/// 하고 물어본다. 그래서 일정 이름을 말하지 않고, 무엇을 할지도 정해주지 않는다.
///
/// 재촉이 아니다. 무시해도 다시 부르지 않고, 했는지 세지도 않는다. 쉬는 시간을
/// 새 일정으로 만드는 기능이 아니라서, 그 순간을 놓치면 그냥 지나간다.
///
/// 마스터 플랜 전용이다.
class GapCoachingService {
  /// 딴짓 방지 코치와 같은 채널을 쓴다. 안드로이드에서 자리를 하나 더 맡는
  /// 것뿐이라, 같은 네이티브 층이 예약과 노출을 함께 관리한다.
  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/ongoing_nudge',
  );

  /// 이 두 값은 'nyang_'으로 시작한다.
  ///
  /// 모닝콜 시각과 같은 성격의 사용자 설정이라 기기를 바꿔도 따라와야 한다.
  /// 반대로 "오늘 이미 나갔는지" 같은 이 기기에서만 뜻이 있는 값은 네이티브가
  /// 접두어 없는 키에 따로 적는다 — 그건 클라우드 복원에 덮이면 안 된다.
  static const String enabledKey = 'nyang_gap_coaching_enabled';
  static const String timesKey = 'nyang_gap_coaching_times';

  /// 하루에 둘까지.
  static const int maxTimes = 2;

  /// 처음 켤 때 하나만 준다. 두 번째는 필요한 사람이 직접 더한다.
  static const TimeOfDay defaultTime = TimeOfDay(hour: 15, minute: 30);

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
  static String bodyFor(List tasks, DateTime at) {
    final name = _pickTaskName(tasks, at);
    if (name == null) {
      // 이름 부를 것이 없어도 남아 있는 일이 있으면 "이따 할 일"이다.
      // 아예 비어 있을 때만 정하자고 권한다.
      return hasAnyRemaining(tasks) ? fallbackBody : emptyBody;
    }
    final shown = _shorten(name);
    if (_conceptWords.any(name.contains)) {
      return "이따 할 '$shown' 10분간 콘셉트만 생각해둬도 훨씬 가벼워질 거라냥.";
    }
    if (_outlineWords.any(name.contains)) {
      return "이따 할 '$shown' 10분간 개요만 대충 잡아둬도 훨씬 가벼워질 거라냥.";
    }
    if (_firstLineWords.any(name.contains)) {
      return "이따 할 '$shown' 10분간 첫문장만 준비해둬도 훨씬 가벼워질 거라냥.";
    }
    if (_bodyWords.any(name.contains)) {
      return "이따 할 '$shown' 10분간 뭐부터 준비할지만 정해둬도 훨씬 움직이기 좋을 거라냥.";
    }
    return "이따 할 '$shown' 10분만 미리 해두면 훨씬 가벼워질 거라냥.";
  }

  /// 머리로 하는 일인지. 10분을 앞당겨 얻는 것이 가장 큰 쪽이다.
  static bool _isMindWork(String name) =>
      _conceptWords.any(name.contains) ||
      _outlineWords.any(name.contains) ||
      _firstLineWords.any(name.contains);

  static String _shorten(String text) =>
      text.length <= _nameLimit ? text : '${text.substring(0, _nameLimit)}…';

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
    final items = _candidates(tasks, at);
    if (items.isEmpty) return null;
    return items.firstWhere(
      (item) => _isMindWork(item['text']?.toString() ?? ''),
      orElse: () => items.first,
    );
  }

  /// 이름을 부를 수 있는 일들. 부르고 싶은 순서대로.
  ///
  /// 아직 시작하지 않은 일만 본다 — 손을 댄 일에 "미리 해두라"고 할 수는 없다.
  /// 약속(schedule)은 시각에 가서 하는 것이라 10분을 앞당길 자리가 없어 뺀다.
  static List<Map> _candidates(List tasks, DateTime at) {
    final atMinutes = at.hour * 60 + at.minute;
    final untimed = <Map>[];
    final timed = <MapEntry<int, Map>>[];

    for (final item in tasks) {
      if (item is! Map) continue;
      if (item['done'] == true) continue;
      if (item['inProgress'] == true) continue;
      if (((item['elapsedSeconds'] as num?)?.toInt() ?? 0) > 0) continue;
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
      // 이미 지난 시각은 "이따"가 아니다.
      if (minutes <= atMinutes) continue;
      timed.add(MapEntry(minutes, item));
    }

    timed.sort((a, b) => a.key.compareTo(b.key));
    return [...timed.map((e) => e.value), ...untimed];
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
  static Future<void> prepareCard(
    SharedPreferences prefs, {
    DateTime? at,
  }) async {
    final tasks = _decodeTasks(prefs.getString('nyang_tasks'));
    final now = at ?? DateTime.now();
    final late = lateSuggestionFor(prefs, tasks, now);
    final picked = late == null ? _pickTask(tasks, now) : null;

    final body = await bodyForSlot(prefs, tasks, now, mayAsk: true);
    final name = picked?['text']?.toString().trim();
    final button = late == null && (name == null || name.isEmpty)
        ? (hasAnyRemaining(tasks) ? buttonDefault : buttonPlan)
        : buttonDefault;

    // 늦은 쪽 문장이 부른 일도 함께 적어둔다. 그 일을 그새 끝냈으면 다른 말이
    // 나가야 한다.
    final taskId = late?.taskId ?? picked?['id']?.toString();

    await prefs.setString(
      preparedCardKey,
      jsonEncode({
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

    final name = _pickTaskName(tasks, at);
    if (name == null || name.isEmpty) {
      return hasAnyRemaining(tasks) ? fallbackBody : emptyBody;
    }
    final fragment = mayAsk
        ? await _fragmentFor(prefs, name, at)
        : _cachedFragment(prefs, name, at);
    if (fragment == null) return bodyFor(tasks, at);
    return fragmentBody(name: name, fragment: fragment);
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
  /// 15분이다. 30분은 조각이 아니라 또 하나의 일이 된다.
  static String fragmentBody({
    required String name,
    required String fragment,
  }) => "이따 할 '${_shorten(name)}' 15분만 $fragment에 써볼까냥?";

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

  /// 조각 하나. 오늘 같은 일로 이미 물어봤으면 그걸 다시 쓴다.
  ///
  /// [GapCoachingService.sync]는 앱을 열 때마다 돈다. 여기서 그냥 물어보면
  /// 하루에 앱 연 횟수만큼 결제된다 — 하루 30번 열면 서른 번이다. 그래서
  /// 하루 한 번, 그것도 고른 일이 바뀌었을 때만 묻는다.
  static Future<String?> _fragmentFor(
    SharedPreferences prefs,
    String name,
    DateTime now,
  ) async {
    final today = _dateKey(now);
    if (_hasFragmentAnswer(prefs, name, now)) {
      return _cachedFragment(prefs, name, now);
    }

    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    final askedToday = cached != null && cached['date'] == today
        ? (int.tryParse(cached['asked'] ?? '') ?? 0)
        : 0;
    if (askedToday >= maxFragmentAsksPerDay) return null;

    final fragment = await GapFragmentCheck.fragmentFor(name);
    // 못 받아온 것도 적어둔다. 안 적으면 통신이 끊긴 날 앱을 열 때마다 다시
    // 물어보게 된다.
    await prefs.setString(
      fragmentCacheKey,
      jsonEncode({
        'date': today,
        'taskId': name,
        'asked': askedToday + 1,
        if (fragment != null) 'fragment': fragment,
      }),
    );
    return fragment;
  }

  /// 오늘 몇 번 물어봤는지. 테스트와 진단용.
  @visibleForTesting
  static int fragmentAsksToday(SharedPreferences prefs, DateTime now) {
    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    if (cached == null || cached['date'] != _dateKey(now)) return 0;
    return int.tryParse(cached['asked'] ?? '') ?? 0;
  }

  /// 오늘 이 일로 이미 물어봤는지. 못 받아온 것도 물어본 것으로 센다.
  static bool _hasFragmentAnswer(
    SharedPreferences prefs,
    String name,
    DateTime now,
  ) {
    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    return cached != null &&
        cached['date'] == _dateKey(now) &&
        cached['taskId'] == name;
  }

  /// 오늘 받아둔 조각. 없으면 null. 물어보지 않는다.
  static String? _cachedFragment(
    SharedPreferences prefs,
    String name,
    DateTime at,
  ) {
    if (!_hasFragmentAnswer(prefs, name, at)) return null;
    final cached = _readFragmentCache(prefs.getString(fragmentCacheKey));
    final fragment = cached?['fragment'];
    return (fragment == null || fragment.isEmpty) ? null : fragment;
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
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

  /// 저장된 설정을 지금 상태에 맞춰 네이티브·알림에 다시 건다.
  ///
  /// 등급이 내려갔으면 여기서 조용히 접힌다. 앱이 꺼진 사이에는 등급을 알 수
  /// 없어서, 앱이 켜져 있는 동안 확인한 결론만 넘긴다.
  static Future<void> sync() async {
    if (!isSupported) return;
    final userData = await UserDataService.load();
    final master = userData.isPlanActive && userData.planType == 'master';
    final enabled = master && await isEnabled();
    final slots = enabled ? await times() : const <TimeOfDay>[];

    if (_isAndroid) {
      try {
        if (slots.isEmpty) {
          await _channel.invokeMethod('clearGapCoaching');
        } else {
          // 문장을 먼저 만들어 두고 시각을 건다. 카드가 뜨는 순간에는 앱이
          // 꺼져 있을 수 있어서, 그때 만들 수는 없다.
          final prefs = await SharedPreferences.getInstance();
          await prepareCard(prefs);
          await _channel.invokeMethod('syncGapCoaching', {
            'times': slots.map(formatTime).toList(),
          });
        }
      } on PlatformException {
        //
      } on MissingPluginException {
        // 네이티브가 아직 없는 빌드.
      }
      return;
    }

    // 아이폰도 문장을 미리 만든다. 알림을 예약할 때 문구가 굳기 때문이다.
    // 여기서 물어봐 두면 아래 예약이 그 답을 가져다 쓴다.
    if (slots.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prepareCard(prefs);
    }
    // 다른 배너와 시간이 겹치는지 함께 봐야 해서 예약은 그쪽 한 곳에서 한다.
    await NyangBannerNudge.sync();
  }
}
