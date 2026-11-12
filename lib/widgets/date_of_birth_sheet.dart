import 'package:flutter/material.dart';

import 'date_of_birth_fields.dart';

/// Asks for a date of birth in a bottom sheet -- shown after Google
/// sign-in when the backend reports a brand-new account (Google never
/// shares a birthdate). Returns the checked "YYYY-MM-DD", or null if
/// the sheet is closed without one.
Future<String?> showDateOfBirthSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const DateOfBirthSheet(),
  );
}

class DateOfBirthSheet extends StatefulWidget {
  const DateOfBirthSheet({super.key});

  @override
  State<DateOfBirthSheet> createState() => _DateOfBirthSheetState();
}

class _DateOfBirthSheetState extends State<DateOfBirthSheet> {
  final DateOfBirthController _dob = DateOfBirthController();

  @override
  void dispose() {
    _dob.dispose();
    super.dispose();
  }

  void _continue() {
    final result = _dob.validate();
    if (result.isValid) Navigator.pop(context, result.isoDate);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF151829),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // Scrolls rather than overflowing when the keyboard leaves a
      // small screen only a few hundred pixels of room.
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 28, 24, 24 + keyboard),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'One more thing',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'We need your date of birth to finish setting up your account.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
            ),
            const SizedBox(height: 20),
            DateOfBirthFields(controller: _dob, onSubmitted: _continue),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                key: const Key('dob-continue'),
                onTap: _continue,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(colors: [Color(0xFFFF8C6B), Color(0xFFE86B4A)]),
                  ),
                  child: const Center(
                    child: Text(
                      'Continue',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
