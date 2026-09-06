import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/domain/services/scoring_service.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/widgets/this_or_that_game_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class ThisOrThatSessionRouterScreen extends ConsumerWidget {
  const ThisOrThatSessionRouterScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Refreshes what this screen reads whenever the partner acts. Without
    // it, a player waiting on their turn saw nothing until they tapped
    // something — which in a turn-based game is most of the time.
    ref.listen(gameSessionLiveProvider(sessionId), (_, _) {
      ref.invalidate(sessionProvider(sessionId));
      ref.invalidate(sessionRoundsProvider(sessionId));
    });
    ref.watch(gameSessionLiveProvider(sessionId));

    final sessionAsync = ref.watch(sessionProvider(sessionId));
    final userId = ref.watch(currentUserIdProvider);

    if (userId == null) {
      return const _GameStatusScreen(
        title: 'Sign in to keep playing',
        message: 'Your game is waiting safely for you.',
        icon: Icons.lock_outline_rounded,
      );
    }

    return sessionAsync.when(
      loading: () => const _GameLoadingScreen(),
      error:
          (_, __) => _GameStatusScreen(
            title: 'Could not load the game',
            message: 'Check your connection and try once more.',
            icon: Icons.cloud_off_rounded,
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(sessionProvider(sessionId)),
          ),
      data: (session) {
        if (session == null) {
          return _GameStatusScreen(
            title: 'This game has ended',
            message: 'Start a fresh round whenever you are both ready.',
            icon: Icons.hourglass_disabled_rounded,
            actionLabel: 'Back to games',
            onAction: () => context.pushReplacementNamed('thisOrThatGamesHub'),
          );
        }

        final partnerNameAsync = ref.watch(partnerNameProvider);
        final membersAsync = ref.watch(
          relationshipMembersProvider(session.relationshipId),
        );

        return partnerNameAsync.when(
          loading: () => const _GameLoadingScreen(),
          error:
              (_, __) => _GameStatusScreen(
                title: 'Could not find your partner',
                message: 'The game will be ready when your connection returns.',
                icon: Icons.people_outline_rounded,
                actionLabel: 'Try again',
                onAction: () => ref.invalidate(partnerNameProvider),
              ),
          data: (partnerName) {
            return membersAsync.when(
              loading: () => const _GameLoadingScreen(),
              error:
                  (_, __) => _GameStatusScreen(
                    title: 'The game is out of reach',
                    message: 'We could not reconnect both players just yet.',
                    icon: Icons.link_off_rounded,
                    actionLabel: 'Try again',
                    onAction:
                        () => ref.invalidate(
                          relationshipMembersProvider(session.relationshipId),
                        ),
                  ),
              data: (members) {
                final isPartnerA = userId == members.userA;
                final isInitiator = userId == session.initiatorId;
                final resolvedPartnerName = partnerName ?? 'Partner';

                if (session.status == 'invited') {
                  if (isInitiator) {
                    return _InviteSentScreen(
                      partnerName: resolvedPartnerName,
                      onCancel: () async {
                        await ref.read(
                          abandonSessionProvider(session.id).future,
                        );
                        if (!context.mounted) return;
                        context.pushReplacementNamed('thisOrThatGamesHub');
                      },
                    );
                  }

                  return _InvitationDecisionScreen(
                    partnerName: resolvedPartnerName,
                    tone: session.tone,
                    onAccept: () async {
                      await ref.read(
                        acceptThisOrThatSessionProvider((
                          sessionId: session.id,
                          intimateConsent: session.tone == 'intimate',
                          fallbackTone: null,
                        )).future,
                      );
                      ref.invalidate(sessionProvider(session.id));
                    },
                    onDecline: () async {
                      if (session.tone == 'intimate') {
                        await ref.read(
                          acceptThisOrThatSessionProvider((
                            sessionId: session.id,
                            intimateConsent: false,
                            fallbackTone: 'spicy',
                          )).future,
                        );
                      } else {
                        await ref.read(
                          abandonSessionProvider(session.id).future,
                        );
                      }
                      ref.invalidate(sessionProvider(session.id));
                    },
                  );
                }

                if (session.status == 'abandoned') {
                  return _GameStatusScreen(
                    title: 'This round has ended',
                    message:
                        'No score to settle. Start another whenever the mood is right.',
                    icon: Icons.hourglass_disabled_rounded,
                    actionLabel: 'Back to games',
                    onAction:
                        () =>
                            context.pushReplacementNamed('thisOrThatGamesHub'),
                  );
                }

                final roundsAsync = ref.watch(
                  sessionRoundsProvider(session.id),
                );
                return roundsAsync.when(
                  loading: () => const _GameLoadingScreen(),
                  error:
                      (_, __) => _GameStatusScreen(
                        title: 'Rounds could not sync',
                        message: 'Your progress is safe. Try loading it again.',
                        icon: Icons.sync_problem_rounded,
                        actionLabel: 'Try again',
                        onAction:
                            () => ref.invalidate(
                              sessionRoundsProvider(session.id),
                            ),
                      ),
                  data:
                      (rounds) => _buildActiveFlow(
                        context: context,
                        ref: ref,
                        session: session,
                        rounds: rounds,
                        isPartnerA: isPartnerA,
                        partnerName: resolvedPartnerName,
                      ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildActiveFlow({
    required BuildContext context,
    required WidgetRef ref,
    required ThisOrThatSession session,
    required List<GameRound> rounds,
    required bool isPartnerA,
    required String partnerName,
  }) {
    if (rounds.isEmpty) {
      return const _GameLoadingScreen();
    }

    final scoringService = ref.read(scoringServiceProvider);
    final completedRounds = rounds.where((round) => round.bothAnswered).length;
    final matchCount =
        rounds
            .where(
              (round) =>
                  round.bothAnswered &&
                  round.answerA != null &&
                  round.answerA == round.answerB,
            )
            .length;

    final isCompleted =
        session.status == 'completed' || completedRounds >= session.totalRounds;

    if (isCompleted) {
      final interestingPick = _buildInterestingPick(scoringService, rounds);
      return EndScreen(
        matchCount: matchCount,
        totalRounds: session.totalRounds,
        mostInterestingPick: interestingPick,
        onPlayAgain: () {
          context.pushReplacementNamed('thisOrThatToneSelector');
        },
        onTryAnotherGame: () {
          context.pushReplacementNamed('thisOrThatGamesHub');
        },
      );
    }

    final round = _resolveCurrentRound(session: session, rounds: rounds);
    final userAnswered =
        isPartnerA ? round.hasUserAAnswered : round.hasUserBAnswered;

    if (round.bothAnswered) {
      return RevealScreen(
        questionText: round.displayQuestionText,
        userChoice: isPartnerA ? (round.answerA ?? '') : (round.answerB ?? ''),
        userChoiceText:
            isPartnerA ? (round.answerAText ?? '') : (round.answerBText ?? ''),
        userChoiceEmoji:
            isPartnerA
                ? (round.answerA == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? ''))
                : (round.answerB == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? '')),
        partnerChoice:
            isPartnerA ? (round.answerB ?? '') : (round.answerA ?? ''),
        partnerChoiceText:
            isPartnerA ? (round.answerBText ?? '') : (round.answerAText ?? ''),
        partnerChoiceEmoji:
            isPartnerA
                ? (round.answerB == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? ''))
                : (round.answerA == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? '')),
        partnerName: partnerName,
        roundNumber: round.roundNumber,
        totalRounds: session.totalRounds,
        isMatch: round.answerA == round.answerB,
        onNext: () async {
          final nextRound = round.roundNumber + 1;
          await ref.read(
            advanceSessionProvider((
              sessionId: session.id,
              nextRound:
                  nextRound > session.totalRounds
                      ? session.totalRounds
                      : nextRound,
              matchCount: matchCount,
              totalRoundsCompleted: completedRounds,
              isCompleted: round.roundNumber >= session.totalRounds,
            )).future,
          );
        },
        hasPrevious: false,
      );
    }

    if (userAnswered) {
      return WaitingScreen(
        sessionId: session.id,
        roundId: round.id,
        questionText: round.displayQuestionText,
        userChoice: isPartnerA ? (round.answerA ?? '') : (round.answerB ?? ''),
        userChoiceText:
            isPartnerA ? (round.answerAText ?? '') : (round.answerBText ?? ''),
        userChoiceEmoji:
            isPartnerA
                ? (round.answerA == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? ''))
                : (round.answerB == 'a'
                    ? (round.emojiA ?? '')
                    : (round.emojiB ?? '')),
        optionA: round.optionA ?? 'Option A',
        optionB: round.optionB ?? 'Option B',
        emojiA: round.emojiA,
        emojiB: round.emojiB,
        roundNumber: round.roundNumber,
        totalRounds: session.totalRounds,
        isPartnerA: isPartnerA,
        partnerName: partnerName,
        onRoundUpdated: () {
          ref.invalidate(sessionRoundsProvider(session.id));
        },
      );
    }

    return QuestionScreen(
      roundId: round.id,
      questionText: round.displayQuestionText,
      optionA: round.optionA ?? 'Option A',
      optionB: round.optionB ?? 'Option B',
      emojiA: round.emojiA,
      emojiB: round.emojiB,
      roundNumber: round.roundNumber,
      totalRounds: session.totalRounds,
      tone: session.tone,
      isPartnerA: isPartnerA,
      partnerName: partnerName,
      isCustom: round.isCustom,
      onAnswerSubmitted: () {
        ref.invalidate(sessionRoundsProvider(session.id));
      },
    );
  }

  GameRound _resolveCurrentRound({
    required ThisOrThatSession session,
    required List<GameRound> rounds,
  }) {
    final bySessionPointer =
        rounds
            .where((round) => round.roundNumber == session.currentRound)
            .toList();
    if (bySessionPointer.isNotEmpty) {
      return bySessionPointer.first;
    }

    return rounds.firstWhere(
      (round) => !round.bothAnswered,
      orElse: () => rounds.last,
    );
  }

  Map<String, dynamic> _buildInterestingPick(
    ScoringService scoringService,
    List<GameRound> rounds,
  ) {
    final mappedRounds =
        rounds
            .map(
              (round) => {
                'question_text': round.displayQuestionText,
                'answer_a': round.answerA,
                'answer_b': round.answerB,
                'answer_a_text': round.answerAText ?? '',
                'answer_b_text': round.answerBText ?? '',
                'answer_a_emoji':
                    round.answerA == 'a'
                        ? (round.emojiA ?? '')
                        : (round.emojiB ?? ''),
                'answer_b_emoji':
                    round.answerB == 'a'
                        ? (round.emojiA ?? '')
                        : (round.emojiB ?? ''),
                'is_interesting': round.isInteresting,
              },
            )
            .toList();

    return mappedRounds.isEmpty
        ? <String, dynamic>{}
        : scoringService.getMostInterestingPick(mappedRounds);
  }
}

class _InviteSentScreen extends StatelessWidget {
  const _InviteSentScreen({required this.partnerName, required this.onCancel});

  final String partnerName;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      title: 'Invitation sent',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ThisOrThatWaitingMark(size: 132),
          const SizedBox(height: 20),
          Text(
            '$partnerName has the next move',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'We will bring you back here as soon as they join. You can leave safely in the meantime.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.45,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel invitation'),
          ),
        ],
      ),
    );
  }
}

