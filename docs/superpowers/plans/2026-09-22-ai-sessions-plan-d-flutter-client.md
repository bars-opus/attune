# AI Sessions — Plan D: Flutter Client

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the client surface for AI Sessions — a composer entry
point matching the existing attachment-scrim treatment, preparation/
context-approval screens, a live transcript renderer for shared sessions,
Nearby's private staging/publish flow, the seven server-authoritative
rollout flags from spec §12, and a typed session repository over Plan C's
nine-command edge function — reusing the existing
`AiAssistantGateway`/`AssistantError` seam rather than inventing a second
client stack.

**Architecture:** A new `AiSessionRepository` (mirrors
`AiAssistantRepository`'s exact shape: one `_invoke('ai-sessions', ...)`
call per command, throwing a new `AiSessionError` sealed type on every
non-2xx response) alongside the existing `AiAssistantRepository` — not a
replacement for it, since long-press Understand still calls `ai-understand`
directly and is unchanged. `ChatTextField` gains one `ComposerSatellite`
button and an `aiMode` parameter that hides the existing attachment/mic/
game controls, following the exact `_ChatAttachScrim` dark-backdrop
pattern already in the file. A new `AiSessionSheet` screen (pushed via
`MaterialPageRoute`, matching `AssistSheet`'s own convention) hosts
preparation, approval, the live transcript, and Nearby staging. Long-press
Assist's "Get ideas" choice in `AskAttuneModeSheet` is repointed to open
`AiSessionSheet` pre-seeded with the selected message, rather than
`AssistSheet`'s own single-shot flow — `AssistSheet` itself is NOT deleted
(Nearby-only single-shot and the private-draft-without-a-session flow it
implements remain reachable exactly as today; only the "Get ideas" choice's
destination changes).

**Tech Stack:** Flutter, Riverpod (`.autoDispose` providers matching the
existing `assistDraftProvider`/`understandResultProvider` convention),
Supabase Realtime (`.channel('ai_session_hint:<user id>').onBroadcast(...)`
per Plan C Task 6's server-side authorization), the existing
`ChatFeatureFlags`/`FutureProvider<bool>` flag pattern.

**Spec:** `docs/superpowers/specs/2026-09-22-ai-sessions-design.md` §3.3
(composer behavior), §4.1 (command list — this plan is the only caller of
every one), §5.3 (rendering each output kind), §9 (client integration —
this plan's central chapter), §10 (error contract — client-side handling
of every code), §12 (rollout flags). Read Plan C in full
(`docs/superpowers/plans/2026-09-22-ai-sessions-plan-c-edge-function-and-safety.md`)
before Task 1 — every request/response shape this plan sends and parses
is defined there, including its own two flagged follow-up tasks (consent
gating, Nearby source-card validation) which **must be confirmed merged**
before this plan's Task 6 (Nearby) is trusted to reject malformed source
cards the server should already have rejected.

## Global Constraints

- **Every provider this plan introduces for session state is
  `.autoDispose`**, matching `assistDraftProvider`/
  `understandResultProvider`'s own documented reasoning
  (`ai_assistant_providers.dart`'s file header): no session's turns are
  ever readable as context for a later, unrelated session — a stale
  singleton would be exactly the kind of leak the base spec's "no
  previous assistant result is context for a later call" rule exists to
  prevent, now applied to Sessions' own turn history.
- **The composer's ordinary chat draft and the AI session's own
  instruction field are separate `TextEditingController`s.** Toggling
  into AI mode must never copy, clear, or reinterpret whatever the user
  had typed in the ordinary composer, and vice versa (spec §3.3:
  "toggling AI must not reinterpret or transmit an existing chat
  draft").
- **No in-progress prompt text is ever shown on the partner's device.**
  A shared session's transcript renderer subscribes to committed turns
  only (via `read` after a Realtime hint, never a live-typing stream) —
  there is no code path in this plan that broadcasts keystroke-level
  state.
- **Every error code in Plan C's `SessionErrorCode` union has a distinct
  UI treatment**, per spec §10's table — a generic "Something went
  wrong" catch-all for a code this plan doesn't specifically handle is a
  plan defect; if a new task discovers a code with no assigned UI
  behavior, stop and add one rather than falling through to a generic
  message.
- **Never call any Sessions RPC directly from Flutter.** Every one of
  Plan B's RPCs is `service_role`-only (Plan B/C's own Global
  Constraints) — this plan's repository calls ONLY the `ai-sessions`
  edge function's nine commands, never `supabase.rpc('admit_ai_session_generation', ...)`
  or similar. If a task in this plan finds itself reaching for
  `.rpc(...)` on a session table/function, that is a plan defect — the
  fix is always "route through `AiSessionRepository`'s `_invoke` call to
  the edge function," never a direct RPC call bypassing it.
- **Flags default to their safe-off value on any read failure**,
  matching `ChatFeatureFlags.isEnabled`'s existing `try/catch ->
  safeDefault` behavior exactly — never `true` on a network error.

---

### Task 1: `AiSessionError` and `AiSessionRepository` skeleton

**Files:**
- Create: `lib/features/ai_assistant/data/repositories/ai_session_error.dart`
- Create: `lib/features/ai_assistant/data/repositories/ai_session_repository.dart`
- Test: `test/features/ai_assistant/ai_session_repository_test.dart`

**Interfaces:**
- Consumes: `AiAssistantGateway` (existing, `ai_assistant_repository.dart`).
- Produces: `sealed class AiSessionError implements Exception` with one
  subtype per Plan C `SessionErrorCode` value (`AiSessionUnavailableError`,
  `AiSessionConsentRequiredError`, `AiSessionApprovalRequiredError`,
  `AiSessionContextChangedError`, `AiSessionInvalidInputError`,
  `AiSessionContextTooLargeError`, `AiSessionRequestConflictError`,
  `AiSessionBusyError`, `AiSessionLimitReachedError`,
  `AiSessionRateLimitedError(int? retryAfterSeconds)`,
  `AiSessionOverloadedError`, `AiSessionLocationRequiredError`,
  `AiSessionLocationExpiredError`, `AiSessionRequestFailedError`,
  `AiSessionProviderUnavailableError`, `AiSessionResultUnavailableError`,
  `AiSessionFeatureDisabledError`, `AiSessionInternalError`),
  `AiSessionError.fromCode(String code, {int? retryAfterSeconds})`
  factory — mirrors `AssistantError.fromCode`'s exact pattern
  (`assistant_error.dart:44`).
- Produces: `class AiSessionRepository` with `const AiSessionRepository(this._gateway)`,
  reusing the existing `AiAssistantGateway` type (no new gateway
  abstraction — Sessions' edge function calls are structurally identical
  to `ai-assist`'s: one `invokeFunction` call, JSON body in, JSON body
  out).

- [ ] **Step 1: Write the failing test**

Create `test/features/ai_assistant/ai_session_repository_test.dart`:

```dart
// test/features/ai_assistant/ai_session_repository_test.dart
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_error.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements AiAssistantGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> functionHandlers;
  const _FakeGateway({this.functionHandlers = const {}});

  @override
  Future<dynamic> invokeFunction(String functionName, {Map<String, dynamic>? body}) async {
    final handler = functionHandlers[functionName];
    if (handler == null) {
      throw StateError('No fake handler registered for function $functionName');
    }
    return handler(body);
  }

  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) {
    throw StateError('AiSessionRepository must never call .rpc() directly');
  }

  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) {
    throw UnimplementedError();
  }
}

void main() {
  test('prepare() sends the exact command/kind/visibility shape and returns sessionId/revision', () async {
    Map<String, dynamic>? sentBody;
    final gateway = _FakeGateway(functionHandlers: {
      'ai-sessions': (body) {
        sentBody = body;
        return {'session_id': 'sess-1', 'revision': 1, 'created': true};
      },
    });
    final repository = AiSessionRepository(gateway);

    final result = await repository.prepare(
      idempotencyKey: 'idem-1',
      relationshipId: 'rel-1',
      kind: 'ideas',
      visibility: 'private',
    );

    expect(sentBody?['command'], 'prepare');
    expect(sentBody?['relationship_id'], 'rel-1');
    expect(sentBody?['kind'], 'ideas');
    expect(sentBody?['visibility'], 'private');
    expect(result.sessionId, 'sess-1');
    expect(result.revision, 1);
    expect(result.created, true);
  });

  test('a SESSION_BUSY response throws AiSessionBusyError, not a generic exception', () async {
    final gateway = _FakeGateway(functionHandlers: {
      'ai-sessions': (_) => throw _FakeFunctionException({'code': 'SESSION_BUSY'}),
    });
    final repository = AiSessionRepository(gateway);

    expect(
      () => repository.generate(
        sessionId: 'sess-1',
        requestId: 'req-1',
        expectedRevision: 1,
        userInstruction: 'brainstorm ideas',
      ),
      throwsA(isA<AiSessionBusyError>()),
    );
  });

  test('a RATE_LIMITED response carries retry_after_seconds through to the error', () async {
    final gateway = _FakeGateway(functionHandlers: {
      'ai-sessions': (_) => throw _FakeFunctionException({'code': 'RATE_LIMITED', 'retry_after_seconds': 42}),
    });
    final repository = AiSessionRepository(gateway);

    try {
      await repository.generate(
        sessionId: 'sess-1',
        requestId: 'req-1',
        expectedRevision: 1,
        userInstruction: 'brainstorm ideas',
      );
      fail('expected AiSessionRateLimitedError');
    } on AiSessionRateLimitedError catch (e) {
      expect(e.retryAfterSeconds, 42);
    }
  });
}

