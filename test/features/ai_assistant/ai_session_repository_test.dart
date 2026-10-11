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
}
