import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../services/purchase_service.dart';

class _Tier {
  final String productId;
  final String title;
  final String fallbackPrice;
  final String subtitle;
  final bool isRecommended;
  const _Tier(this.productId, this.title, this.fallbackPrice, this.subtitle, {this.isRecommended = false});
}

const _tiers = [
  _Tier(
    PurchaseService.monthlyId,
    'Monthly',
    '\$9.99/mo',
    'Unlimited messages, voice with Ollie, no ads',
  ),
  _Tier(
    PurchaseService.yearlyId,
    'Yearly',
    '\$89.99/yr',
    'Best value — about 25% less than paying monthly',
    isRecommended: true,
  ),
  _Tier(
    PurchaseService.lifetimeId,
    'Lifetime',
    '\$249.99 once',
    'Pay once, premium forever',
  ),
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
    switch (event.status) {
      case PurchaseUiStatus.pending:
        setState(() => _busy = true);
        break;
      case PurchaseUiStatus.success:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("you're premium now — welcome"),
            backgroundColor: Color(0xFF43A047),
          ),
        );
        Navigator.pop(context, true);
        break;
      case PurchaseUiStatus.error:
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.message ?? 'Something went wrong with that purchase'),
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
        SnackBar(content: Text('Could not start purchase: $e'), backgroundColor: const Color(0xFFE53935)),
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
        SnackBar(content: Text('Could not restore purchases: $e'), backgroundColor: const Color(0xFFE53935)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Ollie Premium', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)))
          : _iosNotYetSupported
              ? _buildMessage("premium on iOS is coming soon — for now, premium is available on Android")
              : !_storeAvailable
                  ? _buildMessage("purchases aren't available on this device right now")
                  : _buildTiers(),
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

  Widget _buildTiers() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.workspace_premium_outlined, color: Color(0xFFFF8C6B), size: 40),
        const SizedBox(height: 12),
        const Text(
          'unlimited messages, real voice conversations, no ads',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        for (final tier in _tiers) ...[
          _tierCard(tier),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _restore,
            child: Text(
              'restore purchases',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tierCard(_Tier tier) {
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
                      tier.title,
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
                  available ? tier.subtitle : 'not available yet',
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
                : const Text('go', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
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
            child: const Text(
              'BEST VALUE',
              style: TextStyle(
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
