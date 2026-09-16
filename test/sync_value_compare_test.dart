import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/tasks_sync_service.dart';

/// 클라우드에서 내려온 값이 로컬과 같은지 견주는 자리.
///
/// 여기서 "달라졌다"가 한 번 잘못 나오면 앱은 다시 올리고, 올린 것이 다시
/// 스냅샷으로 돌아와 왕복이 끝나지 않는다. 그 왕복이 한 바퀴마다 모닝콜
/// 알람을 다시 걸어 정시에 내일로 밀어버렸다.
void main() {
  group('저장값 비교', () {
    test('내용이 같은 목록은 다른 물건이어도 같은 것으로 본다', () {
      // 클라우드에서 내려온 목록은 언제나 새로 만들어진 물건이다.
      final local = <String>['2026-09-01', '2026-09-02'];
      final cloud = <dynamic>['2026-09-01', '2026-09-02'];
      expect(local == cloud, isFalse, reason: 'Dart의 리스트 비교는 내용을 안 본다');
      expect(TasksSyncService.sameStoredValue(local, cloud), isTrue);
    });

    test('빈 목록끼리도 같은 것으로 본다', () {
      expect(TasksSyncService.sameStoredValue(<String>[], <dynamic>[]), isTrue);
    });

    test('내용이 다르면 다른 것으로 본다', () {
      expect(
        TasksSyncService.sameStoredValue(
          <String>['2026-09-01'],
          <dynamic>['2026-09-02'],
        ),
        isFalse,
      );
    });

    test('길이가 다르면 다른 것으로 본다', () {
      expect(
        TasksSyncService.sameStoredValue(<String>['a'], <dynamic>['a', 'b']),
        isFalse,
      );
    });

    test('순서가 다르면 다른 것으로 본다', () {
      expect(
        TasksSyncService.sameStoredValue(
          <String>['a', 'b'],
          <dynamic>['b', 'a'],
        ),
        isFalse,
      );
    });

    test('목록은 올릴 때 글자로 펴서 보내므로 견줄 때도 글자로 본다', () {
      expect(TasksSyncService.sameStoredValue(<String>['1'], <dynamic>[1]), isTrue);
    });

    test('목록이 아닌 값은 그대로 견준다', () {
      expect(TasksSyncService.sameStoredValue('가', '가'), isTrue);
      expect(TasksSyncService.sameStoredValue('가', '나'), isFalse);
      expect(TasksSyncService.sameStoredValue(true, true), isTrue);
      expect(TasksSyncService.sameStoredValue(7, 7), isTrue);
      expect(TasksSyncService.sameStoredValue(null, null), isTrue);
      expect(TasksSyncService.sameStoredValue(null, '가'), isFalse);
    });

    test('한쪽만 목록이면 다른 것으로 본다', () {
      expect(TasksSyncService.sameStoredValue(<String>['가'], '가'), isFalse);
    });
  });
}
