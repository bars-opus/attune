import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';

class SessionHistoryCard extends StatelessWidget {
  const SessionHistoryCard({
    super.key,
    required this.session,
    required this.onHide,
    required this.onTap,
  });

  final ThisOrThatSession session;
  final VoidCallback onHide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final showPercentage = session.matchPercentage >= 60;

    return Material(
      color: palette.panel.withValues(alpha: 0.96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 10, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: palette.thisSurface,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(
                      Icons.style_rounded,
                      size: 21,
                      color: palette.thisColor,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _toneLabel(session.tone),
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(
                            color: palette.ink,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(session.completedAt ?? session.createdAt),
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(
                            color: palette.mutedInk,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Game options',
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: palette.mutedInk,
                    ),
                    onSelected: (value) {
                      if (value == 'hide') onHide();
                    },
                    itemBuilder:
                        (_) => const [
                          PopupMenuItem(
                            value: 'hide',
                            child: Row(
                              children: [
                                Icon(Icons.visibility_off_outlined),
                                SizedBox(width: 10),
                                Text('Hide from my view'),
                              ],
                            ),
                          ),
                        ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      showPercentage
                          ? '${session.matchCount} shared picks'
                          : 'Different perspectives',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: palette.ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  Text(
                    showPercentage
                        ? '${session.matchPercentage.round()}%'
                        : '${session.totalRoundsCompleted} rounds',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color:
                          showPercentage
                              ? palette.thisColor
                              : palette.thatColor,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: palette.mutedInk,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _toneLabel(String tone) {
    if (tone.isEmpty) return 'This or That';
    return '${tone[0].toUpperCase()}${tone.substring(1)} game';
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
