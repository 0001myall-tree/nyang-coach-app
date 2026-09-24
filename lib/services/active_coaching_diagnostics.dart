/// 적극 코칭이 안 뜰 때, 지금 폰이 어떤 상태인지 그 자리에서 보여준다.
///
/// 안 뜨는 길이 여럿이다 — 스위치가 꺼졌거나, 오늘이 고른 요일이 아니거나,
/// 방금 한 번 나가서 쉬는 중이거나, 오늘 몫을 다 썼거나, 권한이 막고 있거나,
/// 부를 일이 아예 없거나. 화면에는 "아무 일도 안 일어남"이라는 결과만 남아서
/// 여섯 가지가 구별되지 않는다. 고치는 자리는 전부 다르다.
///
/// 짐작으로 맞히지 않으려고 만든 자리다. 값을 그대로 읽어 적는다.
library;

import 'active_coaching_plan.dart';
import 'active_coaching_state.dart';
import 'active_coaching_target.dart';

class ActiveCoachingDiagnostics {
  const ActiveCoachingDiagnostics._();

  /// 사람이 읽을 수 있는 한 장.
  ///
  /// [plan]은 지금 상태로 다시 계산한 다음 개입. [planned]는 실제로 걸어둔 것
  /// (`ActiveCoachingSync.plannedKey`에 적힌 값)이다. 둘이 다르면 걸어둔 뒤에
  /// 상황이 바뀐 것이다.
  static String build({
    required DateTime now,
    required bool enabled,
    required bool master,
    required Set<int> onDays,
    required List<String> times,
    required ActiveCoachingBudget budget,
    required ActiveCoachingDay day,
    ActiveCoachingPlan? plan,
    DateTime? plannedAt,
    String? plannedTitle,
    List<DateTime> plannedQueue = const [],
    Map<String, bool> blockers = const {},
    Map<String, String> taskNames = const {},
  }) {
    String name(String id) => taskNames[id] ?? id;
    final lines = <String>[];
    lines.add('지금 ${_clock(now)} (${_weekday(now.weekday)})');
    lines.add('');

    lines.add('[설정]');
    lines.add('적극 코칭 ${enabled ? '켜짐' : '꺼짐'}');
    lines.add('마스터 ${master ? '맞음' : '아님'}');
    lines.add('참견 요일 ${_days(onDays)}');
    lines.add('오늘 요일 ${onDays.contains(now.weekday) ? '포함' : '빠짐'}');
    lines.add('여유 시간 ${times.isEmpty ? '없음' : times.join(' · ')}');
    if (!enabled) lines.add('※ 꺼져 있어 아무것도 걸리지 않음');
    if (!master) lines.add('※ 마스터가 아니라 걸리지 않음');
    if (!onDays.contains(now.weekday)) lines.add('※ 오늘은 참견하지 않는 요일');
    lines.add('');

    lines.add('[오늘 예산]');
    lines.add('나간 횟수 ${budget.spokenToday} / ${ActiveCoachingBudget.dailyCap}');
    lines.add(
      '마지막으로 말 건 때 '
      '${budget.lastSpokeAt == null ? '없음' : _clock(budget.lastSpokeAt!)}',
    );
    lines.add('연속 무응답 ${budget.noReplyStreak}');
    lines.add('지금 간격 ${budget.currentInterval.inHours}시간');
    final resting = budget.lastSpokeAt?.add(budget.currentInterval);
    if (resting != null && resting.isAfter(now)) {
      lines.add('※ 쉬는 중 — ${_clock(resting)}부터 다시 부를 수 있음');
    }
    if (budget.spokenToday >= ActiveCoachingBudget.dailyCap) {
      lines.add('※ 오늘 몫을 다 씀');
    }
    lines.add(
      '하루 닫는 말 '
      '${budget.wrappedUpAt == null ? '아직' : '${_clock(budget.wrappedUpAt!)}에 건넴'}',
    );
    lines.add(
      '직전에 다룬 일 '
      '${budget.lastTaskId == null ? '없음' : name(budget.lastTaskId!)}',
    );
    lines.add('');

    lines.add('[추적 중]');
    if (day.tasks.isEmpty) {
      lines.add('없음');
    } else {
      for (final entry in day.tasks.entries) {
        final t = entry.value;
        final marks = [
          if (t.promisedAt != null) '약속 ${_clock(t.promisedAt!)}',
          if (t.nudges > 0) '${t.nudges}번 말 검',
          if (t.reason != null) '이유 ${t.reason}',
          if (t.isSettled) '결정 ${_decision(t.decision)}',
          if (t.pickedByUser) '직접 고름',
        ];
        lines.add(
          '${name(entry.key)}: ${marks.isEmpty ? '표시 없음' : marks.join(' · ')}',
        );
      }
    }
    lines.add('');

    lines.add('[걸어둔 자리]');
    if (plannedAt == null) {
      lines.add('없음');
    } else {
      lines.add('${_clock(plannedAt)}  ${plannedTitle ?? ''}'.trim());
      if (!plannedAt.isAfter(now)) lines.add('※ 이미 지난 시각 — 나갔거나 걸러짐');
    }
    // 앱을 안 열어도 이어서 걸릴 오늘 차례들. 하나가 지나가면 다음 것이 걸린다.
    if (plannedQueue.length > 1) {
      lines.add('오늘 남은 차례 ${plannedQueue.map(_clock).join(' · ')}');
    }
    lines.add('');

    lines.add('[지금 다시 계산하면]');
    if (plan == null) {
      lines.add('부를 자리 없음');
    } else {
      lines.add('${_clock(plan.at)}  ${_signal(plan.signal)}');
      if (plan.taskText != null) lines.add('대상 ${plan.taskText}');
    }

    if (blockers.isNotEmpty) {
      lines.add('');
      lines.add('[막고 있는 것]');
      // 넘어오는 값에는 딴짓 방지 스위치('enabled')도 섞여 있다. 그건 적극
      // 코칭과 무관한데, 여기 적으면 꺼둔 사람에게 "막힘"으로 보인다.
      const names = {
        'overlay': '다른 앱 위에 표시',
        'exactAlarms': '알람 및 리마인더',
        'notifications': '알림',
        'batteryRestricted': '배터리 절전',
      };
      for (final key in names.keys) {
        if (!blockers.containsKey(key)) continue;
        // batteryRestricted만 참일 때가 막힌 상태다. 나머지는 거짓일 때 막혔다.
        final blocked = key == 'batteryRestricted'
            ? blockers[key]!
            : !blockers[key]!;
        lines.add('${names[key]} ${blocked ? '막힘' : '괜찮음'}');
      }
    }

    return lines.join('\n');
  }

