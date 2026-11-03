import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/couple_profile/presentation/about_us_entry.dart';
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// R3's About us card (§3.8 R3), on the pending state only: the draft.
class AboutUsCard extends ConsumerWidget {
  const AboutUsCard({super.key, this.partnerName});

  /// R1's first name for the partner (this phone only), if typed.
  final String? partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(coupleProfileEnabledProvider)) {
      return const SizedBox.shrink();
    }
    final loc = AppLocalizations.of(context)!;
    final name = partnerName;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.md),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          // R3's SpaceRow look, but the body is never cut at 200% text
          // (SpaceRow stops at 4 lines; this body says who sees what).
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: InfoRowWidget(
              title: loc.aboutUs_cardTitle,
              subtitle:
                  name == null
                      ? loc.aboutUs_cardBodyUnnamed
                      : loc.aboutUs_cardBody(name),
              icon: Icons.favorite_border_rounded,
              onTap: () => context.push(aboutUsLocation(null), extra: name),
              showDivider: false,
              showTrailingArrow: true,
              titleMaxLines: 3,
              subTitleMaxLines: 12,
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
            ),
          ),
        ),
      ),
    );
  }
}
