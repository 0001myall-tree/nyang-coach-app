import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
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
/// 뜨는 자리는 코치 선택 화면 하나다.
///
/// 한동안 메인 탭과 채팅 화면에서도 불렀다. 그러다 마스터 코치와 이야기하는
/// 중에 "마스터 코치가 열렸어요"가 튀어나오고, 확인을 누르면 그 방에서
/// 밀려나는 일이 생겼다. 안내가 하려던 일이 그대로 방해가 된 것이다.
///
/// 결제가 실제로 일어나는 자리도 여기다. 채팅 화면의 구독 시트는 디버그
/// 빌드에서만 열려서, 실기기에서는 그 경로로 결제가 되지 않는다.
const String _masterUnlockNoticeKey = 'master_unlock_notice_shown';

/// 플래그는 'nyang_'으로 시작하지 않는 키에 둔다. 그 접두어를 쓰면 클라우드
/// 복원이 덮어써서 앱을 켤 때마다 같은 안내가 다시 뜬다.
Future<void> maybeShowMasterUnlockNotice(BuildContext context) async {
  final data = await UserDataService.load();
  final prefs = await SharedPreferences.getInstance();

  // 마스터가 아닌 동안에는 표시를 지워둔다. 해지했다가 다시 결제했을 때도
  // 열렸다는 안내를 한 번 더 받는다.
  if (!data.isPlanActive || data.planType != 'master') {
    await prefs.remove(_masterUnlockNoticeKey);
    return;
  }

  if (prefs.getBool(_masterUnlockNoticeKey) == true) return;
  await prefs.setBool(_masterUnlockNoticeKey, true);

  if (!context.mounted) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    _showMasterUnlockDialog(context);
  });
}

void _showMasterUnlockDialog(BuildContext context) {
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
          // 이 화면이 이미 코치 선택 화면이고, 마스터 탭이 왼쪽에서 열려 있다.
          // 보내줄 곳이 없으니 닫는 버튼 하나면 된다.
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppDesignTokens.brand,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              '좋아요',
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
