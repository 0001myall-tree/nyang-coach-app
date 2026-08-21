import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reset_service.dart';
import 'planner_action.dart';

/// 코치가 짚어준 이름이 저장소 어디에 있는지 찾는다.
///
/// 값을 바꾸지는 않는다. 채팅에서 받은 부탁은 그 일을 할 수 있는 화면으로
/// 데려가는 것으로 끝나고, 바꾸는 것은 사용자가 그 화면에서 한다. 여기서 하는
/// 일은 "그런 것이 있는지, 하나뿐인지, 루틴인지"를 답해주는 것까지다.
///
/// 할 일 화면을 거치지 않는다. 그 화면은 플래너를 열었을 때만 존재해서, 채팅
/// 중에는 부를 상대가 없다.
///
/// 저장소는 넷이다. 오늘 할 일, 날짜별 일정, 날짜별로 미리 세워둔 계획, 루틴.
class PlannerEditService {
  static const String _tasksKey = 'nyang_tasks';
  static const String _schedulesKey = 'nyang_schedules';
  static const String _habitsKey = 'nyang_habits';

  /// 무엇을 가리키는지 찾는다. 아무것도 바꾸지 않는다.
  static Future<PlannerActionResult> preview(PlannerAction action) async {
    if (action.target.trim().isEmpty) {
      return const PlannerActionResult(PlannerActionStatus.notFound);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final found = _find(prefs, action);
    if (found.isEmpty) {
      return PlannerActionResult(
        PlannerActionStatus.notFound,
        label: action.target,
      );
    }
    if (found.length > 1) {
      return PlannerActionResult(
        PlannerActionStatus.multiple,
        label: action.target,
      );
    }

    final hit = found.first;
    final label =
        (hit.item['text'] ?? hit.item['name'])?.toString() ?? action.target;

    // 이미 끝낸 일은 고칠 것이 없다. 수정 창을 열어봐야 할 일이 없다.
    if (hit.item['done'] == true) {
      return PlannerActionResult(PlannerActionStatus.noChange, label: label);
    }

    // 끝냈다는 말은 루틴이라도 오늘 하루의 체크다. 오늘 목록에 내려와 있으면
    // 그 칸으로 데려간다 — 루틴 탭에는 오늘 체크할 자리가 없다.
    final todaysCopy = hit.store != _Store.habit;
    if (action.kind == PlannerActionKind.done && todaysCopy) {
      return PlannerActionResult(PlannerActionStatus.ok, label: label);
    }

    // 시각과 요일은 루틴 탭에서 고친다. 오늘 목록에 안 내려온 루틴은 오늘 할
    // 것이 아니므로 완료도 여기서 할 일이 없다.
    if (hit.isRoutine || hit.store == _Store.habit) {
      return PlannerActionResult(PlannerActionStatus.routine, label: label);
    }
    return PlannerActionResult(PlannerActionStatus.ok, label: label);
  }

  // ── 찾기 ──────────────────────────────────────

  static List<_Hit> _find(SharedPreferences prefs, PlannerAction action) {
    final hits = <_Hit>[];
    final todayKey = dateKey(DateTime.now());
    // 완료는 지난 날의 일도 받는다. "어제 했던 청소 완료했어"처럼.
    final wantKey = action.kind == PlannerActionKind.done && action.date != null
        ? dateKey(action.date!)
        : null;

    // 루틴을 먼저 찾아둔다. 이름이 걸리는지 알아야 오늘 목록의 그 항목이
    // 루틴에서 온 것인지 알 수 있다.
    final habitHits = <String, _Hit>{};
    for (final habit in _list(prefs.getString(_habitsKey))) {
      if (_titleMatches(habit['name']?.toString() ?? '', action.target)) {
        habitHits[habit['id'].toString()] = _Hit(
          _Store.habit,
          habit,
          todayKey,
        );
      }
    }

    // 오늘 목록에 내려온 일정이 원본과 따로 세어지지 않게, 그 원본의 id를
    // 적어둔다. 일정은 오늘 목록에 'schedule_<원본id>'로 복사되어 들어온다.
    final injectedScheduleIds = <String>{};

    if (wantKey == null || wantKey == todayKey) {
      for (final task in _list(prefs.getString(_tasksKey))) {
        if (!_titleMatches(task['text']?.toString() ?? '', action.target)) {
          continue;
        }
        // 오늘 목록에 내려온 것이 있으면 그쪽을 쓴다. 완료는 오늘 하루의
        // 일이라 루틴 정의가 아니라 오늘치에 적혀야 한다.
        habitHits.remove(task['habitId']?.toString());
        final id = task['id'].toString();
        if (id.startsWith('schedule_')) {
          injectedScheduleIds.add(id.substring('schedule_'.length));
        }
        hits.add(_Hit(_Store.today, task, todayKey));
      }
    }

    // 오늘 목록에 안 내려온 루틴만 남는다. 이건 오늘 할 것이 아니므로 여기서
    // 고칠 것이 없고, 루틴 탭으로 보내는 표시로만 쓴다.
    hits.addAll(habitHits.values);

    final planned = _map(prefs.getString(DailyResetService.plannedTasksByDateKey));
    planned.forEach((key, value) {
      if (key == todayKey) return;
      if (wantKey != null && key != wantKey) return;
      for (final task in _asList(value)) {
        if (_titleMatches(task['text']?.toString() ?? '', action.target)) {
          hits.add(_Hit(_Store.planned, task, key));
        }
      }
    });

    final schedules = _map(prefs.getString(_schedulesKey));
    schedules.forEach((key, value) {
      if (wantKey != null && key != wantKey) return;
      for (final item in _asList(value)) {
        if (!_titleMatches(item['text']?.toString() ?? '', action.target)) {
          continue;
        }
        // 오늘 목록에서 이미 센 것이면 건너뛴다. 둘 다 세면 하나뿐인 일정이
        // "여러 개 있다"가 되고, 사용자는 있지도 않은 선택을 하라는 말을 듣는다.
        if (injectedScheduleIds.contains(item['id'].toString())) continue;
        hits.add(_Hit(_Store.schedule, item, key));
      }
    });

    return hits;
  }

  /// 오늘 목록에 일정이 그대로 복사되어 들어오기도 한다. 같은 것을 두 번 세면
  /// "여럿이라 못 고르겠다"가 되어버리므로, 이름이 같고 날짜도 같으면 하나로 본다.
  static bool _titleMatches(String title, String target) {
    final a = _normalize(title);
    final b = _normalize(target);
    if (b.isEmpty) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  static String _normalize(String value) => value
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'(?:약속|일정|할일|항목)$'), '')
      .replaceAll(RegExp(r'(?:을|를|은|는|이|가)$'), '')
      .toLowerCase();

