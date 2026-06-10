import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ApiService {
  // CHANGE THIS TO YOUR PC'S IP ADDRESS
  static const String baseUrl = 'http://ollie-api-1-production.up.railway.app';

  // ============================================================
  // CHAT & VOICE
  // ============================================================

  Future<Map<String, dynamic>> sendMessage({
    required String phoneNumber,
    required String message,
    List<Map<String, String>> history = const [],
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': phoneNumber,
        'message': message,
        'history': history,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 429) {
      throw Exception('Daily limit reached. Try again tomorrow.');
    } else {
      throw Exception('Failed to send message');
    }
  }

  Future<File?> sendVoiceMessage({
    required String phoneNumber,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/speak'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': phoneNumber,
        'message': message,
      }),
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
      return jsonDecode(response.body);
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
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail']);
    }
  }

  Future<Map<String, dynamic>> forgotPassword({
    required String phoneNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/forgot'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
      }),
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