import 'package:attune/features/games/session_games/domain/session_game_flow_state.dart';
import 'package:attune/features/games/session_games/presentation/providers/session_game_flow_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isAlreadySubmitted', () {
    test('recognises the server\'s resubmission message', () {
      // "Answer already submitted" is NOT a failure: it is the normal
      // state of a user returning to a round they answered before
      // backgrounding the app or losing signal. Surfacing it as an error
      // would show a scary message on a round that is perfectly fine.
      expect(
        isAlreadySubmitted(Exception('Answer already submitted')),
        isTrue,
      );
    });

    test('does not swallow other failures', () {
      // A genuine failure must still surface — treating everything as
      // "already submitted" would hide real breakage.
      expect(isAlreadySubmitted(Exception('Round not found')), isFalse);
      expect(
        isAlreadySubmitted(Exception('Rating must be an integer from 1 to 10')),
        isFalse,
      );
      expect(isAlreadySubmitted(Exception('network unreachable')), isFalse);
    });
  });

  group('subjectOf', () {
    test('the viewer is the subject when the round names them', () {
      expect(subjectOf(subjectId: 'me', userId: 'me'), isTrue);
    });

    test('the viewer is not the subject when the round names the partner', () {
      expect(subjectOf(subjectId: 'them', userId: 'me'), isFalse);
    });

    test('a round with no subject makes nobody the subject', () {
      // Sliding Scale and Scenario have no subject at all; treating a
      // null as "you" would give both partners a judge step that should
      // not exist.
      expect(subjectOf(subjectId: null, userId: 'me'), isFalse);
    });
  });
}
