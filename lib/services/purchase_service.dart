import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/user_data.dart';

enum PlanDuration { monthly, sixMonths }

class PurchasePlan {
  const PurchasePlan({
    required this.planType,
    required this.duration,
    required this.productId,
  });

  final String planType;
  final PlanDuration duration;
  final String productId;

  String get label {
    final planLabel = planType == 'master' ? '마스터 플랜' : '프렌즈 플랜';
    final durationLabel = duration == PlanDuration.monthly ? '월간' : '6개월';
    return '$planLabel $durationLabel';
  }

  DateTime entitlementExpiresAt(DateTime purchasedAt) {
    final days = duration == PlanDuration.monthly ? 31 : 183;
    return purchasedAt.add(Duration(days: days));
  }
}

class PurchaseResult {
  const PurchaseResult._({
    required this.success,
    required this.message,
    this.plan,
  });

  final bool success;
  final String message;
  final PurchasePlan? plan;

  factory PurchaseResult.success(PurchasePlan plan) => PurchaseResult._(
    success: true,
    message: '${plan.label}이 활성화됐어요.',
    plan: plan,
  );

  factory PurchaseResult.failure(String message) =>
      PurchaseResult._(success: false, message: message);
}

class PurchaseService {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  static const friendsMonthlyProductId = 'nyang_friends_monthly';
  static const friendsSixMonthProductId = 'nyang_friends_6month';
  static const masterMonthlyProductId = 'nyang_master_monthly';
  static const masterSixMonthProductId = 'nyang_master_6month';

  static const List<PurchasePlan> plans = [
    PurchasePlan(
      planType: 'friends',
      duration: PlanDuration.monthly,
      productId: friendsMonthlyProductId,
    ),
    PurchasePlan(
      planType: 'friends',
      duration: PlanDuration.sixMonths,
      productId: friendsSixMonthProductId,
    ),
    PurchasePlan(
      planType: 'master',
      duration: PlanDuration.monthly,
      productId: masterMonthlyProductId,
    ),
    PurchasePlan(
      planType: 'master',
      duration: PlanDuration.sixMonths,
      productId: masterSixMonthProductId,
    ),
  ];

  static final Set<String> productIds = plans
      .map((plan) => plan.productId)
      .toSet();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Map<String, Completer<PurchaseResult>> _pendingPurchases = {};
  Map<String, ProductDetails> _products = {};
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Purchase stream error: $error');
      },
    );
  }

  Future<bool> isAvailable() async {
    await start();
    return _iap.isAvailable();
  }

  Future<Map<String, ProductDetails>> loadProducts() async {
    await start();
    final available = await _iap.isAvailable();
    if (!available) return {};

    final response = await _iap.queryProductDetails(productIds);
    if (response.error != null) {
      debugPrint('Product query error: ${response.error}');
    }
    _products = {
      for (final product in response.productDetails) product.id: product,
    };
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Missing store products: ${response.notFoundIDs.join(', ')}');
    }
    return _products;
  }

  PurchasePlan? planForSelection(String planType, bool isSixMonth) {
    final duration = isSixMonth ? PlanDuration.sixMonths : PlanDuration.monthly;
    for (final plan in plans) {
      if (plan.planType == planType && plan.duration == duration) return plan;
    }
    return null;
  }

  ProductDetails? productFor(PurchasePlan plan) => _products[plan.productId];

  Future<PurchaseResult> purchase(PurchasePlan plan) async {
    await start();
    final available = await _iap.isAvailable();
    if (!available) {
      return PurchaseResult.failure('스토어 결제를 사용할 수 없는 상태예요.');
    }

    final products = _products.isEmpty ? await loadProducts() : _products;
    final product = products[plan.productId];
    if (product == null) {
      return PurchaseResult.failure(
        '스토어 상품을 찾지 못했어요. App Store Connect와 Play Console에 ${plan.productId} 상품을 먼저 만들어주세요.',
      );
    }

    final completer = Completer<PurchaseResult>();
    _pendingPurchases[plan.productId] = completer;
    final started = await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
    if (!started) {
      _pendingPurchases.remove(plan.productId);
      return PurchaseResult.failure('결제를 시작하지 못했어요. 잠시 후 다시 시도해주세요.');
    }

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _pendingPurchases.remove(plan.productId);
        return PurchaseResult.failure(
          '결제 확인 시간이 길어지고 있어요. 잠시 후 복원을 눌러 확인해주세요.',
        );
      },
    );
  }

  Future<void> restorePurchases() async {
    await start();
    await _iap.restorePurchases();
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
    _purchaseSubscription = null;
    _started = false;
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetails,
  ) async {
    for (final purchase in purchaseDetails) {
      final plan = _planForProductId(purchase.productID);
      if (plan == null) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grantPlan(plan, purchase);
          _completePending(plan.productId, PurchaseResult.success(plan));
          break;
        case PurchaseStatus.error:
          _completePending(
            plan.productId,
            PurchaseResult.failure(
              purchase.error?.message ?? '결제 중 오류가 발생했어요.',
            ),
          );
          break;
        case PurchaseStatus.canceled:
          _completePending(
            plan.productId,
            PurchaseResult.failure('결제가 취소됐어요.'),
          );
          break;
        case PurchaseStatus.pending:
          break;
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _grantPlan(PurchasePlan plan, PurchaseDetails purchase) async {
    // TODO: Move entitlement writes behind a Cloud Function after adding
    // App Store Server API / Google Play Developer API receipt validation.
    await UserDataService.setPlan(
      plan.planType,
      expiresAt: plan.entitlementExpiresAt(
        purchase.transactionDate == null
            ? DateTime.now()
            : DateTime.fromMillisecondsSinceEpoch(
                int.tryParse(purchase.transactionDate!) ??
                    DateTime.now().millisecondsSinceEpoch,
              ),
      ),
    );
  }

  PurchasePlan? _planForProductId(String productId) {
    for (final plan in plans) {
      if (plan.productId == productId) return plan;
    }
    return null;
  }

  void _completePending(String productId, PurchaseResult result) {
    final completer = _pendingPurchases.remove(productId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }
}
