// Widget tests for DateOfBirthFields / DateOfBirthController and the
// Google signup sheet built on them -- typing, errors, correcting an
// entry, and fitting on small Android screens (including with the
// keyboard up and with larger system text).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/utils/date_of_birth.dart';
import 'package:ollie_app/widgets/date_of_birth_fields.dart';
import 'package:ollie_app/widgets/date_of_birth_sheet.dart';

final _day = find.byKey(const Key('dob-day'));
final _month = find.byKey(const Key('dob-month'));
final _year = find.byKey(const Key('dob-year'));
final _error = find.byKey(const Key('dob-error'));
final _readback = find.byKey(const Key('dob-readback'));

const _today = CalendarDate(2026, 11, 12);

String _text(WidgetTester tester, Finder field) => tester.widget<TextField>(field).controller!.text;

Color _borderColor(WidgetTester tester, Finder field) {
  final box = tester.widget<Container>(find.ancestor(of: field, matching: find.byType(Container)).first);
  return ((box.decoration as BoxDecoration).border as Border).top.color;
}

/// Pins the test surface to a phone size (logical pixels), optionally
/// with the keyboard up and/or larger system text.
void _useScreen(WidgetTester tester, Size size, {double keyboard = 0, double textScale = 1}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

class _Harness extends StatefulWidget {
  const _Harness();
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final controller = DateOfBirthController();
  DobValidation? last;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF151829),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              DateOfBirthFields(controller: controller),
              TextButton(
                key: const Key('submit'),
                onPressed: () => setState(() => last = controller.validate(today: _today)),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      );
}

Future<_HarnessState> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: _Harness()));
  return tester.state<_HarnessState>(find.byType(_Harness));
}

