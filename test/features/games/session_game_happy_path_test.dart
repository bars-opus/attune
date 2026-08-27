import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/games/mirror/presentation/screens/mirror_judge_screen.dart';
import 'package:attune/features/games/mirror/presentation/screens/mirror_question_screen.dart';
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
const _them = 'user-them';
const _relationshipId = 'rel-1';
const _sessionId = 'session-1';

/// A two-round Mirror session where the caller is the subject of round
/// 1 and the guesser in round 2.
///
/// Subclasses the real repository rather than mocking an interface:
/// every network method is overridden here, so no call can reach
/// Supabase, and any method added to the parent without being overridden
/// would fail loudly on a null client rather than silently passing.
class _FakeRepository extends SessionGameRepository {
  _FakeRepository();

  final List<String> submitted = [];
  final List<bool> judgements = [];
  bool completed = false;

  /// Flipped by the test once it wants the reveal gate to open, so the
  /// waiting stage is exercised rather than skipped.
  bool bothAnswered = false;

  /// An answer the server would return with both_answered still false.
  /// Lets the gate test prove the GATE withholds it, rather than the
  /// payload merely being empty.
  String? answerAWhileClosed;

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
      _them;

  @override
  Future<List<SessionGameRound>> fetchRounds(String sessionId) async => const [
        // Round 1: the caller is the subject, so they answer about
        // themselves and judge their partner's guess.
        SessionGameRound(
          id: 'round-1',
          roundNumber: 1,
          questionId: 'q1',
          bothAnswered: false,
          subjectId: _me,
        ),
        // Round 2: the partner is the subject, so the caller guesses
        // and never reaches the judge step.
        SessionGameRound(
          id: 'round-2',
          roundNumber: 2,
          questionId: 'q2',
          bothAnswered: false,
          subjectId: _them,
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
        SessionGameQuestion(
          id: 'q2',
          gameType: 'mirror',
          questionText: 'What are they most looking forward to?',
        ),
      ];

  @override
  Future<bool> submitAnswer({
    required String roundId,
    required String answer,
  }) async {
    submitted.add(answer);
    return true;
  }

  @override
  Future<RevealedRound> fetchRevealedRound(String roundId) async =>
      RevealedRound(
        answerA: bothAnswered ? 'their guess about me' : answerAWhileClosed,
        answerB: null,
        bothAnswered: bothAnswered,
      );

  @override
  Future<bool> isUserA(String relationshipId) async => false;

  @override
  Future<String?> fetchMirrorTruth(String roundId) async => 'work has been hard';

  @override
  Future<void> judgeRound({
    required String roundId,
    required bool wasCorrect,
  }) async {
    judgements.add(wasCorrect);
  }

  @override
  Future<void> completeSession(
    String sessionId, {
    required String gameType,
  }) async {
    completed = true;
  }

  @override
  Future<int?> fetchMirrorScore(String sessionId) async => 1;
}

/// A minimal authenticated user: the scaffold reads only `id` off it.
final _signedInUser = User(
  id: _me,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
);

void main() {
  testWidgets(
    'a Mirror session plays through question, waiting, reveal, judge and end',
    (tester) async {
      final repository = _FakeRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            activeRelationshipIdProvider
                .overrideWith((ref) async => _relationshipId),
            sessionGameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: SessionGameFlowScaffold(gameType: 'mirror'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ---- Round 1, question: the caller IS the subject (C3) ----
      expect(find.byType(MirrorQuestionScreen), findsOneWidget);
      expect(
        find.text(
          'Answer honestly about yourself — your partner is trying to read you.',
        ),
        findsOneWidget,
        reason: 'the subject must be told they are answering about themselves',
      );

      await tester.enterText(find.byType(TextField), 'work has been hard');
      await tester.tap(find.text('Submit'));
      // Not pumpAndSettle: the waiting screen polls on a periodic Timer
      // that never goes idle, so settling would time out.
      await tester.pump();
      await tester.pump();

      // ---- Waiting: the partner has not answered yet ----
      expect(find.text('Waiting for your partner'), findsOneWidget);
      expect(repository.submitted, ['work has been hard']);

      // The partner answers; the next poll opens the reveal gate.
      repository.bothAnswered = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pumpAndSettle();

      // ---- Reveal ----
      expect(find.text('You said'), findsOneWidget);
      expect(find.text('They said'), findsOneWidget);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // ---- Judge: subject-only, and it must show no running tally ----
      expect(find.byType(MirrorJudgeScreen), findsOneWidget);
      expect(find.text('work has been hard'), findsOneWidget);
      expect(find.text('their guess about me'), findsOneWidget);

      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(repository.judgements, [true]);

      // ---- Round 2, question: the caller is the GUESSER, not the
      // subject, so the second-person framing must be gone (C3) ----
      expect(find.byType(MirrorQuestionScreen), findsOneWidget);
      expect(
        find.text(
          'Answer honestly about yourself — your partner is trying to read you.',
        ),
        findsNothing,
        reason: 'the guesser must not be told to answer about themselves',
      );

      repository.bothAnswered = false;
      await tester.enterText(find.byType(TextField), 'a quiet weekend');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump();

      repository.bothAnswered = true;
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // ---- End: the last round completes the session, and only the
      // viewer's own score is shown (§11.1) ----
      expect(repository.completed, isTrue);
      expect(find.text('That is the end'), findsOneWidget);
      expect(find.text('You read them 1 of 4 times'), findsOneWidget);

      // The caller was subject in round 1 only, so exactly one judgement.
      expect(repository.judgements, [true]);
    },
  );

  testWidgets(
    'the reveal stage withholds answers while the gate is still closed',
    (tester) async {
      // The happy path only ever reaches reveal after both partners have
      // answered, so it cannot catch a removed gate. This drives the
      // reveal stage while the server still reports both_answered=false
      // — the §8.4 case where a partner's answer must stay hidden.
      final repository = _FakeRepository();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProvider.overrideWithValue(_signedInUser),
            activeRelationshipIdProvider
                .overrideWith((ref) async => _relationshipId),
            sessionGameRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: SessionGameFlowScaffold(gameType: 'mirror'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'work has been hard');
      await tester.tap(find.text('Submit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Waiting for your partner'), findsOneWidget);

      // Force the flow into reveal WITHOUT the gate opening: a stale
      // build or an early poll landing here must not render a
      // half-empty comparison.
      repository.answerAWhileClosed = 'their guess about me';
      final element = tester.element(find.byType(SessionGameFlowScaffold));
      ProviderScope.containerOf(element, listen: false)
          .read(sessionGameFlowProvider.notifier)
          .onRevealed();
      await tester.pump();
      await tester.pump();

      expect(
        find.text('their guess about me'),
        findsNothing,
        reason: "the partner's answer must never render before the gate opens",
      );
      expect(find.text('You said'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
    },
  );
}
