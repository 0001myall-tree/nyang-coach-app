import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/notification_service.dart';

/// 모닝콜과 일정 알람이 함께 쓰는 권한 안내.
/// 두 알람 모두 같은 시스템 권한(알림·정확한 알람·전체화면)에 걸리기 때문에
/// 안내 문구만 알람 이름으로 바꿔서 같은 모양을 보여준다.

/// 알람 설정 결과 안내.
/// 설정 서랍(모달 바텀시트)이 열린 상태에서 뜨기 때문에 스낵바는 서랍에 가려 보이지 않는다.
/// 게다가 권한 안내는 시스템 설정 화면을 함께 열어서, 자동으로 사라지는 스낵바로는
/// 안내를 놓치게 된다. 그래서 사용자가 직접 닫아야 하는 팝업으로 띄운다.
Future<void> showAlarmNoticeDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
  String closeLabel = '확인',
}) {
  return showDialog<void>(
    context: context,
    // 권한 안내는 그냥 닫고 지나치기 쉬우므로 바깥을 눌러서는 닫히지 않게 한다.
    barrierDismissible: actionLabel == null,
    builder: (ctx) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: const Color(0xFF3D3A4E),
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.notoSansKr(
            fontSize: 13.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B6676),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              closeLabel,
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900,
                color: actionLabel == null
                    ? const Color(0xFF8B7CFF)
                    : const Color(0xFF9B96A8),
              ),
            ),
          ),
          if (actionLabel != null)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                onAction?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B7CFF),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                actionLabel,
                style: GoogleFonts.notoSansKr(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// 일정을 저장하다 곁다리로 걸리는 자리(일정 알람 자동 등록 등)에서 권한
/// 안내를 다시 띄워도 되는지.
///
/// 설정 화면에서 사용자가 직접 스위치를 켰을 때는 늘 바로 알려줘야 하지만,
/// 여기서는 한 번 보여줬으면 충분하다. 안 고친 사람이 시간 있는 일정을
/// 저장할 때마다 같은 팝업을 또 보게 하면 그 자체가 잔소리가 된다. 그 뒤로도
/// 안 고친 사람에게는 설정 화면의 배너([buildAlarmPermissionBanner])가 계속
/// 남아 있으니, 새 일정을 저장할 때마다 또 튀어나올 필요가 없다.
///
/// [noticeKey]로 어느 안내인지 가른다 — 알림 권한을 고쳤는데 정확한 알람은
/// 아직이면 그건 다른 문제라 다시 알려줄 만하고, "다른 앱 위에 표시"처럼
/// 아예 다른 권한을 묻는 안내와도 서로 섞이면 안 된다.
Future<bool> shouldAutoShowAlarmPermissionNotice(String noticeKey) async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'auto_alarm_notice_shown_$noticeKey';
  if (prefs.getBool(key) == true) return false;
  await prefs.setBool(key, true);
  return true;
}

/// 권한이 없을 때의 안내 팝업. 사용자가 직접 시스템 설정으로 갈 수 있게
/// 버튼을 함께 띄운다. 자동으로 설정 화면을 열어버리면 무슨 이유로 넘어왔는지
/// 모른 채 뒤로가기를 눌러버리기 때문에, 설명을 먼저 읽히고 나서 보낸다.
///
/// [alarmLabel]은 '모닝콜', '일정 알람'처럼 사용자가 켠 알람의 이름.
/// [emoji]는 제목 앞에 붙는다.
Future<void> showAlarmPermissionDialog(
  BuildContext context,
  AlarmPermissionIssue issue, {
  required String alarmLabel,
  String emoji = '⏰',
}) async {
  if (issue == AlarmPermissionIssue.none) return;
  final isBlocking = issue == AlarmPermissionIssue.notifications;
  await showAlarmNoticeDialog(
    context,
    title: isBlocking
        ? '$emoji 지금은 $alarmLabel이 울리지 않아요'
        : '$emoji $alarmLabel이 조용히 울릴 수 있어요',
    message: switch (issue) {
      AlarmPermissionIssue.notifications =>
        '냥냥코치 알림이 꺼져 있어요. 알림을 켜지 않으면 $alarmLabel 시간이 되어도 소리가 나지 않고, '
            '나중에 앱을 열었을 때에야 뒤늦게 울려요.\n\n'
            '설정에서 냥냥코치 알림을 켜주세요.',
      AlarmPermissionIssue.exactAlarm =>
        '알람을 정확한 시간에 울릴 수 있는 권한이 꺼져 있어요. '
            '이대로 두면 $alarmLabel이 설정한 시간보다 늦게 울릴 수 있어요.\n\n'
            '설정에서 "알람 및 리마인더"를 허용해주세요.',
      AlarmPermissionIssue.fullScreen =>
        '잠금화면을 덮는 알람 화면 권한이 꺼져 있어요. '
            '소리는 나지만 화면이 켜지지 않아 알람을 놓치기 쉬워요.\n\n'
            '설정에서 전체화면 알림을 허용해주세요.',
      AlarmPermissionIssue.none => '',
    },
    actionLabel: '설정 열기',
    closeLabel: isBlocking ? '나중에' : '괜찮아요',
    onAction: () async {
      await NotificationService().openAlarmPermissionSettings(issue);
    },
  );
}

/// 알람이 울리지 않는 상태를 설정 화면에 계속 띄워두는 배너.
/// 스위치만 켜져 있으면 사용자는 정상이라고 믿게 되므로, 켜진 동안 계속 보이게 한다.
Widget buildAlarmPermissionBanner({
  required AlarmPermissionIssue issue,
  required String alarmLabel,
  required VoidCallback onTap,
}) {
  if (issue == AlarmPermissionIssue.none) {
    return const SizedBox.shrink();
  }
  final isBlocking = issue == AlarmPermissionIssue.notifications;
  final accent = isBlocking ? const Color(0xFFD64545) : const Color(0xFFCE8A2E);
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isBlocking ? const Color(0xFFFDECEC) : const Color(0xFFFDF4E4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isBlocking ? Icons.notifications_off : Icons.warning_amber_rounded,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBlocking
                      ? '지금은 $alarmLabel이 울리지 않아요'
                      : '$alarmLabel 화면이 안 뜰 수 있어요',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isBlocking
                      ? '냥냥코치 알림이 꺼져 있어요. 눌러서 켜주세요.'
                      : '알람 권한이 일부 꺼져 있어요. 눌러서 확인해주세요.',
                  style: GoogleFonts.notoSansKr(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF6B6676),
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, size: 18, color: accent),
        ],
      ),
    ),
  );
}
