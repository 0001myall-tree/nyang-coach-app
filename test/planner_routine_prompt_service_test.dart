import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/planner_routine_prompt_service.dart';

Map<String, dynamic> record(String date, List<Map<String, dynamic>> tasks) => {
  'date': date,
  'totalCount': tasks.length,
  'tasks': tasks,
};

Map<String, dynamic> task(String text, {String category = 'today'}) => {
  'text': text,
  'category': category,
};

void main() {
  final now = DateTime(2026, 8, 25, 10);

  test('최근 7일 중 계획 없는 날이 4일 이상이면 제안한다', () {
    final history = [
      record('2026-08-24', []),
      record('2026-08-23', []),
      record('2026-08-22', [task('운동')]),
      record('2026-08-21', []),
    ];

    expect(
      PlannerRoutinePromptService.shouldOffer(
        history: history,
        todayTasks: [],
        habits: const [],
        now: now,
      ),
      isTrue,
    );
  });

  test('30일 쿨다운 안이면 제안하지 않는다', () {
    final history = [
      record('2026-08-24', []),
      record('2026-08-23', []),
      record('2026-08-22', []),
    ];

    expect(
      PlannerRoutinePromptService.shouldOffer(
        history: history,
        todayTasks: [],
        habits: const [],
        now: now,
        lastOfferedAt: now.subtract(const Duration(days: 10)),
      ),
      isFalse,
    );
  });

  test('이미 플래너 보기 루틴이 있으면 제안하지 않는다', () {
    final history = [
      record('2026-08-24', []),
      record('2026-08-23', []),
      record('2026-08-22', []),
    ];

    expect(
      PlannerRoutinePromptService.shouldOffer(
        history: history,
        todayTasks: [],
        habits: [
          {'name': '아침 플래너 확인', 'freq': 'daily', 'timeStart': '09:00'},
        ],
        now: now,
      ),
      isFalse,
    );
  });

  test('루틴만 자동으로 채워진 날은 계획을 짠 날로 세지 않는다', () {
    final history = [
      record('2026-08-24', [task('물 마시기', category: 'habit')]),
      record('2026-08-23', [task('스트레칭', category: 'habit')]),
      record('2026-08-22', []),
    ];

    expect(
      PlannerRoutinePromptService.shouldOffer(
        history: history,
        todayTasks: [task('명상', category: 'habit')],
        habits: const [],
        now: now,
      ),
      isTrue,
    );
  });
}
