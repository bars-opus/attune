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
    //
    // Two more rules, both from review findings F2/F5:
    // - `failedPermanent` records are excluded from the match entirely.
    //   `flush()` (story_outbox_controller.dart) skips them but never
    //   removes them from the store, so a dead record can otherwise sit
    //   in the list forever; the old first-match code let it permanently
    //   outrank a real `hasStories` ring (F2). This does NOT change the
    //   outbox controller's retention semantics — the record still lives
    //   in the store, it is simply never treated as "the" pending item
    //   for ring purposes. A distinct failure affordance is out of scope
    //   for this task; excluding it here at minimum stops it from hiding
    //   real, already-posted stories.
    // - Among the remaining candidates, the NEWEST by `createdAt` wins,
    //   not the first one in the store's (oldest-first) iteration order
    //   (F5) — the ring shows the most recent thing the user did.
    StoryOutboxRecord? myPending;
    for (final record in outbox) {
      if (record.relationshipId != relationshipId) continue;
      if (record.state == StoryOutboxState.failedPermanent) continue;
      if (myPending == null || record.createdAt.isAfter(myPending.createdAt)) {
        myPending = record;
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
    // segment on my own ring. Mirroring segmentCount is inherently in
    // range (it IS segmentCount), so no separate clamp is needed here —
    // unlike the partner ring below, this value is never read from the
    // RPC's unviewed_count field at all.
    final myUnviewedCount = mySegmentCount;

    final myRing = myPending == null && mySegmentCount > 0
        ? _MineRing(
            key: const ValueKey('story-ring-mine'),
            summary: mySummary!,
            onTap: onOpenMine,
            onTapPlus: onCapture,
          )
        : StoryRing(
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
      // Clamped at this boundary (finding F4): activeCount and
      // unviewedCount are independently-computed server aggregates
      // (get_story_ring_summary) and can diverge (a story expiring or
      // being deleted between the two counts being taken, or view-ledger
      // lag). StoryRing's constructor assert is a correct invariant for
      // the widget's OWN contract, but it is the wrong place to validate
      // unclamped network data — that hard-crashes the widget in debug on
      // a server-side timing issue the client did not cause. Clamping
      // here, not removing the assert, keeps the assert meaningful for
      // actual programmer error while never feeding it a value it can't
      // already guarantee is in range.
      unviewedCount: summary.unviewedCount.clamp(0, summary.activeCount),
      thumbnailUrl: thumbnailUrl,
      onTap: onTap,
      semanticLabel:
          "$partnerName's story, "
          '${summary.unviewedCount > 0 ? 'new' : 'seen'}',
    );
  }
}

/// Separated so [storyMediaSignedUrlProvider] is only watched when my
/// ring actually has a server-known thumbnail to show — mirrors
/// [_PartnerRing]'s scoping exactly (finding F1: this widget did not
/// previously exist, and MY ring never watched this provider at all, so
/// it always painted a blank fill once a pending capture cleared).
///
/// Only used by [StoryRingsRow] when `myPending == null &&
/// mySegmentCount > 0` — a pending capture shows its own local file
/// ([StoryRing.localThumbnailPath]) instead, and a zero/absent summary
/// (spec: the RPC omits zero-story authors) has nothing to sign a URL
/// for and no ring to draw a thumbnail on in the first place. Both of
/// those cases go through the plain [StoryRing] constructor directly, so
/// this widget's presence in the tree already implies "there is a real,
/// non-empty summary row and no pending capture," matching
/// [_PartnerRing]'s precondition.
class _MineRing extends ConsumerWidget {
  const _MineRing({
    super.key,
    required this.summary,
    required this.onTap,
    required this.onTapPlus,
  });

  final StoryRingSummary summary;
  final VoidCallback? onTap;
  final VoidCallback? onTapPlus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thumbnailUrl = ref
        .watch(storyMediaSignedUrlProvider(summary.newestThumbnailKey))
        .valueOrNull;

    final segmentCount = summary.activeCount;

    return StoryRing(
      isMine: true,
      hasStories: true,
      segmentCount: segmentCount,
      // See the comment at the call site in StoryRingsRow.build: my own
      // unviewed_count has no meaning on my own row, so every one of my
      // active segments renders bright.
      unviewedCount: segmentCount,
      thumbnailUrl: thumbnailUrl,
      onTap: onTap,
      onTapPlus: onTapPlus,
      semanticLabel:
          'Your story, $segmentCount ${segmentCount == 1 ? 'item' : 'items'}',
    );
  }
}
