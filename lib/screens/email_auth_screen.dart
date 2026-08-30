import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';

enum _EmailAuthMode { login, signup, forgot }

// Email/password sign-in/signup/forgot-password -- same shape as
// phone_auth_screen.dart, just an email field instead of the
// phone/country picker, and OTP verification is a code emailed via
// Resend (see auth.py's /auth/email/* routes) rather than SMS.
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
  DateTime? _dateOfBirth;

  static const int _minSignupAgeYears = 13;

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }

  // ============================================================
  // SUBMIT HANDLER
  // ============================================================

  Future<void> _handleSubmit() async {
    final email = _emailController.text.trim().toLowerCase();

    if (email.isEmpty) {
      _showError('Enter your email');
      return;
    }
    if (!_isValidEmail(email)) {
      _showError('Enter a valid email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_mode == _EmailAuthMode.login) {
        if (_passwordController.text.isEmpty) {
          _showError('Enter password');
          return;
        }
        await _api.emailLogin(email: email, password: _passwordController.text);
        await _saveAndNavigate(email);
      } else if (_mode == _EmailAuthMode.signup) {
        if (_passwordController.text.length < 6) {
          _showError('Password must be at least 6 characters');
          return;
        }
        if (_passwordController.text != _confirmController.text) {
          _showError('Passwords do not match');
          return;
        }
        if (_dateOfBirth == null) {
          _showError('Enter your date of birth');
          return;
        }
        if (_calculateAge(_dateOfBirth!) < _minSignupAgeYears) {
          _showError('You must be at least $_minSignupAgeYears years old to create an account');
          return;
        }

        if (!_signupOtpSent) {
          await _api.emailRequestSignupOtp(email: email);
          setState(() => _signupOtpSent = true);
          _showSuccess('Code sent to your email');
        } else {
          if (_signupOtpController.text.trim().isEmpty) {
            _showError('Enter the code sent to your email');
            return;
          }
          await _api.emailSignup(
            email: email,
            password: _passwordController.text,
            otp: _signupOtpController.text.trim(),
            dateOfBirth: _formatDate(_dateOfBirth!),
          );
          await _saveAndNavigate(email);
        }
      } else if (_mode == _EmailAuthMode.forgot) {
        if (!_otpSent) {
          await _api.emailForgotPassword(email: email);
          setState(() => _otpSent = true);
          _showSuccess('Code sent to your email');
        } else {
          if (_otpController.text.isEmpty) {
            _showError('Enter the code');
            return;
          }
          if (_passwordController.text.length < 6) {
            _showError('Password must be at least 6 characters');
            return;
          }
          await _api.emailResetPassword(
            email: email,
            otp: _otpController.text.trim(),
            newPassword: _passwordController.text,
          );
          _showSuccess('Password reset! Login with new password.');
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

  Future<void> _saveAndNavigate(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', email);
    await prefs.setBool('is_logged_in', true);
    await _registerFcmToken();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => HomeScreen(phoneNumber: email)),
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
                        ? 'Welcome Back'
                        : (_mode == _EmailAuthMode.signup ? 'Create Account' : 'Reset Password'),
                    style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == _EmailAuthMode.login
                        ? 'Sign in with your email'
                        : (_mode == _EmailAuthMode.signup ? 'Join Ollie today' : 'Enter your email'),
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  _buildTextField(
                    controller: _emailController,
                    hint: 'Enter your email',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),

                  if (_mode != _EmailAuthMode.forgot || (_mode == _EmailAuthMode.forgot && _otpSent)) ...[
                    _buildTextField(
                      controller: _passwordController,
                      hint: _mode == _EmailAuthMode.forgot ? 'New password' : 'Password',
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
                      hint: 'Confirm password',
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

                  if (_mode == _EmailAuthMode.signup) ...[
                    GestureDetector(
                      onTap: _isLoading ? null : _pickDateOfBirth,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: Colors.white.withOpacity(0.07),
                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.cake_outlined, color: const Color(0xFFFF8C6B).withOpacity(0.7), size: 20),
                            const SizedBox(width: 12),
                            Text(
                              _dateOfBirth == null ? 'Date of birth' : _formatDate(_dateOfBirth!),
                              style: TextStyle(
                                color: _dateOfBirth == null ? Colors.white.withOpacity(0.3) : Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_mode == _EmailAuthMode.signup && _signupOtpSent) ...[
                    _buildTextField(
                      controller: _signupOtpController,
                      hint: 'Enter the code sent to your email',
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  if (_mode == _EmailAuthMode.forgot && _otpSent) ...[
                    _buildTextField(
                      controller: _otpController,
                      hint: 'Enter the code sent to your email',
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
                                  ? 'Sign In'
                                  : (_mode == _EmailAuthMode.signup
                                      ? (_signupOtpSent ? 'Verify & Create Account' : 'Send Code')
                                      : (_otpSent ? 'Reset Password' : 'Send Code')),
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
                          _mode == _EmailAuthMode.login ? "Don't have an account?" : "Already have an account?",
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
                              _dateOfBirth = null;
                            });
                          },
                          child: Text(
                            _mode == _EmailAuthMode.login ? 'Sign Up' : 'Sign In',
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
                        child: Text('Forgot password?', style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
                        child: Text('Back to Login', style: TextStyle(color: Colors.white.withOpacity(0.5))),
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
