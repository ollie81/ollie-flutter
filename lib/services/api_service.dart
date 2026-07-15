
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'https://ollie-api-1-production.up.railway.app';
  static const _storage = FlutterSecureStorage();

  // ==========================================================
  // TOKEN STORAGE
  // ==========================================================

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<String?> getAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<String?> getRefreshToken() async {
    return await _storage.read(key: 'refresh_token');
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  // ============================================================
  // AUTH HEADERS
  // ============================================================

  Future<Map<String, String>> _authHeaders() async {
    final token = await getAccessToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // ============================================================
  // TOKEN REFRESH
  // ============================================================

  Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;

    final response = await http.post(
      Uri.parse('$baseUrl/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': refreshToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      return true;
    } else {
      await clearTokens();
      return false;
    }
  }

  // ============================================================
  // SMART REQUEST — auto retry with refresh if token expired
  // ============================================================

  Future<http.Response> _authRequest({
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
  }) async {
    final headers = await _authHeaders();

    http.Response response;

    if (method == 'POST') {
      response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else {
      response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
      );
    }

    // If token expired — refresh and retry once
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        final newHeaders = await _authHeaders();
        if (method == 'POST') {
          response = await http.post(
            Uri.parse('$baseUrl$endpoint'),
            headers: newHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
        } else {
          response = await http.get(
            Uri.parse('$baseUrl$endpoint'),
            headers: newHeaders,
          );
        }
      }
    }

    return response;
  }

  // ============================================================
  // CHAT & VOICE
  // ============================================================

  Future<Map<String, dynamic>> sendMessage({
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/chat',
      body: {
        'message': message,
        'history': history,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 429) {
      throw Exception('Daily limit reached. Try again tomorrow.');
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      throw Exception('Failed to send message');
    }
  }

  Future<File?> sendVoiceMessage({
    required String message,
  }) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/speak',
      body: {'message': message},
    );

    if (response.statusCode == 200) {
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/ollie_voice_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else if (response.statusCode == 429) {
      throw Exception('Voice limit reached (1 minute per day)');
    } else {
      return null;
    }
  }

  // ============================================================
  // AUTHENTICATION
  // ============================================================

  Future<Map<String, dynamic>> requestSignupOtp({
    required String phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to send OTP');
    }
  }

  Future<Map<String, dynamic>> signup({
    required String phoneNumber,
    required String password,
    required String otp,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
        'otp': otp,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await _storage.write(key: 'phoneNumber', value: phoneNumber);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Signup failed');
    }
  }

  Future<Map<String, dynamic>> login({
    required String phoneNumber,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await _storage.write(key: 'phoneNumber', value: phoneNumber);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Login failed');
    }
  }

  Future<void> logout() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse('$baseUrl/auth/logout'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        );
      } catch (e) {
        // Ignore logout errors
      }
    }
    await clearTokens();
    await _storage.delete(key: 'phoneNumber');
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone_number': phoneNumber}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to send OTP');
    }
  }

  Future<Map<String, dynamic>> resetPassword({
    required String phoneNumber,
    required String otp,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'otp': otp,
        'new_password': newPassword,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Password reset failed');
    }
  }

  // ============================================================
  // GOOGLE LOGIN
  // ============================================================

  Future<Map<String, dynamic>> googleLogin({required String idToken}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'id_token': idToken}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      
      // Extract email from ID token
      try {
        final payload = idToken.split('.')[1];
        // Add padding if needed
        String normalized = payload;
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        final decoded = jsonDecode(
          String.fromCharCodes(base64.decode(normalized))
        );
        final email = decoded['email'];
        if (email != null) {
          await _storage.write(key: 'phoneNumber', value: email);
        }
      } catch (e) {
        // If we can't extract email, use a placeholder
        await _storage.write(key: 'phoneNumber', value: 'google_user');
      }
      
      return data;
    } else {
      try {
        final error = jsonDecode(response.body);
        throw Exception(error['detail'] ?? 'Google login failed');
      } catch (e) {
        throw Exception('Google login failed: ${response.statusCode}');
      }
    }
  }

  // ============================================================
  // AUTO-LOGIN
  // ============================================================

  Future<Map<String, dynamic>?> autoLogin() async {
    final token = await getAccessToken();
    if (token == null) return null;

    final response = await _authRequest(
      method: 'GET',
      endpoint: '/auth/verify',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      await clearTokens();
      return null;
    }
  }

  Future<bool> checkUserExists(String phoneNumber) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/check/$phoneNumber'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['exists'] ?? false;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null;
  }

  // ============================================================
  // PHONE NUMBER
  // ============================================================

  Future<String?> getPhoneNumber() async {
    return await _storage.read(key: 'phoneNumber');
  }

  // ============================================================
  // PREMIUM
  // ============================================================

  Future<Map<String, dynamic>> checkPremiumStatus() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/premium/status',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return {'is_premium': false};
    }
  }

  Future<Map<String, dynamic>> activatePremium({
    required String planType,
    required int expiryDays,
  }) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/premium/activate',
      body: {
        'plan_type': planType,
        'expiry_days': expiryDays,
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to activate premium');
    }
  }

  // ============================================================
  // FCM TOKEN
  // ============================================================

  Future<void> saveFcmToken(String token) async {
    try {
      final response = await _authRequest(
        method: 'POST',
        endpoint: '/auth/fcm-token',  // Fixed: added /auth/ prefix
        body: {'fcm_token': token},
      );

      if (response.statusCode != 200) {
        print('Failed to save FCM token: ${response.statusCode}');
      }
    } catch (e) {
      print('Error saving FCM token: $e');
    }
  }

  // ============================================================
  // ADS
  // ============================================================

  Future<Map<String, dynamic>> watchAdBonus() async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/premium/watch-ad',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to unlock bonus messages');
    }
  }

  // ============================================================
  // GET USER PROFILE
  // ============================================================

  Future<Map<String, dynamic>> getUserProfile() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/auth/me',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get user profile');
    }
  }

  // ============================================================
  // UPDATE USER PROFILE
  // ============================================================

  Future<Map<String, dynamic>> updateUserProfile({
    String? username,
    String? country,
  }) async {
    final Map<String, dynamic> body = {};
    if (username != null) body['username'] = username;
    if (country != null) body['country'] = country;

    final response = await _authRequest(
      method: 'POST',
      endpoint: '/auth/update',
      body: body,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to update profile');
    }
  }
}
