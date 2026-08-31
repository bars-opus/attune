import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/domain/services/scoring_service.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/reveal_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/waiting_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      return const Scaffold(
        body: Center(child: Text('Please sign in to continue.')),
      );
    }

    return sessionAsync.when(
      loading:
          () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(body: Center(child: Text('Error: $error'))),
      data: (session) {
        if (session == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found.')),
          );
        }

        final partnerNameAsync = ref.watch(partnerNameProvider);
        final membersAsync = ref.watch(
          relationshipMembersProvider(session.relationshipId),
        );

        return partnerNameAsync.when(
          loading:
              () => const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              ),
          error:
              (error, _) =>
                  Scaffold(body: Center(child: Text('Error: $error'))),
          data: (partnerName) {
            return membersAsync.when(
              loading:
                  () => const Scaffold(
                    body: Center(child: CircularProgressIndicator()),
                  ),
              error:
                  (error, _) =>
                      Scaffold(body: Center(child: Text('Error: $error'))),
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
                  return Scaffold(
                    appBar: AppBar(title: const Text('This or That')),
                    body: Center(
                      child: Padding(
                        padding: EdgeInsets.all(Spacing.lg.w),
                        child: SemanticContainerWidget(
                          title: 'Session expired',
                          content:
                              'This session is no longer active. Start a new game when you are both ready.',
                          icon: Icons.hourglass_disabled_outlined,
                          backgroundColor:
                              Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                          borderColor: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.3),
                          iconColor: Theme.of(context).colorScheme.onSurface,
                          textTheme: Theme.of(context).textTheme,
                          child: Padding(
                            padding: EdgeInsets.only(top: Spacing.md.h),
                            child: AppButton(
                              label: 'Back to games',
                              onPressed: () {
                                context.pushReplacementNamed(
                                  'thisOrThatGamesHub',
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final roundsAsync = ref.watch(
                  sessionRoundsProvider(session.id),
                );
                return roundsAsync.when(
                  loading:
                      () => const Scaffold(
                        body: Center(child: CircularProgressIndicator()),
                      ),
                  error:
                      (error, _) =>
                          Scaffold(body: Center(child: Text('Error: $error'))),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
        roundNumber: round.roundNumber,
        totalRounds: session.totalRounds,
        isPartnerA: isPartnerA,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Invitation sent')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Invitation sent to $partnerName',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.lg.h),
            const CircularProgressIndicator(),
            Gap(Spacing.lg.h),
            AppButton(
              label: 'Cancel invitation',
              onPressed: onCancel,
              customColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              textColor: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}

class _InvitationDecisionScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final isIntimate = tone == 'intimate';
    return Scaffold(
      appBar: AppBar(title: const Text('Game invite')),
      body: Padding(
        padding: EdgeInsets.all(Spacing.lg.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$partnerName invited you to play',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.md.h),
            Text(
              isIntimate
                  ? 'This tone contains adult content. Do you want to play at this level?'
                  : 'This or That • ${tone[0].toUpperCase()}${tone.substring(1)} tone • ~5 minutes',
              textAlign: TextAlign.center,
            ),
            Gap(Spacing.xl.h),
            AppButton(
              label: isIntimate ? 'Yes, I’m in' : 'Let’s play!',
              onPressed: () async => onAccept(),
              width: double.infinity,
            ),
            Gap(Spacing.md.h),
            AppButton(
              label:
                  isIntimate
                      ? 'Decline — play at Spicy instead'
                      : 'Maybe later',
              onPressed: () async => onDecline(),
              width: double.infinity,
              customColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              textColor: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }
}
