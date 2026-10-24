/// The lines under the rings row that say what the outbox is doing
/// (spec §6.1; Wave 2 Task 18): a story on its way (with Cancel), a story
/// that will not post on its own (why, Retry only when it can help, and a
/// Discard that asks first), and a take that failed after its camera had
/// closed.
library;

import 'dart:async';

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/domain/captured_media.dart';
import 'package:attune/features/stories/domain/story_post_copy.dart';
import 'package:attune/features/stories/domain/story_ring_copy.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/state/story_post_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _noun(CapturedMediaType t) =>
    t == CapturedMediaType.image ? 'photo' : 'video';

/// Shown when Cancel comes too late: finalize was sent, or the story has
/// already left the queue (batch-3 review N1).
const String storyAlreadyPostedCopy =
    'It has already posted. You can delete it from your story.';

/// Discard on a previous relationship's story whose finalize was already
/// sent (batch-4 review #4).
const String storyOrphanMayHavePostedCopy =
    'It may already have posted — check your story.';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String keep,
  required String destroy,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(keep),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text(destroy),
            ),
          ],
        ),
  );
  return result == true;
}

/// A 48 dp text action.
class _NoticeAction extends StatelessWidget {
  const _NoticeAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      minimumSize: const Size(48, 48),
      tapTargetSize: MaterialTapTargetSize.padded,
    ),
    child: Text(label),
  );
}

/// Under the rings when their read failed (03 M3): says whether the rings
/// above are the last known ones, and offers Retry.
class StoryRingsLoadErrorNotice extends StatelessWidget {
  const StoryRingsLoadErrorNotice({
    super.key,
    required this.showingLastKnown,
    required this.onRetry,
  });

  final bool showingLastKnown;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _NoticeRow(
    icon: Icons.cloud_off_rounded,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    text: storyRingsLoadErrorCopy(showingLastKnown: showingLastKnown),
    actions: [_NoticeAction(label: 'Retry', onPressed: onRetry)],
  );
}

/// Icon, message and actions on one line; on a narrow screen or with large
/// text the actions move under the message so it is never squeezed.
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.icon,
    required this.color,
    required this.text,
    required this.actions,
  });

  final IconData icon;
  final Color color;
  final String text;
  final List<Widget> actions;

  static const double _stackBelowWidth = 360;
  static const double _stackAboveTextScale = 1.3;

  @override
  Widget build(BuildContext context) {
    final message = Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    );
    final lead = [
      ExcludeSemantics(child: Icon(icon, size: IconSizes.sm, color: color)),
      const SizedBox(width: Spacing.xs),
    ];
    // Below, not above: the rings row ends with my ring's `+` overhang,
    // already the gap above the first notice; this keeps the next notice
    // (or the chat card) off this one.
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final stacked =
                constraints.maxWidth < _stackBelowWidth ||
                scale > _stackAboveTextScale;
            if (!stacked) {
              return Row(
                children: [...lead, Expanded(child: message), ...actions],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [...lead, Expanded(child: message)],
                ),
                if (actions.isNotEmpty)
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: Spacing.xs,
                      children: actions,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The story on its way: what it is waiting for, and Cancel (01 #13).
///
/// Cancel, never Discard: Discard cannot stop a finalize already on the
/// wire, so a "discarded" story could still post. Cancel refuses once
/// finalize has been sent, and is not offered at all while the row is
/// finalizing.
class StoryPendingNotice extends ConsumerWidget {
  const StoryPendingNotice({super.key, required this.record});

  final StoryOutboxRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    return _NoticeRow(
      icon: Icons.cloud_upload_outlined,
      color: colors.onSurfaceVariant,
      text: storyPendingStatus(record),
      actions: [
        if (record.state != StoryOutboxState.finalizing)
          _NoticeAction(
            label: 'Cancel',
            onPressed: () => unawaited(_cancel(context, ref)),
          )
        else if (storyFinalizingMayBeStuck(record))
          // Never Cancel (it may be live), but not stuck forever either
          // (final review #3d): Discard, saying it may already have posted.
          _NoticeAction(
            label: 'Discard',
            onPressed: () => unawaited(_discardStuck(context, ref)),
          ),
      ],
    );
  }

  Future<void> _discardStuck(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(storyOutboxProvider.notifier);
    final ok = await _confirm(
      context,
      title: 'Discard this ${_noun(record.mediaType)}?',
      body:
          "It may already have posted. Check your story first. If it hasn't, "
          "it can't be recovered.",
      keep: 'Keep',
      destroy: 'Discard',
    );
    if (ok) await notifier.discard(record.clientStoryId);
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(storyOutboxProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirm(
      context,
      title: 'Cancel this story?',
      body: "It hasn't been posted yet.",
      keep: 'Keep posting',
      destroy: 'Cancel story',
    );
    if (!ok) return;
    final outcome = await notifier.cancel(record.clientStoryId);
    switch (outcome) {
      case StoryCancelOutcome.cancelled:
        break;
      case StoryCancelOutcome.alreadyPosting:
      case StoryCancelOutcome.notFound:
        messenger.showSnackBar(
          const SnackBar(content: Text(storyAlreadyPostedCopy)),
        );
    }
  }
}

/// The surface for a story that will never post on its own.
///
/// Spec §6.1: a failed upload "never silently disappears" — it is worse
/// here than in chat, because there is no bubble to hang a retry off. The
/// outbox RETAINS these records; this is where `retry()`/`discard()` are
/// called. Deliberately a plain row rather than a ring overlay: a dead
/// record must not outrank a real, already-posted story on the ring (the
/// F2 finding in story_rings_row.dart's header), so it gets its own space
/// beneath. It says why (01 #20), offers Retry only where retrying can
/// help, and asks before Discard, which deletes the only copy (06 #14).
class StoryFailedNotice extends ConsumerWidget {
  const StoryFailedNotice({super.key, required this.record});

  final StoryOutboxRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final notifier = ref.read(storyOutboxProvider.notifier);
    final copy = storyOutboxFailureCopy(record.lastErrorCode, record.mediaType);
    return _NoticeRow(
      icon: Icons.error_outline_rounded,
      color: colors.error,
      text: copy.message,
      actions: [
        if (copy.canRetry)
          _NoticeAction(
            label: 'Retry',
            onPressed: () => unawaited(notifier.retry(record.clientStoryId)),
          ),
        _NoticeAction(
          label: 'Discard',
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: 'Discard this ${_noun(record.mediaType)}?',
              body: "It hasn't been posted, and it can't be recovered.",
              keep: 'Keep',
              destroy: 'Discard',
            );
            if (ok) await notifier.discard(record.clientStoryId);
          },
        ),
      ],
    );
  }
}

