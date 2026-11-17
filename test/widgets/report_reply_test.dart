// Reporting an Ollie reply (Google Play's AI-generated content policy):
// the flag beside each reply, the "what's wrong" sheet, and that the
// sheet still fits on the smallest phones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/widgets/report_reply.dart';

/// Opens the sheet from a button and records what it returned.
class _Opened {
  ReportChoice? choice;
  bool closed = false;
}

Future<_Opened> _openSheet(WidgetTester tester, {Size size = const Size(400, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = _Opened();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () async {
              opened.choice = await showReportReplySheet(context);
              opened.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return opened;
}

ElevatedButton _sendButton(WidgetTester tester) =>
    tester.widget<ElevatedButton>(find.byKey(const Key('report-send')));

void main() {
  test('offers exactly the reasons the server accepts', () {
    // Must match chat.py's REPORT_REASONS keys.
    expect(reportReasons.keys.toSet(), {'offensive', 'sexual', 'harmful', 'false', 'other'});
  });

  testWidgets('Send stays off until a reason is picked, then returns it with the note', (tester) async {
    final opened = await _openSheet(tester);
    expect(find.text('Report this reply'), findsOneWidget);
    expect(_sendButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const Key('report-reason-harmful')));
    await tester.pump();
    expect(_sendButton(tester).onPressed, isNotNull);

    await tester.enterText(find.byKey(const Key('report-details')), '  it told me to skip my medicine  ');
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.pumpAndSettle();

    expect(opened.closed, isTrue);
    expect(opened.choice?.reason, 'harmful');
    expect(opened.choice?.details, 'it told me to skip my medicine');
  });

  testWidgets('a blank note is sent as no note, and the last reason tapped wins', (tester) async {
    final opened = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('report-reason-offensive')));
    await tester.tap(find.byKey(const Key('report-reason-other')));
    await tester.enterText(find.byKey(const Key('report-details')), '   ');
    await tester.tap(find.byKey(const Key('report-send')));
    await tester.pumpAndSettle();
    expect(opened.choice?.reason, 'other');
    expect(opened.choice?.details, isNull);
  });

  testWidgets('Cancel sends nothing', (tester) async {
    final opened = await _openSheet(tester);
    await tester.tap(find.byKey(const Key('report-reason-sexual')));
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(opened.closed, isTrue);
    expect(opened.choice, isNull);
  });

  for (final size in const [Size(320, 568), Size(320, 480)]) {
    testWidgets('fits a ${size.width.toInt()}x${size.height.toInt()} screen, keyboard open too', (tester) async {
      final opened = await _openSheet(tester, size: size);
      expect(tester.takeException(), isNull, reason: 'no overflow on a small phone');

      // Every reason and the button can be reached by scrolling.
      await tester.tap(find.byKey(const Key('report-reason-false')));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();

      // A 260px keyboard: the sheet scrolls instead of overflowing.
      tester.view.viewInsets = const FakeViewPadding(bottom: 260);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(opened.choice?.reason, 'false');
    });
  }

  group('flag button', () {
    Future<List<int>> pumpFlag(WidgetTester tester, {required bool reported}) async {
      final taps = <int>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(child: ReportFlagButton(reported: reported, onTap: () => taps.add(1))),
        ),
      ));
      return taps;
    }

    testWidgets('opens the report from a 40px target', (tester) async {
      final taps = await pumpFlag(tester, reported: false);
      expect(tester.getSize(find.byType(ReportFlagButton)), const Size(40, 40));
      expect(find.byIcon(Icons.outlined_flag_rounded), findsOneWidget);
      await tester.tap(find.byType(ReportFlagButton));
      expect(taps, hasLength(1));
    });

    testWidgets('once reported it is filled in and does nothing', (tester) async {
      final taps = await pumpFlag(tester, reported: true);
      expect(find.byIcon(Icons.flag_rounded), findsOneWidget);
      await tester.tap(find.byType(ReportFlagButton));
      expect(taps, isEmpty);
    });

    testWidgets('a screen reader hears what it does', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpFlag(tester, reported: false);
      expect(find.bySemanticsLabel('Report this reply'), findsOneWidget);
      await pumpFlag(tester, reported: true);
      expect(find.bySemanticsLabel('Reply reported'), findsOneWidget);
      handle.dispose();
    });
  });
}
