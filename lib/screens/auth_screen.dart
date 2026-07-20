import 'package:flutter/material.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

enum AuthMode { login, signup, forgot }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthMode _mode = AuthMode.login;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final ApiService _api = ApiService();

  String _countryCode = '+250';
  String _fullPhoneNumber = '';

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _otpSent = false;
  bool _signupOtpSent = false;
  final TextEditingController _signupOtpController = TextEditingController();

  // Must match the Web client ID your backend (auth.py) verifies
  // Google ID tokens against. Without this, Android issues a token
  // scoped to the Android OAuth client instead, and the backend's
  // id_token.verify_oauth2_token() rejects it with an audience
  // mismatch — Google Sign-In fails even with a correct SHA-1.
  static const String _googleServerClientId =
    '431417738635-f3ipimjqmdldh0lfsf44f70irif9eoho.apps.googleusercontent.com';
  // ============================================================
  // SUBMIT HANDLER
  // ============================================================

  Future<void> _handleSubmit() async {
    final phone = _fullPhoneNumber;

    if (phone.isEmpty) {
      _showError('Enter phone number');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_mode == AuthMode.login) {
        if (_passwordController.text.isEmpty) {
          _showError('Enter password');
          return;
        }
        await _api.login(
          phoneNumber: phone,
          password: _passwordController.text,
        );
        await _saveAndNavigate(phone);
      } else if (_mode == AuthMode.signup) {
        if (_passwordController.text.length < 6) {
          _showError('Password must be at least 6 characters');
          return;
        }
        if (_passwordController.text != _confirmController.text) {
          _showError('Passwords do not match');
          return;
        }

        if (!_signupOtpSent) {
          await _api.requestSignupOtp(phoneNumber: phone);
          setState(() => _signupOtpSent = true);
          _showSuccess('OTP sent to your phone');
        } else {
          if (_signupOtpController.text.trim().isEmpty) {
            _showError('Enter the OTP sent to your phone');
            return;
          }
          await _api.signup(
            phoneNumber: phone,
            password: _passwordController.text,
            otp: _signupOtpController.text.trim(),
          );
          await _saveAndNavigate(phone);
        }
      } else if (_mode == AuthMode.forgot) {
        if (!_otpSent) {
          await _api.forgotPassword(phoneNumber: phone);
          setState(() => _otpSent = true);
          _showSuccess('OTP sent to your phone');
        } else {
          if (_otpController.text.isEmpty) {
            _showError('Enter the OTP');
            return;
          }
          if (_passwordController.text.length < 6) {
            _showError('Password must be at least 6 characters');
            return;
          }
          await _api.resetPassword(
            phoneNumber: phone,
            otp: _otpController.text.trim(),
            newPassword: _passwordController.text,
          );
          _showSuccess('Password reset! Login with new password.');
          setState(() {
            _mode = AuthMode.login;
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

  Future<void> _saveAndNavigate(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', phone);
    await prefs.setBool('is_logged_in', true);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(phoneNumber: phone),
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

      if (googleUser == null) {
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

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

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(phoneNumber: googleUser.email),
          ),
        );
      }
    } catch (e) {
      _showError('Google Sign-In failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
                  // Orb
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
                    child: const Center(
                      child: Text('🙂', style: TextStyle(fontSize: 44)),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Title
                  Text(
                    _mode == AuthMode.login
                        ? 'Welcome Back'
                        : (_mode == AuthMode.signup
                            ? 'Create Account'
                            : 'Reset Password'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mode == AuthMode.login
                        ? 'Sign in to continue'
                        : (_mode == AuthMode.signup
                            ? 'Join Ollie today'
                            : 'Enter your phone number'),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Phone Field with Country Picker
                  IntlPhoneField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      hintText: 'Enter phone number',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.07),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFFFF8C6B),
                          width: 2,
                        ),
                      ),
                      prefixIcon: Icon(
                        Icons.phone_android,
                        color: const Color(0xFFFF8C6B).withOpacity(0.7),
                        size: 20,
                      ),
                    ),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    dropdownIconPosition: IconPosition.trailing,
                    dropdownIcon: Icon(
                      Icons.arrow_drop_down,
                      color: Colors.white.withOpacity(0.5),
                    ),
                    flagsButtonPadding: const EdgeInsets.all(8),
                    onChanged: (PhoneNumber number) {
                      setState(() {
                        _countryCode = number.countryCode;
                        _fullPhoneNumber = number.completeNumber;
                      });
                    },
                    onCountryChanged: (country) {
                      setState(() {
                        _countryCode = country.dialCode;
                      });
                    },
                    initialCountryCode: 'RW',
                  ),
                  const SizedBox(height: 14),

                  // Password Field
                  if (_mode != AuthMode.forgot || (_mode == AuthMode.forgot && _otpSent)) ...[
                    _buildTextField(
                      controller: _passwordController,
                      hint: _mode == AuthMode.forgot ? 'New password' : 'Password',
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

                  // Confirm Password (signup only)
                  if (_mode == AuthMode.signup) ...[
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

                  // Signup OTP field
                  if (_mode == AuthMode.signup && _signupOtpSent) ...[
                    _buildTextField(
                      controller: _signupOtpController,
                      hint: 'Enter the code sent to your phone',
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // OTP Field for forgot password
                  if (_mode == AuthMode.forgot && _otpSent) ...[
                    _buildTextField(
                      controller: _otpController,
                      hint: 'Enter OTP',
                      icon: Icons.pin,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Submit Button
                  GestureDetector(
                    onTap: _isLoading ? null : _handleSubmit,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        gradient: LinearGradient(
                          colors: _isLoading
                              ? [
                                  const Color(0xFFFF8C6B).withOpacity(0.5),
                                  const Color(0xFFE86B4A).withOpacity(0.5),
                                ]
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              _mode == AuthMode.login
                                  ? 'Sign In'
                                  : (_mode == AuthMode.signup
                                      ? (_signupOtpSent ? 'Verify & Create Account' : 'Send OTP')
                                      : (_otpSent ? 'Reset Password' : 'Send OTP')),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // DIVIDER + GOOGLE BUTTON
                  if (_mode != AuthMode.forgot) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: Colors.white.withOpacity(0.15),
                            thickness: 1,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            'or continue with',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: Colors.white.withOpacity(0.15),
                            thickness: 1,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Google Sign-In Button
                    GestureDetector(
                      onTap: _isLoading ? null : _handleGoogleLogin,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          color: Colors.white.withOpacity(0.07),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.15),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Image.network(
                              'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                              height: 24,
                              width: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              _mode == AuthMode.login
                                  ? 'Sign in with Google'
                                  : 'Sign up with Google',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Switch login/signup
                  if (_mode != AuthMode.forgot)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _mode == AuthMode.login
                              ? "Don't have an account?"
                              : "Already have an account?",
                          style: TextStyle(color: Colors.white.withOpacity(0.5)),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _mode = _mode == AuthMode.login
                                  ? AuthMode.signup
                                  : AuthMode.login;
                              _passwordController.clear();
                              _confirmController.clear();
                              _signupOtpSent = false;
                              _signupOtpController.clear();
                            });
                          },
                          child: Text(
                            _mode == AuthMode.login ? 'Sign Up' : 'Sign In',
                            style: const TextStyle(
                              color: Color(0xFFFF8C6B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                  // Forgot password link
                  if (_mode == AuthMode.login)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _mode = AuthMode.forgot;
                          _otpSent = false;
                          _otpController.clear();
                          _passwordController.clear();
                        });
                      },
                      child: Text(
                        'Forgot password?',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
                      ),
                    ),

                  // Back to login
                  if (_mode == AuthMode.forgot)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _mode = AuthMode.login;
                          _otpSent = false;
                          _otpController.clear();
                          _passwordController.clear();
                        });
                      },
                      child: Text(
                        'Back to Login',
                        style: TextStyle(color: Colors.white.withOpacity(0.5)),
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
          prefixIcon: Icon(
            icon,
            color: const Color(0xFFFF8C6B).withOpacity(0.7),
            size: 20,
          ),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }
}
