import 'package:attune/core/utils/date_formatter.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:attune/features/relationships/domain/relationship_lifecycle.dart';
import 'package:attune/features/relationships/presentation/relationship_lifecycle_providers.dart';
import 'package:attune/features/relationships/presentation/widgets/end_relationship_action.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _date(DateTime? at) =>
    at == null ? '' : MyDateFormat.toDate(at.toLocal());

/// Paused: "{N} days left to decide."; under a day: "Less than a day…".
String pausedDaysCopy(int days) => switch (days) {
  0 => 'Chat is read-only. Less than a day left to decide.',
  1 => 'Chat is read-only. 1 day left to decide.',
  _ => 'Chat is read-only. $days days left to decide.',
};

/// The lifecycle hub at the top of the couples-locked chat screen (Spec 3a;
/// research 06 §3 F1 (2)-(4), (6)). Paused: read, resume, end. Ended and
/// still readable: read until the window closes, or seal this side. Closed,
/// sealed or archived: what happened, with no buttons. The one-time clear
/// and the ending sheet are the app shell's (RelationshipLifecycleWatcher).
class RelationshipLifecycleCard extends ConsumerStatefulWidget {
  const RelationshipLifecycleCard({super.key});

  @override
  ConsumerState<RelationshipLifecycleCard> createState() =>
      _RelationshipLifecycleCardState();
}

class _RelationshipLifecycleCardState
    extends ConsumerState<RelationshipLifecycleCard> {
  bool _busy = false;

  Future<void> _run(
    Future<void> Function(RelationshipLifecycleService s) act,
  ) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await act(ref.read(relationshipLifecycleServiceProvider));
      ref.invalidate(relationshipLifecycleProvider);
      ref.invalidate(activeRelationshipIdProvider);
      relationshipModeResyncSignal.value++;
    } catch (error) {
      if (mounted) {
        context.showErrorSnackbar(
          error is RelationshipLifecycleException
              ? error.message
              : "Couldn't do that. Please try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _readChat(RelationshipLifecycle l) => context.push(
    '${RouteNames.chatChannel}?relationshipId=${l.relationshipId}',
  );

  void _confirmSeal(RelationshipLifecycle l) {
    BottomSheetUtils.showDocumentationBottomSheet(
      maxHeight: 380.h,
      context: context,
      widget: ConfirmationDialog(
        noIcon: true,
        type: ConfirmationType.warning,
        title: 'Seal your side now?',
        message:
            "Your chat closes for you now. It can't be opened again. "
            'Download what you shared first: Settings → Download my data.',
        confirmText: 'Seal',
        onConfirm: () => _run((s) => s.seal(l.relationshipId)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lifecycle = ref.watch(relationshipLifecycleProvider).valueOrNull;
    if (lifecycle == null) return const SizedBox.shrink();

    final now = ref.read(lifecycleClockProvider)();
    final paused = lifecycle.status == LifecycleStatus.paused;
    final readableEnding =
        lifecycle.status == LifecycleStatus.ended &&
        lifecycle.chatReadable &&
        !lifecycle.sealedByMe;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Sealed, archived, or past day 30 before the hourly cron: no buttons
    // over an empty chat (review I8); the screen still says what happened.
    if (!paused && !readableEnding) {
      final closedWindow =
          lifecycle.status == LifecycleStatus.ended && !lifecycle.sealedByMe;
      return Padding(
        padding: EdgeInsets.only(bottom: Spacing.md.h),
        child: CardInkWell(
          child:
              closedWindow
                  ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your shared space has ended',
                        style: text.titleMedium,
                      ),
                      Gap(Spacing.xs.h),
                      Text(
                        'Your chat has closed. It is deleted 12 months from now.',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                  : Text(
                    'Your shared space has ended.',
                    style: text.bodyMedium,
                  ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: Spacing.md.h),
      child: CardInkWell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              paused
                  ? 'Your shared space is paused'
                  : 'Your shared space has ended',
              style: text.titleMedium,
            ),
            Gap(Spacing.xs.h),
            Text(
              paused
                  ? pausedDaysCopy(daysLeft(lifecycle.decideBy, now))
                  : 'You can read your chat until '
                      '${_date(lifecycle.windowEndsAt)}. After that it closes, '
                      'and 12 months later it is deleted.',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Gap(Spacing.sm.h),
            Wrap(
              spacing: Spacing.sm.w,
              runSpacing: Spacing.xs.h,
              children: [
                if (lifecycle.chatReadable)
                  OutlinedButton(
                    onPressed: _busy ? null : () => _readChat(lifecycle),
                    child: const Text('Read our chat'),
                  ),
                if (paused) ...[
                  FilledButton(
                    onPressed:
                        _busy
                            ? null
                            : () =>
                                _run((s) => s.resume(lifecycle.relationshipId)),
                    child: const Text('Resume'),
                  ),
                  TextButton(
                    onPressed:
                        _busy
                            ? null
                            : () => EndRelationshipAction.confirmAndEnd(
                              context,
                              relationshipId: lifecycle.relationshipId,
                              service: ref.read(
                                relationshipLifecycleServiceProvider,
                              ),
                              // The card must not offer Resume over an
                              // ended space (final review IMP-4).
                              onEnded: () {
                                ref.invalidate(relationshipLifecycleProvider);
                                ref.invalidate(activeRelationshipIdProvider);
                              },
                            ),
                    child: const Text('End'),
                  ),
                ] else ...[
                  // Spec 3c: what's theirs, before the window closes.
                  OutlinedButton(
                    onPressed:
                        _busy ? null : () => context.push(RouteNames.dataExport),
                    child: const Text('Download what we shared'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _confirmSeal(lifecycle),
                    child: const Text('Seal my side now'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
