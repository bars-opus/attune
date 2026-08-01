import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/games/data/models/game_session.dart';
import 'package:attune/features/games/truth_or_dare/data/models/custom_truth_or_dare_question.dart';
import 'package:attune/features/games/truth_or_dare/presentation/providers/truth_or_dare_providers.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/card_flip_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/dare_reveal_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/partner_watching_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_end_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_or_dare_round_result_screen.dart';
import 'package:attune/features/games/truth_or_dare/presentation/screens/truth_reveal_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TruthOrDareSessionRouterScreen extends ConsumerWidget {
  const TruthOrDareSessionRouterScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionAsync = ref.watch(truthOrDareSessionProvider(sessionId));
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
                          abandonTruthOrDareSessionProvider(session.id).future,
                        );
                        if (!context.mounted) return;
                        context.pushReplacementNamed('truthOrDareGame');
                      },
                    );
                  }

                  return _InvitationDecisionScreen(
                    partnerName: resolvedPartnerName,
                    tone: session.tone,
                    onAccept: () async {
                      await ref.read(
                        acceptTruthOrDareSessionProvider((
                          sessionId: session.id,
                          intimateConsent: session.tone == 'intimate',
                          fallbackTone: null,
                        )).future,
                      );
                      ref.invalidate(truthOrDareSessionProvider(session.id));
                    },
                    onDecline: () async {
                      if (session.tone == 'intimate') {
                        await ref.read(
                          acceptTruthOrDareSessionProvider((
                            sessionId: session.id,
                            intimateConsent: false,
                            fallbackTone: 'spicy',
                          )).future,
                        );
                      } else {
                        await ref.read(
                          abandonTruthOrDareSessionProvider(session.id).future,
                        );
                      }
                      ref.invalidate(truthOrDareSessionProvider(session.id));
                    },
                  );
                }

                if (session.status == 'abandoned') {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Truth or Dare')),
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
                                context.pushReplacementNamed('truthOrDareGame');
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                final roundsAsync = ref.watch(
                  truthOrDareSessionRoundsProvider(session.id),
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
                        members: members,
                        currentUserId: userId,
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
    required GameSession session,
    required List<TruthOrDareRound> rounds,
    required ({String userA, String userB}) members,
    required String currentUserId,
    required bool isPartnerA,
    required String partnerName,
  }) {
    final truthsForA =
        rounds
            .where(
              (round) =>
                  round.questionType == 'truth' &&
                  round.activePartnerId == members.userA &&
                  (round.answerA?.isNotEmpty ?? false) &&
                  round.answerA != '__revealed__',
            )
            .length;
    final truthsForB =
        rounds
            .where(
              (round) =>
                  round.questionType == 'truth' &&
                  round.activePartnerId == members.userB &&
                  (round.answerB?.isNotEmpty ?? false) &&
                  round.answerB != '__revealed__',
            )
            .length;
    final daresForA =
        rounds
            .where(
              (round) =>
                  round.questionType == 'dare' &&
                  round.activePartnerId == members.userA &&
                  (round.answerA?.isNotEmpty ?? false) &&
                  round.answerA != '__revealed__',
            )
            .length;
    final daresForB =
        rounds
            .where(
              (round) =>
                  round.questionType == 'dare' &&
                  round.activePartnerId == members.userB &&
                  (round.answerB?.isNotEmpty ?? false) &&
                  round.answerB != '__revealed__',
            )
            .length;

    if (session.status == 'completed' ||
        session.currentRound > session.totalRounds) {
      return TruthOrDareEndScreen(
        userTruths: isPartnerA ? truthsForA : truthsForB,
        userDares: isPartnerA ? daresForA : daresForB,
        partnerTruths: isPartnerA ? truthsForB : truthsForA,
        partnerDares: isPartnerA ? daresForB : daresForA,
        mostInterestingPick: _buildMostInterestingPick(rounds),
        onPlayAgain: () {
          context.pushReplacementNamed('truthOrDareToneSelector');
        },
        onTryAnotherGame: () {
          context.pushReplacementNamed('truthOrDareGame');
        },
      );
    }

    TruthOrDareRound? currentRound;
    for (final round in rounds) {
      if (round.roundNumber == session.currentRound) {
        currentRound = round;
        break;
      }
    }

    final activeTurnUserId = _resolveActiveTurnUserId(
      session: session,
      members: members,
    );

    if (currentRound == null) {
      if (currentUserId == activeTurnUserId) {
        return CardFlipScreen(
          sessionId: session.id,
          roundNumber: session.currentRound,
          totalRounds: session.totalRounds,
          tone: session.tone,
          isPartnerA: isPartnerA,
          partnerName: partnerName,
          activePartnerId: currentUserId,
        );
      }

      return _WaitingForRevealScreen(
        partnerName: partnerName,
        roundNumber: session.currentRound,
        totalRounds: session.totalRounds,
      );
    }

    if (currentRound.bothAnswered) {
      final answerText =
          currentRound.activePartnerId == members.userA
              ? (currentRound.answerA == '__revealed__'
                  ? currentRound.answerB
                  : currentRound.answerA)
              : (currentRound.answerB == '__revealed__'
                  ? currentRound.answerA
                  : currentRound.answerB);

      return TruthOrDareRoundResultScreen(
        questionType: currentRound.questionType,
        questionText: currentRound.questionText,
        partnerName: partnerName,
        answerText: currentRound.questionType == 'truth' ? answerText : null,
        roundNumber: currentRound.roundNumber,
        totalRounds: session.totalRounds,
        onNext: () async {
          final nextRound = currentRound!.roundNumber + 1;
          await ref.read(
            advanceTruthOrDareSessionProvider((
              sessionId: session.id,
              nextRound:
                  nextRound > session.totalRounds
                      ? session.totalRounds + 1
                      : nextRound,
              isCompleted: currentRound.roundNumber >= session.totalRounds,
            )).future,
          );
        },
      );
    }

    if (currentUserId == currentRound.activePartnerId) {
      if (currentRound.questionType == 'truth') {
        return TruthRevealScreen(
          sessionId: session.id,
          roundId: currentRound.id,
          roundNumber: currentRound.roundNumber,
          totalRounds: session.totalRounds,
          tone: session.tone,
          isPartnerA: isPartnerA,
          partnerName: partnerName,
          questionText: currentRound.questionText,
          isCustom: currentRound.isCustom,
          customQuestionId: currentRound.customQuestionId,
        );
      }

      return DareRevealScreen(
        sessionId: session.id,
        roundId: currentRound.id,
        roundNumber: currentRound.roundNumber,
        totalRounds: session.totalRounds,
        tone: session.tone,
        isPartnerA: isPartnerA,
        partnerName: partnerName,
        dareText: currentRound.questionText,
        isCustom: currentRound.isCustom,
        customQuestionId: currentRound.customQuestionId,
      );
    }

    return PartnerWatchingScreen(
      sessionId: session.id,
      roundId: currentRound.id,
      roundNumber: currentRound.roundNumber,
      totalRounds: session.totalRounds,
      tone: session.tone,
      isPartnerA: isPartnerA,
      partnerName: partnerName,
      questionType: currentRound.questionType,
      content: currentRound.questionText,
      hasAnswered: false,
    );
  }

  String _resolveActiveTurnUserId({
    required GameSession session,
    required ({String userA, String userB}) members,
  }) {
    if (session.currentRound <= 1) {
      return session.initiatorId;
    }

    final otherUserId =
        session.initiatorId == members.userA ? members.userB : members.userA;
    return session.currentRound.isOdd ? session.initiatorId : otherUserId;
  }

  Map<String, dynamic> _buildMostInterestingPick(
    List<TruthOrDareRound> rounds,
  ) {
    final truthRounds =
        rounds.where((round) {
          if (round.questionType != 'truth') return false;
          final answer = _roundAnswer(round);
          return answer != null &&
              answer.isNotEmpty &&
              answer != '__revealed__';
        }).toList();

    if (truthRounds.isNotEmpty) {
      truthRounds.sort((a, b) {
        final aAnswer = _roundAnswer(a) ?? '';
        final bAnswer = _roundAnswer(b) ?? '';
        return aAnswer.length.compareTo(bAnswer.length);
      });
      final round = truthRounds.last;
      return {'text': round.questionText, 'answer': _roundAnswer(round) ?? ''};
    }

    for (final round in rounds) {
      if (round.questionType == 'dare') {
        return {'text': round.questionText};
      }
    }

    for (final round in rounds) {
      if (round.isSkip) {
        return {'text': round.questionText};
      }
    }

    return rounds.isEmpty
        ? <String, dynamic>{}
        : {'text': rounds.first.questionText};
  }

  String? _roundAnswer(TruthOrDareRound round) {
    final answers =
        [round.answerA, round.answerB]
            .whereType<String>()
            .where((value) => value.isNotEmpty && value != '__revealed__')
            .toList();
    return answers.isEmpty ? null : answers.first;
  }
}

class _WaitingForRevealScreen extends StatelessWidget {
  const _WaitingForRevealScreen({
    required this.partnerName,
    required this.roundNumber,
    required this.totalRounds,
  });

  final String partnerName;
  final int roundNumber;
  final int totalRounds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Truth or Dare • Round $roundNumber/$totalRounds'),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(Spacing.lg.w),
          child: SemanticContainerWidget(
            title: '$partnerName is up',
            content:
                'They are about to flip the card and see whether they got a truth or a dare.',
            icon: Icons.visibility_outlined,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            borderColor: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.3),
            iconColor: Theme.of(context).colorScheme.primary,
            textTheme: Theme.of(context).textTheme,
          ),
        ),
      ),
    );
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
                  : 'Truth or Dare • ${tone[0].toUpperCase()}${tone.substring(1)} tone • ~15 minutes',
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
