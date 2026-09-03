// First widget test in this app. Scoped to delete_account_screen.dart's
// confirmation gate specifically because it's pure widget state --
// _submit() (the only thing that touches the network) never fires
// unless _canDelete is already true, so these tests never need to
// mock ApiService or flutter_secure_storage. Testing anything past
// this gate (or most other screens, which construct their services
// directly rather than accepting them injected) would need the app
// refactored toward dependency injection first -- a real follow-up,
// not something to fake here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/screens/delete_account_screen.dart';

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: DeleteAccountScreen()));
}

Finder get _deleteButton => find.widgetWithText(ElevatedButton, 'Delete my account');

bool _isEnabled(WidgetTester tester) =>
    tester.widget<ElevatedButton>(_deleteButton).onPressed != null;

void main() {
  testWidgets('delete button starts disabled', (tester) async {
    await _pumpScreen(tester);
    expect(_isEnabled(tester), isFalse);
  });

  testWidgets('typing something other than DELETE keeps it disabled', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'delete my account');
    await tester.pump();
    expect(_isEnabled(tester), isFalse);
  });

  testWidgets('typing DELETE exactly enables it', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(_isEnabled(tester), isTrue);
  });

  testWidgets('the match is case-sensitive', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(_isEnabled(tester), isFalse);
  });

  testWidgets('surrounding whitespace is trimmed', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), '  DELETE  ');
    await tester.pump();
    expect(_isEnabled(tester), isTrue);
  });

  testWidgets('deleting back to an empty field disables it again', (tester) async {
    await _pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(_isEnabled(tester), isTrue);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(_isEnabled(tester), isFalse);
  });
}
