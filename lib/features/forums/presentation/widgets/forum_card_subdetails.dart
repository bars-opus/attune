import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:flutter/material.dart';

class ForumCardSubDetails extends StatelessWidget {
  /// Distinct people who picked each side (user_forum_sides), not a count of
  /// posts — see TopicModel.forPeople/againstPeople.
  final int forPeople;
  final int againstPeople;
  final String contributors;

  /// The viewer's own side on this topic — 'FOR', 'AGAINST', 'Browsing', or
  /// null (hasn't picked one / not authenticated). Tints the matching
  /// For/Against icon+count green or red so the card reflects which side is
  /// actually yours, rather than both always reading in the same neutral
  /// color regardless of your stake in the debate.
  final String? userSide;

  const ForumCardSubDetails({
    super.key,
    required this.forPeople,
    required this.againstPeople,
    required this.contributors,
    this.userSide,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFor = userSide == 'FOR';
    final isAgainst = userSide == 'AGAINST';

    // "For"'s icon sits on the right of its text, "Against"'s on the left —
    // a mirrored layout so the two read as opposing sides of one line
    // rather than two identical left-icon rows.
    Widget rowTexts(
      int count,
      String subtitle,
      IconData icon, {
      required bool iconOnRight,
      Color? tint,
    }) {
      final color = tint ?? colorScheme.onBackground.withOpacity(.4);
      final iconWidget = Icon(icon, size: 20.h, color: color);
      final textWidget = Column(
        crossAxisAlignment:
            iconOnRight ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedRollingCounter(
            count: count,
            compact: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: tint ?? colorScheme.onBackground,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            subtitle,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: colorScheme.onBackground),
          ),
        ],
      );

      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children:
            iconOnRight
                ? [textWidget, Gap(Spacing.sm.w), iconWidget]
                : [iconWidget, Gap(Spacing.sm.w), textWidget],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        rowTexts(
          forPeople,
          'For',
          isFor ? Icons.thumb_up : Icons.thumb_up_outlined,
          iconOnRight: true,
          tint: isFor ? colorScheme.primary : null,
        ),
        Gap(Spacing.md),
        rowTexts(
          againstPeople,
          'Against',
          isAgainst ? Icons.thumb_down : Icons.thumb_down_outlined,
          iconOnRight: false,
          tint: isAgainst ? colorScheme.against : null,
        ),
      ],
    );
  }
}
