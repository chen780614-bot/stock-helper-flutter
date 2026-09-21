import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'entitlement.dart';

/// Product IDs for Play Billing subscriptions (ads-off only).
class BillingProductIds {
  static const quarterly = 'premium_quarterly';
  static const yearly = 'premium_yearly';
  static const Set<String> all = {quarterly, yearly};
}

enum BillingAvailability {
  unknown,
  available,
  storeUnavailable,
  productsMissing,
}

/// Thin Play Billing scaffolding. Never fakes paid status.
class BillingService extends ChangeNotifier {
  BillingService(this.entitlement);

  final EntitlementService entitlement;
  final InAppPurchase _iap = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  bool _ready = false;
  BillingAvailability _availability = BillingAvailability.unknown;
  String? _message;
  List<ProductDetails> _products = [];
  bool _purchaseInFlight = false;

  bool get ready => _ready;
  BillingAvailability get availability => _availability;
  String? get message => _message;
  List<ProductDetails> get products => List.unmodifiable(_products);
  bool get purchaseInFlight => _purchaseInFlight;
  bool get canPurchase =>
      _availability == BillingAvailability.available && _products.isNotEmpty;

  ProductDetails? productById(String id) {
    for (final p in _products) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Fallback display when Play has not returned localized prices.
  String fallbackPriceLabel(String productId) => switch (productId) {
        BillingProductIds.quarterly => 'NT\$52／季',
        BillingProductIds.yearly => 'NT\$170／年',
        _ => productId,
      };

  Future<void> init() async {
    try {
      final available = await _iap.isAvailable();
      if (!available) {
        _availability = BillingAvailability.storeUnavailable;
        _message = 'Play 訂閱商品尚未開放，請稍後';
        _ready = true;
        notifyListeners();
        return;
      }
      _sub ??= _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e, StackTrace st) {
          debugPrint('purchaseStream error: $e\n$st');
        },
      );
      await refreshProducts();
    } catch (e, st) {
      debugPrint('BillingService.init failed: $e\n$st');
      _availability = BillingAvailability.storeUnavailable;
      _message = 'Play 訂閱商品尚未開放，請稍後';
    } finally {
      _ready = true;
      notifyListeners();
    }
  }

  Future<void> refreshProducts() async {
    try {
      final resp = await _iap.queryProductDetails(BillingProductIds.all);
      _products = resp.productDetails.toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      if (_products.isEmpty) {
        _availability = BillingAvailability.productsMissing;
        _message = 'Play 訂閱商品尚未開放，請稍後';
      } else {
        _availability = BillingAvailability.available;
        _message = null;
      }
      if (resp.notFoundIDs.isNotEmpty) {
        debugPrint('Billing notFoundIDs: ${resp.notFoundIDs}');
        if (_products.isEmpty) {
          _availability = BillingAvailability.productsMissing;
          _message = 'Play 訂閱商品尚未開放，請稍後';
        }
      }
    } catch (e, st) {
      debugPrint('queryProductDetails failed: $e\n$st');
      _availability = BillingAvailability.storeUnavailable;
      _message = 'Play 訂閱商品尚未開放，請稍後';
      _products = [];
    }
    notifyListeners();
  }

  Future<void> buy(ProductDetails product) async {
    if (_purchaseInFlight) return;
    if (!canPurchase) {
      _message = 'Play 訂閱商品尚未開放，請稍後';
      notifyListeners();
      return;
    }
    _purchaseInFlight = true;
    notifyListeners();
    try {
      final param = PurchaseParam(productDetails: product);
      // Subscriptions use buyNonConsumable on Android via Play Billing.
      final ok = await _iap.buyNonConsumable(purchaseParam: param);
      if (!ok) {
        _message = '無法啟動購買流程，請稍後再試';
      }
    } catch (e, st) {
      debugPrint('buy failed: $e\n$st');
      _message = 'Play 訂閱商品尚未開放，請稍後';
    } finally {
      _purchaseInFlight = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    try {
      await _iap.restorePurchases();
    } catch (e, st) {
      debugPrint('restorePurchases failed: $e\n$st');
      _message = '無法還原購買，請稍後再試';
      notifyListeners();
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          _purchaseInFlight = true;
          notifyListeners();
        case PurchaseStatus.error:
          _purchaseInFlight = false;
          _message = purchase.error?.message ?? '購買失敗，請稍後再試';
          notifyListeners();
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.canceled:
          _purchaseInFlight = false;
          notifyListeners();
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _purchaseInFlight = false;
          if (BillingProductIds.all.contains(purchase.productID)) {
            // Client-side grant after Play reports purchased/restored.
            // No server verification yet — do not invent status when store missing.
            await entitlement.grantFromPlay(
              productId: purchase.productID,
              purchaseId: purchase.purchaseID,
            );
          }
          notifyListeners();
          if (purchase.pendingCompletePurchase) {
            await _iap.completePurchase(purchase);
          }
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
