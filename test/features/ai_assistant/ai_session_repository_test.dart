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
    if (nextInvokeError != null) {
      final error = nextInvokeError!;
      nextInvokeError = null;
      throw error;
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
}
