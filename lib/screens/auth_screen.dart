import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'email_auth_screen.dart';
import 'phone_auth_screen.dart';
import 'home_screen.dart';

// Landing screen for signing in -- picks between the three methods,
// then hands off to a dedicated screen for whichever one has an
// actual form (email, phone). Google is a single native picker, not
// a form, so it stays a button right here rather than getting its
// own screen with nothing else on it.
//
// Google and Email are the two prominent options up top since most
// users already have one or the other; Phone (SMS OTP) is still
// fully supported, just secondary -- for anyone without email or
// where phone sign-in is more natural.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final ApiService _api = ApiService();
  bool _isLoading = false;

  // Must match the Web client ID your backend (auth.py) verifies
  // Google ID tokens against. Without this, Android issues a token
  // scoped to the Android OAuth client instead, and the backend's
  // id_token.verify_oauth2_token() rejects it with an audience
  // mismatch — Google Sign-In fails even with a correct SHA-1.
  static const String _googleServerClientId =
      '431417738635-f3ipimjqmdldh0lfsf44f70irif9eoho.apps.googleusercontent.com';

  // ============================================================
  // GOOGLE LOGIN
  // ============================================================

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);

    try {
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
        serverClientId: _googleServerClientId,
      );

      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        _showError('Google Sign-In failed: no ID token returned');
        return;
      }

      // googleLogin() already saves tokens to secure storage
      // internally — no need to duplicate that here.
      await _api.googleLogin(idToken: idToken);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('phoneNumber', googleUser.email);
      await _registerFcmToken();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(phoneNumber: googleUser.email)),
        );
      }
    } catch (e) {
      _showError('Google Sign-In failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _registerFcmToken() async {
    try {
      final fcmToken = await NotificationService.getFCMToken();
      if (fcmToken != null) {
        await _api.saveFcmToken(fcmToken);
      }
    } catch (_) {
      // Best-effort — a failed registration here shouldn't block
      // the user from getting into the app.
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: const Color(0xFFE53935),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withOpacity(0.5),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(child: Text('🙂', style: TextStyle(fontSize: 44))),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Welcome to Ollie',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue',
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 44),

                  // Google -- prominent, most users have one.
                  _primaryButton(
                    label: 'Continue with Google',
                    icon: Image.network(
                      'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                      height: 22,
                      width: 22,
                    ),
                    onTap: _handleGoogleLogin,
                    filled: false,
                  ),
                  const SizedBox(height: 12),

                  // Email -- prominent, the other option most people
                  // already expect to be able to use.
                  _primaryButton(
                    label: 'Continue with Email',
                    icon: const Icon(Icons.email_outlined, color: Colors.white, size: 20),
                    onTap: _isLoading
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const EmailAuthScreen()),
                            ),
                    filled: true,
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.15), thickness: 1)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.15), thickness: 1)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Phone -- secondary, still fully supported.
                  TextButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PhoneAuthScreen()),
                            ),
                    icon: Icon(Icons.phone_android, color: Colors.white.withOpacity(0.6), size: 18),
                    label: Text(
                      'Continue with phone number',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),

                  if (_isLoading) ...[
                    const SizedBox(height: 20),
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required String label,
    required Widget icon,
    required VoidCallback? onTap,
    required bool filled,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: filled
              ? LinearGradient(
                  colors: _isLoading
                      ? [const Color(0xFFFF8C6B).withOpacity(0.5), const Color(0xFFE86B4A).withOpacity(0.5)]
                      : const [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                )
              : null,
          color: filled ? null : Colors.white.withOpacity(0.07),
          border: filled ? null : Border.all(color: Colors.white.withOpacity(0.15)),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF8C6B).withOpacity(0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: filled ? Colors.white : Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
