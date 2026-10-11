// lib/features/ai_assistant/data/repositories/ai_session_error.dart

/// Every failure [AiSessionRepository] can throw. Matches the
/// `SessionErrorCode` union in `supabase/functions/ai-sessions/index.ts`
/// EXACTLY — all 18 values, one subtype each.
///
/// Deliberately a SEPARATE type from `AssistantError`
/// (`assistant_error.dart`) rather than an extension of it, because the
/// two wire contracts differ in both their code unions and their
/// envelope shape:
///
/// - ai-assist's envelope carries `error: true` and a server-computed
///   `retryable` boolean. The §10 envelope this type wraps carries the
///   `code` plus an optional `retry_after_seconds` and NOTHING else;
///   index.ts's own header says so ("A client of this function branches
///   on `code`; there is no second derived field to disagree with it").
/// - §10 has NO `UNAUTHENTICATED` code. The server's `handleRequest`
///   maps a failed `requireUser` to `INVALID_INPUT`, with the comment
///   "§10 has no UNAUTHENTICATED, and 401 is already carried by the HTTP
///   layer". So there is deliberately no `AiSessionUnauthenticatedError`
///   here, unlike `AssistantUnauthenticatedError` — a subtype for a code
///   the server never sends would be a branch no server response can
///   ever reach, while the real auth failure arrived as invalid input.
///
/// A raw string code or a generic "something went wrong" must never
/// reach the UI: the UI branches on WHICH subtype it got, which is what
/// Plan D's Global Constraint ("Every error code in Plan C's
/// SessionErrorCode union has a distinct UI treatment") requires.
///
/// ## Branch on the CODE, never on the HTTP status
///
/// `SESSION_ERROR_STATUS` maps the 18 codes onto only 9 distinct HTTP
/// statuses. Five codes share 409 (`APPROVAL_REQUIRED`,
/// `CONTEXT_CHANGED`, `REQUEST_CONFLICT`, `SESSION_BUSY`,
/// `SESSION_LIMIT_REACHED`), three share 400 (`INVALID_INPUT`,
/// `LOCATION_REQUIRED`, `LOCATION_EXPIRED`), two share 403
/// (`CONSENT_REQUIRED`, `FEATURE_DISABLED`) and two share 502
/// (`REQUEST_FAILED`, `PROVIDER_UNAVAILABLE`), while `INTERNAL_ERROR` is
/// the only bare 500. Their §10 remedies are different — "approve
/// first", "re-review the context", "keep your draft and refetch",
/// "end your other session" — so a client that read the status could not
/// tell the user what to do. `AiSessionRepository._mapTransportError`
/// therefore reads only `details['code']` and never
/// `FunctionException.status`.
sealed class AiSessionError implements Exception {
  const AiSessionError();

  /// The §10 wire code this error came from. Present so a call site can
  /// log or report the code without reconstructing it from the subtype,
  /// and so a test can assert the subtype and the code agree. It is NOT
  /// an invitation to branch on the string: call sites pattern-match on
  /// the sealed subtype, which the analyzer can check exhaustively.
  String get code;

  const factory AiSessionError.unavailable() = AiSessionUnavailableError;
  const factory AiSessionError.consentRequired() =
      AiSessionConsentRequiredError;
  const factory AiSessionError.approvalRequired() =
      AiSessionApprovalRequiredError;
  const factory AiSessionError.contextChanged() = AiSessionContextChangedError;
  const factory AiSessionError.invalidInput() = AiSessionInvalidInputError;
  const factory AiSessionError.contextTooLarge() =
      AiSessionContextTooLargeError;
  const factory AiSessionError.requestConflict() =
      AiSessionRequestConflictError;
  const factory AiSessionError.busy() = AiSessionBusyError;
  const factory AiSessionError.limitReached() = AiSessionLimitReachedError;
  const factory AiSessionError.rateLimited(int? retryAfterSeconds) =
      AiSessionRateLimitedError;
  const factory AiSessionError.overloaded() = AiSessionOverloadedError;
  const factory AiSessionError.locationRequired() =
      AiSessionLocationRequiredError;
  const factory AiSessionError.locationExpired() =
      AiSessionLocationExpiredError;
  const factory AiSessionError.requestFailed() = AiSessionRequestFailedError;
  const factory AiSessionError.providerUnavailable() =
      AiSessionProviderUnavailableError;
  const factory AiSessionError.resultUnavailable() =
      AiSessionResultUnavailableError;
  const factory AiSessionError.featureDisabled() =
      AiSessionFeatureDisabledError;
  const factory AiSessionError.internalError() = AiSessionInternalError;

