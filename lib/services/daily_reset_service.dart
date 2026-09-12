import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'memory_service.dart';
import 'chat_store.dart';
import 'coach_id_service.dart';
import 'routine_schedule.dart';
import 'tasks_sync_service.dart';

class DailyResetService {
  static const String lastResetAtKey = 'nyang_last_daily_reset_at';
  static const String lastResetFromDateKey = 'nyang_last_daily_reset_from_date';
  static const String lastResetToDateKey = 'nyang_last_daily_reset_to_date';
  static const String previousDayHadTasksKey = 'nyang_previous_day_had_tasks';
  static const String previousDayAllDoneKey =
      'nyang_previous_day_all_tasks_done';

  /// 이 기기에서 어느 날짜의 정리를 이미 끝냈는지.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 그 접두어는 클라우드가 덮어쓰는데, 정리를
  /// 이미 했다는 것은 이 기기에서 일어난 사실이라 덮이면 안 된다.
  ///
  /// 정리를 돌릴지는 원래 [lastDateKey] 하나로 정했다. 그 값은 클라우드로
  /// 오가기 때문에 오래된 값이 도착하면 되돌아갈 수 있고, 그러면 앱은 이미
  /// 끝낸 정리를 낮에 다시 실행했다. 그 순간 오늘 목록은 통째로 어제 칸으로
  /// 넘어가고, 루틴과 일정에서 새로 만들어진다 — 오늘 직접 적은 할 일은
  /// 만들 재료가 없어서 그대로 사라졌다.
  static const String resetDoneDateKey = 'daily_reset_done_date';

  static const String lastDateKey = 'nyang_last_date';

  /// 이 기기가 들고 있는 오늘 목록이 어느 날 것인지.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. [lastDateKey]가 바로 그 접두어 때문에
  /// 기기 사이를 오갔고, 그 하나로 정리 여부를 정한 것이 화근이었다. 다른
  /// 기기가 먼저 정리를 끝내고 오늘 날짜를 올리면, 아직 어제 목록을 들고 있는
  /// 기기는 "저장된 날짜가 이미 오늘"이라며 보관을 통째로 건너뛰었다. 건너뛴
  /// 사실도 안 남겨서 그날은 몇 번을 열어도 같은 자리를 다시 밟았다.
  /// 2026-09-08과 09-09 목록이 보관함에 없던 이유가 이것이다.
  static const String localListDateKey = 'daily_list_date';

  /// 옛 보관함 키 접두사. 지금은 합쳐 들이기 위해서만 본다.
  ///
  /// 대화는 원래 자정마다 방에서 보관함으로 **옮겨졌다**. 옮기는 일은 어긋날
  /// 자리가 많았다 — 정리가 두 번 돌 때, 늦게 돌 때, 다른 기기가 먼저 돌 때,
  /// 옮기다 멈출 때. 사라진 대화 신고는 대부분 그 네 가지였다.
  ///
  /// 지금은 방 하나에 그대로 쌓고 오래된 날만 버린다. 담아두는 규칙은 전부
  /// [ChatStore]에 있다.
  static const String chatArchivePrefix = ChatStore.archivePrefix;

  /// 뒤늦은 하루 요약을 며칠까지 거슬러 볼지.
  static const int chatArchiveDays = 7;
  static const List<String> coachIds = [
    'cat',
    'boyfriend',
    'halmae',
    'bro',
    CoachIdService.nyangHalbaeId,
    'sec_female',
  ];

  /// 지나간 하루의 대화를 날짜로 모은다. 방과 옛 보관함을 함께 본다.
  ///
  /// 어느 날 대화든 여기로 묻는다. 예전에는 "방에 남은 것이 곧 어제 대화"라고
  /// 보는 자리가 따로 있었는데, 그 전제는 자정 정리가 막 돈 순간에만 맞았다.
  /// 이제 방은 여러 날을 함께 들고 있으므로 날짜로 고르는 이 길만 남긴다.
  ///
  /// 같은 말이 양쪽에 다 있는 일은 정상적으로는 없지만, 정리가 한 번 어긋나면
  /// 생길 수 있어서 코치·시각·내용이 같으면 한 번만 센다.
  static List<dynamic> collectChatHistoryForDate(
    SharedPreferences prefs,
    String date,
  ) {
    final merged = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final coachId in coachIds) {
      final normalizedCoachId = CoachIdService.normalize(coachId);
      for (final key in [
        'nyang_chat_history_$normalizedCoachId',
        '$chatArchivePrefix$normalizedCoachId',
      ]) {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        try {
          final history = jsonDecode(raw) as List;
          for (final item in history) {
            if (item is! Map) continue;
            final text = (item['text'] ?? item['content'] ?? '')
                .toString()
                .trim();
            if (text.isEmpty) continue;
            final rawTime = item['time']?.toString() ?? '';
            final time = DateTime.tryParse(rawTime);
            // 시각을 모르면 어느 날 것인지도 모른다. 요약은 하루 단위라 여기서는
            // 넣지 않는다 - 엉뚱한 날에 섞이면 그날 기억이 통째로 틀어진다.
            if (time == null) continue;
            if (DateFormat('yyyy-MM-dd').format(time) != date) continue;
            if (!seen.add('$normalizedCoachId|$rawTime|$text')) continue;
            merged.add({
              ...item.cast<String, dynamic>(),
              'coachId': normalizedCoachId,
            });
          }
        } catch (_) {}
      }
    }

