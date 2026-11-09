// Spec 2 §2.4, §3.2 D5 (10 S3): the static "Why?" sheet. Opening it calls
// nothing: no RPC, no counter, no log. Used by the kill-switch note, D5 and
// D6.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';

Future<void> showDatingWhySheet(
  BuildContext context, {
  required String country,
}) {
  final loc = AppLocalizations.of(context)!;
  final name = datingCountryName(loc, country);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Final fix (I-1b): a Dating sheet, closed when the unlock ends.
    routeSettings: datingSheetSettings('why'),
    builder:
        (sheet) => DatingSheetTracker(
          child: AllowLargeText(
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  0,
                  Spacing.lg,
                  Spacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        loc.dating_why,
                        style: Theme.of(sheet).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      loc.dating_whyBody(name),
                      style: Theme.of(sheet).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: Spacing.lg),
                    FlowSecondaryButton(
                      label: loc.dating_close,
                      onPressed: () => Navigator.of(sheet).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
  );
}
