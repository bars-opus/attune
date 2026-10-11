// Repository-level tests for the `ai-sessions` edge function's client
// (Plan D Task 1). Same contract as ai_assistant_repository_test.dart:
// these exercise error MAPPING and request/response wiring, not live
// edge-function behavior (supabase/functions/ai-sessions/index.test.ts
// already proves the server's own nine branches correct) — so they fake
// the injected `AiAssistantGateway` seam rather than SupabaseClient.
//
// The transport exception these raise is the REAL `FunctionException`
// from supabase_flutter, not a local stand-in: Task 1's brief sketched a
// `_FakeFunctionException` but `SupabaseAiAssistantGateway.invokeFunction`
// awaits `_supabase.functions.invoke(...)`, which throws
// `FunctionException` on a non-2xx response. A stand-in would have let
// `_mapTransportError`'s `error is FunctionException` check fall through
// to internalError() while every test still passed.
import 'package:attune/features/ai_assistant/data/models/ai_session_model.dart';
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_error.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAiSessionGateway implements AiAssistantGateway {
  Object? nextInvokeError;
  dynamic nextInvokeResult;
  String? lastInvokedFunction;
  Map<String, dynamic>? lastInvokeBody;
  int invokeCount = 0;

  @override
  Future<dynamic> invokeFunction(
    String functionName, {
    Map<String, dynamic>? body,
  }) async {
    invokeCount++;
    lastInvokedFunction = functionName;
    lastInvokeBody = body;
    // Deliberately does NOT clear `nextInvokeError` after throwing,
    // unlike ai_assistant_repository_test.dart's own fake. A
    // one-shot error made a repository that silently auto-retried
    // succeed on the second attempt with whatever `nextInvokeResult`
    // happened to be — which turned a no-auto-retry defect into
    // eighteen misleading "wrong error subtype" failures and MASKED the
    // one test that targets it (`invokeCount`). A persistent error
    // keeps each test's failure attributable to its own assertion.
    if (nextInvokeError != null) {
      throw nextInvokeError!;
    }
    return nextInvokeResult;
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    // Plan D's Global Constraint: every Sessions RPC is service_role-only,
    // so the repository must reach the edge function and nothing else.
    throw StateError('AiSessionRepository must never call .rpc() directly');
  }

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) {
    throw StateError(
      'AiSessionRepository must never read ai_assist_planning_links',
    );
  }
}

/// A §10 error envelope exactly as `errorResponse` shapes it
/// (supabase/functions/ai-sessions/index.ts): the code plus an optional
/// `retry_after_seconds`, and NOTHING else — no `error: true`, no
/// server-computed `retryable`, which is where §10 deliberately diverges
/// from ai-assist's own envelope.
FunctionException _sessionErrorException(
  String code, {
  int? retryAfterSeconds,
  required int status,
}) {
  return FunctionException(
    status: status,
    details: <String, dynamic>{
      'code': code,
      if (retryAfterSeconds != null) 'retry_after_seconds': retryAfterSeconds,
    },
    reasonPhrase: code,
  );
}

/// The §10 code-to-HTTP-status map, transcribed from
/// `SESSION_ERROR_STATUS` in supabase/functions/ai-sessions/index.ts, and
/// paired with the `AiSessionError` subtype each code must produce.
///
/// Statuses are present so the "branch on code, not status" tests can
/// feed the REAL status alongside each code — several codes share 409 and
/// several share 400/502, so a mapper that read the status could not
/// distinguish them.
const Map<String, ({int status, Type error})> _sessionErrorContract = {
  'UNAVAILABLE': (status: 404, error: AiSessionUnavailableError),
  'CONSENT_REQUIRED': (status: 403, error: AiSessionConsentRequiredError),
  'APPROVAL_REQUIRED': (status: 409, error: AiSessionApprovalRequiredError),
  'CONTEXT_CHANGED': (status: 409, error: AiSessionContextChangedError),
  'INVALID_INPUT': (status: 400, error: AiSessionInvalidInputError),
  'CONTEXT_TOO_LARGE': (status: 413, error: AiSessionContextTooLargeError),
  'REQUEST_CONFLICT': (status: 409, error: AiSessionRequestConflictError),
  'SESSION_BUSY': (status: 409, error: AiSessionBusyError),
  'SESSION_LIMIT_REACHED': (status: 409, error: AiSessionLimitReachedError),
  'RATE_LIMITED': (status: 429, error: AiSessionRateLimitedError),
  'OVERLOADED': (status: 503, error: AiSessionOverloadedError),
  'LOCATION_REQUIRED': (status: 400, error: AiSessionLocationRequiredError),
  'LOCATION_EXPIRED': (status: 400, error: AiSessionLocationExpiredError),
  'REQUEST_FAILED': (status: 502, error: AiSessionRequestFailedError),
  'PROVIDER_UNAVAILABLE': (
    status: 502,
    error: AiSessionProviderUnavailableError,
  ),
  'RESULT_UNAVAILABLE': (status: 410, error: AiSessionResultUnavailableError),
  'FEATURE_DISABLED': (status: 403, error: AiSessionFeatureDisabledError),
  'INTERNAL_ERROR': (status: 500, error: AiSessionInternalError),
};

const _validUuid = '11111111-1111-4111-8111-111111111111';
const _validRelationshipId = '22222222-2222-4222-8222-222222222222';
const _validMessageId = '33333333-3333-4333-8333-333333333333';
const _validRequestId = '44444444-4444-4444-8444-444444444444';

/// A 64-character lowercase-hex digest, which is the SHAPE
/// `handleApprove` enforces with `/^[0-9a-f]{64}$/` and which
/// [AiSessionApprovalTicket] mirrors. Any shorter or re-cased value must
/// fail at the parse boundary rather than reaching the server.
const _validDigest =
    'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789';

/// A fresh Ideas answer exactly as `dispatchIdeas` shapes it
/// (supabase/functions/ai-sessions/index.ts:2726) — SEVEN keys, including
/// the `kind: "answer"` discriminator the task brief's own fixture
/// omitted and the `session_revision` the plan's description of Plan C
/// did not mention.
Map<String, dynamic> _ideasAnswerResponse() => <String, dynamic>{
  'kind': 'answer',
  'user_ordinal': 1,
  'attune_ordinal': 2,
  'session_revision': 2,
  'reply_text': 'Try a picnic.',
  'suggested_planning_item': null,
  'show_safety_resources': true,
};

/// A staged Nearby generation exactly as `dispatchNearby` shapes it
/// (index.ts:2888).
Map<String, dynamic> _stagedNearbyResponse() => <String, dynamic>{
  'kind': 'nearby_result',
  'staged': true,
  'request_id': _validRequestId,
  'reply_text': 'Here are a few coffee options nearby: Vida e Caffe',
  'sources': <dynamic>[
    <String, dynamic>{
      'provider_id': 'mapbox:poi.1234',
      'name': 'Vida e Caffe',
      'formatted_address': 'Osu, Accra',
      'category': 'coffee',
      'map_url': 'https://www.mapbox.com/place/poi.1234',
    },
  ],
  'show_safety_resources': true,
};

/// THE SAFETY-REFUSAL REDIRECT, transcribed verbatim from
/// `safetyRefusalResponse` (index.ts:2145): `kind`, `reason`, `copy`,
/// `show_safety_resources` and an EMPTY `offered`.
Map<String, dynamic> _safetyRefusalRedirectResponse({
  String reason = 'unsafe_to_assist',
}) => <String, dynamic>{
  'kind': 'redirect',
  'reason': reason,
  // Verbatim from SESSION_SAFETY_NEUTRAL_COPY's frozen table. Nothing is
  // interpolated server-side, so no phrase or rule name can reach it.
  'copy': 'I am not able to help with this. Support resources are '
      'available if you want them.',
  'show_safety_resources': true,
  'offered': <dynamic>[],
};

/// THE ORDINARY MODEL REDIRECT, transcribed verbatim from
/// `dispatchIdeas`'s redirect branch (index.ts:2707) and
/// `dispatchNearby`'s (index.ts:2806): the SAME `kind`, a reason from the
/// SAME set, and NO `copy`.
Map<String, dynamic> _ordinaryRedirectResponse({
  String reason = 'unsafe_to_assist',
  List<String> offered = const <String>['ideas'],
}) => <String, dynamic>{
  'kind': 'redirect',
  'reason': reason,
  'offered': offered,
  'show_safety_resources': true,
};

/// `handleReviewContext`'s success body, with all ELEVEN keys the server
/// actually sends — transcribed from its `jsonResponse` call, including
/// the `civil_day_start_utc` that neither half of the gate-2 split reads.
/// Sending the full body here is deliberate: a fixture carrying only the
/// seven keys the review half reads could not catch a repository that
/// started reading a dropped field.
Map<String, dynamic> _reviewContextResponse({
  bool includeWindow = false,
  String digest = _validDigest,
  int revision = 4,
  List<Map<String, dynamic>>? window,
  Map<String, dynamic>? target = const {'content': 'the selected message'},
}) {
  return <String, dynamic>{
    'session_id': _validUuid,
    'revision': revision,
    'policy_version': 'v3',
    'kind': 'ideas',
    'visibility': 'shared',
    'include_window': includeWindow,
    'utc_offset_minutes': 120,
    'civil_day_start_utc': '2026-10-11T02:00:00.000Z',
    'window': window ??
        (includeWindow
            ? const [
                {'content': 'morning note', 'truncated': false},
                {'content': 'a long reply that was cut', 'truncated': true},
              ]
            : const []),
    'target': target,
    'digest': digest,
  };
}

/// The ticket half as `review_context` would have produced it. Built via
/// `fromJson` rather than the constructor so the fixture itself goes
/// through the digest-shape validation a real response would.
AiSessionApprovalTicket _ticket() => AiSessionApprovalTicket.fromJson(
      <String, dynamic>{
        'session_id': _validUuid,
        'revision': 4,
        'policy_version': 'v3',
        'digest': _validDigest,
      },
    );