    merged.sort((a, b) {
      final at = DateTime.tryParse(a['time']?.toString() ?? '');
      final bt = DateTime.tryParse(b['time']?.toString() ?? '');
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return merged;
  }

  /// 코치별 대화에서 오래된 날을 걷어낸다. 옛 보관함이 남아 있으면 합쳐 들인다.
  ///
  /// 자정 정리가 대화에 하는 일은 이것뿐이다. 옮기지도, 비우지도 않는다.
  ///
  /// 보관함 합치기를 한 번만 하는 표시를 두지 않는다. 업데이트를 안 한 다른
  /// 기기가 여전히 보관함에 적고 그것이 클라우드로 올라올 수 있어서, 볼 때마다
  /// 있으면 합치는 쪽이 스스로 아문다. 같은 말은 한 번만 남으므로 여러 번
  /// 합쳐도 늘어나지 않는다.
  static Future<bool> pruneChatHistories(SharedPreferences prefs) async {
    var changed = false;
    for (final coachId in coachIds) {
      final normalizedCoachId = CoachIdService.normalize(coachId);
      final historyKey = ChatStore.historyKey(normalizedCoachId);
      final archiveKey = '$chatArchivePrefix$normalizedCoachId';
      final rawHistory = prefs.getString(historyKey);
      final rawArchive = prefs.getString(archiveKey);
      if (rawHistory == null && rawArchive == null) continue;

      // 방에 있는 지금 값을 남긴다. 보관함 쪽이 이기면 눌렀던 확인 카드의
      // 버튼이 되살아난다.
      final merged = ChatStore.mergedValue(
        ChatStore.decode(rawHistory),
        ChatStore.decode(rawArchive),
      );
      if (merged != rawHistory) {
        await prefs.setString(historyKey, merged);
        changed = true;
      }
      if (rawArchive != null) {
        await prefs.remove(archiveKey);
        changed = true;
      }
    }
    return changed;
  }

  /// 날짜별 계획 보관함. 미래 계획과 함께, 자정에 넘어간 어제 목록도 여기 하루 머문다.
  static const String plannedTasksByDateKey = 'nyang_today_tasks_by_date';

  /// 지난 날의 목록을 며칠까지 남겨둘지.
  ///
  /// 하루만 남기면, 밤에 냥냥이에게 "다 했어"를 누르고 이틀 뒤에 들어온 사람은
  /// 그 표시를 잃는다. 오랜만에 여는 사람을 위해 사흘까지 들고 있는다.
  /// (오늘 탭에서 직접 열어볼 수 있는 건 어제까지다. 그 앞은 채워 넣을 자리로만 쓴다.)
  static const int archivedPastDays = 3;

  /// 자정 정리로 사라질 지난 목록을 보관함에 며칠 남긴다.
  ///
  /// 전날 완료 표시를 깜빡했거나 자정을 넘겨 끝낸 일을 나중에 채울 수 있게 하려는 것이다.
  static Future<void> archivePreviousDayTasks({
    required SharedPreferences prefs,
    required String fromDate,
    required String today,
    required List<dynamic> tasksJson,
  }) async {
    final todayDate = DateTime.tryParse(today);
    if (todayDate == null) return;
    final floor = DateFormat(
      'yyyy-MM-dd',
    ).format(todayDate.subtract(const Duration(days: archivedPastDays)));

    Map<String, dynamic> byDate = {};
    try {
      final raw = prefs.getString(plannedTasksByDateKey);
      if (raw != null && raw.isNotEmpty) {
        byDate = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}

    // 며칠 만에 열었다면 fromDate가 보관 범위 밖일 수 있다. 그때는 남길 것이 없다.
    if (tasksJson.isNotEmpty &&
        fromDate.compareTo(floor) >= 0 &&
        fromDate.compareTo(today) < 0) {
      byDate[fromDate] = tasksJson;
    }
    byDate.removeWhere((key, _) => key.compareTo(floor) < 0);

    await prefs.setString(plannedTasksByDateKey, jsonEncode(byDate));
  }

  /// 날짜별 계획을 저장할 때, 저장소에 있던 것과 합친다.
  ///
  /// 자정 정리는 두 곳에서 돈다 — 여기(저장소만 보고)와 플래너 화면(메모리를 보고).
  /// 둘이 같이 돌기 때문에, 화면이 표를 읽어둔 뒤에 이쪽이 어제 목록을 저장소에
  /// 넣는 순간이 생긴다. 그때 화면이 자기 표를 그대로 저장하면 방금 보관된 어제가
  /// 통째로 사라진다. 어제를 열었을 때 목록이 텅 비어 보이던 이유가 이것이다.
  ///
  /// 그래서 화면이 아예 모르는 날짜는 저장소 쪽을 남긴다. 화면이 아는 날짜는
  /// 비어 있더라도 화면이 이긴다 — 지운 것이 되살아나면 안 되기 때문이다.
  ///
  /// [justArchivedKey]는 예외다. 정리가 방금 어제 목록을 넣어둔 날짜인데,
  /// 화면은 그 칸을 빈손으로 알고 있어서 곧바로 다시 비웠다. 오늘 목록에서도
  /// 없고 어제 칸에서도 없어지던 자리가 여기다. 화면이 빈손일 때만 저장소를
  /// 남긴다 — 화면에 뭔가 들고 있으면 사용자가 실제로 고친 것이므로 그대로 둔다.
  static Map<String, dynamic> mergePlannedTasksForSave({
    required Map<String, dynamic> stored,
    required Map<String, dynamic> encoded,
    required Set<String> knownKeys,
    String? justArchivedKey,
  }) {
    final merged = Map<String, dynamic>.from(encoded);
    stored.forEach((key, value) {
      if (!knownKeys.contains(key)) {
        merged[key] = value;
        return;
      }
      if (key != justArchivedKey) return;
      final mine = merged[key];
      final emptyHere = mine == null || (mine is List && mine.isEmpty);
      if (emptyHere) merged[key] = value;
    });
    return merged;
  }

  static Future<void> recordDayTransition({
    required SharedPreferences prefs,
    required String fromDate,
    required String toDate,
    required bool previousDayHadTasks,
    required bool previousDayAllDone,
  }) async {
    await prefs.setString(lastResetAtKey, DateTime.now().toIso8601String());
    await prefs.setString(lastResetFromDateKey, fromDate);
    await prefs.setString(lastResetToDateKey, toDate);
    await prefs.setBool(previousDayHadTasksKey, previousDayHadTasks);
    await prefs.setBool(previousDayAllDoneKey, previousDayAllDone);
  }

  static String _getTodayStr(double resetHour) {
    final now = DateTime.now();
    var base = DateTime(now.year, now.month, now.day);
    if (now.hour < resetHour) {
      base = base.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy-MM-dd').format(base);
  }

  static String _getWeekMondayStr(String today) {
    final parts = today.split('-');
    DateTime baseDate;
    if (parts.length >= 3) {
      baseDate = DateTime(
        int.parse(parts[0]),
        int.parse(parts[1]),
        int.parse(parts[2]),
      );
    } else {
      final now = DateTime.now();
      baseDate = DateTime(now.year, now.month, now.day);
    }
    final dayOfWeek = baseDate.weekday; // 1=Mon ~ 7=Sun
    final monday = baseDate.subtract(Duration(days: dayOfWeek - 1));
    return DateFormat('yyyy-MM-dd').format(monday);
  }

  /// 파이어베이스가 로그인 상태를 되살릴 때까지 기다린다.
  ///
  /// [FirebaseAuth.currentUser]는 앱이 막 켜진 순간 잠깐 비어 있을 수 있다.
  /// 그 찰나를 "로그아웃"으로 읽으면 아래 가드가 통째로 열린다 - 아직 도착하지
  /// 않은 클라우드 데이터를 없는 것으로 치고 정리가 달려버리고, 어제 대화는
  /// 보관함에 들어가지도 남지도 못한 채 사라진다.
  ///
  /// 기기가 느리거나 네트워크가 느릴수록 잘 걸린다. 같은 앱 같은 계정인데
  /// "지난 대화 보기"가 되는 사람과 안 되는 사람이 갈리던 것이 이것이다.
  ///
  /// 진짜 로그아웃 상태면 스트림이 곧바로 null을 내주므로 기다리지 않는다.
  static Future<User?> resolvedUser({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current != null) return current;
    try {
      return await FirebaseAuth.instance.authStateChanges().first.timeout(
        timeout,
      );
    } catch (_) {
      // 스트림이 끝내 아무것도 안 주면 예전처럼 지금 값으로 판단한다.
      return FirebaseAuth.instance.currentUser;
    }
  }

  /// 로그인 상태인데 이 기기에서 첫 클라우드 복원이 아직 성공하지 않았으면 true.
  /// 이 상태에서 리셋이 돌면 재설치 직후의 빈 로컬을 기준으로 하루 전환이
  /// 실행되어, 곧 복원될 데이터를 지우거나 빈 값을 서버로 역전파할 수 있다.
  static Future<bool> isCloudRestorePending(SharedPreferences prefs) async {
    if (await resolvedUser() == null) return false;
    await prefs.reload();
    return !(prefs.getBool('nyang_has_synced_from_cloud') ?? false);
  }

  /// 복원이 끝나기를 기다렸다가 정리한다. 앱을 켤 때 쓴다.
  ///
  /// 가드에 막히면 [checkAndExecuteReset]은 그냥 돌아서고, 그 판에서는 아무도
  /// 다시 부르지 않았다. 그러면 정리는 앱을 껐다 켜거나 자정을 넘길 때까지
  /// 밀리고, 그동안 오늘 목록은 어제 것을 그대로 들고 있다.
  ///
  /// 끝내 복원이 안 되면 정리하지 않는다. 늦는 것이 지우는 것보다 낫다 -
  /// 아직 안 온 데이터를 없는 것으로 치고 하루를 넘기면 되돌릴 길이 없다.
  static Future<bool> checkAndExecuteResetAfterRestore({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    var prefs = await SharedPreferences.getInstance();
    while (await isCloudRestorePending(prefs)) {
      if (!DateTime.now().isBefore(deadline)) return false;
      await Future.delayed(const Duration(milliseconds: 500));
      prefs = await SharedPreferences.getInstance();
    }
    return checkAndExecuteReset();
  }

  /// 오늘 정리를 이미 끝냈는지. 끝냈으면 되돌아온 날짜만 바로잡고 목록은
  /// 건드리지 않는다.
  static Future<bool> alreadyResetToday(
    SharedPreferences prefs,
    String today,
  ) async {
    if (prefs.getString(resetDoneDateKey) != today) return false;
    if (prefs.getString(lastDateKey) != today) {
      await prefs.setString(lastDateKey, today);
    }
    if (prefs.getString(localListDateKey) != today) {
      await prefs.setString(localListDateKey, today);
    }
    return true;
  }

  /// 오늘 정리가 끝났다고 적는다.
  ///
  /// 정리할 것이 없어 지나갈 때도 적어야 한다. 안 적으면 앱을 열 때마다 같은
  /// 자리를 다시 밟고, 그러는 동안 이 기기는 자기가 오늘 정리를 안 했다고
  /// 계속 생각한다.
  static Future<void> markResetDone(
    SharedPreferences prefs,
    String today,
  ) async {
    await prefs.setString(lastDateKey, today);
    await prefs.setString(resetDoneDateKey, today);
    await prefs.setString(localListDateKey, today);
  }

  /// 목록이 어느 날 것인지 목록 스스로 말하게 한다.
  ///
  /// 루틴 항목은 id에 그날 날짜가 박혀 있다(`habit_<루틴id>_<날짜>`). 그게
  /// 없으면 손으로 적은 할 일의 적은 시각을 본다. 일정은 보지 않는다 — 일정을
  /// 만든 날은 그 일정이 놓인 날이 아니다.
  ///
  /// 저장된 날짜값과 달리 이건 클라우드가 덮을 수 없다. 목록을 옮기는 일이니
  /// 어느 날 것인지는 옮길 목록에게 묻는 것이 맞다.
  ///
  /// 날짜가 섞여 있으면 **가장 이른 날**이 답이다. 화면은 정리와 상관없이 오늘
  /// 루틴을 목록에 채워 넣기 때문에, 어제 목록에 오늘 만든 루틴 하나가 얹힐 수
  /// 있다. 그걸 보고 "이 목록은 오늘 것"이라고 읽으면 어제 목록이 통째로 보관을
  /// 건너뛴다 — 고치려던 바로 그 일이 다른 문으로 들어온다.
  @visibleForTesting
  static String? listDateOf(List<dynamic> tasks) {
    final habitDate = RegExp(r'_(\d{4}-\d{2}-\d{2})$');
    String? fromHabits;
    String? fromCreated;
    for (final task in tasks) {
      if (task is! Map) continue;
      final id = task['id']?.toString() ?? '';
      if (id.startsWith('habit_')) {
        final match = habitDate.firstMatch(id);
        final date = match?.group(1);
        if (date != null &&
            (fromHabits == null || date.compareTo(fromHabits) < 0)) {
          fromHabits = date;
        }
        continue;
      }
      if (task['category'] == 'schedule') continue;
      final date = _dateOfIso(task['createdAt']);
      if (date != null &&
          (fromCreated == null || date.compareTo(fromCreated) < 0)) {
        fromCreated = date;
      }
    }
    return fromHabits ?? fromCreated;
  }

  /// 지금 들고 있는 목록이 어느 날 것인지. null이면 정리할 목록이 없다.
  ///
  /// 목록이 먼저다. 적어둔 날짜는 목록이 아무 말도 못 할 때만 쓴다. 그중에서도
  /// 이 기기에 적은 것을 먼저 보고, 그것마저 없을 때에만 클라우드로 오가는
  /// 값을 본다.
  ///
  /// 아직 오지 않은 날은 답으로 삼지 않는다. 폰 시계가 앞서 있거나 시차가 다른
  /// 곳에서 만든 목록이 넘어오면 그럴 수 있는데, 그 날짜로 정리를 돌리면
  /// "지난 날 보관"이 성립하지 않아 목록이 보관 없이 버려진다. 그때는 오늘로
  /// 읽어 아무것도 옮기지 않는다 — 아직 오지 않은 날의 목록이라면 옮길 이유도
  /// 없다.
  static String? resetFromDate({
    required List<dynamic> tasks,
    required String? localListDate,
    required String? lastDate,
    required String today,
  }) {
    final found = listDateOf(tasks) ?? localListDate ?? lastDate;
    if (found == null) return null;
    return found.compareTo(today) > 0 ? today : found;
  }

  /// 뒤늦은 하루 요약을 이 기기에서 어느 날 시도했는지.
  ///
  /// 'nyang_' 접두어를 쓰지 않는다. 그 접두어는 클라우드가 덮어쓰는데, 이건
  /// 이 기기가 오늘 이미 한 번 불렀다는 사실이라 덮이면 안 된다.
  static const String summaryCatchUpDateKey = 'daily_summary_catch_up_date';

  /// 빠진 하루 요약을 뒤늦게 채운다.
  ///
  /// 요약은 원래 자정 정리의 "날짜가 넘어갔다" 갈래 안에서만 만들어졌다. 그
  /// 판정은 네 군데서 돌아서는데(복원 대기, 오늘 이미 정리함, 어느 날 목록인지
  /// 모름, 목록이 이미 오늘 것), 그중 하나라도 걸리면 그날 요약은 만들어지지
  /// 않았고 다시 시도하는 길도 없었다. 다른 기기가 먼저 오늘 날짜를 올린 날이
  /// 특히 그랬다 - 목록만 안 밀리는 줄 알았는데 기억도 같이 굶었다.
  ///
  /// 그래서 정리와 떼어놓는다. 앱을 열 때 "요약이 빠진 날이 있나"만 보고,
  /// 있으면 그 하루를 만든다. 대부분의 날은 정리가 이미 만들어둔 것을 보고
  /// 그냥 지나간다.
  ///
  /// 하루에 한 번만 시도한다. 실패해도 오늘 다시 부르지 않는다 - 이 자리는
  /// 사용자가 부른 것이 아니라 배경에서 도는 것이라, 앱을 여닫을 때마다
  /// 호출이 나가면 안 된다. 대신 대상은 보관함이 남아 있는 동안 그대로
  /// 기다리므로 내일 다시 집는다.
  static Future<void> catchUpMissedDailySummary() async {
    final prefs = await SharedPreferences.getInstance();
    // 아직 클라우드에서 받아오는 중이다. 지금 보이는 빈 기록은 이 사람이
    // 대화를 안 한 것이 아니라 아직 안 온 것이다.
    if (await isCloudRestorePending(prefs)) return;

    const resetHour = 0.0;
    final today = _getTodayStr(resetHour);
    if (prefs.getString(summaryCatchUpDateKey) == today) return;
    // 부르기 전에 적는다. 시작할 때와 자정 넘김이 나란히 달리면 같은 하루를
    // 두 번 부를 수 있고, 그건 그대로 두 번의 API 요금이다.
    await prefs.setString(summaryCatchUpDateKey, today);

    final memory = MemoryService();
    await memory.loadMemoryData();

    final todayDate = DateTime.tryParse(today);
    if (todayDate == null) return;

    // 보관함이 들고 있는 날까지만 거슬러 본다. 그보다 오래된 날은 재료가
    // 이미 버려져서 만들 수 없다.
    for (var back = 1; back <= chatArchiveDays; back++) {
      final date = DateFormat(
        'yyyy-MM-dd',
      ).format(todayDate.subtract(Duration(days: back)));
      if (memory.hasDailySummary(date)) continue;
      final messages = collectChatHistoryForDate(prefs, date);
      // 그날 대화가 없었다. 요약할 것이 없는 것이지 빠진 것이 아니다.
      if (messages.isEmpty) continue;
      await memory.generateDailySummary(date, messages);
      // 한 번에 하루만. 며칠이 비어 있어도 앱 한 번 여는 데 호출 여러 개가
      // 나가면 안 된다. 나머지는 다음 날 같은 자리에서 집는다.
      return;
    }
  }

  /// 목록을 실제로 옮기고 다시 만들었으면 true.
  ///
  /// 부르는 쪽이 화면을 다시 읽을지 정하는 데 쓴다. 앱을 처음 켤 때는 이 정리와
  /// 화면의 첫 읽기가 나란히 달리는데, 정리가 조금 늦게 끝나면 화면은 정리
  /// 이전 목록을 그대로 들고 있었다. 그 상태에서 어제 칸을 열면 방금 보관된
  /// 목록이 화면에는 없어서 빈칸으로 보인다.
  static Future<bool> checkAndExecuteReset() async {
    final prefs = await SharedPreferences.getInstance();
    if (await isCloudRestorePending(prefs)) return false;
    const resetHour = 0.0;
    final today = _getTodayStr(resetHour);
    if (await alreadyResetToday(prefs, today)) return false;

    final previousTasksRaw = prefs.getString('nyang_tasks') ?? '[]';
    List<dynamic> previousTasks = [];
    try {
      previousTasks = jsonDecode(previousTasksRaw) as List;
    } catch (_) {}

    final lastDate = resetFromDate(
      tasks: previousTasks,
      localListDate: prefs.getString(localListDateKey),
      lastDate: prefs.getString(lastDateKey),
      today: today,
    );

    if (lastDate == null) {
      await markResetDone(prefs, today);
      return false;
    }

    var rebuiltList = false;

    if (lastDate == today) {
      // 목록이 이미 오늘 것이다. 옮길 것이 없어도 지나갔다는 표시는 남긴다.
      await markResetDone(prefs, today);
    }

    if (lastDate != today) {
      final previousDayHadTasks = previousTasks.isNotEmpty;
      final previousDayAllDone =
          previousDayHadTasks &&
          previousTasks.every((task) => task is Map && task['done'] == true);
      await recordDayTransition(
        prefs: prefs,
        fromDate: lastDate,
        toDate: today,
        previousDayHadTasks: previousDayHadTasks,
        previousDayAllDone: previousDayAllDone,
      );

      // 1. Calculate streak
      final rawHistory = prefs.getString('nyang_history');
      List<dynamic> history = [];
      if (rawHistory != null) {
        history = jsonDecode(rawHistory);
      }

      final prev = history.cast<Map<String, dynamic>>().firstWhere(
        (h) => h['date'] == lastDate,
        orElse: () => <String, dynamic>{},
      );

      final n = DateTime.now();
      var yesterday = DateTime(
        n.year,
        n.month,
        n.day,
      ).subtract(const Duration(days: 1));
      if (n.hour < resetHour) {
        yesterday = yesterday.subtract(const Duration(days: 1));
      }
      final yStr = DateFormat('yyyy-MM-dd').format(yesterday);

      int streak = prefs.getInt('nyang_streak') ?? 0;

      if (lastDate == yStr) {
        if (prev.isNotEmpty && prev['success'] == true) {
          streak += 1;
        } else {
          streak = 0;
        }
      } else {
        if (prev.isNotEmpty && prev['success'] == true) {
          streak = 1;
        } else {
          streak = 0;
        }
      }
      await prefs.setInt('nyang_streak', streak);

      // 2. Clear tasks in preferences (어제 목록은 보관함에 하루 남긴다)
      await archivePreviousDayTasks(
        prefs: prefs,
        fromDate: lastDate,
        today: today,
        tasksJson: previousTasks,
      );
      await prefs.setString('nyang_tasks', '[]');
      await prefs.setString('nyang_core_tasks', '[]');
      await prefs.setBool('nyang_core_reminder_enabled', false);
      await prefs.remove('nyang_core_reminder_coach');
      await prefs.remove('nyang_core_reminder_advance');
      await prefs.remove('nyang_deferred_tasks_today');

      // 3. 어제 하루 요약. 날짜로 골라 쓴다 — 방은 여러 날을 함께 들고 있다.
      final oldChatHistory = collectChatHistoryForDate(prefs, lastDate);
      if (oldChatHistory.isNotEmpty) {
        await MemoryService().loadMemoryData();
        await MemoryService().generateDailySummary(lastDate, oldChatHistory);
      }

      // 4. 대화는 그대로 두고 오래된 날만 걷어낸다. 비우지 않는다 — 비우는 줄이
      //    있던 동안에는 정리가 어긋날 때마다 그날 대화가 되돌릴 수 없이 사라졌다.
      await pruneChatHistories(prefs);

      await markResetDone(prefs, today);

      // 5. Inject habits & schedules to prefs for the new day
      await _injectTodayHabitsAndSchedulesDirectly(
        prefs,
        today,
        previousTasks: previousTasks,
      );
      TasksSyncService.scheduleSyncToCloud();
      rebuiltList = true;
    }

    // Weekly/Monthly Reset Check
    final thisWeek = _getWeekMondayStr(today);
    final now = DateTime.now();
    final thisMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final lastWeek = prefs.getString('nyang_last_week');
    if (lastWeek == null) {
      await prefs.setString('nyang_last_week', thisWeek);
    } else if (lastWeek != thisWeek) {
      await prefs.setString('nyang_last_week', thisWeek);
      await prefs.setString('nyang_week_goals', '[]');
    }

    final lastMonth = prefs.getString('nyang_last_month');
    if (lastMonth == null) {
      await prefs.setString('nyang_last_month', thisMonth);
    } else if (lastMonth != thisMonth) {
      await prefs.setString('nyang_last_month', thisMonth);
      await prefs.setString('nyang_month_goals', '[]');
    }

    return rebuiltList;
  }

  /// 오늘 목록을 루틴·일정·미리 세운 계획으로 다시 만든다.
  ///
  /// [previousTasks]는 정리 직전의 목록이다. 이 셋 어디에도 재료가 없는 항목,
  /// 곧 오늘 탭에서 손으로 적은 할 일은 여기서 다시 만들어질 수 없다. 그래서
  /// 그중 오늘 적은 것만 그대로 들고 간다 — 자정 정리라면 어제 것뿐이라 아무
  /// 일도 일어나지 않고, 정리가 엉뚱한 때에 한 번 더 돌더라도 오늘 적은 것이
  /// 사라지지 않는다.
  static Future<void> _injectTodayHabitsAndSchedulesDirectly(
    SharedPreferences prefs,
    String today, {
    List<dynamic> previousTasks = const [],
  }) async {
    final parts = today.split('-');
    int todayDow = DateTime.now().weekday;
    if (parts.length >= 3) {
      final y = int.tryParse(parts[0]) ?? DateTime.now().year;
      final m = int.tryParse(parts[1]) ?? DateTime.now().month;
      final d = int.tryParse(parts[2]) ?? DateTime.now().day;
      todayDow = DateTime(y, m, d).weekday;
    }
    final dbDow = todayDow - 1; // 0=Mon ~ 6=Sun

    // 1. habits load
    final rawHabits = prefs.getString('nyang_habits') ?? '[]';
    final List<dynamic> habitsList = jsonDecode(rawHabits);
    final rawLogs = prefs.getString('nyang_habit_logs') ?? '{}';
    final Map<String, dynamic> habitLogs = jsonDecode(rawLogs);

    List<Map<String, dynamic>> injectedTasks = [];

    for (final h in habitsList) {
      if (h is! Map) continue;
      final freq = h['freq'] ?? 'daily';
      final days = List<int>.from(h['days'] ?? []);
      bool matches = false;
      if (freq == 'daily') matches = true;
      if (freq == 'weekly_count') {
        matches = _shouldShowWeeklyCountHabitOnDate(
          h,
          habitLogs,
          DateTime.tryParse(today) ?? DateTime.now(),
        );
      }
      if (freq == 'weekly') matches = days.contains(dbDow);

      if (matches) {
        final habitId = h['id'].toString();
        final log = (habitLogs[habitId] ?? {})[today];
        final isSkipped = log != null && log['status'] == 'skipped';
        if (isSkipped) continue;

        final isDone = log != null && log['done'] == true;
        final taskId = 'habit_${habitId.replaceAll('.', '_')}_$today';
        String? tTime;
        if (h['timeType'] == 'single' && h['timeStart'] != null) {
          tTime = _displayTimeFromStored(timeStart: h['timeStart']);
        }
        if (h['timeType'] == 'range' && h['timeStart'] != null) {
          tTime = _displayTimeFromStored(
            timeStart: h['timeStart'],
            timeEnd: h['timeEnd'],
          );
        }

        injectedTasks.add({
          'id': taskId,
          'habitId': habitId,
          'text': h['name'],
          'category': 'habit',
          'done': isDone,
          'isHabit': true,
          'time': tTime,
          'duration': h['habitDuration'],
          'timeStart': h['timeStart'],
          'timeEnd': h['timeEnd'],
          'createdAt': DateTime.now().toIso8601String(),
          'completedAt': isDone ? log['completedAt'] : null,
          'isReminderEnabled': h['isReminderEnabled'] ?? false,
        });
      }
    }

    // 2. schedules load
    final rawSchedules = prefs.getString('nyang_schedules') ?? '{}';
    final Map<String, dynamic> schedulesMap = jsonDecode(rawSchedules);
    final List<dynamic> todaySchedules = schedulesMap[today] ?? [];

    for (final s in todaySchedules) {
      if (s is! Map) continue;
      final taskId = 'schedule_${s['id']}';
      injectedTasks.add({
        'id': taskId,
        'text': s['text'],
        'category': 'schedule',
        'done': s['done'] ?? false,
        'time': s['time'],
        'duration': s['duration'],
        'timeStart': s['timeStart'],
        'timeEnd': s['timeEnd'],
        'createdAt': s['createdAt'] ?? DateTime.now().toIso8601String(),
        'isReminderEnabled': s['isReminderEnabled'] ?? false,
        'deferredCount': s['deferredCount'] ?? 0,
        'googleEventId': s['googleEventId'],
        'googleUpdated': s['googleUpdated'],
        'isRecurring': s['isRecurring'] ?? false,
      });

      if (s['isReminderEnabled'] == true) {
        final rawCore = prefs.getString('nyang_core_tasks') ?? '[]';
        final List<dynamic> coreList = jsonDecode(rawCore);
        final coreExists = coreList.any((t) => t['id'].toString() == taskId);
        if (!coreExists) {
          coreList.add({
            'id': taskId,
            'text': s['text'],
            'category': 'schedule',
            'done': s['done'] ?? false,
            'time': s['time'],
            'duration': s['duration'],
            'timeStart': s['timeStart'],
            'timeEnd': s['timeEnd'],
            'createdAt': s['createdAt'] ?? DateTime.now().toIso8601String(),
            'isReminderEnabled': true,
            'deferredCount': s['deferredCount'] ?? 0,
            'googleEventId': s['googleEventId'],
            'googleUpdated': s['googleUpdated'],
            'isRecurring': s['isRecurring'] ?? false,
          });
          await prefs.setString('nyang_core_tasks', jsonEncode(coreList));
        }
      }
    }

    // 3. 오늘 날짜로 미리 세워둔 계획 승격 + 지나간 날짜의 계획 정리
    final rawPlanned = prefs.getString('nyang_today_tasks_by_date');
    if (rawPlanned != null) {
      try {
        final Map<String, dynamic> plannedMap = jsonDecode(rawPlanned);
        final todayPlanned = plannedMap.remove(today);
        if (todayPlanned is List) {
          final existingIds = injectedTasks
              .map((t) => t['id'].toString())
              .toSet();
          for (final t in todayPlanned) {
            if (t is Map && existingIds.add(t['id'].toString())) {
              injectedTasks.add(Map<String, dynamic>.from(t));
            }
          }
        }
        // 키는 yyyy-MM-dd 형식이라 문자열 비교가 날짜 순서와 일치한다.
        // 지난 며칠은 남긴다. 뒤늦게 도착한 완료 표시를 채울 자리가 필요하다.
        final todayDate = DateTime.tryParse(today);
        final keepFrom = todayDate == null
            ? today
            : DateFormat('yyyy-MM-dd').format(
                todayDate.subtract(const Duration(days: archivedPastDays)),
              );
        plannedMap.removeWhere((key, _) => key.compareTo(keepFrom) < 0);
        await prefs.setString(
          'nyang_today_tasks_by_date',
          jsonEncode(plannedMap),
        );
      } catch (_) {}
    }

    // 4. 다시 만들 재료가 없는 항목 중, 오늘 적은 것만 그대로 들고 간다.
    final existingIds = injectedTasks.map((t) => t['id'].toString()).toSet();
    for (final t in previousTasks) {
      if (t is! Map) continue;
      final task = Map<String, dynamic>.from(t);
      if (!existingIds.add(task['id'].toString())) continue;
      if (!shouldCarryOverTask(task, today)) continue;
      injectedTasks.add(task);
    }

    await prefs.setString('nyang_tasks', jsonEncode(injectedTasks));
    await pruneOrphanCoreTasks(prefs, injectedTasks);
    await _saveTodayRecordDirectly(prefs, today, injectedTasks);
  }

  /// 오늘 목록에 없는 핵심을 걷어낸다.
  ///
  /// 핵심은 오늘 목록에서 골라 담는 것이라, 목록에 없는 핵심은 어제 것이
  /// 남은 자리다. 정리는 목록과 핵심을 같이 비우는데, 마지막에 목록만 다시
  /// 쓴다 — 그 사이에 플래너 화면이 자기 기억에 있던 어제 핵심을 저장하면
  /// 그 값이 마지막 기록이 되어 살아남는다. 오늘의 핵심 칸에 오늘 목록에도
  /// 없는 어제 항목이 올라와 있던 이유가 이것이다.
  ///
  /// 목표 마일스톤은 예외다. 그건 오늘 목록이 아니라 목표 탭에서 오는 것이라
  /// 원래 목록에 없고, 걷어내는 규칙도 따로 있다.
  static Future<void> pruneOrphanCoreTasks(
    SharedPreferences prefs,
    List<dynamic> todayTasks,
  ) async {
    // 비교할 목록이 없으면 아무것도 지우지 않는다. 빈 목록을 기준으로 삼으면
    // 걷어내는 것이 아니라 통째로 비우는 일이 된다.
    if (todayTasks.isEmpty) return;
    final raw = prefs.getString('nyang_core_tasks');
    if (raw == null) return;
    List<dynamic> coreList;
    try {
      coreList = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }
    final todayIds = todayTasks
        .whereType<Map>()
        .map((t) => t['id'].toString())
        .toSet();
    final kept = coreList.where((c) {
      if (c is! Map) return false;
      final id = c['id'].toString();
      if (id.startsWith('milestone_')) return true;
      return todayIds.contains(id);
    }).toList();
    if (kept.length == coreList.length) return;
    await prefs.setString('nyang_core_tasks', jsonEncode(kept));
  }

  /// 정리가 목록을 다시 만들 때, 이 항목을 그대로 들고 가야 하는지.
  ///
  /// 루틴과 일정은 각자의 저장소에서 다시 만들어지므로 들고 가지 않는다.
  /// 남는 건 오늘 탭에서 손으로 적은 할 일이고, 그건 다시 만들 재료가 없다.
  /// 오늘 적은 것만 본다 — 어제 것을 들고 가면 자정 정리가 아무것도 안 지운
  /// 셈이 된다.
  @visibleForTesting
  static bool shouldCarryOverTask(Map<String, dynamic> task, String today) {
    if (task['habitId'] != null) return false;
    if (task['category'] == 'schedule') return false;
    return _dateOfIso(task['createdAt']) == today;
  }

  /// ISO 시각에서 날짜만. 못 읽으면 null.
  static String? _dateOfIso(Object? raw) {
    final parsed = DateTime.tryParse(raw?.toString() ?? '');
    return parsed == null ? null : DateFormat('yyyy-MM-dd').format(parsed);
  }

  static String? _displayTimeFromStored({dynamic timeStart, dynamic timeEnd}) {
    final start = _parseStoredTime(timeStart?.toString());
    if (start == null) return timeStart?.toString();
    final end = _parseStoredTime(timeEnd?.toString());
    if (end == null) return _formatTimeParts(start.$1, start.$2);
    return '${_formatTimeParts(start.$1, start.$2)} ~ ${_formatTimeParts(end.$1, end.$2)}';
  }

  static (int, int)? _parseStoredTime(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return (hour, minute);
  }

  static String _formatTimeParts(int hour, int minute) {
    final ap = hour >= 12 ? '오후' : '오전';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$ap $displayHour:${minute.toString().padLeft(2, '0')}';
  }

  static bool _shouldShowWeeklyCountHabitOnDate(
    Map<dynamic, dynamic> habit,
    Map<String, dynamic> habitLogs,
    DateTime date,
  ) {
    final habitId = habit['id']?.toString();
    if (habitId == null) return true;
    final logsForHabit = habitLogs[habitId];
    if (logsForHabit is! Map) return true;

    return RoutineSchedule.shouldShowWeeklyCountOnDate(
      rawWeeklyTargetCount: habit['weeklyTargetCount'],
      rawCreatedAt: habit['createdAt'],
      logs: logsForHabit,
      date: date,
    );
  }

  static Future<void> _saveTodayRecordDirectly(
    SharedPreferences prefs,
    String todayStr,
    List<Map<String, dynamic>> tasksList,
  ) async {
    final rawHistory = prefs.getString('nyang_history');
    List<Map<String, dynamic>> history = [];
    if (rawHistory != null) {
      try {
        final List decoded = jsonDecode(rawHistory);
        history = decoded.cast<Map<String, dynamic>>();
      } catch (_) {}
    }

    final rawHabits = prefs.getString('nyang_habits') ?? '[]';
    final List<dynamic> habitsList = jsonDecode(rawHabits);
    final countableTasks = tasksList
        .where((t) => _countsTowardDailyCompletion(t, habitsList))
        .toList();
    final doneTasks = countableTasks.where((t) => t['done'] == true).toList();

    // 밤 9시 이후 이월된 일정 로드
    final rawDeferred = prefs.getString('nyang_deferred_tasks_today');
    List<dynamic> deferredList = [];
    if (rawDeferred != null) {
      try {
        deferredList = jsonDecode(rawDeferred);
      } catch (_) {}
    }

    final mergedTasks = [
      ...tasksList.map(
        (t) => {
          'text': t['text'],
          'done': t['done'] ?? false,
          'inProgress': t['inProgress'] ?? false,
          if (t['inProgressAt'] != null) 'startedAt': t['inProgressAt'],
          if (t['completedAt'] != null) 'completedAt': t['completedAt'],
          'category': t['category'] ?? 'today',
          // 시각을 지정해둔 일이 더 많이 끝나는지 보려면, 지정 여부가 그날
          // 기록에 남아 있어야 한다. 기록에 없는 것은 나중에 못 센다.
          'hasTime': t['timeStart'] != null || t['time'] != null,
          'deferred': false,
        },
      ),
      ...deferredList.map(
        (t) => {
          'text': t['text'],
          'done': t['done'] ?? false,
          'category': t['category'] ?? 'today',
          'deferred': true,
        },
      ),
    ];

    final record = {
      'date': todayStr,
      'totalCount': countableTasks.length,
      'doneCount': doneTasks.length,
      'success': doneTasks.isNotEmpty,
      'updatedAt': DateTime.now().toIso8601String(),
      'tasks': mergedTasks,
    };

    final idx = history.indexWhere((h) => h['date'] == todayStr);
    if (idx >= 0) {
      history[idx] = record;
    } else {
      history.add(record);
    }

    history.sort((a, b) => a['date']!.compareTo(b['date']!));
    if (history.length > 30) history = history.sublist(history.length - 30);

    await prefs.setString('nyang_history', jsonEncode(history));
  }

  static bool _countsTowardDailyCompletion(
    Map<String, dynamic> task,
    List<dynamic> habits,
  ) {
    final habitId = task['habitId']?.toString();
    if (habitId == null) return true;
    Map<dynamic, dynamic>? habit;
    for (final item in habits) {
      if (item is Map && item['id']?.toString() == habitId) {
        habit = item;
        break;
      }
    }
    if (habit == null) return true;
    return habit['freq'] != 'weekly_count' || task['done'] == true;
  }
}
