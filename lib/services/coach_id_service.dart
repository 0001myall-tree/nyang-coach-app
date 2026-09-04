class CoachIdService {
  static const String legacyNyangHalbaeId = 'sec_male';
  static const String legacyGodlifeBroId = 'godlife_bro';
  static const String nyangHalbaeId = 'nyang_halbae';
  static const String broId = 'bro';
  static const String secretaryChiefId = 'sec_female';
  static const String defaultCoachId = 'cat';

  static String normalize(String? coachId, {String fallback = defaultCoachId}) {
    final id = coachId?.trim();
    if (id == null || id.isEmpty) return fallback;
    if (id == legacyNyangHalbaeId) return nyangHalbaeId;
    if (id == legacyGodlifeBroId) return broId;
    return id;
  }

  static bool isNyangHalbae(String? coachId) =>
      normalize(coachId) == nyangHalbaeId;

  static bool isMaster(String? coachId) {
    final normalized = normalize(coachId);
    return normalized == nyangHalbaeId || normalized == secretaryChiefId;
  }
}
