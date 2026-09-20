import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/purchase_service.dart';

// Title/subtitle for each tier are looked up by productId at build
// time (_tierTitle/_tierSubtitle) rather than stored on _Tier, since
// a top-level const list can't hold context-dependent localized
// strings. fallbackPrice stays a plain literal -- it's only ever
// shown for the brief moment before the real, already
// locale-formatted price loads from the store.
class _Tier {
  final String productId;
  final String fallbackPrice;
  final bool isRecommended;
  const _Tier(this.productId, this.fallbackPrice, {this.isRecommended = false});
}

const _tiers = [
  _Tier(PurchaseService.monthlyId, '\$9.99/mo'),
  _Tier(PurchaseService.yearlyId, '\$89.99/yr', isRecommended: true),
  _Tier(PurchaseService.lifetimeId, '\$249.99 once'),
];

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _loading = true;
  bool _storeAvailable = true;
  bool _busy = false;
  Map<String, ProductDetails> _products = {};
  StreamSubscription<PurchaseUiEvent>? _uiSubscription;

  // The backend only verifies Google Play purchases so far (see
  // premium.py's /activate -- it's Android Publisher API only, no
  // Apple App Store Server API support yet). A real purchase would
  // still go through on iOS via StoreKit, charging the user, and
  // then fail to activate anything -- so block it here rather than
  // ship that. Remove this once the backend can verify Apple receipts.
  bool get _iosNotYetSupported => Platform.isIOS;

  String _tierTitle(AppLocalizations l10n, _Tier tier) {
    if (tier.productId == PurchaseService.monthlyId) return l10n.paywallMonthlyTitle;
    if (tier.productId == PurchaseService.yearlyId) return l10n.paywallYearlyTitle;
    return l10n.paywallLifetimeTitle;
  }

  String _tierSubtitle(AppLocalizations l10n, _Tier tier) {
    if (tier.productId == PurchaseService.monthlyId) return l10n.paywallMonthlySubtitle;
    if (tier.productId == PurchaseService.yearlyId) return l10n.paywallYearlySubtitle;
    return l10n.paywallLifetimeSubtitle;
  }

  @override
  void initState() {
    super.initState();
    PurchaseService.instance.init();
    _uiSubscription = PurchaseService.instance.uiEvents.listen(_onPurchaseUiEvent);
    _load();
  }

  @override
  void dispose() {
    _uiSubscription?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_iosNotYetSupported) {
      setState(() => _loading = false);
      return;
    }

    final available = await PurchaseService.instance.isAvailable();
    if (!mounted) return;
    if (!available) {
      setState(() {
        _storeAvailable = false;
        _loading = false;
      });
      return;
    }

    final products = await PurchaseService.instance.queryProducts();
    if (!mounted) return;
    setState(() {
      _products = {for (final p in products) p.id: p};
      _loading = false;
    });
  }

  void _onPurchaseUiEvent(PurchaseUiEvent event) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    switch (event.status) {
      case PurchaseUiStatus.pending:
        setState(() => _busy = true);
        break;
      case PurchaseUiStatus.success:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.paywallPurchaseSuccess),
            backgroundColor: const Color(0xFF43A047),
          ),
        );
        Navigator.pop(context, true);
        break;
      case PurchaseUiStatus.error:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.message ?? l10n.paywallPurchaseError),
            backgroundColor: const Color(0xFFE53935),
          ),
        );
        break;
      case PurchaseUiStatus.canceled:
        setState(() => _busy = false);
        break;
    }
  }

  Future<void> _buy(_Tier tier) async {
    final product = _products[tier.productId];
    if (product == null || _busy) return;
    setState(() => _busy = true);
    try {
      await PurchaseService.instance.buy(product);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.paywallPurchaseStartError(e.toString())),
          backgroundColor: const Color(0xFFE53935),
        ),
      );
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      await PurchaseService.instance.restorePurchases();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.paywallRestoreError(e.toString())),
          backgroundColor: const Color(0xFFE53935),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.paywallTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)))
          : _iosNotYetSupported
              ? _buildMessage(l10n.paywalliOSComingSoon)
              : !_storeAvailable
                  ? _buildMessage(l10n.paywallStoreUnavailable)
                  : _buildTiers(l10n),
    );
  }

  Widget _buildMessage(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 15),
        ),
      ),
    );
  }

  Widget _buildTiers(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.workspace_premium_outlined, color: Color(0xFFFF8C6B), size: 40),
        const SizedBox(height: 12),
        Text(
          l10n.paywallHeadline,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        for (final tier in _tiers) ...[
          _tierCard(l10n, tier),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _restore,
            child: Text(
              l10n.paywallRestorePurchases,
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tierCard(AppLocalizations l10n, _Tier tier) {
    final product = _products[tier.productId];
    final available = product != null;
    final price = product?.price ?? tier.fallbackPrice;

    final card = Container(
      padding: EdgeInsets.fromLTRB(18, tier.isRecommended ? 22 : 18, 18, 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: tier.isRecommended
              ? const Color(0xFFFF8C6B).withOpacity(0.6)
              : Colors.white.withOpacity(0.08),
          width: tier.isRecommended ? 1.5 : 1,
        ),
        boxShadow: tier.isRecommended
            ? [
                BoxShadow(
                  color: const Color(0xFFFF8C6B).withOpacity(0.15),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _tierTitle(l10n, tier),
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      price,
                      style: const TextStyle(color: Color(0xFFFF8C6B), fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  available ? _tierSubtitle(l10n, tier) : l10n.paywallNotAvailableYet,
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C6B),
              disabledBackgroundColor: Colors.white.withOpacity(0.1),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: available && !_busy ? () => _buy(tier) : null,
            child: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(l10n.paywallGo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (!tier.isRecommended) return card;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        Positioned(
          top: -1,
          left: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.paywallBestValueBadge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
