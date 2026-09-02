class LocalReplyTexts {
  const LocalReplyTexts._();

  static String todayTaskTimeReply({
    required String coachId,
    required String text,
    required String timeLabel,
  }) {
    if (timeLabel.isEmpty) {
      return switch (coachId) {
        'cat' || 'nyang_halbae' => "오늘 '$text' 시간은 아직 안 잡혀 있다냥.",
        'bro' => "오늘 '$text' 시간은 아직 안 잡혀 있다.",
        'sec_female' => "오늘 '$text' 시간은 아직 정해져 있지 않아요.",
        _ => "오늘 '$text' 시간은 아직 안 잡혀 있어.",
      };
    }
    return switch (coachId) {
      'cat' || 'nyang_halbae' => "오늘 '$text'은 $timeLabel부터다냥.",
      'bro' => "오늘 '$text'은 $timeLabel부터다.",
      'sec_female' => "오늘 '$text'은 $timeLabel부터예요.",
      _ => "오늘 '$text'은 $timeLabel부터야.",
    };
  }
}
