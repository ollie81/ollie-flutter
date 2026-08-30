import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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

  String _formatDate(String iso) {
    final date = DateTime.tryParse(iso)?.toLocal();
    if (date == null) return 'in 14 days';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  Future<void> _submit() async {
    if (!_canDelete) return;
    setState(() => _isDeleting = true);
    try {
      final scheduledFor = await _api.requestAccountDeletion();
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1A1035),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Account scheduled for deletion',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
          ),
          content: Text(
            "Everything will be permanently deleted on ${_formatDate(scheduledFor)}. "
            "Changed your mind? Just log back in before then and it's restored automatically.",
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600)),
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
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWarningIcon(),
                      const SizedBox(height: 20),
                      const Text(
                        "This isn't reversible after 14 days",
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Deleting your account permanently removes:',
                        style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
                      ),
                      const SizedBox(height: 12),
                      _buildLossItem('Every conversation with Ollie'),
                      _buildLossItem("Everything Ollie's learned about you"),
                      _buildLossItem('Your streak and relationship journey'),
                      const SizedBox(height: 20),
                      _buildInfoCard(
                        icon: Icons.schedule_rounded,
                        text: "You'll have 14 days to change your mind — just log back in during "
                            "that window and your account, with everything in it, comes right back.",
                      ),
                      const SizedBox(height: 12),
                      _buildInfoCard(
                        icon: Icons.payment_rounded,
                        text: 'This does NOT cancel an active Play Store subscription — cancel that separately first.',
                        actionLabel: 'Open Play Store subscriptions',
                        onAction: _openSubscriptions,
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Type "$_confirmationPhrase" to confirm',
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
                                  'Delete my account',
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

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
            onPressed: _isDeleting ? null : () => Navigator.pop(context),
          ),
          const Text(
            'Delete Account',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
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
