/// The two-ring row for the conversations screen (spec §5.1;
/// task-3-brief.md, Task 3). Sits ABOVE the conversation tile, per the
/// spec and the brief's reference image.
///
/// This is the one place that reads `storyRingSummaryProvider`'s
/// `Map<authorId, StoryRingSummary>` and turns it into what
/// [StoryRing] draws. Two rules from the brief/spec are enforced here,
/// not in [StoryRing] itself, because only this widget knows which
/// author is "me":
///
/// 1. **My ring is drawn unconditionally.** `storyRingSummaryProvider`
///    omits an author with zero active stories entirely (spec §5.1/§5.5,
///    `StoryRingSummary`'s own doc comment). This widget never asks
///    `summaries.containsKey(myId)` to decide WHETHER to render my ring
///    — only `summaries[myId]` to decide what to FILL it with. My
///    `StoryRing` is always in the tree, unconditionally, below.
/// 2. **An empty partner ring renders nothing at all** — not a greyed
///    ring, not a placeholder slot. When the partner has no active
///    stories, this widget places nothing in the row for them: no
///    `StoryRing`, no `SizedBox` reserving their space, nothing.
///    `story_rings_test.dart` asserts the partner's `StoryRing` is
///    entirely absent from the tree in that case, so a future change
///    that swaps this for an invisible-but-present placeholder fails
///    that test rather than silently drifting back into "a placeholder
///    reads as they have something" (spec §5.1).
///
/// The pending outbox tile (Plan B, `storyOutboxProvider`) overlays on
/// MY ring only — spec §6.1, "the Mine ring shows a local pending tile
/// with progress." A pending item takes priority over a finalized
/// summary for what the ring's thumbnail/progress show, since it is the
/// most recent thing the user did, and its local file is shown directly
/// (`StoryRing.localThumbnailPath`) since the server has not necessarily
/// produced a signed URL yet.
library;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/stories/data/story_outbox_record.dart';
import 'package:attune/features/stories/data/story_read_repository.dart'
    show StoryRingSummary;
import 'package:attune/features/stories/presentation/providers/story_providers.dart';
import 'package:attune/features/stories/presentation/state/story_outbox_controller.dart';
import 'package:attune/features/stories/presentation/widgets/story_ring.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rough upload-progress fraction per outbox state, for the pending
/// ring's progress indicator. Not a byte-accurate progress — the outbox
/// controller does not track partial-upload byte counts — just enough to
/// show the capture visibly advancing rather than sitting static (spec
/// §6.1's "the capture is visible before it is posted").
double _pendingProgressFor(StoryOutboxState state) {
  switch (state) {
    case StoryOutboxState.queued:
      return 0.05;
    case StoryOutboxState.uploadingMedia:
      return 0.35;
    case StoryOutboxState.uploadingThumbnail:
      return 0.7;
    case StoryOutboxState.finalizing:
      return 0.9;
    case StoryOutboxState.failedPermanent:
      return 1.0;
  }
}

class StoryRingsRow extends ConsumerWidget {
  const StoryRingsRow({
    super.key,
    required this.relationshipId,
    required this.partnerId,
    required this.partnerName,
    this.onOpenMine,
    this.onOpenPartner,
    this.onCapture,
  });

  final String relationshipId;
  final String partnerId;
  final String partnerName;

  /// Opens the caller's own reel. Not used when there is nothing to
  /// open yet (mine-empty taps the `+` instead).
  final VoidCallback? onOpenMine;

  /// Opens the partner's reel. Only ever wired when the partner's ring
  /// is actually drawn.
  final VoidCallback? onOpenPartner;

  /// Opens the story camera/capture flow (the `+` affordance).
  final VoidCallback? onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(currentUserProvider)?.id;
    final summariesAsync = ref.watch(storyRingSummaryProvider(relationshipId));
    final outbox = ref.watch(storyOutboxProvider);

