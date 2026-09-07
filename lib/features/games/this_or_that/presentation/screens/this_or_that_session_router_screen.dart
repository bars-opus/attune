import 'package:attune/features/games/presentation/widgets/game_icon.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/domain/services/scoring_service.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/end_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_screen.dart';
import 'package:attune/features/games/this_or_that/presentation/screens/question_source_screen.dart';
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
    ref.listen(thisOrThatSessionPulseProvider(sessionId), (_, _) {
      ref.invalidate(sessionProvider(sessionId));
      ref.invalidate(sessionRoundsProvider(sessionId));
    });
    ref.watch(thisOrThatSessionPulseProvider(sessionId));

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
                        ref.invalidate(abandonSessionProvider(session.id));
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
                      final request = (
                        sessionId: session.id,
                        intimateConsent: session.tone == 'intimate',
                        fallbackTone: null as String?,
                      );
                      ref.invalidate(acceptThisOrThatSessionProvider(request));
                      await ref.read(
                        acceptThisOrThatSessionProvider(request).future,
                      );
                      ref.invalidate(sessionProvider(session.id));
                    },
                    onDecline: () async {
                      if (session.tone == 'intimate') {
                        final request = (
                          sessionId: session.id,
                          intimateConsent: false,
                          fallbackTone: 'spicy' as String?,
                        );
                        ref.invalidate(
                          acceptThisOrThatSessionProvider(request),
                        );
                        await ref.read(
                          acceptThisOrThatSessionProvider(request).future,
                        );
                      } else {
                        ref.invalidate(abandonSessionProvider(session.id));
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
                        userId: userId,
                        partnerUserId:
                            isPartnerA ? members.userB : members.userA,
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
    required String userId,
    required String partnerUserId,
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

    // The final answered round still needs its reveal and completion action.
    // Rendering results from the local round count skips both and leaves the
    // authoritative session active indefinitely.
    final isCompleted = session.status == 'completed';

    if (isCompleted) {
      final interestingPick = _buildInterestingPick(
        scoringService,
        rounds,
        isPartnerA,
      );
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
      final nextRound = round.roundNumber + 1;
      final isChoosingNext =
          nextRound <= session.totalRounds &&
          (nextRound.isEven ? isPartnerA : !isPartnerA);
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
          if (nextRound <= session.totalRounds) {
            final usedFallback = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder:
                    (_) => QuestionSourceScreen(
                      sessionId: session.id,
                      nextRound: nextRound,
                      totalRounds: session.totalRounds,
                      isChooser: isChoosingNext,
                      chooserName: isChoosingNext ? 'You' : partnerName,
                      currentUserId: userId,
                      partnerUserId: partnerUserId,
                      partnerName: partnerName,
                    ),
              ),
            );
            if (usedFallback == true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No shared questions were available, so we used a preset.',
                  ),
                ),
              );
            }
            return;
          }
          final request = (
            sessionId: session.id,
            nextRound:
                nextRound > session.totalRounds
                    ? session.totalRounds
                    : nextRound,
            matchCount: matchCount,
            totalRoundsCompleted: completedRounds,
            isCompleted: round.roundNumber >= session.totalRounds,
          );
          ref.invalidate(advanceSessionProvider(request));
          await ref.read(advanceSessionProvider(request).future);
        },
        nextLabel:
            round.roundNumber >= session.totalRounds
                ? null
                : isChoosingNext
                ? 'Choose next card'
                : 'See what\'s next',
        hasPrevious: round.roundNumber > 1,
        onPrevious:
            round.roundNumber > 1
                ? () => _openRoundRecap(
                  context: context,
                  rounds: rounds,
                  roundNumber: round.roundNumber - 1,
                  isPartnerA: isPartnerA,
                  partnerName: partnerName,
                )
                : null,
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
        answeredAt:
            isPartnerA ? round.answerASubmittedAt : round.answerBSubmittedAt,
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
      partnerAnswered:
          isPartnerA ? round.hasUserBAnswered : round.hasUserAAnswered,
      isCustom: round.isCustom,
      onAnswerSubmitted: () {
        ref.invalidate(sessionRoundsProvider(session.id));
      },
    );
  }

  Future<void> _openRoundRecap({
    required BuildContext context,
    required List<GameRound> rounds,
    required int roundNumber,
    required bool isPartnerA,
    required String partnerName,
    bool replace = false,
  }) async {
    final round = rounds.where((item) => item.roundNumber == roundNumber).first;
    final route = MaterialPageRoute<void>(
      builder:
          (routeContext) => RevealScreen(
            questionText: round.displayQuestionText,
            userChoice:
                isPartnerA ? (round.answerA ?? '') : (round.answerB ?? ''),
            userChoiceText:
                isPartnerA
                    ? (round.answerAText ?? '')
                    : (round.answerBText ?? ''),
            userChoiceEmoji: _answerEmoji(
              round: round,
              answer: isPartnerA ? round.answerA : round.answerB,
            ),
            partnerChoice:
                isPartnerA ? (round.answerB ?? '') : (round.answerA ?? ''),
            partnerChoiceText:
                isPartnerA
                    ? (round.answerBText ?? '')
                    : (round.answerAText ?? ''),
            partnerChoiceEmoji: _answerEmoji(
              round: round,
              answer: isPartnerA ? round.answerB : round.answerA,
            ),
            partnerName: partnerName,
            roundNumber: round.roundNumber,
            totalRounds: rounds.length,
            isMatch: round.answerA == round.answerB,
            celebrate: false,
            hasPrevious: round.roundNumber > 1,
            onPrevious:
                round.roundNumber > 1
                    ? () => _openRoundRecap(
                      context: routeContext,
                      rounds: rounds,
                      roundNumber: round.roundNumber - 1,
                      isPartnerA: isPartnerA,
                      partnerName: partnerName,
                      replace: true,
                    )
                    : null,
            nextLabel: 'Current round',
            onNext: () => Navigator.of(routeContext).pop(),
          ),
    );

    if (replace) {
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
  }

  String _answerEmoji({required GameRound round, required String? answer}) {
    if (answer == 'a') return round.emojiA ?? '';
    if (answer == 'b') return round.emojiB ?? '';
    return '';
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
    bool isPartnerA,
  ) {
    final mappedRounds =
        rounds
            .map(
              (round) => {
                'question_text': round.displayQuestionText,
                'answer_a': round.answerA,
                'answer_b': round.answerB,
                'answer_a_text':
                    isPartnerA
                        ? (round.answerAText ?? '')
                        : (round.answerBText ?? ''),
                'answer_b_text':
                    isPartnerA
                        ? (round.answerBText ?? '')
                        : (round.answerAText ?? ''),
                'answer_a_emoji':
                    (isPartnerA ? round.answerA : round.answerB) == 'a'
                        ? (round.emojiA ?? '')
                        : (round.emojiB ?? ''),
                'answer_b_emoji':
                    (isPartnerA ? round.answerB : round.answerA) == 'a'
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

class _InviteSentScreen extends StatefulWidget {
  const _InviteSentScreen({required this.partnerName, required this.onCancel});

  final String partnerName;
  final Future<void> Function() onCancel;

  @override
  State<_InviteSentScreen> createState() => _InviteSentScreenState();
}

class _InviteSentScreenState extends State<_InviteSentScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCancel();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'The invitation could not be cancelled. Try once more.';
      });
    }
  }

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
            '${widget.partnerName} has the next move',
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
            onPressed: _busy ? null : _cancel,
            icon:
                _busy
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.close_rounded),
            label: Text(_busy ? 'Cancelling...' : 'Cancel invitation'),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child:
                _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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
  _InvitationAction? _busyAction;
  String? _error;

  Future<void> _run(
    _InvitationAction actionType,
    Future<void> Function() action,
  ) async {
    if (_busyAction != null) return;
    setState(() {
      _busyAction = actionType;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busyAction = null;
        _error =
            'That did not go through. Check your connection and try again.';
      });
    } finally {
      if (mounted && _busyAction != null) {
        setState(() => _busyAction = null);
      }
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
            onPressed:
                _busyAction == null
                    ? () => _run(_InvitationAction.accept, widget.onAccept)
                    : null,
            loading: _busyAction == _InvitationAction.accept,
            icon: Icons.play_arrow_rounded,
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed:
                _busyAction == null
                    ? () => _run(_InvitationAction.decline, widget.onDecline)
                    : null,
            child:
                _busyAction == _InvitationAction.decline
                    ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      isIntimate ? 'Play at Spicy instead' : 'Maybe later',
                    ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child:
                _error == null
                    ? const SizedBox.shrink()
                    : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
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

enum _InvitationAction { accept, decline }

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