/// A minimal stand-in for whatever real exception type
/// SupabaseAiAssistantGateway.invokeFunction throws on a non-2xx
/// response -- AiAssistantRepository's own existing `_invoke` helper
/// (ai_assistant_repository.dart) already has real logic for unwrapping
/// this; AiSessionRepository's own `_invoke` (Step 3 below) must be
/// written against THAT real unwrapping logic, not this fake, once
/// Step 3 is implemented -- this fake only proves the ERROR MAPPING
/// (code string -> AiSessionError subtype), not the transport unwrap.
class _FakeFunctionException implements Exception {
  final Map<String, dynamic> body;
  const _FakeFunctionException(this.body);
}
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd /Users/user/attune && flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -20
```

Expected: fails with `Target of URI doesn't exist` for both new files.

- [ ] **Step 3: Read `AiAssistantRepository`'s real `_invoke` unwrapping logic before writing `AiSessionError`/`AiSessionRepository`**

```bash
grep -n "_invoke\|FunctionException\|_call\b" lib/features/ai_assistant/data/repositories/ai_assistant_repository.dart
```

Read the full body of `_invoke` and `_call` in that file (they are the
existing, real error-unwrapping logic this plan's own equivalents must
match exactly — do not re-derive a different unwrapping shape). Confirm:
what exception type `_supabase.functions.invoke(...)` throws on a non-2xx
response in this codebase's actual Supabase client version, and how the
existing code extracts a `code` field and an optional
`retry_after_seconds` from it.

- [ ] **Step 4: Write `AiSessionError`**

Create `lib/features/ai_assistant/data/repositories/ai_session_error.dart`,
mirroring `assistant_error.dart`'s exact structure (sealed class, one
`const factory` per code, a `fromCode` factory with a `default: throw
AiSessionInternalError()` fallback for any code Plan C's own union
doesn't cover — matching `AssistantError.fromCode`'s own defensive
default). Every `SessionErrorCode` value from Plan C Task 1 gets exactly
one subtype; do not add a subtype for a code Plan C does not define.

```dart
// lib/features/ai_assistant/data/repositories/ai_session_error.dart

/// Mirrors AssistantError's exact shape (assistant_error.dart) for
/// AiSessionRepository's own edge function, ai-sessions -- one subtype
/// per SessionErrorCode value defined in
/// supabase/functions/ai-sessions/index.ts (Plan C Task 1). Every
/// AiSessionRepository method throws this, never a raw
/// FunctionException/parse exception, so every call site can
/// pattern-match on the sealed type alone.
sealed class AiSessionError implements Exception {
  const AiSessionError();

  const factory AiSessionError.unavailable() = AiSessionUnavailableError;
  const factory AiSessionError.consentRequired() = AiSessionConsentRequiredError;
  const factory AiSessionError.approvalRequired() = AiSessionApprovalRequiredError;
  const factory AiSessionError.contextChanged() = AiSessionContextChangedError;
  const factory AiSessionError.invalidInput() = AiSessionInvalidInputError;
  const factory AiSessionError.contextTooLarge() = AiSessionContextTooLargeError;
  const factory AiSessionError.requestConflict() = AiSessionRequestConflictError;
  const factory AiSessionError.busy() = AiSessionBusyError;
  const factory AiSessionError.limitReached() = AiSessionLimitReachedError;
  const factory AiSessionError.rateLimited(int? retryAfterSeconds) =
      AiSessionRateLimitedError;
  const factory AiSessionError.overloaded() = AiSessionOverloadedError;
  const factory AiSessionError.locationRequired() = AiSessionLocationRequiredError;
  const factory AiSessionError.locationExpired() = AiSessionLocationExpiredError;
  const factory AiSessionError.requestFailed() = AiSessionRequestFailedError;
  const factory AiSessionError.providerUnavailable() = AiSessionProviderUnavailableError;
  const factory AiSessionError.resultUnavailable() = AiSessionResultUnavailableError;
  const factory AiSessionError.featureDisabled() = AiSessionFeatureDisabledError;
  const factory AiSessionError.internalError() = AiSessionInternalError;

  factory AiSessionError.fromCode(String code, {int? retryAfterSeconds}) {
    switch (code) {
      case 'UNAVAILABLE':
        return const AiSessionError.unavailable();
      case 'CONSENT_REQUIRED':
        return const AiSessionError.consentRequired();
      case 'APPROVAL_REQUIRED':
        return const AiSessionError.approvalRequired();
      case 'CONTEXT_CHANGED':
        return const AiSessionError.contextChanged();
      case 'INVALID_INPUT':
        return const AiSessionError.invalidInput();
      case 'CONTEXT_TOO_LARGE':
        return const AiSessionError.contextTooLarge();
      case 'REQUEST_CONFLICT':
        return const AiSessionError.requestConflict();
      case 'SESSION_BUSY':
        return const AiSessionError.busy();
      case 'SESSION_LIMIT_REACHED':
        return const AiSessionError.limitReached();
      case 'RATE_LIMITED':
        return AiSessionError.rateLimited(retryAfterSeconds);
      case 'OVERLOADED':
        return const AiSessionError.overloaded();
      case 'LOCATION_REQUIRED':
        return const AiSessionError.locationRequired();
      case 'LOCATION_EXPIRED':
        return const AiSessionError.locationExpired();
      case 'REQUEST_FAILED':
        return const AiSessionError.requestFailed();
      case 'PROVIDER_UNAVAILABLE':
        return const AiSessionError.providerUnavailable();
      case 'RESULT_UNAVAILABLE':
        return const AiSessionError.resultUnavailable();
      case 'FEATURE_DISABLED':
        return const AiSessionError.featureDisabled();
      default:
        return const AiSessionError.internalError();
    }
  }
}

class AiSessionUnavailableError extends AiSessionError {
  const AiSessionUnavailableError();
}
class AiSessionConsentRequiredError extends AiSessionError {
  const AiSessionConsentRequiredError();
}
class AiSessionApprovalRequiredError extends AiSessionError {
  const AiSessionApprovalRequiredError();
}
class AiSessionContextChangedError extends AiSessionError {
  const AiSessionContextChangedError();
}
class AiSessionInvalidInputError extends AiSessionError {
  const AiSessionInvalidInputError();
}
class AiSessionContextTooLargeError extends AiSessionError {
  const AiSessionContextTooLargeError();
}
class AiSessionRequestConflictError extends AiSessionError {
  const AiSessionRequestConflictError();
}
class AiSessionBusyError extends AiSessionError {
  const AiSessionBusyError();
}
class AiSessionLimitReachedError extends AiSessionError {
  const AiSessionLimitReachedError();
}
class AiSessionRateLimitedError extends AiSessionError {
  final int? retryAfterSeconds;
  const AiSessionRateLimitedError(this.retryAfterSeconds);
}
class AiSessionOverloadedError extends AiSessionError {
  const AiSessionOverloadedError();
}
class AiSessionLocationRequiredError extends AiSessionError {
  const AiSessionLocationRequiredError();
}
class AiSessionLocationExpiredError extends AiSessionError {
  const AiSessionLocationExpiredError();
}
class AiSessionRequestFailedError extends AiSessionError {
  const AiSessionRequestFailedError();
}
class AiSessionProviderUnavailableError extends AiSessionError {
  const AiSessionProviderUnavailableError();
}
class AiSessionResultUnavailableError extends AiSessionError {
  const AiSessionResultUnavailableError();
}
class AiSessionFeatureDisabledError extends AiSessionError {
  const AiSessionFeatureDisabledError();
}
class AiSessionInternalError extends AiSessionError {
  const AiSessionInternalError();
}
```

- [ ] **Step 5: Write `AiSessionRepository`**

Create `lib/features/ai_assistant/data/repositories/ai_session_repository.dart`,
using the SAME error-unwrapping logic Step 3 found in
`ai_assistant_repository.dart`'s own `_invoke` (do not write a second,
different unwrap — copy that exact logic, adjusted only to throw
`AiSessionError` instead of `AssistantError`):

```dart
// lib/features/ai_assistant/data/repositories/ai_session_repository.dart
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/data/repositories/ai_session_error.dart';

/// Result of a 'prepare' command (spec §4.1, Plan C Task 2).
class AiSessionPrepareResult {
  final String sessionId;
  final int revision;
  final bool created;
  const AiSessionPrepareResult({
    required this.sessionId,
    required this.revision,
    required this.created,
  });
}

/// Domain/repository layer over the ai-sessions edge function's nine
/// commands (Plan C). Every method throws AiSessionError, never a raw
/// FunctionException/parse exception, mirroring
/// AiAssistantRepository's own promise for AssistantError.
///
/// Deliberately does NOT extend or wrap AiAssistantRepository -- the
/// two are siblings over the same AiAssistantGateway seam, not a
/// hierarchy, since Sessions and single-shot Assist/Understand have
/// different error unions and different command shapes even though
/// they share a transport.
class AiSessionRepository {
  final AiAssistantGateway _gateway;
  const AiSessionRepository(this._gateway);

  Future<AiSessionPrepareResult> prepare({
    required String idempotencyKey,
    required String relationshipId,
    required String kind,
    required String visibility,
    String? targetMessageId,
    bool includeWindow = false,
  }) {
    return _invoke(
      command: 'prepare',
      body: {
        'idempotency_key': idempotencyKey,
        'relationship_id': relationshipId,
        'kind': kind,
        'visibility': visibility,
        'target_message_id': targetMessageId,
        'include_window': includeWindow,
      },
      onResult: (data) => AiSessionPrepareResult(
        sessionId: data['session_id'] as String,
        revision: data['revision'] as int,
        created: data['created'] as bool,
      ),
    );
  }

  // Task 3 adds reviewContext/approve/start.
  // Task 4 adds generate.
  // Task 5 adds read.
  // Task 6 adds publishNearby/discardNearby.
  // Task 7 adds end/shareAnswer.

  Future<T> _invoke<T>({
    required String command,
    required Map<String, dynamic> body,
    required T Function(Map<String, dynamic> data) onResult,
  }) async {
    try {
      final data = await _gateway.invokeFunction('ai-sessions', body: {
        'command': command,
        ...body,
      });
      return onResult(Map<String, dynamic>.from(data as Map));
    } catch (error) {
      // Step 3's own reading of AiAssistantRepository's real _invoke
      // determines the EXACT shape here -- this comment is a
      // placeholder for "copy that logic," not a description of logic
      // that differs from it. Extract `code`/`retry_after_seconds` the
      // same way, then:
      // throw AiSessionError.fromCode(code, retryAfterSeconds: retryAfterSeconds);
      rethrow; // REPLACE with the real unwrap once Step 3 is complete.
    }
  }
}
```

