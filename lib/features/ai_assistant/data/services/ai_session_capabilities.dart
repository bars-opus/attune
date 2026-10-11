// lib/features/ai_assistant/data/services/ai_session_capabilities.dart
//
// Spec §12's capability flags, as the client sees them.
//
// WHY THIS IS NOT FIVE `ChatFeatureFlags` CONSTANTS (Plan D Task 5, PF2).
//
// Task 5's brief asked for five `FutureProvider<bool>`s reading
// `public.feature_flags` through `ChatFeatureFlags.isEnabled`, the way
// `chatTranslatorEntryEnabledProvider` reads `chat_translator_entry`.
// Those providers would have read nothing. Migration
// 20260953200000_ai_capability_flags.sql narrowed that table's SELECT
// policy to
//
//     key NOT LIKE 'dating\_%' AND key NOT LIKE 'ai\_%'
//
// deliberately, so that an unlaunched rollout plan cannot be enumerated
// by any authenticated client -- which is the exact finding
// 20260712150000_dating_flag_defense_in_depth.sql was written about.
// Measured as `authenticated`: zero `ai_%` rows visible, and
// `isEnabled`'s own `.eq('key', ...).maybeSingle()` query returns no
// row, so every flag would have fallen back to its `false` default
// FOREVER and no operator UPDATE could ever have turned the feature on.
// A kill switch that looks live and is dead is worse than no flag.
//
// So availability is derived from a server RPC instead -- exactly as
// `DatingFeatureFlags.isDatingModeAvailable` derives Dating's from
// `get_dating_eligibility()`, the precedent that migration points at.
// The RPC is `get_ai_session_capabilities()` (migration
// 20260953200500), which takes no parameter and so is not a key-by-key
// oracle, and reports only the five capabilities this client renders
// entry points for.
//
// THESE ARE NOT GATES. §12: "A client flag alone is insufficient."
// Enforcement lives in the ai-sessions edge function's
// `checkEligibility` CHECK 0, which consults the service_role-only
// `ai_capability_enabled()` before membership and returns
// `FEATURE_DISABLED`. Everything here does is decide whether to OFFER a
// door. A spoofed `true` buys a user an `AiSessionFeatureDisabledError`
// on their first command, which is what an unspoofed client would have
// shown anyway.
//
// NOTHING IN THIS FILE CAN ENABLE A CAPABILITY. There is one RPC call,
// it is a read, and there is no write path to `feature_flags` anywhere
// in the client (that table grants `authenticated` SELECT only). The
// flags ship OFF and flipping them is an operator act.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

/// The five §12 capability flags this client renders entry points for,
/// as reported by one `get_ai_session_capabilities()` call.
///
/// Every field defaults to `false` and the unknown/unreachable case is
/// [AiSessionCapabilities.unavailable], so there is no constructor path
/// that yields an optimistic value. That is the whole point: a client
/// that cannot reach the server must offer nothing, never everything.
class AiSessionCapabilities {
  /// Base single-turn Ask Attune (`ai_assist_enabled`).
  ///
  /// This is the base Assist gate §14.1 requires and which, verified
  /// here, NOTHING currently applies: `grep 'ChatFeatureFlags\.'` over
  /// `lib/` returns 16 call sites and not one is in the Ask Attune path,
  /// whose only conditions are `message.isEligibleForAskAttune`
  /// (deleted/system/media/length predicates) and `aiConsentStatusProvider`.
  /// So the base spec's own "Ask Attune is wired live with no feature
  /// flag guarding it" finding was still true, and this is its fix.
  final bool assist;

  /// Private multi-turn Sessions (`ai_sessions_private_enabled`).
  final bool sessionsPrivate;

  /// Shared (mutually joined) multi-turn Sessions
  /// (`ai_sessions_shared_enabled`).
  ///
  /// Separate from [sessionsPrivate] because §12 requires
  /// "Subcapability disable closes affected sessions, not unrelated
  /// chat" -- killing shared must leave private sessions alive, which
  /// one combined flag cannot express. A UI must therefore never infer
  /// one from the other.
  final bool sessionsShared;

  /// The optional shared recent-message window
  /// (`ai_sessions_recent_window_enabled`).
  ///
  /// The one subcapability that puts the PARTNER's chat text into a
  /// provider prompt, so it is separately killable. A shared session
  /// may be offered with this off; only the window toggle hides.
  final bool sessionsRecentWindow;

  /// Nearby, the Mapbox-backed kind (`ai_sessions_nearby_enabled`).
  final bool sessionsNearby;

  const AiSessionCapabilities({
    required this.assist,
    required this.sessionsPrivate,
    required this.sessionsShared,
    required this.sessionsRecentWindow,
    required this.sessionsNearby,
  });

  /// Everything off. The value for "the server said no" AND for "I could
  /// not ask" -- see [AiSessionCapabilitiesService.load] for why those
  /// two are not distinguished to callers.
  static const AiSessionCapabilities unavailable = AiSessionCapabilities(
    assist: false,
    sessionsPrivate: false,
    sessionsShared: false,
    sessionsRecentWindow: false,
    sessionsNearby: false,
  );

