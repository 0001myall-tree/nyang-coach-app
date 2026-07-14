// 태스크 저항 예측 시스템 데이터 모델.
// 설계 근거: 선제개입_저항예측_설계문서.md 3.1
class TaskResistanceEvent {
  final String id;
  final String taskId;
  final String taskText;

  /// 반복그룹 식별자. habitId가 있으면 'habit_{habitId}', 없으면 'text_{정규화된 태스크텍스트}'.
  /// 기록 시점에 결정적으로 계산되며(LLM 불필요), 이후 변경되지 않는다.
  final String groupId;

  /// yyyy-MM-dd
  final String date;

  /// 'explicit' | 'implicit'
  final String signalType;

  /// 0~1. 현재는 explicit=1.0, implicit=0.4 고정값.
  final double intensity;

  final bool completedEventually;

  /// 그날 몇 번째로 완료했는지 (done 타임스탬프 기반, 미완료면 null)
  final int? completionOrder;

  final int totalTasksThatDay;

  TaskResistanceEvent({
    required this.id,
    required this.taskId,
    required this.taskText,
    required this.groupId,
    required this.date,
    required this.signalType,
    required this.intensity,
    required this.completedEventually,
    this.completionOrder,
    required this.totalTasksThatDay,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskText': taskText,
    'groupId': groupId,
    'date': date,
    'signalType': signalType,
    'intensity': intensity,
    'completedEventually': completedEventually,
    'completionOrder': completionOrder,
    'totalTasksThatDay': totalTasksThatDay,
  };

  factory TaskResistanceEvent.fromJson(Map<String, dynamic> j) =>
      TaskResistanceEvent(
        id: j['id'] as String,
        taskId: j['taskId'] as String,
        taskText: j['taskText'] as String? ?? '',
        groupId: j['groupId'] as String? ?? '',
        date: j['date'] as String,
        signalType: j['signalType'] as String? ?? 'explicit',
        intensity: (j['intensity'] as num?)?.toDouble() ?? 1.0,
        completedEventually: j['completedEventually'] as bool? ?? false,
        completionOrder: (j['completionOrder'] as num?)?.toInt(),
        totalTasksThatDay: (j['totalTasksThatDay'] as num?)?.toInt() ?? 0,
      );
}
