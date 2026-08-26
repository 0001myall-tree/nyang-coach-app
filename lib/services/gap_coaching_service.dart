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

  static Future<void> save({
    required bool enabled,
    required List<TimeOfDay> times,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = times.take(maxTimes).map(formatTime).toList();
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
