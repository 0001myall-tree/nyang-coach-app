import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'daily_reset_service.dart';
import 'planner_action.dart';
import 'task_completion_service.dart';

/// 채팅에서 받은 조작을 저장소에 직접 적용한다.
///
/// 할 일 화면을 거치지 않는다. 그 화면은 플래너를 열었을 때만 존재해서, 채팅
/// 중에는 부를 상대가 없다. 배너 버튼이 화면 없이 완료를 적는 것과 같은 자리다.
///
/// 저장소는 셋이다. 오늘 할 일, 날짜별 일정, 날짜별로 미리 세워둔 계획.
/// 무엇을 옮긴다는 것은 이 중 한 곳에서 빼고 다른 곳에 넣는 일이기도 하다.
class PlannerEditService {
  static const String _tasksKey = 'nyang_tasks';
  static const String _schedulesKey = 'nyang_schedules';

  /// 찾기만 하고 아무것도 바꾸지 않는다.
  ///
  /// 확인 카드에 무엇을 어떻게 바꿀지 적으려면 대상이 실제로 있는지 먼저 알아야
  /// 한다. 없는 것을 두고 "옮길까?"라고 물으면 눌러도 아무 일이 안 일어난다.
  static Future<PlannerActionResult> preview(PlannerAction action) =>
      _run(action, dryRun: true);

  /// 실제로 바꾼다.
  static Future<PlannerActionResult> apply(PlannerAction action) =>
      _run(action, dryRun: false);

  static Future<PlannerActionResult> _run(
    PlannerAction action, {
    required bool dryRun,
  }) async {
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
    final label = hit.item['text']?.toString() ?? action.target;

    return switch (action.kind) {
      PlannerActionKind.move => _move(prefs, hit, action, label, dryRun),
      PlannerActionKind.done => _complete(prefs, hit, label, dryRun),
      PlannerActionKind.remind => _remind(prefs, hit, action, label, dryRun),
      PlannerActionKind.morning => const PlannerActionResult(
        PlannerActionStatus.failed,
      ),
    };
  }

  // ── 찾기 ──────────────────────────────────────

