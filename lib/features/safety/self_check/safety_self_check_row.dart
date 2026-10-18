import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/pulse/providers/pulse_providers.dart'
    show currentRelationshipIdProvider;
import 'package:attune/features/safety/self_check/safety_self_check_screen.dart';
import 'package:attune/features/safety/self_check/safety_self_check_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// When the private check was last answered (null: never).
final safetySelfCheckAnsweredAtProvider = FutureProvider.autoDispose
    .family<DateTime?, String>(
      (ref, relationshipId) =>
          ref.read(safetySelfCheckServiceProvider).answeredAt(relationshipId),
    );

void _open(BuildContext context, String relationshipId) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SafetySelfCheckScreen(relationshipId: relationshipId),
      ),
    );

/// The way in (Spec 8, F14): the same title and look whether or not it was
/// answered (plan review I1). [dueOnly] (Pulse) shows it only when it was
/// never answered or more than 90 days ago.
class SafetySelfCheckRow extends ConsumerWidget {
  const SafetySelfCheckRow({super.key, this.dueOnly = false});

  final bool dueOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(safetySelfCheckEnabledProvider).valueOrNull ?? false)) {
      return const SizedBox.shrink();
    }
    final relationshipId = ref.watch(currentRelationshipIdProvider).valueOrNull;
    if (relationshipId == null) return const SizedBox.shrink();
    if (dueOnly) {
      final answered = ref.watch(
        safetySelfCheckAnsweredAtProvider(relationshipId),
      );
      if (!answered.hasValue ||
          !safetySelfCheckDue(answered.value, DateTime.now())) {
        return const SizedBox.shrink();
      }
    }
    return InfoRowWidget(
      title: safetySelfCheckRowTitle,
      subtitle: 'Just for you. Nothing is stored or shared.',
      icon: Icons.shield_moon_outlined,
      showAvatar: false,
      showTrailingArrow: true,
      onTap: () => _open(context, relationshipId),
    );
  }
}

/// The end of Ask-2 (plan review §1.8): offered once, skippable, never
/// stored with the Ask-2 answers.
Future<void> offerSafetySelfCheck(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!(await container.read(safetySelfCheckEnabledProvider.future))) return;
  if (!context.mounted) return;
  final relationshipId = await container.read(
    currentRelationshipIdProvider.future,
  );
  if (relationshipId == null || !context.mounted) return;
  final start = await showModalBottomSheet<bool>(
    context: context,
    builder:
        (context) => SafeArea(
          child: Padding(
            padding: EdgeInsets.all(Spacing.lg.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  safetySelfCheckRowTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Gap(Spacing.sm.h),
                const Text(
                  'Four quick questions, just for you. Nothing is stored or '
                  'shared.',
                ),
                Gap(Spacing.lg.h),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Start'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Not now'),
                ),
              ],
            ),
          ),
        ),
  );
  if (start == true && context.mounted) _open(context, relationshipId);
}
