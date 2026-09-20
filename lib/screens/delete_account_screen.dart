import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';
import 'auth_screen.dart';

// Deliberately its own screen, not a single confirm dialog off the
// Settings list -- deleting an account that holds real personal
// history (every conversation, everything Ollie's learned) shouldn't
// be one accidental tap away. The typed confirmation phrase is the
// actual gate; the backend also schedules a 14-day grace period
// rather than deleting anything the moment this screen submits (see
// POST /settings/delete-account) -- logging back in during that
// window restores the account automatically, no separate "undo"
// flow needed here.
//
// _confirmationPhrase stays the literal English word "DELETE" in
// every language -- settings.py's DELETE_ACCOUNT_CONFIRMATION_PHRASE
// is a fixed backend constant, so translating it would silently
// break the confirmation check.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const String _confirmationPhrase = 'DELETE';

  final ApiService _api = ApiService();
  final TextEditingController _controller = TextEditingController();
  bool _isDeleting = false;

  bool get _canDelete => !_isDeleting && _controller.text.trim() == _confirmationPhrase;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openSubscriptions() async {
    try {
      await launchUrl(
        Uri.parse('https://play.google.com/store/account/subscriptions'),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      // Best-effort -- this screen's main action doesn't depend on it.
    }
  }

  String _formatDate(BuildContext context, String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return AppLocalizations.of(context)!.deleteAccountInFourteenDays;
    return DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(date);
  }

  Future<void> _submit() async {
    if (!_canDelete) return;
    setState(() => _isDeleting = true);
    try {
      final scheduledFor = await _api.requestAccountDeletion();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1035),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            l10n.deleteAccountScheduledTitle,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          content: Text(
            l10n.deleteAccountScheduledBody(_formatDate(context, scheduledFor)),
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonOk, style: const TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isDeleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFE53935),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0D0F1A), Color(0xFF151829), Color(0xFF1A1035)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(l10n),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWarningIcon(),
                      const SizedBox(height: 20),
                      Text(
                        l10n.deleteAccountNotReversible,
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.deleteAccountRemovesIntro,
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      _buildLossItem(l10n.deleteAccountLossConversations),
                      _buildLossItem(l10n.deleteAccountLossMemory),
                      _buildLossItem(l10n.deleteAccountLossStreak),
                      const SizedBox(height: 20),
                      _buildInfoCard(
                        icon: Icons.schedule_rounded,
                        text: l10n.deleteAccountGracePeriodInfo,
                      ),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        icon: Icons.payment_rounded,
                        text: l10n.deleteAccountSubscriptionInfo,
                        actionLabel: l10n.deleteAccountOpenSubscriptions,
                        onAction: _openSubscriptions,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        l10n.deleteAccountTypeToConfirm(_confirmationPhrase),
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.white.withOpacity(0.07),
                          border: Border.all(color: Colors.white.withOpacity(0.15)),
                        ),
                        child: TextField(
                          controller: _controller,
                          enabled: !_isDeleting,
                          style: const TextStyle(color: Colors.white, letterSpacing: 1),
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            hintText: _confirmationPhrase,
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _canDelete ? _submit : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53935),
                            disabledBackgroundColor: const Color(0xFFE53935).withOpacity(0.2),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                          ),
                          child: _isDeleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                )
                              : Text(
                                  l10n.deleteAccountConfirmButton,
                                  style: TextStyle(
                                    color: _canDelete ? Colors.white : Colors.white.withOpacity(0.4),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: _isDeleting ? null : () => Navigator.pop(context),
          ),
          Text(
            l10n.deleteAccountTitle,
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningIcon() {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE53935).withOpacity(0.15),
        border: Border.all(color: const Color(0xFFE53935).withOpacity(0.3)),
      ),
      child: const Icon(Icons.warning_rounded, color: Color(0xFFE53935), size: 30),
    );
  }

  Widget _buildLossItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.3), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String text,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.05),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFFF8C6B), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13, height: 1.4)),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel,
                style: const TextStyle(
                  color: Color(0xFFFF8C6B),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
