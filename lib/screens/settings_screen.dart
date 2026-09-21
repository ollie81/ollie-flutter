import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/locale_controller.dart';
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
    final l10n = AppLocalizations.of(context)!;
    if (_productId == PurchaseService.lifetimeId) return l10n.settingsPlanLifetime;
    if (_productId == PurchaseService.yearlyId) return l10n.settingsPlanYearly;
    if (_productId == PurchaseService.monthlyId) return l10n.settingsPlanMonthly;
    return null;
  }

  String? get _renewalSummary {
    final l10n = AppLocalizations.of(context)!;
    if (_productId == PurchaseService.lifetimeId) return l10n.settingsRenewalLifetime;
    if (_expiryTimeMillis == null) return null;
    final date = DateTime.fromMillisecondsSinceEpoch(_expiryTimeMillis!);
    final formatted = DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);
    return l10n.settingsRenewsOn(formatted);
  }

  static const List<String> _frequencyValues = ['off', 'low', 'normal', 'frequent'];

  String _freqLabel(AppLocalizations l10n, String value) {
    switch (value) {
      case 'off':
        return l10n.settingsFreqOffLabel;
      case 'low':
        return l10n.settingsFreqLowLabel;
      case 'frequent':
        return l10n.settingsFreqFrequentLabel;
      default:
        return l10n.settingsFreqNormalLabel;
    }
  }

  String _freqDescription(AppLocalizations l10n, String value) {
    switch (value) {
      case 'off':
        return l10n.settingsFreqOffDescription;
      case 'low':
        return l10n.settingsFreqLowDescription;
      case 'frequent':
        return l10n.settingsFreqFrequentDescription;
      default:
        return l10n.settingsFreqNormalDescription;
    }
  }

  Future<void> _exportData() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    final l10n = AppLocalizations.of(context)!;
    try {
      final data = await _api.exportUserData();
      final jsonString = const JsonEncoder.withIndent('  ').convert(data);
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ollie_data_export_${DateTime.now().millisecondsSinceEpoch}.json');
      await file.writeAsString(jsonString);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: l10n.settingsExportShareText),
      );
    } catch (e) {
      if (!mounted) return;
      _showError(l10n.settingsExportError);
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _shareOllie() async {
    final l10n = AppLocalizations.of(context)!;
    final userId = await _api.getOwnUserId();
    final url = 'https://ourollie.space/auth${userId != null ? '?ref=$userId' : ''}';
    try {
      await SharePlus.instance.share(
        ShareParams(text: l10n.settingsShareText, uri: Uri.parse(url)),
      );
    } catch (e) {
      // The native share sheet being dismissed also lands here on
      // some platforms -- not worth showing an error for that.
    }
  }

  Future<void> _openSubscriptionManagement() async {
    final l10n = AppLocalizations.of(context)!;
    final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('launch returned false');
    } catch (e) {
      if (!mounted) return;
      _showError(l10n.settingsOpenPlayStoreError);
    }
  }

  String _frequencyLabel(String value) {
    final l10n = AppLocalizations.of(context)!;
    return _freqLabel(l10n, _frequencyValues.contains(value) ? value : 'normal');
  }

  Future<void> _setFrequency(String frequency) async {
    final l10n = AppLocalizations.of(context)!;
    final previous = _notificationFrequency;
    setState(() => _notificationFrequency = frequency);
    try {
      await _api.setNotificationFrequency(frequency);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notificationFrequency = previous);
      _showError(l10n.settingsFrequencyError);
    }
  }

  Future<void> _showFrequencyDialog() async {
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: Text(l10n.settingsFrequencyDialogTitle, style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _frequencyValues.map((value) {
            final selected = value == _notificationFrequency;
            // "Frequent" is Premium-only (see settings.py's write-time
            // gate) -- a free user tapping it goes to the paywall
            // instead of a dead-end error.
            final locked = value == 'frequent' && !_isPremium;
            return InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                Navigator.pop(context);
                if (locked) {
                  _openPaywall();
                } else if (!selected) {
                  _setFrequency(value);
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
                                _freqLabel(l10n, value),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                              ),
                              if (locked) ...[
                                const SizedBox(width: 6),
                                Text(
                                  l10n.settingsPremiumBadge,
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
                            _freqDescription(l10n, value),
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
            child: Text(l10n.commonCancel, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final current = Localizations.localeOf(context).languageCode;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: Text(l10n.settingsChooseLanguage, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: kSupportedLanguages.map((lang) {
              final selected = lang.code == current;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  Navigator.pop(context);
                  if (!selected) LocaleController.setLocale(lang.code);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: selected ? const Color(0xFFFF8C6B) : Colors.white.withOpacity(0.4),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Text(lang.label, style: const TextStyle(color: Colors.white, fontSize: 15)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
        ],
      ),
    );
  }

  String _currentLanguageLabel() {
    final code = Localizations.localeOf(context).languageCode;
    return kSupportedLanguages.firstWhere((l) => l.code == code, orElse: () => kSupportedLanguages.first).label;
  }

  Future<void> _toggleMemory(bool value) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _memoryEnabled = value);
    try {
      await _api.setMemoryEnabled(value);
    } catch (e) {
      // revert on failure
      if (!mounted) return;
      setState(() => _memoryEnabled = !value);
      _showError(l10n.settingsMemoryToggleError);
    }
  }

  String _locationSummary() {
    final l10n = AppLocalizations.of(context)!;
    final parts = [_district, _region, _country]
        .where((p) => p != null && p.trim().isNotEmpty)
        .toList();
    return parts.isEmpty ? l10n.settingsLocationNotSet : parts.join(', ');
  }

  Future<void> _showLocationEditDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final countryController = TextEditingController(text: _country);
    final regionController = TextEditingController(text: _region);
    final districtController = TextEditingController(text: _district);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: Text(l10n.settingsYourLocation, style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsLocationHint,
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
              const SizedBox(height: 16),
              _locationField(countryController, l10n.settingsCountryLabel),
              const SizedBox(height: 10),
              _locationField(regionController, l10n.settingsRegionLabel),
              const SizedBox(height: 10),
              _locationField(districtController, l10n.settingsDistrictLabel),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel, style: TextStyle(color: Colors.white.withOpacity(0.6))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonSave, style: const TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600)),
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
      _showSuccess(l10n.settingsLocationUpdated);
    } catch (e) {
      if (!mounted) return;
      _showError(l10n.settingsLocationError);
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
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _showConfirmDialog(
      title: l10n.settingsClearMemoryTitle,
      message: l10n.settingsClearMemoryMessage,
      confirmLabel: l10n.settingsClearMemoryConfirm,
      isDestructive: true,
    );
    if (confirmed != true) return;

    try {
      await _api.clearMemory();
      if (!mounted) return;
      _showSuccess(l10n.settingsMemoryCleared);
    } catch (e) {
      _showError(l10n.settingsMemoryClearError);
    }
  }

  Future<void> _openPaywall() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
    _loadUsage();
  }

  Future<void> _logout() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await _showConfirmDialog(
      title: l10n.settingsLogOutTitle,
      message: l10n.settingsLogOutMessage,
      confirmLabel: l10n.settingsLogOut,
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
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1035),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: TextStyle(color: Colors.white.withOpacity(0.7))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel, style: TextStyle(color: Colors.white.withOpacity(0.6))),
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F1A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(l10n.settingsTitle, style: const TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C6B)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionLabel(l10n.settingsSectionAccount),
                _infoTile(Icons.phone_android, l10n.settingsPhoneNumber, widget.phoneNumber),
                _actionTile(
                  Icons.share_outlined,
                  l10n.settingsShareOllie,
                  onTap: _shareOllie,
                ),
                _actionTile(
                  Icons.logout,
                  l10n.settingsLogOut,
                  onTap: _logout,
                ),
                _actionTile(
                  Icons.download_outlined,
                  _isExporting ? l10n.settingsExportPreparing : l10n.settingsExportData,
                  onTap: _exportData,
                ),
                _actionTile(
                  Icons.delete_outline,
                  l10n.settingsDeleteAccount,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
                  ),
                  destructive: true,
                ),

                _sectionLabel(l10n.settingsSectionUsage),
                _infoTile(
                  Icons.chat_bubble_outline,
                  l10n.settingsMessagesToday,
                  '$_messagesUsedToday / $_dailyLimit'
                      '${_isPremium ? l10n.settingsPremiumUnlimited : ""}'
                      '${_hasActiveAdBonus ? l10n.settingsBonusActive : ""}',
                ),
                _infoTile(
                  Icons.workspace_premium_outlined,
                  l10n.settingsPlan,
                  _isPremium ? (_planLabel ?? l10n.settingsPlanPremiumFallback) : l10n.settingsPlanFree,
                ),
                if (_isPremium && _renewalSummary != null)
                  _infoTile(Icons.event_repeat_outlined, l10n.settingsRenewal, _renewalSummary!),
                if (_isPremium && _productId != PurchaseService.lifetimeId)
                  _actionTile(
                    Icons.open_in_new_rounded,
                    l10n.settingsManageSubscription,
                    onTap: _openSubscriptionManagement,
                  ),
                if (!_isPremium)
                  _actionTile(
                    Icons.workspace_premium_outlined,
                    l10n.settingsUpgradeToPremium,
                    onTap: _openPaywall,
                  ),

                _sectionLabel(l10n.settingsSectionNotifications),
                _infoTile(
                  Icons.notifications_none,
                  l10n.settingsReachOutFrequency,
                  _frequencyLabel(_notificationFrequency),
                ),
                _actionTile(
                  Icons.tune,
                  l10n.commonChange,
                  onTap: _showFrequencyDialog,
                ),

                _sectionLabel(l10n.settingsSectionLocation),
                _infoTile(
                  Icons.location_on_outlined,
                  l10n.settingsYourLocation,
                  _locationSummary(),
                ),
                _actionTile(
                  Icons.edit_location_alt_outlined,
                  _country == null && _region == null && _district == null
                      ? l10n.settingsSetLocation
                      : l10n.settingsEditLocation,
                  onTap: _showLocationEditDialog,
                ),

                _sectionLabel(l10n.settingsSectionMemory),
                _switchTile(
                  Icons.psychology_outlined,
                  l10n.settingsLetOllieRemember,
                  _memoryEnabled,
                  _toggleMemory,
                ),
                _actionTile(
                  Icons.auto_stories_outlined,
                  l10n.settingsManageMemories,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MemoriesScreen()),
                  ),
                ),
                _actionTile(
                  Icons.refresh,
                  l10n.settingsClearMemory,
                  onTap: _confirmClearMemory,
                  destructive: true,
                ),

                _sectionLabel(l10n.settingsSectionLanguage),
                _infoTile(Icons.language, l10n.settingsChooseLanguage, _currentLanguageLabel()),
                _actionTile(
                  Icons.tune,
                  l10n.commonChange,
                  onTap: _showLanguageDialog,
                ),

                _sectionLabel(l10n.settingsSectionAbout),
                _infoTile(Icons.info_outline, l10n.settingsAboutOllie, l10n.settingsMadeInRwanda),
                _actionTile(
                  Icons.privacy_tip_outlined,
                  l10n.settingsPrivacyPolicy,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
                  ),
                ),
                _actionTile(
                  Icons.description_outlined,
                  l10n.settingsTermsOfService,
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