void main() {
  testWidgets('shows labelled Day, Month and Year boxes with an example', (tester) async {
    await _pumpHarness(tester);
    expect(find.text('Date of birth'), findsOneWidget);
    expect(find.text('Day'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);
    expect(find.text('Type it as numbers. For example: 27\u00a03\u00a02007'), findsOneWidget);
    expect(tester.widget<TextField>(_day).keyboardType, TextInputType.number);
  });

  testWidgets('boxes keep digits only and stop at their length', (tester) async {
    await _pumpHarness(tester);
    await tester.enterText(_day, 'a1b2c3');
    await tester.enterText(_year, '200712');
    expect(_text(tester, _day), '12');
    expect(_text(tester, _year), '2007');
  });

  testWidgets('a real date is read back in words', (tester) async {
    await _pumpHarness(tester);
    await tester.enterText(_day, '27');
    await tester.enterText(_month, '3');
    await tester.enterText(_year, '2007');
    await tester.pump();
    expect(tester.widget<Text>(_readback).data, "That's 27 March 2007");
  });

  testWidgets('submitting nothing explains, marks every box red and focuses Day', (tester) async {
    final state = await _pumpHarness(tester);
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(tester.widget<Text>(_error).data, 'Enter your date of birth.');
    expect(_borderColor(tester, _day), const Color(0xFFE53935));
    expect(_borderColor(tester, _year), const Color(0xFFE53935));
    expect(state.controller.dayFocus.hasFocus, isTrue);
    expect(state.last!.isValid, isFalse);
  });

  testWidgets('31 April: explains the month length and marks only day and month', (tester) async {
    final state = await _pumpHarness(tester);
    await tester.enterText(_day, '31');
    await tester.enterText(_month, '4');
    await tester.enterText(_year, '2007');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(tester.widget<Text>(_error).data, 'April 2007 has 30 days. Please check the day.');
    expect(state.controller.errorFields, [DobField.day, DobField.month]);
    expect(_borderColor(tester, _year), isNot(const Color(0xFFE53935)));
  });

  testWidgets('fixing a box clears the error straight away; tapping into a box does not', (tester) async {
    final state = await _pumpHarness(tester);
    await tester.enterText(_day, '31');
    await tester.enterText(_month, '4');
    await tester.enterText(_year, '2007');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(_error, findsOneWidget);

    await tester.tap(_month); // only moves focus/selection
    await tester.pump();
    expect(_error, findsOneWidget, reason: 'the message should stay up to be read');

    await tester.enterText(_day, '30');
    await tester.pump();
    expect(_error, findsNothing);
    expect(state.controller.errorFields, isEmpty);
    expect(tester.widget<Text>(_readback).data, "That's 30 April 2007");
  });

  testWidgets('valid date returns exactly YYYY-MM-DD', (tester) async {
    final state = await _pumpHarness(tester);
    await tester.enterText(_day, '5');
    await tester.enterText(_month, '3');
    await tester.enterText(_year, '2007');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    expect(state.last!.isoDate, '2007-03-05');
    expect(_error, findsNothing);
  });

  for (final (label, size, scale) in [
    ('320x568', const Size(320, 568), 1.0),
    ('320x568 with 130% text', const Size(320, 568), 1.3),
    ('360x640', const Size(360, 640), 1.0),
    ('360x640 with 200% text', const Size(360, 640), 2.0),
  ]) {
    testWidgets('fits a $label screen: one row, no overflow, error shown', (tester) async {
      _useScreen(tester, size, textScale: scale);
      await _pumpHarness(tester);
      await tester.enterText(_day, '31');
      await tester.enterText(_month, '4');
      await tester.enterText(_year, '2007');
      await tester.tap(find.byKey(const Key('submit')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final dayBox = tester.getRect(_day);
      final yearBox = tester.getRect(_year);
      expect(dayBox.top, closeTo(yearBox.top, 0.5), reason: 'boxes on one row');
      expect(yearBox.right, lessThanOrEqualTo(size.width));
      expect(yearBox.width, greaterThan(dayBox.width));
      expect(dayBox.height, greaterThanOrEqualTo(44), reason: 'finger-sized');
    });
  }

  group('Google signup sheet', () {
    Future<List<String?>> openSheet(WidgetTester tester) async {
      final results = <String?>[];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => results.add(await showDateOfBirthSheet(context)),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets('returns the checked date', (tester) async {
      final results = await openSheet(tester);
      expect(find.text('One more thing'), findsOneWidget);
      await tester.enterText(_day, '27');
      await tester.enterText(_month, '3');
      await tester.enterText(_year, '2007');
      await tester.tap(find.byKey(const Key('dob-continue')));
      await tester.pumpAndSettle();
      expect(results, ['2007-03-27']);
      expect(find.text('One more thing'), findsNothing);
    });

    testWidgets('the keyboard done key submits too', (tester) async {
      final results = await openSheet(tester);
      await tester.enterText(_day, '27');
      await tester.enterText(_month, '3');
      await tester.enterText(_year, '2007');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(results, ['2007-03-27']);
    });

    testWidgets('an under-13 date stays open with the reason, then can be corrected', (tester) async {
      final results = await openSheet(tester);
      await tester.enterText(_day, '1');
      await tester.enterText(_month, '1');
      await tester.enterText(_year, '2020');
      await tester.tap(find.byKey(const Key('dob-continue')));
      await tester.pumpAndSettle();
      expect(results, isEmpty);
      expect(tester.widget<Text>(_error).data, 'You must be at least 13 years old to use Ollie.');

      await tester.enterText(_year, '2005');
      await tester.tap(find.byKey(const Key('dob-continue')));
      await tester.pumpAndSettle();
      expect(results, ['2005-01-01']);
    });

    testWidgets('fits a 320x568 screen with the keyboard up (scrolls, no overflow)', (tester) async {
      _useScreen(tester, const Size(320, 568), keyboard: 260, textScale: 1.3);
      final results = await openSheet(tester);
      expect(tester.takeException(), isNull);
      await tester.enterText(_day, '27');
      await tester.enterText(_month, '3');
      await tester.enterText(_year, '2007');
      await tester.ensureVisible(find.byKey(const Key('dob-continue')));
      await tester.tap(find.byKey(const Key('dob-continue')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(results, ['2007-03-27']);
    });
  });
}
