import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 무엇을 파는지 — 상품 이름, 가격, 기간 — 를 담은 목록.
///
/// 이 값들이 앱 안에 박혀 있으면 6개월권을 4개월권으로 바꾸는 것 같은 일에도
/// 앱을 새로 올리고 심사를 받아야 한다. 그래서 콘솔에서 고칠 수 있는 문서
/// 하나(config/plans)에서 읽고, 못 읽으면 아래 기본값으로 돈다.
///
/// 문서 모양. 콘솔에서 넣기 쉽도록 `json`이라는 글자 칸 하나에 아래 전체를
/// 붙여넣으면 된다 (칸을 나눠 넣어도 읽는다):
/// ```
/// {
///   "long_term_label": "6개월",
///   "plans": [
///     { "plan_type": "friends", "term": "monthly", "product_id": "...",
///       "entitlement_days": 31, "price": "5,900원 / 월" },
///     { "plan_type": "friends", "term": "long", "product_id": "...",
///       "entitlement_days": 183, "price": "29,400원",
///       "original_price": "35,400원", "sub_price": "월 4,900원" }
///   ]
/// }
/// ```
///
/// 가격은 여기 적힌 글자를 그대로 보여준다. Play Console에 등록한 금액과
/// 반드시 같아야 한다 — 다르면 사용자가 본 값과 결제창 값이 어긋난다.
class PurchasePlan {
  const PurchasePlan({
    required this.planType,
    required this.isLongTerm,
    required this.productId,
    required this.entitlementDays,
    required this.termLabel,
    required this.price,
    this.originalPrice,
    this.subPrice,
  });

  /// 'friends' 또는 'master'
  final String planType;

  /// 기간 토글의 오른쪽(장기권)인지. 왼쪽은 월간이다.
  final bool isLongTerm;

  final String productId;

  /// 결제 후 플랜을 며칠 열어둘지.
  final int entitlementDays;

  /// '월간', '6개월', '4개월'처럼 화면에 쓰는 기간 이름.
  final String termLabel;

  final String price;
  final String? originalPrice;
  final String? subPrice;

  String get label {
    final planLabel = planType == 'master' ? '마스터 플랜' : '프렌즈 플랜';
    return '$planLabel $termLabel';
  }

  DateTime entitlementExpiresAt(DateTime purchasedAt) =>
      purchasedAt.add(Duration(days: entitlementDays));

  factory PurchasePlan.fromMap(Map<String, dynamic> map, String termLabel) {
    return PurchasePlan(
      planType: map['plan_type']?.toString() ?? 'friends',
      isLongTerm: map['term']?.toString() == 'long',
      productId: map['product_id']?.toString() ?? '',
      entitlementDays: _readInt(map['entitlement_days']) ?? 31,
      termLabel: termLabel,
      price: map['price']?.toString() ?? '',
      originalPrice: map['original_price']?.toString(),
      subPrice: map['sub_price']?.toString(),
    );
  }

  static int? _readInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }
}

class PlanCatalog {
  PlanCatalog._();

  static final instance = PlanCatalog._();

  static const String configDocPath = 'config/plans';

  /// 서버를 못 읽을 때 쓰는 값. 지금 Play Console에 올라가 있는 그대로다.
  static const String defaultLongTermLabel = '6개월';

  static const List<PurchasePlan> defaultPlans = [
    PurchasePlan(
      planType: 'friends',
      isLongTerm: false,
      productId: 'nyang_friends_monthly',
      entitlementDays: 31,
      termLabel: '월간',
      price: '5,900원 / 월',
    ),
    PurchasePlan(
      planType: 'friends',
      isLongTerm: true,
      productId: 'nyang_friends_6month',
      entitlementDays: 183,
      termLabel: defaultLongTermLabel,
      price: '29,400원',
      originalPrice: '35,400원',
      subPrice: '월 4,900원',
    ),
    PurchasePlan(
      planType: 'master',
      isLongTerm: false,
      productId: 'nyang_master_monthly',
      entitlementDays: 31,
      termLabel: '월간',
      price: '8,900원 / 월',
    ),
    PurchasePlan(
      planType: 'master',
      isLongTerm: true,
      productId: 'nyang_master_6month',
      entitlementDays: 183,
      termLabel: defaultLongTermLabel,
      price: '47,400원',
      originalPrice: '53,400원',
      subPrice: '월 7,900원',
    ),
  ];

