// 선제개입 이력. 설계 근거: 선제개입_저항예측_설계문서.md 3.3
class PreemptiveInterventionLog {
  final String id;
  final String groupId;
  final String taskId;

  /// yyyy-MM-dd
  final String date;

  final String message;
  final String coachId;

  /// 'pending' | 'resolved_low_resistance' | 'resolved_high_resistance' | 'ignored'
  final String outcome;

  PreemptiveInterventionLog({
    required this.id,
    required this.groupId,
    required this.taskId,
    required this.date,
    required this.message,
    required this.coachId,
    this.outcome = 'pending',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'taskId': taskId,
    'date': date,
    'message': message,
    'coachId': coachId,
    'outcome': outcome,
  };

  factory PreemptiveInterventionLog.fromJson(Map<String, dynamic> j) =>
      PreemptiveInterventionLog(
        id: j['id'] as String,
        groupId: j['groupId'] as String,
        taskId: j['taskId'] as String,
        date: j['date'] as String,
        message: j['message'] as String? ?? '',
        coachId: j['coachId'] as String? ?? 'cat',
        outcome: j['outcome'] as String? ?? 'pending',
      );
}
