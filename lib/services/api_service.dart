import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
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

  // Coalesces concurrent refresh attempts into one in-flight call.
  // The backend rotates refresh tokens (single-use -- every
  // /auth/refresh deletes the old one and issues a new one), so if
  // two requests 401 around the same moment (e.g. a screen loading
  // its data while the user taps something else) and each
  // independently calls refreshAccessToken with the same
  // now-shared token, the loser gets "Invalid refresh token" back
  // and wipes out the tokens the winner just saved via clearTokens
  // -- even though the winner's refresh genuinely succeeded. Any
  // retry after that sends no token at all, which looks like a
  // second, unrelated 401 on the exact same request. Concurrent
  // callers now await the SAME network call instead of each
  // starting their own.
  Future<bool>? _refreshInFlight;

  Future<bool> refreshAccessToken() {
    return _refreshInFlight ??= _doRefreshAccessToken().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<bool> _doRefreshAccessToken() async {
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
    try {
      return await _doAuthRequest(method: method, endpoint: endpoint, body: body);
    } on SocketException {
      // DNS failure, connection refused, network unreachable -- no
      // signal, in other words. Every screen's catch block already
      // shows whatever this throws, so converting it here once
      // means every one of them gets a clean message for free
      // instead of a raw "Failed host lookup" string.
      throw Exception('No internet connection. Check your signal and try again.');
    }
  }

  Future<http.Response> _doAuthRequest({
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
    } else if (method == 'PUT') {
      response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else if (method == 'PATCH') {
      response = await http.patch(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      );
    } else if (method == 'DELETE') {
      response = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: headers,
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
        } else if (method == 'PUT') {
          response = await http.put(
            Uri.parse('$baseUrl$endpoint'),
            headers: newHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
        } else if (method == 'PATCH') {
          response = await http.patch(
            Uri.parse('$baseUrl$endpoint'),
            headers: newHeaders,
            body: body != null ? jsonEncode(body) : null,
          );
        } else if (method == 'DELETE') {
          response = await http.delete(
            Uri.parse('$baseUrl$endpoint'),
            headers: newHeaders,
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
    String? mode,
    String? replyToId,
  }) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/chat',
      body: {
        'message': message,
        'history': history,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
        if (mode != null) 'mode': mode,
        if (replyToId != null) 'reply_to_id': replyToId,
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

  Future<({File? file, int? voiceTrialSecondsRemaining})> sendVoiceMessage({
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
        '${tempDir.path}/ollie_voice_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(response.bodyBytes);
      // Absent for premium users (unlimited, nothing to count).
      final remainingHeader =
          response.headers['x-voice-trial-remaining-seconds'];
      return (
        file: file,
        voiceTrialSecondsRemaining: int.tryParse(remainingHeader ?? ''),
      );
    } else if (response.statusCode == 402) {
      throw Exception('Voice replies require Ollie Premium');
    } else {
      // Was: silently returning nulls here, which _speakMessage
      // treats as "nothing to play" -- indistinguishable from a
      // real failure, since no error ever surfaced. Throwing here
      // (same pattern as sendVoiceChat) lets the actual backend
      // detail reach the user instead of the request just going
      // quiet with no explanation.
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not generate voice reply');
    }
  }

  // ============================================================
  // VOICE INPUT — record a message, get it transcribed + a real
  // reply back in one call. Shares the same free trial as
  // sendVoiceMessage/'/speak' (see voice_trial_seconds_remaining
  // in the returned map below) — premium is unlimited.
  // ============================================================

  Future<http.StreamedResponse> _sendVoiceChatRequest(
    File audioFile,
    String? token,
    String? mode,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/voice'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['utc_offset_minutes'] = DateTime.now()
        .timeZoneOffset
        .inMinutes
        .toString();
    if (mode != null) request.fields['mode'] = mode;
    request.files.add(
      await http.MultipartFile.fromPath('audio', audioFile.path),
    );
    return await request.send();
  }

  Future<Map<String, dynamic>> sendVoiceChat(
    File audioFile, {
    String? mode,
  }) async {
    var token = await getAccessToken();
    var response = await http.Response.fromStream(
      await _sendVoiceChatRequest(audioFile, token, mode),
    );

    // Same single-retry-after-refresh pattern as _authRequest.
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        token = await getAccessToken();
        response = await http.Response.fromStream(
          await _sendVoiceChatRequest(audioFile, token, mode),
        );
      }
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 402) {
      throw Exception('Voice chat requires Ollie Premium');
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Failed to process voice message');
    }
  }

  // ============================================================
  // MODES — "Do It With Me": Ollie speaks first when a mode
  // session opens. Doesn't count against the daily message limit.
  // ============================================================

  Future<String> startMode(String mode) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/chat/mode-starter',
      body: {
        'mode': mode,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not start that');
    }

    final data = jsonDecode(response.body);
    return data['reply'] ?? '';
  }

  // ============================================================
  // ONBOARDING — a one-time personalized name + welcome message
  // right after signup. See onboarding_screen.dart.
  // ============================================================

  Future<void> updateDisplayName(String name) async {
    final response = await _authRequest(
      method: 'PUT',
      endpoint: '/settings/display-name',
      body: {'name': name},
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not update name');
    }
  }

  Future<String> getChatWelcome(String name) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/chat/welcome',
      body: {
        'name': name,
        'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
      },
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not generate welcome message');
    }

    final data = jsonDecode(response.body);
    return data['reply'] ?? '';
  }

  // ============================================================
  // IMAGE INPUT — send a photo (with an optional caption), get a
  // real reaction to it. Free tier, same daily message cap as
  // sendMessage/'/chat' -- a shared photo isn't a premium feature.
  // ============================================================

  // Sniffs the actual image format from its bytes rather than
  // trusting the OS-picked file's name/extension -- image_picker's
  // temp files don't always carry a recognizable one (camera vs.
  // gallery vs. device differ), and MultipartFile.fromPath falls
  // back to application/octet-stream with no contentType given,
  // which the backend correctly rejects as "not an image".
  MediaType _sniffImageMediaType(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return MediaType('image', 'jpeg');
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return MediaType('image', 'png');
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return MediaType('image', 'gif');
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return MediaType('image', 'webp');
    }
    // Fall back to jpeg -- by far the most common phone camera/
    // gallery format, and still passes the backend's "starts with
    // image/" check even when this specific guess is imperfect.
    return MediaType('image', 'jpeg');
  }

  Future<http.StreamedResponse> _sendImageChatRequest(
    File imageFile,
    String? caption,
    String? token,
  ) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/chat/image'),
    );
    request.headers['Authorization'] = 'Bearer $token';
    request.fields['utc_offset_minutes'] = DateTime.now()
        .timeZoneOffset
        .inMinutes
        .toString();
    if (caption != null && caption.trim().isNotEmpty) {
      request.fields['caption'] = caption.trim();
    }
    final bytes = await imageFile.readAsBytes();
    request.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: 'photo.jpg',
        contentType: _sniffImageMediaType(bytes),
      ),
    );
    return await request.send();
  }

  Future<Map<String, dynamic>> sendImageMessage(
    File imageFile, {
    String? caption,
  }) async {
    var token = await getAccessToken();
    var response = await http.Response.fromStream(
      await _sendImageChatRequest(imageFile, caption, token),
    );

    // Same single-retry-after-refresh pattern as _authRequest.
    if (response.statusCode == 401) {
      final refreshed = await refreshAccessToken();
      if (refreshed) {
        token = await getAccessToken();
        response = await http.Response.fromStream(
          await _sendImageChatRequest(imageFile, caption, token),
        );
      }
    }

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 429) {
      throw Exception('Daily limit reached. Try again tomorrow.');
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please log in again.');
    } else {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Failed to send photo');
    }
  }

  // ============================================================
  // VOICE PREVIEW — free, short, fixed sample of Ollie's voice.
  // ============================================================

  Future<File?> getVoicePreview() async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/speak/preview',
    );

    if (response.statusCode == 200) {
      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/ollie_preview_${DateTime.now().millisecondsSinceEpoch}.mp3',
      );
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else if (response.statusCode == 429) {
      throw Exception(
        "you've heard enough of him for today — try again tomorrow",
      );
    } else {
      // Was: silently returning null here, which _playVoicePreview
      // treats as "nothing to play" with no error shown -- the
      // request could be failing for any reason (TTS misconfigured,
      // upstream outage...) and nothing would ever tell the user
      // why. Throwing surfaces the real backend detail instead.
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not play voice preview');
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
    String? dateOfBirth,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
        'otp': otp,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
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
      body: jsonEncode({'phone_number': phoneNumber, 'password': password}),
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
  // EMAIL LOGIN — third sign-in method alongside phone and Google.
  // Same shapes as the phone methods above, against /auth/email/*.
  // ============================================================

  Future<Map<String, dynamic>> emailRequestSignupOtp({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/email/signup/request-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to send OTP');
    }
  }

  Future<Map<String, dynamic>> emailSignup({
    required String email,
    required String password,
    required String otp,
    String? dateOfBirth,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/email/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'otp': otp,
        if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await _storage.write(key: 'phoneNumber', value: email);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Signup failed');
    }
  }

  Future<Map<String, dynamic>> emailLogin({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/email/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await saveTokens(
        accessToken: data['access_token'],
        refreshToken: data['refresh_token'],
      );
      await _storage.write(key: 'phoneNumber', value: email);
      return data;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Login failed');
    }
  }

  Future<Map<String, dynamic>> emailForgotPassword({
    required String email,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/email/forgot'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['detail'] ?? 'Failed to send OTP');
    }
  }

  Future<Map<String, dynamic>> emailResetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/email/reset'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
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
          String.fromCharCodes(base64.decode(normalized)),
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
    required String purchaseToken,
    required String productId,
  }) async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/premium/activate',
      body: {'purchase_token': purchaseToken, 'product_id': productId},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Failed to activate premium');
    }
  }

  // ============================================================
  // FCM TOKEN
  // ============================================================

  Future<void> saveFcmToken(String token) async {
    try {
      final response = await _authRequest(
        method: 'POST',
        endpoint: '/auth/fcm-token',
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
    final response = await _authRequest(method: 'GET', endpoint: '/auth/me');

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

  // ============================================================
  // USAGE
  // ============================================================

  Future<List<dynamic>> getHistory() async {
    final response = await _authRequest(method: 'GET', endpoint: '/history');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['messages'] ?? [];
    } else {
      return [];
    }
  }

  Future<List<dynamic>> searchChat(String query) async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/chat/search?q=${Uri.encodeQueryComponent(query)}',
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['results'] ?? [];
    } else {
      return [];
    }
  }

  Future<Map<String, dynamic>> getUsage() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/settings/usage',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return {
        'messages_used_today': 0,
        'daily_limit': 20,
        'has_active_ad_bonus': false,
        'is_premium': false,
        'current_streak': 0,
      };
    }
  }

  // ============================================================
  // NOTIFICATIONS
  // ============================================================

  Future<Map<String, dynamic>> getNotifications() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/notifications/',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      return {'success': false, 'notifications': [], 'unread_count': 0};
    }
  }

  Future<void> markNotificationRead(String notificationId) async {
    try {
      await _authRequest(
        method: 'POST',
        endpoint: '/notifications/$notificationId/read',
      );
    } catch (e) {
      // Ignore
    }
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    try {
      await _authRequest(
        method: 'PUT',
        endpoint: '/settings/notifications',
        body: {'enabled': enabled},
      );
    } catch (e) {
      // Ignore
    }
  }

  // Governs how much Ollie reaches out first (morning check-in,
  // nightly recap, event check-ins, "you disappeared"). Throws on
  // failure so Settings can show a real error and revert the UI.
  Future<void> setNotificationFrequency(String frequency) async {
    final response = await _authRequest(
      method: 'PUT',
      endpoint: '/settings/notification-frequency',
      body: {'frequency': frequency},
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(
        error['detail'] ?? 'Could not update notification frequency',
      );
    }
  }

  // Lets Ollie talk like a local (culture, slang, holidays) --
  // entirely optional, set from Settings. Unlike
  // setNotificationsEnabled above, this throws on failure so the
  // Settings screen can show a real error instead of silently
  // pretending it saved.
  Future<void> updateLocation({
    String? country,
    String? region,
    String? district,
  }) async {
    final response = await _authRequest(
      method: 'PUT',
      endpoint: '/settings/location',
      body: {'country': country, 'region': region, 'district': district},
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not update location');
    }
  }

  // ============================================================
  // MEMORY
  // ============================================================

  Future<void> clearMemory() async {
    try {
      await _authRequest(method: 'DELETE', endpoint: '/settings/memory');
    } catch (e) {
      // Ignore
    }
  }

  // Individual memory management -- view/edit/delete what Ollie
  // remembers, and turn memory on/off entirely. All throw on
  // failure (unlike clearMemory above) so the Memories screen can
  // show a real error instead of silently pretending it worked.

  Future<List<Map<String, dynamic>>> getMemories() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/settings/memories',
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not load memories');
    }

    final data = jsonDecode(response.body);
    return List<Map<String, dynamic>>.from(data['memories'] ?? []);
  }

  Future<void> updateMemory(
    String memoryId, {
    String? memoryText,
    String? category,
  }) async {
    final response = await _authRequest(
      method: 'PATCH',
      endpoint: '/settings/memories/$memoryId',
      body: {'memory_text': memoryText, 'category': category},
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not update memory');
    }
  }

  Future<void> deleteMemory(String memoryId) async {
    final response = await _authRequest(
      method: 'DELETE',
      endpoint: '/settings/memories/$memoryId',
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not delete memory');
    }
  }

  Future<void> setMemoryEnabled(bool enabled) async {
    final response = await _authRequest(
      method: 'PUT',
      endpoint: '/settings/memory/enabled',
      body: {'enabled': enabled},
    );

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not update memory setting');
    }
  }

  // ============================================================
  // JOURNEY -- "Our Space": relationship stage + shared history
  // ============================================================

  Future<Map<String, dynamic>> getJourney() async {
    final response = await _authRequest(method: 'GET', endpoint: '/journey/');

    if (response.statusCode != 200) {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Could not load your journey');
    }

    return jsonDecode(response.body);
  }

  // ============================================================
  // EXPORT DATA
  // ============================================================

  Future<Map<String, dynamic>> exportUserData() async {
    final response = await _authRequest(
      method: 'GET',
      endpoint: '/settings/export-data',
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Could not export your data');
    }
  }

  // ============================================================
  // DELETE ACCOUNT
  // ============================================================

  /// Schedules deletion (a 14-day grace period, not instant -- see
  /// DeleteAccountScreen) and returns the ISO date it actually
  /// happens on. The confirmation phrase is fixed since the typed-
  /// confirmation gate already lives client-side on that screen;
  /// this just carries it to the server, which checks it again.
  Future<String> requestAccountDeletion() async {
    final response = await _authRequest(
      method: 'POST',
      endpoint: '/settings/delete-account',
      body: {'confirmation': 'DELETE'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await clearTokens();
      await _storage.delete(key: 'phoneNumber');
      return data['scheduled_for'] as String;
    } else {
      Map<String, dynamic> error = {};
      try {
        error = jsonDecode(response.body);
      } catch (_) {}
      throw Exception(error['detail'] ?? 'Failed to delete account');
    }
  }
}
