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
/// Deliberately not a bubble and not tappable. It is a record of a move
/// that happened, not a thing to act on; the live card is the only place
/// a game can be opened.
class GameTrailLine extends StatelessWidget {
  const GameTrailLine({
    super.key,
    required this.label,
    required this.isMine,
    this.gameType,
  });

  final String label;
  final bool isMine;
  final String? gameType;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final muted = colorScheme.onSurface.withValues(alpha: 0.45);

    final icon =
        gameType == null
            ? Icons.sports_esports_outlined
            : (chatGameIconForType(gameType!) ?? Icons.sports_esports_outlined);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment:
          isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Icon(icon, size: 14.h, color: muted),
        SizedBox(width: 5.w),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: muted),
        ),
      ],
    );
  }
}
