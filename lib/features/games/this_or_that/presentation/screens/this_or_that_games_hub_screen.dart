import 'package:attune/features/community/presentation/widgets/community_questions_entry.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ThisOrThatGamesHubScreen extends ConsumerWidget {
  const ThisOrThatGamesHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ThisOrThatPalette.of(context);
    final sessionAsync = ref.watch(activeThisOrThatSessionProvider);

    return ThisOrThatGameScaffold(
      scrollable: true,
      child: Column(
        children: [
          const SizedBox(height: 8),
          const GameIcon(gameType: 'this_or_that', size: 108),
          const SizedBox(height: 16),
          Text(
            'Two choices.\nOne little reveal.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              height: 1.06,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Pick privately, discover together, and find the answers worth talking about.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.45,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: const [
              Expanded(
                child: _GameFact(
                  value: '10',
                  label: 'quick rounds',
                  icon: Icons.style_rounded,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _GameFact(
                  value: '2',
                  label: 'private picks',
                  icon: Icons.lock_outline_rounded,
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                child: _GameFact(
                  value: '1',
                  label: 'shared reveal',
                  icon: Icons.favorite_outline_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          sessionAsync.when(
            loading:
                () => Container(
                  height: 92,
                  alignment: Alignment.center,
                  child: const CircularProgressIndicator(),
                ),
            error: (_, __) => const SizedBox.shrink(),
            data: (session) {
              if (session == null) {
                return ThisOrThatPrimaryAction(
                  label: 'Choose a mood',
                  onPressed: () => context.pushNamed('thisOrThatToneSelector'),
                  icon: Icons.play_arrow_rounded,
                );
              }

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: palette.panel.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: palette.thisColor),
                  boxShadow: [
                    BoxShadow(
                      color: palette.thisColor.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: palette.thisColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: palette.thisColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.status == 'invited'
                                ? 'Invitation waiting'
                                : 'Your game is in play',
                            style: Theme.of(
                              context,
                            ).textTheme.titleSmall?.copyWith(
                              color: palette.ink,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                          Text(
                            session.status == 'invited'
                                ? 'Open it to see who is waiting.'
                                : 'Round ${session.currentRound.clamp(1, session.totalRounds)} of ${session.totalRounds}',
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
                    IconButton.filled(
                      onPressed:
                          () => context.pushNamed(
                            'thisOrThatSessionRouter',
                            extra: session.id,
                          ),
                      tooltip: 'Resume game',
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HubAction(
                  icon: Icons.edit_note_rounded,
                  label: 'Your questions',
                  onTap: () => context.pushNamed('thisOrThatCustomList'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HubAction(
                  icon: Icons.history_rounded,
                  label: 'Past games',
                  onTap: () => context.pushNamed('thisOrThatSessionHistory'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'From the community',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 10),
          const CommunityQuestionsEntry(typeFilter: 'This or That'),
        ],
      ),
    );
  }
}

class _GameFact extends StatelessWidget {
  const _GameFact({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      height: 104,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: palette.thatColor),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: palette.mutedInk,
              height: 1.1,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _HubAction extends StatelessWidget {
  const _HubAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.ink,
          side: BorderSide(color: palette.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
