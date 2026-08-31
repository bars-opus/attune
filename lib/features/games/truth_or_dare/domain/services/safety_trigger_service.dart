// lib/features/games/truth_or_dare/domain/services/safety_trigger_service.dart

/// Truth-answer safety runs SERVER-SIDE.
///
/// This file used to hold a `checkTruthAnswer` stub that returned false and
/// was called from nowhere, which read as "safety is handled" while nothing
/// was checked.
///
/// TRUTH_OR_DARE.md §4.4 requires the same keyword detection as chat
/// messages, and chat's runs in an Edge Function so the wordlist is never
/// shipped in the client bundle. Truth answers now follow the same route:
///
///   game_session_rounds UPDATE
///     -> queue_truth_answer_safety trigger
///     -> truth_answer_safety_outbox
///     -> process-truth-answer-safety (shares _shared/chat_safety.ts)
///     -> safety_events + a private push to the READER
///     -> game_session_rounds.safety_triggered
///
/// The client's only part is reading safety_triggered to show resources in
/// place. There is deliberately nothing to call from here.
library;
