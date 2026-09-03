import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/coach_id_service.dart';
import 'package:nyang_coach/services/daily_reset_service.dart';
import 'package:nyang_coach/services/tasks_sync_service.dart';

/// 오래된 클라우드 값이 방금 저장한 로컬 값을 덮어쓰지 못하게 막는 목록.
///
/// 이 목록에서 빠진 데이터는 조용히 사라진다. 메모, 습관 완료, 대화 기록이
/// 차례로 같은 이유로 없어졌다. 새 데이터를 만들 때 여기 넣는 걸 잊지 않도록
/// 테스트로 박아둔다.
void main() {
  group('덮어쓰기 보호 대상', () {
    test('코치별 대화 기록과 보관함이 모두 들어 있다', () {
      for (final coachId in DailyResetService.coachIds) {
        final normalized = CoachIdService.normalize(coachId);
        expect(
          TasksSyncService.isCriticalKey('nyang_chat_history_$normalized'),
          isTrue,
          reason: '$normalized 대화 기록이 보호를 못 받으면 방금 한 대화가 옛 값에 덮인다',
        );
        expect(
          TasksSyncService.isCriticalKey(
            '${DailyResetService.chatArchivePrefix}$normalized',
          ),
          isTrue,
          reason: '$normalized 보관함이 보호를 못 받으면 어제 대화가 옛 값에 덮인다',
        );
      }
    });

    test('할 일과 일정도 그대로 들어 있다', () {
      expect(TasksSyncService.isCriticalKey('nyang_tasks'), isTrue);
      expect(TasksSyncService.isCriticalKey('nyang_core_tasks'), isTrue);
      expect(TasksSyncService.isCriticalKey('nyang_schedules'), isTrue);
      expect(TasksSyncService.isCriticalKey('nyang_habit_logs'), isTrue);
    });

    test('못 올린 변경이 있다는 표시는 클라우드가 건드리지 못한다', () {
      // 'nyang_'으로 시작하면 클라우드 복원이 이 표시까지 덮어쓴다. 그러면
      // 로그인 전에 자정 정리가 끝난 기기가 보호를 잃고, 어제 대화가 옛
      // 클라우드 값으로 되돌아간다.
      expect(
        TasksSyncService.pendingUploadFlagKey.startsWith('nyang_'),
        isFalse,
      );
    });

    test('다시 만들 수 있는 화면 설정까지 붙잡지는 않는다', () {
      expect(TasksSyncService.isCriticalKey('nyang_chat_bg_style'), isFalse);
      expect(
        TasksSyncService.isCriticalKey('nyang_has_synced_from_cloud'),
        isFalse,
      );
    });
  });
}