**This step's `_invoke` body is intentionally incomplete** — it is a
placeholder that must be replaced with the real unwrap logic Step 3
found, before this task is considered done. This is flagged explicitly
rather than silently left as `rethrow`, which would make every one of
this task's own error-mapping tests (Step 1) fail.

- [ ] **Step 6: Complete the real unwrap, then run the tests**

Replace the placeholder in `_invoke`'s `catch` block with the exact logic
read in Step 3 (this plan cannot show the literal code here without
having read the live file first — that is Step 3's own purpose). Then:

```bash
flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -30
```

Expected: PASS (3 tests). If the `_FakeFunctionException` stand-in from
Step 1 does not match the REAL exception shape `invokeFunction` throws in
this codebase, fix the fake to match reality (never the reverse — the
fake exists to simulate the real transport, not to define it).

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/features/ai_assistant/data/repositories/ai_session_error.dart \
  lib/features/ai_assistant/data/repositories/ai_session_repository.dart \
  test/features/ai_assistant/ai_session_repository_test.dart
git add lib/features/ai_assistant/data/repositories/ai_session_error.dart \
        lib/features/ai_assistant/data/repositories/ai_session_repository.dart \
        test/features/ai_assistant/ai_session_repository_test.dart
git commit -m "feat(ai-sessions): add AiSessionError and AiSessionRepository skeleton with prepare()"
```

---

### Task 2: Session domain models — `AiSession`, `AiSessionTurn`

**Files:**
- Create: `lib/features/ai_assistant/data/models/ai_session_turn_model.dart`
- Test: `test/features/ai_assistant/ai_session_turn_model_test.dart`

**Interfaces:**
- Produces: `sealed class AiSessionTurnModel` with two subtypes —
  `AiSessionUserTurn(int ordinal, String instruction)` and
  `AiSessionAttuneTurn` (itself sealed:
  `AiSessionIdeasAnswerTurn(int ordinal, String replyText,
  SuggestedPlanningItem? suggestedPlanningItem)`,
  `AiSessionRedirectTurn(int ordinal, String reason, List<String> offered)`,
  `AiSessionNearbyResultTurn(int ordinal, String replyText, List<PlaceSourceModel> sources)`)
  — mirrors `AssistDraftModel`'s sealed-on-discriminant pattern exactly
  (`assist_draft_model.dart`), reusing the EXISTING `PlaceSourceModel`
  and `SuggestedPlanningItem` types from `place_source_model.dart`/
  `assist_draft_model.dart` rather than redefining them — Sessions'
  output shapes are supersets of Assist's, not a parallel vocabulary.
  Parses from `read_ai_session_turns`' row shape via Plan C's `'read'`
  command response (`{turns: [...]}`).
- Produces: **no `AiSession` model class in this plan** — a session's own
  metadata (`kind`/`visibility`/`state`/`revision`) is carried directly
  by `AiSessionPrepareResult` (Task 1) plus whatever `'start'`/`'read'`
  responses return; introducing a third redundant model wrapping the
  same four fields would violate this plan's own DRY discipline. If a
  later task in this plan finds it genuinely needs a richer session
  object (e.g. the sheet's own state class), that is UI state, not a
  data model, and belongs in that task's own `State` class, not here.

- [ ] **Step 1: Write the failing test**

Create `test/features/ai_assistant/ai_session_turn_model_test.dart`:

```dart
// test/features/ai_assistant/ai_session_turn_model_test.dart
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a user turn', () {
    final turn = AiSessionTurnModel.fromJson({
      'ordinal': 1,
      'role': 'user',
      'kind': 'ideas_answer',
      'payload': {'instruction': 'brainstorm date ideas'},
    });
    expect(turn, isA<AiSessionUserTurn>());
    expect((turn as AiSessionUserTurn).instruction, 'brainstorm date ideas');
    expect(turn.ordinal, 1);
  });

  test('parses an attune ideas_answer turn with a suggested planning item', () {
    final turn = AiSessionTurnModel.fromJson({
      'ordinal': 2,
      'role': 'attune',
      'kind': 'ideas_answer',
      'payload': {
        'reply_text': 'Try a picnic this weekend.',
        'suggested_planning_item': {
          'kind': 'event',
          'title': 'Picnic',
          'event_date': '2026-09-27',
        },
      },
    });
    expect(turn, isA<AiSessionIdeasAnswerTurn>());
    final ideas = turn as AiSessionIdeasAnswerTurn;
    expect(ideas.replyText, 'Try a picnic this weekend.');
    expect(ideas.suggestedPlanningItem?.title, 'Picnic');
  });

  test('parses a redirect turn', () {
    final turn = AiSessionTurnModel.fromJson({
      'ordinal': 4,
      'role': 'attune',
      'kind': 'redirect',
      'payload': {'reason': 'unsupported', 'offered': ['ideas']},
    });
    expect(turn, isA<AiSessionRedirectTurn>());
    expect((turn as AiSessionRedirectTurn).offered, ['ideas']);
  });

  test('parses a nearby_result turn with source cards', () {
    final turn = AiSessionTurnModel.fromJson({
      'ordinal': 6,
      'role': 'attune',
      'kind': 'nearby_result',
      'payload': {
        'reply_text': 'A few places nearby.',
        'sources': [
          {
            'provider_id': 'p1',
            'name': 'Cafe One',
            'formatted_address': '1 Main St',
            'category': 'cafe',
            'map_url': 'https://www.mapbox.com/search/p1',
          },
        ],
      },
    });
    expect(turn, isA<AiSessionNearbyResultTurn>());
    expect((turn as AiSessionNearbyResultTurn).sources.single.name, 'Cafe One');
  });

  test('throws FormatException for an unrecognized kind rather than silently returning null', () {
    expect(
      () => AiSessionTurnModel.fromJson({
        'ordinal': 1, 'role': 'attune', 'kind': 'nonsense', 'payload': {},
      }),
      throwsFormatException,
    );
  });
}
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
flutter test test/features/ai_assistant/ai_session_turn_model_test.dart 2>&1 | tail -10
```

Expected: `Target of URI doesn't exist`

- [ ] **Step 3: Write the model**

Create `lib/features/ai_assistant/data/models/ai_session_turn_model.dart`:

```dart
// lib/features/ai_assistant/data/models/ai_session_turn_model.dart
import 'assist_draft_model.dart' show SuggestedPlanningItem;
import 'place_source_model.dart';

/// One row of `read_ai_session_turns` (Plan B/C). Sealed on `role` then
/// `kind`, mirroring AssistDraftModel's sealed-on-discriminant pattern
/// (assist_draft_model.dart) -- throws on any missing/mistyped field
/// rather than defaulting, since this is the boundary where raw server
/// JSON becomes a trusted model (same reasoning as every other
/// `.fromJson` factory in this feature).
sealed class AiSessionTurnModel {
  final int ordinal;
  const AiSessionTurnModel({required this.ordinal});

  factory AiSessionTurnModel.fromJson(Map<String, dynamic> json) {
    final ordinal = json['ordinal'];
    if (ordinal is! int) {
      throw FormatException('AiSessionTurnModel.fromJson: missing ordinal');
    }
    final role = json['role'];
    final kind = json['kind'];
    final payload = json['payload'];
    if (payload is! Map) {
      throw FormatException('AiSessionTurnModel.fromJson: missing payload');
    }
    final payloadMap = Map<String, dynamic>.from(payload);

    if (role == 'user') {
      final instruction = payloadMap['instruction'];
      if (instruction is! String) {
        throw FormatException('AiSessionTurnModel.fromJson: missing user instruction');
      }
      return AiSessionUserTurn(ordinal: ordinal, instruction: instruction);
    }

    if (role != 'attune') {
      throw FormatException('AiSessionTurnModel.fromJson: unrecognized role "$role"');
    }

    switch (kind) {
      case 'ideas_answer':
        final replyText = payloadMap['reply_text'];
        if (replyText is! String) {
          throw FormatException('AiSessionTurnModel.fromJson: missing reply_text');
        }
        final rawItem = payloadMap['suggested_planning_item'];
        SuggestedPlanningItem? suggestedItem;
        if (rawItem != null) {
          suggestedItem = SuggestedPlanningItem.fromJson(Map<String, dynamic>.from(rawItem as Map));
        }
        return AiSessionIdeasAnswerTurn(
          ordinal: ordinal,
          replyText: replyText,
          suggestedPlanningItem: suggestedItem,
        );
      case 'redirect':
        final reason = payloadMap['reason'];
        final offered = payloadMap['offered'];
        if (reason is! String || offered is! List) {
          throw FormatException('AiSessionTurnModel.fromJson: malformed redirect payload');
        }
        return AiSessionRedirectTurn(
          ordinal: ordinal,
          reason: reason,
          offered: offered.map((o) => o as String).toList(growable: false),
        );
      case 'nearby_result':
        final replyText = payloadMap['reply_text'];
        final rawSources = payloadMap['sources'];
        if (replyText is! String || rawSources is! List) {
          throw FormatException('AiSessionTurnModel.fromJson: malformed nearby_result payload');
        }
        final sources = rawSources
            .map((s) => PlaceSourceModel.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(growable: false);
        return AiSessionNearbyResultTurn(ordinal: ordinal, replyText: replyText, sources: sources);
      default:
        throw FormatException('AiSessionTurnModel.fromJson: unrecognized kind "$kind"');
    }
  }
}

class AiSessionUserTurn extends AiSessionTurnModel {
  final String instruction;
  const AiSessionUserTurn({required super.ordinal, required this.instruction});
}

sealed class AiSessionAttuneTurn extends AiSessionTurnModel {
  const AiSessionAttuneTurn({required super.ordinal});
}

class AiSessionIdeasAnswerTurn extends AiSessionAttuneTurn {
  final String replyText;
  final SuggestedPlanningItem? suggestedPlanningItem;
  const AiSessionIdeasAnswerTurn({
    required super.ordinal,
    required this.replyText,
    this.suggestedPlanningItem,
  });
}

class AiSessionRedirectTurn extends AiSessionAttuneTurn {
  final String reason;
  final List<String> offered;
  const AiSessionRedirectTurn({
    required super.ordinal,
    required this.reason,
    required this.offered,
  });
}

class AiSessionNearbyResultTurn extends AiSessionAttuneTurn {
  final String replyText;
  final List<PlaceSourceModel> sources;
  const AiSessionNearbyResultTurn({
    required super.ordinal,
    required this.replyText,
    required this.sources,
  });
}
```

