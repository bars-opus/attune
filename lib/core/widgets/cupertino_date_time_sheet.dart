// lib/core/widgets/cupertino_date_time_sheet.dart

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Shows a bottom-sheet Cupertino wheel picker (date, time, or both) and
/// auto-saves as the wheel scrolls via [onChanged] — there is no Cancel/Done
/// bar, matching the pattern this was extracted from
/// (HealingSelfReportSheet's original _pickDate): a single value with an
/// always-reachable "reopen and change it again" undo has no real cost to
/// skipping a confirm gesture, and it removes the failure mode where a user
/// picks a value, doesn't notice or bother tapping Done, and the value never
/// actually saves.
///
/// [onChanged] fires on every scroll frame, not just once on dismiss — the
/// caller is expected to `setState`/store the value on each call the same
/// way the original implementation did, so whatever UI is showing the
/// current value (e.g. a title/subtitle behind this sheet) updates live
/// while the wheel is still moving, not just after the sheet closes.
///
/// This is the whole picker's UI — callers don't build their own
/// SizedBox/CupertinoDatePicker; they just await this and read the value(s)
/// back out of their own state via [onChanged].
Future<void> showCupertinoDateTimeSheet({
  required BuildContext context,
  required CupertinoDatePickerMode mode,
  required DateTime initialDateTime,
  required ValueChanged<DateTime> onChanged,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        top: false,
        child: SizedBox(
          height: 216,
          child: CupertinoDatePicker(
            mode: mode,
            initialDateTime: initialDateTime,
            minimumDate: minimumDate,
            maximumDate: maximumDate,
            onDateTimeChanged: onChanged,
          ),
        ),
      );
    },
  );
}
