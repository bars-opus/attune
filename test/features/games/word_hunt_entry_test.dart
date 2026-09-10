import 'dart:io';

import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/screens/word_hunt_game_screen.dart';
import 'package:attune/features/games/presentation/providers/game_session_live_provider.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opening Word Hunt must land on exactly the right state, every time.
///
/// The lobby that used to make this decision is gone; the hunt itself
/// makes it now. Four states share the screen -- nothing open, my
/// invitation pending, their invitation waiting for me, and a game in
/// progress -- and showing the wrong one either starts a game nobody
/// agreed to or hides one already running.
class _LobbyGateway implements WordHuntGateway {
  _LobbyGateway({this.active, this.currentUser = 'u1'});

  WordHuntSession? active;
  String currentUser;
  WordHuntApiError? failCreate;

  /// Fails only the first create, so a retry can be observed.
  bool failFirstCreateOnly = false;
  final List<String> createKeys = [];
  int createCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    createCalls++;
    createKeys.add(idempotencyKey);
    if (failFirstCreateOnly && createCalls == 1) {
      throw const WordHuntApiError(code: 'NETWORK', message: 'Try again.');
    }
    final error = failCreate;
    if (error != null) throw error;
    return 's1';
  }

  @override
  Future<void> acceptSession(String sessionId) async => acceptCalls++;

  @override
  Future<void> declineSession(String sessionId) async {
    declineCalls++;
    active = null;
  }

  @override
  Future<WordHuntSession> start(String sessionId) async => active!;

  @override
  Future<WordHuntSubmission> submit({
    required String sessionId,
    required List<WordHuntCell> cells,
  }) async => WordHuntSubmission(hit: false, session: active!);

  @override
  Future<WordHuntSession> giveUp(String sessionId) async => active!;

  @override
  Future<WordHuntSession> getState(String sessionId) async => active!;

  @override
  Future<WordHuntSession?> getActiveSession(String relationshipId) async =>
      active;
}

WordHuntSession invitation({
  required String initiator,
  String status = 'invited',
  bool started = false,
}) => WordHuntSession.fromJson({
  'session_id': 's1',
  'relationship_id': 'r1',
  'initiator_id': initiator,
  'status': status,
  'user_a': 'u1',
  'user_b': 'u2',
  'partner_id': 'u2',
  'word_length': 4,
  'server_observed_at': '2026-09-08T12:00:00Z',
  'both_terminal': false,
  if (started) 'my_started_at': '2026-09-08T12:00:00Z',
});

void main() {
  /// Opens the hunt the way the picker does: no session in hand, so the
  /// screen resolves one.
  Future<void> show(
    WidgetTester tester,
    _LobbyGateway gateway, {
    String? sessionId,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordHuntGatewayProvider.overrideWithValue(gateway),
          wordHuntCurrentUserIdProvider.overrideWithValue(gateway.currentUser),
          gameSessionLiveProvider.overrideWith(
            (_, __) => const Stream<void>.empty(),
          ),
        ],
        child: MaterialApp(
          home: WordHuntGameScreen(relationshipId: 'r1', sessionId: sessionId),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('nothing open: starts a hunt instead of asking twice', (
    tester,
  ) async {
    // From the picker. The tap on the game already said what the player
    // wants; the lobby's "Invite them to hunt" button asked it again.
    final gateway = _LobbyGateway();
    await show(tester, gateway);

    expect(gateway.createCalls, 1);
    expect(find.text('Invite them to hunt'), findsNothing);
    expect(find.text('One hidden word.'), findsNothing);
  });

  testWidgets('a hunt already open is resumed, never duplicated', (
    tester,
  ) async {
    final gateway = _LobbyGateway(
      active: invitation(initiator: 'u2', status: 'active'),
      currentUser: 'u1',
    );
    await show(tester, gateway);

    expect(gateway.createCalls, 0);
  });

  testWidgets('my own pending invitation waits, over the hunt itself', (
    tester,
  ) async {
    // Both players hunt the same grid, so there is genuinely nothing for
    // the sender to do yet -- but that is a line, not a screen, and no
    // clock starts by being here.
    await show(
      tester,
      _LobbyGateway(active: invitation(initiator: 'u1'), currentUser: 'u1'),
      sessionId: 's1',
    );

    expect(find.textContaining('Waiting for them'), findsOneWidget);
    expect(find.text('Cancel the invitation'), findsOneWidget);
    expect(find.text('Join the hunt'), findsNothing);
  });

  testWidgets('their invitation offers joining, and offers declining', (
    tester,
  ) async {
    await show(
      tester,
      _LobbyGateway(active: invitation(initiator: 'u2'), currentUser: 'u1'),
      sessionId: 's1',
    );

    expect(find.text('Join the hunt'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('joining tells the server', (tester) async {
    final gateway = _LobbyGateway(
      active: invitation(initiator: 'u2'),
      currentUser: 'u1',
    );
    await show(tester, gateway, sessionId: 's1');

    await tester.tap(find.text('Join the hunt'));
    await tester.pump();
    await tester.pump();

    expect(gateway.acceptCalls, 1);
  });

  testWidgets('declining tells the server and clears the invitation', (
    tester,
  ) async {
    final gateway = _LobbyGateway(
      active: invitation(initiator: 'u2'),
      currentUser: 'u1',
    );
    await show(tester, gateway, sessionId: 's1');

    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump();

    expect(gateway.declineCalls, 1);
  });

  testWidgets('an accepted hunt opens the start gate, not a lobby button', (
    tester,
  ) async {
    // The clock still cannot start by accident: the hunt's own start
    // gate says so, which is what the lobby's copy was duplicating.
    await show(
      tester,
      _LobbyGateway(
        active: invitation(initiator: 'u2', status: 'active'),
        currentUser: 'u1',
      ),
      sessionId: 's1',
    );

    expect(
      find.textContaining('Tapping Start begins your clock'),
      findsOneWidget,
    );
    expect(find.text('Open the hunt'), findsNothing);
  });

  testWidgets('a create failure is shown in the player\'s language', (
    tester,
  ) async {
    final gateway =
        _LobbyGateway()
          ..failCreate = const WordHuntApiError(
            code: 'RATE_LIMITED',
            message: 'Slow down a moment.',
          );
    await show(tester, gateway);

    expect(find.text('Slow down a moment.'), findsOneWidget);
    // Checklist 5.5: the code is internal.
    expect(find.textContaining('RATE_LIMITED'), findsNothing);
  });

  testWidgets(
    'a retried start reuses its key rather than starting a second hunt',
    (tester) async {
      // Checklist 1.1 / 2.18. A create whose response was dropped may well
      // have succeeded on the server. Minting a fresh key on "Try again"
      // would start a SECOND hunt for a couple who asked for one -- so the
      // failed attempt keeps its key and the retry is the same request.
      final gateway = _LobbyGateway()..failFirstCreateOnly = true;
      await show(tester, gateway);

      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(gateway.createKeys, hasLength(2));
      expect(
        gateway.createKeys[1],
        gateway.createKeys[0],
        reason: 'the retry started a second hunt instead of retrying the first',
      );
    },
  );

  testWidgets('the lobby is gone and must not come back', (tester) async {
    final router = File('lib/app/routing/app_router.dart').readAsStringSync();
    final chat =
        File(
          'lib/features/chat/presentation/screens/chat_screen.dart',
        ).readAsStringSync();
    expect(router.contains('wordHuntLobby'), isFalse);
    expect(chat.contains('wordHuntLobby'), isFalse);
    expect(router.contains("name: 'wordHuntGame'"), isTrue);
  });
}
