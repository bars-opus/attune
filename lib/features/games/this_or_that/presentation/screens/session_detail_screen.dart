import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SessionDetailScreen extends ConsumerWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(sessionProvider(sessionId));

    return sessionAsync.when(
      loading: () => const _RecapLoadingScreen(),
      error:
          (_, __) => _RecapStatusScreen(
            title: 'Recap unavailable',
            message: 'We could not load this game just yet.',
            onRetry: () => ref.invalidate(sessionProvider(sessionId)),
          ),
      data: (session) {
        if (session == null) {
          return const _RecapStatusScreen(
            title: 'Game not found',
            message: 'This recap may have been removed from your view.',
          );
        }

        final roundsAsync = ref.watch(sessionRoundsProvider(sessionId));
        final membersAsync = ref.watch(
          relationshipMembersProvider(session.relationshipId),
        );
        final userId = ref.watch(currentUserIdProvider);

        return membersAsync.when(
          loading: () => const _RecapLoadingScreen(),
          error:
              (_, __) => _RecapStatusScreen(
                title: 'Recap unavailable',
                message: 'We could not identify both players.',
                onRetry:
                    () => ref.invalidate(
                      relationshipMembersProvider(session.relationshipId),
                    ),
              ),
          data: (members) {
            final isPartnerA = userId == members.userA;
            return roundsAsync.when(
              loading: () => const _RecapLoadingScreen(),
              error:
                  (_, __) => _RecapStatusScreen(
                    title: 'Rounds unavailable',
                    message: 'Your game is safe. Try loading the recap again.',
                    onRetry:
                        () => ref.invalidate(sessionRoundsProvider(sessionId)),
                  ),
              data:
                  (rounds) => _SessionRecap(
                    session: session,
                    rounds: rounds,
                    isPartnerA: isPartnerA,
                  ),
            );
          },
        );
      },
    );
  }
}

class _SessionRecap extends StatelessWidget {
  const _SessionRecap({
    required this.session,
    required this.rounds,
    required this.isPartnerA,
  });

  final ThisOrThatSession session;
  final List<GameRound> rounds;
  final bool isPartnerA;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final completed = rounds.where((round) => round.bothAnswered).toList();
    final showPercentage = session.matchPercentage >= 60;

    return ThisOrThatGameScaffold(
      title: 'Game recap',
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.panel.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: palette.line),
            ),
            child: Column(
              children: [
                ThisOrThatStageLabel(
                  text: _toneLabel(session.tone),
                  icon: Icons.auto_awesome_rounded,
                  color: palette.thisColor,
                ),
                const SizedBox(height: 12),
                Text(
                  showPercentage
                      ? '${session.matchCount} shared picks'
                      : 'A game worth talking about',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: palette.ink,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  showPercentage
                      ? '${session.matchPercentage.round()}% matched across ${completed.length} rounds'
                      : '${completed.length} rounds, with plenty to discover in the differences',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: palette.mutedInk,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child:
                completed.isEmpty
                    ? Center(
                      child: Text(
                        'No completed rounds to show.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.mutedInk,
                        ),
                      ),
                    )
                    : ListView.separated(
                      physics: const BouncingScrollPhysics(),
                      itemCount: completed.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder:
                          (context, index) => _RoundRecapCard(
                            round: completed[index],
                            isPartnerA: isPartnerA,
                          ),
                    ),
          ),
        ],
      ),
    );
  }

  static String _toneLabel(String tone) {
    if (tone.isEmpty) return 'Game';
    return '${tone[0].toUpperCase()}${tone.substring(1)} game';
  }
}

class _RoundRecapCard extends StatelessWidget {
  const _RoundRecapCard({required this.round, required this.isPartnerA});

  final GameRound round;
  final bool isPartnerA;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final yourAnswer = isPartnerA ? round.answerA : round.answerB;
    final partnerAnswer = isPartnerA ? round.answerB : round.answerA;
    final yourText = isPartnerA ? round.answerAText : round.answerBText;
    final partnerText = isPartnerA ? round.answerBText : round.answerAText;
    final matched = yourAnswer != null && yourAnswer == partnerAnswer;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'ROUND ${round.roundNumber}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: palette.mutedInk,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              Icon(
                matched ? Icons.favorite_rounded : Icons.compare_arrows_rounded,
                size: 18,
                color: matched ? palette.thisColor : palette.thatColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            round.displayQuestionText,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _AnswerTile(
                  label: 'YOU',
                  text: yourText ?? 'No answer',
                  emoji: _emojiFor(round, yourAnswer),
                  color: palette.thisColor,
                  surface: palette.thisSurface,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _AnswerTile(
                  label: 'PARTNER',
                  text: partnerText ?? 'No answer',
                  emoji: _emojiFor(round, partnerAnswer),
                  color: palette.thatColor,
                  surface: palette.thatSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _emojiFor(GameRound round, String? answer) {
    if (answer == 'a') return round.emojiA ?? '';
    if (answer == 'b') return round.emojiB ?? '';
    return '';
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({
    required this.label,
    required this.text,
    required this.emoji,
    required this.color,
    required this.surface,
  });

  final String label;
  final String text;
  final String emoji;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 92),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$emoji $text'.trim(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w700,
              height: 1.2,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecapLoadingScreen extends StatelessWidget {
  const _RecapLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const ThisOrThatGameScaffold(
      title: 'Game recap',
      child: Center(child: ThisOrThatWaitingMark(size: 104)),
    );
  }
}

class _RecapStatusScreen extends StatelessWidget {
  const _RecapStatusScreen({
    required this.title,
    required this.message,
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      title: 'Game recap',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style_rounded, size: 48, color: palette.thatColor),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: palette.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: palette.mutedInk),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