- [ ] **Step 4: Run to confirm it passes**

```bash
flutter test test/features/ai_assistant/ai_session_turn_model_test.dart 2>&1 | tail -20
```

Expected: PASS (5 tests)

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze lib/features/ai_assistant/data/models/ai_session_turn_model.dart
git add lib/features/ai_assistant/data/models/ai_session_turn_model.dart \
        test/features/ai_assistant/ai_session_turn_model_test.dart
git commit -m "feat(ai-sessions): add AiSessionTurnModel sealed on role/kind"
```

---

### Task 3: Complete `AiSessionRepository` — reviewContext/approve/start/read/end/shareAnswer

**Files:**
- Modify: `lib/features/ai_assistant/data/repositories/ai_session_repository.dart`
- Modify: `test/features/ai_assistant/ai_session_repository_test.dart`

**Interfaces:**
- Consumes: `AiSessionTurnModel` (Task 2).
- Produces: `reviewContext({required String sessionId, required String relationshipId, required int utcOffsetMinutes}) -> Future<({List<String> window, String digest})>`,
  `approve({required String sessionId, required int revision, required String digest}) -> Future<void>`,
  `start({required String sessionId, required int revision}) -> Future<({bool activated, String state})>`,
  `read(String sessionId) -> Future<List<AiSessionTurnModel>>`,
  `end(String sessionId) -> Future<void>`,
  `shareAnswer({required String sessionId, required int ordinal}) -> Future<String>` (returns the new
  `message_id`).

- [ ] **Step 1: Write the failing tests** — one per new method, following
  Task 1 Step 1's exact `_FakeGateway` pattern (sent-body assertion +
  parsed-result assertion for the success case; one error-mapping case
  reused from Task 1's coverage is enough — this task does not need to
  re-prove error mapping for every method, since `_invoke`'s unwrap logic
  is shared and already covered).

```dart
// Add to test/features/ai_assistant/ai_session_repository_test.dart

test('reviewContext sends session_id/relationship_id/utc_offset_minutes and parses window/digest', () async {
  Map<String, dynamic>? sentBody;
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (body) {
      sentBody = body;
      return {
        'window': [{'content': 'hi', 'truncated': false}],
        'digest': 'abc123',
      };
    },
  });
  final repository = AiSessionRepository(gateway);

  final result = await repository.reviewContext(
    sessionId: 'sess-1', relationshipId: 'rel-1', utcOffsetMinutes: 0,
  );

  expect(sentBody?['command'], 'review_context');
  expect(result.digest, 'abc123');
  expect(result.window, ['hi']);
});

test('approve sends session_id/revision/digest', () async {
  Map<String, dynamic>? sentBody;
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (body) {
      sentBody = body;
      return {'approved': true};
    },
  });
  await AiSessionRepository(gateway).approve(sessionId: 'sess-1', revision: 1, digest: 'abc123');
  expect(sentBody?['command'], 'approve');
  expect(sentBody?['digest'], 'abc123');
});

test('start returns activated/state and throws AiSessionApprovalRequiredError when not all approvals exist', () async {
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (_) => throw _FakeFunctionException({'code': 'APPROVAL_REQUIRED'}),
  });
  expect(
    () => AiSessionRepository(gateway).start(sessionId: 'sess-1', revision: 1),
    throwsA(isA<AiSessionApprovalRequiredError>()),
  );
});

test('read parses a list of turns', () async {
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (_) => {
      'turns': [
        {'ordinal': 1, 'role': 'user', 'kind': 'ideas_answer', 'payload': {'instruction': 'hi'}},
      ],
    },
  });
  final turns = await AiSessionRepository(gateway).read('sess-1');
  expect(turns, hasLength(1));
  expect(turns.single, isA<AiSessionUserTurn>());
});

test('end sends session_id and returns void', () async {
  Map<String, dynamic>? sentBody;
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (body) { sentBody = body; return {'ended': true}; },
  });
  await AiSessionRepository(gateway).end('sess-1');
  expect(sentBody?['command'], 'end');
});

test('shareAnswer returns the new message id', () async {
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (_) => {'message_id': 'msg-1'},
  });
  final messageId = await AiSessionRepository(gateway).shareAnswer(sessionId: 'sess-1', ordinal: 2);
  expect(messageId, 'msg-1');
});
```

Add the missing import to the test file:

```dart
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
```

- [ ] **Step 2: Run to confirm all six fail**

```bash
flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -30
```

Expected: fails — the six new methods don't exist yet.

- [ ] **Step 3: Implement the six methods**

Add to `ai_session_repository.dart`, replacing the "Task 3/4/5/6/7 adds
..." comments:

```dart
  Future<({List<String> window, String digest})> reviewContext({
    required String sessionId,
    required String relationshipId,
    required int utcOffsetMinutes,
  }) {
    return _invoke(
      command: 'review_context',
      body: {
        'session_id': sessionId,
        'relationship_id': relationshipId,
        'utc_offset_minutes': utcOffsetMinutes,
      },
      onResult: (data) {
        final rawWindow = data['window'] as List;
        return (
          window: rawWindow
              .map((w) => (Map<String, dynamic>.from(w as Map))['content'] as String)
              .toList(growable: false),
          digest: data['digest'] as String,
        );
      },
    );
  }

  Future<void> approve({
    required String sessionId,
    required int revision,
    required String digest,
  }) {
    return _invoke(
      command: 'approve',
      body: {'session_id': sessionId, 'revision': revision, 'digest': digest},
      onResult: (_) {},
    );
  }

  Future<({bool activated, String state})> start({
    required String sessionId,
    required int revision,
  }) {
    return _invoke(
      command: 'start',
      body: {'session_id': sessionId, 'revision': revision},
      onResult: (data) => (
        activated: data['activated'] as bool,
        state: data['state'] as String,
      ),
    );
  }

  Future<List<AiSessionTurnModel>> read(String sessionId) {
    return _invoke(
      command: 'read',
      body: {'session_id': sessionId},
      onResult: (data) {
        final rawTurns = data['turns'] as List;
        return rawTurns
            .map((t) => AiSessionTurnModel.fromJson(Map<String, dynamic>.from(t as Map)))
            .toList(growable: false);
      },
    );
  }

  Future<void> end(String sessionId) {
    return _invoke(
      command: 'end',
      body: {'session_id': sessionId},
      onResult: (_) {},
    );
  }

  Future<String> shareAnswer({required String sessionId, required int ordinal}) {
    return _invoke(
      command: 'share_answer',
      body: {'session_id': sessionId, 'ordinal': ordinal},
      onResult: (data) => data['message_id'] as String,
    );
  }
```

Add the needed import at the top of the file:

```dart
import 'package:attune/features/ai_assistant/data/models/ai_session_turn_model.dart';
```

- [ ] **Step 4: Run to confirm all pass**

```bash
flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -30
```

Expected: PASS (9 tests total: 3 from Task 1 + 6 new)

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze lib/features/ai_assistant/data/repositories/ai_session_repository.dart
git add lib/features/ai_assistant/data/repositories/ai_session_repository.dart \
        test/features/ai_assistant/ai_session_repository_test.dart
git commit -m "feat(ai-sessions): complete AiSessionRepository with reviewContext/approve/start/read/end/shareAnswer"
```

---

### Task 4: `generate` and Nearby-specific repository methods

**Files:**
- Modify: `lib/features/ai_assistant/data/repositories/ai_session_repository.dart`
- Modify: `test/features/ai_assistant/ai_session_repository_test.dart`

