import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String _resetOtp = '';
  bool _otpSent = false;

  Future<void> _handleSubmit() async {
    if (_phoneController.text.trim().isEmpty) {
      _showError('Enter phone number');
      return;
    }

    if (_mode == AuthMode.login) {
      if (_passwordController.text.isEmpty) {
        _showError('Enter password');
        return;
      }
      // TODO: Call your login API
      _fakeLogin();
    } 
    else if (_mode == AuthMode.signup) {
      if (_passwordController.text.length < 6) {
        _showError('Password must be at least 6 characters');
        return;
      }
      if (_passwordController.text != _confirmController.text) {
        _showError('Passwords do not match');
        return;
      }
      // TODO: Call your signup API
      _fakeSignup();
    }
    else if (_mode == AuthMode.forgot) {
      if (!_otpSent) {
        // Send OTP
        _resetOtp = '123456';
        setState(() => _otpSent = true);
        _showError('Demo OTP: 123456');
      } else {
        // Verify OTP and reset password
        if (_otpController.text != _resetOtp) {
          _showError('Wrong OTP');
          return;
        }
        if (_passwordController.text.length < 6) {
          _showError('Password must be at least 6 characters');
          return;
        }
        // TODO: Call reset password API
        _showError('Password reset successfully! Login with new password.');
        setState(() {
          _mode = AuthMode.login;
          _otpSent = false;
          _otpController.clear();
          _passwordController.clear();
        });
      }
    }
  }

  void _fakeLogin() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', _phoneController.text.trim());
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(phoneNumber: _phoneController.text.trim()),
        ),
      );
    }
  }

  void _fakeSignup() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 1));
    setState(() => _isLoading = false);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phoneNumber', _phoneController.text.trim());
    
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => HomeScreen(phoneNumber: _phoneController.text.trim()),
        ),
      );
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Orb
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C6B).withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text('🙂', style: TextStyle(fontSize: 40)),
                  ),
                ),
                const SizedBox(height: 24),
                // Title
                Text(
                  _mode == AuthMode.login
                      ? 'Welcome Back'
                      : (_mode == AuthMode.signup ? 'Create Account' : 'Reset Password'),
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
                      : (_mode == AuthMode.signup ? 'Join Ollie today' : 'Enter your phone number'),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 32),
                // Phone Field
                _buildTextField(
                  controller: _phoneController,
                  hint: 'Phone number',
                  icon: Icons.phone_android,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                // Password Field (not for forgot OTP stage)
                if (_mode != AuthMode.forgot || (_mode == AuthMode.forgot && _otpSent)) ...[
                  _buildTextField(
                    controller: _passwordController,
                    hint: _mode == AuthMode.forgot ? 'New password' : 'Password',
                    icon: Icons.lock,
                    obscure: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Confirm Password (signup only)
                if (_mode == AuthMode.signup) ...[
                  _buildTextField(
                    controller: _confirmController,
                    hint: 'Confirm password',
                    icon: Icons.lock_outline,
                    obscure: _obscureConfirm,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // OTP Field (forgot mode after OTP sent)
                if (_mode == AuthMode.forgot && _otpSent) ...[
                  _buildTextField(
                    controller: _otpController,
                    hint: 'Enter OTP',
                    icon: Icons.pin,
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                ],
                // Submit Button
                GestureDetector(
                  onTap: _handleSubmit,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C6B).withValues(alpha: 0.4),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _mode == AuthMode.login
                                ? 'Sign In'
                                : (_mode == AuthMode.signup ? 'Create Account' : (_otpSent ? 'Reset Password' : 'Send OTP')),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                // Bottom Links
                if (_mode != AuthMode.forgot)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _mode == AuthMode.login ? "Don't have an account?" : "Already have an account?",
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _mode = _mode == AuthMode.login ? AuthMode.signup : AuthMode.login;
                            _passwordController.clear();
                            _confirmController.clear();
                          });
                        },
                        child: Text(
                          _mode == AuthMode.login ? 'Sign Up' : 'Sign In',
                          style: const TextStyle(color: Color(0xFFFF8C6B)),
                        ),
                      ),
                    ],
                  ),
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
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
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
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
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
        borderRadius: BorderRadius.circular(28),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: 0.5)),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}