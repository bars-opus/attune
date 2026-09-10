import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/games/invites/services/game_invite_service.dart';
import 'package:attune/features/games/invites/state/game_invite_provider.dart';
import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:attune/features/games/session_games/data/models/session_game_round.dart';
import 'package:attune/features/games/session_games/data/repositories/session_game_repository.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:attune/features/games/session_games/presentation/screens/session_game_flow_scaffold.dart';
import 'package:attune/features/relationships/data/relationship_lifecycle_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = '11111111-1111-1111-1111-111111111111';
const _them = '22222222-2222-2222-2222-222222222222';
const _relationshipId = '33333333-3333-3333-3333-333333333333';
const _sessionId = '44444444-4444-4444-4444-444444444444';

final _signedInUser = User(
  id: _me,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.now().toIso8601String(),
);

/// A repository whose only job is to report an outstanding invitation.
class _InviteRepository extends SessionGameRepository {
  _InviteRepository({required this.initiatorId});

  final String initiatorId;
  int createCalls = 0;

  @override
  Future<({String sessionId, String initiatorId})?> pendingInvite({
    required String relationshipId,
    required String gameType,
  }) async => (sessionId: _sessionId, initiatorId: initiatorId);

  @override
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required String partnerId,
  }) async {
    createCalls++;
    return _sessionId;
  }

  @override
  Future<String> getPartnerId(String relationshipId, String userId) async =>
      _them;

  @override
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async =>
      const [];

  @override
  Future<List<SessionGameQuestion>> fetchQuestions({
    required String gameType,
    required int limit,
  }) async => const [];
}

class _RecordingInviteGateway implements GameInviteGateway {
  final List<String> declined = [];

  @override
  Future<GameInvite> create({
    required String relationshipId,
    required String gameType,
    required String idempotencyKey,
    String tone = 'connecting',
  }) async => const GameInvite(sessionId: _sessionId, existing: false);

  @override
  Future<void> accept(String sessionId) async {}

  @override
  Future<void> decline(String sessionId) async => declined.add(sessionId);
}

void main() {
  Widget host(
    _InviteRepository repository,
    GameInviteGateway gateway,
  ) => ProviderScope(
    overrides: [
      currentUserProvider.overrideWithValue(_signedInUser),
      activeRelationshipIdProvider.overrideWith((ref) async => _relationshipId),
      sessionGameRepositoryProvider.overrideWithValue(repository),
      gameInviteGatewayProvider.overrideWithValue(gateway),
    ],
    child: const MaterialApp(home: SessionGameFlowScaffold(gameType: 'mirror')),
  );

  testWidgets('your own unanswered invitation says so and does not start', (
    tester,
  ) async {
    // Opening it used to start the game, which means accepting your own
    // invitation and playing both sides of it. The partner had not
    // agreed to anything.
    final repository = _InviteRepository(initiatorId: _me);
    await tester.pumpWidget(host(repository, _RecordingInviteGateway()));
    await tester.pumpAndSettle();

    expect(find.text('Invitation sent.'), findsOneWidget);
    expect(find.text('Cancel invitation'), findsOneWidget);
    expect(
      repository.createCalls,
      0,
      reason: 'opening your own invitation started the game',
    );
  });

  testWidgets('cancelling withdraws the invitation through the RPC', (
    tester,
  ) async {
    final gateway = _RecordingInviteGateway();
    await tester.pumpWidget(host(_InviteRepository(initiatorId: _me), gateway));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel invitation'));
    await tester.pumpAndSettle();

    expect(gateway.declined, [_sessionId]);
  });

  testWidgets("the partner's invitation opens the game instead", (
    tester,
  ) async {
    // The other side of the same state. Only the sender waits; the
    // receiver's tap is the acceptance.
    final repository = _InviteRepository(initiatorId: _them);
    await tester.pumpWidget(host(repository, _RecordingInviteGateway()));
    // Fixed pumps rather than pumpAndSettle: with no rounds the flow
    // lands on the end screen, whose animation never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Invitation sent.'), findsNothing);
    expect(
      repository.createCalls,
      1,
      reason: 'the receiver was left waiting on their own invitation',
    );
  });
}
