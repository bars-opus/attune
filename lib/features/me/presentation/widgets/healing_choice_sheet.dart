import 'package:attune/app/routing/app_router.dart' show RouteNames;
import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/ui/text/allow_large_text.dart';
import 'package:attune/core/widgets/circular_documentation_container.dart';
import 'package:attune/features/me/presentation/widgets/your_space_section.dart';
import 'package:attune/features/safety/presentation/providers/support_resources_providers.dart';
import 'package:attune/i10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

/// What the Healing row's "After a breakup or a loss" was (Spec 1 §3.10).
enum HealingChoice { breakup, loss }

/// Where grief support lives: the Support screen's grief view (W7a).
final griefSupportLocation = '${RouteNames.safetyResources}?focus=grief';

/// Spec 1 W7a (§3.10): with support_resources_v2 on, the Healing row asks
/// first. "A breakup" opens Healing as before; "Someone I love died" opens
/// grief support, with "Write about it in your journal". Off: Healing as
/// before, no question.
Future<void> openHealingOrGrief(BuildContext context, WidgetRef ref) async {
  if (!ref.read(supportResourcesV2Provider)) return openHealing(context, ref);
  final choice = await _showHealingChoice(context);
  if (!context.mounted) return;
  switch (choice) {
    case HealingChoice.breakup:
      await openHealing(context, ref);
    case HealingChoice.loss:
      await context.push(griefSupportLocation);
    case null:
      break;
  }
}

/// The question, never animated (§2.2; W7 ruling PF-M1): showModalBottomSheet
/// directly, not the shared BottomSheetUtils (left as it is), with that
/// helper's chrome (the drag handle, the rounded top, the surface, the
/// tablet width) and sized to its content.
Future<HealingChoice?> _showHealingChoice(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  final colorScheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<HealingChoice>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    sheetAnimationStyle: AnimationStyle.noAnimation,
    constraints: BoxConstraints(
      maxHeight: size.height * 0.9,
      maxWidth:
          size.shortestSide > Breakpoints.mobile
              ? ContentWidth.sheet
              : double.infinity,
    ),
    builder:
        (_) => CircularDocumentationContainer(
          color: colorScheme.surface,
          padding: 0,
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DragHandle(colorScheme: colorScheme),
                  const HealingChoiceSheet(),
                ],
              ),
            ),
          ),
        ),
  );
}

/// The pill every app sheet has at its top (BottomSheetUtils' own is
/// private; same size and colour).
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('healing_choice_handle'),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Center(
        child: Container(
          width: 40.w,
          height: 4.h,
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(2.r),
          ),
        ),
      ),
    );
  }
}

class HealingChoiceSheet extends StatelessWidget {
  const HealingChoiceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    Widget option(String label, HealingChoice choice) => Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 56),
          alignment: AlignmentDirectional.centerStart,
          foregroundColor: theme.colorScheme.onSurface,
        ),
        onPressed: () => Navigator.of(context).pop(choice),
        child: Text(label),
      ),
    );
    // The phone's text size, up to 2.0 (§2.3): the root shell clamps
    // every route, this sheet's too, to 1.0.
    return AllowLargeText(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          Spacing.sm,
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
                loc.flow_healingChoiceTitle,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            option(loc.flow_healingBreakup, HealingChoice.breakup),
            option(loc.flow_healingLoss, HealingChoice.loss),
          ],
        ),
      ),
    );
  }
}
