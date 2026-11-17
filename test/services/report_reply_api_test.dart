// ApiService.reportReply: the exact request the app sends to
// POST /chat/report (chat.py's report_reply), using a fake HTTP client.

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ollie_app/services/api_service.dart';

Future<http.Request> _send(Future<void> Function(ApiService api) call, {int status = 200}) async {
  http.Request? sent;
  await http.runWithClient(
    () => call(ApiService()),
    () => MockClient((request) async {
      sent = request;
      return http.Response(status == 200 ? '{"success": true}' : '{"detail": "no"}', status);
    }),
  );
  return sent!;
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({'access_token': 'token-1'}));

  test('a saved reply goes by its id, with the reason and the note', () async {
    final sent = await _send((api) => api.reportReply(
          messageId: 'm-1',
          messageText: 'the reply',
          reason: 'harmful',
          details: 'it told me to skip my medicine',
        ));
    expect(sent.method, 'POST');
    expect(sent.url.toString(), '${ApiService.baseUrl}/chat/report');
    expect(sent.headers['Authorization'], 'Bearer token-1');
    expect(jsonDecode(sent.body), {
      'message_id': 'm-1',
      'message_text': 'the reply',
      'reason': 'harmful',
      'details': 'it told me to skip my medicine',
    });
  });

  test('a greeting that was never saved goes by its text alone', () async {
    final sent = await _send((api) => api.reportReply(messageText: 'hey, welcome!', reason: 'other'));
    expect(jsonDecode(sent.body), {'message_text': 'hey, welcome!', 'reason': 'other'});
  });

  test('a refused report throws, so the chat can put the flag back', () async {
    await expectLater(
      _send((api) => api.reportReply(messageText: 'x', reason: 'offensive'), status: 404),
      throwsA(isA<Exception>()),
    );
  });
}