  /// The ONLY place a raw server `code` string is allowed to become an
  /// [AiSessionError]. A `switch` over a bare string — not a Dart enum —
  /// because the wire contract is a TypeScript string-literal union, so
  /// there is no exhaustiveness check the Dart compiler can give here.
  /// Completeness is proven instead by
  /// `ai_session_repository_test.dart`'s one-test-per-code coverage of
  /// all 18 values, whose denominator that suite asserts explicitly.
  ///
  /// The `default` case exists ONLY to catch a code the server contract
  /// does not (yet) define — never to swallow one of the 18 known codes.
  /// Do not hoist it above the explicit cases: if a case is ever
  /// accidentally removed, its own test fails loudly (falling into
  /// `default` -> `internalError()`, which that code's test asserts
  /// against and does not get) rather than the analyzer catching it.
  ///
  /// `retryAfterSeconds` is attached ONLY to `RATE_LIMITED`, the one
  /// §10 code whose envelope carries it on this contract; passing it
  /// alongside any other code discards it rather than quietly inventing
  /// a retry hint on a subtype that has no business carrying one.
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
      case 'INTERNAL_ERROR':
        return const AiSessionError.internalError();
      default:
        // A code outside the 18-value contract (a future server addition
        // this client has not been updated for, or a transport oddity)
        // fails closed to the most generic, no-retry-implied subtype
        // rather than throwing a raw parse exception up to the UI.
        //
        // This is also where a hypothetical 'UNAUTHENTICATED' would land:
        // §10 does not define it, so a server that sent it would be
        // speaking a contract this client does not know.
        return const AiSessionError.internalError();
    }
  }
}

/// Unknown, foreign, closed or expired session, or a relationship
/// change (§10 `UNAVAILABLE`, HTTP 404). §3.1 makes a non-member, an
/// unknown id, an ended and an archived relationship ONE
/// indistinguishable response, so the UI must not try to say which: it
/// returns the user to chat.
class AiSessionUnavailableError extends AiSessionError {
  const AiSessionUnavailableError();

  @override
  String get code => 'UNAVAILABLE';
}

/// Dual AI-processing consent has not been granted (§10
/// `CONSENT_REQUIRED`, HTTP 403). The caller CAN act on this: §10's own
/// guidance is "caller can open consent".
class AiSessionConsentRequiredError extends AiSessionError {
  const AiSessionConsentRequiredError();

  @override
  String get code => 'CONSENT_REQUIRED';
}

/// A `generate` arrived on a session that is not yet approved/active
/// (§10 `APPROVAL_REQUIRED`, HTTP 409).
///
/// NOT the shared-session first-approver case. `approve` answering
/// `{approved: true, activated: false, state: "preparing"}` is SUCCESS —
/// the caller approved and is waiting for their partner — and
/// `handleApprove` says so explicitly: "reporting it here would tell a
/// partner who did everything right that they failed". A client that
/// turned that 200 body into this error would be that bug.
class AiSessionApprovalRequiredError extends AiSessionError {
  const AiSessionApprovalRequiredError();

  @override
  String get code => 'APPROVAL_REQUIRED';
}

/// The approved context no longer matches the session's current one
/// (§10 `CONTEXT_CHANGED`, HTTP 409) — either the two partners'
/// submitted digests differ (§4.3's invalidation case) or the revision
/// moved under the caller.
///
/// The remedy is always "re-run `review_context` and approve the digest
/// it returns", never "recompute the digest locally and retry": see
/// [AiSessionError]'s own note and `AiSessionRepository`'s class header
/// on why the digest is opaque to this client.
class AiSessionContextChangedError extends AiSessionError {
  const AiSessionContextChangedError();

  @override
  String get code => 'CONTEXT_CHANGED';
}

/// The request body failed the server's bounded schema (§10
/// `INVALID_INPUT`, HTTP 400): a malformed field, an unknown field, a
/// body over §4.1's 4 KiB UTF-8 cap, an actor-naming field, or an
/// unrecognized command.
///
/// ALSO the code the server returns when JWT verification fails, since
/// §10 defines no `UNAUTHENTICATED` (`handleRequest`'s own comment). So
/// a UI branch on this subtype must cope with "you are signed out" as
/// well as "that input was not valid" — checking session validity before
/// blaming the user's input is the right order.
class AiSessionInvalidInputError extends AiSessionError {
  const AiSessionInvalidInputError();

  @override
  String get code => 'INVALID_INPUT';
}

/// The context WINDOW exceeds its §4.2 budget (§10 `CONTEXT_TOO_LARGE`,
/// HTTP 413). Distinct from [AiSessionInvalidInputError]: the user fixes
/// this by narrowing a selection, not by shortening a body.
class AiSessionContextTooLargeError extends AiSessionError {
  const AiSessionContextTooLargeError();

  @override
  String get code => 'CONTEXT_TOO_LARGE';
}

/// A request id or idempotency key was reused with a DIFFERENT payload
/// (§10 `REQUEST_CONFLICT`, HTTP 409). §4.1: "Request IDs for retries
/// bind actor, operation, session and payload revision; different
/// payload reuse yields REQUEST_CONFLICT." The remedy is a NEW key, not
/// a retry of the same one.
class AiSessionRequestConflictError extends AiSessionError {
  const AiSessionRequestConflictError();

  @override
  String get code => 'REQUEST_CONFLICT';
}

/// Another generation is already in flight on this session (§10
/// `SESSION_BUSY`, HTTP 409). §10's guidance: "keep own draft, retry
/// explicitly after refetch" — the client must never auto-retry, and
/// must not discard what the user typed.
class AiSessionBusyError extends AiSessionError {
  const AiSessionBusyError();

