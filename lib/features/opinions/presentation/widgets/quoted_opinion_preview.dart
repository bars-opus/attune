// lib/features/opinions/presentation/widgets/quoted_opinion_preview.dart

import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/core/utils/relationship_status_display.dart';
import 'package:attune/features/opinions/presentation/providers/opinion_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// The original opinion embedded inside a quote's card
/// (ATTUNE_MASTER_SPEC.md §8.11 "Quotes").
///
/// Deliberately NOT an [OpinionCard]: this renders the original's status label
/// and text only — no like/dislike/repost/quote/save/follow actions, no
/// overflow menu. Two reasons, in order of importance:
///
///  1. Recursion. A nested OpinionCard would itself render a
///     QuotedOpinionPreview whenever its own quotedOpinionId were non-null,
///     and a quote-of-a-quote would nest without bound. The DB re-targets to
///     the original at insert time so a real chain cannot exist, but that is a
///     server invariant, and the client should not be one stale row away from
///     an infinite widget tree. This widget structurally cannot recurse: it
///     never reads the embedded row's own quotedOpinionId.
///  2. Interaction. Two full action rows on one card gives every tap an
///     ambiguous target — the quote's like or the original's.
///
/// The original is attributed to its OWN author handle, never linked to the
/// quoter's beyond "this opinion quotes that one" (FORUM.md §7).
class QuotedOpinionPreview extends ConsumerWidget {
  /// The id of the opinion being quoted — i.e. the quote card's
  /// `opinion.quotedOpinionId`, not the quote's own id.
  final String quotedOpinionId;

  /// Tapping the preview opens the original's own thread, when the host
  /// screen supplies a handler. Null makes the preview inert.
  final void Function(String opinionId)? onTap;

  const QuotedOpinionPreview({
    super.key,
    required this.quotedOpinionId,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Family-cached, so several quotes of the same original on one page share
    // one fetch rather than one per card.
    final original = ref.watch(quotedOriginalProvider(quotedOpinionId));

    return original.when(
      loading: () => const _QuotedPreviewShell(child: _QuotedPreviewSkeleton()),
      // A failed lookup is shown as unavailable rather than as an error: from
      // the reader's point of view the embedded content is missing either way,
      // and an error affordance inside someone else's card invites a retry
      // that isn't theirs to make.
      error:
          (_, __) =>
              const _QuotedPreviewShell(child: _QuotedPreviewUnavailable()),
      data: (opinion) {
        if (opinion == null) {
          // Zero rows: the original was removed by moderation or deleted by
          // its author. The quote itself is untouched — only this slot
          // changes (§8.11 "Removed original").
          return const _QuotedPreviewShell(child: _QuotedPreviewUnavailable());
        }

        final colorScheme = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final statusDisplay = statusDisplayFor(opinion.relationshipStatus);

        return _QuotedPreviewShell(
          onTap: onTap == null ? null : () => onTap!(opinion.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FontAwesomeIcons.quoteLeft,
                    size: 10.h,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                  Gap(Spacing.xs.w),
                  Flexible(
                    child: Text(
                      statusDisplay.isEmpty ? 'Someone' : statusDisplay,
                      style: textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              Gap(Spacing.xs.h),
              Text(
                opinion.content,
                // Truncated: this is a reference to the original, not a second
                // copy of it — the full text is one tap away in its own thread.
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}

/// The bordered, tinted container every preview state shares, so the card's
/// layout does not shift as the lazy lookup resolves.
class _QuotedPreviewShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _QuotedPreviewShell({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(Spacing.sm.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: colorScheme.onSurface.withValues(alpha: 0.15),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Placeholder for a removed or deleted original. Copy is fixed by the spec
/// (§8.11 "Removed original").
class _QuotedPreviewUnavailable extends StatelessWidget {
  const _QuotedPreviewUnavailable();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(
          Icons.block,
          size: 14.h,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
        Gap(Spacing.xs.w),
        Flexible(
          child: Text(
            'This opinion is no longer available',
            style: textTheme.bodySmall?.copyWith(
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two muted bars sized like the label + text they resolve into. Deliberately
/// tiny rather than reusing ListviewLoadingShimmer, which paints a whole list
/// of full-height rows — far too heavy for one embedded box.
class _QuotedPreviewSkeleton extends StatelessWidget {
  const _QuotedPreviewSkeleton();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final barColor = colorScheme.onSurface.withValues(alpha: 0.08);

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: barColor,
          borderRadius: BorderRadius.circular(4.r),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(0.25, 10.h), Gap(Spacing.xs.h), bar(0.9, 10.h)],
    );
  }
}
