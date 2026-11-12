// The email and phone signup screens use the Day/Month/Year boxes
// (not the old calendar dialog), stop on a bad date before any code
// is requested, and fit small Android screens. Nothing here reaches
// the network: every check stops at the date validation, which runs
// before the first API call.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/screens/email_auth_screen.dart';
import 'package:ollie_app/screens/phone_auth_screen.dart';
import 'package:ollie_app/widgets/date_of_birth_fields.dart';

final _error = find.byKey(const Key('dob-error'));

void _useScreen(WidgetTester tester, Size size, {double textScale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _openEmailSignup(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: EmailAuthScreen()));
  await _tapVisible(tester, find.widgetWithText(TextButton, 'Sign Up'));
}

void main() {
  testWidgets('email signup shows the Day/Month/Year boxes, not a calendar', (tester) async {
    await _openEmailSignup(tester);
    expect(find.byType(DateOfBirthFields), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);
  });

  testWidgets('email signup with no date explains under the boxes and sends no code', (tester) async {
    await _openEmailSignup(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'new@example.com');
    await tester.enterText(fields.at(1), 'hunters2');
    await tester.enterText(fields.at(2), 'hunters2');
    await _tapVisible(tester, find.text('Send Code'));

    expect(tester.widget<Text>(_error).data, 'Enter your date of birth.');
    // Still on the first step: no code was requested.
    expect(find.text('Send Code'), findsOneWidget);
    expect(find.text('Enter the code sent to your email'), findsNothing);
  });

  testWidgets('email signup with 29/2/2023 says February 2023 has 28 days', (tester) async {
    await _openEmailSignup(tester);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'new@example.com');
    await tester.enterText(fields.at(1), 'hunters2');
    await tester.enterText(fields.at(2), 'hunters2');
    await tester.enterText(find.byKey(const Key('dob-day')), '29');
    await tester.enterText(find.byKey(const Key('dob-month')), '2');
    await tester.enterText(find.byKey(const Key('dob-year')), '2023');
    await _tapVisible(tester, find.text('Send Code'));
    expect(tester.widget<Text>(_error).data, 'February 2023 has 28 days. Please check the day.');
  });

  testWidgets('switching back to sign in and up again starts with empty boxes', (tester) async {
    await _openEmailSignup(tester);
    await tester.enterText(find.byKey(const Key('dob-day')), '27');
    await _tapVisible(tester, find.widgetWithText(TextButton, 'Sign In'));
    await _tapVisible(tester, find.widgetWithText(TextButton, 'Sign Up'));
    expect(tester.widget<TextField>(find.byKey(const Key('dob-day'))).controller!.text, '');
  });

  testWidgets('phone signup shows the boxes and stops on a missing date before any SMS', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PhoneAuthScreen()));
    await _tapVisible(tester, find.widgetWithText(TextButton, 'Sign Up'));
    expect(find.byType(DateOfBirthFields), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '788123456'); // the phone field
    await tester.enterText(fields.at(1), 'hunters2');
    await tester.enterText(fields.at(2), 'hunters2');
    await _tapVisible(tester, find.text('Send OTP'));

    expect(tester.widget<Text>(_error).data, 'Enter your date of birth.');
    expect(find.text('Send OTP'), findsOneWidget, reason: 'still on the first step: no SMS requested');
  });

  for (final (label, size, scale) in [
    ('320x568', const Size(320, 568), 1.0),
    ('320x568 with 130% text', const Size(320, 568), 1.3),
    ('360x640', const Size(360, 640), 1.0),
  ]) {
    testWidgets('email signup fits $label without overflow, with an error showing', (tester) async {
      _useScreen(tester, size, textScale: scale);
      await _openEmailSignup(tester);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'new@example.com');
      await tester.enterText(fields.at(1), 'hunters2');
      await tester.enterText(fields.at(2), 'hunters2');
      await _tapVisible(tester, find.text('Send Code'));
      expect(_error, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(const Key('dob-year'))).right, lessThanOrEqualTo(size.width));
    });

    testWidgets('phone signup fits $label without overflow', (tester) async {
      _useScreen(tester, size, textScale: scale);
      await tester.pumpWidget(const MaterialApp(home: PhoneAuthScreen()));
      await _tapVisible(tester, find.widgetWithText(TextButton, 'Sign Up'));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(const Key('dob-year'))).right, lessThanOrEqualTo(size.width));
    });
  }
}
