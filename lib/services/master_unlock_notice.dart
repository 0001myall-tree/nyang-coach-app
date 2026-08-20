import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_data.dart';
import 'daily_reset_service.dart';

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
/// 알리는 자리는 냥냥이와의 대화 하나다. 냥냥이가 자기 입으로 말한다.
///
/// 예전에는 코치 선택 화면에서 팝업으로 띄웠다. 결제가 일어나는 자리라 골랐는데,
/// 결제하고 한참 뒤 코치를 고르러 들른 사람에게는 아무 맥락 없이 튀어나왔다.
/// 그전에는 메인 탭과 채팅 화면에서도 불러서, 마스터 코치와 이야기하는 중에
/// "마스터 코치가 열렸어요"가 뜨고 확인을 누르면 그 방에서 밀려나기까지 했다.
///
/// 팝업이 문제였다기보다 말하는 사람이 없던 게 문제였다. 이제 냥냥이가
/// 대화 중에 말해준다. 마스터 코치 방에서는 말하지 않는다 — 이미 만난
/// 사람에게 열렸다고 알릴 일은 없다.
///
/// 어떤 구독을 두고 안내했는지 적어두는 자리.
///
/// 예전에는 "알렸다/안 알렸다" 한 칸이었고, 마스터가 아닌 것으로 읽히면 그 칸을
/// 지웠다. 해지 뒤 다시 결제한 사람에게 한 번 더 알려주려던 것이었는데, 등급이
/// 잠깐 다르게 읽히는 순간마다 표시가 함께 지워졌다. 그래서 같은 안내가 며칠씩
/// 다시 떴다.
///
/// 이제 지우지 않는다. 대신 무엇을 두고 알렸는지를 적어두고, 그것과 다를 때만
/// 다시 알린다. 잘못 읽힌 순간은 아무것도 건드리지 않고 지나간다.
const String _masterUnlockNoticeKey = 'master_unlock_notice_plan';

/// 예전의 "알렸다" 한 칸. 이미 안내를 받은 사람에게 한 번 더 띄우지 않으려고
/// 읽기만 한다.
const String _legacyMasterUnlockNoticeKey = 'master_unlock_notice_shown';

/// 지금 무엇을 해야 하는지.
enum MasterUnlockDecision {
  /// 판단할 때가 아니거나 알릴 것이 없다. 적어둔 것도 건드리지 않는다.
  skip,

  /// 이미 이 구독을 두고 알렸다.
  alreadyShown,

  /// 지금 알린다.
  show,
}

/// 이 구독을 알아보는 이름. 마스터가 아니면 null.
///
/// 만료일까지 넣는다. 해지하고 다시 결제하면 만료일이 달라지므로, 새 구독으로
/// 보고 한 번 더 알려줄 수 있다.
String? masterUnlockSignature({
  required bool isPlanActive,
  required String planType,
  required DateTime? planExpiresAt,
}) {
  if (!isPlanActive || planType != 'master') return null;
  return 'master|${planExpiresAt?.toIso8601String() ?? 'forever'}';
}

/// 판단만 떼어낸 것. 화면도 저장소도 없이 시험할 수 있다.
///
/// [restorePending]이 참이면 아무것도 하지 않는다. 로그인은 되어 있는데 이 기기가
/// 아직 클라우드에서 데이터를 받아오기 전이면, 그때 읽은 등급은 진짜 등급이 아니다.
MasterUnlockDecision decideMasterUnlockNotice({
  required bool restorePending,
  required String? signature,
  required String? announced,
}) {
  if (restorePending) return MasterUnlockDecision.skip;
  if (signature == null) return MasterUnlockDecision.skip;
  if (announced == signature) return MasterUnlockDecision.alreadyShown;
  return MasterUnlockDecision.show;
}

/// 적어두는 키는 'nyang_'으로 시작하지 않는다. 그 접두어를 쓰면 클라우드 복원이
/// 덮어써서 앱을 켤 때마다 같은 안내가 다시 뜬다.
/// 지금 알릴 차례면 참을 돌려주고, 알렸다고 적어둔다.
///
/// 참이 돌아온 뒤 실제로 말하지 못하면 그 안내는 사라진다. 부르는 쪽에서 바로
/// 말할 수 있을 때만 부른다.
Future<bool> claimMasterUnlockNotice() async {
  final data = await UserDataService.load();
  final prefs = await SharedPreferences.getInstance();

  final signature = masterUnlockSignature(
    isPlanActive: data.isPlanActive,
    planType: data.planType,
    planExpiresAt: data.planExpiresAt,
  );
  // 옛 표시가 남아 있으면 그 사람은 이미 받은 것으로 본다.
  final announced =
      prefs.getString(_masterUnlockNoticeKey) ??
      (prefs.getBool(_legacyMasterUnlockNoticeKey) == true ? signature : null);

  final decision = decideMasterUnlockNotice(
    restorePending: DailyResetService.isCloudRestorePending(prefs),
    signature: signature,
    announced: announced,
  );
  if (decision != MasterUnlockDecision.show) return false;

  await prefs.setString(_masterUnlockNoticeKey, signature!);
  return true;
}
