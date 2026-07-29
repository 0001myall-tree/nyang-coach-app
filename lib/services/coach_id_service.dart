class CoachIdService {
  static const String legacyNyangHalbaeId = 'sec_male';
  static const String nyangHalbaeId = 'nyang_halbae';
  static const String secretaryChiefId = 'sec_female';
  static const String defaultCoachId = 'cat';

  static String normalize(String? coachId, {String fallback = defaultCoachId}) {
    final id = coachId?.trim();
    if (id == null || id.isEmpty) return fallback;
    if (id == legacyNyangHalbaeId) return nyangHalbaeId;
    return id;
  }

  static bool isNyangHalbae(String? coachId) =>
      normalize(coachId) == nyangHalbaeId;

  static bool isMaster(String? coachId) {
    final normalized = normalize(coachId);
    return normalized == nyangHalbaeId || normalized == secretaryChiefId;
  }
}
