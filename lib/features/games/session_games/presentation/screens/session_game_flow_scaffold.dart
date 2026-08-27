import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/games/mirror/presentation/screens/mirror_judge_screen.dart';
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_end_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_reveal_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_router_screen.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_waiting_screen.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _genericErrorMessage = 'Could not start this game. Please try again.';

/// Renders whichever stage the flow controller is in, starting the
/// session on first build.
///
/// One scaffold for all three games: they share waiting, reveal and end,
/// and differ only in how an answer is captured (handled by
/// SessionGameRouterScreen) and whether a judge step exists (Mirror
/// only).
///
/// A ConsumerStatefulWidget rather than a ConsumerWidget: start() must
/// run exactly once per session, and nothing else in this widget's
/// build() is a safe place to trigger it — build() reruns on every
/// provider change, and calling start() from within it would re-create
/// the session on every rebuild.
class SessionGameFlowScaffold extends ConsumerStatefulWidget {
  const SessionGameFlowScaffold({super.key, required this.gameType});

  final String gameType;

  @override
  ConsumerState<SessionGameFlowScaffold> createState() =>
      _SessionGameFlowScaffoldState();
}

class _SessionGameFlowScaffoldState
    extends ConsumerState<SessionGameFlowScaffold> {
  bool _starting = false;

  /// Set when there is no relationship/user to start a session with — a
  /// signed-out or unpaired user reaching this route. Distinct from
  /// "still starting": that case must keep spinning; this one must
  /// stop and show the generic message, or the user spins forever.
  bool _unavailable = false;

  @override
  void initState() {
    super.initState();
    // Cannot touch a provider synchronously during initState; scheduling
    // via addPostFrameCallback defers it to just after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (_starting || !mounted) return;
    _starting = true; // guards a double-start if the widget rebuilds

    final userId = ref.read(currentUserProvider)?.id;
    final relationshipId = await ref.read(activeRelationshipIdProvider.future);
    if (!mounted) return;

    if (userId == null || relationshipId == null) {
      setState(() => _unavailable = true);
      return;
    }

    final repository = ref.read(sessionGameRepositoryProvider);
    final partnerId = await repository.getPartnerId(relationshipId, userId);
    if (!mounted) return;

    await ref.read(sessionGameFlowProvider.notifier).start(
          gameType: widget.gameType,
          relationshipId: relationshipId,
          userId: userId,
          // Sourced from the authenticated relationship row, never from
          // the caller — start()'s own contract requires the real
          // partner, because nothing downstream validates it.
          partnerId: partnerId,
        );
  }

  @override
  Widget build(BuildContext context) {
    if (_unavailable) {
      return const Scaffold(
        body: Center(child: Text(_genericErrorMessage)),
      );
    }

    final async = ref.watch(sessionGameFlowProvider);
    final notifier = ref.read(sessionGameFlowProvider.notifier);

    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          // Never render the raw error: it can carry row contents.
          child: Text(_genericErrorMessage),
        ),
        data: (flow) {
          final question = notifier.currentQuestion;
          if (question == null) {
            // Either the relationship/user is still resolving, or
            // start() is in flight. _unavailable (checked above) is
            // what stops this from spinning forever in the one case
            // where nothing will ever arrive.
            return const Center(child: CircularProgressIndicator());
          }

          switch (flow.stage) {
            case SessionGameStage.question:
              return SessionGameRouterScreen(
                question: question,
                onSubmit: notifier.submit,
              );
            case SessionGameStage.waiting:
              return SessionGameWaitingScreen(
                roundId: notifier.currentRoundId!,
                onRevealed: notifier.onRevealed,
              );
            case SessionGameStage.reveal:
              return _RevealStage(notifier: notifier);
            case SessionGameStage.judge:
              return _JudgeStage(notifier: notifier);
            case SessionGameStage.end:
              return SessionGameEndScreen(
                onDone: () => Navigator.of(context).pop(),
              );
          }
        },
      ),
    );
  }
}

/// Fetches the revealed round through the gated RPC and hands it to
/// [SessionGameRevealScreen].
///
/// Also resolves which answer slot is the viewer's own: answer_a and
/// answer_b are assigned by `relationships.user_a`/`user_b`, not by who
/// is asking, so that must come from the server rather than being
/// guessed client-side.
class _RevealStage extends StatelessWidget {
  const _RevealStage({required this.notifier});

  final SessionGameFlowNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final roundId = notifier.currentRoundId;
    final relationshipId = notifier.relationshipId;
    if (roundId == null || relationshipId == null) {
      return const Center(
        child: Text('Could not start this game. Please try again.'),
      );
    }

    final repository = SessionGameRepository();

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        repository.fetchRevealedRound(roundId),
        repository.isUserA(relationshipId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // Never render the raw error: it can carry row contents.
          return const Center(
            child: Text('Could not start this game. Please try again.'),
          );
        }

        final round = snapshot.data![0] as RevealedRound;
        final yourAnswerIsA = snapshot.data![1] as bool;

        // The reveal gate: this stage must only render once both
        // partners have answered (§8.4). A poll landing here early
        // (or a stale build) waits rather than showing a half-empty
        // comparison.
        if (!round.bothAnswered) {
          return const Center(child: CircularProgressIndicator());
        }

        return SessionGameRevealScreen(
          round: round,
          yourAnswerIsA: yourAnswerIsA,
          // advance() reads stageAfterReveal() itself: Mirror's subject
          // lands on the judge step, everyone else proceeds to the next
          // round or the end.
          onNext: notifier.advance,
        );
      },
    );
  }
}

/// Fetches the subject's truth and the revealed round, then hands them
/// to [MirrorJudgeScreen].
///
/// Mirror-only, and only the round's subject ever reaches this stage
/// (§8.4) — the flow controller enforces that in stageAfterReveal.
class _JudgeStage extends StatelessWidget {
  const _JudgeStage({required this.notifier});

  final SessionGameFlowNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final roundId = notifier.currentRoundId;
    if (roundId == null) {
      return const Center(
        child: Text('Could not start this game. Please try again.'),
      );
    }

    final repository = SessionGameRepository();

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        repository.fetchMirrorTruth(roundId),
        repository.fetchRevealedRound(roundId),
      ]),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData) {
          // Never render the raw error: it can carry row contents.
          return const Center(
            child: Text('Could not start this game. Please try again.'),
          );
        }

        final truth = snapshot.data![0] as String?;
        final round = snapshot.data![1] as RevealedRound;

        // The subject's own guess-facing slot is always empty (their
        // text went to mirror_round_truth, not answer_a/answer_b), so
        // the partner's guess is whichever slot is non-null.
        final theirGuess = round.answerA ?? round.answerB ?? '';

        return MirrorJudgeScreen(
          yourTruth: truth ?? '',
          theirGuess: theirGuess,
          onJudge: notifier.judge,
        );
      },
    );
  }
}
