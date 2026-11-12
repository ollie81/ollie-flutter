// ============================================================
// Date-of-birth rules for signup -- shared by every signup screen
// (email, phone, and the Google bottom sheet).
// ============================================================
// Mirrors the backend's _validate_date_of_birth (ollie-api-1
// auth.py) and the web app's src/lib/dateOfBirth.ts, which share
// these rules:
// - at least minSignupAgeYears old, at most maxPlausibleAgeYears
// - a real calendar date (month lengths, leap years)
// - "today" is the current UTC date, the same one the server uses,
//   so the app never accepts a date the server then rejects (or the
//   other way round) around midnight on someone's 13th birthday.
//
// Dates stay as plain year/month/day numbers from the three boxes
// all the way to the "YYYY-MM-DD" string that's sent. No DateTime is
// ever built from what was typed, so no timezone conversion can
// move it by a day.

const int minSignupAgeYears = 13;
const int maxPlausibleAgeYears = 120;

enum DobField { day, month, year }

const List<String> monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

class CalendarDate {
  final int year;
  final int month; // 1-12
  final int day;

  const CalendarDate(this.year, this.month, this.day);

  String toIso() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  /// "27 March 2007" -- day first, in the same order as the boxes.
  String toLongString() => '$day ${monthNames[month - 1]} $year';

  int _compareTo(CalendarDate other) {
    if (year != other.year) return year - other.year;
    if (month != other.month) return month - other.month;
    return day - other.day;
  }

  @override
  bool operator ==(Object other) =>
      other is CalendarDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => toIso();
}

class DobValidation {
  /// "YYYY-MM-DD" when valid -- exactly what the backend expects.
  final String? isoDate;

  /// Plain-words message when invalid.
  final String? error;

  /// Which boxes to mark; the first one gets focus.
  final List<DobField> fields;

  const DobValidation.valid(String this.isoDate)
      : error = null,
        fields = const [];

  const DobValidation.invalid(String this.error, this.fields) : isoDate = null;

  bool get isValid => isoDate != null;
}

CalendarDate utcToday([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  return CalendarDate(utc.year, utc.month, utc.day);
}

bool isLeapYear(int year) => year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

int daysInMonth(int year, int month) {
  if (month == 2) return isLeapYear(year) ? 29 : 28;
  return const [4, 6, 9, 11].contains(month) ? 30 : 31;
}

/// Whole years old on [today]. A 29 February birthday counts from
/// 1 March in non-leap years -- the stricter reading, and the same
/// one the server uses.
int ageOn(CalendarDate today, CalendarDate dob) {
  final hadBirthdayThisYear =
      today.month > dob.month || (today.month == dob.month && today.day >= dob.day);
  return today.year - dob.year - (hadBirthdayThisYear ? 0 : 1);
}

final RegExp _digits = RegExp(r'^\d+$');
final RegExp _fourDigits = RegExp(r'^\d{4}$');

DobValidation validateDateOfBirth({
  required String day,
  required String month,
  required String year,
  CalendarDate? today,
}) {
  final now = today ?? utcToday();
  final d = day.trim();
  final m = month.trim();
  final y = year.trim();

  final missing = [
    if (d.isEmpty) DobField.day,
    if (m.isEmpty) DobField.month,
    if (y.isEmpty) DobField.year,
  ];
  if (missing.length == 3) return DobValidation.invalid('Enter your date of birth.', missing);
  if (missing.isNotEmpty) return DobValidation.invalid('Enter the day, month and year.', missing);

  final dayNumber = _digits.hasMatch(d) ? int.parse(d) : -1;
  final monthNumber = _digits.hasMatch(m) ? int.parse(m) : -1;
  if (dayNumber < 1 || dayNumber > 31) {
    return const DobValidation.invalid('Day must be a number from 1 to 31.', [DobField.day]);
  }
  if (monthNumber < 1 || monthNumber > 12) {
    return const DobValidation.invalid('Month must be a number from 1 to 12.', [DobField.month]);
  }
  if (!_fourDigits.hasMatch(y)) {
    return const DobValidation.invalid('Year must have 4 digits, for example 2007.', [DobField.year]);
  }
  final yearNumber = int.parse(y);

  if (yearNumber > now.year) {
    return const DobValidation.invalid("Date of birth can't be in the future.", [DobField.year]);
  }
  if (yearNumber < now.year - maxPlausibleAgeYears - 1) {
    return const DobValidation.invalid('Please check the year.', [DobField.year]);
  }

  final monthLength = daysInMonth(yearNumber, monthNumber);
  if (dayNumber > monthLength) {
    return DobValidation.invalid(
      '${monthNames[monthNumber - 1]} $yearNumber has $monthLength days. Please check the day.',
      const [DobField.day, DobField.month],
    );
  }

  final dob = CalendarDate(yearNumber, monthNumber, dayNumber);
  if (dob._compareTo(now) > 0) {
    return const DobValidation.invalid(
      "Date of birth can't be in the future.",
      [DobField.day, DobField.month, DobField.year],
    );
  }

  final age = ageOn(now, dob);
  if (age > maxPlausibleAgeYears) {
    return const DobValidation.invalid('Please check the year.', [DobField.year]);
  }
  if (age < minSignupAgeYears) {
    return const DobValidation.invalid(
      'You must be at least $minSignupAgeYears years old to use Ollie.',
      [DobField.year],
    );
  }
  return DobValidation.valid(dob.toIso());
}

/// The typed numbers as a real calendar date (ignoring age), or null
/// while incomplete or impossible. Drives the "That's 27 March 2007"
/// read-back under the boxes, so a swapped day and month is obvious
/// before submitting.
CalendarDate? typedCalendarDate(String day, String month, String year) {
  if (!RegExp(r'^\d{1,2}$').hasMatch(day) || !RegExp(r'^\d{1,2}$').hasMatch(month) || !_fourDigits.hasMatch(year)) {
    return null;
  }
  final d = int.parse(day);
  final m = int.parse(month);
  final y = int.parse(year);
  if (y < 1000 || m < 1 || m > 12 || d < 1 || d > daysInMonth(y, m)) return null;
  return CalendarDate(y, m, d);
}
