import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'routine_spread_plan.dart';
import 'tasks_sync_service.dart';

/// 코치가 짚어준 요일 배정을 루틴에 적는다.
///
/// 이름으로 찾는다. 코치는 사용자가 부르는 이름으로 말하지 저장소의 id를 모른다.
/// 못 찾은 이름은 건너뛴다 — 코치가 없는 루틴을 지어냈을 때 엉뚱한 것을 고치는
/// 것보다 아무것도 안 하는 쪽이 낫다.
class RoutineSpreadApply {
  const RoutineSpreadApply._();

  static const String _habitsKey = 'nyang_habits';

  /// 적은 것들의 이름. 하나도 못 적었으면 빈 목록.
  static Future<List<String>> apply(
    List<RoutineDayAssignment> assignments,
  ) async {
    if (assignments.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final raw = prefs.getString(_habitsKey);
    List<dynamic> habits;
    try {
      final decoded = jsonDecode(raw ?? '[]');
      if (decoded is! List) return const [];
      habits = decoded;
    } catch (_) {
      return const [];
    }

    final applied = <String>[];
    for (final assignment in assignments) {
      // 여기 오는 배정에는 요일이 반드시 하나 이상 있다(RoutineSpreadPlan이
      // 거른다). 그래도 한 번 더 본다 — 요일이 빈 채로 저장되면 그 루틴은
      // 루틴 탭에만 남고 오늘 탭에서 영영 사라진다.
      if (assignment.days.isEmpty) continue;

      final index = _indexOfHabit(habits, assignment.name);
      if (index < 0) continue;

      final habit = Map<String, dynamic>.from(habits[index] as Map);
      habit['freq'] = 'weekly';
      habit['days'] = List<int>.from(assignment.days);
      // 주 n회로 쓰던 값이 남아 있으면 화면이 그걸 먼저 읽는다.
      habit.remove('weeklyTargetCount');
      habits[index] = habit;
      applied.add(assignment.name);
    }
    if (applied.isEmpty) return const [];

    await prefs.setString(_habitsKey, jsonEncode(habits));
    TasksSyncService.scheduleSyncToCloud();
    return applied;
  }

  /// 이름이 같은 루틴의 자리. 없으면 -1.
  ///
  /// 띄어쓰기만 다른 경우까지는 같은 것으로 본다. 코치가 "SNS 글쓰기"를
  /// "SNS글쓰기"로 적는 일이 있다.
  @visibleForTesting
  static int indexOfHabit(List<dynamic> habits, String name) =>
      _indexOfHabit(habits, name);

  static int _indexOfHabit(List<dynamic> habits, String name) {
    final target = _normalize(name);
    if (target.isEmpty) return -1;
    for (var i = 0; i < habits.length; i++) {
      final item = habits[i];
      if (item is! Map) continue;
      if (_normalize(item['name']?.toString() ?? '') == target) return i;
    }
    return -1;
  }

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
