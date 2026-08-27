import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
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
    '기획', '아이디어', '콘텐츠', '카드뉴스', '디자인', '영상', '캠페인',
    '컨셉', '콘셉', '시안', '네이밍', '브레인', '로고', '굿즈', '썸네일',
  ];

  /// 첫 줄이 안 나와서 미루게 되는 일.
  static const List<String> _firstLineWords = [
    '글', '원고', '에세이', '블로그', '메일', '편지', '일기', '소설',
    '후기', '리뷰', '대본', '스크립트', '기사', '자소서',
  ];

  /// 무슨 말을 어떤 순서로 할지가 반인 일.
  ///
  /// [_firstLineWords]와 겹쳐 보이지만 하는 일이 다르다. 저쪽은 시작 장벽을
  /// 없애는 말이고 이쪽은 구조를 미리 잡는 말이다 — 발표 자료에 "첫문장만
  /// 준비해둬"는 약하고, 일기에 "개요 잡아둬"는 과하다.
  static const List<String> _outlineWords = [
    '보고서', '리포트', '발표', '제안', '논문', '계획서', '문서',
    '강의', '수업', '이력서', '정리해서', '회의록',
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
    if (_conceptWords.any(name.contains)) {
      return "이따 할 '$name' 10분간 콘셉트만 생각해둬도 훨씬 가벼워질 거라냥.";
    }
    if (_outlineWords.any(name.contains)) {
      return "이따 할 '$name' 10분간 개요만 대충 잡아둬도 훨씬 가벼워질 거라냥.";
    }
    if (_firstLineWords.any(name.contains)) {
      return "이따 할 '$name' 10분간 첫문장만 준비해둬도 훨씬 가벼워질 거라냥.";
    }
    return "이따 할 '$name' 10분만 미리 해두면 훨씬 가벼워질 거라냥.";
  }

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
  /// 아직 시작하지 않은 일만 본다 — 손을 댄 일에 "미리 해두라"고 할 수는 없다.
  /// [at] 뒤에 오는 시각이 정해진 일이 먼저고, 없으면 시각 없는 일 중 첫 번째다.
  /// 약속(schedule)은 시각에 가서 하는 것이라 10분을 앞당길 자리가 없어 뺀다.
  static String? _pickTaskName(List tasks, DateTime at) {
    final atMinutes = at.hour * 60 + at.minute;
    String? untimed;
    int? soonestMinutes;
    String? soonest;

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
        untimed ??= text;
        continue;
      }
      final minutes = hour * 60 + minute;
      // 이미 지난 시각은 "이따"가 아니다.
      if (minutes <= atMinutes) continue;
      if (soonestMinutes == null || minutes < soonestMinutes) {
        soonestMinutes = minutes;
        soonest = text;
      }
    }

    final picked = soonest ?? untimed;
    if (picked == null) return null;
    return picked.length <= _nameLimit
        ? picked
        : '${picked.substring(0, _nameLimit)}…';
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

    // 아이폰은 알림 배너로 간다. 다른 배너와 시간이 겹치는지 함께 봐야 해서
    // 예약은 그쪽 한 곳에서 한다.
    await NyangBannerNudge.sync();
  }
}
