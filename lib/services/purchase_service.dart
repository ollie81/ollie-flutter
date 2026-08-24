import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api_service.dart';

enum PurchaseUiStatus { pending, success, error, canceled }

class PurchaseUiEvent {
  final PurchaseUiStatus status;
  final String? message;
  const PurchaseUiEvent(this.status, [this.message]);
}

// Owns the single subscription to the plugin's purchaseStream so a
// purchase is only ever completed once, even though both the paywall
// screen and this app-wide listener care about its outcome. Started
// once at app launch (see main.dart) rather than only while the
// paywall is open, since a purchase can resolve after the user has
// already left that screen (a pending payment method, or picking the
// app back up after closing the platform billing sheet).
class PurchaseService {
  PurchaseService._();
  static final PurchaseService instance = PurchaseService._();

  // TODO: these are placeholder product IDs. Create matching
  // products in Play Console (Monetize > Products) -- monthly and
  // yearly as auto-renewing subscriptions, lifetime as a managed
  // one-time product -- and update these to match before release.
  static const String monthlyId = 'ollie_premium_monthly';
  static const String yearlyId = 'ollie_premium_yearly';
  static const String lifetimeId = 'ollie_premium_lifetime';
  static const Set<String> productIds = {monthlyId, yearlyId, lifetimeId};

  final InAppPurchase _iap = InAppPurchase.instance;
  final ApiService _api = ApiService();
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final StreamController<PurchaseUiEvent> _uiEvents = StreamController.broadcast();

  Stream<PurchaseUiEvent> get uiEvents => _uiEvents.stream;

  void init() {
    if (_subscription != null) return;
    _subscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        _uiEvents.add(PurchaseUiEvent(PurchaseUiStatus.error, error.toString()));
      },
    );
  }

  Future<bool> isAvailable() => _iap.isAvailable();

  Future<List<ProductDetails>> queryProducts() async {
    final response = await _iap.queryProductDetails(productIds);
    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) {
    return _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: product));
  }

  Future<void> restorePurchases() => _iap.restorePurchases();

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      var shouldComplete = true;

      switch (purchase.status) {
        case PurchaseStatus.pending:
          _uiEvents.add(const PurchaseUiEvent(PurchaseUiStatus.pending));
          shouldComplete = false;
          break;
        case PurchaseStatus.error:
          _uiEvents.add(PurchaseUiEvent(PurchaseUiStatus.error, purchase.error?.message));
          break;
        case PurchaseStatus.canceled:
          _uiEvents.add(const PurchaseUiEvent(PurchaseUiStatus.canceled));
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          shouldComplete = await _activateOnServer(purchase);
          break;
      }

      if (shouldComplete && purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  // Returns whether it's safe to complete the purchase. On failure we
  // deliberately leave it uncompleted -- the purchase itself already
  // went through, so the store will redeliver it (on next launch, or
  // when the stream reconnects) and we get another chance to activate,
  // instead of losing the purchase over a network blip.
  Future<bool> _activateOnServer(PurchaseDetails purchase) async {
    try {
      await _api.activatePremium(
        purchaseToken: purchase.verificationData.serverVerificationData,
        productId: purchase.productID,
      );
      _uiEvents.add(const PurchaseUiEvent(PurchaseUiStatus.success));
      return true;
    } catch (e) {
      _uiEvents.add(const PurchaseUiEvent(
        PurchaseUiStatus.error,
        "Purchase went through but we couldn't confirm it — it'll finish activating next time you open the app.",
      ));
      return false;
    }
  }
}