/// Outbox records for any relationship other than [activeRelationshipId]
/// (03 M6): they can never post, so they get one grouped line with
/// Discard. No Retry, because there is nowhere to post them.
class StoryOrphanedPostsNotice extends ConsumerWidget {
  const StoryOrphanedPostsNotice({
    super.key,
    required this.activeRelationshipId,
  });

  /// The relationship the rings show, or null when there is none (then the
  /// notice stands alone, outside the rings row, and pads itself like it).
  final String? activeRelationshipId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orphans = [
      for (final record in ref.watch(storyOutboxProvider))
        if (record.relationshipId != activeRelationshipId) record,
    ];
    if (orphans.isEmpty) return const SizedBox.shrink();
    final notifier = ref.read(storyOutboxProvider.notifier);
    final one = orphans.length == 1;
    final notice = _NoticeRow(
      icon: Icons.error_outline_rounded,
      color: Theme.of(context).colorScheme.error,
      text: storyOrphanedPostsCopy(orphans.length),
      actions: [
        _NoticeAction(
          label: 'Discard',
          onPressed: () async {
            final ok = await _confirm(
              context,
              title: one ? 'Discard this story?' : 'Discard these stories?',
              body: one
                  ? "It hasn't been posted, and it can't be recovered."
                  : "They haven't been posted, and they can't be recovered.",
              keep: 'Keep',
              destroy: 'Discard',
            );
            if (!ok || !context.mounted) return;
            final messenger = ScaffoldMessenger.maybeOf(context);
            var tooLate = false;
            for (final record in orphans) {
              if (record.state == StoryOutboxState.failedPermanent) {
                await notifier.discard(record.clientStoryId);
              } else {
                final outcome = await notifier.cancel(record.clientStoryId);
                // Finalize was sent: it may be live, and stays queued.
                if (outcome == StoryCancelOutcome.alreadyPosting) {
                  tooLate = true;
                }
              }
            }
            if (tooLate) {
              messenger?.showSnackBar(
                const SnackBar(content: Text(storyOrphanMayHavePostedCopy)),
              );
            }
          },
        ),
      ],
    );
    if (activeRelationshipId != null) return notice;
    // No rings row above it (Conversations with no relationship), so no
    // `+` overhang to sit under: bring the row's own 8 dp top and inset,
    // keeping the 8 / 14 / 8 rhythm (batch-2 review nit 7).
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.sm,
      ),
      child: notice,
    );
  }
}

/// A take that failed (or lost its place) after its camera had closed
/// (Task 16's [storyPostNoticeProvider]). Shown only to the account it was
/// raised for, until OK.
class StoryPrepareFailedNotice extends ConsumerWidget {
  const StoryPrepareFailedNotice({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(storyPostNoticeProvider);
    final myId = ref.watch(currentUserProvider.select((user) => user?.id));
    if (notice == null || notice.userId != myId) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).colorScheme;
    final shared = notice.code == 'place_dropped';
    return _NoticeRow(
      icon: shared ? Icons.location_off_outlined : Icons.error_outline_rounded,
      color: shared ? colors.onSurfaceVariant : colors.error,
      text: storyPostNoticeMessage(notice.code, notice.mediaType),
      actions: [
        _NoticeAction(
          label: 'OK',
          onPressed:
              () => ref.read(storyPostNoticeProvider.notifier).state = null,
        ),
      ],
    );
  }
}
