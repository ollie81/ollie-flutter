// The chat mic in both builds: the APK's hold-to-talk, and the Play
// Store's "coming soon" version that must never start recording.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/config/store_build.dart';
import 'package:ollie_app/widgets/voice_record_button.dart';

class _Calls {
  int start = 0, stop = 0, comingSoon = 0;
}

Future<_Calls> _pump(WidgetTester tester, {required bool comingSoon}) async {
  final calls = _Calls();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: VoiceRecordButton(
          comingSoon: comingSoon,
          isListening: false,
          isTranscribing: false,
          onStartRecording: () => calls.start++,
          onStopRecording: () => calls.stop++,
          onComingSoon: () => calls.comingSoon++,
        ),
      ),
    ),
  ));
  return calls;
}

void main() {
  testWidgets('APK: hold records, release sends; no "soon" tag', (tester) async {
    final calls = await _pump(tester, comingSoon: false);
    expect(find.text('soon'), findsNothing);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(VoiceRecordButton)));
    await tester.pump(const Duration(milliseconds: 600)); // past the long-press delay
    expect(calls.start, 1);
    await gesture.up();
    await tester.pump();
    expect(calls.stop, 1);
    expect(calls.comingSoon, 0);
  });

  testWidgets('Play Store: shows "soon", and a tap or a hold never records', (tester) async {
    final calls = await _pump(tester, comingSoon: true);
    expect(find.text('soon'), findsOneWidget);

    await tester.tap(find.byType(VoiceRecordButton));
    await tester.pump();
    expect(calls.comingSoon, 1);

    await tester.longPress(find.byType(VoiceRecordButton));
    await tester.pump();
    expect(calls.comingSoon, 2);

    expect(calls.start, 0, reason: 'the Play Store build must never start the microphone');
    expect(calls.stop, 0);
  });

  testWidgets('Play Store: a screen reader announces it as coming soon', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, comingSoon: true);
    expect(find.bySemanticsLabel('Voice messages, coming soon'), findsOneWidget);
    handle.dispose();
  });

  test('voice is only "coming soon" in the Play Store build', () {
    // `flutter test` builds like the APK; the Play bundle is built
    // with --dart-define=PLAY_STORE=true (see main.yml).
    expect(voiceComingSoon, isPlayStoreBuild);
    expect(isPlayStoreBuild, const bool.fromEnvironment('PLAY_STORE'));
  });
}
