/// 이 기기가 마지막으로 클라우드와 맞췄을 때의 값을 기억하는 자리.
///
/// 예전 동기화는 "나중에 올린 쪽이 이긴다"였다. 값에 언제 적었는지가 없어서
/// 새 것과 옛 것을 못 가렸고, 며칠 꺼져 있던 폰을 켜면 그 폰의 옛 데이터가
/// 통째로 올라가 쓰던 폰의 최근 며칠을 덮었다.
///
/// 그래서 세 값을 견준다. 이 기기 값, 클라우드 값, 그리고 둘이 마지막으로
/// 같았을 때의 값(바탕).
///
/// - 이 기기가 바탕 그대로인데 클라우드가 바뀌었다 → 이 기기가 뒤처졌다. 받는다.
/// - 클라우드가 바탕 그대로인데 이 기기가 바뀌었다 → 이 기기가 고쳤다. 올린다.
/// - 둘 다 바뀌었다 → 클라우드를 따른다. 옛 기기가 최신을 덮는 것을 막는 쪽이다.
///
/// 값 전체를 들고 있지 않고 지문만 적는다. 목록이 커도 자리를 적게 쓴다.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum SyncMove {
  /// 이미 같다. 할 일이 없다.
  same,

  /// 이 기기 값을 올린다.
  push,

  /// 클라우드 값을 받는다.
  takeCloud,

  /// 이 기기에서 지운 것이다. 클라우드에서도 지운다.
  deleteCloud,
}

class SyncBase {
  const SyncBase._();

  /// 'nyang_' 접두어를 쓰지 않는다. 이 기기가 무엇과 맞췄는지는 기기마다
  /// 다른 사실이라, 클라우드로 오르내리면 뜻이 없어진다.
  static const String storeKey = 'sync_base_fingerprints';

  /// 세 값의 지문으로 무엇을 할지 정한다. 없는 값은 null.
  static SyncMove decide({
    required String? local,
    required String? cloud,
    required String? base,
  }) {
    if (local == cloud) return SyncMove.same;
    // 클라우드에 없다. 이 기기에서 새로 생긴 것이다.
    if (cloud == null) return SyncMove.push;
    if (local == null) {
      // 맞춘 적이 있고 클라우드가 그대로인데 이 기기에 없다면, 이 기기에서
      // 지운 것이다. 그 밖에는 다른 기기에서 새로 생긴 것이다.
      return base != null && cloud == base
          ? SyncMove.deleteCloud
          : SyncMove.takeCloud;
    }
    // 맞춘 적이 없다(이 기능 이전부터 쓰던 기기, 새로 깐 기기). 어느 쪽이
    // 새 것인지 모르니 클라우드를 따른다 — 꺼져 있던 폰이 여기 해당한다.
    if (base == null) return SyncMove.takeCloud;
    if (local == base) return SyncMove.takeCloud;
    if (cloud == base) return SyncMove.push;
    // 둘 다 바뀌었다.
    return SyncMove.takeCloud;
  }

  /// 저장된 값의 지문. 목록은 클라우드에 올릴 때처럼 각 항목을 글자로 펴서
  /// 본다 — 이 기기의 문자열 목록과 클라우드에서 내려온 목록이 같은 지문을
  /// 가져야 한다.
  static String? fingerprint(Object? value) {
    if (value == null) return null;
    final String text;
    if (value is List) {
      text = 'L:${value.map((item) => item.toString()).join('\u0001')}';
    } else if (value is String) {
      text = 'S:$value';
    } else {
      text = 'P:$value';
    }
    return '${text.length}:${_fnv(text, 0x811c9dc5)}:${_fnv(text, 0x050c5d1f)}';
  }

  /// FNV-1a 32비트. 두 벌을 씨앗만 달리해 붙이면 우연히 같을 일이 사실상 없다.
  static String _fnv(String text, int seed) {
    var hash = seed;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// 이 계정에서 맞춘 지문들. 계정이 바뀌었으면 비어 있는 것으로 본다.
  static Map<String, String> read(SharedPreferences prefs, String uid) {
    try {
      final raw = prefs.getString(storeKey);
      if (raw == null) return {};
      final decoded = jsonDecode(raw) as Map;
      if (decoded['uid'] != uid) return {};
      return Map<String, String>.from(decoded['keys'] as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> write(
    SharedPreferences prefs,
    String uid,
    Map<String, String> bases,
  ) => prefs.setString(storeKey, jsonEncode({'uid': uid, 'keys': bases}));

  static Future<void> clear(SharedPreferences prefs) => prefs.remove(storeKey);
}
