import 'package:attune/features/games/this_or_that/data/models/this_or_that_session.dart';
import 'package:attune/features/games/this_or_that/data/repositories/this_or_that_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockThisOrThatRepository extends Mock implements ThisOrThatRepository {}

/// A session as the server returns one.
ThisOrThatSession thisOrThatSession({
  String id = 's1',
  String initiatorId = 'user-a',
  String tone = 'connecting',
  String status = 'active',
  int totalRounds = 10,
  int currentRound = 3,
}) {
  return ThisOrThatSession(
    id: id,
    relationshipId: 'rel-1',
    initiatorId: initiatorId,
    tone: tone,
    status: status,
    totalRounds: totalRounds,
    currentRound: currentRound,
    matchCount: 0,
    totalRoundsCompleted: 0,
    createdAt: DateTime.utc(2026, 11, 19),
  );
}

/// Answers createSession with a session whose id is [id], in the tone asked
/// for.
void createSessionAnswers(
  MockThisOrThatRepository repository, {
  String id = 'new-session',
}) {
  when(
    () => repository.createSession(
      relationshipId: any(named: 'relationshipId'),
      initiatorId: any(named: 'initiatorId'),
      tone: any(named: 'tone'),
      idempotencyKey: any(named: 'idempotencyKey'),
    ),
  ).thenAnswer((invocation) async {
    final tone = invocation.namedArguments[#tone] as String;
    return thisOrThatSession(id: id, tone: tone, status: 'invited');
  });
}

/// The tones createSession was called with, in order.
List<String> createdTones(MockThisOrThatRepository repository) {
  return verify(
    () => repository.createSession(
      relationshipId: any(named: 'relationshipId'),
      initiatorId: any(named: 'initiatorId'),
      tone: captureAny(named: 'tone'),
      idempotencyKey: any(named: 'idempotencyKey'),
    ),
  ).captured.cast<String>();
}

void verifyNoSessionCreated(MockThisOrThatRepository repository) {
  verifyNever(
    () => repository.createSession(
      relationshipId: any(named: 'relationshipId'),
      initiatorId: any(named: 'initiatorId'),
      tone: any(named: 'tone'),
      idempotencyKey: any(named: 'idempotencyKey'),
    ),
  );
}
