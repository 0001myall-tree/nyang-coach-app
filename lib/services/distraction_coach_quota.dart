import 'package:shared_preferences/shared_preferences.dart';

/// 프렌즈 등급에서 딴짓 방지 코칭이 하루에 몇 일정까지 붙는지.
///
/// 마스터는 지금까지처럼 모든 일정에 붙는다. 프렌즈는 하루 한 일정이다.
///
/// 하루치가 줄어드는 시점은 일정을 시작할 때가 아니라 냥냥이가 실제로 나온
/// 때다. 시작만 해두고 딴짓하지 않은 일정은 몫을 쓰지 않고 지나가고, 그 몫은
/// 다음에 시작하는 일정으로 넘어간다. 시작한 순간 가져가게 두면, 10분 만에
/// 끝낸 일정 하나에 하루치를 잃는다 — 받아본 적 없는 코칭에 몫을 잃는 것은
/// 제한이 아니라 고장으로 보인다.
///
/// 한 번 나온 일정은 그날 내내 계속 받는다. 하루 한 "번"이 아니라 한
/// "일정"이라, 30분마다 다시 확인하는 원래 동작이 그 일정에서는 그대로다.
///
/// ## 어디서 판단하나
///
/// 갈래마다 냥냥이가 나오는 방식이 달라서, 판단하는 자리도 다르다.
///
/// - **안드로이드**: 30분 뒤 딴짓 중인지 네이티브가 보고 그때 결정한다. 앱이
///   꺼져 있어도 돌아야 해서 Dart가 낄 수 없다. 그래서 네이티브가 나가기
///   직전에 [slotDateKey]와 [slotTaskIdKey]를 직접 읽고 쓴다. 같은
///   SharedPreferences 파일을 보므로 여기서 읽는 값과 같은 값이다.
/// - **다이내믹 아일랜드가 없는 아이폰**: 30분 뒤 배너. 알림은 미리 걸어두는
///   것이라 발동하는 순간에 코드가 돌지 않는다. 그래서 걸 때 자리를
///   맡아두고([reserve]), 그 시각이 지나간 뒤에 확정한다. 30분이 되기 전에
///   일정을 끝내면 알림이 취소되면서 자리도 풀린다([release]).
/// - **다이내믹 아일랜드가 있는 아이폰**: 시작하자마자 라이브 액티비티가
///   붙는다. 딴짓 여부를 알 길이 없어서 발동 시점이 곧 시작 시점이고,
///   그래서 이 갈래에서만 "그날 처음 시작한 일정"이 몫을 가져간다.
///
/// ## 이 기기에서만 센다
///
/// 여기 쓰는 키는 'nyang_'으로 시작하지 않는다. 그 접두어가 붙으면 통째로
/// 클라우드에 올라갔다 내려오는데, 네이티브가 같은 값을 직접 쓰고 있어서
/// 다른 기기 값에 덮이면 안 된다. 대신 폰이 두 대면 하루치도 두 번이다.
class DistractionCoachQuota {
  /// 마스터 등급인지. 네이티브가 읽어야 해서 'flutter.' 접두어가 붙는다.
  static const String unlimitedKey = 'ongoing_nudge_unlimited';

  /// 오늘치를 가져간 날짜(yyyy-MM-dd)와 그 일정.
  static const String slotDateKey = 'ongoing_nudge_slot_date';
  static const String slotTaskIdKey = 'ongoing_nudge_slot_task_id';

  /// 냥냥이가 실제로 나왔는지. 아직 자리만 맡아둔 상태와 구분한다.
  static const String slotConfirmedKey = 'ongoing_nudge_slot_confirmed';

  /// 맡아둔 자리가 언제 발동할 예정인지(밀리초).
  static const String slotFiresAtKey = 'ongoing_nudge_slot_fires_at';

  /// 하루치를 다 썼다고 알려준 날. 하루 한 번만 말한다.
  static const String noticeShownDateKey = 'ongoing_nudge_quota_notice_date';

  static String dateKeyOf(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  /// 등급을 네이티브가 읽을 수 있는 자리에 적어둔다.
  ///
  /// 네이티브는 앱이 꺼진 사이에 판단해야 해서 사용자 정보를 읽을 수 없다.
  /// 그래서 등급 자체가 아니라 결론만 boolean 하나로 넘긴다. 사용자 정보가
  /// 저장될 때마다 불리므로, 이 서비스는 반대로 사용자 정보를 알지 못한다.
  static Future<void> setUnlimited(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(unlimitedKey, value);
  }

  static Future<bool> isUnlimited() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(unlimitedKey) ?? false;
  }

