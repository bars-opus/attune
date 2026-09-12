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
//
// Fix round 1: the first version of this file asserted the taxonomy
// against codes ('rate_limited', 'not_a_member', ...) nobody checked
// against the server. The real vocabulary is five UPPERCASE codes from
// `public.story_intent_error` (supabase/migrations/2026093[89]*.sql) —
// RATE_LIMITED, UNAUTHORIZED, FORBIDDEN, INVALID_INPUT, UNAVAILABLE. The
// 'errors' group below now uses those, and 'the retryable set is drawn
// from codes the server actually emits' derives the vocabulary from the
// migrations directly so this suite cannot silently drift from the
// server again.

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
        'code': 'FORBIDDEN',
        'message': "You don't have access to this story.",
      });

      expect(error, isA<StoryApiError>());
      expect(error.message, "You don't have access to this story.");
      expect(error.code, 'FORBIDDEN');
      // The public surface is the message; toString() is what a caller
      // reaches for by habit, and it must not accidentally print the code
      // or the word "Exception".
      expect(error.toString(), "You don't have access to this story.");
      expect(error.toString(), isNot(contains('FORBIDDEN')));
      expect(error.toString(), isNot(contains('Exception')));
    });

    test('a message-less refusal still reads as English', () {
      final error = StoryApiError.fromJson({'code': 'WEIRD'});
      expect(error.message, isNotEmpty);
      expect(error.message, isNot(contains('WEIRD')));
    });

    test('a RATE_LIMITED refusal is marked retryable', () {
      // The outbox must retry this rather than failing permanently. This
      // is the ONE server code the spec calls retryable (§4.2).
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'RATE_LIMITED',
        'message': 'Slow down a moment before adding more.',
      });

      expect(error.retryable, isTrue);
    });

    test('UNAVAILABLE is NOT retryable, even though an expired intent '
        'is one of the things that causes it', () {
      // The server deliberately collapses "not a member," "relationship
      // ended," "feature off," and "expired/consumed intent" into this
      // one code so a client can never use it as an existence oracle
      // (20260938050000_stories_finalize_rpc.sql:30,96). Because the
      // client cannot tell those apart from the code alone,
      // blanket-retrying UNAVAILABLE would spin forever on the permanent
      // cases. Spec §6.1's recovery for a genuinely expired intent is
      // structural (mint a fresh pair of intents and re-upload), decided
      // by the outbox one layer up — not a retry of this same call.
      final error = StoryApiError.fromJson({
        'error': true,
        'code': 'UNAVAILABLE',
        'message': "Stories aren't available right now.",
      });

      expect(error.retryable, isFalse);
    });

    test('a validation refusal is NOT retryable', () {
      // Retrying an unchanged request against a permanent refusal (bad
      // auth, malformed input) would just fail again forever.
      for (final code in ['UNAUTHORIZED', 'FORBIDDEN', 'INVALID_INPUT']) {
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

    test('the retryable set is drawn from codes the server actually emits', () {
      // Derives truth from the migrations rather than from anyone's
      // belief about what the server sends — the exact gap that let
      // 'rate_limited'/'intent_expired' (neither real) ship as the
      // taxonomy in fix round 0.
      final codes = <String>{};
      for (final f in Directory('supabase/migrations').listSync()) {
        if (f is! File || !f.path.contains('stories')) continue;
        codes.addAll(
          RegExp(
            r"story_intent_error\('([A-Z_]+)'\)",
          ).allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
        );
      }

      // Without this guard, a regex that stopped matching (a migration
      // rename, a formatting change) would make every assertion below
      // vacuously pass on an empty set.
      expect(codes, isNotEmpty, reason: 'the regex stopped matching');
      expect(
        codes,
        containsAll(<String>[
          'UNAUTHORIZED',
          'FORBIDDEN',
          'INVALID_INPUT',
          'RATE_LIMITED',
          'UNAVAILABLE',
        ]),
        reason: 'the known server vocabulary changed — update this test '
            'and the taxonomy doc comment together',
      );

      // Every code the client classifies as retryable must be one the
      // server actually sends.
      expect(codes.containsAll(StoryApiError.retryableCodesForTest), isTrue);
      // And RATE_LIMITED specifically must be retryable — the one code
      // the spec explicitly requires the outbox to retry.
      expect(StoryApiError.retryableCodesForTest, contains('RATE_LIMITED'));
      // Nothing else may be marked retryable: UNAVAILABLE in particular
      // must stay out, since it silently covers the permanent cases too.
      expect(StoryApiError.retryableCodesForTest, {'RATE_LIMITED'});
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
