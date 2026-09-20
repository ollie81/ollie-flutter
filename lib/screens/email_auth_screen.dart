import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';
import 'onboarding_screen.dart';

enum _EmailAuthMode { login, signup, forgot }

// Email/password sign-in/signup/forgot-password -- same shape as
// phone_auth_screen.dart, just an email field instead of the
// phone/country picker, and OTP verification is a code emailed via
// SendGrid (see auth.py's /auth/email/* routes) rather than SMS.
class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({super.key});

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  _EmailAuthMode _mode = _EmailAuthMode.login;
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final ApiService _api = ApiService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _otpSent = false;
  bool _signupOtpSent = false;
  final TextEditingController _signupOtpController = TextEditingController();

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }

  // ============================================================
  // SUBMIT HANDLER
  // ============================================================

  Future<void> _handleSubmit() async {
    final l10n = AppLocalizations.of(context)!;
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      _showError(l10n.emailAuthErrorEnterEmail);
      return;
    }
    if (!_isValidEmail(email)) {
      _showError(l10n.emailAuthErrorInvalidEmail);
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_mode == _EmailAuthMode.login) {
        if (_passwordController.text.isEmpty) {
          _showError(l10n.emailAuthErrorEnterPassword);
          return;
        }
        await _api.emailLogin(email: email, password: _passwordController.text);
        await _saveAndNavigate(email, isNewUser: false);
      } else if (_mode == _EmailAuthMode.signup) {
        if (_passwordController.text.length < 6) {
          _showError(l10n.emailAuthErrorPasswordTooShort);
          return;
        }
        if (_passwordController.text != _confirmController.text) {
          _showError(l10n.emailAuthErrorPasswordMismatch);
          return;
        }

        if (!_signupOtpSent) {
          await _api.emailRequestSignupOtp(email: email);
          setState(() => _signupOtpSent = true);
          _showSuccess(l10n.emailAuthCodeSent);
        } else {
          if (_signupOtpController.text.trim().isEmpty) {
            _showError(l10n.emailAuthEnterCodeSentHint);
            return;
          }
          await _api.emailSignup(
            email: email,
            password: _passwordController.text,
            otp: _signupOtpController.text.trim(),
          );
          await _saveAndNavigate(email, isNewUser: true);
        }
      } else if (_mode == _EmailAuthMode.forgot) {
        if (!_otpSent) {
          await _api.emailForgotPassword(email: email);
          setState(() => _otpSent = true);
          _showSuccess(l10n.emailAuthCodeSent);
        } else {
          if (_otpController.text.isEmpty) {
            _showError(l10n.emailAuthErrorEnterCode);
            return;
          }
          if (_passwordController.text.length < 6) {
            _showError(l10n.emailAuthErrorPasswordTooShort);
            return;
          }
          await _api.emailResetPassword(
            email: email,
            otp: _otpController.text.trim(),
            newPassword: _passwordController.text,
          );
          _showSuccess(l10n.emailAuthPasswordResetSuccess);
          setState(() {
            _mode = _EmailAuthMode.login;
            _otpSent = false;
            _otpController.clear();
            _passwordController.clear();
          });
        }
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // NAVIGATION HELPERS
  // ============================================================

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

  Future<void> _saveAndNavigate(String email, {required bool isNewUser}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', email);
    await prefs.setBool('is_logged_in', true);
    await _registerFcmToken();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => isNewUser
              ? OnboardingScreen(phoneNumber: email)
              : HomeScreen(phoneNumber: email),
        ),
      );
    }
  }

  // ============================================================
  // SNACKBAR HELPERS
  // ============================================================

  void _showError(String message) {
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(color: Colors.white))),
          ],
        ),
        backgroundColor: const Color(0xFF43A047),
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == _EmailAuthMode.login
                        ? l10n.emailAuthWelcomeBack
                        : (_mode == _EmailAuthMode.signup ? l10n.emailAuthCreateAccount : l10n.emailAuthResetPasswordTitle),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == _EmailAuthMode.login
                        ? l10n.emailAuthSignInSubtitle
                        : (_mode == _EmailAuthMode.signup ? l10n.emailAuthJoinSubtitle : l10n.emailAuthForgotSubtitle),
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  _buildTextField(
                    controller: _emailController,
                    hint: l10n.emailAuthEmailHint,
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),

                  if (_mode != _EmailAuthMode.forgot || (_mode == _EmailAuthMode.forgot && _otpSent)) ...[
                    _buildTextField(
                      controller: _passwordController,
                      hint: _mode == _EmailAuthMode.forgot ? l10n.emailAuthNewPasswordHint : l10n.emailAuthPasswordHint,
                      icon: Icons.lock,
                      obscure: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white.withOpacity(0.3),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_mode == _EmailAuthMode.signup) ...[
                    _buildTextField(
                      controller: _confirmController,
                      hint: l10n.emailAuthConfirmPasswordHint,
                      icon: Icons.lock_outline,
                      obscure: _obscureConfirm,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                          color: Colors.white.withOpacity(0.3),
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_mode == _EmailAuthMode.signup && _signupOtpSent) ...[
                    _buildTextField(
                      controller: _signupOtpController,
                      hint: l10n.emailAuthEnterCodeSentHint,
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_mode == _EmailAuthMode.forgot && _otpSent) ...[
                    _buildTextField(
                      controller: _otpController,
                      hint: l10n.emailAuthEnterCodeSentHint,
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  GestureDetector(
                    onTap: _isLoading ? null : _handleSubmit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          colors: _isLoading
                              ? [const Color(0xFFFF8C6B).withOpacity(0.5), const Color(0xFFE86B4A).withOpacity(0.5)]
                              : const [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF8C6B).withOpacity(0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              ),
                            )
                          : Text(
                              _mode == _EmailAuthMode.login
                                  ? l10n.emailAuthSignIn
                                  : (_mode == _EmailAuthMode.signup
                                      ? (_signupOtpSent ? l10n.emailAuthVerifyAndCreateAccount : l10n.emailAuthSendCode)
                                      : (_otpSent ? l10n.emailAuthResetPasswordTitle : l10n.emailAuthSendCode)),
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_mode != _EmailAuthMode.forgot)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _mode == _EmailAuthMode.login ? l10n.emailAuthNoAccount : l10n.emailAuthHaveAccount,
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _mode = _mode == _EmailAuthMode.login ? _EmailAuthMode.signup : _EmailAuthMode.login;
                              _passwordController.clear();
                              _confirmController.clear();
                              _signupOtpSent = false;
                              _signupOtpController.clear();
                            });
                          },
                          child: Text(
                            _mode == _EmailAuthMode.login ? l10n.emailAuthSignUp : l10n.emailAuthSignIn,
                            style: const TextStyle(color: Color(0xFFFF8C6B), fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),

                  if (_mode == _EmailAuthMode.login)
                    Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _mode = _EmailAuthMode.forgot;
                            _otpSent = false;
                            _otpController.clear();
                            _passwordController.clear();
                          });
                        },
                        child: Text(l10n.emailAuthForgotPassword, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ),
                    ),

                  if (_mode == _EmailAuthMode.forgot)
                    Center(
                      child: TextButton(
                        onPressed: () {
                          setState(() {
                            _mode = _EmailAuthMode.login;
                            _otpSent = false;
                            _otpController.clear();
                            _passwordController.clear();
                          });
                        },
                        child: Text(l10n.emailAuthBackToLogin, style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ),
                    ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffixIcon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: const Color(0xFFFF8C6B).withOpacity(0.7), size: 20),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }
}
