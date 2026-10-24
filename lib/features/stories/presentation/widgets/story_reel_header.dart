/// The line under the reel's progress bars: whose story this is and when
/// it was posted (Wave 1 R6; review 06 #8), with the reel's own actions on
/// the right so they no longer sit on top of the bars (02 #21).
library;

import 'package:attune/app/theme/design_tokens.dart';
import 'package:attune/core/utils/date_formatter.dart';
import 'package:flutter/material.dart';

/// "Just now", "12m" or "3h" in the 24-hour reel. The time of day
/// ([MyDateFormat.toTime]) for a calendar or map story, or anything older
/// than a day. [withDate] (map and chat-quote reels, whose stories can be
/// from any day) puts the date first, joined with [MyDateFormat.join].
String storyPostedLabel(
  DateTime createdAt, {
  required DateTime now,
  required bool clockTime,
  bool withDate = false,
}) {
  final local = createdAt.toLocal();
  if (clockTime && withDate) {
    return MyDateFormat.join([
      MyDateFormat.toDateShort(local),
      MyDateFormat.toTime(local),
    ]);
  }
  if (clockTime) return MyDateFormat.toTime(local);
  final age = now.difference(createdAt);
  if (age < const Duration(minutes: 1)) return 'Just now';
  if (age < const Duration(hours: 1)) return '${age.inMinutes}m';
  if (age < const Duration(hours: 24)) return '${age.inHours}h';
  return MyDateFormat.toTime(local);
}

/// [storyPostedLabel] as a screen reader should say it (batch-4 review,
/// Minor 3): "3 hours ago", not "3 h".
String storyPostedSpokenLabel(
  DateTime createdAt, {
  required DateTime now,
  required bool clockTime,
  bool withDate = false,
}) {
  final local = createdAt.toLocal();
  if (clockTime && withDate) {
    return 'posted ${MyDateFormat.toDateShort(local)} at '
        '${MyDateFormat.toTime(local)}';
  }
  if (clockTime) return 'posted at ${MyDateFormat.toTime(local)}';
  final age = now.difference(createdAt);
  if (age < const Duration(minutes: 1)) return 'just now';
  if (age < const Duration(hours: 1)) {
    final m = age.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (age < const Duration(hours: 24)) {
    final h = age.inHours;
    return h == 1 ? '1 hour ago' : '$h hours ago';
  }
  return 'posted at ${MyDateFormat.toTime(local)}';
}

/// Below this much room for the byline, Seen drops to its icon (batch-4
/// review, Minor 1): whose story it is matters more than the word "Seen".
const double _kMinBylineWidth = 120;

class StoryReelHeader extends StatelessWidget {
  const StoryReelHeader({
    super.key,
    required this.authorLabel,
    required this.postedLabel,
    required this.postedSpokenLabel,
    this.seenBy,
    this.trailing = const [],
    this.showByline = true,
  });

  /// False until the reel has chosen the story it starts on (final review
  /// #4): never name a story the person has not been shown.
  final bool showByline;

  /// "You", or the partner's name.
  final String authorLabel;
  final String postedLabel;

  /// [postedLabel] in words, for the screen reader ([storyPostedSpokenLabel]).
  final String postedSpokenLabel;

  /// Non-null on the poster's own story once the partner has seen it (spec
  /// §5.2). The server masks the flag when seen receipts are off.
  final String? seenBy;

  /// The reel's actions (remove place, delete, close), 48 dp each.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final seenStyle = textTheme.labelMedium?.copyWith(color: Colors.white);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Each trailing action is a 48 dp button; the full chip is its
        // padding, icon, gap and the word as this text scale draws it.
        var compactSeen = false;
        if (seenBy != null) {
          final word = TextPainter(
            text: TextSpan(text: _SeenChip.word, style: seenStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fullChip =
              Spacing.sm * 2 + IconSizes.sm + Spacing.xs + word.width;
          word.dispose();
          final byline =
              constraints.maxWidth -
              Spacing.sm -
              kMinInteractiveDimension * trailing.length -
              fullChip;
          compactSeen = byline < _kMinBylineWidth;
        }
        return Row(
          children: [
            const SizedBox(width: Spacing.sm),
            Expanded(
              // Its own node, read as words ("Kofi, 3 hours ago"), not merged
              // into the reel's 'Story viewer' node (batch-4 review, Minor 3).
              child:
                  !showByline
                      ? const SizedBox.shrink()
                      : Semantics(
                        container: true,
                        label: '$authorLabel, $postedSpokenLabel',
                        excludeSemantics: true,
                        child: Text(
                          MyDateFormat.join([authorLabel, postedLabel]),
                          key: const ValueKey('story-reel-byline'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelLarge?.copyWith(
                            color: Colors.white,
                            shadows: const [
                              Shadow(blurRadius: 4, color: Colors.black54),
                            ],
                          ),
                        ),
                      ),
            ),
            if (seenBy != null)
              _SeenChip(
                seenBy: seenBy!,
                style: seenStyle,
                compact: compactSeen,
              ),
            ...trailing,
          ],
        );
      },
    );
  }
}

class _SeenChip extends StatelessWidget {
  const _SeenChip({
    required this.seenBy,
    required this.style,
    required this.compact,
  });

  static const word = 'Seen';

  final String seenBy;
  final TextStyle? style;

  /// Icon only, when the row is tight. The label still says who saw it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // container: true so the label is its own node rather than merging into
    // the reel's 'Story viewer' node above it.
    return Semantics(
      container: true,
      label: 'Seen by $seenBy',
      excludeSemantics: true,
      child: Padding(
        key: const ValueKey('story-reel-seen'),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.visibility_outlined,
              size: IconSizes.sm,
              color: Colors.white,
            ),
            if (!compact) ...[
              const SizedBox(width: Spacing.xs),
              Text(word, style: style),
            ],
          ],
        ),
      ),
    );
  }
}
