// The real chat screen, with a fake server: every Ollie reply has a
// report flag (in both builds), the user's own messages don't, and
// reporting sends the reply to POST /chat/report and fills the flag.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ollie_app/config/store_build.dart';
import 'package:ollie_app/screens/chat_screen.dart';
import 'package:ollie_app/widgets/report_reply.dart';

const _history = [
  {'id': 'u-1', 'sender': 'user', 'message': 'i had a rough day', 'created_at': '2026-11-17T08:00:00Z'},
  {'id': 'o-1', 'sender': 'ollie', 'message': "I'm sorry. Want to tell me what happened?", 'created_at': '2026-11-17T08:00:05Z'},
];

/// Plugins the chat screen starts on open (ads, audio, recorder,
/// permissions) have no native side in a test: answer their method
/// and event channels -- including each audio player's own event
/// channel, named after a random id -- with an empty success.
void _silencePlugins() {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const plugins = [
    'plugins.flutter.io/google_mobile_ads',
    'xyz.luan/audioplayers',
    'com.dooboolab.flutter_sound',
    'flutter.baseflow.com/permissions',
  ];
  messenger.allMessagesHandler = (channel, handler, message) {
    if (plugins.any(channel.startsWith)) {
      // Raw bytes, not a decoded call: the ads plugin uses its own codec.
      return Future.value(const StandardMethodCodec().encodeSuccessEnvelope(null));
    }
    return handler != null ? handler(message) : messenger.delegate.send(channel, message);
  };
  addTearDown(() => messenger.allMessagesHandler = null);
}

/// Opens the chat on [_history].
Future<void> _openChat(
  WidgetTester tester, {
  Size size = const Size(393, 851),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'token-1'});
  _silencePlugins();

  final client = MockClient((request) async => request.url.path == '/history'
      ? http.Response(jsonEncode({'messages': _history}), 200)
      : http.Response('{}', 200));

  await http.runWithClient(() async {
    await tester.pumpWidget(const MaterialApp(home: ChatScreen(phoneNumber: '')));
    await _step(tester);
  }, () => client);
}

/// The screen animates forever (orb, particles), so step time forward
/// instead of waiting for it to settle.
Future<void> _step(WidgetTester tester, [int times = 10]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('only Ollie replies get a flag, and the speaker only outside the Play build', (tester) async {
    await _openChat(tester);
    expect(find.text("I'm sorry. Want to tell me what happened?"), findsOneWidget);
    expect(find.byType(ReportFlagButton), findsOneWidget, reason: "one Ollie reply, one flag; none on the user's message");
    expect(find.byIcon(Icons.volume_up_rounded), voiceComingSoon ? findsNothing : findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(320, 568), Size(360, 640)]) {
    testWidgets('fits a ${size.width.toInt()}dp-wide phone', (tester) async {
      await _openChat(tester, size: size);
      expect(tester.takeException(), isNull, reason: 'no overflow beside the reply');
      final flag = tester.getRect(find.byType(ReportFlagButton));
      expect(flag.right, lessThanOrEqualTo(size.width));
    });
  }

  testWidgets('reporting from the flag sends the saved reply and fills the flag', (tester) async {
    await _openChat(tester);
    final reports = <Map<String, dynamic>>[];
    await http.runWithClient(() async {
      await tester.tap(find.byType(ReportFlagButton));
      await _step(tester);
      await tester.tap(find.byKey(const Key('report-reason-harmful')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await _step(tester);
    }, () => MockClient((request) async {
      reports.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response('{"success": true}', 200);
    }));

    expect(reports, [
      {'message_id': 'o-1', 'message_text': "I'm sorry. Want to tell me what happened?", 'reason': 'harmful'},
    ]);
    expect(find.byIcon(Icons.flag_rounded), findsOneWidget, reason: 'the flag is filled in');
    expect(find.text("Thanks for telling us. We'll review this reply."), findsOneWidget);

    // A second tap does nothing now.
    await tester.tap(find.byType(ReportFlagButton));
    await _step(tester);
    expect(find.text('Report this reply'), findsNothing);
  });

  testWidgets('long-pressing an Ollie reply offers Report; your own message does not', (tester) async {
    await _openChat(tester);
    await tester.longPress(find.text("I'm sorry. Want to tell me what happened?"));
    await _step(tester);
    expect(find.text('Report'), findsOneWidget);
    await tester.tap(find.text('Report'));
    await _step(tester);
    expect(find.text('Report this reply'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await _step(tester);

    await tester.longPress(find.text('i had a rough day'));
    await _step(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets('if the report fails, the flag goes back and the user is told', (tester) async {
    await _openChat(tester);
    await http.runWithClient(() async {
      await tester.tap(find.byType(ReportFlagButton));
      await _step(tester);
      await tester.tap(find.byKey(const Key('report-reason-offensive')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await _step(tester);
    }, () => MockClient((_) async => http.Response('{"detail": "down"}', 500)));

    expect(find.byIcon(Icons.outlined_flag_rounded), findsOneWidget, reason: 'can be tried again');
    expect(find.text("Couldn't send the report. Check your connection and try again."), findsOneWidget);
  });
}
