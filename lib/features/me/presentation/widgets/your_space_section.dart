import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/bottom_sheet_utils.dart';
import 'package:attune/core/utils/exports/export_screens.dart' show RouteNames;
import 'package:attune/core/widgets/info_row_widget.dart';
import 'package:attune/features/healing/presentation/providers/healing_providers.dart';
import 'package:attune/features/healing/presentation/widgets/healing_self_report_sheet.dart';
import 'package:attune/features/profile/widgets/know_yourself_section.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The space's heading with a way to Settings (Spec 1 §3.10, §3.8 R3).
class SpaceHeader extends StatelessWidget {
  const SpaceHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              loc.flow_spaceTitle,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: loc.flow_settingsTooltip,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.pushNamed('settings'),
        ),
      ],
    );
  }
}

/// "Your space" (Spec 1 §3.10 rows; §3.8 R3): Journal, Quizzes, Healing,
/// on Me and on the Relationship space alike. [extraRows] go last.
class YourSpaceSection extends ConsumerWidget {
  const YourSpaceSection({super.key, this.extraRows = const []});

  final List<Widget> extraRows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md,
          vertical: Spacing.sm,
        ),
        child: Column(
          children: [
            SpaceRow(
              title: loc.flow_spaceJournal,
              subtitle: loc.flow_spaceJournalLine,
              icon: Icons.menu_book_outlined,
              onTap: () => context.pushNamed('reflectionJournal'),
            ),
            SpaceRow(
              title: loc.flow_spaceQuizzes,
              subtitle: loc.flow_spaceQuizzesLine,
              icon: Icons.psychology_outlined,
              onTap: () => openQuizzes(context),
            ),
            SpaceRow(
              title: loc.flow_spaceHealing,
              subtitle: loc.flow_spaceHealingLine,
              icon: Icons.healing_outlined,
              onTap: () => openHealing(context, ref),
            ),
            ...extraRows,
          ],
        ),
      ),
    );
  }
}

/// One row of the space: InfoRowWidget, labelled as one button, lines that
/// wrap at large text.
class SpaceRow extends StatelessWidget {
  const SpaceRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: InfoRowWidget(
        title: title,
        subtitle: subtitle,
        icon: icon,
        onTap: onTap,
        showDivider: false,
        showTrailingArrow: true,
        titleMaxLines: 3,
        subTitleMaxLines: 4,
        padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      ),
    );
  }
}

/// The quizzes, in a sheet: "Know yourself" (today's list, same gates).
Future<void> openQuizzes(BuildContext context) =>
    BottomSheetUtils.showDocumentationBottomSheet<void>(
      context: context,
      widget: const SingleChildScrollView(child: KnowYourselfSection()),
    );

/// Healing, as today's personal-mode entry does it (ChatCouplesLockedScreen):
/// the journey if one is under way, else the self-report sheet first.
Future<void> openHealing(BuildContext context, WidgetRef ref) async {
  final colorScheme = Theme.of(context).colorScheme;
  final active = await ref.read(hasActiveSoloHealingJourneyProvider.future);
  if (!context.mounted) return;
  if (active) {
    await context.push(RouteNames.healingJourney);
    return;
  }
  final started = await BottomSheetUtils.showDocumentationBottomSheet<bool>(
    context: context,
    backgroundColor: colorScheme.surface,
    widget: const HealingSelfReportSheet(),
  );
  if (started == true && context.mounted) {
    await context.push(RouteNames.healingJourney);
  }
}