  static List<_Hit> _find(SharedPreferences prefs, PlannerAction action) {
    final hits = <_Hit>[];
    final todayKey = dateKey(DateTime.now());
    // 완료는 지난 날의 일도 받는다. "어제 했던 청소 완료했어"처럼.
    final wantKey = action.kind == PlannerActionKind.done && action.date != null
        ? dateKey(action.date!)
        : null;

    if (wantKey == null || wantKey == todayKey) {
      for (final task in _list(prefs.getString(_tasksKey))) {
        if (_titleMatches(task['text']?.toString() ?? '', action.target)) {
          hits.add(_Hit(_Store.today, task, todayKey));
        }
      }
    }

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
        if (_titleMatches(item['text']?.toString() ?? '', action.target)) {
          hits.add(_Hit(_Store.schedule, item, key));
        }
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

  // ── 옮기기 ────────────────────────────────────

  static Future<PlannerActionResult> _move(
    SharedPreferences prefs,
    _Hit hit,
    PlannerAction action,
    String label,
    bool dryRun,
  ) async {
    final detail = moveDetail(date: action.date, time: action.time);
    if (dryRun) {
      return PlannerActionResult(
        PlannerActionStatus.ok,
        label: label,
        detail: detail,
      );
    }

    final time = action.time;
    if (time != null) {
      final stored =
          '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
      hit.item['timeStart'] = stored;
      hit.item['time'] = clockLabel(time.hour, time.minute);
      // 끝 시각이 시작보다 앞서면 남겨둘 수 없다. 어느 쪽이 맞는지 알 수 없다.
      final end = hit.item['timeEnd']?.toString();
      if (end != null && end.compareTo(stored) <= 0) {
        hit.item.remove('timeEnd');
      }
    }

    final toKey = action.date == null ? null : dateKey(action.date!);
    if (toKey != null && toKey != hit.dateKey) {
      _detach(hit);
      await _insert(prefs, hit, toKey);
    }

    await _save(prefs, hit);
    return PlannerActionResult(
      PlannerActionStatus.ok,
      label: label,
      detail: detail,
    );
  }

  /// 다른 날로 옮기기 전에 정리한다.
  static void _detach(_Hit hit) {
    hit.item['deferredCount'] =
        ((hit.item['deferredCount'] as num?)?.toInt() ?? 0) + 1;
    // 옮긴 날에는 아직 하지 않은 일이다.
    hit.item['done'] = false;
    hit.item['inProgress'] = false;
    hit.item.remove('runStartedAt');
    hit.item.remove('inProgressAt');
    hit.item.remove('completedAt');
    // 반복에서 떼어낸다. 규칙을 그대로 두면 다음 계산에서 원래 자리로 돌아온다.
    hit.item['isRecurring'] = false;
    hit.item.remove('recurrenceRule');
    hit.item.remove('recurrenceGroupId');
  }

  static Future<void> _insert(
    SharedPreferences prefs,
    _Hit hit,
    String toKey,
  ) async {
    // 일정은 일정끼리, 할 일은 할 일끼리 옮긴다.
    if (hit.store == _Store.schedule) {
      final all = _map(prefs.getString(_schedulesKey));
      final day = _asList(all[toKey]);
      day.add(hit.item);
      all[toKey] = day;
      _removeFrom(all, hit);
      await prefs.setString(_schedulesKey, jsonEncode(all));
      hit.movedTo = _Store.schedule;
      return;
    }

    final all = _map(prefs.getString(DailyResetService.plannedTasksByDateKey));
    final day = _asList(all[toKey]);
    day.add(hit.item);
    all[toKey] = day;
    if (hit.store == _Store.planned) _removeFrom(all, hit);
    await prefs.setString(
      DailyResetService.plannedTasksByDateKey,
      jsonEncode(all),
    );
    if (hit.store == _Store.today) {
      final tasks = _list(prefs.getString(_tasksKey))
          .where((t) => t['id'].toString() != hit.item['id'].toString())
          .toList();
      await prefs.setString(_tasksKey, jsonEncode(tasks));
    }
    hit.movedTo = _Store.planned;
  }

  static void _removeFrom(Map<String, dynamic> all, _Hit hit) {
    final day = _asList(all[hit.dateKey]);
    day.removeWhere((e) => e['id'].toString() == hit.item['id'].toString());
    if (day.isEmpty) {
      all.remove(hit.dateKey);
    } else {
      all[hit.dateKey] = day;
    }
  }

  // ── 완료 ──────────────────────────────────────

  static Future<PlannerActionResult> _complete(
    SharedPreferences prefs,
    _Hit hit,
    String label,
    bool dryRun,
  ) async {
    if (hit.item['done'] == true) {
      return PlannerActionResult(PlannerActionStatus.noChange, label: label);
    }
    if (dryRun) {
      return PlannerActionResult(PlannerActionStatus.ok, label: label);
    }
    // 오늘 할 일은 기록·루틴 도장까지 함께 찍혀야 한다. 그 일을 이미 하는
    // 곳이 있으므로 여기서 값을 직접 쓰지 않는다.
    if (hit.store == _Store.today) {
      final done = await TaskCompletionService.completeStoredTask(
        taskId: hit.item['id'].toString(),
      );
      return PlannerActionResult(
        done ? PlannerActionStatus.ok : PlannerActionStatus.failed,
        label: label,
      );
    }
    hit.item['done'] = true;
    hit.item['completedAt'] = DateTime.now().toIso8601String();
    await _save(prefs, hit);
    return PlannerActionResult(PlannerActionStatus.ok, label: label);
  }

  // ── 알람 ──────────────────────────────────────

  static Future<PlannerActionResult> _remind(
    SharedPreferences prefs,
    _Hit hit,
    PlannerAction action,
    String label,
    bool dryRun,
  ) async {
    final on = action.enabled ?? false;
    // 시각이 없으면 알람이 울릴 자리가 없다.
    if (on && (hit.item['timeStart']?.toString() ?? '').isEmpty) {
      return PlannerActionResult(PlannerActionStatus.failed, label: label);
    }
    if ((hit.item['isReminderEnabled'] == true) == on) {
      return PlannerActionResult(PlannerActionStatus.noChange, label: label);
    }
    if (dryRun) {
      return PlannerActionResult(PlannerActionStatus.ok, label: label);
    }
    hit.item['isReminderEnabled'] = on;
    await _save(prefs, hit);
    return PlannerActionResult(PlannerActionStatus.ok, label: label);
  }

  // ── 저장 ──────────────────────────────────────

  static Future<void> _save(SharedPreferences prefs, _Hit hit) async {
    // 옮기면서 이미 두 저장소를 다 썼다면 다시 쓸 것이 없다.
    if (hit.movedTo == null) {
      switch (hit.store) {
        case _Store.today:
          final tasks = _list(prefs.getString(_tasksKey));
          _replaceIn(tasks, hit.item);
          await prefs.setString(_tasksKey, jsonEncode(tasks));
        case _Store.planned:
          final all = _map(
            prefs.getString(DailyResetService.plannedTasksByDateKey),
          );
          final day = _asList(all[hit.dateKey]);
          _replaceIn(day, hit.item);
          all[hit.dateKey] = day;
          await prefs.setString(
            DailyResetService.plannedTasksByDateKey,
            jsonEncode(all),
          );
        case _Store.schedule:
          final all = _map(prefs.getString(_schedulesKey));
          final day = _asList(all[hit.dateKey]);
          _replaceIn(day, hit.item);
          all[hit.dateKey] = day;
          await prefs.setString(_schedulesKey, jsonEncode(all));
      }
    }
    // 플래너가 열려 있으면 메모리에 든 옛 목록을 들고 있다. 돌아올 때 다시
    // 읽게 표시해두지 않으면, 방금 고친 것이 그 화면의 저장에 덮인다.
    await TaskCompletionService.markChangedNow();
  }

  static void _replaceIn(List<Map<String, dynamic>> list, Map<String, dynamic> item) {
    final id = item['id'].toString();
    for (var i = 0; i < list.length; i++) {
      if (list[i]['id'].toString() == id) {
        list[i] = item;
        return;
      }
    }
  }

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

enum _Store { today, planned, schedule }

class _Hit {
  _Hit(this.store, this.item, this.dateKey);

  final _Store store;
  final Map<String, dynamic> item;
  final String dateKey;

  /// 다른 날로 옮기면서 저장이 이미 끝났으면 그 자리를 적어둔다.
  _Store? movedTo;
}
