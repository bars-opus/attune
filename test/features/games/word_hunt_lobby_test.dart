import 'package:attune/features/games/word_hunt/models/word_hunt_models.dart';
import 'package:attune/features/games/word_hunt/presentation/screens/word_hunt_lobby_screen.dart';
import 'package:attune/features/games/word_hunt/presentation/state/word_hunt_provider.dart';
import 'package:attune/features/games/word_hunt/services/word_hunt_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The lobby's job is to offer exactly one thing at a time, correctly.
///
/// Four states share this screen -- nothing open, my invitation pending,
/// their invitation waiting for me, and a game in progress -- and showing
/// the wrong one either starts a game nobody agreed to or hides one
/// already running.
class _LobbyGateway implements WordHuntGateway {
  _LobbyGateway({this.active, this.currentUser = 'u1'});

  WordHuntSession? active;
  String currentUser;
  WordHuntApiError? failCreate;
  int createCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;

  @override
  Future<String> createSession({
    required String relationshipId,
    required String idempotencyKey,
  }) async {
    createCalls++;
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
  Future<void> show(WidgetTester tester, _LobbyGateway gateway) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wordHuntGatewayProvider.overrideWithValue(gateway),
          wordHuntCurrentUserIdProvider.overrideWithValue(gateway.currentUser),
        ],
        child: const MaterialApp(
          home: WordHuntLobbyScreen(relationshipId: 'r1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('nothing open: offers to invite, and says what the game is', (
    tester,
  ) async {
    await show(tester, _LobbyGateway());

    expect(find.text('Invite them to hunt'), findsOneWidget);
    expect(find.text('One hidden word.'), findsOneWidget);
    // The clock is stated up front, because tapping Start later is what
    // begins it and that must not surprise anyone.
    expect(find.textContaining('starts when you tap Start'), findsOneWidget);
  });

  testWidgets('inviting asks the server once', (tester) async {
    final gateway = _LobbyGateway();
    await show(tester, gateway);

    await tester.tap(find.text('Invite them to hunt'));
    await tester.pump();
    await tester.pump();

    expect(gateway.createCalls, 1);
  });

  testWidgets('my own pending invitation waits rather than opening a board', (
    tester,
  ) async {
    // Both players hunt the same grid. Opening a board here would start a
    // clock against a partner who has not agreed to play.
    await show(
      tester,
      _LobbyGateway(active: invitation(initiator: 'u1'), currentUser: 'u1'),
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
    );

    expect(find.text('Join the hunt'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('declining tells the server and clears the invitation', (
    tester,
  ) async {
    final gateway = _LobbyGateway(
      active: invitation(initiator: 'u2'),
      currentUser: 'u1',
    );
    await show(tester, gateway);

    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump();

    expect(gateway.declineCalls, 1);
  });

  testWidgets('an accepted game offers to open it, not to start another', (
    tester,
  ) async {
    final gateway = _LobbyGateway(
      active: invitation(initiator: 'u2', status: 'active'),
      currentUser: 'u1',
    );
    await show(tester, gateway);

    expect(find.text('Open the hunt'), findsOneWidget);
    expect(find.text('Invite them to hunt'), findsNothing);
    expect(gateway.createCalls, 0);
  });

  testWidgets('a hunt already begun says so, so the clock is not a surprise', (
    tester,
  ) async {
    await show(
      tester,
      _LobbyGateway(
        active: invitation(initiator: 'u2', status: 'active', started: true),
        currentUser: 'u1',
      ),
    );

    expect(find.text('Back to your hunt'), findsOneWidget);
  });

  testWidgets('a create failure is shown in the player\'s language', (
    tester,
  ) async {
    final gateway = _LobbyGateway()
      ..failCreate = const WordHuntApiError(
        code: 'RATE_LIMITED',
        message: 'Slow down a moment.',
      );
    await show(tester, gateway);

    await tester.tap(find.text('Invite them to hunt'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Slow down a moment.'), findsOneWidget);
    // Checklist 5.5: the code is internal.
    expect(find.textContaining('RATE_LIMITED'), findsNothing);
  });
}
