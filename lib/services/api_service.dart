import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiService {
  static const String baseUrl = 'http://ollie-api-1-production.up.railway.app';
  static const _storage = FlutterSecureStorage();

  // ============================================================
  // TOKEN HELPERS
  // ============================================================

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
    await _storage.deleteAll();
  }

  Future<String?> getValidAccessToken() async {
    return await _storage.read(key: 'access_token');
  }

  Future<bool> refreshAccessToken() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken == null) return false;

    try {
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
    } catch (e) {
      return false;
    }
  }

  // Makes authenticated requests, auto-refreshes on 401
  Future<http.Response> _authRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    String? token = await getValidAccessToken();

    final headers = {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };

    http.Response response;

    if (method == 'POST') {
      response = await http.post(
        Uri.parse('$baseUrl$path'),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else {
      response = await http.get(
        Uri.parse('$baseUrl$path'),
        headers: headers,
      );
    }

    // Token expired — refresh and retry once
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        token = await getValidAccessToken();
        final retryHeaders = {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        };
        if (method == 'POST') {
          response = await http.post(
            Uri.parse('$baseUrl$path'),
            headers: retryHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
        } else {
          response = await http.get(
            Uri.parse('$baseUrl$path'),
            headers: retryHeaders,
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
    required String phoneNumber,
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final response = await _authRequest(
      'POST',
      '/chat',
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
    required String phoneNumber,
    required String message,
  }) async {
    final response = await _authRequest(
      'POST',
      '/speak',
      body: {'message': message},
    );

    if (response.statusCode == 200) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/ollie_voice_${DateTime.now().millisecondsSinceEpoch}.mp3');
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

  Future<Map<String, dynamic>> signup({
    required String phoneNumber,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
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
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail']);
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
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail']);
    }
  }

  Future<void> logout() async {
    final refreshToken = await getRefreshToken();
    if (refreshToken != null) {
      await http.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      );
    }
    await clearTokens();
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
      throw Exception(error['detail']);
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
      throw Exception(error['detail']);
    }
  }

  Future<bool> checkUserExists(String phoneNumber) async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/check/$phoneNumber'),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['exists'];
    }
    return false;
  }

  Future<bool> isLoggedIn() async {
    final token = await getAccessToken();
    return token != null;
  }
}

// ============================================================
// PREMIUM
// ============================================================

Future<Map<String, dynamic>> checkPremiumStatus(String phoneNumber) async {
  final response = await http.get(
    Uri.parse('${ApiService.baseUrl}/premium/status/$phoneNumber'),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    return {'is_premium': false};
  }
}

Future<Map<String, dynamic>> activatePremium({
  required String phoneNumber,
  required String planType,
  required int expiryDays,
}) async {
  final response = await http.post(
    Uri.parse('${ApiService.baseUrl}/premium/activate'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      'phone_number': phoneNumber,
      'plan_type': planType,
      'expiry_days': expiryDays,
    }),
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception('Failed to activate premium');
  }
}
