import 'package:flutter_test/flutter_test.dart';
import 'package:nyang_coach/services/apple_calendar_sync_service.dart';

/// 아이폰 캘린더로는 내보내기만 한다.
///
/// 한동안은 양방향이었다. 캘린더에서 이벤트가 조회에 안 잡히면 "사용자가
/// 지웠다"로 읽고, 루틴이면 그날을 쉬기로 찍고 일정이면 아예 지웠다. 그런데
/// 안 잡히는 이유는 사람이 지운 것 말고도 많다 — 아이클라우드가 이벤트를 다시
/// 만들거나, 들고 있던 이벤트 번호표가 옛것이거나. 그렇게 찍힌 쉬기는 화면에
/// 보이지도 되돌려지지도 않아서, 쉰다고 한 적 없는 날에 루틴이 사라졌다.
///
/// 애초에 캘린더에서 냥냥코치 일정을 고치는 것은 계획에 없던 쓰임이었다.
/// 지우기 감지는 통째로 걷어냈고(그 판단을 하던 `looksLikeLookupGlitch`,
/// `shouldApplyDelete`도 같이 사라졌다), 캘린더에서 지운 것은 다음 내보내기가
/// 다시 만든다. 시간을 옮기는 것만 앱으로 돌아온다.
void main() {
  test('이벤트 번호표는 클라우드로 오르내리지 않는다', () {
    // 번호표 속 id는 이 아이폰의 EventKit이 발급한 값이라 다른 기기에서는
    // 뜻이 없다. 'nyang_' 접두어가 붙은 값은 전부 클라우드를 타기 때문에,
    // 옛 표가 내려와 이미 없는 이벤트를 찾게 만들던 자리다.
    expect(AppleCalendarSyncService.eventMapKey.startsWith('nyang_'), isFalse);
  });
}
