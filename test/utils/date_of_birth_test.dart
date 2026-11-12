// Unit tests for lib/utils/date_of_birth.dart -- the same cases the
// backend (tests/test_age_gate.py) and the web app
// (tests/dateOfBirth.test.ts) check, so all three agree.

import 'package:flutter_test/flutter_test.dart';
import 'package:ollie_app/utils/date_of_birth.dart';

const today = CalendarDate(2026, 11, 12);

DobValidation check(String day, String month, String year, {CalendarDate at = today}) =>
    validateDateOfBirth(day: day, month: month, year: year, today: at);

void expectOk(String day, String month, String year, String iso, {CalendarDate at = today}) {
  final result = check(day, month, year, at: at);
  expect(result.error, isNull, reason: '$day/$month/$year should be accepted');
  expect(result.isoDate, iso);
}

DobValidation expectError(String day, String month, String year, String message, {CalendarDate at = today}) {
  final result = check(day, month, year, at: at);
  expect(result.isValid, isFalse, reason: '$day/$month/$year should be rejected');
  expect(result.error, message);
  return result;
}

void main() {
  group('accepted dates', () {
    test('a normal date is sent exactly as typed, zero-padded', () {
      expectOk('5', '3', '2007', '2007-03-05');
      expectOk('27', '12', '1990', '1990-12-27');
    });

    test('leading zeros and spaces are fine', () {
      expectOk('05', '07', '2000', '2000-07-05');
      expectOk(' 5 ', ' 7', '2000 ', '2000-07-05');
    });

    test('turning 13 today is allowed', () => expectOk('12', '11', '2013', '2013-11-12'));

    test('29 February exists in leap years', () {
      expectOk('29', '2', '2000', '2000-02-29');
      expectOk('29', '2', '2012', '2012-02-29');
    });

    test('the maximum plausible age itself is allowed', () => expectOk('12', '11', '1906', '1906-11-12'));
  });

  group('missing parts', () {
    test('nothing typed asks for the date and marks every box', () {
      final r = expectError('', '', '', 'Enter your date of birth.');
      expect(r.fields, [DobField.day, DobField.month, DobField.year]);
    });

    test('a missing part marks only that box', () {
      final r = expectError('27', '', '2007', 'Enter the day, month and year.');
      expect(r.fields, [DobField.month]);
    });
  });

  group('not a real calendar date', () {
    test('day and month out of range point at the right box', () {
      for (final d in ['0', '32']) {
        expect(expectError(d, '3', '2007', 'Day must be a number from 1 to 31.').fields, [DobField.day]);
      }
      for (final m in ['0', '13']) {
        expect(expectError('5', m, '2007', 'Month must be a number from 1 to 12.').fields, [DobField.month]);
      }
    });

    test('a year must have four digits', () {
      expectError('5', '3', '07', 'Year must have 4 digits, for example 2007.');
      expectError('5', '3', '207', 'Year must have 4 digits, for example 2007.');
    });

    test('31 April says how long April is', () {
      final r = expectError('31', '4', '1990', 'April 1990 has 30 days. Please check the day.');
      expect(r.fields, [DobField.day, DobField.month]);
    });

    test('29 February outside a leap year says February has 28 days', () {
      expectError('29', '2', '2023', 'February 2023 has 28 days. Please check the day.');
    });

    test('century years are leap years only when divisible by 400', () {
      expect(daysInMonth(2000, 2), 29);
      expect(daysInMonth(1900, 2), 28);
      expect(daysInMonth(2100, 2), 28);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2023, 2), 28);
    });

    test('every month has the right length', () {
      const lengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      for (var m = 1; m <= 12; m++) {
        expect(daysInMonth(2023, m), lengths[m - 1], reason: 'month $m');
      }
    });
  });

  group('impossible ages', () {
    test('tomorrow and future years are in the future', () {
      expectError('13', '11', '2026', "Date of birth can't be in the future.");
      expectError('1', '1', '2030', "Date of birth can't be in the future.");
    });

    test('older than the maximum plausible age asks to check the year', () {
      expectError('12', '11', '1905', 'Please check the year.');
      expectError('1', '1', '0000', 'Please check the year.');
    });
  });

  group('the age bar', () {
    test('one day short of 13 is too young', () {
      expectError('13', '11', '2013', 'You must be at least 13 years old to use Ollie.');
    });

    test('a 29 February birthday only counts from 1 March in non-leap years', () {
      expectError('29', '2', '2012', 'You must be at least 13 years old to use Ollie.',
          at: const CalendarDate(2025, 2, 28));
      expectOk('29', '2', '2012', '2012-02-29', at: const CalendarDate(2025, 3, 1));
    });

    test('ageOn counts whole years', () {
      expect(ageOn(today, const CalendarDate(2000, 11, 12)), 26);
      expect(ageOn(today, const CalendarDate(2000, 11, 13)), 25);
    });
  });

  group('timezones never change the date', () {
    test('"today" is the UTC date, the same one the server uses', () {
      // 00:30 on 12 Nov in Kigali (UTC+2) is still 11 Nov in UTC.
      expect(utcToday(DateTime.parse('2026-11-12T00:30:00+02:00')), const CalendarDate(2026, 11, 11));
      // 23:30 on 11 Nov in Sao Paulo (UTC-3) is already 12 Nov in UTC.
      expect(utcToday(DateTime.parse('2026-11-11T23:30:00-03:00')), const CalendarDate(2026, 11, 12));
    });

    test('the value sent is built from the typed numbers', () {
      expect(const CalendarDate(2007, 1, 1).toIso(), '2007-01-01');
      expect(const CalendarDate(2007, 12, 31).toIso(), '2007-12-31');
    });
  });

  group('read-back', () {
    test('only for a real, complete date', () {
      expect(typedCalendarDate('27', '3', ''), isNull);
      expect(typedCalendarDate('31', '4', '2007'), isNull);
      expect(typedCalendarDate('1', '1', '0012'), isNull);
      expect(typedCalendarDate('27', '3', '2007'), const CalendarDate(2007, 3, 27));
      expect(const CalendarDate(2007, 3, 27).toLongString(), '27 March 2007');
    });
  });
}
