import 'dart:io';

import 'package:attune/features/games/session_games/data/models/session_game_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('createSession — find-or-create (C1)', () {
    // No fake Supabase client exists in this suite (consistent with
    // every other test in test/features/games/), so this asserts
    // against the repository's real source, matching the pattern
    // session_game_flow_repository_test.dart already uses for
    // fetchRounds' select list. The regression this guards against is
    // concrete: without a lookup-before-insert, two partners opening
    // Mirror independently each create their own session, each with
    // exactly one writer, and both_answered can never flip on either
    // one — both partners wait forever. This is not a race; it is the
    // only possible outcome of two people playing.
    final source =
        File(
          'lib/features/games/session_games/data/repositories/session_game_repository.dart',
        ).readAsStringSync();
    final createSessionIndex = source.indexOf('Future<String> createSession(');
    final nextMethodIndex = source.indexOf(
      '\n  Future<',
      createSessionIndex + 1,
    );
    final methodBody =
        nextMethodIndex == -1
            ? source.substring(createSessionIndex)
            : source.substring(createSessionIndex, nextMethodIndex);

    test('createSession method exists', () {
      expect(
        createSessionIndex,
        isNot(-1),
        reason: 'createSession method not found',
      );
    });

    test('looks up an existing session before inserting one', () {
      // Must query game_sessions by relationship_id + game_type before
      // any insert into game_sessions appears in the method body.
      final selectIndex = methodBody.indexOf("from('game_sessions')");
      final insertIndex = methodBody.indexOf(".insert({");
      expect(
        selectIndex,
        isNot(-1),
        reason:
            'createSession must select from game_sessions to look '
            'for an existing session',
      );
      expect(
        insertIndex,
        isNot(-1),
        reason: 'createSession must still insert when none exists',
      );
      expect(
        selectIndex < insertIndex,
        isTrue,
        reason:
            'the existing-session lookup must happen before the '
            'insert, or every call still creates a fresh session',
      );
    });

    test('scopes the lookup to this relationship and game type', () {
      expect(methodBody, contains("eq('relationship_id', relationshipId)"));
      expect(methodBody, contains("eq('game_type', gameType)"));
    });

    test('only returns non-completed sessions, matching this_or_that', () {
      // Same shape as ThisOrThatRepository.createSession: a completed
      // session must never be handed back as "the" session to join,
      // or a finished game would look re-playable.
      expect(methodBody, contains("inFilter('status', ['invited', 'active'])"));
    });
  });

  group('SessionGameQuestion.fromRow', () {
    test('parses a sliding_scale row with its anchors', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q1',
        'game_type': 'sliding_scale',
        'question_text': 'How much of our money should be shared?',
        'value_domain': 'money',
        'scale_low': 'Kept separate',
        'scale_high': 'Fully shared',
      });
      expect(q.gameType, 'sliding_scale');
      expect(q.valueDomain, 'money');
      expect(q.scaleLow, 'Kept separate');
      expect(q.scaleHigh, 'Fully shared');
      expect(q.options, isEmpty);
    });

    test('parses a scenario row with its options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q2',
        'game_type': 'scenario',
        'question_text': 'You are both tired and a disagreement starts.',
        'options': [
          {'key': 'a', 'text': 'Push through'},
          {'key': 'b', 'text': 'Pause'},
          {'key': 'c', 'text': 'Step away'},
        ],
      });
      expect(q.options.length, 3);
      expect(q.options.first.key, 'a');
      expect(q.options.first.text, 'Push through');
    });

    test('parses a mirror row, which has neither anchors nor options', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q3',
        'game_type': 'mirror',
        'question_text': 'What is weighing on them most this week?',
      });
      expect(q.gameType, 'mirror');
      expect(q.options, isEmpty);
      expect(q.scaleLow, isNull);
    });

    test('malformed options degrade to empty rather than throwing', () {
      // The column is jsonb; a row written by hand or by a future
      // migration could hold a shape this parser does not expect. A
      // throw here would take down the whole question list.
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q4',
        'game_type': 'scenario',
        'question_text': 'Broken',
        'options': 'not-an-array',
      });
      expect(q.options, isEmpty);
    });

    test('an option missing its text is dropped, not rendered blank', () {
      final q = SessionGameQuestion.fromRow(const {
        'id': 'q5',
        'game_type': 'scenario',
        'question_text': 'Partial',
        'options': [
          {'key': 'a', 'text': 'Fine'},
          {'key': 'b'},
        ],
      });
      expect(q.options.length, 1);
      expect(q.options.first.key, 'a');
    });
  });
}