  static String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:'
      '${at.minute.toString().padLeft(2, '0')}';

  static const List<String> _weekdayNames = ['월', '화', '수', '목', '금', '토', '일'];

  static String _weekday(int weekday) => _weekdayNames[weekday - 1];

  static String _days(Set<int> days) {
    if (days.length == 7) return '매일';
    return (days.toList()..sort()).map(_weekday).join('·');
  }

  static String _decision(ActiveCoachingDecision decision) =>
      switch (decision) {
        ActiveCoachingDecision.done => '완료',
        ActiveCoachingDecision.notToday => '오늘은 안 함',
        ActiveCoachingDecision.moved => '다른 날로',
        ActiveCoachingDecision.none => '없음',
      };

  static String _signal(ActiveCoachingSignal signal) => switch (signal) {
    ActiveCoachingSignal.promised => '약속한 시각',
    ActiveCoachingSignal.lateStart => '시작 시각 +30분',
    ActiveCoachingSignal.paused => '하다 멈춘 일',
    ActiveCoachingSignal.core => '핵심',
    ActiveCoachingSignal.onlyLeft => '남은 하나',
    ActiveCoachingSignal.askUser => '물어보기',
    ActiveCoachingSignal.nightWrap => '하루 닫는 말',
    ActiveCoachingSignal.none => '없음',
  };
}
