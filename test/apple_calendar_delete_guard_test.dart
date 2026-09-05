import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/apple_calendar_sync_service.dart';

/// 아이폰 캘린더에서 일정이 안 보일 때, 그걸 곧바로 "지웠다"로 받아들이지
/// 않는다.
///
/// 방금 내보낸 이벤트는 캘린더에 자리 잡기 전이라 조회에 안 잡힐 수 있는데,
/// 그걸 삭제로 받아들이면 앱에서 만든 일정이 만든 그날 사라진다. 루틴은 그날
/// 쉬기로 찍히고 일반 일정은 아예 지워진다 — 2026-09-05에 실제로 그렇게
/// 사라졌고, 9월 2일에 만든 루틴은 당했지만 8월에 만든 것은 멀쩡했다.
void main() {
  group('여러 개가 한꺼번에 안 잡히면', () {
    test('조회가 어긋난 것으로 보고 넘어간다', () {
      expect(
        AppleCalendarSyncService.looksLikeLookupGlitch(missing: 3, mapped: 5),
        isTrue,
      );
    });

    test('하나만 안 잡히면 사람이 지운 것으로 본다', () {
      expect(
        AppleCalendarSyncService.looksLikeLookupGlitch(missing: 1, mapped: 5),
        isFalse,
      );
    });

    test('한둘 빠진 정도는 그대로 진행한다', () {
      expect(
        AppleCalendarSyncService.looksLikeLookupGlitch(missing: 2, mapped: 9),
        isFalse,
      );
    });

    test('없어진 게 없으면 아무 일도 없다', () {
      expect(
        AppleCalendarSyncService.looksLikeLookupGlitch(missing: 0, mapped: 4),
        isFalse,
      );
    });
  });

  group('안 보이는 항목을 지운 것으로 받아들일지', () {
    final now = DateTime(2026, 9, 5, 10, 30);

    test('처음 안 보이는 것은 기다린다', () {
      expect(
        AppleCalendarSyncService.shouldApplyDelete(
          firstMissedAtIso: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('방금 안 보이기 시작한 것도 기다린다', () {
      expect(
        AppleCalendarSyncService.shouldApplyDelete(
          firstMissedAtIso: DateTime(2026, 9, 5, 10, 25).toIso8601String(),
          now: now,
        ),
        isFalse,
      );
    });

    test('한참 지나도 안 보이면 받아들인다', () {
      expect(
        AppleCalendarSyncService.shouldApplyDelete(
          firstMissedAtIso: DateTime(2026, 9, 5, 10, 5).toIso8601String(),
          now: now,
        ),
        isTrue,
      );
    });

    test('읽을 수 없는 시각이면 기다린다', () {
      expect(
        AppleCalendarSyncService.shouldApplyDelete(
          firstMissedAtIso: '언젠가',
          now: now,
        ),
        isFalse,
      );
    });
  });
}
