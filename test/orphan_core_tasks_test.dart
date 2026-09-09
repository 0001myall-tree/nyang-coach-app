import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';

/// 오늘의 핵심에 어제 것이 남아 있던 자리.
///
/// 자정 정리는 목록과 핵심을 같이 비운 뒤 목록만 다시 쓴다. 그 사이에 플래너
/// 화면이 기억하고 있던 어제 핵심을 저장하면 그 값이 마지막 기록으로 살아남아,
/// 오늘 목록에는 없는 어제 항목이 핵심 칸에 올라온다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<List<String>> coreTextsAfterPrune({
    required List<Map<String, dynamic>> core,
    required List<Map<String, dynamic>> todayTasks,
  }) async {
    SharedPreferences.setMockInitialValues({
      'nyang_core_tasks': jsonEncode(core),
    });
    final prefs = await SharedPreferences.getInstance();
    await DailyResetService.pruneOrphanCoreTasks(prefs, todayTasks);
    final raw = jsonDecode(prefs.getString('nyang_core_tasks')!) as List;
    return raw.map((e) => e['text'].toString()).toList();
  }

  test('오늘 목록에 없는 핵심은 걷어낸다', () async {
    final texts = await coreTextsAfterPrune(
      core: [
        {'id': 'task_1', 'text': '앱 개발'},
        {'id': 'habit_2_2026-09-09', 'text': 'sns 글쓰기'},
      ],
      todayTasks: [
        {'id': 'habit_2_2026-09-09', 'text': 'sns 글쓰기'},
      ],
    );

    expect(texts, ['sns 글쓰기']);
  });

  test('어제 아이디로 남은 루틴 핵심도 걷어낸다', () async {
    final texts = await coreTextsAfterPrune(
      core: [
        {'id': 'habit_2_2026-09-08', 'text': 'sns 글쓰기'},
      ],
      // 같은 루틴이지만 오늘 아이디로 새로 만들어졌다.
      todayTasks: [
        {'id': 'habit_2_2026-09-09', 'text': 'sns 글쓰기'},
      ],
    );

    expect(texts, isEmpty);
  });

  test('목표 마일스톤은 오늘 목록에 없어도 남긴다', () async {
    final texts = await coreTextsAfterPrune(
      core: [
        {'id': 'milestone_v1_m1', 'text': '1장 끝내기'},
        {'id': 'task_9', 'text': '어제 적은 것'},
      ],
      todayTasks: [
        {'id': 'task_2', 'text': 'sns 글쓰기'},
      ],
    );

    expect(texts, ['1장 끝내기']);
  });

  test('오늘 목록이 비었으면 아무것도 지우지 않는다', () async {
    // 목록이 빈 것은 아직 못 읽었다는 뜻일 수 있다. 그걸 기준으로 삼으면
    // 걷어내는 게 아니라 통째로 비우는 일이 된다.
    final texts = await coreTextsAfterPrune(
      core: [
        {'id': 'task_1', 'text': '앱 개발'},
      ],
      todayTasks: const [],
    );

    expect(texts, ['앱 개발']);
  });

  test('걷어낼 게 없으면 그대로 둔다', () async {
    final texts = await coreTextsAfterPrune(
      core: [
        {'id': 'task_1', 'text': '앱 개발'},
      ],
      todayTasks: [
        {'id': 'task_1', 'text': '앱 개발'},
      ],
    );

    expect(texts, ['앱 개발']);
  });
}
