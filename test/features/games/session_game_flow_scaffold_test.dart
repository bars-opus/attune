import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_flow_scaffold.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'shows the generic message, not a spinner, when there is no '
    'active relationship',
    (tester) async {
      // A signed-out or unpaired user reaching this route has nothing
      // for start() to build a session from. Overriding
      // activeRelationshipIdProvider and currentUserProvider directly
      // avoids needing a real Supabase client or auth session — both
      // are plain providers the scaffold reads, so overriding them is
      // enough to exercise the real widget end to end.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(null),
            activeRelationshipIdProvider.overrideWith((ref) async => null),
          ],
          child: const MaterialApp(
            home: SessionGameFlowScaffold(gameType: 'mirror'),
          ),
        ),
      );

      // initState's addPostFrameCallback needs one frame to fire, and
      // _maybeStart awaits the overridden FutureProvider.
      await tester.pumpAndSettle();

      expect(
        find.text('Could not start this game. Please try again.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );
}
