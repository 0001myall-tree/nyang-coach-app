import 'package:shared_preferences/shared_preferences.dart';

class UserTitleService {
  static const String defaultTitle = '대표님';
  static const String prefKey = 'nyang_master_title';

  static Future<String> getTitle() async {
    final prefs = await SharedPreferences.getInstance();
    final title = prefs.getString(prefKey)?.trim();
    return title == null || title.isEmpty ? defaultTitle : title;
  }

  static bool isSecretaryCoach(String coachId) {
    return coachId == 'sec_male' || coachId == 'sec_female';
  }

  static Future<String> applyForCoach(String text, String coachId) async {
    if (!isSecretaryCoach(coachId)) return text;
    final title = await getTitle();
    return text.replaceAll(defaultTitle, title);
  }
}
