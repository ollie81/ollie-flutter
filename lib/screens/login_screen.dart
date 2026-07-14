import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final ApiService _api = ApiService();

  // Full E.164 number (e.g. +250788123456) — set once the user
  // picks a country and enters a valid number for that country.
  String? _fullPhoneNumber;
  bool _phoneValid = false;

  bool _isLoading = false;
  bool _isNewUser = false;
  bool _obscurePassword = true;

  // Signup requires OTP verification before the account is
  // created — mirrors the flow in auth_screen.dart.
  bool _signupOtpSent = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _submit() async {
    final password = _passwordController.text.trim();

    if (!_phoneValid || _fullPhoneNumber == null) {
      _showError('Enter a valid phone number for your country');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isNewUser) {
        if (password.length < 6) {
          _showError('Password must be at least 6 characters');
          return;
        }

        if (!_signupOtpSent) {
          // Step 1: send OTP, account not created yet.
          await _api.requestSignupOtp(phoneNumber: _fullPhoneNumber!);
          setState(() => _signupOtpSent = true);
          _showSuccess('OTP sent to your phone');
          return;
        } else {
          // Step 2: verify OTP + create the account.
          if (_otpController.text.trim().isEmpty) {
            _showError('Enter the OTP sent to your phone');
            return;
          }
          await _api.signup(
            phoneNumber: _fullPhoneNumber!,
            password: password,
            otp: _otpController.text.trim(),
          );
        }
      } else {
        if (password.length < 6) {
          _showError('Password must be at least 6 characters');
          return;
        }
        await _api.login(phoneNumber: _fullPhoneNumber!, password: password);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phoneNumber', _fullPhoneNumber!);
      await prefs.setBool('is_logged_in', true);

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(phoneNumber: _fullPhoneNumber!)),
        );
      }
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

                  // Ollie orb
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withOpacity(0.5),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text('🙂', style: TextStyle(fontSize: 55)),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'Welcome to Ollie',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isNewUser
                        ? 'Create your account to get started'
                        : 'Your emotional companion is waiting',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 48),

                  // Phone field with country code picker
                  _buildPhoneField(),
                  const SizedBox(height: 14),

                  // Password field
                  _buildPasswordField(),
                  const SizedBox(height: 14),

                  // OTP field — only for signup, after OTP is sent
                  if (_isNewUser && _signupOtpSent) ...[
                    _buildOtpField(),
                    const SizedBox(height: 14),
                  ],

                  const SizedBox(height: 14),

                  // Submit button
                  GestureDetector(
                    onTap: _isLoading ? null : _submit,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
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
                            blurRadius: 16,
                            spreadRadius: 0,
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
                              _isNewUser
                                  ? (_signupOtpSent ? 'Verify & Create Account' : 'Send OTP')
                                  : 'Login',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Toggle login/signup
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isNewUser = !_isNewUser;
                        _passwordController.clear();
                        _otpController.clear();
                        _signupOtpSent = false;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Text(
                        _isNewUser
                            ? 'Already have an account? Login'
                            : "Don't have an account? Sign up",
                        style: TextStyle(
                          color: const Color(0xFFFF8C6B).withOpacity(0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

  Widget _buildPhoneField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: IntlPhoneField(
        initialCountryCode: 'RW',
        style: const TextStyle(color: Colors.white, fontSize: 15),
        dropdownTextStyle: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Phone number',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
        dropdownIconPosition: IconPosition.trailing,
        flagsButtonPadding: const EdgeInsets.only(left: 12),
        onChanged: (phone) {
          setState(() {
            _fullPhoneNumber = phone.completeNumber;
            _phoneValid = phone.isValidNumber();
          });
        },
      ),
    );
  }

  Widget _buildPasswordField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Password',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(Icons.lock_outline_rounded,
              color: const Color(0xFFFF8C6B).withOpacity(0.7), size: 20),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            child: Icon(
              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              color: Colors.white.withOpacity(0.3),
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }

  Widget _buildOtpField() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.07),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: TextField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Enter the code sent to your phone',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(Icons.pin,
              color: const Color(0xFFFF8C6B).withOpacity(0.7), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        ),
      ),
    );
  }
}
