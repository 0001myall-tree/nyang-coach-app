import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 기기 시계 대신 서버가 말하는 지금.
///
/// 구독 만료와 무료 체험을 기기 시계로 재고 있었다. 기기 날짜를 뒤로 돌리면
/// 끝난 구독이 되살아나고, 앞으로 돌리면 체험 시작일이 미래로 박혀 남은 날이
/// 줄지 않는다. 설정 화면만 열면 되는 일이라 문턱이랄 것도 없었다.
///
/// **기기는 자기 시계가 맞는지 스스로 알 수 없다.** 안에 있는 시계가 모두 같은
/// 값을 말하니 견줄 것이 없어서다. 그래서 밖에서 한 번 받아온다.
///
/// 받아오는 것은 시각이 아니라 **차이**다. 기기가 5분 빠르면 그 차이는 그대로
/// 있으므로, 한 번 구해두면 그다음부터는 더하기만 하면 된다. 대화할 때마다
/// 서버에 묻지 않아도 되고, 따라서 느려지는 자리도 없다.
class ServerClock {
  ServerClock._();

  /// 서버 시각 - 기기 시각. 아직 못 받았으면 null.
  static Duration? _offset;

  /// 마지막으로 맞춘 때(기기 기준). 너무 오래된 값은 다시 맞춘다.
  static DateTime? _syncedAt;

  /// 한 번 맞추면 이만큼은 그대로 쓴다.
  static const Duration _freshFor = Duration(hours: 6);

  /// 서버에 물어본 적이 있는지.
  static bool get isSynced => _offset != null;

  /// 맞춰둔 값이 아직 쓸 만한지.
  static bool get isFresh {
    final at = _syncedAt;
    if (_offset == null || at == null) return false;
    return DateTime.now().difference(at).abs() < _freshFor;
  }

  /// 진짜 지금.
  ///
  /// 아직 못 받았으면 기기 시각을 그대로 돌려준다. 화면에 남은 날을 적는 것
  /// 같은 자리는 이걸로 충분하다. **돈이 나가는 자리에서는 [ensureSynced]를
  /// 먼저 불러** 받아온 값인지 확인하고 써야 한다.
  static DateTime now() => DateTime.now().add(_offset ?? Duration.zero);

  /// 서버 시각을 받아온다. 이미 받아둔 것이 싱싱하면 그대로 쓴다.
  ///
  /// 받아왔으면 참. 인터넷이 없거나 로그인 전이면 거짓이다.
  static Future<bool> ensureSynced({bool force = false}) async {
    if (!force && isFresh) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // 자기 문서 아래라 규칙에 걸리지 않고, 이름에 날짜가 없어 기기 시계가
    // 끼어들 자리도 없다.
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('meta')
        .doc('clock');

    try {
      await ref.set({
        'probedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 캐시를 읽으면 방금 쓴 값이 아직 비어 있거나 기기가 어림잡은 값이라,
      // 서버에서 직접 받아야 한다.
      final snapshot = await ref.get(const GetOptions(source: Source.server));
      final probedAt = snapshot.data()?['probedAt'];
      if (probedAt is! Timestamp) return false;

      _offset = probedAt.toDate().difference(DateTime.now());
      _syncedAt = DateTime.now();
      return true;
    } catch (e) {
      debugPrint('Server clock sync failed: $e');
      return false;
    }
  }

  /// 테스트에서 쓴다.
  @visibleForTesting
  static void setOffsetForTest(Duration? offset) {
    _offset = offset;
    _syncedAt = offset == null ? null : DateTime.now();
  }
}
