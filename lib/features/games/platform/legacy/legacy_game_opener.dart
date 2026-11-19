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
final legacyGameOpenerProvider = Provider<LegacyGameOpener>((ref) {
  return (context, gameType, {sessionId}) async {
    final destination = chatGameDestinationForType(gameType);
    // A game with no screens (Never Have I Ever) has nowhere to go.
    if (destination == null) return;
    final relationshipId = await ref.read(currentRelationshipIdProvider.future);
    if (relationshipId == null || !context.mounted) return;
    await openGameRoute(
      context,
      destination,
      relationshipId: relationshipId,
      sessionId: sessionId,
    );
  };
});
