import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import '../screens/coach_selection_screen.dart';
import '../services/coach_id_service.dart';
import '../theme/app_design_tokens.dart';

/// 마스터 코치가 열렸다는 걸 한 번만 알려준다.
///
/// 등급을 올리고도 버릇대로 냥냥 코치만 쓰는 경우가 많았다. 열렸다는 사실을
/// 모르고 지나가는 것이다.
///
/// 결제 순간을 잡으려 하지 않는다. 결제 경로가 여럿이고 앱을 껐다 켜는 사이에
/// 반영되기도 해서, 그 한 지점만 노리면 새는 길이 생긴다. 대신 "지금 마스터인데
/// 아직 안 알렸는가"만 보고, 그 확인을 여러 자리에서 부른다. 한 번만 뜨게
/// 막아주는 플래그가 있으니 부르는 자리가 늘어도 두 번 뜨지 않는다.
///
/// 원래 메인 탭 화면 안에만 있었다. 그런데 결제는 그 화면 위에 뜬 시트에서
/// 일어나서, 결제를 마쳐도 화면이 새로 만들어지지 않아 안내가 안 떴다. 마스터
/// 코치를 눌러 코치 선택 화면에 다녀와야 그제야 떴는데, 그건 이 안내가 하려던
/// 일을 사용자가 이미 해버린 뒤다.
const String _masterUnlockNoticeKey = 'master_unlock_notice_shown';

/// 플래그는 'nyang_'으로 시작하지 않는 키에 둔다. 그 접두어를 쓰면 클라우드
/// 복원이 덮어써서 앱을 켤 때마다 같은 안내가 다시 뜬다.
Future<void> maybeShowMasterUnlockNotice(
  BuildContext context, {
  required String returnCoachId,
}) async {
  final data = await UserDataService.load();
  final prefs = await SharedPreferences.getInstance();

  // 마스터가 아닌 동안에는 표시를 지워둔다. 해지했다가 다시 결제했을 때도
  // 열렸다는 안내를 한 번 더 받는다.
  if (!data.isPlanActive || data.planType != 'master') {
    await prefs.remove(_masterUnlockNoticeKey);
    return;
  }

  // 이미 마스터 코치와 있는 사람에게는 알릴 것이 없다.
  //
  // 열렸다는 걸 알고 들어온 사람인데, 여기서 띄우면 대화를 끊는다. 게다가
  // 버튼이 코치 선택 화면으로 보내는 것이라, 누르면 방금까지 이야기하던
  // 방에서 밀려난다. 안내가 하려던 일이 그대로 방해가 된다.
  //
  // 본 것으로 표시해두고 넘어간다. 이 사람에게는 나중에 띄워도 마찬가지다.
  if (CoachIdService.isMaster(returnCoachId)) {
    await prefs.setBool(_masterUnlockNoticeKey, true);
    return;
  }

  if (prefs.getBool(_masterUnlockNoticeKey) == true) return;
  await prefs.setBool(_masterUnlockNoticeKey, true);

  if (!context.mounted) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    _showMasterUnlockDialog(context, returnCoachId: returnCoachId);
  });
}

void _showMasterUnlockDialog(
  BuildContext context, {
  required String returnCoachId,
}) {
  showDialog<void>(
    context: context,
    // 그냥 닫고 지나치면 이 안내가 하는 일이 없다. 버튼을 누르게 한다.
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.radiusLarge),
        ),
        title: Text(
          '마스터 코치가 열렸어요',
          style: GoogleFonts.notoSansKr(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppDesignTokens.textPrimary,
          ),
        ),
        content: Text(
          '이제 냥할배와 비서 실장을 만날 수 있어요.\n'
          '목표와 하루의 흐름을 함께 보면서, 지금 무엇부터 하면 좋을지 챙겨드립니다.',
          style: GoogleFonts.notoSansKr(
            fontSize: 13.5,
            height: 1.5,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF6B6676),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              '나중에',
              style: GoogleFonts.notoSansKr(
                fontWeight: FontWeight.w900,
                color: const Color(0xFF9B96A8),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CoachSelectionScreen(returnCoachId: returnCoachId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.brand,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '코치 보러 가기',
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
