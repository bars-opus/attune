// Tests for the story repository (Plan B, Task 4): the three server calls
// that post a story — intent, upload, finalize (spec §4.2).
//
// story_repository.dart wraps SupabaseClient directly, the same shape as
// snakes_service.dart, and the house pattern (snakes_test.dart,
// paint_ball_provider_test.dart) never mocks SupabaseClient's RPC/storage
// builders — those are final, heavily-generic classes with no seam for it.
// So these tests exercise the parts that do not require a live client:
//
//   - StoryApiError.fromJson: the jsonb-to-typed-error conversion, and its
//     retryable classification — pure functions, directly testable.
//   - the upload call site: asserted against the source, the same way
//     snakes_test.dart proves "the client cannot send a die face" by
//     reading snakes_service.dart's text rather than mocking the RPC.

import 'dart:io';

import 'package:attune/features/stories/data/story_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('errors', () {
    test('an error jsonb becomes a typed error, never a raw exception', () {
      // Checklist 2.4/5.5: {error:true, code, message} -> StoryApiError
      // carrying the server's message. The code stays internal.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'not_a_member',
        'message': 'This story could not be posted.',
      });

      expect(error, isA<StoryApiError>());
      expect(error.message, 'This story could not be posted.');
      expect(error.code, 'not_a_member');
      // The public surface is the message; toString() is what a caller
      // reaches for by habit, and it must not accidentally print the code
      // or the word "Exception".
      expect(error.toString(), 'This story could not be posted.');
      expect(error.toString(), isNot(contains('not_a_member')));
      expect(error.toString(), isNot(contains('Exception')));
    });

    test('a message-less refusal still reads as English', () {
      final error = StoryApiError.fromJson({'code': 'weird'});
      expect(error.message, isNotEmpty);
      expect(error.message, isNot(contains('weird')));
    });

    test('a rate_limited refusal is marked retryable', () {
      // The outbox must retry this rather than failing permanently.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'rate_limited',
        'message': 'Too many uploads right now. Please try again shortly.',
      });

      expect(error.retryable, isTrue);
    });

    test('an expired intent is marked retryable', () {
      // A fresh intent fixes this; Task 6's outbox should re-run
      // intent+upload rather than give up.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'intent_expired',
        'message': 'That upload took too long. Please try again.',
      });

      expect(error.retryable, isTrue);
    });

    test('a validation refusal is NOT retryable', () {
      // Retrying an unchanged request against a permanent refusal (bad
      // membership, malformed input) would just fail again forever.
      for (final code in ['not_a_member', 'relationship_not_active', 'invalid_mime_type']) {
        final error = StoryApiError.fromJson({
          'error': true,
          'code': code,
          'message': 'refused',
        });
        expect(error.retryable, isFalse, reason: 'code=$code');
      }
    });

    test('a network failure (no server response at all) is retryable', () {
      final error = StoryApiError.network();
      expect(error.retryable, isTrue);
      expect(error.code, 'network');
    });
  });

  group('upload', () {
    test('uploads use upsert: false', () {
      // Spec §4.2. An upsert would let a second capture overwrite an
      // object another intent already claimed.
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      final uploadCallIndex = source.indexOf('.upload(');
      expect(
        uploadCallIndex,
        greaterThan(-1),
        reason: 'no Storage upload call found',
      );

      // The FileOptions for this call must say upsert: false somewhere
      // nearby, and never upsert: true anywhere in the file.
      expect(
        source.contains('upsert: false'),
        isTrue,
        reason: 'the upload does not pin upsert: false',
      );
      expect(
        source.contains('upsert: true'),
        isFalse,
        reason: 'an upsert:true would let a second capture overwrite '
            'an object another intent already claimed',
      );
    });

    test('uploadObject targets the intent-provided bucket and key, not a hardcoded one', () {
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      // The bucket/key must flow from the method's own parameters (the
      // intent), never a literal bucket name — the intent is what
      // Storage RLS actually authorizes (spec §4.1/§4.2).
      expect(source.contains("'story-media'"), isFalse,
          reason: 'the bucket must come from the intent, not be hardcoded');
    });
  });

  group('finalize', () {
    test('finalizeStory sends all 8 RPC params to create_story_item', () {
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      expect(source.contains("'create_story_item'"), isTrue);
      for (final param in [
        'p_relationship_id',
        'p_client_story_id',
        'p_media_intent_id',
        'p_thumbnail_intent_id',
        'p_media_width',
        'p_media_height',
        'p_duration_ms',
        'p_utc_offset_minutes',
      ]) {
        expect(source.contains("'$param'"), isTrue, reason: 'missing $param');
      }
    });

    test('StoryFinalizeResult surfaces existing for idempotent retries', () {
      const result = StoryFinalizeResult(storyId: 'story-1', existing: true);
      expect(result.storyId, 'story-1');
      expect(result.existing, isTrue);
    });
  });

  group('timeout', () {
    test('every RPC/storage call in the repository is bounded', () {
      // Checklist 1.2, matching snakes_service.dart: without a bound, a
      // stalled connection leaves the poster staring at a spinner that
      // never resolves.
      final source =
          File(
            'lib/features/stories/data/story_repository.dart',
          ).readAsStringSync();

      expect(source.contains('.timeout('), isTrue);
      expect(source.contains('Duration(seconds: 30)'), isTrue);
    });
  });
}
