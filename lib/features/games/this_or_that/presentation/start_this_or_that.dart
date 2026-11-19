import 'package:attune/features/games/platform/shell/game_material_theme.dart';
import 'package:attune/features/games/this_or_that/data/models/game_round.dart';
import 'package:attune/features/games/this_or_that/presentation/providers/this_or_that_providers.dart';
import 'package:attune/features/games/this_or_that/this_or_that_game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a game in [tone]. Returns the new session's id, or null when it
/// did not start: no active relationship, the Intimate question declined,
/// or an error (already shown to the player).
///
/// Opens nothing: where the game goes next is the caller's to decide. The
/// tone screen replaces itself with the game; the landing page pushes it.
Future<String?> startThisOrThat(
  BuildContext context,
  WidgetRef ref, {
  required String tone,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final relationshipId = await ref.read(currentRelationshipIdProvider.future);
  if (relationshipId == null) {
    if (!context.mounted) return null;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('This game unlocks when a relationship is active.'),
      ),
    );
    return null;
  }

  if (tone == 'intimate') {
    if (!context.mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      // Asked over a game, whose screens are dark whatever the app is
      // doing; the route above it would otherwise take the app's theme.
      builder:
          (dialogContext) => Theme(
            data: gameMaterialTheme(dialogContext, thisOrThatTheme),
            child: AlertDialog(
              icon: const Icon(Icons.favorite_outline_rounded),
              title: const Text('Choose Intimate together'),
              content: const Text(
                'This tone includes adult questions for committed couples. Your partner will also be asked before the game begins.',
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
    );
    if (confirmed != true) return null;
  }

  try {
    final request = (relationshipId: relationshipId, tone: tone);
    ref.invalidate(createThisOrThatSessionProvider(request));
    final session = await ref.read(
      createThisOrThatSessionProvider(request).future,
    );
    return session.id;
  } catch (_) {
    if (context.mounted) {
      messenger.showSnackBar(
        const SnackBar(content: Text('The game could not start. Try again.')),
      );
    }
    return null;
  }
}

/// When the player may nudge: they have answered the current round, their
/// partner has not, and their answer is at least two hours old.
///
/// The current round is the first one not yet answered by both. The two
/// hours are the waiting screen's: it offers the nudge once that long has
/// passed since the answer, and never for an answer with no time on it.
bool thisOrThatCanRemind({
  required List<GameRound> rounds,
  required bool viewerIsPartnerA,
  required DateTime now,
}) {
  final ordered = [...rounds]
    ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
  GameRound? current;
  for (final round in ordered) {
    if (!round.bothAnswered) {
      current = round;
      break;
    }
  }
  if (current == null) return false;

  final viewerAnswered =
      viewerIsPartnerA ? current.hasUserAAnswered : current.hasUserBAnswered;
  final partnerAnswered =
      viewerIsPartnerA ? current.hasUserBAnswered : current.hasUserAAnswered;
  if (!viewerAnswered || partnerAnswered) return false;

  final answeredAt =
      viewerIsPartnerA
          ? current.answerASubmittedAt
          : current.answerBSubmittedAt;
  if (answeredAt == null) return false;
  final reminderDelay = const Duration(hours: 2) - now.difference(answeredAt);
  return reminderDelay <= Duration.zero;
}
