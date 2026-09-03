import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../services/purchase_service.dart';
import 'auth_screen.dart';
import 'delete_account_screen.dart';
import 'memories_screen.dart';
import 'paywall_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_of_service_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String phoneNumber;
  const SettingsScreen({super.key, required this.phoneNumber});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _isExporting = false;
  String _notificationFrequency = 'normal';
  bool _memoryEnabled = true;
  int _messagesUsedToday = 0;
  int _dailyLimit = 20;
  bool _hasActiveAdBonus = false;
  bool _isPremium = false;
  String? _country;
  String? _region;
  String? _district;

  // Subscription details -- fetched separately from /premium/status
  // (the canonical, Play-re-verifying premium check), not /usage's
  // simpler local one. Null product/expiry just means "don't have
  // the details yet" or "not on a paid plan" -- the plan summary
  // tile below falls back to the plain Free/Premium label either way.
  String? _productId;
  int? _expiryTimeMillis;

  @override
  void initState() {
    super.initState();
    _loadUsage();
    _loadPremiumDetails();
  }

  Future<void> _loadUsage() async {
    try {
      final usage = await _api.getUsage();
      if (!mounted) return;
      setState(() {
        _messagesUsedToday = usage['messages_used_today'] ?? 0;
        _dailyLimit = usage['daily_limit'] ?? 20;
        _hasActiveAdBonus = usage['has_active_ad_bonus'] ?? false;
        _isPremium = usage['is_premium'] ?? false;
        _notificationFrequency = usage['notification_frequency'] ?? 'normal';
        _memoryEnabled = usage['memory_enabled'] ?? true;
        _country = usage['country'];
        _region = usage['region'];
        _district = usage['district'];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadPremiumDetails() async {
    try {
      final status = await _api.checkPremiumStatus();
      if (!mounted) return;
      setState(() {
        _productId = status['product_id'];
        _expiryTimeMillis = status['expiry_time_millis'];
      });
    } catch (e) {
      // Plan summary just falls back to the plain Free/Premium label.
    }
  }

  String? get _planLabel {
    if (_productId == PurchaseService.lifetimeId) return 'Lifetime';
    if (_productId == PurchaseService.yearlyId) return 'Yearly';
    if (_productId == PurchaseService.monthlyId) return 'Monthly';
    return null;
  }

  String? get _renewalSummary {
    if (_productId == PurchaseService.lifetimeId) return 'No renewal — yours for life 🎉';
    if (_expiryTimeMillis == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(_expiryTimeMillis!);
    final formatted = '${_monthName(date.month)} ${date.day}, ${date.year}';
    return 'Renews $formatted';
  }

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String _monthName(int month) => _monthNames[(month - 1).clamp(0, 11)];

  Future<void> _exportData() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final data = await _api.exportUserData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ollie_data_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Your Ollie data export'),
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Could not export your data, try again');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _openSubscriptionManagement() async {
    final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('launch returned false');
    } catch (e) {
      if (!mounted) return;
      _showError('Could not open the Play Store — manage your subscription there directly.');
    }
  }

  static const List<Map<String, String>> _frequencyOptions = [
    {'value': 'off', 'label': 'Off', 'description': "Ollie won't reach out first"},
    {'value': 'low', 'label': 'Low', 'description': 'Just a morning hello'},
    {'value': 'normal', 'label': 'Normal', 'description': 'Morning, evening, and check-ins'},
    {'value': 'frequent', 'label': 'Frequent', 'description': "More often, checks in sooner if you're quiet"},
  ];

  String _frequencyLabel(String value) {
    return _frequencyOptions.firstWhere(
      (o) => o['value'] == value,
      orElse: () => _frequencyOptions[2],
    )['label']!;
  }

  Future<void> _setFrequency(String frequency) async {
    final previous = _notificationFrequency;
    setState(() => _notificationFrequency = frequency);
    try {
      await _api.setNotificationFrequency(frequency);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificationFrequency = previous);
      _showError('Could not update notification setting');
    }
  }

  Future<void> _showFrequencyDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: const Text('How often should Ollie reach out?', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _frequencyOptions.map((option) {
            final selected = option['value'] == _notificationFrequency;
            // "Frequent" is Premium-only (see settings.py's write-time
            // gate) -- a free user tapping it goes to the paywall
            // instead of a dead-end error.
            final locked = option['value'] == 'frequent' && !_isPremium;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.pop(context);
                if (locked) {
                  _openPaywall();
                } else if (!selected) {
                  _setFrequency(option['value']!);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                child: Row(
                  children: [
                    Icon(
                      locked
                          ? Icons.lock_outline
                          : (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                      color: selected ? const Color(0xFFFF8C6B) : Colors.white.withOpacity(0.4),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                option['label']!,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              if (locked) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'PREMIUM',
                                  style: TextStyle(
                                    color: const Color(0xFFFF8C6B).withOpacity(0.9),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            option['description']!,
                            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMemory(bool value) async {
    setState(() => _memoryEnabled = value);
    try {
      await _api.setMemoryEnabled(value);
    } catch (e) {
      // revert on failure
      if (!mounted) return;
      setState(() => _memoryEnabled = !value);
      _showError('Could not update memory setting');
    }
  }

  String _locationSummary() {
    final parts = [_district, _region, _country]
        .where((p) => p != null && p.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Not set' : parts.join(', ');
  }

  Future<void> _showLocationEditDialog() async {
    final countryController = TextEditingController(text: _country);
    final regionController = TextEditingController(text: _region);
    final districtController = TextEditingController(text: _district);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: const Text('Your location', style: TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "so Ollie can talk like a local — reference your culture, "
                "holidays, what's actually going on where you are",
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _locationField(countryController, 'Country'),
              const SizedBox(height: 10),
              _locationField(regionController, 'State / Province / Region'),
              const SizedBox(height: 10),
              _locationField(districtController, 'District / City (optional)'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save', style: TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) return;

    final country = countryController.text.trim();
    final region = regionController.text.trim();
    final district = districtController.text.trim();

    try {
      await _api.updateLocation(
        country: country.isEmpty ? null : country,
        region: region.isEmpty ? null : region,
        district: district.isEmpty ? null : district,
      );
      if (!mounted) return;
      setState(() {
        _country = country.isEmpty ? null : country;
        _region = region.isEmpty ? null : region;
        _district = district.isEmpty ? null : district;
      });
      _showSuccess('Location updated');
    } catch (e) {
      if (!mounted) return;
      _showError('Could not update location, try again');
    }
  }

  Widget _locationField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF8C6B)),
        ),
      ),
    );
  }

  Future<void> _confirmClearMemory() async {
    final confirmed = await _showConfirmDialog(
      title: 'Clear memory?',
      message:
          "Ollie will forget everything it's learned about you — your interests, "
          "things you've shared, patterns it noticed. This can't be undone.",
      confirmLabel: 'Clear memory',
      isDestructive: true,
    );
    if (confirmed != true) return;

    try {
      await _api.clearMemory();
      if (!mounted) return;
      _showSuccess('Memory cleared');
    } catch (e) {
      _showError('Could not clear memory, try again');
    }
  }

  Future<void> _openPaywall() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
    _loadUsage();
  }

  Future<void> _logout() async {
    final confirmed = await _showConfirmDialog(
      title: 'Log out?',
      message: 'You can log back in anytime.',
      confirmLabel: 'Log out',
      isDestructive: false,
    );
    if (confirmed != true) return;

    await _api.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required bool isDestructive,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: TextStyle(color: Colors.white.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              confirmLabel,
              style: TextStyle(
                color: isDestructive ? const Color(0xFFE53935) : const Color(0xFFFF8C6B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFFE53935)),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: const Color(0xFF43A047)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Settings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionLabel('Account'),
                _infoTile(Icons.phone_android, 'Phone number', widget.phoneNumber),
                _actionTile(
                  Icons.logout,
                  'Log out',
                  onTap: _logout,
                ),
                _actionTile(
                  Icons.download_outlined,
                  _isExporting ? 'Preparing your export…' : 'Export my data',
                  onTap: _exportData,
                ),
                _actionTile(
                  Icons.delete_outline,
                  'Delete account',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
                  ),
                  destructive: true,
                ),

                _sectionLabel('Usage'),
                _infoTile(
                  Icons.chat_bubble_outline,
                  'Messages today',
                  '$_messagesUsedToday / $_dailyLimit'
                      '${_isPremium ? " (premium — unlimited)" : ""}'
                      '${_hasActiveAdBonus ? " · bonus active" : ""}',
                ),
                _infoTile(
                  Icons.workspace_premium_outlined,
                  'Plan',
                  _isPremium ? (_planLabel ?? 'Premium') : 'Free',
                ),
                if (_isPremium && _renewalSummary != null)
                  _infoTile(Icons.event_repeat_outlined, 'Renewal', _renewalSummary!),
                if (_isPremium && _productId != PurchaseService.lifetimeId)
                  _actionTile(
                    Icons.open_in_new_rounded,
                    'Manage subscription',
                    onTap: _openSubscriptionManagement,
                  ),
                if (!_isPremium)
                  _actionTile(
                    Icons.workspace_premium_outlined,
                    'Upgrade to Premium',
                    onTap: _openPaywall,
                  ),

                _sectionLabel('Notifications'),
                _infoTile(
                  Icons.notifications_none,
                  'How often Ollie reaches out',
                  _frequencyLabel(_notificationFrequency),
                ),
                _actionTile(
                  Icons.tune,
                  'Change',
                  onTap: _showFrequencyDialog,
                ),

                _sectionLabel('Location'),
                _infoTile(
                  Icons.location_on_outlined,
                  'Your location',
                  _locationSummary(),
                ),
                _actionTile(
                  Icons.edit_location_alt_outlined,
                  _country == null && _region == null && _district == null
                      ? 'Set your location'
                      : 'Edit location',
                  onTap: _showLocationEditDialog,
                ),

                _sectionLabel('Memory'),
                _switchTile(
                  Icons.psychology_outlined,
                  'Let Ollie remember',
                  _memoryEnabled,
                  _toggleMemory,
                ),
                _actionTile(
                  Icons.auto_stories_outlined,
                  'Manage memories',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemoriesScreen()),
                  ),
                ),
                _actionTile(
                  Icons.refresh,
                  'Clear Ollie\'s memory of you',
                  onTap: _confirmClearMemory,
                  destructive: true,
                ),

                _sectionLabel('About'),
                _infoTile(Icons.info_outline, 'Ollie', 'Made in Rwanda 🇷🇼'),
                _actionTile(
                  Icons.privacy_tip_outlined,
                  'Privacy Policy',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                _actionTile(
                  Icons.description_outlined,
                  'Terms of Service',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsOfServiceScreen()),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String title, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF8C6B).withOpacity(0.8), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Text(value, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, {required VoidCallback onTap, bool destructive = false}) {
    final color = destructive ? const Color(0xFFE53935) : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                Icon(icon, color: destructive ? color.withOpacity(0.8) : const Color(0xFFFF8C6B).withOpacity(0.8), size: 20),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(title, style: TextStyle(color: color, fontSize: 15)),
                ),
                Icon(Icons.chevron_right, color: Colors.white.withOpacity(0.2), size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchTile(IconData icon, String title, bool value, ValueChanged<bool> onChanged) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF8C6B).withOpacity(0.8), size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 15)),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFFFF8C6B),
          ),
        ],
      ),
    );
  }
}