  /// The wire keys of `get_ai_session_capabilities()`, transcribed from
  /// migration 20260953200500.
  ///
  /// Exposed so a test can assert this set and the parser agree, the way
  /// Task 2's models expose `wireKeysRead`. `ai_understand_enabled` is
  /// deliberately absent: the RPC does not report it, because no Plan D
  /// entry point depends on Understand and reporting a capability state
  /// no client needs is the disclosure the dating migration warns about.
  static const Set<String> wireKeys = <String>{
    'ai_assist_enabled',
    'ai_sessions_private_enabled',
    'ai_sessions_shared_enabled',
    'ai_sessions_recent_window_enabled',
    'ai_sessions_nearby_enabled',
  };

  /// Parses the RPC's jsonb object.
  ///
  /// RULING 11: raises a [FormatException] naming what it could not
  /// read, never a constant typed error -- so a caller's own error
  /// mapping stays the only thing that assigns meaning to a failure.
  ///
  /// FAILS CLOSED ON ANYTHING THAT IS NOT AN EXPLICIT `true`, matching
  /// `checkEligibility`'s own rule for the same values ("a NULL, a
  /// missing row, an absent key or an unexpected shape all mean
  /// disabled"). A missing key is therefore `false`, not an exception:
  /// a server that drops a capability from the payload must read as off,
  /// which is the direction §12's "defaults off" points. A key present
  /// with a non-boolean value is the one case that DOES raise, because
  /// that is a contract violation rather than an absence, and silently
  /// reading it as `false` would hide a server/client version skew that
  /// also affects the four keys around it.
  factory AiSessionCapabilities.fromRpc(Map<String, Object?> payload) {
    bool read(String key) {
      final value = payload[key];
      if (value == null) return false;
      if (value is! bool) {
        throw FormatException(
          'get_ai_session_capabilities returned $key as '
          '${value.runtimeType} ("$value"), not a boolean. Refusing to '
          'guess: a non-boolean here is a server/client contract skew, '
          'not an absent capability, and reading it as `false` would '
          'hide skew affecting the other keys too.',
        );
      }
      return value;
    }

    return AiSessionCapabilities(
      assist: read('ai_assist_enabled'),
      sessionsPrivate: read('ai_sessions_private_enabled'),
      sessionsShared: read('ai_sessions_shared_enabled'),
      sessionsRecentWindow: read('ai_sessions_recent_window_enabled'),
      sessionsNearby: read('ai_sessions_nearby_enabled'),
    );
  }

  /// True when no capability is available. Deliberately NOT a
  /// "something is available" convenience: a call site that wants to
  /// know whether to draw the Nearby button must read [sessionsNearby],
  /// because §12's subcapability independence means any aggregate would
  /// be the wrong question.
  bool get noneAvailable =>
      !assist &&
      !sessionsPrivate &&
      !sessionsShared &&
      !sessionsRecentWindow &&
      !sessionsNearby;
}

/// Loads [AiSessionCapabilities] from the server.
///
/// Takes the `rpc` call as a seam rather than a [SupabaseClient] so the
/// parse and the fail-closed behaviour are testable without a live
/// Postgres -- the same reason `AiSessionRepository` takes a gateway.
class AiSessionCapabilitiesService {
  AiSessionCapabilitiesService(this._rpc);

  /// Production: `(name) => supabase.rpc(name)`.
  factory AiSessionCapabilitiesService.forClient(SupabaseClient supabase) {
    return AiSessionCapabilitiesService((name) => supabase.rpc(name));
  }

  final Future<Object?> Function(String name) _rpc;

  /// The RPC's name. One constant so the service and its test cannot
  /// disagree about which function is called.
  static const String rpcName = 'get_ai_session_capabilities';

  /// Reads all five capabilities in ONE round trip.
  ///
  /// FAILS CLOSED to [AiSessionCapabilities.unavailable] on any error,
  /// any null and any unexpected shape. Three cases collapse here on
  /// purpose:
  ///
  ///   * the RPC returned the five booleans -> parsed.
  ///   * the RPC returned `null`, which migration 20260953200500 does
  ///     when there is no authenticated subject (an expired session, a
  ///     misconfigured key) -> unavailable.
  ///   * the call threw -> unavailable.
  ///
  /// The SERVER distinguishes the last two (it returns NULL rather than
  /// an all-false object precisely so that "could not ask" is not
  /// reported as a deliberate disable); the CLIENT collapses them
  /// because the only decision downstream is whether to offer an entry
  /// point, and the answer is "no" either way. What must NOT happen is
  /// the reverse -- treating an unreadable answer as permission -- and
  /// there is no code path here that can.
  ///
  /// Never throws.
  Future<AiSessionCapabilities> load() async {
    try {
      final result = await _rpc(rpcName);
      if (result is! Map) return AiSessionCapabilities.unavailable;
      return AiSessionCapabilities.fromRpc(
        result.map((key, value) => MapEntry(key.toString(), value)),
      );
    } catch (_) {
      // Includes the FormatException fromRpc raises on a non-boolean.
      // A contract skew is a reason to offer nothing, not to throw into
      // a widget build.
      return AiSessionCapabilities.unavailable;
    }
  }
}
