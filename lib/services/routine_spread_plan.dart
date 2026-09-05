import 'package:flutter/foundation.dart';

/// 매일 루틴을 요일로 나눌 때 쓰는 값들.
///
/// 어느 루틴을 나눌지는 사용자가 고른다. 코치가 대신 고르면 목표를 향해 매일
/// 쌓는 중인 일이나 영양제처럼 매일 해야 뜻이 서는 일을 건드릴 수 있는데,
/// 그건 되돌린다고 없던 일이 되지 않는다.
///
/// 여기서 반드시 막아야 하는 것이 하나 있다. **요일이 하나도 없는 배정**이다.
/// 그렇게 저장되면 그 루틴은 루틴 탭에는 그대로 보이는데 오늘 탭에는 영영
/// 올라오지 않는다. 사용자에게는 사라진 것과 구별되지 않는다.
class RoutineSpreadPlan {
  const RoutineSpreadPlan._();

  static const List<String> dayNames = ['월', '화', '수', '목', '금', '토', '일'];

  /// 나눌 때 기본으로 잡는 요일. 화·목.
  ///
  /// 주 2회로 줄이면 하루 몫이 확 준다. 월요일은 한 주가 시작하느라 이미
  /// 무겁고 금요일은 지쳐 있어서, 가운데 이틀이 가장 지키기 쉽다.
  /// 마음에 안 들면 루틴 탭에서 바꾼다 — 그래서 여기서 정답을 찾을 이유가 없다.
  static const List<int> defaultDays = [1, 3];

  /// 사람에게 보여줄 요일. `화·목`.
  static String label(List<int> days) =>
      days.map((d) => dayNames[d]).join('·');
}

@immutable
class RoutineDayAssignment {
  const RoutineDayAssignment({required this.name, required this.days});

  /// 루틴 이름. 저장소에서 찾을 때 쓴다.
  final String name;

  /// 0=월 ~ 6=일. 비어 있으면 적용하는 쪽이 거른다.
  final List<int> days;

  String get dayLabel => RoutineSpreadPlan.label(days);
}