**Interfaces:**
- Consumes: `RequesterLocation` (existing, `ai_assistant_repository.dart:20`).
- Produces: `generate({required String sessionId, required String requestId, required int expectedRevision, required String userInstruction, RequesterLocation? requesterLocation}) -> Future<AiSessionTurnModel>` (parses
  whichever of `answer`/`redirect` shape Plan C's `generate` command
  returned into the matching `AiSessionAttuneTurn` subtype — NOT the
  Nearby staging shape, which is a different response — see below),
  `publishNearby(String requestId) -> Future<AiSessionTurnModel>`,
  `discardNearby(String requestId) -> Future<void>`.

**A genuine design question resolved here, not silently assumed:**
Plan C's `generate` command has two different response shapes depending
on `kind` (Ideas/redirect: `{user_ordinal, attune_ordinal, reply_text,
suggested_planning_item}`) versus Nearby (which — per Plan C Task 4's own
scope note — currently only implements the Ideas path fully; Plan C's
own self-review flagged Nearby's `generate` wiring and source-card
validation as its own follow-up Task 9). **This task's `generate` method
handles the Ideas/redirect response shape only**, matching what Plan C
actually ships as of its own Task 4/5. A Nearby-specific `generate` call
returns a STAGED result (not a committed turn) per spec §6.1 — the
client's next action is `publishNearby`/`discardNearby`, not rendering a
turn directly. **Confirm Plan C's Task 9 (Nearby source-card validation)
is merged, and read its actual `generate`-command Nearby response shape
from the live `ai-sessions/index.ts` file, before implementing this
task's Nearby handling** — do not guess the shape from this plan's own
description of Plan C alone.

- [ ] **Step 1: Write the failing tests**

```dart
test('generate parses an ideas_answer response into AiSessionIdeasAnswerTurn', () async {
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (_) => {
      'user_ordinal': 1,
      'attune_ordinal': 2,
      'reply_text': 'Try a picnic.',
      'suggested_planning_item': null,
    },
  });
  final turn = await AiSessionRepository(gateway).generate(
    sessionId: 'sess-1', requestId: 'req-1', expectedRevision: 1, userInstruction: 'ideas please',
  );
  expect(turn, isA<AiSessionIdeasAnswerTurn>());
  expect((turn as AiSessionIdeasAnswerTurn).ordinal, 2);
});

test('generate parses a redirect response into AiSessionRedirectTurn', () async {
  final gateway = _FakeGateway(functionHandlers: {
    'ai-sessions': (_) => {'kind': 'redirect', 'reason': 'unsupported', 'offered': ['nearby']},
  });
  final turn = await AiSessionRepository(gateway).generate(
    sessionId: 'sess-1', requestId: 'req-1', expectedRevision: 1, userInstruction: 'news today',
  );
  expect(turn, isA<AiSessionRedirectTurn>());
});
```

- [ ] **Step 2: Run to confirm it fails**

```bash
flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -20
```

- [ ] **Step 3: Implement `generate`**

Add to `ai_session_repository.dart`:

```dart
  Future<AiSessionAttuneTurn> generate({
    required String sessionId,
    required String requestId,
    required int expectedRevision,
    required String userInstruction,
    RequesterLocation? requesterLocation,
  }) {
    return _invoke(
      command: 'generate',
      body: {
        'session_id': sessionId,
        'request_id': requestId,
        'expected_revision': expectedRevision,
        'user_instruction': userInstruction,
        'requester_location': requesterLocation == null
            ? null
            : {
                'latitude': requesterLocation.latitude,
                'longitude': requesterLocation.longitude,
                'accuracy_m': requesterLocation.accuracyM,
              },
      },
      onResult: (data) {
        if (data['kind'] == 'redirect') {
          return AiSessionRedirectTurn(
            ordinal: -1, // a redirect is never committed as a real turn -- no ordinal exists for it
            reason: data['reason'] as String,
            offered: (data['offered'] as List).map((o) => o as String).toList(growable: false),
          );
        }
        final rawItem = data['suggested_planning_item'];
        return AiSessionIdeasAnswerTurn(
          ordinal: data['attune_ordinal'] as int,
          replyText: data['reply_text'] as String,
          suggestedPlanningItem: rawItem == null
              ? null
              : SuggestedPlanningItem.fromJson(Map<String, dynamic>.from(rawItem as Map)),
        );
      },
    );
  }
```

Add the needed import:

```dart
import 'package:attune/features/ai_assistant/data/models/assist_draft_model.dart' show SuggestedPlanningItem;
```

**Flagged for the implementer:** the `AiSessionRedirectTurn(ordinal: -1,
...)` construction above uses a sentinel ordinal because a redirect from
`generate` (as opposed to one already stored in `ai_session_turns` —
Plan B's own schema DOES allow `kind = 'redirect'` rows per Task 2's
`ai_session_turns.kind` CHECK, but Plan C's `commit_ai_session_ideas_turn`
call in its own `generate` branch is only invoked on the `answer` path,
per Plan C Task 4's own code — a redirect is returned to the caller but
never committed to the turns table at all) has no real ordinal, since
nothing was written. **This is worth a second look**: if Plan C's
eventual behavior changes to also commit redirects as their own turn
kind (contradicting spec §5.3's "Only ordinary unsupported redirects
become transcript pairs... Safety refusals remain requester-only, not
shared transcript events" — meaning SOME redirects DO get committed),
this client-side sentinel-ordinal approach would need revisiting. Read
Plan C's actual shipped `generate` branch behavior for the `redirect`
case before trusting this assumption; it is written here as the most
literal reading of Plan C Task 4's own code sample, not independently
re-verified against a later Plan C revision.

- [ ] **Step 4: Add `publishNearby`/`discardNearby`**

```dart
  Future<AiSessionNearbyResultTurn> publishNearby(String requestId) {
    return _invoke(
      command: 'publish_nearby',
      body: {'request_id': requestId},
      onResult: (data) => AiSessionNearbyResultTurn(
        ordinal: data['attune_ordinal'] as int,
        replyText: data['reply_text'] as String? ?? '',
        sources: const [], // Plan C's own publish_nearby response shape does not echo sources back -- see note below
      ),
    );
  }

  Future<void> discardNearby(String requestId) {
    return _invoke(
      command: 'discard_nearby',
      body: {'request_id': requestId},
      onResult: (_) {},
    );
  }
```

**Flagged gap, not silently resolved:** Plan C Task 5's own
`publish_nearby` response shape (`{user_ordinal, attune_ordinal}`) does
NOT include `reply_text`/`sources` — the client would need a SEPARATE
`read` call after `publishNearby` to actually render the committed
Nearby turn's content. This task's `publishNearby` return type above is
therefore misleading as written (`replyText: '' `, `sources: const
[]`). **Fix required**: either (a) change Plan C's `publish_nearby`
response to echo the committed content back (simplest, avoids an extra
round trip — flag this as a Plan C revision request rather than silently
working around it here), or (b) change this method's return type to
`Future<void>` and require the caller to `read()` afterward. **This
plan proceeds with option (b)** as the change requiring the least
coupling back into Plan C:

```dart
  Future<void> publishNearby(String requestId) {
    return _invoke(
      command: 'publish_nearby',
      body: {'request_id': requestId},
      onResult: (_) {},
    );
  }
```

Update Step 1's test for `publishNearby` accordingly (assert only that
the command was sent correctly, not a parsed turn).

- [ ] **Step 5: Run the full repository test suite**

```bash
flutter test test/features/ai_assistant/ai_session_repository_test.dart 2>&1 | tail -30
```

Expected: PASS (all tests)

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze lib/features/ai_assistant/data/repositories/ai_session_repository.dart
git add lib/features/ai_assistant/data/repositories/ai_session_repository.dart \
        test/features/ai_assistant/ai_session_repository_test.dart
