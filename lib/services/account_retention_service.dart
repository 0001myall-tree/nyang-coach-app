import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 로그인 기준 사용자 데이터 보존 기한을 Firestore에 남긴다.
///
/// 실제 삭제는 서버 배치나 콘솔 작업이 맡고, 앱은 폐기 판단에 필요한
/// 마지막 로그인 시각만 갱신한다.
///
/// **폐기 시각은 저장하지 않는다.** 예전에는 `retentionDeleteAfterAt`에 기기
/// 시계로 잰 "로그인 + 3년"을 적어뒀는데, 기기가 자기 시계가 맞는지 스스로 알
/// 수 없어서 어긋난 기기는 어긋난 값을 그대로 박았다. 실제로 시계가 3주 앞선
/// 기기들이 들어와, 서버가 찍은 `lastLoginAt`과 3주가 벌어진 문서가 쌓였다.
///
/// 어차피 `lastLoginAt`에서 [retentionDeleteAfter]로 계산해 나오는 값이라,
/// 복사본을 두는 것은 **틀릴 자리를 하나 더 만드는 일**일 뿐이었다. 지우는
/// 쪽에서 서버가 찍은 시각을 보고 그때 재면 된다.
class AccountRetentionService {
  AccountRetentionService._();

  static final instance = AccountRetentionService._();

  static const retentionYears = 3;

  /// 예전에 기기 시계로 적어두던 칸. 남아 있으면 배치가 틀린 시각을 보고
  /// 지울 수 있어서, 로그인할 때마다 걷어낸다.
  static const _staleDeleteAfterField = 'retentionDeleteAfterAt';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> markLoggedIn(User user) async {
    try {
      await _db.collection('users').doc(user.uid).set({
        'email': user.email,
        'loginEmail': user.email,
        'lastLoginAt': FieldValue.serverTimestamp(),
        _staleDeleteAfterField: FieldValue.delete(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Account retention update failed: $e');
    }
  }

  /// 마지막 로그인이 [loginAt]일 때 언제부터 지워도 되는지.
  ///
  /// 지우는 쪽에서 **서버가 찍은** `lastLoginAt`을 넣어 쓴다. 기기에서 잰
  /// 시각을 넣으면 예전과 같은 문제가 되돌아온다.
  static DateTime retentionDeleteAfter(DateTime loginAt) {
    final utc = loginAt.toUtc();
    return DateTime.utc(
      utc.year + retentionYears,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
      utc.microsecond,
    );
  }
}