    // A pending capture for a DIFFERENT relationship must not paint over
    // this row's ring — the outbox is per-user, not per-relationship
    // (story_outbox_controller.dart's own header), so a couple's screen
    // showing another active relationship's queued item would be wrong.
    StoryOutboxRecord? myPending;
    for (final record in outbox) {
      if (record.relationshipId == relationshipId) {
        myPending = record;
        break;
      }
    }

    final summaries = summariesAsync.valueOrNull ?? const {};
    final partnerSummary = partnerId.isEmpty ? null : summaries[partnerId];
    // Loading/error states for the summary fetch must not hide MY ring —
    // it is drawn unconditionally regardless of fetch state (rule 1 in
    // this file's header). A slow/failed fetch simply means it renders
    // empty until data arrives, exactly like "no stories yet" would.
    final mySummary = myId == null ? null : summaries[myId];

    final mySegmentCount = mySummary?.activeCount ?? 0;
    // The RPC's unviewed_count is defined as the PARTNER's-view-of-me
    // count on MY row (StoryRingSummary's doc comment: "always 0 for the
    // caller's own row by construction" — it counts MY unviewed items
    // from THEIR perspective, never populated for the caller's own
    // entry). For MY ring there is no "have I seen my own story" concept
    // at all, so every one of my own active segments renders bright:
    // unviewedCount mirrors segmentCount here rather than reading the
    // always-zero field literally, which would incorrectly fade every
    // segment on my own ring.
    final myUnviewedCount = mySegmentCount;

    final myRing = StoryRing(
      key: const ValueKey('story-ring-mine'),
      isMine: true,
      hasStories: myPending != null || mySegmentCount > 0,
      segmentCount: mySegmentCount,
      unviewedCount: myUnviewedCount,
      localThumbnailPath: myPending?.localThumbnailPath,
      pendingProgress: myPending == null
          ? null
          : _pendingProgressFor(myPending.state),
      onTap: myPending != null || mySegmentCount > 0 ? onOpenMine : null,
      onTapPlus: onCapture,
      semanticLabel: myPending != null
          ? 'Your story, posting'
          : mySegmentCount > 0
          ? 'Your story, $mySegmentCount ${mySegmentCount == 1 ? 'item' : 'items'}'
          : 'Add to your story',
    );

    final showPartnerRing =
        partnerSummary != null && partnerSummary.activeCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.md,
        vertical: Spacing.sm,
      ),
      child: SizedBox(
        height:
            kStoryRingThumbnailDiameter +
            2 * (kStoryRingGap + kStoryRingStrokeWidth) +
            4,
        child: Row(
          children: [
            myRing,
            // Nothing at all for an empty partner ring — no SizedBox, no
            // placeholder slot. Rule 2 in this file's header.
            if (showPartnerRing) ...[
              const SizedBox(width: Spacing.md),
              _PartnerRing(
                summary: partnerSummary,
                partnerName: partnerName,
                onTap: onOpenPartner,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Separated so [storyMediaSignedUrlProvider] is only watched when the
/// partner actually has a ring to draw — avoids minting a signed URL
/// request for a key that does not exist when there is nothing to show.
class _PartnerRing extends ConsumerWidget {
  const _PartnerRing({
    required this.summary,
    required this.partnerName,
    required this.onTap,
  });

  final StoryRingSummary summary;
  final String partnerName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailUrl = ref
        .watch(storyMediaSignedUrlProvider(summary.newestThumbnailKey))
        .valueOrNull;

    return StoryRing(
      key: const ValueKey('story-ring-partner'),
      isMine: false,
      hasStories: true,
      segmentCount: summary.activeCount,
      unviewedCount: summary.unviewedCount,
      thumbnailUrl: thumbnailUrl,
      onTap: onTap,
      semanticLabel:
          "$partnerName's story, "
          '${summary.unviewedCount > 0 ? 'new' : 'seen'}',
    );
  }
}