git commit -m "feat(ai-sessions): add generate/publishNearby/discardNearby to AiSessionRepository"
```

---

### Task 5: Rollout flags

**Files:**
- Modify: `lib/features/chat/domain/services/chat_feature_flags.dart`
- Modify: `lib/features/chat/presentation/providers/chat_experience_providers.dart`
- Test: `test/features/chat/chat_feature_flags_test.dart` (create if it
  does not exist; extend if it does)

**Interfaces:**
- Produces: seven new `ChatFeatureFlags` constants matching spec §12
  exactly — `aiAssistBase` (renaming nothing existing; this is the base
  Assist/Understand flag the base spec's own §14.1 already requires but
  which, per this feature's own gate audit, has no confirmed flag today
  — **flagged**: check whether `chat_translatorEntry`/another existing
  flag is ALREADY silently gating Ask Attune before adding a redundant
  one; if none does, this is the fix for the base spec's own "Ask Attune
  is wired live with no flag" finding, in scope here since Sessions
  cannot ship responsibly on top of an still-ungated base), `aiSessionsPrivate`,
  `aiSessionsShared`, `aiSessionsRecentWindow`, `aiSessionsNearby` — all
  defaulting `false` in `_defaults`, matching every existing flag's
  default.
- Produces: five new `FutureProvider<bool>`s in
  `chat_experience_providers.dart`, one per flag, matching
  `chatTranslatorEntryEnabledProvider`'s exact shape.

- [ ] **Step 1: Confirm whether Ask Attune is currently gated by anything**

```bash
grep -n "ChatFeatureFlags\." lib/features/chat/presentation/widgets/message_bubble.dart lib/features/ai_assistant/**/*.dart 2>/dev/null
```

If this returns nothing, the base spec's own gate-audit finding (Sessions
design spec §14: "Ask Attune is already wired live... with no feature
flag guarding it") is confirmed still true. **This task adds the missing
base gate as its first real fix**, not just Sessions' own five new
flags — resolving a cross-cutting gap this whole plan set has surfaced
three times now (spec review, Plan A commit, and here) is more valuable
done once than deferred a fourth time.

- [ ] **Step 2: Write the failing test**

Create or extend `test/features/chat/chat_feature_flags_test.dart`:

```dart
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every new AI flag defaults to false', () {
    // ChatFeatureFlags._defaults is private; this test can only assert
    // through the public isEnabled() surface with a Supabase client that
    // always throws (simulating "row not found" / "network error"),
    // which is exactly the existing test pattern this file's own
    // sibling tests already use for every OTHER flag -- copy that
    // pattern's exact fake-client shape here rather than reaching into
    // a private field.
    expect(ChatFeatureFlags.aiAssistBase, 'chat_ai_assist_base');
    expect(ChatFeatureFlags.aiSessionsPrivate, 'chat_ai_sessions_private');
    expect(ChatFeatureFlags.aiSessionsShared, 'chat_ai_sessions_shared');
    expect(ChatFeatureFlags.aiSessionsRecentWindow, 'chat_ai_sessions_recent_window');
    expect(ChatFeatureFlags.aiSessionsNearby, 'chat_ai_sessions_nearby');
  });
}
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
flutter test test/features/chat/chat_feature_flags_test.dart 2>&1 | tail -20
```

Expected: fails — the five new constants don't exist.

- [ ] **Step 4: Add the flags**

Edit `lib/features/chat/domain/services/chat_feature_flags.dart`:

```dart
  static const String imageSharing = 'chat_image_sharing';
  static const String translatorEntry = 'chat_translator_entry';
  static const String expandedHeaderDrawer = 'chat_expanded_header_drawer';
  static const String voiceMessages = 'chat_voice_messages';
  static const String reactions = 'chat_reactions';
  static const String editDelete = 'chat_edit_delete';
  static const String videoSharing = 'chat_video_sharing';
  static const String linkPreviews = 'chat_link_previews';
  static const String historicalImport = 'chat_historical_import';
  static const String streaks = 'chat_streaks';
  static const String ephemeralVideo = 'chat_ephemeral_video';
  static const String aiAssistBase = 'chat_ai_assist_base';
  static const String aiSessionsPrivate = 'chat_ai_sessions_private';
  static const String aiSessionsShared = 'chat_ai_sessions_shared';
  static const String aiSessionsRecentWindow = 'chat_ai_sessions_recent_window';
  static const String aiSessionsNearby = 'chat_ai_sessions_nearby';

  static const Map<String, bool> _defaults = <String, bool>{
    imageSharing: false,
    translatorEntry: false,
    expandedHeaderDrawer: false,
    voiceMessages: false,
    reactions: false,
    editDelete: false,
    videoSharing: false,
    linkPreviews: false,
    historicalImport: false,
    streaks: false,
    ephemeralVideo: false,
    aiAssistBase: false,
    aiSessionsPrivate: false,
    aiSessionsShared: false,
    aiSessionsRecentWindow: false,
    aiSessionsNearby: false,
  };
```

- [ ] **Step 5: Add the providers**

Edit `lib/features/chat/presentation/providers/chat_experience_providers.dart`:

```dart
final aiAssistBaseEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.aiAssistBase,
  );
});

final aiSessionsPrivateEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.aiSessionsPrivate,
  );
});

final aiSessionsSharedEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.aiSessionsShared,
  );
});

final aiSessionsRecentWindowEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.aiSessionsRecentWindow,
  );
});

final aiSessionsNearbyEnabledProvider = FutureProvider<bool>((ref) {
  return ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.aiSessionsNearby,
  );
});
```

- [ ] **Step 6: Run the test, confirm it passes**

```bash
flutter test test/features/chat/chat_feature_flags_test.dart 2>&1 | tail -20
```

Expected: PASS

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/features/chat/domain/services/chat_feature_flags.dart \
  lib/features/chat/presentation/providers/chat_experience_providers.dart
git add lib/features/chat/domain/services/chat_feature_flags.dart \
        lib/features/chat/presentation/providers/chat_experience_providers.dart \
        test/features/chat/chat_feature_flags_test.dart
git commit -m "feat(ai-sessions): add rollout flags for base Assist and four Sessions subcapabilities"
```

---

### Task 6: Composer AI mode — the button, the scrim, and control hiding

**Files:**
- Modify: `lib/features/chat/presentation/widgets/chat_text_field.dart`
- Test: `test/features/chat/chat_text_field_ai_mode_test.dart`

**Interfaces:**
- Consumes: `aiAssistBaseEnabledProvider` (Task 5).
- Produces: a new `aiMode: bool` parameter (default `false`) on
  `ChatTextField`, and a new `onAiButtonTap: VoidCallback?` parameter.
  When `aiMode` is `true`: the existing attachment button, mic button,
  and game button are not rendered (matching the exact condition the
  existing attachment-menu/mic-record code already gates on — read that
  code before writing this, since duplicating a slightly-different
  condition would be a real bug). The AI button itself uses
  `ComposerSatellite` (existing widget, `chat_text_field.dart:188`),
  following the SAME construction as the existing attachment button.

- [ ] **Step 1: Write the failing test**

Create `test/features/chat/chat_text_field_ai_mode_test.dart`:

```dart
// test/features/chat/chat_text_field_ai_mode_test.dart
//
// Follows chat_screen_header_test.dart's own harness pattern
// (support/chat_test_harness.dart) for pumping a real ChatTextField
// inside a minimal MaterialApp.
import 'package:attune/features/chat/presentation/widgets/chat_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/chat_test_harness.dart';

void main() {
  testWidgets('the AI button is present in the composer', (tester) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: ChatTextField(
              // ... minimal required constructor args, matching this
              // file's own existing widget tests for ChatTextField's
              // required parameter list (read chat_text_field.dart's
              // constructor before filling these in -- do not guess the
              // parameter list).
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget); // or whatever icon this task's Step 3 actually picks
  });

  testWidgets('aiMode:true hides the attachment, mic, and game buttons', (tester) async {
    await tester.pumpWidget(
      withScreenUtil(
        MaterialApp(
          home: Scaffold(
            body: ChatTextField(
              aiMode: true,
              // ... same required args as above
            ),
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.attach_file), findsNothing); // whichever icon the existing attach button uses -- confirm exact icon in Step 2
  });

  testWidgets('exiting AI mode (aiMode:false again) restores every dismissed control', (tester) async {
    // Pump with aiMode:true, then rebuild the SAME widget tree with
    // aiMode:false, and confirm the attachment/mic/game controls are
    // back -- this is the literal spec §3.3 requirement ("Hide
    // unsupported attachment controls in AI mode, restore on exit").
  });
}
```

**This step's test file is intentionally a skeleton with two explicit
"confirm before filling in" markers** — `ChatTextField`'s real
constructor signature and the real attachment button's real icon must be
read from the live file, not guessed, before this test can be completed
and run. This mirrors this plan's own established discipline (Task 1
Step 3) of reading real code before writing code against it, rather than
inventing a plausible-looking API.

- [ ] **Step 2: Read `ChatTextField`'s real constructor and the existing attachment/mic/game control-gating condition**

```bash
sed -n '1,190p' lib/features/chat/presentation/widgets/chat_text_field.dart
grep -n "showAttachButton\|showMicButton\|showGameButton\|_attachActions\|widget\.\|class ChatTextField" lib/features/chat/presentation/widgets/chat_text_field.dart | head -60
```

Complete Step 1's test file with the real constructor arguments and real
icon names found here.

- [ ] **Step 3: Run to confirm it fails**

```bash
flutter test test/features/chat/chat_text_field_ai_mode_test.dart 2>&1 | tail -20
```

Expected: fails — `aiMode` parameter doesn't exist yet.

- [ ] **Step 4: Add the `aiMode`/`onAiButtonTap` parameters and gate existing controls**

In `ChatTextField`'s constructor (near the top of the class, matching
where its other boolean feature-toggle parameters like
`showAttachButton` — confirmed name from Step 2 — already live), add:

```dart
  final bool aiMode;
  final VoidCallback? onAiButtonTap;
```

with `aiMode = false` as the constructor default. Find every place the
existing attachment/mic/game buttons are conditionally built (from Step
2's grep) and add `&& !widget.aiMode` (or `!aiMode` at the appropriate
scope) to each existing condition — do not introduce a SEPARATE
`if (!aiMode)` wrapper around each button if the codebase's existing
pattern is a single boolean flag per button already; extending that
existing flag's own condition is more consistent than layering a second
independent gate.

Add the AI button itself, using the existing `ComposerSatellite` widget
(read its own constructor at `chat_text_field.dart:188` before using it,
matching whatever parameters the existing attachment button already
passes to its own `ComposerSatellite` instance):

```dart
        ComposerSatellite(
          icon: Icons.auto_awesome, // confirm this doesn't collide with an existing icon use elsewhere in the composer row
          onTap: widget.onAiButtonTap,
          tooltip: 'Ask Attune',
        ),
```

- [ ] **Step 5: Run to confirm the tests pass**

```bash
flutter test test/features/chat/chat_text_field_ai_mode_test.dart 2>&1 | tail -30
```

Expected: PASS (3 tests)

- [ ] **Step 6: Run the existing composer test suite to confirm no regression**

```bash
flutter test test/features/chat/ --concurrency=1 2>&1 | tail -20
```

Expected: no new failures. `ChatTextField` is used across many existing
chat tests — a parameter with a `false` default should not change any
existing test's behavior, but this step is the actual proof, not an
assumption.