  /// 오늘치를 이미 가져간 일정. 아직 아무도 안 가져갔으면 null.
  ///
  /// 맡아만 두고 발동 시각이 지난 자리는 여기서 확정된다. 발동하는 순간에는
  /// 코드가 돌지 않아서, 지나간 뒤 처음 물어볼 때 정리한다.
  static Future<String?> ownerToday([DateTime? nowOverride]) async {
    final now = nowOverride ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (prefs.getString(slotDateKey) != dateKeyOf(now)) return null;
    final taskId = prefs.getString(slotTaskIdKey);
    if (taskId == null || taskId.isEmpty) return null;

    if (prefs.getBool(slotConfirmedKey) ?? false) return taskId;

    final firesAt = prefs.getInt(slotFiresAtKey);
    if (firesAt != null && now.millisecondsSinceEpoch >= firesAt) {
      await prefs.setBool(slotConfirmedKey, true);
      return taskId;
    }
    // 아직 나오지 않은 자리. 임자는 이 일정이지만 확정은 아니다.
    return taskId;
  }

  /// 30분 뒤에 나올 자리를 맡아둔다.
  ///
  /// 아직 확정이 아니다. 그 시각 전에 일정을 끝내면 [release]로 풀린다.
  /// 이미 확정된 다른 일정이 있으면 맡지 못한다.
  ///
  /// 맡아만 둔 다른 일정이 있을 때는 빼앗는다. 그 일정에 다시 걸 일이 있다면
  /// 그쪽이 다시 맡는다. 발동하지 못한 자리를 붙들고 있으면, 몫이 다음
  /// 일정으로 넘어가야 한다는 규칙이 무너진다.
  static Future<bool> reserve({
    required String taskId,
    required DateTime firesAt,
    DateTime? nowOverride,
  }) async {
    if (await isUnlimited()) return true;
    final now = nowOverride ?? DateTime.now();
    final owner = await ownerToday(now);
    if (owner != null && owner != taskId) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(slotConfirmedKey) ?? false) return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(slotDateKey, dateKeyOf(now));
    await prefs.setString(slotTaskIdKey, taskId);
    await prefs.setBool(slotConfirmedKey, false);
    await prefs.setInt(slotFiresAtKey, firesAt.millisecondsSinceEpoch);
    return true;
  }

  /// 아직 나오지 않은 자리를 푼다. 이미 나온 뒤라면 아무것도 하지 않는다.
  ///
  /// [keepTaskId]가 지금 걸어두는 일정이다. 그 자리는 그대로 두고, 다른
  /// 일정이 붙들고 있던 미확정 자리만 푼다 — 일정을 멈추거나 끝내면 걸어둔
  /// 배너가 취소되므로, 나오지 못한 그 자리도 같이 풀려야 한다.
  static Future<void> releaseUnconfirmedUnless({
    String? keepTaskId,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getString(slotDateKey) != dateKeyOf(now)) return;
    final owner = prefs.getString(slotTaskIdKey);
    if (owner == null || owner.isEmpty) return;
    if (owner == keepTaskId) return;
    if (prefs.getBool(slotConfirmedKey) ?? false) return;
    final firesAt = prefs.getInt(slotFiresAtKey);
    if (firesAt != null && now.millisecondsSinceEpoch >= firesAt) return;

    await prefs.remove(slotDateKey);
    await prefs.remove(slotTaskIdKey);
    await prefs.remove(slotConfirmedKey);
    await prefs.remove(slotFiresAtKey);
  }

  /// 지금 바로 나오는 갈래(라이브 액티비티)에서 오늘치를 가져간다.
  ///
  /// 가져갔거나 이미 임자였으면 true.
  static Future<bool> claimNow(String taskId, [DateTime? nowOverride]) async {
    if (await isUnlimited()) return true;
    final now = nowOverride ?? DateTime.now();
    final owner = await ownerToday(now);
    if (owner != null && owner != taskId) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(slotDateKey, dateKeyOf(now));
    await prefs.setString(slotTaskIdKey, taskId);
    await prefs.setBool(slotConfirmedKey, true);
    await prefs.remove(slotFiresAtKey);
    return true;
  }

  /// [taskId]를 시작하는 지금, 하루치가 이미 다른 일정에 쓰였다고 말해줄
  /// 차례인지.
  ///
  /// 아무 말 없이 안 나오면 고장과 구별되지 않는다. 그렇다고 ▶를 누를 때마다
  /// 말하면 그건 잔소리라, 하루 한 번만 말하고 그날은 다시 말하지 않는다.
  static Future<bool> shouldTellQuotaSpent(
    String taskId, [
    DateTime? nowOverride,
  ]) async {
    if (await isUnlimited()) return false;
    final now = nowOverride ?? DateTime.now();
    final owner = await ownerToday(now);
    if (owner == null || owner == taskId) return false;

    final prefs = await SharedPreferences.getInstance();
    // 아직 나오지 않은 자리라면 그 일정도 몫을 잃을 수 있다. 확정된 뒤에만
    // 말한다.
    if (!(prefs.getBool(slotConfirmedKey) ?? false)) return false;
    if (prefs.getString(noticeShownDateKey) == dateKeyOf(now)) return false;

    await prefs.setString(noticeShownDateKey, dateKeyOf(now));
    return true;
  }

  static const String quotaSpentMessage =
      '오늘의 딴짓 방지 코칭은 이미 다른 일정에 쓰였어요.\n'
      '프렌즈는 하루 한 일정까지예요. 마스터로 올리면 무제한으로 붙습니다.';
}