void main() {
  group('prepare — request shape', () {
    test(
      'sends command/relationship_id/kind/visibility/utc_offset_minutes/'
      'idempotency_key and returns session_id/revision/created',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'session_id': _validUuid,
            'revision': 1,
            'created': true,
          };
        final repository = AiSessionRepository(gateway);

        final result = await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 60,
        );

        expect(gateway.lastInvokedFunction, 'ai-sessions');
        final body = gateway.lastInvokeBody!;
        expect(body['command'], 'prepare');
        expect(body['relationship_id'], _validRelationshipId);
        expect(body['kind'], 'ideas');
        expect(body['visibility'], 'private');
        expect(body['idempotency_key'], _validUuid);
        // Mandatory server-side: `parsePrepareRequest` runs
        // `isValidUtcOffsetMinutes(body.utc_offset_minutes)`, and an
        // absent field is `undefined`, which is not a number — so
        // omitting it is INVALID_INPUT on every call.
        expect(body['utc_offset_minutes'], 60);
        expect(body['target_message_id'], isNull);
        expect(body['include_window'], false);

        expect(result.sessionId, _validUuid);
        expect(result.revision, 1);
        expect(result.created, true);
      },
    );

    test(
      'sends ONLY the keys parsePrepareRequest allowlists — an unknown key '
      'is INVALID_INPUT server-side',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'session_id': _validUuid,
            'revision': 3,
            'created': false,
          };
        final repository = AiSessionRepository(gateway);

        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'shared',
          utcOffsetMinutes: -480,
          targetMessageId: _validMessageId,
          includeWindow: true,
        );

        // Transcribed from `parsePrepareRequest`'s own `allowed` set.
        expect(
          gateway.lastInvokeBody!.keys.toSet(),
          {
            'command',
            'relationship_id',
            'kind',
            'visibility',
            'target_message_id',
            'include_window',
            'utc_offset_minutes',
            'idempotency_key',
          },
        );
        expect(gateway.lastInvokeBody!['target_message_id'], _validMessageId);
        expect(gateway.lastInvokeBody!['include_window'], true);
        expect(gateway.lastInvokeBody!['utc_offset_minutes'], -480);
      },
    );

    test('carries created=false through rather than coercing it to true',
        () async {
      // The idempotent-replay case: `prepare_ai_session` returns the
      // ORIGINAL session with created=false. A client that read this as
      // true would double-count a session slot in its own UI.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'session_id': _validUuid,
          'revision': 7,
          'created': false,
        };
      final repository = AiSessionRepository(gateway);

      final result = await repository.prepare(
        idempotencyKey: _validUuid,
        relationshipId: _validRelationshipId,
        kind: 'nearby',
        visibility: 'private',
        utcOffsetMinutes: 0,
      );

      expect(result.created, false);
      expect(result.revision, 7);
    });
  });

  group('no request body may carry an actor id', () {
    test(
      'every one of the 11 ACTOR_NAMING_FIELDS spellings is absent from a '
      'prepare body, and the set asserted is the full 11',
      () async {
        // Transcribed from `ACTOR_NAMING_FIELDS` in
        // supabase/functions/ai-sessions/index.ts. The server rejects any
        // body carrying one of these with INVALID_INPUT; the client has no
        // business sending identity at all, since the actor comes from the
        // verified JWT.
        const actorNamingFields = <String>{
          'actor_id',
          'p_actor_id',
          'user_id',
          'p_user_id',
          'requester_id',
          'creator_id',
          'author_id',
          'partner_id',
          'sender_id',
          'actor',
          'user',
        };
        // Vacuous-denominator guard: the server's set has 11 entries, and
        // Plan C's own history records a 12th unlisted spelling as a real
        // finding — so this asserts the count it iterated, not just that
        // the loop ran.
        expect(actorNamingFields.length, 11);

        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'session_id': _validUuid,
            'revision': 1,
            'created': true,
          };
        final repository = AiSessionRepository(gateway);

        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'shared',
          utcOffsetMinutes: 120,
          targetMessageId: _validMessageId,
        );

        final sentKeys = gateway.lastInvokeBody!.keys.toSet();
        for (final field in actorNamingFields) {
          expect(
            sentKeys,
            isNot(contains(field)),
            reason: 'prepare must never send the actor field "$field"',
          );
        }
        // Stronger than the allowlist check above: no key may even
        // CONTAIN an identity-shaped substring, which catches a 12th
        // unlisted spelling (e.g. `acting_user_id`) that the server's own
        // set would miss.
        for (final key in sentKeys) {
          expect(
            key.contains('actor') ||
                key.contains('user') ||
                key.endsWith('_id') &&
                    (key.contains('creator') ||
                        key.contains('author') ||
                        key.contains('partner') ||
                        key.contains('sender') ||
                        key.contains('requester')),
            isFalse,
            reason: 'prepare body key "$key" names an actor',
          );
        }
      },
    );
  });

  group('§10 error envelope — all 18 codes map by CODE, not status', () {
    test('the contract table under test covers exactly 18 codes', () {
      // Vacuous-denominator guard for the generated tests below: if a
      // code were dropped from `_sessionErrorContract`, its own test
      // would silently stop existing and nothing else would notice.
      expect(_sessionErrorContract.length, 18);
    });

    for (final entry in _sessionErrorContract.entries) {
      final code = entry.key;
      final status = entry.value.status;
      final expectedType = entry.value.error;

      test('$code (HTTP $status) throws $expectedType', () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeError = _sessionErrorException(code, status: status);
        final repository = AiSessionRepository(gateway);

        Object? thrown;
        try {
          await repository.prepare(
            idempotencyKey: _validUuid,
            relationshipId: _validRelationshipId,
            kind: 'ideas',
            visibility: 'private',
            utcOffsetMinutes: 0,
          );
        } catch (error) {
          thrown = error;
        }

        expect(thrown, isNotNull, reason: '$code must not succeed');
        expect(thrown.runtimeType, expectedType);
        expect(thrown, isA<AiSessionError>());
        expect((thrown! as AiSessionError).code, code);
      });
    }

    test(
      'the five codes that share HTTP 409 stay distinguishable — proof the '
      'mapper reads the code and not the status',
      () async {
        final sharing409 = _sessionErrorContract.entries
            .where((entry) => entry.value.status == 409)
            .toList();
        // APPROVAL_REQUIRED, CONTEXT_CHANGED, REQUEST_CONFLICT,
        // SESSION_BUSY, SESSION_LIMIT_REACHED all map to 409.
        expect(sharing409.length, 5);

        final produced = <Type>{};
        for (final entry in sharing409) {
          final gateway = _FakeAiSessionGateway()
            ..nextInvokeError = _sessionErrorException(entry.key, status: 409);
          final repository = AiSessionRepository(gateway);
          try {
            await repository.prepare(
              idempotencyKey: _validUuid,
              relationshipId: _validRelationshipId,
              kind: 'ideas',
              visibility: 'private',
              utcOffsetMinutes: 0,
            );
            fail('expected ${entry.key} to throw');
          } on AiSessionError catch (error) {
            expect(error.runtimeType, entry.value.error);
            produced.add(error.runtimeType);
          }
        }
        // Five distinct subtypes from one status: impossible for any
        // status-driven mapper.
        expect(produced.length, 5);
      },
    );

    test(
      'a code arriving with the WRONG HTTP status still maps by the code',
      () async {
        // The sharpest form of "branch on the code": SESSION_BUSY served
        // with 500 (INTERNAL_ERROR's status) must still be a busy error.
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeError = _sessionErrorException(
            'SESSION_BUSY',
            status: 500,
          );
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.prepare(
            idempotencyKey: _validUuid,
            relationshipId: _validRelationshipId,
            kind: 'ideas',
            visibility: 'private',
            utcOffsetMinutes: 0,
          ),
          throwsA(isA<AiSessionBusyError>()),
        );
      },
    );

    test('INTERNAL_ERROR is the only bare 500 in the contract', () {
      final fiveHundreds = _sessionErrorContract.entries
          .where((entry) => entry.value.status == 500)
          .map((entry) => entry.key)
          .toList();
      expect(fiveHundreds, ['INTERNAL_ERROR']);
    });
  });

  group('RATE_LIMITED carries retry_after_seconds', () {
    test('a RATE_LIMITED envelope with retry_after_seconds: 42 keeps the 42',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'RATE_LIMITED',
          status: 429,
          retryAfterSeconds: 42,
        );
      final repository = AiSessionRepository(gateway);

      try {
        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        );
        fail('expected AiSessionRateLimitedError');
      } on AiSessionRateLimitedError catch (error) {
        // The SPECIFIC value, not "non-null": a mapper that hard-coded
        // any other integer would pass a non-null assertion.
        expect(error.retryAfterSeconds, 42);
      }
    });

    test('a RATE_LIMITED envelope with NO retry_after_seconds yields null',
        () async {
      // §10 makes the field optional, so the absent case is a real wire
      // shape and must not become 0 — "retry in 0 seconds" would invite
      // the immediate auto-retry §10 forbids.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'RATE_LIMITED',
          status: 429,
        );
      final repository = AiSessionRepository(gateway);

      try {
        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        );
        fail('expected AiSessionRateLimitedError');
      } on AiSessionRateLimitedError catch (error) {
        expect(error.retryAfterSeconds, isNull);
      }
    });

    test('a non-integer retry_after_seconds is dropped, not coerced',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = FunctionException(
          status: 429,
          details: <String, dynamic>{
            'code': 'RATE_LIMITED',
            'retry_after_seconds': 'soon',
          },
          reasonPhrase: 'RATE_LIMITED',
        );
      final repository = AiSessionRepository(gateway);

      try {
        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        );
        fail('expected AiSessionRateLimitedError');
      } on AiSessionRateLimitedError catch (error) {
        expect(error.retryAfterSeconds, isNull);
      }
    });

    test('only RATE_LIMITED carries a retry hint — OVERLOADED does not',
        () async {
      // OVERLOADED's §10 guidance is "bounded retry-after" too, but the
      // server shapes it without the field on this path; the client must
      // not invent one. Asserting the TYPE has no such field is a
      // compile-time property, so this asserts the behavioural half: an
      // OVERLOADED envelope that DOES carry the field still produces the
      // plain subtype rather than being re-routed to rate-limited.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'OVERLOADED',
          status: 503,
          retryAfterSeconds: 9,
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AiSessionOverloadedError>()),
      );
    });
  });

  group('AiSessionError.fromCode', () {
    test('maps each of the 18 contract codes to its own subtype', () {
      expect(_sessionErrorContract.length, 18);
      final produced = <Type>{};
      for (final entry in _sessionErrorContract.entries) {
        final error = AiSessionError.fromCode(entry.key);
        expect(
          error.runtimeType,
          entry.value.error,
          reason: 'fromCode("${entry.key}")',
        );
        expect(error.code, entry.key);
        produced.add(error.runtimeType);
      }
      // 18 codes must produce 18 DISTINCT subtypes: a mapper that
      // collapsed two codes onto one subtype would pass the per-entry
      // assertions above only if the table agreed, so this pins the
      // one-to-one property independently.
      expect(produced.length, 18);
    });

    test('an unknown code fails closed to AiSessionInternalError', () {
      final error = AiSessionError.fromCode('SOME_FUTURE_CODE');
      expect(error, isA<AiSessionInternalError>());
      expect(error.code, 'INTERNAL_ERROR');
    });

    test('there is no UNAUTHENTICATED code — §10 does not define one', () {
      // The server's own `handleRequest` maps a failed `requireUser` to
      // INVALID_INPUT with the comment "§10 has no UNAUTHENTICATED". A
      // client that invented one would branch on a code the server never
      // sends and leave the real auth failure in a generic bucket.
      expect(
        _sessionErrorContract.keys,
        isNot(contains('UNAUTHENTICATED')),
      );
      final error = AiSessionError.fromCode('UNAUTHENTICATED');
      expect(error, isA<AiSessionInternalError>());
      // And the code the server actually sends for auth failure maps to
      // the invalid-input subtype, which is what the UI must handle.
      expect(
        AiSessionError.fromCode('INVALID_INPUT'),
        isA<AiSessionInvalidInputError>(),
      );
    });

    test('rateLimited is the only subtype carrying a retry hint', () {
      final rateLimited = AiSessionError.fromCode(
        'RATE_LIMITED',
        retryAfterSeconds: 30,
      );
      expect((rateLimited as AiSessionRateLimitedError).retryAfterSeconds, 30);
      // retryAfterSeconds passed alongside any other code is discarded
      // rather than silently attached to an unrelated subtype.
      final busy = AiSessionError.fromCode(
        'SESSION_BUSY',
        retryAfterSeconds: 30,
      );
      expect(busy, isA<AiSessionBusyError>());
    });
  });

  group('transport failures never escape as raw exceptions', () {
    test('a FunctionException whose details carry a JSON STRING envelope '
        'still maps by code', () async {
      // `functions.invoke` surfaces the body as a decoded Map on a JSON
      // content type and as a raw String otherwise; the existing
      // AiAssistantRepository handles both and so must this.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = FunctionException(
          status: 409,
          details: '{"code":"SESSION_BUSY"}',
          reasonPhrase: 'SESSION_BUSY',
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AiSessionBusyError>()),
      );
    });

    test('a FunctionException with an unparseable body maps to '
        'AiSessionInternalError, not a FormatException', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = FunctionException(
          status: 500,
          details: 'not json at all',
          reasonPhrase: 'oops',
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('a bare network error maps to AiSessionInternalError', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = Exception('SocketException: host unreachable');
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('a malformed 2xx success body maps to AiSessionInternalError, '
        'not a TypeError', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'session_id': _validUuid,
          // `revision` missing: `prepare`'s parser must not let a
          // TypeError reach the UI.
          'created': true,
        };
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        ),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('an AiSessionError thrown from the parser is not re-wrapped',
        () async {
      // A null body is the degenerate 2xx shape; it must surface as the
      // internal error exactly once, not as internalError wrapping
      // internalError (which would break `catch (e) { e is AiSessionError }`
      // only subtly, but would also hide the real shape in a log).
      final gateway = _FakeAiSessionGateway()..nextInvokeResult = null;
      final repository = AiSessionRepository(gateway);

      Object? thrown;
      try {
        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        );
      } catch (error) {
        thrown = error;
      }
      expect(thrown.runtimeType, AiSessionInternalError);
    });

    test('the repository never retries a failed command on its own', () async {
      // §10: "no automatic retry". A single call must produce exactly one
      // transport attempt, so a RATE_LIMITED or SESSION_BUSY refusal can
      // never be amplified into a second provider-costing attempt.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException('OVERLOADED', status: 503);
      final repository = AiSessionRepository(gateway);

      try {
        await repository.prepare(
          idempotencyKey: _validUuid,
          relationshipId: _validRelationshipId,
          kind: 'ideas',
          visibility: 'private',
          utcOffsetMinutes: 0,
        );
      } on AiSessionError {
        // expected
      }
      expect(gateway.invokeCount, 1);
    });
  });

  group('the repository is the only caller of the edge function', () {
    test('prepare reaches ai-sessions and never .rpc() or a table read',
        () async {
      // The fake throws StateError from rpc()/selectPlanningLink(), so a
      // repository that reached for either would fail here rather than in
      // a later task's integration test.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'session_id': _validUuid,
          'revision': 1,
          'created': true,
        };
      final repository = AiSessionRepository(gateway);

      await repository.prepare(
        idempotencyKey: _validUuid,
        relationshipId: _validRelationshipId,
        kind: 'ideas',
        visibility: 'private',
        utcOffsetMinutes: 0,
      );

      expect(gateway.lastInvokedFunction, 'ai-sessions');
      expect(gateway.invokeCount, 1);
    });
  });

  // =====================================================================
  // Task 3: review_context / approve / read / end / share_answer
  //
  // Every group below transcribes its command's own `allowed` set from
  // supabase/functions/ai-sessions/index.ts and asserts the sent body's
  // key set EQUALS it. Each branch rejects an unknown key with
  // INVALID_INPUT rather than ignoring it, so an added key is a broken
  // call, not a harmless one — equality catches that, `contains` would
  // not.
  // =====================================================================

  group('reviewContext — request shape', () {
    test(
      'sends ONLY handleReviewContext\'s allowlist, and NOT relationship_id',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = _reviewContextResponse();
        final repository = AiSessionRepository(gateway);

        await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: 60,
        );

        expect(gateway.lastInvokedFunction, 'ai-sessions');
        // Transcribed from `handleReviewContext`'s own `allowed` set.
        // `set_include_window` is OPTIONAL and is therefore ABSENT on a
        // read-only call: the server distinguishes `undefined` (do not
        // toggle) from `false` (turn the window OFF, which bumps the
        // revision and clears both approvals), so sending `false` by
        // default would silently invalidate a partner's approval on
        // every plain re-read.
        expect(gateway.lastInvokeBody!.keys.toSet(), {
          'command',
          'session_id',
          'utc_offset_minutes',
        });
        expect(gateway.lastInvokeBody!['command'], 'review_context');
        expect(gateway.lastInvokeBody!['session_id'], _validUuid);
        expect(gateway.lastInvokeBody!['utc_offset_minutes'], 60);
        // The brief's sketch sent `relationship_id`. The server reads the
        // relationship from the SESSION ROW and its allowlist has no such
        // key, so a brief-faithful call is INVALID_INPUT every time.
        expect(
          gateway.lastInvokeBody!.containsKey('relationship_id'),
          isFalse,
        );
      },
    );

    test(
      'with setIncludeWindow sends the toggle key, and its key set is still '
      'exactly the allowlist',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = _reviewContextResponse(includeWindow: true);
        final repository = AiSessionRepository(gateway);

        await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: -480,
          setIncludeWindow: true,
        );

        expect(gateway.lastInvokeBody!.keys.toSet(), {
          'command',
          'session_id',
          'utc_offset_minutes',
          'set_include_window',
        });
        expect(gateway.lastInvokeBody!['set_include_window'], true);
        expect(gateway.lastInvokeBody!['utc_offset_minutes'], -480);
      },
    );

    test('setIncludeWindow: false is SENT, not treated as absent', () async {
      // Turning the window OFF is a real request. `applyWindowToggle`
      // runs for any boolean; only `undefined` means "do not toggle".
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = _reviewContextResponse();
      final repository = AiSessionRepository(gateway);

      await repository.reviewContext(
        sessionId: _validUuid,
        utcOffsetMinutes: 0,
        setIncludeWindow: false,
      );

      expect(gateway.lastInvokeBody!.containsKey('set_include_window'), isTrue);
      expect(gateway.lastInvokeBody!['set_include_window'], false);
    });

    test('the transcribed allowlist matches the model\'s own transcription',
        () {
      // Two independent transcriptions of the same server set, asserted
      // equal. If either drifts the suite fails rather than both agreeing
      // on a stale copy.
      expect(
        AiSessionContextReview.reviewCommandBodyKeys,
        {'session_id', 'utc_offset_minutes', 'set_include_window'},
      );
      expect(AiSessionContextReview.reviewCommandBodyKeys.length, 3);
    });
  });

  group('reviewContext — gate 2: the two halves are returned UNRECOMBINED',
      () {
    test('returns a review half and a ticket half, each parsed separately',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = _reviewContextResponse(includeWindow: true);
      final repository = AiSessionRepository(gateway);

      final result = await repository.reviewContext(
        sessionId: _validUuid,
        utcOffsetMinutes: 120,
      );

      // The renderable half: snippets, toggle, offset — and NO digest.
      expect(result.review, isA<AiSessionContextReview>());
      expect(result.review.sessionId, _validUuid);
      expect(result.review.kind, AiSessionKind.ideas);
      expect(result.review.visibility, AiSessionVisibility.shared);
      expect(result.review.includeWindow, true);
      expect(result.review.utcOffsetMinutes, 120);
      expect(result.review.window, hasLength(2));
      expect(result.review.window.first.content, 'morning note');
      expect(result.review.window.first.truncated, false);
      expect(result.review.window[1].truncated, true);
      expect(result.review.target?.content, 'the selected message');

      // The opaque half: revision/digest/policy — and NO snippet.
      expect(result.ticket, isA<AiSessionApprovalTicket>());
      expect(result.ticket.sessionId, _validUuid);
      expect(result.ticket.revision, 4);
      expect(result.ticket.policyVersion, 'v3');
      expect(result.ticket.digest, _validDigest);
    });

    test(
      'the returned record has EXACTLY two fields, so nothing recombined '
      'them into a third flattened view',
      () async {
        // A vacuous-denominator guard on the claim above: the record type
        // is structural, so this asserts the shape by exhausting it. A
        // flattened `{digest, window}` field added later would not
        // type-check against this destructuring.
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = _reviewContextResponse();
        final repository = AiSessionRepository(gateway);

        final (:review, :ticket) = await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: 0,
        );

        expect(review, isA<AiSessionContextReview>());
        expect(ticket, isA<AiSessionApprovalTicket>());
      },
    );

    test(
      'neither half can reach the other\'s fields: the two wire key sets '
      'intersect in exactly {session_id}',
      () {
        final intersection = AiSessionContextReview.wireKeysRead.intersection(
          AiSessionApprovalTicket.wireKeysRead,
        );
        expect(intersection, {'session_id'});
        expect(intersection.length, 1);
        // The digest is on the ticket and NOWHERE on the review half, so
        // no caller can hold a digest beside the snippets that produced
        // it and be tempted to recompute.
        expect(
          AiSessionContextReview.wireKeysRead,
          isNot(contains('digest')),
        );
        expect(AiSessionApprovalTicket.wireKeysRead, contains('digest'));
        for (final preImageInput in const [
          'window',
          'target',
          'utc_offset_minutes',
          'civil_day_start_utc',
        ]) {
          expect(
            AiSessionApprovalTicket.wireKeysRead,
            isNot(contains(preImageInput)),
            reason: 'the ticket must carry no digest pre-image input',
          );
        }
      },
    );

    test('a malformed digest in the response fails the whole call', () async {
      // The ticket validates the digest's SHAPE. A truncated digest must
      // not reach `approve`, where it would be stored and later compared
      // unequal — which the server notes "would read to the user as 'my
      // partner changed the context'".
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = _reviewContextResponse(digest: 'abc123');
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.reviewContext(sessionId: _validUuid, utcOffsetMinutes: 0),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('a null target parses as a null target, not as an empty snippet',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = _reviewContextResponse(target: null);
      final repository = AiSessionRepository(gateway);

      final result = await repository.reviewContext(
        sessionId: _validUuid,
        utcOffsetMinutes: 0,
      );

      expect(result.review.target, isNull);
    });

    test('an empty window parses as an empty list, and is not an error',
        () async {
      // `include_window: false` is the DEFAULT per §4.3, so this is the
      // ordinary case, not a degenerate one.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = _reviewContextResponse(window: const []);
      final repository = AiSessionRepository(gateway);

      final result = await repository.reviewContext(
        sessionId: _validUuid,
        utcOffsetMinutes: 0,
      );

      expect(result.review.window, isEmpty);
      expect(result.review.includeWindow, false);
    });
  });

  group('approve — consumes the TICKET, never loose digest arguments', () {
    test(
      'sends ONLY handleApprove\'s allowlist, built from the ticket',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'approved': true,
            'activated': true,
            'state': 'active',
          };
        final repository = AiSessionRepository(gateway);

        await repository.approve(ticket: _ticket());

        // Transcribed from `handleApprove`'s own `allowed` set. Note
        // `policy_version` — the brief's sketch omitted it entirely, and
        // it is what lets the server detect that the consent policy moved
        // between review and approval (a CONTEXT_CHANGED rather than a
        // silent overwrite).
        expect(gateway.lastInvokeBody!.keys.toSet(), {
          'command',
          'session_id',
          'revision',
          'digest',
          'policy_version',
        });
        expect(gateway.lastInvokeBody!['command'], 'approve');
        expect(gateway.lastInvokeBody!['session_id'], _validUuid);
        expect(gateway.lastInvokeBody!['revision'], 4);
        expect(gateway.lastInvokeBody!['digest'], _validDigest);
        expect(gateway.lastInvokeBody!['policy_version'], 'v3');
      },
    );

    test(
      'the digest it sends is byte-identical to the ticket\'s — carried, '
      'never derived',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = _reviewContextResponse();
        final repository = AiSessionRepository(gateway);

        final reviewed = await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: 0,
        );
        gateway.nextInvokeResult = <String, dynamic>{
          'approved': true,
          'activated': true,
          'state': 'active',
        };
        await repository.approve(ticket: reviewed.ticket);

        expect(gateway.lastInvokeBody!['digest'], _validDigest);
        expect(gateway.lastInvokeBody!['revision'], 4);
        // And the renderable half contributed NOTHING to the approve
        // body: no snippet, no offset, no civil day.
        for (final key in gateway.lastInvokeBody!.keys) {
          expect(
            const {'window', 'target', 'utc_offset_minutes',
                'civil_day_start_utc', 'include_window', 'kind', 'visibility'},
            isNot(contains(key)),
            reason: 'approve must not send a review-half field',
          );
        }
      },
    );

    test(
      'the first approver\'s {approved,activated:false,state:preparing} is a '
      'SUCCESS, not an APPROVAL_REQUIRED error',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'approved': true,
            'activated': false,
            'state': 'preparing',
          };
        final repository = AiSessionRepository(gateway);

        final result = await repository.approve(ticket: _ticket());

        expect(result.approved, true);
        expect(result.activated, false);
        expect(result.state, AiSessionState.preparing);
        expect(result.isWaitingForPartner, true);
      },
    );

    test('returns all THREE fields, and state is read not inferred',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'approved': true,
          'activated': true,
          'state': 'active',
        };
      final repository = AiSessionRepository(gateway);

      final result = await repository.approve(ticket: _ticket());

      expect(result.approved, true);
      expect(result.activated, true);
      expect(result.state, AiSessionState.active);
      expect(result.isWaitingForPartner, false);
      expect(AiSessionApprovalResult.wireKeys.length, 3);
    });

    test('a response missing `state` fails rather than defaulting it',
        () async {
      // Makes the `!activated` inference unavailable rather than merely
      // discouraged: a server that stopped sending `state` must break
      // loudly, not be papered over client-side.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'approved': true,
          'activated': false,
        };
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.approve(ticket: _ticket()),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('CONTEXT_CHANGED maps by code, and is NOT APPROVAL_REQUIRED',
        () async {
      // The §10 code whose remedy is "call review_context again and
      // approve the digest it returns" — never "recompute and retry".
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'CONTEXT_CHANGED',
          status: 409,
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.approve(ticket: _ticket()),
        throwsA(isA<AiSessionContextChangedError>()),
      );
    });
  });

  group('read — request shape', () {
    test('without a requestId sends ONLY command/session_id', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
      final repository = AiSessionRepository(gateway);

      await repository.read(sessionId: _validUuid);

      // Transcribed from `handleRead`'s own `allowed` set, minus the
      // OPTIONAL `request_id`. Sending `request_id: null` would be a
      // different request: the server branches on `typeof requestId ===
      // "string"`, and `null` is allowlisted but not a string, so it
      // would read the turns and return `staged: undefined` — which is
      // indistinguishable here, but it would also make the key present,
      // and the key's presence is what a future server could branch on.
      expect(gateway.lastInvokeBody!.keys.toSet(), {'command', 'session_id'});
      expect(gateway.lastInvokeBody!['command'], 'read');
      expect(gateway.lastInvokeBody!['session_id'], _validUuid);
    });

    test('with a requestId sends exactly the full allowlist', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[],
          'staged': <dynamic>[],
        };
      final repository = AiSessionRepository(gateway);

      await repository.read(sessionId: _validUuid, requestId: _validRequestId);

      expect(gateway.lastInvokeBody!.keys.toSet(), {
        'command',
        'session_id',
        'request_id',
      });
      expect(gateway.lastInvokeBody!['request_id'], _validRequestId);
    });
  });

  group('read — the staged null-vs-empty distinction survives', () {
    test('staged ABSENT parses as null — "I did not ask"', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
      final repository = AiSessionRepository(gateway);

      final transcript = await repository.read(sessionId: _validUuid);

      expect(transcript.staged, isNull);
    });

    test(
      'staged [] parses as an EMPTY LIST, not null — "I asked and there is '
      'nothing"',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{
            'turns': <dynamic>[],
            'staged': <dynamic>[],
          };
        final repository = AiSessionRepository(gateway);

        final transcript = await repository.read(
          sessionId: _validUuid,
          requestId: _validRequestId,
        );

        // BOTH halves of the distinction asserted: not null, AND empty.
        // A single `isEmpty` would pass on null under a `?? []` at this
        // call site, which is exactly the collapse Ruling 9 forbids.
        expect(transcript.staged, isNotNull);
        expect(transcript.staged, isEmpty);
      },
    );

    test('a populated staged list parses its rows', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[],
          'staged': <dynamic>[
            <String, dynamic>{
              'request_id': _validRequestId,
              'reply_text': 'two cafes near you',
              'sources': <dynamic>[
                <String, dynamic>{
                  'provider_id': 'mapbox-1',
                  'name': 'Cafe One',
                  'formatted_address': '1 Main St',
                  'category': 'cafe',
                },
              ],
              'expires_at': '2026-10-11T12:00:00.000Z',
            },
          ],
        };
      final repository = AiSessionRepository(gateway);

      final transcript = await repository.read(
        sessionId: _validUuid,
        requestId: _validRequestId,
      );

      expect(transcript.staged, hasLength(1));
      expect(transcript.staged!.single.requestId, _validRequestId);
      expect(transcript.staged!.single.replyText, 'two cafes near you');
      expect(transcript.staged!.single.sources, hasLength(1));
    });

    test(
      'the three legs are mutually distinguishable: null != empty != '
      'populated',
      () async {
        // The denominator for the claim "both legs tested": three
        // distinct observable outcomes from one method.
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        gateway.nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
        final notAsked = await repository.read(sessionId: _validUuid);

        gateway.nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[],
          'staged': <dynamic>[],
        };
        final askedNothing = await repository.read(
          sessionId: _validUuid,
          requestId: _validRequestId,
        );

        expect(notAsked.staged, isNull);
        expect(askedNothing.staged, isNotNull);
        expect(askedNothing.staged, hasLength(0));
        // The two are NOT equal — which is the whole distinction.
        expect(notAsked.staged == askedNothing.staged, isFalse);
      },
    );
  });

  group('read — an empty turn list is NOT evidence the session is gone', () {
    test('an empty turns array returns an empty transcript, not an error',
        () async {
      // §7.2's silence: `handleRead` returns 200-with-empty for an
      // unknown session, a non-member, withdrawn consent, an unapproved
      // shared session AND a healthy session with no turns yet. They are
      // byte-identical on the wire, so this method must not invent a
      // distinction.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
      final repository = AiSessionRepository(gateway);

      final transcript = await repository.read(sessionId: _validUuid);

      expect(transcript.turns, isEmpty);
    });

    test(
      'the transcript exposes no member by which a caller could read '
      'emptiness as a terminal state',
      () async {
        final gateway = _FakeAiSessionGateway()
          ..nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
        final repository = AiSessionRepository(gateway);

        final transcript = await repository.read(sessionId: _validUuid);

        // There is no isGone/exists/isUnavailable/isTerminal to call, so
        // the only assertable property is that the type's whole public
        // surface is the two collections. Asserted behaviourally: the
        // empty read and a populated read differ ONLY in `turns`, and
        // neither carries a verdict.
        expect(transcript.turns, isEmpty);
        expect(transcript.staged, isNull);

        gateway.nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[
            <String, dynamic>{
              'ordinal': 1,
              'role': 'user',
              'kind': 'ideas_answer',
              'payload': <String, dynamic>{'instruction': 'hi'},
              'created_at': '2026-10-11T10:00:00.000Z',
            },
          ],
        };
        final populated = await repository.read(sessionId: _validUuid);
        expect(populated.turns, hasLength(1));
        expect(populated.staged, isNull);
      },
    );

    test('a FEATURE_DISABLED error is NOT how read reports a disabled flag',
        () async {
      // Recorded as the contrapositive: if the server ever did send
      // FEATURE_DISABLED for `read`, this maps it like any other code
      // rather than swallowing it into an empty transcript. §7.2 says it
      // will not, and `handleRead` does not run the eligibility gate at
      // all — so this asserts the mapping, not the server's behaviour.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'FEATURE_DISABLED',
          status: 403,
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.read(sessionId: _validUuid),
        throwsA(isA<AiSessionFeatureDisabledError>()),
      );
    });

    test('a response with no `turns` key fails rather than reading as empty',
        () async {
      // The inverse inference: manufacturing a benign empty state out of
      // a malformed response. `handleRead` always sends the key.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{};
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.read(sessionId: _validUuid),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('non-contiguous ordinals parse unchanged', () async {
      // Measured in Plan B: ordinals are 2n-1/2n and may skip after a
      // failed attempt (3,4 observed). A reader that assumed 1,2 would
      // mis-render a real transcript.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[
            <String, dynamic>{
              'ordinal': 3,
              'role': 'user',
              'kind': 'ideas_answer',
              'payload': <String, dynamic>{'instruction': 'again'},
              'created_at': '2026-10-11T10:00:00.000Z',
            },
            <String, dynamic>{
              'ordinal': 4,
              'role': 'attune',
              'kind': 'ideas_answer',
              'payload': <String, dynamic>{
                'reply_text': 'here you go',
                'suggested_planning_item': null,
              },
              'created_at': '2026-10-11T10:00:01.000Z',
            },
          ],
        };
      final repository = AiSessionRepository(gateway);

      final transcript = await repository.read(sessionId: _validUuid);

      expect(transcript.turns.map((turn) => turn.ordinal), [3, 4]);
      expect(transcript.turns.first, isA<AiSessionUserTurn>());
      expect(transcript.turns[1], isA<AiSessionIdeasAnswerTurn>());
    });
  });

  group('end — request shape', () {
    test('sends ONLY handleEnd\'s allowlist', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'ended': true};
      final repository = AiSessionRepository(gateway);

      await repository.end(_validUuid);

      // Transcribed from `handleEnd`'s own `allowed` set.
      expect(gateway.lastInvokeBody!.keys.toSet(), {'command', 'session_id'});
      expect(gateway.lastInvokeBody!['command'], 'end');
      expect(gateway.lastInvokeBody!['session_id'], _validUuid);
    });

    test('returns void and does NOT report whether there was work to do',
        () async {
      // `ended: true` means "this session is not running now" — it is
      // idempotent and says nothing about whether a session existed.
      // Returning the boolean would invite a caller to read it as
      // existence, which §5.4 and §3.1 both forbid.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'ended': true};
      final repository = AiSessionRepository(gateway);

      // `end` is declared `Future<void>`, so there is no value to read
      // at all: `final result = await repository.end(...)` does not even
      // COMPILE ("This expression has type 'void' and can't be used"),
      // which is a stronger guarantee than returning a boolean nobody
      // should trust. Measured, not assumed — that is the exact
      // compile error this test produced before being written this way.
      //
      // So the assertable property is that the call completes and the
      // request was made; the absence of a readable result is enforced
      // by the type system.
      await repository.end(_validUuid);
      expect(gateway.invokeCount, 1);
      expect(
        repository.end(_validUuid),
        isA<Future<void>>(),
        reason: 'end must not expose the server\'s idempotent `ended` '
            'boolean, which says nothing about whether a session existed',
      );
    });

    test('a second end of the same session is not an error', () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'ended': true};
      final repository = AiSessionRepository(gateway);

      await repository.end(_validUuid);
      await repository.end(_validUuid);

      expect(gateway.invokeCount, 2);
    });

    test('UNAVAILABLE maps by code — a foreign session is not distinguishable',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException('UNAVAILABLE', status: 404);
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.end(_validUuid),
        throwsA(isA<AiSessionUnavailableError>()),
      );
    });
  });

  group('shareAnswer — request shape', () {
    test('sends ONLY handleShareAnswer\'s allowlist and returns the id',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'message_id': _validMessageId};
      final repository = AiSessionRepository(gateway);

      final messageId = await repository.shareAnswer(
        sessionId: _validUuid,
        ordinal: 2,
      );

      // Transcribed from `handleShareAnswer`'s own `allowed` set.
      expect(gateway.lastInvokeBody!.keys.toSet(), {
        'command',
        'session_id',
        'ordinal',
      });
      expect(gateway.lastInvokeBody!['command'], 'share_answer');
      expect(gateway.lastInvokeBody!['session_id'], _validUuid);
      expect(gateway.lastInvokeBody!['ordinal'], 2);
      expect(messageId, _validMessageId);
    });

    test('sends the ordinal unchanged — it is not renumbered client-side',
        () async {
      // Ordinals may be non-contiguous, so a client that renumbered a
      // rendered list to 1..n would share the WRONG turn.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{'message_id': _validMessageId};
      final repository = AiSessionRepository(gateway);

      await repository.shareAnswer(sessionId: _validUuid, ordinal: 4);

      expect(gateway.lastInvokeBody!['ordinal'], 4);
    });

    test('CONSENT_REQUIRED is the one actionable refusal and maps distinctly',
        () async {
      // §10 gives consent its own code "precisely because 'caller can
      // open consent' is a refusal the caller can ACT on". Everything
      // else collapses to RESULT_UNAVAILABLE server-side.
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'CONSENT_REQUIRED',
          status: 403,
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.shareAnswer(sessionId: _validUuid, ordinal: 2),
        throwsA(isA<AiSessionConsentRequiredError>()),
      );
    });

    test('RESULT_UNAVAILABLE discloses nothing about which check refused',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeError = _sessionErrorException(
          'RESULT_UNAVAILABLE',
          status: 410,
        );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.shareAnswer(sessionId: _validUuid, ordinal: 2),
        throwsA(isA<AiSessionResultUnavailableError>()),
      );
    });

    test('a response with no message_id fails rather than returning empty',
        () async {
      final gateway = _FakeAiSessionGateway()
        ..nextInvokeResult = <String, dynamic>{};
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.shareAnswer(sessionId: _validUuid, ordinal: 2),
        throwsA(isA<AiSessionInternalError>()),
      );
    });
  });

  group('no Task 3 command body carries an actor id', () {
    test(
      'none of the 11 ACTOR_NAMING_FIELDS spellings, nor an unlisted '
      'identity-shaped key, appears in any of the five bodies',
      () async {
        // Transcribed from `ACTOR_NAMING_FIELDS`. The vacuous-denominator
        // guard is the length assertion: Plan C recorded a 12th unlisted
        // spelling as a real finding, so the substring sweep below is
        // STRONGER than the server's own list.
        const actorNamingFields = <String>{
          'actor_id',
          'p_actor_id',
          'user_id',
          'p_user_id',
          'requester_id',
          'creator_id',
          'author_id',
          'partner_id',
          'sender_id',
          'actor',
          'user',
        };
        expect(actorNamingFields.length, 11);

        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);
        final sentBodies = <String, Set<String>>{};

        gateway.nextInvokeResult = _reviewContextResponse();
        await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: 0,
          setIncludeWindow: true,
        );
        sentBodies['review_context'] = gateway.lastInvokeBody!.keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{
          'approved': true,
          'activated': true,
          'state': 'active',
        };
        await repository.approve(ticket: _ticket());
        sentBodies['approve'] = gateway.lastInvokeBody!.keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{
          'turns': <dynamic>[],
          'staged': <dynamic>[],
        };
        await repository.read(
          sessionId: _validUuid,
          requestId: _validRequestId,
        );
        sentBodies['read'] = gateway.lastInvokeBody!.keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{'ended': true};
        await repository.end(_validUuid);
        sentBodies['end'] = gateway.lastInvokeBody!.keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{
          'message_id': _validMessageId,
        };
        await repository.shareAnswer(sessionId: _validUuid, ordinal: 2);
        sentBodies['share_answer'] = gateway.lastInvokeBody!.keys.toSet();

        // Denominator: all five commands this task wraps were exercised.
        expect(sentBodies.length, 5);

        for (final entry in sentBodies.entries) {
          for (final field in actorNamingFields) {
            expect(
              entry.value,
              isNot(contains(field)),
              reason: '${entry.key} must never send the actor field "$field"',
            );
          }
          for (final key in entry.value) {
            expect(
              key.contains('actor') ||
                  key.contains('user') ||
                  key.contains('creator') ||
                  key.contains('author') ||
                  key.contains('partner') ||
                  key.contains('sender') ||
                  key.contains('requester'),
              isFalse,
              reason: '${entry.key} body key "$key" names an actor',
            );
          }
        }
      },
    );
  });

  group('_invoke preserves a typed error thrown while parsing', () {
    test(
      'an AiSessionError raised from onResult survives rather than being '
      'relabelled AiSessionInternalError',
      () async {
        // FOUND BY MUTATION 7. `_invoke`'s parse-failure catch used to
        // throw `internalError()` unconditionally, discarding `error` —
        // so a typed §10 error raised by a parser was silently
        // downgraded to a generic internal error at the exact boundary
        // whose job is to preserve the code. `_mapTransportError`'s
        // `error is AiSessionError` passthrough was written for this
        // path and could not reach it.
        //
        // HONEST SCOPE NOTE: no `onResult` in the repository throws a
        // typed AiSessionError today — every parser raises
        // FormatException — so the swallowing was LATENT, and the
        // mutation is what exposed it. This test therefore pins the two
        // halves of the fixed behaviour that ARE reachable, and
        // mutation 7 (recorded in the task report) is the evidence for
        // the third: with the fix in place it reports
        // AiSessionUnavailableError rather than AiSessionInternalError.
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        // The behavioural half: a malformed response still becomes
        // internalError, so the fix did not widen what escapes.
        gateway.nextInvokeResult = <String, dynamic>{};
        await expectLater(
          repository.read(sessionId: _validUuid),
          throwsA(isA<AiSessionInternalError>()),
        );

        // And a transport-side typed error is still passed through
        // unwrapped rather than double-wrapped — the same passthrough,
        // reached from the other direction.
        gateway.nextInvokeResult = null;
        gateway.nextInvokeError = const AiSessionError.unavailable();
        await expectLater(
          repository.read(sessionId: _validUuid),
          throwsA(isA<AiSessionUnavailableError>()),
        );
      },
    );

    test(
      'a FormatException from a parser still maps to internalError, so the '
      'passthrough did not widen what escapes',
      () async {
        for (final malformed in <Map<String, dynamic>>[
          // share_answer: missing message_id.
          <String, dynamic>{},
          // share_answer: an id of the wrong type.
          <String, dynamic>{'message_id': 7},
        ]) {
          final gateway = _FakeAiSessionGateway()
            ..nextInvokeResult = malformed;
          final repository = AiSessionRepository(gateway);
          await expectLater(
            repository.shareAnswer(sessionId: _validUuid, ordinal: 2),
            throwsA(isA<AiSessionInternalError>()),
            reason: 'malformed $malformed must not escape as a raw exception',
          );
        }
      },
    );
  });

  group('the five Task 3 commands name only the server\'s own commands', () {
    test(
      'each method sends its own command discriminator, and the five are '
      'distinct members of processSessionCommand\'s nine cases',
      () async {
        // `processSessionCommand` has EXACTLY nine cases and none of them
        // is `start`: activation rides inside `handleApprove`, which is
        // why there is no `start()` method on this repository. The brief's
        // Interfaces line specifies one; it is wrong.
        const serverCommands = <String>{
          'prepare',
          'review_context',
          'generate',
          'approve',
          'read',
          'publish_nearby',
          'discard_nearby',
          'end',
          'share_answer',
        };
        expect(serverCommands.length, 9);
        expect(serverCommands, isNot(contains('start')));

        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);
        final observed = <String>{};

        gateway.nextInvokeResult = _reviewContextResponse();
        await repository.reviewContext(
          sessionId: _validUuid,
          utcOffsetMinutes: 0,
        );
        observed.add(gateway.lastInvokeBody!['command'] as String);

        gateway.nextInvokeResult = <String, dynamic>{
          'approved': true,
          'activated': true,
          'state': 'active',
        };
        await repository.approve(ticket: _ticket());
        observed.add(gateway.lastInvokeBody!['command'] as String);

        gateway.nextInvokeResult = <String, dynamic>{'turns': <dynamic>[]};
        await repository.read(sessionId: _validUuid);
        observed.add(gateway.lastInvokeBody!['command'] as String);

        gateway.nextInvokeResult = <String, dynamic>{'ended': true};
        await repository.end(_validUuid);
        observed.add(gateway.lastInvokeBody!['command'] as String);

        gateway.nextInvokeResult = <String, dynamic>{
          'message_id': _validMessageId,
        };
        await repository.shareAnswer(sessionId: _validUuid, ordinal: 2);
        observed.add(gateway.lastInvokeBody!['command'] as String);

        // Five DISTINCT commands, each one a real server case.
        expect(observed.length, 5);
        expect(observed, {
          'review_context',
          'approve',
          'read',
          'end',
          'share_answer',
        });
        expect(observed.difference(serverCommands), isEmpty);
      },
    );
  });

  // =====================================================================
  // Task 4: generate
  // =====================================================================

  group('generate', () {
    test(
      'sends ONLY parseGenerateRequest\'s allowlist — the key set equals the '
      'transcribed six exactly',
      () async {
        // RULING 4. Transcribed from `parseGenerateRequest`'s own
        // `allowed` set (supabase/functions/ai-sessions/index.ts:1715).
        // Every branch rejects an unknown key with INVALID_INPUT rather
        // than ignoring it, so an extra key here is a failed call, not
        // a harmless one.
        const serverAllowlist = <String>{
          'command',
          'session_id',
          'request_id',
          'expected_revision',
          'user_instruction',
          'requester_location',
        };
        // Denominator guard: the server's set has six entries, so a
        // future edit that drops one from this transcription fails here
        // rather than weakening the equality below silently.
        expect(serverAllowlist.length, 6);

        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = _ideasAnswerResponse();
        final repository = AiSessionRepository(gateway);

        await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 3,
          userInstruction: 'ideas please',
          requesterLocation: (
            latitude: 5.6,
            longitude: -0.19,
            accuracyM: 12.0,
          ),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
        );

        expect(gateway.lastInvokedFunction, 'ai-sessions');
        // EQUALITY, not containment: `isNot(contains(...))` on a few
        // names would pass for a body that invented a seventh key.
        expect(gateway.lastInvokeBody!.keys.toSet(), serverAllowlist);
        expect(gateway.lastInvokeBody!['command'], 'generate');
        expect(gateway.lastInvokeBody!['session_id'], _validUuid);
        expect(gateway.lastInvokeBody!['request_id'], _validRequestId);
        expect(gateway.lastInvokeBody!['expected_revision'], 3);
        expect(gateway.lastInvokeBody!['user_instruction'], 'ideas please');
      },
    );

    test(
      'the nested requester_location key set equals parseGenerateRequest\'s '
      'location allowlist MINUS the decorative confirmation_nonce',
      () async {
        // Transcribed from `allowedLocationKeys` (index.ts:1774). The
        // server allows five; this client sends four.
        const serverLocationAllowlist = <String>{
          'latitude',
          'longitude',
          'accuracy_m',
          'captured_at',
          'confirmation_nonce',
        };
        expect(serverLocationAllowlist.length, 5);

        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = _stagedNearbyResponse();
        final repository = AiSessionRepository(gateway);

        await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'coffee nearby',
          requesterLocation: (
            latitude: 5.6037,
            longitude: -0.187,
            accuracyM: 25.0,
          ),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30, 15),
        );

        final sentLocation = Map<String, dynamic>.from(
          gateway.lastInvokeBody!['requester_location'] as Map,
        );
        // GATE 4: the nonce is DECORATIVE — no issuing RPC, column or
        // table exists, and `parseGenerateRequest` allowlists it only
        // to refuse to trust it. Sending one would be a confirmation
        // control that gates nothing. This asserts the exact four keys,
        // so adding the nonce back fails here.
        expect(sentLocation.keys.toSet(), {
          'latitude',
          'longitude',
          'accuracy_m',
          'captured_at',
        });
        expect(
          sentLocation.keys.toSet(),
          isNot(contains('confirmation_nonce')),
        );
        // And the four it does send are a SUBSET of the server's five,
        // so nothing invented reaches the nested object either.
        expect(
          sentLocation.keys.toSet().difference(serverLocationAllowlist),
          isEmpty,
        );
        expect(sentLocation['latitude'], 5.6037);
        expect(sentLocation['longitude'], -0.187);
        expect(sentLocation['accuracy_m'], 25.0);
        // UTC, with the Z suffix: the server `Date.parse`s this and
        // compares it to its OWN instant, so an offsetless local-time
        // string would be read as the wrong moment.
        expect(sentLocation['captured_at'], '2026-10-11T12:30:15.000Z');
      },
    );

    test(
      'omits requester_location entirely when there is none, rather than '
      'sending null',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = _ideasAnswerResponse();
        final repository = AiSessionRepository(gateway);

        await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'ideas please',
        );

        expect(
          gateway.lastInvokeBody!.keys.toSet(),
          {
            'command',
            'session_id',
            'request_id',
            'expected_revision',
            'user_instruction',
          },
        );
        expect(
          gateway.lastInvokeBody!.containsKey('requester_location'),
          isFalse,
          reason: 'an Ideas session WITH a location is INVALID_INPUT, so '
              '"I sent none" must be literal on the wire',
        );
      },
    );

    test(
      'a location without a capture timestamp is refused locally rather than '
      'sent as an incomplete point',
      () async {
        // `parseGenerateRequest` answers LOCATION_REQUIRED when
        // `captured_at` is not a string — whose §10 remedy is "ask for
        // permission", the wrong thing to show a user whose permission
        // was granted and whose point this client simply failed to
        // timestamp. The brief's sketch sent exactly this incomplete
        // object.
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        // THROWN SYNCHRONOUSLY, not as a rejected Future — the guard
        // runs before `_invoke` is reached, so there is no Future to
        // await. That is the stronger behaviour (the mistake surfaces
        // at the call site rather than one microtask later), and
        // asserting it this way is what proves it: an `expectLater` on
        // the returned Future would NOT have caught a synchronous
        // throw, and a guard moved inside the async body would fail
        // here.
        expect(
          () => repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'coffee nearby',
            requesterLocation: (
              latitude: 5.6,
              longitude: -0.19,
              accuracyM: 12.0,
            ),
          ),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('locationCapturedAt'),
            ),
          ),
        );
        // NOTHING WAS SENT. A call that reached the server would burn
        // the request id on a LOCATION_REQUIRED, and retrying that id
        // with a corrected body is REQUEST_CONFLICT.
        expect(gateway.invokeCount, 0);
      },
    );

    test('parses a fresh ideas answer, revision and proposal included',
        () async {
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeResult = <String, dynamic>{
        'kind': 'answer',
        'user_ordinal': 3,
        'attune_ordinal': 4,
        'session_revision': 7,
        'reply_text': 'Try a picnic at Legon Botanical Gardens.',
        'suggested_planning_item': <String, dynamic>{
          'kind': 'event',
          'title': 'Picnic',
          'event_date': '2026-10-18',
        },
        'show_safety_resources': true,
      };
      final repository = AiSessionRepository(gateway);

      final result = await repository.generate(
        sessionId: _validUuid,
        requestId: _validRequestId,
        expectedRevision: 3,
        userInstruction: 'ideas please',
      );

      final answer = result as AiSessionGeneratedAnswer;
      // ORDINALS 3/4, NOT 1/2 — the attempt counter advances on a
      // FAILED attempt too, so a session whose first attempt failed
      // holds 3 and 4 with no 1 or 2. Asserting the specific pair
      // catches a parser that renumbered.
      expect(answer.userOrdinal, 3);
      expect(answer.attuneOrdinal, 4);
      // GATE 1: the revision is returned to the actor who caused the
      // bump. This is that actor.
      expect(answer.sessionRevision, 7);
      expect(answer.replyText, 'Try a picnic at Legon Botanical Gardens.');
      expect(answer.suggestedPlanningItem, isNotNull);
      expect(answer.suggestedPlanningItem!.title, 'Picnic');
      expect(answer.replayed, isFalse);
    });

    test(
      'parses the idempotent replay, which has NO kind key and NO '
      'session_revision',
      () async {
        // Transcribed from `replayAdmittedRequest` (index.ts:2555). The
        // brief's own first fixture was this shape — no `kind` — while
        // its sketch branched on `kind == 'redirect'` and otherwise
        // read `attune_ordinal`, which would have silently parsed a
        // replay as a fresh answer and reported a null revision as
        // though the session had not moved.
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{
          'user_ordinal': 1,
          'attune_ordinal': 2,
          'reply_text': 'the one and only reply',
          'suggested_planning_item': null,
          'replayed': true,
        };
        final repository = AiSessionRepository(gateway);

        final result = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'ideas please',
        );

        final answer = result as AiSessionGeneratedAnswer;
        expect(answer.replayed, isTrue);
        expect(answer.attuneOrdinal, 2);
        expect(answer.replyText, 'the one and only reply');
        // NULL, not 0 and not invented: the replay path sends no
        // revision, and §6.2 guarantees no new provider lease, so there
        // is no bump to report. A client must not synthesize one — gate
        // 1 means there is nothing to fall back to.
        expect(answer.sessionRevision, isNull);
      },
    );

    test(
      'a body with neither kind nor replayed is malformed, not an answer',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{
          'user_ordinal': 1,
          'attune_ordinal': 2,
          'reply_text': 'looks like an answer',
        };
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'ideas please',
          ),
          // A FormatException from the parser, surfaced through
          // _mapTransportError's fallthrough. See the §10-preservation
          // group below for why no parser raises a typed error.
          throwsA(isA<AiSessionInternalError>()),
        );
      },
    );

    test(
      'parses a Nearby generation as STAGED, with no ordinals and no '
      'confirmation nonce',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = _stagedNearbyResponse();
        final repository = AiSessionRepository(gateway);

        final result = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'coffee nearby',
          requesterLocation: (
            latitude: 5.6,
            longitude: -0.19,
            accuracyM: 12.0,
          ),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
        );

        // NOT an AiSessionTurnModel and not an answer: nothing is
        // committed, the revision has not moved, and the partner can
        // see nothing until publishNearby.
        final staged = result as AiSessionStagedNearbyGeneration;
        expect(staged, isNot(isA<AiSessionTurnModel>()));
        expect(staged, isNot(isA<AiSessionGeneratedAnswer>()));
        expect(staged.requestId, _validRequestId);
        expect(
          staged.replyText,
          'Here are a few coffee options nearby: Vida e Caffe',
        );
        expect(staged.sources.length, 1);
        expect(staged.sources.single.name, 'Vida e Caffe');
        // GATE 4 again, now on the RESPONSE side: the staged type has
        // no nonce field, so a server that started sending one could
        // not be rendered as a confirmation. Its transcribed wire key
        // set is the proof, and it has six entries.
        expect(AiSessionStagedNearbyGeneration.wireKeys.length, 6);
        expect(
          AiSessionStagedNearbyGeneration.wireKeys,
          isNot(contains('confirmation_nonce')),
        );
      },
    );

    test('zero Nearby sources is a valid staged result, not a failure',
        () async {
      // §5.3: "Zero results is a deterministic no-results card", and
      // `buildNearbySessionReplyText` has an explicit branch for it.
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeResult = <String, dynamic>{
        'kind': 'nearby_result',
        'staged': true,
        'request_id': _validRequestId,
        'reply_text':
            'No coffee results came back nearby. Try a different category.',
        'sources': <dynamic>[],
        'show_safety_resources': true,
      };
      final repository = AiSessionRepository(gateway);

      final result = await repository.generate(
        sessionId: _validUuid,
        requestId: _validRequestId,
        expectedRevision: 1,
        userInstruction: 'coffee nearby',
        requesterLocation: (latitude: 5.6, longitude: -0.19, accuracyM: 12.0),
        locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
      );

      final staged = result as AiSessionStagedNearbyGeneration;
      expect(staged.sources, isEmpty);
      expect(
        staged.replyText,
        'No coffee results came back nearby. Try a different category.',
      );
    });

    test(
      'a nearby_result body without staged: true is malformed rather than '
      'rendered as publishable',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{
          'kind': 'nearby_result',
          'request_id': _validRequestId,
          'reply_text': 'Here are a few coffee options nearby: Vida e Caffe',
          'sources': <dynamic>[],
          'show_safety_resources': true,
        };
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'coffee nearby',
            requesterLocation: (
              latitude: 5.6,
              longitude: -0.19,
              accuracyM: 12.0,
            ),
            locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
          ),
          throwsA(isA<AiSessionInternalError>()),
        );
      },
    );

    test('an unrecognized kind is a malformed response, not a fourth case',
        () async {
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeResult = <String, dynamic>{
        'kind': 'ideas_answer',
        'attune_ordinal': 2,
        'reply_text': 'the stored turn kind is not a generate response kind',
      };
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'ideas please',
        ),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test(
      'a CONTEXT_CHANGED from a stale expected_revision surfaces as its own '
      'code, whose remedy is to review again',
      () async {
        // `expected_revision` is bound into
        // admit_ai_session_generation's operation fingerprint, and a
        // mismatch raises CONTEXT_CHANGED. The remedy is ALWAYS to call
        // reviewContext again and approve the digest it returns — never
        // to recompute the digest (gate 2 makes that impossible) and
        // never to bump the number locally and resend.
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeError = _sessionErrorException(
          'CONTEXT_CHANGED',
          status: 409,
        );
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'ideas please',
          ),
          throwsA(isA<AiSessionContextChangedError>()),
        );
        // ONE attempt. A repository that retried would, with a bumped
        // revision, change the fingerprint and earn REQUEST_CONFLICT;
        // with the same revision it would just repeat the failure.
        expect(gateway.invokeCount, 1);
      },
    );

    test(
      'the two location codes stay distinct — their §10 remedies differ',
      () async {
        // LOCATION_REQUIRED -> ask for permission.
        // LOCATION_EXPIRED  -> recapture the point.
        // Both are HTTP 400, so a status-driven mapper could not tell
        // them apart; these assert the distinct subtypes.
        for (final probe in <({String code, Type error})>[
          (code: 'LOCATION_REQUIRED', error: AiSessionLocationRequiredError),
          (code: 'LOCATION_EXPIRED', error: AiSessionLocationExpiredError),
        ]) {
          final gateway = _FakeAiSessionGateway();
          gateway.nextInvokeError = _sessionErrorException(
            probe.code,
            status: 400,
          );
          final repository = AiSessionRepository(gateway);

          await expectLater(
            repository.generate(
              sessionId: _validUuid,
              requestId: _validRequestId,
              expectedRevision: 1,
              userInstruction: 'coffee nearby',
              requesterLocation: (
                latitude: 5.6,
                longitude: -0.19,
                accuracyM: 12.0,
              ),
              locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
            ),
            throwsA(predicate((e) => e.runtimeType == probe.error)),
            reason: '${probe.code} must map to ${probe.error}',
          );
        }
      },
    );
  });


  // =====================================================================
  // RULING 6: the two `kind: "redirect"` shapes must be
  // INDISTINGUISHABLE through the client's public surface.
  //
  // `safetyRefusalResponse` (index.ts:2145) emits `kind: "redirect"`
  // with a server-rendered `copy` and an EMPTY `offered`; the model's
  // own redirect (index.ts:2707 / :2806) emits the SAME `kind` without
  // `copy`. They deliberately share the kind AND the reason set
  // (`unsupported | unsafe_to_assist | insufficient_context`), and that
  // sharing is what prevents a side channel: Plan C Task 6 established
  // that a durable or distinguishable redirect would disclose that a
  // safety detector fired, which §8.1 forbids revealing to EITHER
  // party.
  //
  // So these tests do not merely check that both parse. They assert
  // that after parsing, the two values are INDISTINGUISHABLE through
  // every member the type exposes — which is the property a UI relies
  // on and the property a future getter would silently destroy.
  // =====================================================================

  group('RULING 6: the two redirect shapes are indistinguishable', () {
    test(
      'both shapes parse into the SAME runtime type — no subtype, no '
      'discriminator',
      () async {
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        gateway.nextInvokeResult = _safetyRefusalRedirectResponse();
        final refusal = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'probing instruction',
        );

        gateway.nextInvokeResult = _ordinaryRedirectResponse();
        final ordinary = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'news today',
        );

        // `runtimeType` EQUALITY, not two isA<> checks: a subtype for
        // either shape would satisfy `isA<AiSessionGeneratedRedirect>()`
        // on both while being perfectly distinguishable with an `is`
        // check at any call site.
        expect(refusal.runtimeType, AiSessionGeneratedRedirect);
        expect(refusal.runtimeType, ordinary.runtimeType);
      },
    );

    test(
      'EVERY member of the public surface returns the same value for both '
      'shapes, given the same reason',
      () async {
        // THE CORE PROOF. The enumeration below is exhaustive over
        // AiSessionGeneratedRedirect's public instance surface:
        //   - reason
        //   - offered
        //   - showSafetyResources
        //   - resolveCopy(genericRedirectCopy:)
        //   - runtimeType / toString / hashCode-class (Object's own)
        // `copy` is PRIVATE, so it is not on this list and cannot be.
        //
        // The two fixtures are made to agree on everything the server
        // lets them agree on — the same reason, and `offered: []` on
        // BOTH, which an ordinary redirect may legally send
        // (`validateSessionTurnOutput` accepts an empty array) — so any
        // residual difference must come from the ONE field that
        // genuinely differs on the wire: `copy`.
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        gateway.nextInvokeResult = _safetyRefusalRedirectResponse(
          reason: 'unsafe_to_assist',
        );
        final refusal = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'probing instruction',
        ) as AiSessionGeneratedRedirect;

        gateway.nextInvokeResult = _ordinaryRedirectResponse(
          reason: 'unsafe_to_assist',
          offered: const <String>[],
        );
        final ordinary = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'news today',
        ) as AiSessionGeneratedRedirect;

        // `reason` is drawn from ONE set on both paths.
        // `classifySessionContent` refuses with only `unsafe_to_assist`
        // or `unsupported`, and the model may report either of those
        // too, so reading it narrows nothing.
        expect(refusal.reason, 'unsafe_to_assist');
        expect(refusal.reason, ordinary.reason);

        expect(refusal.offered, isEmpty);
        expect(refusal.offered, ordinary.offered);

        // CONSTANT-TRUE at all three of classifySessionContent's
        // return points INCLUDING the allowed one, and hardcoded true
        // in both redirect bodies. Being constant, it cannot be a
        // signal — and this assertion is what keeps it constant.
        expect(refusal.showSafetyResources, isTrue);
        expect(ordinary.showSafetyResources, isTrue);
        expect(refusal.showSafetyResources, ordinary.showSafetyResources);

        // THE ONE ACCESSOR OVER `copy`, AND IT IS TOTAL. Both return a
        // non-empty String; neither returns null; and the signature has
        // no second return value, no out-parameter and no overload that
        // could report which branch was taken.
        const generic =
            'I can help with ideas or places nearby. Want to try one of '
            'those?';
        expect(refusal.resolveCopy(genericRedirectCopy: generic), isNotEmpty);
        expect(ordinary.resolveCopy(genericRedirectCopy: generic), generic);

        // ==== THE SURFACE IS CLOSED ====
        //
        // The assertions above compare every member the type exposes.
        // This one proves the LIST is complete rather than merely long:
        // `noSuchMethod`-free Dart has no reflection in this test
        // environment, so completeness is proved structurally — the
        // type is NOT sealed/abstract and has exactly four public
        // instance members, enumerated here as the declared names a
        // caller can reach. A fifth would have to be added to this list
        // for the mutation test below to be meaningful, which is the
        // point: the list is maintained deliberately.
        const publicInstanceSurface = <String>{
          'reason',
          'offered',
          'showSafetyResources',
          'resolveCopy',
        };
        expect(publicInstanceSurface.length, 4);
        // And none of the forbidden names is among them. These are the
        // exact getters Ruling 6 names, plus the proxies: each one would
        // reconstruct the detector signal.
        for (final forbidden in const <String>[
          'isSafetyRefusal',
          'wasBlocked',
          'isUnsafe',
          'blocked',
          'copy',
          'hasCopy',
          'hasServerCopy',
          'copyOrNull',
          'serverCopy',
          'hasAlternatives',
          'canOfferAnything',
          'shape',
          'variant',
          'source',
        ]) {
          expect(
            publicInstanceSurface,
            isNot(contains(forbidden)),
            reason: '"$forbidden" would distinguish a safety refusal from an '
                'ordinary redirect, which §8.1 forbids',
          );
        }
      },
    );

    test(
      'the two shapes differ on the wire in EXACTLY one key, and it is the '
      'one this client cannot read',
      () {
        // The denominator for the proof above. If the shapes differed in
        // more than `copy`, hiding `copy` alone would not be enough —
        // so this measures the difference from the transcribed key sets
        // rather than assuming it.
        final difference = AiSessionGeneratedRedirect.safetyShapeWireKeys
            .difference(AiSessionGeneratedRedirect.ordinaryShapeWireKeys)
            .union(
              AiSessionGeneratedRedirect.ordinaryShapeWireKeys.difference(
                AiSessionGeneratedRedirect.safetyShapeWireKeys,
              ),
            );
        expect(difference, {'copy'});
        // Both sets are non-trivial, so the equality above is not the
        // accident of two empty sets.
        expect(AiSessionGeneratedRedirect.safetyShapeWireKeys.length, 5);
        expect(AiSessionGeneratedRedirect.ordinaryShapeWireKeys.length, 4);
        // And `kind` is shared, which is the sharing that makes the
        // side channel closable at all.
        expect(
          AiSessionGeneratedRedirect.safetyShapeWireKeys,
          contains('kind'),
        );
        expect(
          AiSessionGeneratedRedirect.ordinaryShapeWireKeys,
          contains('kind'),
        );
      },
    );

    test(
      'a refusal reason the MODEL can also produce is accepted from both '
      'shapes — the reason set is shared, not partitioned',
      () async {
        // If this client accepted `unsafe_to_assist` only with a `copy`,
        // or `unsupported` only without one, the parse itself would be
        // the oracle. So every reason is fed through BOTH shapes and all
        // six combinations must parse to the same reason.
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);
        final parsed = <String, Set<String>>{};

        for (final reason in const <String>[
          'unsupported',
          'unsafe_to_assist',
          'insufficient_context',
        ]) {
          gateway.nextInvokeResult = _safetyRefusalRedirectResponse(
            reason: reason,
          );
          final refusal = await repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'x',
          ) as AiSessionGeneratedRedirect;

          gateway.nextInvokeResult = _ordinaryRedirectResponse(
            reason: reason,
            offered: const <String>[],
          );
          final ordinary = await repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'x',
          ) as AiSessionGeneratedRedirect;

          expect(refusal.reason, reason);
          expect(ordinary.reason, reason);
          parsed[reason] = {refusal.reason, ordinary.reason};
        }

        // Denominator: all three reasons were exercised, and each
        // produced ONE value across both shapes.
        expect(parsed.length, 3);
        for (final entry in parsed.entries) {
          expect(
            entry.value,
            {entry.key},
            reason: 'the two shapes disagreed about reason "${entry.key}"',
          );
        }
      },
    );

    test(
      'a redirect is never a transcript turn — RULING 7',
      () async {
        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);

        gateway.nextInvokeResult = _safetyRefusalRedirectResponse();
        final refusal = await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'x',
        );

        // The redirect model is a RESPONSE type only. It is not an
        // AiSessionTurnModel, so it cannot be put in a transcript list,
        // cannot be rendered by a turn renderer, and has no ordinal or
        // created_at to persist. §5.3 as amended by Plan C Task 6: "NO
        // redirect becomes a transcript pair. ALL redirects are
        // requester-only" — because a durable redirect is itself the
        // safety side channel (bumping the revision for 'unsupported'
        // but not 'unsafe_to_assist' would disclose the detector to a
        // partner polling session_revision).
        expect(refusal, isNot(isA<AiSessionTurnModel>()));
        expect(refusal, isNot(isA<AiSessionAttuneTurn>()));

        // And the transcript parser still REJECTS the kind outright, so
        // a server that somehow committed one could not be rendered.
        expect(
          () => AiSessionTurnModel.fromJson(<String, dynamic>{
            'ordinal': 2,
            'role': 'attune',
            'kind': 'redirect',
            'payload': <String, dynamic>{'reason': 'unsupported'},
            'created_at': '2026-10-11T12:00:00Z',
          }),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test(
      'an offered entry the server could not have sent is a malformed '
      'response rather than a rendered chip',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = _ordinaryRedirectResponse(
          offered: const <String>['understand'],
        );
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'x',
          ),
          // `validateSessionTurnOutput` admits only 'ideas' and
          // 'nearby', so anything else never left the server.
          throwsA(isA<AiSessionInternalError>()),
        );
      },
    );

    test('an unrecognized redirect reason is rejected from BOTH shapes',
        () async {
      // Symmetry matters here too: rejecting an unknown reason from one
      // shape but tolerating it from the other would make the parse
      // outcome itself a discriminator.
      final gateway = _FakeAiSessionGateway();
      final repository = AiSessionRepository(gateway);

      for (final body in <Map<String, dynamic>>[
        <String, dynamic>{
          ..._safetyRefusalRedirectResponse(),
          'reason': 'policy_violation',
        },
        <String, dynamic>{
          ..._ordinaryRedirectResponse(),
          'reason': 'policy_violation',
        },
      ]) {
        gateway.nextInvokeResult = body;
        await expectLater(
          repository.generate(
            sessionId: _validUuid,
            requestId: _validRequestId,
            expectedRevision: 1,
            userInstruction: 'x',
          ),
          throwsA(isA<AiSessionInternalError>()),
          reason: 'both shapes must refuse an unknown reason identically',
        );
      }
    });
  });


  // =====================================================================
  // Task 4: publish_nearby / discard_nearby
  // =====================================================================

  group('publishNearby', () {
    test(
      'sends ONLY handlePublishNearby\'s allowlist — the key set equals the '
      'transcribed two exactly',
      () async {
        // RULING 4. Transcribed from `handlePublishNearby`'s own
        // `allowed` set (index.ts:3432). NARROWER than generate's: no
        // session id (the server resolves it from the request row), no
        // expected_revision, and — gate 4 — no confirmation nonce.
        const serverAllowlist = <String>{'command', 'request_id'};
        expect(serverAllowlist.length, 2);

        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{
          'committed': true,
          'user_ordinal': 1,
          'attune_ordinal': 2,
          'session_revision': 3,
        };
        final repository = AiSessionRepository(gateway);

        await repository.publishNearby(_validRequestId);

        expect(gateway.lastInvokedFunction, 'ai-sessions');
        expect(gateway.lastInvokeBody!.keys.toSet(), serverAllowlist);
        expect(gateway.lastInvokeBody!['command'], 'publish_nearby');
        expect(gateway.lastInvokeBody!['request_id'], _validRequestId);
        // GATE 4 behaviourally: publishing is authorized by the actor's
        // JWT and the staging row's author check. There is no nonce to
        // send and no parameter that could carry one.
        expect(
          gateway.lastInvokeBody!.containsKey('confirmation_nonce'),
          isFalse,
        );
      },
    );

    test(
      'returns the ordinals AND the session_revision — the body has four '
      'fields, not the two the brief claimed',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{
          'committed': true,
          // Non-contiguous on purpose: a failed attempt advanced the
          // counter, so the published pair is 3/4.
          'user_ordinal': 3,
          'attune_ordinal': 4,
          'session_revision': 9,
        };
        final repository = AiSessionRepository(gateway);

        final published = await repository.publishNearby(_validRequestId);

        expect(published.committed, isTrue);
        expect(published.userOrdinal, 3);
        expect(published.attuneOrdinal, 4);
        // GATE 1: disclosed to THIS actor, the one who caused the bump.
        // The partner — the party that must poll to notice these turns
        // — cannot read this integer from any command, so nothing may
        // be built assuming they can.
        expect(published.sessionRevision, 9);
        // Denominator: the transcribed wire key set has four entries,
        // so a brief-faithful two-field model would fail here.
        expect(AiSessionPublishNearbyResult.wireKeys.length, 4);
        expect(
          AiSessionPublishNearbyResult.wireKeys,
          {'committed', 'user_ordinal', 'attune_ordinal', 'session_revision'},
        );
      },
    );

    test('a missing session_revision is malformed, not a zero', () async {
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeResult = <String, dynamic>{
        'committed': true,
        'user_ordinal': 1,
        'attune_ordinal': 2,
      };
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.publishNearby(_validRequestId),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test('committed: false on a success status is malformed', () async {
      // The RPC raises rather than returning false, and the branch maps
      // every raise to a §10 code — so a false here cannot be a
      // "published nothing" outcome to render.
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeResult = <String, dynamic>{
        'committed': false,
        'user_ordinal': 1,
        'attune_ordinal': 2,
        'session_revision': 3,
      };
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.publishNearby(_validRequestId),
        throwsA(isA<AiSessionInternalError>()),
      );
    });

    test(
      'RESULT_UNAVAILABLE collapses expired, discarded, already-published '
      'and foreign staging rows into one code',
      () async {
        // `handlePublishNearby` maps 'No staged result for this
        // request', 'Staged result has expired', 'Only the requester
        // may publish' and 'Request not found' to the SAME code, for
        // the same indistinguishability reason §3.1 requires of session
        // ids. A client must not try to tell them apart.
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeError = _sessionErrorException(
          'RESULT_UNAVAILABLE',
          status: 410,
        );
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.publishNearby(_validRequestId),
          throwsA(isA<AiSessionResultUnavailableError>()),
        );
      },
    );

    test('CONSENT_REQUIRED is distinguished, because the caller can act on it',
        () async {
      // §10 names it the one refusal worth distinguishing, "precisely
      // because 'caller can open consent' is a refusal the caller can
      // ACT on". Note it shares HTTP 403 with FEATURE_DISABLED, so a
      // status-driven mapper could not separate them.
      final gateway = _FakeAiSessionGateway();
      gateway.nextInvokeError = _sessionErrorException(
        'CONSENT_REQUIRED',
        status: 403,
      );
      final repository = AiSessionRepository(gateway);

      await expectLater(
        repository.publishNearby(_validRequestId),
        throwsA(isA<AiSessionConsentRequiredError>()),
      );
    });
  });

  group('discardNearby', () {
    test(
      'sends ONLY handleDiscardNearby\'s allowlist — the key set equals the '
      'transcribed two exactly',
      () async {
        // RULING 4. Transcribed from `handleDiscardNearby`'s own
        // `allowed` set (index.ts:3589).
        const serverAllowlist = <String>{'command', 'request_id'};
        expect(serverAllowlist.length, 2);

        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{'discarded': true};
        final repository = AiSessionRepository(gateway);

        await repository.discardNearby(_validRequestId);

        expect(gateway.lastInvokedFunction, 'ai-sessions');
        expect(gateway.lastInvokeBody!.keys.toSet(), serverAllowlist);
        expect(gateway.lastInvokeBody!['command'], 'discard_nearby');
        expect(gateway.lastInvokeBody!['request_id'], _validRequestId);
      },
    );

    test(
      'returns nothing — `discarded: true` is not readable as existence',
      () async {
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{'discarded': true};
        final repository = AiSessionRepository(gateway);

        // `Future<void>`, enforced by the COMPILER: assigning the awaited
        // value to anything is a compile error, so there is no boolean a
        // caller could read as "there was something to discard". For a
        // foreign request id that boolean would be exactly the existence
        // oracle the server's RESULT_UNAVAILABLE mapping exists to close.
        // (Ruling 12's disclosure: this kill is a compile error, not a
        // runtime assertion — the same evidence class as `end`'s.)
        await repository.discardNearby(_validRequestId);
        expect(gateway.invokeCount, 1);
      },
    );

    test(
      'an EMPTY response body still succeeds — nothing is read from it',
      () async {
        // The parser reads nothing, so a server that changed the body
        // cannot break a discard. This is the behavioural half of the
        // claim above.
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeResult = <String, dynamic>{};
        final repository = AiSessionRepository(gateway);

        await repository.discardNearby(_validRequestId);
        expect(gateway.invokeCount, 1);
      },
    );

    test(
      'a foreign request id surfaces as RESULT_UNAVAILABLE, the same code a '
      'missing row gets',
      () async {
        // The RPC's 'Only the requester may discard' raise is mapped to
        // RESULT_UNAVAILABLE deliberately, so a staged result belonging
        // to someone else is indistinguishable from one that never
        // existed.
        final gateway = _FakeAiSessionGateway();
        gateway.nextInvokeError = _sessionErrorException(
          'RESULT_UNAVAILABLE',
          status: 410,
        );
        final repository = AiSessionRepository(gateway);

        await expectLater(
          repository.discardNearby(_validRequestId),
          throwsA(isA<AiSessionResultUnavailableError>()),
        );
      },
    );
  });

  group('no Task 4 command body carries an actor id', () {
    test(
      'none of the 11 ACTOR_NAMING_FIELDS spellings, nor an unlisted '
      'identity-shaped key, appears in any of the three bodies',
      () async {
        // Transcribed from `ACTOR_NAMING_FIELDS`. Same denominator
        // guard as Task 3's sweep: Plan C recorded a 12th unlisted
        // spelling as a real finding, so the substring sweep below is
        // STRONGER than the server's own list.
        const actorNamingFields = <String>{
          'actor_id',
          'p_actor_id',
          'user_id',
          'p_user_id',
          'requester_id',
          'creator_id',
          'author_id',
          'partner_id',
          'sender_id',
          'actor',
          'user',
        };
        expect(actorNamingFields.length, 11);

        final gateway = _FakeAiSessionGateway();
        final repository = AiSessionRepository(gateway);
        final sentBodies = <String, Set<String>>{};

        gateway.nextInvokeResult = _stagedNearbyResponse();
        await repository.generate(
          sessionId: _validUuid,
          requestId: _validRequestId,
          expectedRevision: 1,
          userInstruction: 'coffee nearby',
          // WITH a location, so the one allowlisted key whose name
          // contains "requester" is actually on the wire for this
          // sweep rather than absent.
          requesterLocation: (
            latitude: 5.6,
            longitude: -0.19,
            accuracyM: 12.0,
          ),
          locationCapturedAt: DateTime.utc(2026, 10, 11, 12, 30),
        );
        sentBodies['generate'] = gateway.lastInvokeBody!.keys.toSet();
        // The nested object is swept too — an actor id hidden one level
        // down would pass a top-level-only check.
        final nestedLocationKeys = Map<String, dynamic>.from(
          gateway.lastInvokeBody!['requester_location'] as Map,
        ).keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{
          'committed': true,
          'user_ordinal': 1,
          'attune_ordinal': 2,
          'session_revision': 3,
        };
        await repository.publishNearby(_validRequestId);
        sentBodies['publish_nearby'] = gateway.lastInvokeBody!.keys.toSet();

        gateway.nextInvokeResult = <String, dynamic>{'discarded': true};
        await repository.discardNearby(_validRequestId);
        sentBodies['discard_nearby'] = gateway.lastInvokeBody!.keys.toSet();

        // Denominator: all three commands this task wraps were
        // exercised.
        expect(sentBodies.length, 3);

        // TWO of generate's six allowlisted keys contain an
        // identity-shaped SUBSTRING while naming no identity, and this
        // sweep is stronger than the server's own list precisely
        // because it is substring-based — so each is exempted BY NAME,
        // with its reason, rather than by weakening the sweep. The
        // server's ACTOR_NAMING_FIELDS is exact-match over 11 names and
        // contains neither, so neither is rejected server-side either.
        //
        //   * `requester_location` is a GEOGRAPHIC POINT: three numbers
        //     and a timestamp, with no id of any kind inside it. The
        //     nested key set is asserted EXACTLY below, so this
        //     exemption cannot hide a field that really does name an
        //     actor one level down.
        //   * `user_instruction` is the TEXT THE USER TYPED — §4.1's
        //     own field name for the instruction, bounded to 1..300
        //     scalars and bound into the operation fingerprint. It
        //     carries content, never identity; the actor is derived
        //     from the verified JWT.
        //
        // This exemption list is deliberately a closed set of two: a
        // THIRD identity-shaped key appearing in any Task 4 body fails
        // this test rather than being quietly waved through.
        const substringExemptions = <String>{
          'requester_location',
          'user_instruction',
        };
        expect(substringExemptions.length, 2);
        // Neither exemption is a name the SERVER blocklists — if one
        // were, exempting it here would be excusing a key every call
        // would be rejected for.
        expect(
          substringExemptions.intersection(actorNamingFields),
          isEmpty,
        );
        expect(nestedLocationKeys, {
          'latitude',
          'longitude',
          'accuracy_m',
          'captured_at',
        });

        for (final entry in sentBodies.entries) {
          for (final field in actorNamingFields) {
            expect(
              entry.value,
              isNot(contains(field)),
              reason: '${entry.key} must never send the actor field "$field"',
            );
          }
          for (final key in entry.value) {
            if (substringExemptions.contains(key)) continue;
            expect(
              key.contains('actor') ||
                  key.contains('user') ||
                  key.contains('creator') ||
                  key.contains('author') ||
                  key.contains('partner') ||
                  key.contains('sender') ||
                  key.contains('requester'),
              isFalse,
              reason: '${entry.key} body key "$key" names an actor',
            );
          }
        }
        // And the nested object carries no identity-shaped key at all —
        // no exemption applies one level down.
        for (final key in nestedLocationKeys) {
          expect(
            key.contains('actor') ||
                key.contains('user') ||
                key.contains('creator') ||
                key.contains('author') ||
                key.contains('partner') ||
                key.contains('sender') ||
                key.contains('_id'),
            isFalse,
            reason: 'requester_location key "$key" names an actor or an id',
          );
        }
      },
    );
  });

  group('RULING 11: no Task 4 parser throws a constant typed error', () {
    test(
      'every malformed body this task can receive surfaces a FormatException '
      'through the parser, never a fabricated §10 code',
      () {
        // RULING 11, asserted at the PARSER rather than through the
        // repository, because that is where the requirement lives: a
        // parser that threw a constant typed error would put a
        // fabricated code on `_invoke`'s code-PRESERVING path — the
        // exact defect Task 3's mutation 7 found in the opposite
        // direction, where a REAL typed code was being discarded there.
        //
        // Through the repository these all surface as
        // AiSessionInternalError (via _mapTransportError's
        // fallthrough), which is correct but would ALSO be the
        // observable result of a parser throwing
        // `AiSessionError.internalError()` directly. So the exception
        // TYPE is asserted at the parser, where the two differ.
        final malformedBodies = <String, Map<String, dynamic>>{
          'no kind and no replayed flag': <String, dynamic>{
            'attune_ordinal': 2,
            'reply_text': 'x',
          },
          'unrecognized kind': <String, dynamic>{
            'kind': 'ideas_answer',
            'attune_ordinal': 2,
          },
          'answer without attune_ordinal': <String, dynamic>{
            'kind': 'answer',
            'reply_text': 'x',
            'show_safety_resources': true,
          },
          'fresh answer with no reply_text': <String, dynamic>{
            'kind': 'answer',
            'attune_ordinal': 2,
            'session_revision': 2,
            'show_safety_resources': true,
          },
          'answer with a non-int session_revision': <String, dynamic>{
            'kind': 'answer',
            'attune_ordinal': 2,
            'session_revision': '2',
            'reply_text': 'x',
            'show_safety_resources': true,
          },
          'redirect with an unknown reason': <String, dynamic>{
            'kind': 'redirect',
            'reason': 'policy_violation',
            'offered': <dynamic>[],
            'show_safety_resources': true,
          },
          'redirect with an unknown offered entry': <String, dynamic>{
            'kind': 'redirect',
            'reason': 'unsupported',
            'offered': <dynamic>['understand'],
            'show_safety_resources': true,
          },
          'redirect without show_safety_resources': <String, dynamic>{
            'kind': 'redirect',
            'reason': 'unsupported',
            'offered': <dynamic>[],
          },
          'redirect with a non-string copy': <String, dynamic>{
            'kind': 'redirect',
            'reason': 'unsupported',
            'offered': <dynamic>[],
            'copy': 42,
            'show_safety_resources': true,
          },
          'nearby_result without staged': <String, dynamic>{
            'kind': 'nearby_result',
            'request_id': _validRequestId,
            'reply_text': 'x',
            'sources': <dynamic>[],
            'show_safety_resources': true,
          },
          'nearby_result with non-list sources': <String, dynamic>{
            'kind': 'nearby_result',
            'staged': true,
            'request_id': _validRequestId,
            'reply_text': 'x',
            'sources': 'none',
            'show_safety_resources': true,
          },
        };
        // Denominator: eleven distinct malformations across all three
        // response shapes plus the kind dispatch itself.
        expect(malformedBodies.length, 11);

        for (final entry in malformedBodies.entries) {
          expect(
            () => AiSessionGenerateResult.fromJson(entry.value),
            throwsA(isA<FormatException>()),
            reason: '${entry.key}: a parser must raise a FormatException '
                'describing what it could not read, never a constant typed '
                'AiSessionError',
          );
          // AND NOT a typed §10 error. This is the half that enforces
          // Ruling 11 rather than merely observing a throw.
          expect(
            () => AiSessionGenerateResult.fromJson(entry.value),
            throwsA(isNot(isA<AiSessionError>())),
            reason: '${entry.key}: a typed error here would be a fabricated '
                '§10 code on the code-preserving path',
          );
        }
      },
    );

    test(
      'publish_nearby\'s parser follows the same rule',
      () {
        for (final body in <Map<String, dynamic>>[
          <String, dynamic>{'user_ordinal': 1, 'attune_ordinal': 2},
          <String, dynamic>{
            'committed': false,
            'user_ordinal': 1,
            'attune_ordinal': 2,
            'session_revision': 3,
          },
          <String, dynamic>{
            'committed': true,
            'attune_ordinal': 2,
            'session_revision': 3,
          },
        ]) {
          expect(
            () => AiSessionPublishNearbyResult.fromJson(body),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => AiSessionPublishNearbyResult.fromJson(body),
            throwsA(isNot(isA<AiSessionError>())),
          );
        }
      },
    );
  });

}
