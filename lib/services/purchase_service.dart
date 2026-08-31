import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../models/user_data.dart';
import 'plan_catalog.dart';

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

  /// 구독 안내 시트로 들어가는 입구를 여는지.
  ///
  /// 지금은 닫아둔다. 결제가 성공해도 플랜을 켜주는 쪽(영수증을 확인하고
  /// plan_type을 써주는 서버)이 아직 없어서, 열면 돈만 나가고 아무 일도
  /// 일어나지 않는다. 그 서버가 붙는 날 이 값을 true로 바꾸고,
  /// Play Console에서 구독 상품 4개를 활성으로 돌리면 된다.
  static const bool storeCheckoutEnabled = false;

  /// 코치 한 명만 따로 사는 길. 스토어에 대응하는 상품이 아직 없어서 닫아둔다.
  /// (여는 순간 결제 없이 코치가 지급된다)
  static const bool singleCoachPurchaseEnabled = false;

  /// 무엇을 파는지는 [PlanCatalog]가 안다. 콘솔에서 바꿀 수 있어야 해서
  /// 이 파일에 적어두지 않는다.
  PlanCatalog get catalog => PlanCatalog.instance;

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

    await catalog.load();
    final response = await _iap.queryProductDetails(catalog.productIds);
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

  PurchasePlan? planForSelection(String planType, bool isLongTerm) =>
      catalog.planFor(planType, isLongTerm: isLongTerm);

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
    final candidateExpiry = plan.entitlementExpiresAt(
      purchase.transactionDate == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(
              int.tryParse(purchase.transactionDate!) ??
                  DateTime.now().millisecondsSinceEpoch,
            ),
    );

    // 구매 스트림은 같은 구독을 앱을 열 때마다 다시 흘려보낼 수 있고, 그때
    // transactionDate가 비어 있으면 위에서 "지금부터 며칠"로 다시 잰다.
    // 그대로 덮어쓰면 만료일이 열 때마다 오늘 기준으로 밀리면서, 마스터
    // 개통 안내([[master_unlock_notice]])가 매번 "새 구독"으로 보여 또 뜬다.
    // 이미 가진 만료일이 이번에 다시 잰 값보다 같거나 늦으면(또는 영구면)
    // 그대로 둔다 - 진짜로 더 늘어난 경우(연장 결제)만 갱신한다.
    final current = await UserDataService.load();
    final keepsCurrent =
        current.isPlanActive &&
        current.planType == plan.planType &&
        (current.planExpiresAt == null ||
            !current.planExpiresAt!.isBefore(candidateExpiry));
    if (keepsCurrent) return;

    await UserDataService.setPlan(plan.planType, expiresAt: candidateExpiry);
  }

  PurchasePlan? _planForProductId(String productId) =>
      catalog.planForProductId(productId);

  void _completePending(String productId, PurchaseResult result) {
    final completer = _pendingPurchases.remove(productId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(result);
    }
  }
}
