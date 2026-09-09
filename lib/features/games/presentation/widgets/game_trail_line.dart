import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// The mark a game card leaves behind when it moves to the other side.
///
/// One line -- icon and name -- so the conversation keeps a record of the
/// back-and-forth. Without it a card that migrates between sides would
/// erase its own history: the exchange would show only wherever the card
/// currently sits, as though nobody had replied.
///
/// Sits in the ordinary sender/receiver bubble, and is not tappable. It
/// is a record of a move that happened, not a thing to act on; the live
/// card is the only place a game can be opened.
///
/// It used to render bare, with no bubble, on the reasoning that a record
/// is not a message. But a trail's whole job is to show WHO moved and
/// where in the conversation it happened, and without a fill it showed
/// neither — a left-aligned grey line reads the same as a right-aligned
/// one at a glance.
class GameTrailLine extends StatelessWidget {
  const GameTrailLine({
    super.key,
    required this.label,
    required this.isMine,
    this.foregroundColor,
    this.gameType,
  });

  final String label;
  final bool isMine;

  /// The bubble's on-colour, so icon and text read against the fill
  /// rather than against the wallpaper they used to sit on.
  final Color? foregroundColor;

  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Muted RELATIVE TO THE BUBBLE it now sits in. The old value was
    // muted against the wallpaper, which is a different surface.
    final base = foregroundColor ?? colorScheme.onSurface;
    final muted = base.withValues(alpha: 0.75);

    final icon =
        gameType == null
            ? Icons.sports_esports_outlined
            : (chatGameIconForType(gameType!) ?? Icons.sports_esports_outlined);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 15.h, color: muted),
        SizedBox(width: 6.w),
        Flexible(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
