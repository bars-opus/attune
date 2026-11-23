import 'dart:async';

import 'package:attune/features/chat/presentation/screens/chat_screen.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart';
import 'package:attune/features/games/presentation/widgets/chat_games_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef LegacyGameOpener =
    Future<void> Function(
      BuildContext context,
      String gameType, {
      String? sessionId,
    });

/// Opens a game's current screens through the chat's routing switch.
/// Overridden in tests.
///
/// The chat already knows where every game lives; going through its switch
/// keeps one routing table until each game is redrawn on the shell.
///
/// Completes once navigation has begun, not when the game is closed:
/// openGameRoute awaits its push, which lasts until the game screen is
/// popped and never ends at all if that screen replaces itself. The landing
/// page holds its button busy until this completes, so awaiting the push
/// would leave it spinning; the page hears the player is back through
/// GameController.onResume instead.
final legacyGameOpenerProvider = Provider<LegacyGameOpener>((ref) {
  return (context, gameType, {sessionId}) async {
    final destination = chatGameDestinationForType(gameType);
    // A game with no screens (Never Have I Ever) has nowhere to go.
    if (destination == null) return;
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    if (relationshipId == null || !context.mounted) return;
    unawaited(
      openGameRoute(
        context,
        destination,
        relationshipId: relationshipId,
        sessionId: sessionId,
      ),
    );
  };
});
