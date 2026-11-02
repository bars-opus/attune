import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/features/me/presentation/path_switch.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/onboarding/domain/home_state.dart';
import 'package:attune/features/onboarding/presentation/path_chooser.dart'
    show PathChoiceOutcome;
import 'package:attune/features/onboarding/presentation/providers/home_state_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// J4 · "More ways to use Attune" (Spec 1 §3.10, research 09 P19): one
/// neutral row; the sheet offers the two other paths.
class MoreWaysRow extends ConsumerWidget {
  const MoreWaysRow({super.key, required this.home});

  /// The home the screen shows; the row waits for its live path.
  final HomeSnapshot home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = home.path;
    if (path == null) return const SizedBox.shrink();
    final loc = AppLocalizations.of(context)!;
    return SpaceRow(
      title: loc.flow_moreWays,
      subtitle: '',
      icon: Icons.alt_route_outlined,
      onTap: () async {
        final to = await showModalBottomSheet<AppPath>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          // Ruling M-4 (09 P15): no Dating inside an ending window.
          builder:
              (_) => MoreWaysSheet(
                current: path,
                offerDating: home.link != LinkState.endedWindow,
              ),
        );
        if (to != null && context.mounted) {
          final outcome = await switchPath(context, ref, to: to, home: home);
          // B4 review M-2: a shared space opened since this screen read
          // the home: pause or end it first (§3.12, P-18).
          if (outcome == PathChoiceOutcome.relationshipOpen &&
              context.mounted) {
            await showSharedSpaceSheetAfterRefusal(context, home);
          }
        }
      },
    );
  }
}

/// The two paths the person isn't on (§3.10 J4). Pops the chosen one.
class MoreWaysSheet extends StatelessWidget {
  const MoreWaysSheet({
    super.key,
    required this.current,
    this.offerDating = true,
  });

  final AppPath current;

  /// False inside an ending window (ruling M-4): Dating stays in Settings.
  final bool offerDating;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final options = [
      if (current != AppPath.relationship)
        (
          AppPath.relationship,
          loc.flow_moreInvite,
          loc.flow_pathRelationshipLine,
        ),
      if (current != AppPath.dating && offerDating)
        (AppPath.dating, loc.flow_pathDatingTitle, loc.flow_pathDatingLine),
      if (current != AppPath.justMe)
        (AppPath.justMe, loc.flow_pathJustMeTitle, loc.flow_pathJustMeLine),
    ];
    return AllowLargeText(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  loc.flow_moreWays,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: Spacing.sm),
              for (final (path, title, line) in options)
                SpaceRow(
                  title: title,
                  subtitle: line,
                  icon: switch (path) {
                    AppPath.relationship => Icons.favorite_outline,
                    AppPath.dating => Icons.people_outline,
                    AppPath.justMe => Icons.person_outline,
                  },
                  onTap: () => Navigator.of(context).pop(path),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
