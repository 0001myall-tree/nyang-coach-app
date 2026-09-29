/// 앱을 안 열어도 자정 뒤에 하루 목록을 정리하는 자리. 안드로이드 전용.
///
/// 적극 코칭은 그날 목록을 보고 하루치 차례를 잡는다. 그런데 하루 정리는
/// 앱을 열어야만 돌아서, 다음 날 앱을 안 연 사람은 어제 목록을 든 채로
/// 부를 일이 없어 하루 종일 조용했다. 그래서 적극 코칭을 켜둔 사람에게만
/// 자정 5분 뒤 알람을 걸어, 앱을 켤 때와 같은 순서로 정리를 돌린다.
///
/// 네이티브가 두 길로 부른다.
///
/// - **앱이 떠 있으면**(뒤에 숨어 있어도) 그 앱에게 맡긴다. 목록을 고치는
///   쪽이 둘이면 서로 덮어쓴다.
/// - **꺼져 있으면** 화면 없이 앱을 잠깐 띄워 이것만 돌리고 닫는다.
///
/// 소리도 화면도 없다. 새로 잡힌 차례는 원래 규칙대로 6시 전엔 안 나간다.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/user_data.dart';
import 'active_coaching_sync.dart';
import 'daily_reset_service.dart';
import 'gap_coaching_service.dart';
import 'task_completion_service.dart';
import 'tasks_sync_service.dart';
import 'widget_sync_service.dart';

class BackgroundDailyReset {
  const BackgroundDailyReset._();

  static const MethodChannel _channel = MethodChannel(
    'nyang_coach/daily_reset',
  );

  static bool _running = false;

  /// 앱이 떠 있을 때 네이티브가 이쪽에 정리를 맡기는 길을 연다.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'run') throw MissingPluginException();
      await run();
      return null;
    });
  }

  /// 화면 없이 띄운 앱에서 다 끝났다고 알린다. 네이티브가 그 앱을 닫는다.
  static Future<void> reportDone() async {
    try {
      await _channel.invokeMethod('done');
    } on PlatformException {
      //
    } on MissingPluginException {
      //
    }
  }

  static Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      // 로그인은 앱이 뜬 뒤 조금 있다 돌아온다. 기다리지 않으면 로그인 안 한
      // 사람으로 보고 클라우드를 건너뛴다.
      await DailyResetService.resolvedUser();

      final data = await UserDataService.load();
      final master = data.isPlanActive && data.planType == 'master';
      if (!master || !await GapCoachingService.isEnabled()) {
        // 그사이 꺼졌다. 알람도 같이 지운다.
        await ActiveCoachingSync.sync();
        return;
      }

      // 앱을 켤 때와 같은 순서다. 한 단계가 실패해도 뒤는 돈다 — 클라우드가
      // 안 닿는 밤이어도 이 기기 목록은 정리돼야 한다.
      await _step('클라우드 받기', TasksSyncService.syncFromCloudWithRetry);
      // 어제 대화 요약은 뺀다. 인터넷 호출이라 길어지면 화면 없는 앱이 시간
      // 제한에 걸려 닫힌다. 빠진 요약은 앱을 열 때 채워진다.
      await _step(
        '하루 정리',
        () => DailyResetService.checkAndExecuteResetAfterRestore(
          summarize: false,
        ),
      );
      await _step('루틴 맞추기', DailyResetService.syncTodayHabitTasks);
      // 떠 있던 앱의 화면이 옛 목록을 들고 있다가 저장하면 방금 정리가
      // 되돌아간다. 바뀌었다고 적어두면 돌아왔을 때 다시 읽는다.
      await _step('변경 표시', TaskCompletionService.markChangedNow);
      await _step('클라우드 올리기', TasksSyncService.syncToCloud);
      await _step('적극 코칭 예약', ActiveCoachingSync.sync);
      await _step('위젯', WidgetSyncService.syncFromStoredTasks);
    } finally {
      _running = false;
    }
  }

  static Future<void> _step(String name, Future<Object?> Function() job) async {
    try {
      await job();
    } catch (e, stackTrace) {
      debugPrint('[BackgroundDailyReset] $name 실패: $e');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
