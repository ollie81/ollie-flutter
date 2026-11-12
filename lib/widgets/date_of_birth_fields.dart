import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/date_of_birth.dart';

// Three plain number boxes -- Day, Month, Year -- in place of the
// calendar dialog every signup screen used before. That dialog ran
// with Flutter's built-in US-English defaults (the app registers no
// other locales), so typing a date in it meant mm/dd/yyyy: anyone
// writing day-first got "Invalid format." for a day over 12, or a
// silently swapped day and month otherwise. Here every box is
// labelled, the hint shows an example, and once the numbers make a
// real date it's read back in words ("That's 27 March 2007").
//
// Same layout and rules as the web app (src/components/
// DateOfBirthFields.tsx).

const _accent = Color(0xFFFF8C6B);
const _danger = Color(0xFFE53935);
const _errorText = Color(0xFFFFB4B1);

/// Holds the three boxes' text, their focus, and the current error.
/// Owned by the screen (dispose it there), passed to
/// [DateOfBirthFields].
class DateOfBirthController extends ChangeNotifier {
  final TextEditingController day = TextEditingController();
  final TextEditingController month = TextEditingController();
  final TextEditingController year = TextEditingController();
  final FocusNode dayFocus = FocusNode();
  final FocusNode monthFocus = FocusNode();
  final FocusNode yearFocus = FocusNode();

  String? _error;
  List<DobField> _errorFields = const [];
  List<String> _lastText = const ['', '', ''];

  DateOfBirthController() {
    for (final c in [day, month, year]) {
      c.addListener(_onBoxChanged);
    }
  }

  String? get error => _error;
  List<DobField> get errorFields => _errorFields;

  /// Checks the boxes. On failure the message shows under them and
  /// the first wrong box gets focus; on success the "YYYY-MM-DD" to
  /// send is in the result.
  DobValidation validate({CalendarDate? today}) {
    final result = validateDateOfBirth(day: day.text, month: month.text, year: year.text, today: today);
    _error = result.error;
    _errorFields = result.fields;
    notifyListeners();
    if (!result.isValid && result.fields.isNotEmpty) {
      focusNodeFor(result.fields.first).requestFocus();
    }
    return result;
  }

  void clear() {
    day.clear();
    month.clear();
    year.clear();
    _setError(null, const []);
  }

  FocusNode focusNodeFor(DobField field) => switch (field) {
        DobField.day => dayFocus,
        DobField.month => monthFocus,
        DobField.year => yearFocus,
      };

  TextEditingController textFor(DobField field) => switch (field) {
        DobField.day => day,
        DobField.month => month,
        DobField.year => year,
      };

  // Editing a box is how an error gets fixed, so a real text change
  // clears it straight away. Only text changes count: tapping into
  // a box (a selection change) leaves the message up to read.
  void _onBoxChanged() {
    final now = [day.text, month.text, year.text];
    final changed = now[0] != _lastText[0] || now[1] != _lastText[1] || now[2] != _lastText[2];
    _lastText = now;
    if (changed) {
      if (_error != null) {
        _setError(null, const []);
      } else {
        notifyListeners(); // read-back
      }
    }
  }

  void _setError(String? message, List<DobField> fields) {
    _error = message;
    _errorFields = fields;
    notifyListeners();
  }

  @override
  void dispose() {
    for (final c in [day, month, year]) {
      c.removeListener(_onBoxChanged);
      c.dispose();
    }
    dayFocus.dispose();
    monthFocus.dispose();
    yearFocus.dispose();
    super.dispose();
  }
}

class DateOfBirthFields extends StatelessWidget {
  final DateOfBirthController controller;
  final bool enabled;

  /// Called when the keyboard's done key is pressed in the Year box.
  final VoidCallback? onSubmitted;

  const DateOfBirthFields({
    super.key,
    required this.controller,
    this.enabled = true,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final typed = typedCalendarDate(controller.day.text, controller.month.text, controller.year.text);
        final error = controller.error;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cake_outlined, color: _accent.withValues(alpha: 0.7), size: 18),
                const SizedBox(width: 8),
                const Flexible(
                  child: Text(
                    'Date of birth',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Type it as numbers. For example: 27\u00a03\u00a02007',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _box(DobField.day, 'Day', 2, AutofillHints.birthdayDay)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _box(DobField.month, 'Month', 2, AutofillHints.birthdayMonth)),
                const SizedBox(width: 10),
                Expanded(flex: 3, child: _box(DobField.year, 'Year', 4, AutofillHints.birthdayYear)),
              ],
            ),
            const SizedBox(height: 8),
            // The read-back and the error share one slot, so the
            // layout doesn't jump when either appears.
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  key: const Key('dob-error'),
                  style: const TextStyle(color: _errorText, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              )
            else
              Semantics(
                liveRegion: true,
                child: Text(
                  typed == null ? '' : "That's ${typed.toLongString()}",
                  key: const Key('dob-readback'),
                  style: const TextStyle(color: _accent, fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _box(DobField field, String label, int maxLength, String autofillHint) {
    final invalid = controller.errorFields.contains(field);
    final isLast = field == DobField.year;
    // MergeSemantics makes a screen reader announce the label with
    // its box ("Day, edit box") rather than as separate text.
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: invalid ? _danger.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.07),
              border: Border.all(
                color: invalid ? _danger : Colors.white.withValues(alpha: 0.1),
                width: invalid ? 1.5 : 1,
              ),
            ),
            child: TextField(
              key: Key('dob-${field.name}'),
              controller: controller.textFor(field),
              focusNode: controller.focusNodeFor(field),
              enabled: enabled,
              keyboardType: TextInputType.number,
              textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
              onSubmitted: isLast ? (_) => onSubmitted?.call() : null,
              autofillHints: [autofillHint],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(maxLength),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              cursorColor: _accent,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
