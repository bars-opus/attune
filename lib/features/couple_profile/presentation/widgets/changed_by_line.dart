import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/couple_profile/presentation/about_us_copy.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

/// "Changed by {first name or 'you'} - {date}" under an answered About us
/// row (Spec 1 §3.8, D2). A first name from the server, never an id.
class ChangedByLine extends StatelessWidget {
  const ChangedByLine({super.key, required this.change, this.now});

  final FieldChange change;

  /// Today, for "this year or not" (tests pin it).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Text(
      changedByText(loc, change, now ?? DateTime.now()),
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