  List<PurchasePlan> _plans = defaultPlans;
  String _longTermLabel = defaultLongTermLabel;
  DateTime? _readAt;

  List<PurchasePlan> get plans => _plans;

  /// 기간 토글 오른쪽에 쓸 이름. '6개월 구독' 같은 식으로 붙여 쓴다.
  String get longTermLabel => _longTermLabel;

  Set<String> get productIds =>
      _plans.map((plan) => plan.productId).where((id) => id.isNotEmpty).toSet();

  PurchasePlan? planFor(String planType, {required bool isLongTerm}) {
    for (final plan in _plans) {
      if (plan.planType == planType && plan.isLongTerm == isLongTerm) {
        return plan;
      }
    }
    return null;
  }

  PurchasePlan? planForProductId(String productId) {
    for (final plan in _plans) {
      if (plan.productId == productId) return plan;
    }
    return null;
  }

  /// 콘솔에서 배열 안에 지도를 네 번 넣는 건 클릭이 서른 번쯤 든다. 그래서
  /// `json`이라는 글자 칸 하나에 전체를 붙여넣는 길도 열어둔다. 둘 다 있으면
  /// 붙여넣은 쪽을 쓴다.
  Map<String, dynamic>? _readConfig(Map<String, dynamic>? data) {
    if (data == null) return null;

    final raw = data['json'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        debugPrint('Plan catalog json is not an object');
        return null;
      } catch (e) {
        // 붙여넣다 만 글자로 갈아타면 아무것도 못 판다. 그냥 두는 게 낫다.
        debugPrint('Plan catalog json parse failed: $e');
        return null;
      }
    }

    return data;
  }

  /// 한 시간에 한 번만 다시 읽는다. 목록을 바꿔도 앱이 켜져 있는 동안에는
  /// 최대 한 시간까지 옛 값이 보일 수 있다.
  Future<void> load({bool force = false}) async {
    final readAt = _readAt;
    if (!force &&
        readAt != null &&
        DateTime.now().difference(readAt) < const Duration(hours: 1)) {
      return;
    }

    try {
      final parts = configDocPath.split('/');
      final doc = await FirebaseFirestore.instance
          .collection(parts.first)
          .doc(parts.last)
          .get();
      final data = _readConfig(doc.data());
      if (data == null) return;

      final label = data['long_term_label']?.toString();
      final rawPlans = data['plans'];
      if (rawPlans is! List || rawPlans.isEmpty) return;

      final parsed = <PurchasePlan>[];
      for (final entry in rawPlans) {
        if (entry is! Map) continue;
        final map = Map<String, dynamic>.from(entry);
        final isLongTerm = map['term']?.toString() == 'long';
        parsed.add(
          PurchasePlan.fromMap(
            map,
            isLongTerm ? (label ?? defaultLongTermLabel) : '월간',
          ),
        );
      }

      // 상품 이름이 빠진 목록으로 갈아타면 아무것도 못 산다. 그럴 바엔 둔다.
      if (parsed.any((plan) => plan.productId.isEmpty)) {
        debugPrint('Plan catalog ignored: a plan has no product id');
        return;
      }
      if (parsed.isEmpty) return;

      _plans = parsed;
      if (label != null && label.isNotEmpty) _longTermLabel = label;
      _readAt = DateTime.now();
    } catch (e) {
      debugPrint('Plan catalog read failed: $e');
      // 다음에 다시 시도한다. 그동안은 기본값으로 판다.
    }
  }
}