  // ── 읽고 쓰기 ─────────────────────────────────

  static List<Map<String, dynamic>> _list(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Map<String, dynamic> _map(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is! List) return [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── 사람에게 보여줄 말 ────────────────────────

  static String dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// "오후 8:00". 화면의 시각 표기와 같은 모양이다.
  static String clockLabel(int hour, int minute) {
    final ampm = hour < 12 ? '오전' : '오후';
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$ampm $hour12:${minute.toString().padLeft(2, '0')}';
  }

  /// 확인 카드에 적을 말. "내일(8월 22일) 오후 8시".
  static String moveDetail({DateTime? date, ({int hour, int minute})? time}) {
    final parts = <String>[];
    if (date != null) parts.add(relativeDateLabel(date));
    if (time != null) {
      final ampm = time.hour < 12 ? '오전' : '오후';
      final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
      final tail = time.minute == 0 ? '' : ' ${time.minute}분';
      parts.add('$ampm $hour12시$tail');
    }
    return parts.join(' ');
  }

  /// 앞말에 맞는 '로/으로'를 고른다.
  ///
  /// "8시로"와 "30분으로"는 받침 유무로 갈린다. 하나로 통일하면 둘 중 하나는
  /// 반드시 어색해진다. 괄호로 끝나는 말("내일(8월 22일)")은 괄호를 건너뛰고
  /// 그 앞 글자를 본다.
  static String roJosa(String word) {
    final trimmed = word.replaceAll(RegExp(r'[)\]\s\u0027"]+\$'), '');
    if (trimmed.isEmpty) return '로';
    final code = trimmed.codeUnitAt(trimmed.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return '로';
    final finalConsonant = (code - 0xAC00) % 28;
    // 받침이 없거나 'ㄹ'이면 '로'. 그 밖에는 '으로'.
    return finalConsonant == 0 || finalConsonant == 8 ? '로' : '으로';
  }

  /// 앞말에 맞는 '이/가'를 고른다.
  static String iGaJosa(String word) => _hasFinalConsonant(word) ? '이' : '가';

  /// 앞말에 맞는 '을/를'을 고른다.
  static String eulReulJosa(String word) => _hasFinalConsonant(word) ? '을' : '를';

  static bool _hasFinalConsonant(String word) {
    final trimmed = word.replaceAll(RegExp(r'[)\]\s\u0027"]+\$'), '');
    if (trimmed.isEmpty) return false;
    final code = trimmed.codeUnitAt(trimmed.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return false;
    return (code - 0xAC00) % 28 != 0;
  }

  static String relativeDateLabel(DateTime date) {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day);
    final diff = DateTime(
      date.year,
      date.month,
      date.day,
    ).difference(base).inDays;
    final ymd = '${date.month}월 ${date.day}일';
    return switch (diff) {
      0 => '오늘',
      1 => '내일($ymd)',
      2 => '모레($ymd)',
      -1 => '어제($ymd)',
      _ => ymd,
    };
  }
}

enum _Store { today, planned, schedule, habit }

class _Hit {
  _Hit(this.store, this.item, this.dateKey);

  final _Store store;
  final Map<String, dynamic> item;
  final String dateKey;

  /// 루틴에서 온 것인지. 오늘 목록에 복사되어 들어온 것도 포함한다.
  bool get isRoutine =>
      store == _Store.habit ||
      item['isHabit'] == true ||
      item['category'] == 'habit' ||
      (item['habitId']?.toString().isNotEmpty ?? false);
}
