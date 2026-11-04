import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/reflection_journal/presentation/widgets/journal_support_card.dart'
    show JournalSupportCard;
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens Support (W7a's screen and route; with support_resources_v2 off,
/// today's Safety resources screen). Spec 1 W9e: Healing's opens are not
/// counted (plan P-6). Nothing about it is stored on the phone.
void openHealingSupport(BuildContext context) =>
    context.push(RouteNames.safetyResources);

/// The writer's card on a Healing stage (Spec 1 W9e): W9c's card, the same
/// words the clinician signs, shown instead of the AI text when the crisis
/// check answers `support_offered`. Never animated (spec 2.2); large text let
/// through.
class HealingSupportCard extends StatelessWidget {
  const HealingSupportCard({super.key, required this.onNotNow});

  final VoidCallback onNotNow;

  @override
  Widget build(BuildContext context) => JournalSupportCard(
    onNotNow: onNotNow,
    onSeeSupport: () => openHealingSupport(context),
  );
}

/// "Need support now?" at the end of the Healing reflection (Spec 1 W9e):
/// always there, whatever healing_ai_insights says. Looks like W9b's link.
class HealingNeedSupportLink extends StatelessWidget {
  const HealingNeedSupportLink({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AllowLargeText(
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            minimumSize: const Size(48, 48),
            foregroundColor: scheme.onSurface,
            padding: Spacing.horizontalSm,
          ),
          onPressed: () => openHealingSupport(context),
          icon: const Icon(Icons.support_outlined, size: 20),
          label: Text(loc.support_needSupportNow),
        ),
      ),
    );
  }
}
