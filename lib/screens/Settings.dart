import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'auth_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String phoneNumber;
  const SettingsScreen({super.key, required this.phoneNumber});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();

  bool _loading = true;
  bool _notificationsEnabled = true;
  int _messagesUsedToday = 0;
  int _dailyLimit = 20;
  bool _hasActiveAdBonus = false;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _loadUsage();
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
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    try {
      await _api.setNotificationsEnabled(value);
    } catch (e) {
      // revert on failure
      if (!mounted) return;
      setState(() => _notificationsEnabled = !value);
      _showError('Could not update notification setting');
    }
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

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await _showConfirmDialog(
      title: 'Delete account?',
      message:
          'This permanently deletes your account and everything Ollie remembers '
          'about you. This cannot be undone.',
      confirmLabel: 'Delete account',
      isDestructive: true,
    );
    if (confirmed != true) return;

    try {
      await _api.deleteAccount();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      _showError('Could not delete account, try again');
    }
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
                  Icons.delete_outline,
                  'Delete account',
                  onTap: _confirmDeleteAccount,
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
                  _isPremium ? 'Premium' : 'Free',
                ),

                _sectionLabel('Notifications'),
                _switchTile(
                  Icons.notifications_none,
                  'Push notifications',
                  _notificationsEnabled,
                  _toggleNotifications,
                ),

                _sectionLabel('Privacy'),
                _actionTile(
                  Icons.refresh,
                  'Clear Ollie\'s memory of you',
                  onTap: _confirmClearMemory,
                  destructive: true,
                ),

                _sectionLabel('About'),
                _infoTile(Icons.info_outline, 'Ollie', 'Made in Rwanda 🇷🇼'),
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
