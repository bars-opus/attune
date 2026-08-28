import 'package:attune/features/auth/providers/auth_provider.dart';
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

const _me = 'user-me';
const _sessionId = 'session-1';

final _signedInUser = User(
  id: _me,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
);

class _FakeRepository extends SessionGameRepository {
  final List<String> abandoned = [];

  @override
  Future<String> createSession({
    required String relationshipId,
    required String initiatorId,
    required String gameType,
    required String partnerId,
  }) async =>
      _sessionId;

  @override
  Future<String> getPartnerId(String relationshipId, String userId) async =>
      'user-them';

  @override
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async => const [
        SessionGameRound(
          id: 'round-1',
          roundNumber: 1,
          questionId: 'q1',
          bothAnswered: false,
          subjectId: _me,
        ),
      ];

  @override
  Future<List<SessionGameQuestion>> fetchQuestions({
    required String gameType,
    required int limit,
  }) async =>
      const [
        SessionGameQuestion(
          id: 'q1',
          gameType: 'mirror',
          questionText: 'What is weighing on them most this week?',
        ),
      ];

  @override
  Future<void> abandonSession(String sessionId) async {
    abandoned.add(sessionId);
  }
}

void main() {
  testWidgets('a stuck game can be left, which abandons the session',
      (tester) async {
    final repository = _FakeRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(_signedInUser),
          activeRelationshipIdProvider.overrideWith((ref) async => 'rel-1'),
          sessionGameRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: SessionGameFlowScaffold(gameType: 'mirror'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The control exists...
    final leave = find.byTooltip('Leave this game');
    expect(leave, findsOneWidget);

    // ...and confirms before acting: leaving is not undoable, and a
    // mis-tap would end a round the couple is partway through.
    await tester.tap(leave);
    await tester.pumpAndSettle();
    expect(repository.abandoned, isEmpty);

    // Declining must NOT abandon. Asserting only the accept path lets a
    // build with no confirmation at all pass, since the accept tap
    // satisfies both.
    await tester.tap(find.text('Stay'));
    await tester.pumpAndSettle();
    expect(
      repository.abandoned,
      isEmpty,
      reason: 'declining the dialog must leave the session alone',
    );

    // Accepting does.
    await tester.tap(leave);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(repository.abandoned, [_sessionId]);
  });
}
