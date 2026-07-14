// 반복그룹 단위 저항 프로필. 설계 근거: 선제개입_저항예측_설계문서.md 3.2
// (habitId 또는 정규화된 태스크텍스트로 묶은 그룹. LLM 태그 분류를 대체함 — 갱신이력 참고)
class ResistanceGroupProfile {
  final String groupId;

  /// 화면 표시/디버깅용 예시 텍스트 (그룹에 속한 태스크 중 하나)
  final String sampleText;

  final double resistanceScore;
  final double confidence;

  /// 'active' | 'tapering_test' | 'faded' (설계문서 6.2 상태머신)
  final String interventionMode;

  final int consecutiveSuccessCount;
  final bool taperingTestConsumed;

  /// yyyy-MM-dd
  final String lastUpdated;

  final int eventCount;

  ResistanceGroupProfile({
    required this.groupId,
    required this.sampleText,
    required this.resistanceScore,
    required this.confidence,
    this.interventionMode = 'active',
    this.consecutiveSuccessCount = 0,
    this.taperingTestConsumed = false,
    required this.lastUpdated,
    required this.eventCount,
  });

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'sampleText': sampleText,
    'resistanceScore': resistanceScore,
    'confidence': confidence,
    'interventionMode': interventionMode,
    'consecutiveSuccessCount': consecutiveSuccessCount,
    'taperingTestConsumed': taperingTestConsumed,
    'lastUpdated': lastUpdated,
    'eventCount': eventCount,
  };

  factory ResistanceGroupProfile.fromJson(Map<String, dynamic> j) =>
      ResistanceGroupProfile(
        groupId: j['groupId'] as String,
        sampleText: j['sampleText'] as String? ?? '',
        resistanceScore: (j['resistanceScore'] as num?)?.toDouble() ?? 0.0,
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
        interventionMode: j['interventionMode'] as String? ?? 'active',
        consecutiveSuccessCount:
            (j['consecutiveSuccessCount'] as num?)?.toInt() ?? 0,
        taperingTestConsumed: j['taperingTestConsumed'] as bool? ?? false,
        lastUpdated: j['lastUpdated'] as String? ?? '',
        eventCount: (j['eventCount'] as num?)?.toInt() ?? 0,
      );
}