  @override
  String get code => 'SESSION_BUSY';
}

/// The caller already holds the maximum number of pending/active
/// sessions (§10 `SESSION_LIMIT_REACHED`, HTTP 409). §10: "start a new
/// session explicitly" — the limit is the caller's OWN other session,
/// which they can end, so the UI should offer that rather than a
/// dead end.
class AiSessionLimitReachedError extends AiSessionError {
  const AiSessionLimitReachedError();

  @override
  String get code => 'SESSION_LIMIT_REACHED';
}

/// The shared per-relationship AI quota is exhausted (§10
/// `RATE_LIMITED`, HTTP 429).
///
/// Carries the server's own `retry_after_seconds` so the UI can say "try
/// again in N seconds" rather than "tomorrow" — it must not be dropped
/// on the way from the wire envelope into this type. It is NULLABLE
/// because §10 makes the field optional ("caller-safe
/// retry_after_seconds WHEN RELEVANT"), and a null must stay null rather
/// than defaulting to 0, which would read as "retry immediately" — the
/// exact auto-retry §10 forbids.
class AiSessionRateLimitedError extends AiSessionError {
  final int? retryAfterSeconds;
  const AiSessionRateLimitedError(this.retryAfterSeconds);

  @override
  String get code => 'RATE_LIMITED';
}

/// The provider or the server is shedding load (§10 `OVERLOADED`, HTTP
/// 503). §10 pairs it with RATE_LIMITED under "bounded retry-after;
/// never auto-generate later" — so an explicit user-initiated retry
/// only.
class AiSessionOverloadedError extends AiSessionError {
  const AiSessionOverloadedError();

  @override
  String get code => 'OVERLOADED';
}

/// A Nearby command arrived with no location (§10 `LOCATION_REQUIRED`,
/// HTTP 400). Classified 400 rather than 403 on purpose: §10 treats it
/// as "a client-side input problem, not an upstream failure", and its
/// remedy is "fresh explicit confirmation, no fallback" — never a cached
/// or inferred position.
class AiSessionLocationRequiredError extends AiSessionError {
  const AiSessionLocationRequiredError();

  @override
  String get code => 'LOCATION_REQUIRED';
}

/// The supplied location is too old to use (§10 `LOCATION_EXPIRED`, HTTP
/// 400). Same remedy as [AiSessionLocationRequiredError]: a fresh
/// explicit confirmation, with no silent re-use of the stale fix.
class AiSessionLocationExpiredError extends AiSessionError {
  const AiSessionLocationExpiredError();

  @override
  String get code => 'LOCATION_EXPIRED';
}

/// An upstream generation attempt failed and WAS COUNTED (§10
/// `REQUEST_FAILED`, HTTP 502). §10: "counted status explained to
/// requester" — the UI must tell the user the attempt was spent, rather
/// than presenting it as a free retry.
class AiSessionRequestFailedError extends AiSessionError {
  const AiSessionRequestFailedError();

  @override
  String get code => 'REQUEST_FAILED';
}

/// The model or Mapbox provider call failed or timed out (§10
/// `PROVIDER_UNAVAILABLE`, HTTP 502). Shares its status with
/// [AiSessionRequestFailedError] but not its message: this one is an
/// upstream outage rather than a counted, explained failure.
class AiSessionProviderUnavailableError extends AiSessionError {
  const AiSessionProviderUnavailableError();

  @override
  String get code => 'PROVIDER_UNAVAILABLE';
}

/// A previously-produced result is expired or revoked (§10
/// `RESULT_UNAVAILABLE`, HTTP 410). §10: "never replay provider" — the
/// client must not re-request generation to "recover" it.
class AiSessionResultUnavailableError extends AiSessionError {
  const AiSessionResultUnavailableError();

  @override
  String get code => 'RESULT_UNAVAILABLE';
}

/// One of the six §12 capability flags required by this session's own
/// kind/visibility/window is off (§10 `FEATURE_DISABLED`, HTTP 403).
/// §10: "safe return to chat, no new work."
///
/// Note that `read` DELIBERATELY does not return this code — §7.2
/// requires silence, so `read` answers 200 with an empty array instead.
/// An empty `read` is therefore NOT evidence that the session is gone or
/// the feature is off; see `AiSessionRepository`'s class header.
class AiSessionFeatureDisabledError extends AiSessionError {
  const AiSessionFeatureDisabledError();

  @override
  String get code => 'FEATURE_DISABLED';
}

/// An unexpected server-side failure (§10 `INTERNAL_ERROR`, the only
/// bare HTTP 500 in the contract), OR — client-side — a malformed or
/// unparseable response this client could not make sense of, a transport
/// error with no §10 envelope at all, or a code outside the 18-value
/// contract. A client-side parse failure on a nominally successful
/// response is mapped here deliberately, rather than propagating a raw
/// `FormatException`/`TypeError` to the UI layer.
class AiSessionInternalError extends AiSessionError {
  const AiSessionInternalError();

  @override
  String get code => 'INTERNAL_ERROR';
}
