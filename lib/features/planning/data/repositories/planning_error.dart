// lib/features/planning/data/repositories/planning_error.dart

/// Every failure the Planning repository can throw. Never a raw
/// PostgrestException reaching the UI — the UI branches on WHICH of
/// these it got (fail-closed-and-leave vs. offer-retry vs. show-this-
/// exact-validation-message), so a string comparison against an error
/// message is not a substitute for this type.
sealed class PlanningError implements Exception {
  const PlanningError();

  const factory PlanningError.unauthorized() = PlanningUnauthorizedError;
  const factory PlanningError.notFound() = PlanningNotFoundError;
  const factory PlanningError.validation(String message) =
      PlanningValidationError;
  const factory PlanningError.network(Object cause) = PlanningNetworkError;
}

/// The caller is not authenticated, is not a member of the
/// relationship, or the relationship has ended/archived. The UI must
/// fail closed: clear Planning provider state and leave the screen
/// (spec §9), never retry automatically.
class PlanningUnauthorizedError extends PlanningError {
  const PlanningUnauthorizedError();
}

/// The target row does not exist (already deleted by the other
/// partner, or never existed). Distinct from unauthorized: this is not
/// a security failure, just "that thing isn't there anymore" — the UI
/// may simply drop it from the list rather than showing an error.
class PlanningNotFoundError extends PlanningError {
  const PlanningNotFoundError();
}

/// A rule the RPC enforces was violated (sole-child delete, 100-child
/// cap, a non-member assignee, deep nesting, ...). `message` is the
/// RPC's own RAISE EXCEPTION text — safe to show directly, since every
/// message Plan A's RPCs raise is already written for a human reader,
/// never an internal detail.
class PlanningValidationError extends PlanningError {
  final String message;
  const PlanningValidationError(this.message);
}

/// A transient/network-shaped failure — the UI should offer retry
/// rather than treating this as authoritative.
class PlanningNetworkError extends PlanningError {
  final Object cause;
  const PlanningNetworkError(this.cause);
}