class _InvitationDecisionScreen extends StatefulWidget {
  const _InvitationDecisionScreen({
    required this.partnerName,
    required this.tone,
    required this.onAccept,
    required this.onDecline,
  });

  final String partnerName;
  final String tone;
  final Future<void> Function() onAccept;
  final Future<void> Function() onDecline;

  @override
  State<_InvitationDecisionScreen> createState() =>
      _InvitationDecisionScreenState();
}

class _InvitationDecisionScreenState extends State<_InvitationDecisionScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    final isIntimate = widget.tone == 'intimate';
    final toneLabel =
        '${widget.tone[0].toUpperCase()}${widget.tone.substring(1)}';
    return ThisOrThatGameScaffold(
      title: 'Game invite',
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ThisOrThatPrimaryAction(
            label: isIntimate ? 'I am in' : 'Let\'s play',
            onPressed: _busy ? null : () => _run(widget.onAccept),
            loading: _busy,
            icon: Icons.play_arrow_rounded,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => _run(widget.onDecline),
            child: Text(isIntimate ? 'Play at Spicy instead' : 'Maybe later'),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const GameIcon(gameType: 'this_or_that', size: 116),
          const SizedBox(height: 20),
          Text(
            '${widget.partnerName} picked a game for you',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w900,
              height: 1.1,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: palette.thisColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: palette.thisColor.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              '$toneLabel mood  •  about 5 minutes',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: palette.thisColor,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            isIntimate
                ? 'This mood includes adult questions. Join only if it feels comfortable; choosing Spicy will simply soften the game.'
                : 'Your answers stay hidden until both of you pick. Then you get the reveal together.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.45,
              letterSpacing: 0,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _GameLoadingScreen extends StatelessWidget {
  const _GameLoadingScreen();

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const ThisOrThatWaitingMark(size: 108),
          const SizedBox(height: 16),
          Text(
            'Setting the cards',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _GameStatusScreen extends StatelessWidget {
  const _GameStatusScreen({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final palette = ThisOrThatPalette.of(context);
    return ThisOrThatGameScaffold(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: palette.thatColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 34, color: palette.thatColor),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: palette.ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.mutedInk,
              height: 1.4,
              letterSpacing: 0,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: 220,
              child: ThisOrThatPrimaryAction(
                label: actionLabel!,
                onPressed: onAction,
                icon: Icons.refresh_rounded,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