- [ ] **Step 7: Analyze and commit**

```bash
flutter analyze lib/features/chat/presentation/widgets/chat_text_field.dart
git add lib/features/chat/presentation/widgets/chat_text_field.dart \
        test/features/chat/chat_text_field_ai_mode_test.dart
git commit -m "feat(ai-sessions): add aiMode to ChatTextField, hiding attachment/mic/game controls"
```

---

### Task 7: `AiSessionSheet` — preparation, approval, and the live transcript

**This is the largest UI task in this plan.** Given its size, this task
is itself split into explicit sub-steps rather than a flat TDD loop, but
every sub-step still ends with a runnable widget test.

**Files:**
- Create: `lib/features/ai_assistant/presentation/screens/ai_session_sheet.dart`
- Create: `lib/features/ai_assistant/presentation/providers/ai_session_provider.dart`
- Test: `test/features/ai_assistant/ai_session_sheet_test.dart`

**Interfaces:**
- Consumes: `AiSessionRepository` (Tasks 1/3/4), `AiSessionTurnModel`
  (Task 2), the five flag providers (Task 5).
- Produces: `aiSessionRepositoryProvider` (a plain, non-autoDispose
  `Provider<AiSessionRepository>`, matching
  `aiAssistantRepositoryProvider`'s own existing shape exactly —
  `ai_assistant_providers.dart:37`), `AiSessionSheet` (pushed via
  `MaterialPageRoute`, matching `AssistSheet`'s own convention), a
  `.autoDispose` `AiSessionController` (a `StateNotifier` or
  `AsyncNotifier` — match whichever pattern
  `assistDraftProvider`/`understandResultProvider` already use in
  `ai_assistant_providers.dart`, do not introduce a third state-
  management pattern into this one feature module).

- [ ] **Sub-step A: Read the existing `assistDraftProvider` pattern in full before writing `AiSessionController`**

```bash
sed -n '1,250p' lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart
```

Confirm the exact `AsyncNotifier`/`StateNotifier` base class, the
`.autoDispose` family shape, and how `assist_sheet.dart` consumes it
(`ref.watch`/`ref.read` call sites). `AiSessionController` must follow
this exact shape — a session ID keyed `.family` provider (a session is
naturally per-`sessionId`, unlike a single-shot draft which has no
natural key until it's already been created) is the right shape here:
`aiSessionControllerProvider(sessionId)`.

- [ ] **Sub-step B: Write `AiSessionController`'s failing test — starts with no session, `prepare()` creates one**

Create `test/features/ai_assistant/ai_session_sheet_test.dart` with its
first test only:

```dart
// test/features/ai_assistant/ai_session_sheet_test.dart
import 'package:attune/features/ai_assistant/data/repositories/ai_assistant_repository.dart';
import 'package:attune/features/ai_assistant/presentation/providers/ai_session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeGateway implements AiAssistantGateway {
  final Map<String, dynamic Function(Map<String, dynamic>?)> functionHandlers;
  const _FakeGateway({this.functionHandlers = const {}});
  @override
  Future<dynamic> invokeFunction(String functionName, {Map<String, dynamic>? body}) async {
    final handler = functionHandlers[functionName];
    if (handler == null) throw StateError('No fake handler for $functionName');
    return handler(body);
  }
  @override
  Future<dynamic> rpc(String function, {Map<String, dynamic>? params}) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>?> selectPlanningLink(String messageId) => throw UnimplementedError();
}

void main() {
  test('preparing a session transitions the controller from idle to a real session id', () async {
    final gateway = _FakeGateway(functionHandlers: {
      'ai-sessions': (body) {
        if (body?['command'] == 'prepare') {
          return {'session_id': 'sess-1', 'revision': 1, 'created': true};
        }
        throw StateError('unexpected command ${body?['command']}');
      },
    });
    final container = ProviderContainer(overrides: [
      aiAssistantRepositoryProvider.overrideWithValue(AiAssistantRepository(gateway)),
      // aiSessionRepositoryProvider override -- confirm this provider's
      // exact name/shape from Sub-step A's own reading before writing
      // this override line.
    ]);
    addTearDown(container.dispose);

    // The rest of this test depends entirely on Sub-step A's findings
    // about AiSessionController's real shape (AsyncNotifier vs
    // StateNotifier, .family key, initial state value) -- write the
    // actual assertions against that real shape, not a guess.
  });
}
```

- [ ] **Sub-step C: Implement `AiSessionController` following Sub-step A's confirmed pattern, run the test, iterate until green**

This sub-step's actual code depends entirely on what Sub-step A found —
write `ai_session_provider.dart` matching that exact base class/family
shape, wiring `prepare`/`reviewContext`/`approve`/`start`/`generate`/
`read`/`end`/`shareAnswer` as controller methods that call the matching
`AiSessionRepository` method and update state, exactly mirroring how
`assist_sheet.dart` drives `assistDraftProvider`'s own methods today.

- [ ] **Sub-step D: Write `AiSessionSheet`'s widget skeleton — kind/visibility choice, Start button**

Following `assist_sheet.dart`'s own file-header-documented structure
(input → generate → preview → actions), build the preparation screen:
kind toggle (Ideas/Nearby), visibility toggle (Private/Shared), a Start
button that calls the controller's `prepare()` then `start()` once
approved. For a private session, `start()` can follow `approve()`
immediately (spec §3.2: "Private creator approves... then activates" —
no waiting on a partner). For a shared session, show a "waiting for your
partner" state after the creator's own `approve()` until a Realtime hint
(Task 8) or a manual refresh shows the partner has also approved.

- [ ] **Sub-step E: Write the live transcript renderer**

One widget per `AiSessionTurnModel` subtype (matching Task 2's sealed
type): `AiSessionUserTurn` renders as a right-aligned bubble (the
requester's own instruction), `AiSessionIdeasAnswerTurn` renders as a
left-aligned Attune bubble with a "Share to chat" action calling
`shareAnswer`, `AiSessionRedirectTurn` renders as a neutral inline notice
(never a bubble styled as if Attune "said" something conversational —
matching spec §1's "not a conversational AI persona" framing even within
the session's own UI), `AiSessionNearbyResultTurn` renders source cards
(reuse whatever card widget `assist_sheet.dart`'s own Nearby preview
already uses for `PlaceSourceModel` — do not build a second one).

- [ ] **Sub-step F: Wire the AI mode composer field into the sheet's own instruction input**

The sheet's own text field (NOT `ChatTextField` itself — `AiSessionSheet`
is a separate pushed screen, matching `AssistSheet`'s own convention of
owning its own input field rather than reusing the chat screen's
composer instance) submits via the controller's `generate()` method,
showing a loading state until it resolves, then appending the new turn
to the transcript.

- [ ] **Sub-step G: Run the full test file**

```bash
flutter test test/features/ai_assistant/ai_session_sheet_test.dart 2>&1 | tail -40
```

Expected: PASS. This is the point at which the sheet's own core loop
(prepare → approve → start → generate → render → share) has full test
coverage — expand the test file incrementally as each sub-step above
adds real behavior, rather than writing one giant test at the end.

- [ ] **Sub-step H: Analyze and commit**

```bash
flutter analyze lib/features/ai_assistant/presentation/screens/ai_session_sheet.dart \
  lib/features/ai_assistant/presentation/providers/ai_session_provider.dart
git add lib/features/ai_assistant/presentation/screens/ai_session_sheet.dart \
        lib/features/ai_assistant/presentation/providers/ai_session_provider.dart \
        test/features/ai_assistant/ai_session_sheet_test.dart
git commit -m "feat(ai-sessions): add AiSessionSheet with preparation, approval, and live transcript"
```

---

### Task 8: Realtime hint subscription and read repair

**Files:**
- Modify: `lib/features/ai_assistant/presentation/providers/ai_session_provider.dart`
- Test: extend `test/features/ai_assistant/ai_session_sheet_test.dart`

**Interfaces:**
- Consumes: Plan C Task 6's `ai_session_hint:<user id>` private Broadcast
  channel.
- Produces: a subscription inside `AiSessionController` (or a sibling
  provider it watches) that calls `.channel('ai_session_hint:$userId',
  opts: RealtimeChannelConfig(private: true)).onBroadcast(event: '*',
  callback: (_) => refetch())`, refetching turns via the existing `read`
  command — never rendering the broadcast payload directly, since Plan
  C's outbox is content-free by construction (spec §6.1: "Payload only
  'refresh AI state'"). Debounced to at most one refetch per five seconds
  while the sheet is open (spec §6.1's own stated rate), and a foreground-
  resume listener that refetches once on `AppLifecycleState.resumed`
  (spec §8.2.3: "resume refetches only after authorization").

- [ ] **Step 1: Write the failing test — a broadcast triggers exactly one refetch, debounced**

```dart
test('a realtime hint triggers a refetch, debounced to at most once per 5 seconds', () async {
  // Fake the Supabase Realtime channel surface this provider depends
  // on -- confirm the exact channel API shape (RealtimeChannel,
  // .onBroadcast, .subscribe) against this codebase's actual
  // supabase_flutter version before writing the fake, mirroring how
  // Task 1 Step 3 read real transport behavior before mocking it.
});
```

- [ ] **Step 2: Implement the subscription, following whatever real channel
  API Step 1's own investigation confirmed**

- [ ] **Step 3: Run, confirm passes, analyze, commit**

```bash
flutter test test/features/ai_assistant/ai_session_sheet_test.dart 2>&1 | tail -30
flutter analyze lib/features/ai_assistant/presentation/providers/ai_session_provider.dart
git add lib/features/ai_assistant/presentation/providers/ai_session_provider.dart \
        test/features/ai_assistant/ai_session_sheet_test.dart
git commit -m "feat(ai-sessions): subscribe to content-free realtime hints with debounced refetch"
```

---

### Task 9: Wire the composer button and long-press "Get ideas" into `AiSessionSheet`

**Files:**
- Modify: the chat screen file that constructs `ChatTextField` (find via
  grep — likely `lib/features/chat/presentation/screens/chat_screen.dart`,
  confirm before editing)
- Modify: `lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart`
- Test: extend the relevant existing chat screen test file

**Interfaces:**
- Consumes: `AiSessionSheet` (Task 7), `aiAssistBaseEnabledProvider`
  (Task 5).

- [ ] **Step 1: Find and read the real `ChatTextField` construction site**

```bash
grep -rn "ChatTextField(" lib/features/chat/presentation/screens/*.dart
```

- [ ] **Step 2: Wire `aiMode`/`onAiButtonTap`, gated on the flag**

```dart
Consumer(
  builder: (context, ref, _) {
    final aiEnabled = ref.watch(aiAssistBaseEnabledProvider).valueOrNull ?? false;
    return ChatTextField(
      // ... existing parameters unchanged ...
      onAiButtonTap: aiEnabled
          ? () => Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(builder: (_) => const AiSessionSheet()),
              )
          : null,
    );
  },
)
```

**Confirm this composition point actually has access to a `WidgetRef`**
(a `Consumer`/`ConsumerWidget` ancestor) before writing this — if the
real `ChatTextField` construction site is inside a plain
`StatelessWidget`/`StatefulWidget` with no Riverpod access, wrap only
the button's own visibility check in a `Consumer`, not the whole
`ChatTextField` construction, to avoid an unnecessary rebuild scope
change to unrelated composer state.

- [ ] **Step 3: Repoint "Get ideas" in `AskAttuneModeSheet`**

```bash
grep -n "Get ideas\|AssistSheet\|AssistKind.ideas" lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart
```

Read the exact current wiring, then change the "Get ideas" choice's
navigation target from `AssistSheet(kind: AssistKind.ideas, ...)` to
`AiSessionSheet(...)`, passing the long-pressed message as the
pre-attached target (matching this plan's own Architecture note:
"pre-seeded with the selected message"). **"Possible ways to read this"
(Understand) is unchanged** — do not touch that branch.

- [ ] **Step 4: Write/extend the relevant chat screen test**

Add a test proving: the AI button is absent when
`aiAssistBaseEnabledProvider` resolves `false`; present and tappable when
`true`; tapping it pushes `AiSessionSheet`. Follow whatever existing
pattern this chat screen's own test file already uses for its other
flag-gated buttons (e.g. the translator entry point) — do not invent a
new harness shape for this one test.

- [ ] **Step 5: Run the full chat test suite**

```bash
flutter test test/features/chat/ --concurrency=1 2>&1 | tail -20
```

Expected: no regressions.

- [ ] **Step 6: Analyze and commit**

```bash
flutter analyze lib/features/chat/presentation/screens/ lib/features/ai_assistant/presentation/screens/ask_attune_mode_sheet.dart
git add -A
git commit -m "feat(ai-sessions): wire the composer AI button and repoint long-press Get ideas into AiSessionSheet"
```

---

## Plan D self-review

**Spec coverage:**

- §3.3 (composer behavior: separate drafts, no offline queue, foreground-
  only draft, label Private/Shared and Ideas/Nearby throughout) — Task 6
  (control hiding), Task 7 Sub-step D/F (separate draft, labels). The
  "no offline queue, auto-resend" requirement is satisfied by NEGATIVE
  construction — this plan never builds a queue at all, which is the
  correct way to satisfy a "must not exist" requirement, but is worth
  stating explicitly here since no single task's own text proves a
  negative.
- §4.1 (every command) — Tasks 1/3/4 cover all nine.
- §5.3 (rendering every output kind) — Task 2 (models) + Task 7 Sub-step
  E (rendering).
- §9 (client integration — full list: repository/provider, composer
  mode, preparation/approval screen, transcript/staging renderer,
  source-card review, lifecycle clearing, read repair, foreground
  refresh) — Tasks 1-9 cover all of these **except explicit "lifecycle
  clearing"** (spec §8.2.3: "Foreground session memory clears on
  account/relationship change, End, expiry and background"). **Real
  gap**: no task in this plan explicitly wires a listener for
  account-switch/relationship-change/backgrounding that clears
  `AiSessionController`'s in-memory state. Since the controller is
  `.autoDispose` (Sub-step A), Riverpod already clears it when nothing
  watches it — but that only helps if `AiSessionSheet` itself is popped
  on those events, which nothing in this plan currently does. **Add as
  Task 10**: a listener (on account sign-out, active-relationship
  change, and `AppLifecycleState.paused`) that pops `AiSessionSheet` if
  it's on the navigation stack, ensuring the `.autoDispose` provider
  actually tears down rather than sitting backgrounded with live state.
- §10 (error handling per code) — Task 1's `AiSessionError` sealed type
  gives every call site the ability to pattern-match; **this plan does
  not itself write the UI copy/behavior for each of the 18 error
  variants** inside `AiSessionSheet` — Task 7 Sub-step D/F build the
  happy path, and a `switch` over `AiSessionError` mapping each variant
  to the exact UI behavior spec §10's table describes (e.g.
  `AiSessionBusyError` → "keep own draft, retry explicitly after
  refetch", never an auto-retry) is real remaining work. **Add as Task
  11**: one dedicated task building that switch and a test per error
  variant proving the UI shows the SPEC-MANDATED behavior, not a generic
  fallback — this is exactly the kind of task worth its own isolated
  review gate rather than folding 18 cases into Task 7's already-large
  scope.
- §12 (rollout flags, kill switch) — Task 5 covers the five flags. The
  "server kill blocks admission/dispatch/sharing and revokes pending
  session epochs" half is server-side (Plan B/C's own territory — a
  disabled flag here simply hides the entry point and, if Plan C's
  `generate` command itself also checks the flag server-side [not
  explicitly built in Plan C as written — **cross-plan gap, flag to
  whoever executes Plan C**: its Task 1 skeleton has no flag check at
  all], the client-side hide is cosmetic only, not the actual safety
  boundary).

**Two real gaps found, added as explicit follow-up tasks:**

- [ ] **Task 10 (new): lifecycle clearing.** Listener on sign-out/
  relationship-change/backgrounding that pops `AiSessionSheet` if open.
- [ ] **Task 11 (new): per-error-code UI behavior.** A dedicated
  `switch` over every `AiSessionError` variant inside `AiSessionSheet`,
  with one test per variant proving spec §10's exact mandated behavior.

**One cross-plan gap surfaced, not this plan's to fix but flagged
loudly:** Plan C's `ai-sessions/index.ts` skeleton (Task 1) has no
feature-flag check inside `processSessionCommand` at all — every command
this plan's client calls would succeed against the edge function
regardless of the `chat_ai_sessions_*` flags' server-side state, since
those flags currently only exist as `feature_flags` table rows this
plan's OWN client reads (Task 5). **The server-side enforcement spec §12
requires ("Server kill blocks admission/dispatch/sharing") does not
exist anywhere in Plans A/B/C as currently written.** This is a real,
load-bearing gap across the whole four-plan set, not just Plan D's — the
client-side hide this plan builds is a UX nicety, not the security
boundary spec §12 promises. **Recommend**: before any of these four
plans ship to a real device, add a Plan C task (or a Plan E) that checks
`get_feature_flag`-shaped state inside `processSessionCommand` itself,
returning `FEATURE_DISABLED` for every command when the relevant flag is
off — server-side, unconditionally, regardless of what any client sends.

**Placeholder scan:** Task 7's sub-steps are deliberately less
code-complete than Tasks 1-6, because `AiSessionController`'s real shape
depends on reading live code (Sub-step A) that this plan cannot
pre-determine without guessing — every sub-step says explicitly what
must be confirmed before writing real code, rather than presenting a
guessed API as if it were settled. This is flagged here as a deliberate
plan-writing choice, not an oversight: Task 7 is the one task in this
whole four-plan set where "read the real pattern first" cannot be done
by the plan's own author in advance, because `AiSessionController` is
NEW code with no existing exact analog (unlike every other task, which
extends or mirrors something that already exists on disk).

**Type consistency check:** `AiSessionTurnModel`'s sealed hierarchy
(Task 2) is consumed identically by `AiSessionRepository.read()`/
`.generate()` (Task 3/4) and by `AiSessionSheet`'s renderer (Task 7) —
confirmed no divergent field naming between the model and its
consumers by re-reading Task 3's `read()` implementation against Task
2's constructors.

## Execution Handoff

Plan complete and saved to
`docs/superpowers/plans/2026-09-22-ai-sessions-plan-d-flutter-client.md`.

**All four plans (A/B/C/D) are now written.** Before execution begins on
any of them, two things are worth your attention:

1. Plan D's self-review surfaced a real cross-plan gap: **no plan in
   this set currently enforces the server-side kill switch spec §12
   requires** — the flags Plan D reads are client-side only. This should
   be resolved (likely as a small addition to Plan C) before Plan D's
   own Task 9 wires a live composer button to it.
2. Every plan's self-review found genuine gaps and listed them as
   explicit new follow-up tasks rather than silently patching them into
   existing tasks' code samples. Read each plan's own "self-review"
   section before executing it — those follow-up tasks are real,
   numbered work, not optional polish.

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per
task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using
executing-plans, batch execution with checkpoints

**Which approach?**
