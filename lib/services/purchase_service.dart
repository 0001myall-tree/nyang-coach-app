import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  factory PurchaseResult.coach() =>
      const PurchaseResult._(success: true, message: '코치가 열렸어요.');

  factory PurchaseResult.failure(String message) =>
      PurchaseResult._(success: false, message: message);
}

class PurchaseService {
  PurchaseService._();

  static final PurchaseService instance = PurchaseService._();

  /// 구독 안내 시트로 들어가는 입구를 여는지.
  ///
  /// 결제가 끝나면 서버(verifyPurchase)가 스토어에 직접 확인하고 플랜을 켠다.
  /// 앱은 그 확인을 받은 뒤에만 결제를 마무리한다 — 확인이 안 되면 구글은
  /// 사흘 뒤 자동 환불하고, 애플은 다음에 앱을 열 때 다시 넘겨준다.
  static const bool storeCheckoutEnabled = true;

  /// 코치 한 명만 1년씩 사는 길. 확인은 구독과 같은 서버가 한다.
  static const bool singleCoachPurchaseEnabled = true;

  /// 서버의 결제 확인. 애플 것은 열쇠가 따로 필요해 함수를 나눠두었다.
  static HttpsCallable get _verifyPurchase => FirebaseFunctions.instanceFor(
    region: 'asia-northeast3',
  ).httpsCallable(_isAndroid ? 'verifyPurchase' : 'verifyApplePurchase');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 하루 한 번 구독 상태를 다시 확인한 날. 이 기기만의 사실이라 'nyang_'
  /// 접두어를 쓰지 않는다(클라우드로 오가지 않게).
  static const String _refreshDateKey = 'purchase_refresh_date';

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
    // 구글은 구독 하나를 혜택마다 따로 돌려준다(기본 요금제, 무료 체험 등).
    // 이 사람이 받을 수 있는 혜택만 온다 — 이미 체험한 사람에게는 체험이
    // 빠져서 온다. 무료 구간이 있는 것을 체험으로 따로 챙긴다.
    final products = <String, ProductDetails>{};
    final trials = <String, ProductDetails>{};
    for (final product in response.productDetails) {
      if (_hasFreePhase(product)) {
        trials[product.id] = product;
      } else {
        products[product.id] = product;
      }
    }
    for (final entry in trials.entries) {
      products.putIfAbsent(entry.key, () => entry.value);
    }
    _products = products;
    _trialOffers = trials;
    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('Missing store products: ${response.notFoundIDs.join(', ')}');
    }
    return _products;
  }

  PurchasePlan? planForSelection(String planType, bool isLongTerm) =>
      catalog.planFor(planType, isLongTerm: isLongTerm);

  ProductDetails? productFor(PurchasePlan plan) => _products[plan.productId];

  /// 무료 체험이 붙은 구글 혜택. 상품 이름으로 찾는다.
  Map<String, ProductDetails> _trialOffers = {};

  static bool _hasFreePhase(ProductDetails product) {
    if (product is! GooglePlayProductDetails) return false;
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) {
      return false;
    }
    return offers[index].pricingPhases.any(
      (phase) => phase.priceAmountMicros == 0,
    );
  }

  /// 이 사람이 지금 이 플랜을 무료 체험으로 시작할 수 있는지.
  ///
  /// 체험은 앱 전체에서 한 번이다(구글은 혜택 자격을 "구독한 적 없음",
  /// 애플은 같은 구독 그룹으로 묶어서). 그래서 스토어에 묻는다 — 앱이 따로
  /// 세면 스토어와 어긋나서, 체험이라고 안내했는데 바로 결제되는 일이 생긴다.
  Future<bool> hasFreeTrial(PurchasePlan plan) async {
    if (_products.isEmpty) await loadProducts();
    if (_isAndroid) return _trialOffers.containsKey(plan.productId);
    if (!_products.containsKey(plan.productId)) return false;
    try {
      final platform = InAppPurchasePlatform.instance;
      if (platform is! InAppPurchaseStoreKitPlatform) return false;
      return await platform.isIntroductoryOfferEligible(plan.productId);
    } catch (e) {
      debugPrint('Intro offer check failed: $e');
      return false;
    }
  }

  Future<PurchaseResult> purchase(PurchasePlan plan) async {
    await start();
    final available = await _iap.isAvailable();
    if (!available) {
      return PurchaseResult.failure('스토어 결제를 사용할 수 없는 상태예요.');
    }

    final products = _products.isEmpty ? await loadProducts() : _products;
    // 체험을 받을 수 있으면 체험 혜택으로 산다. 애플은 받을 수 있으면 알아서
    // 붙인다.
    final product = _trialOffers[plan.productId] ?? products[plan.productId];
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

  /// 코치 1년 이용권을 산다.
  Future<PurchaseResult> purchaseCoach(String coachId) async {
    await start();
    if (!await _iap.isAvailable()) {
      return PurchaseResult.failure('스토어 결제를 사용할 수 없는 상태예요.');
    }
    final productId = PlanCatalog.coachPassProductId(coachId);
    final products = _products.containsKey(productId)
        ? _products
        : await loadProducts();
    final product = products[productId];
    if (product == null) {
      return PurchaseResult.failure('스토어에서 이 코치를 찾지 못했어요.');
    }

    final completer = Completer<PurchaseResult>();
    _pendingPurchases[productId] = completer;
    // 다 쓴 뒤 다시 살 수 있어야 해서 소모성으로 산다. 자동으로 쓰지 않는다 —
    // 서버 확인 전에 써버리면, 확인이 실패해도 구글이 환불하지 않는다.
    final started = await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: false,
    );
    if (!started) {
      _pendingPurchases.remove(productId);
      return PurchaseResult.failure('결제를 시작하지 못했어요. 잠시 후 다시 시도해주세요.');
    }
    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        _pendingPurchases.remove(productId);
        return PurchaseResult.failure('결제 확인이 길어지고 있어요. 앱을 다시 열면 반영돼요.');
      },
    );
  }

  /// 하루 한 번, 가진 구독과 아직 확인 못 한 결제를 다시 서버에 맞춘다.
  ///
  /// 매달 갱신돼도 앱이 알 길은 이것뿐이다. 그리고 확인이 실패해 마무리 못 한
  /// 결제도 여기서 다시 넘어온다. 안드로이드만 한다 — 애플은 갱신과 못 끝낸
  /// 결제를 앱을 열 때 알아서 다시 넘겨주고, 복원을 부르면 비밀번호를 묻는다.
  Future<void> refreshOncePerDay() async {
    if (!storeCheckoutEnabled || !_isAndroid) return;
    if (FirebaseAuth.instance.currentUser == null) return;
    final prefs = await SharedPreferences.getInstance();
    final today = DateTime.now().toIso8601String().substring(0, 10);
    if (prefs.getString(_refreshDateKey) == today) return;
    try {
      await restorePurchases();
      await prefs.setString(_refreshDateKey, today);
    } catch (e) {
      debugPrint('Purchase refresh failed: $e');
    }
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
      final coachId = PlanCatalog.coachForProductId(purchase.productID);
      if (plan == null && coachId == null) {
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final verdict = await _verify(purchase);
          if (verdict == _Verdict.failed) {
            // 마무리하지 않는다. 다음에 다시 넘어와 확인을 받는다.
            _completePending(
              purchase.productID,
              PurchaseResult.failure('결제 확인이 늦어지고 있어요. 앱을 다시 열면 반영돼요.'),
            );
            continue;
          }
          await _finish(purchase, consumable: coachId != null);
          await UserDataService.syncFromCloud();
          _completePending(
            purchase.productID,
            verdict == _Verdict.inactive
                ? PurchaseResult.failure('이미 끝난 결제예요.')
                : (plan != null
                      ? PurchaseResult.success(plan)
                      : PurchaseResult.coach()),
          );
          continue;
        case PurchaseStatus.error:
          _completePending(
            purchase.productID,
            PurchaseResult.failure(
              purchase.error?.message ?? '결제 중 오류가 발생했어요.',
            ),
          );
          break;
        case PurchaseStatus.canceled:
          _completePending(
            purchase.productID,
            PurchaseResult.failure('결제가 취소됐어요.'),
          );
          break;
        case PurchaseStatus.pending:
          continue;
      }

      // 실패·취소한 거래도 애플은 마무리해야 줄에서 빠진다.
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// 서버에 이 결제가 진짜인지 묻는다. 진짜면 서버가 플랜이나 코치를 연다.
  ///
  /// 플랜을 여기서 직접 켜지 않는다. 규칙이 막아두었고, 앱이 켤 수 있으면
  /// 결제 없이도 켤 수 있다는 뜻이 된다.
  Future<_Verdict> _verify(PurchaseDetails purchase) async {
    // 애플은 앱이 뜨자마자 못 끝낸 거래를 넘겨준다. 그때 아직 로그인이 안
    // 돌아왔으면 서버가 누구 것인지 모른다.
    try {
      await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((user) => user != null)
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      return _Verdict.failed;
    }
    final token = _isAndroid
        ? purchase.verificationData.serverVerificationData
        : purchase.purchaseID;
    if (token == null || token.isEmpty) return _Verdict.failed;
    try {
      final result = await _verifyPurchase.call<Map<String, dynamic>>({
        'productId': purchase.productID,
        'token': token,
      });
      final data = result.data;
      if (data['ok'] == true) return _Verdict.granted;
      return data['active'] == false ? _Verdict.inactive : _Verdict.failed;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('verifyPurchase ${e.code}: ${e.message}');
      // 다른 계정에 연결된 결제처럼 다시 해봐야 안 되는 것은 마무리한다.
      if (e.code == 'permission-denied' || e.code == 'invalid-argument') {
        return _Verdict.inactive;
      }
      return _Verdict.failed;
    } catch (e) {
      debugPrint('verifyPurchase failed: $e');
      return _Verdict.failed;
    }
  }

  /// 확인을 받은 결제를 마무리한다. 코치 이용권은 써서 다음에 또 살 수 있게
  /// 하고, 구독은 받았다고만 알린다.
  Future<void> _finish(
    PurchaseDetails purchase, {
    required bool consumable,
  }) async {
    if (consumable && _isAndroid) {
      final android = _iap
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await android.consumePurchase(purchase);
      return;
    }
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
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

enum _Verdict {
  /// 서버가 확인하고 열어줬다.
  granted,

  /// 진짜 결제지만 쓸 수 없다(끝난 구독, 다른 계정에 연결된 결제). 마무리한다.
  inactive,

  /// 확인을 못 했다. 마무리하지 않고 다음에 다시 한다.
  failed,
}
