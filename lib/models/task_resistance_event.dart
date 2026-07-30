// 하기 싫다고 말한 일의 기록. 저녁에 "그거 결국 하셨네요"라고 짚는 근거로만 쓴다.
// (카테고리로 묶어 점수를 매기고 코치가 먼저 개입하던 층은 2026-07-30 걷어냈다.)
class TaskResistanceEvent {
  final String id;
  final String taskId;
  final String taskText;

  /// yyyy-MM-dd
  final String date;

  /// 'explicit' | 'implicit'. 저녁 문구는 'explicit'(사용자가 직접 그렇게 말한 것)만 쓴다 —
  /// 추론으로 잡은 신호까지 세면 하지도 않은 말을 했다고 코치가 우기게 된다.
  final String signalType;

  final bool completedEventually;

  /// 그날 몇 번째로 완료했는지 (done 타임스탬프 기반, 미완료면 null)
  final int? completionOrder;

  final int totalTasksThatDay;

  TaskResistanceEvent({
    required this.id,
    required this.taskId,
    required this.taskText,
    required this.date,
    required this.signalType,
    required this.completedEventually,
    this.completionOrder,
    required this.totalTasksThatDay,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'taskId': taskId,
    'taskText': taskText,
    'date': date,
    'signalType': signalType,
    'completedEventually': completedEventually,
    'completionOrder': completionOrder,
    'totalTasksThatDay': totalTasksThatDay,
  };

  factory TaskResistanceEvent.fromJson(Map<String, dynamic> j) =>
      TaskResistanceEvent(
        id: j['id'] as String,
        taskId: j['taskId'] as String,
        taskText: j['taskText'] as String? ?? '',
        date: j['date'] as String,
        signalType: j['signalType'] as String? ?? 'explicit',
        completedEventually: j['completedEventually'] as bool? ?? false,
        completionOrder: (j['completionOrder'] as num?)?.toInt(),
        totalTasksThatDay: (j['totalTasksThatDay'] as num?)?.toInt() ?? 0,
      );
}
