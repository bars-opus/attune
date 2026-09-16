// lib/features/ai_assistant/data/repositories/assistant_error.dart

/// Every failure `AiAssistantRepository` can throw. Matches spec §11's
/// `AssistantErrorCode` union EXACTLY — all 12 values, one subtype
/// each, no default/fallback case anywhere this is constructed from a
/// server code (see `AssistantError.fromCode` below). A raw string
/// code or a generic "something went wrong" must never reach the UI:
/// the UI branches on WHICH of these subtypes it got, the same
/// reasoning `PlanningError` (lib/features/planning/data/repositories/
/// planning_error.dart) already gives for its own sealed shape.
sealed class AssistantError implements Exception {
  const AssistantError();

  const factory AssistantError.unauthenticated() = AssistantUnauthenticatedError;
  const factory AssistantError.consentRequired() = AssistantConsentRequiredError;
  const factory AssistantError.targetUnavailable() = AssistantTargetUnavailableError;
  const factory AssistantError.invalidInput() = AssistantInvalidInputError;
  const factory AssistantError.unsupportedRequest() = AssistantUnsupportedRequestError;
  const factory AssistantError.locationRequired() = AssistantLocationRequiredError;
  const factory AssistantError.noResults() = AssistantNoResultsError;
  const factory AssistantError.rateLimited(int? retryAfterSeconds) =
      AssistantRateLimitedError;
  const factory AssistantError.requestInProgress() = AssistantRequestInProgressError;
  const factory AssistantError.resultUnavailable() = AssistantResultUnavailableError;
  const factory AssistantError.providerUnavailable() = AssistantProviderUnavailableError;
  const factory AssistantError.internalError() = AssistantInternalError;

  /// The ONLY place a raw server `code` string is allowed to become an
  /// [AssistantError]. This is a `switch` over a bare string — not a
  /// Dart enum — because the wire contract (spec §11) is a JSON string
  /// literal union, not a Dart type; there is no `sealed`/`enum`
  /// exhaustiveness check the compiler can give us here, so completeness
  /// is instead proven by the repository test suite's one-test-per-code
  /// coverage of all 12 values (see
  /// ai_assistant_repository_test.dart) and by this switch's `default`
  /// case existing ONLY to catch a code the server contract does not
  /// (yet) define — never to silently swallow one of the 12 known
  /// codes. Do not add a `default` branch above the 12 explicit cases;
  /// if a case is ever accidentally removed, its test fails loudly
  /// (falls into `default` -> `internalError()`, which the test for
  /// that exact code asserts against and does not get) rather than the
  /// analyzer catching it, which is why the mutation-testing step for
  /// this exact file matters more than for a real sealed switch.
  factory AssistantError.fromCode(String code, {int? retryAfterSeconds}) {
    switch (code) {
      case 'UNAUTHENTICATED':
        return const AssistantError.unauthenticated();
      case 'CONSENT_REQUIRED':
        return const AssistantError.consentRequired();
      case 'TARGET_UNAVAILABLE':
        return const AssistantError.targetUnavailable();
      case 'INVALID_INPUT':
        return const AssistantError.invalidInput();
      case 'UNSUPPORTED_REQUEST':
        return const AssistantError.unsupportedRequest();
      case 'LOCATION_REQUIRED':
        return const AssistantError.locationRequired();
      case 'NO_RESULTS':
        return const AssistantError.noResults();
      case 'RATE_LIMITED':
        return AssistantError.rateLimited(retryAfterSeconds);
      case 'REQUEST_IN_PROGRESS':
        return const AssistantError.requestInProgress();
      case 'RESULT_UNAVAILABLE':
        return const AssistantError.resultUnavailable();
      case 'PROVIDER_UNAVAILABLE':
        return const AssistantError.providerUnavailable();
      case 'INTERNAL_ERROR':
        return const AssistantError.internalError();
      default:
        // A code outside the 12-value contract (a future server
        // addition this client hasn't been updated for, or a transport
        // oddity) fails closed to the most generic, no-retry-implied
        // subtype rather than throwing a raw parse exception up to the
        // UI.
        return const AssistantError.internalError();
    }
  }
}

/// Not authenticated (spec §11 `UNAUTHENTICATED`). The UI should fail
/// closed, matching `PlanningUnauthorizedError`'s own reasoning.
class AssistantUnauthenticatedError extends AssistantError {
  const AssistantUnauthenticatedError();
}

/// Dual AI-processing consent has not been granted by both partners
/// yet (spec §10.1, §11 `CONSENT_REQUIRED`).
class AssistantConsentRequiredError extends AssistantError {
  const AssistantConsentRequiredError();
}

/// The target message is missing, not eligible, or not visible to the
/// caller (spec §11 `TARGET_UNAVAILABLE`).
class AssistantTargetUnavailableError extends AssistantError {
  const AssistantTargetUnavailableError();
}

/// The request body failed server-side shape/range validation before
/// any provider/DB work (spec §4.1, §11 `INVALID_INPUT`).
class AssistantInvalidInputError extends AssistantError {
  const AssistantInvalidInputError();
}

/// The request falls outside Assist/Understand's bounded jobs (spec
/// §5.1, §11 `UNSUPPORTED_REQUEST`) — the model/server declined to
/// pretend to answer rather than returning a wrong answer.
class AssistantUnsupportedRequestError extends AssistantError {
  const AssistantUnsupportedRequestError();
}

/// A Nearby request arrived with no `requester_location` (spec §5.2,
/// §11 `LOCATION_REQUIRED`).
class AssistantLocationRequiredError extends AssistantError {
  const AssistantLocationRequiredError();
}

/// Nearby's Mapbox call returned zero valid results (spec §5.2, §11
/// `NO_RESULTS`). Retryable per spec §11's `RETRYABLE_CODES`.
class AssistantNoResultsError extends AssistantError {
  const AssistantNoResultsError();
}

/// The shared per-relationship AI quota is exhausted (spec §7.3, §11
/// `RATE_LIMITED`). Carries the server's own `retry_after_seconds` so
/// the UI can say "try again in N seconds" rather than "tomorrow"
/// (spec §11) — must not be dropped on the way from the wire envelope
/// into this type.
class AssistantRateLimitedError extends AssistantError {
  final int? retryAfterSeconds;
  const AssistantRateLimitedError(this.retryAfterSeconds);
}

/// A request with this `request_id` is already in flight (spec §11
/// `REQUEST_IN_PROGRESS`) — the client must not fire a second provider
/// call for the same id, only poll.
class AssistantRequestInProgressError extends AssistantError {
  const AssistantRequestInProgressError();
}

/// The model's output failed the server's own structural/safety
/// validation (spec §5.2/§6.2, §11 `RESULT_UNAVAILABLE`) or a
/// previously-completed Understand result is no longer available to
/// retrieve (spec §11) — never surfaced as raw model output either
/// way.
class AssistantResultUnavailableError extends AssistantError {
  const AssistantResultUnavailableError();
}

/// The upstream model or Mapbox provider call failed/timed out (spec
/// §11 `PROVIDER_UNAVAILABLE`). Retryable.
class AssistantProviderUnavailableError extends AssistantError {
  const AssistantProviderUnavailableError();
}

/// An unexpected server-side failure (spec §11 `INTERNAL_ERROR`), OR a
/// malformed/unparseable success-status response this client could
/// not make sense of (see `ai_assistant_repository.dart`'s `_call`
/// helper) — a client-side parse failure on a nominally-successful
/// response is deliberately mapped here rather than propagating a raw
/// `FormatException`/`TypeError` to the UI layer.
class AssistantInternalError extends AssistantError {
  const AssistantInternalError();
}
