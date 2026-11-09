// Spec 2 §3.2 D5 off-country: "Support for you" — the country's
// support_resources in the lgbtq_legal and crisis categories (S1 W7a). Each
// row is Spec 1's own resource card (fix 1, I-1): the police tag, the
// hours, the dial string, text and WhatsApp, and each confirm saying what
// it may leave on the phone. Nothing is stored; reading the list says
// nothing about why it was opened.
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/auth/sign_up/presentation/widgets/flow_buttons.dart';
import 'package:attune/features/dating/data/dating_names.dart';
import 'package:attune/features/dating/lock/dating_sheets.dart';
import 'package:attune/features/safety/data/support_resources_repository.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/features/safety/presentation/screens/support_resources_v2_screen.dart'
    show SupportResourceCard, openSupportLinkConfirmed;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showDatingSupportSheet(
  BuildContext context, {
  required String country,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  // Final fix (I-1b): a Dating sheet, closed when the unlock ends.
  routeSettings: datingSheetSettings('support'),
  builder:
      (sheet) => DatingSheetTracker(
        child: AllowLargeText(child: _Support(country: country)),
      ),
);

class _Support extends ConsumerWidget {
  const _Support({required this.country});

  final String country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final read = ref.watch(supportResourcesProvider(country));
    // A failed read is the directory link, never the error (carry C).
    final list = read.hasError ? null : read.valueOrNull;
    final loading = read.isLoading && list == null;
    final shown = [
      for (final r in list?.resources ?? const <SupportResource>[])
        if (r.category == SupportCategory.lgbtqLegal ||
            r.category == SupportCategory.crisis)
          r,
    ];
    final directory = list?.directoryUrl ?? supportDirectoryUrl;
    return SafeArea(
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
                loc.dating_supportForYou,
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              datingCountryName(loc, country),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: Spacing.md),
            if (loading) const Center(child: CircularProgressIndicator()),
            for (final r in shown) SupportResourceCard(resource: r),
            if (!loading && shown.isEmpty)
              FlowTextLink(
                label: loc.support_findHelpline,
                alignment: AlignmentDirectional.centerStart,
                onPressed:
                    () => openSupportLinkConfirmed(context, ref, directory),
              ),
            const SizedBox(height: Spacing.md),
            FlowSecondaryButton(
              label: loc.dating_close,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
