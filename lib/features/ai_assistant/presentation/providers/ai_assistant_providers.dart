// lib/features/ai_assistant/presentation/providers/ai_assistant_providers.dart
//
// Riverpod surface for the AI Assistant feature: consent status, the
// Assist-sheet draft holder, and the Understand-sheet result holder.
//
// Both `assistDraftProvider` and `understandResultProvider` are
// deliberately `.autoDispose` `AsyncNotifier`s that start IDLE (no
// `build()`-time fetch) and are only ever populated by an explicit
// `request...()` call from the sheet that owns them. This is the
// mechanism behind spec §1's "no previous assistant result is context
// for a later call": every sheet-open reads a FRESH provider instance
// (Riverpod tears the old one down once nothing watches it, per
// `.autoDispose`'s own contract), so there is no long-lived singleton
// anywhere in this file a second, unrelated invocation could observe
// a first invocation's result through. See
// `ai_assistant_providers_test.dart`'s own mutation test (temporarily
// defeating `.autoDispose` via `ref.keepAlive()`) for the guarantee
// this buys being actually exercised, not just asserted by
// convention.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/assist_draft_model.dart';
import '../../data/models/understand_result_model.dart';
import '../../data/repositories/ai_assistant_repository.dart';
import '../../data/services/raw_location_service.dart';

final _supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final aiAssistantRepositoryProvider = Provider<AiAssistantRepository>((ref) {
  final supabase = ref.read(_supabaseClientProvider);
  return AiAssistantRepository(SupabaseAiAssistantGateway(supabase));
});

/// The Nearby-only raw position reader (Task 5). A plain `Provider`,
/// not autoDispose — `RawLocationService` is stateless, so there is
/// nothing sheet-scoped to leak between opens (unlike
/// `assistDraftProvider`, which holds the actual result). Overridden in
/// tests with a fake to avoid touching a real platform Geolocator
/// channel from a widget test.
final rawLocationServiceProvider = Provider<RawLocationService>((ref) {
  return const RawLocationService();
});

/// Feature-local copy of the active relationship id, following the
/// same per-feature convention Planning/Reminders/Timeline each keep
/// independently rather than importing across feature boundaries.
final currentRelationshipIdProvider = FutureProvider<String?>((ref) async {
  final supabase = ref.read(_supabaseClientProvider);
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final response = await supabase
      .from('relationships')
      .select('id')
      .or('user_a.eq.$userId,user_b.eq.$userId')
      .eq('status', 'active')
      .maybeSingle();
  return response?['id'] as String?;
});

// --- Consent status ---

/// Both partners' AI-processing consent state for [relationshipId]
/// (spec §10.1). `.autoDispose` — this is a point-in-time read for
/// whatever screen/sheet is asking (e.g. to decide whether to show the
/// "waiting for your partner" gate before allowing an Assist/Understand
/// request), not a value anything should hold onto past that check.
final aiConsentStatusProvider = FutureProvider.autoDispose
    .family<AiConsentStatus, String>((ref, relationshipId) {
      final repository = ref.watch(aiAssistantRepositoryProvider);
      return repository.getConsentStatus(relationshipId);
    });

// --- Assist draft ---

/// Holds the in-flight/last [AssistDraftModel] for the currently-open
/// Assist sheet. `null` means idle (no request made yet on this sheet
/// instance) — distinct from `AsyncLoading`/`AsyncError`/a populated
/// `AsyncData`.
class AssistDraftNotifier extends AutoDisposeAsyncNotifier<AssistDraftModel?> {
  @override
  Future<AssistDraftModel?> build() async {
    // Idle until requestAssist() is called — a fresh sheet open is a
    // fresh provider instance (this class is never itself
    // `ref.keepAlive()`d), so there is nothing here to carry over from
    // a previous sheet's request.
    return null;
  }

  Future<void> requestAssist({
    required String requestId,
    required String messageId,
    required String assistKind,
    String? userInstruction,
    RequesterLocation? requesterLocation,
  }) async {
    state = const AsyncValue.loading();
    final repository = ref.read(aiAssistantRepositoryProvider);
    try {
      final draft = await repository.requestAssist(
        requestId: requestId,
        messageId: messageId,
        assistKind: assistKind,
        userInstruction: userInstruction,
        requesterLocation: requesterLocation,
      );
      state = AsyncValue.data(draft);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Explicit dismiss — clears back to idle without disposing the
  /// provider itself (a sheet that stays mounted but wants to let the
  /// user start over, e.g. after a retryable error, without a full
  /// widget-tree rebuild). Actual dismissal of the sheet should still
  /// let `.autoDispose` tear this provider down entirely; this is only
  /// for "clear and try again" while it stays open.
  void clear() {
    state = const AsyncValue.data(null);
  }
}

final assistDraftProvider =
    AsyncNotifierProvider.autoDispose<AssistDraftNotifier, AssistDraftModel?>(
      AssistDraftNotifier.new,
    );

// --- Understand result ---

/// Holds the in-flight/last [UnderstandResultModel] for the
/// currently-open Understand sheet. `null` means idle.
///
/// Cleared identically to [AssistDraftNotifier] on dismiss (via
/// `.autoDispose` tearing the whole instance down), PLUS three extra
/// triggers spec §6.3 requires that a plain idle-until-requested
/// notifier does not give for free:
///
///  - **backgrounded**: an `AppLifecycleListener` (imported from
///    `flutter/widgets.dart`, matching `AppPrivacyCover`'s and
///    Planning's own realtime-signal provider's import, not the
///    `foundation.dart` one) clears state on `onInactive`/`onHide` —
///    the target message's content must not sit decrypted in memory
///    while the app is switched away from, the same reasoning driving
///    Task 1's privacy cover.
///  - **auth-or-relationship-change**: `ref.listen`s
///    `currentRelationshipIdProvider` and clears on any change (a
///    sign-out, account switch, or relationship change mid-session
///    must never leave a stale result addressed to a different
///    pairing on screen).
///  - **late response**: `requestUnderstand()` stamps a monotonic
///    `_requestEpoch` per call and discards a response that resolves
///    after a NEWER call (or a `clear()`) has already superseded it —
///    the same "does this async result still belong on screen" guard
///    `planning_providers.dart`'s own pager uses, applied here to a
///    single in-flight request rather than a paginated list.
class UnderstandResultNotifier
    extends AutoDisposeAsyncNotifier<UnderstandResultModel?> {
  int _requestEpoch = 0;

  @override
  Future<UnderstandResultModel?> build() {
    final lifecycleListener = AppLifecycleListener(
      onInactive: _clearForBackground,
      onHide: _clearForBackground,
    );
    ref.onDispose(lifecycleListener.dispose);

    ref.listen<AsyncValue<String?>>(currentRelationshipIdProvider, (
      previous,
      next,
    ) {
      if (previous != null && previous.valueOrNull != next.valueOrNull) {
        _clearForBackground();
      }
    });

    return Future.value(null);
  }

  void _clearForBackground() {
    _requestEpoch++; // supersede any in-flight request too
    state = const AsyncValue.data(null);
  }

  Future<void> requestUnderstand({
    required String requestId,
    required String messageId,
    required int utcOffsetMinutes,
  }) async {
    final epoch = ++_requestEpoch;
    state = const AsyncValue.loading();
    final repository = ref.read(aiAssistantRepositoryProvider);
    try {
      final result = await repository.requestUnderstand(
        requestId: requestId,
        messageId: messageId,
        utcOffsetMinutes: utcOffsetMinutes,
      );
      if (epoch != _requestEpoch) return; // superseded — drop the late response
      state = AsyncValue.data(result);
    } catch (error, stackTrace) {
      if (epoch != _requestEpoch) return;
      state = AsyncValue.error(error, stackTrace);
    }
  }

  /// Explicit dismiss while the provider stays mounted (see
  /// [AssistDraftNotifier.clear]'s identical reasoning).
  void clear() {
    _requestEpoch++;
    state = const AsyncValue.data(null);
  }
}

final understandResultProvider =
    AsyncNotifierProvider.autoDispose<
      UnderstandResultNotifier,
      UnderstandResultModel?
    >(UnderstandResultNotifier.new);

// --- Add to Planning link state ---

/// Whether [messageId]'s shared Assist proposal has already been
/// converted to a Planning entity (spec §5.4) — `AttuneAssistBubble`
/// watches this to show "Add to Planning" vs. "Added to Planning".
/// `.autoDispose.family`, keyed by message id, matching Planning's own
/// established Realtime-refresh provider shape
/// (`lib/features/planning/presentation/providers/planning_providers.dart`)
/// rather than polling: a fresh watch re-fetches, and nothing here is
/// long-lived across bubbles for different messages. Callers that just
/// performed a successful `addToPlanning` call should
/// `ref.invalidate(planningLinkProvider(messageId))` rather than wait
/// for this provider's own next natural rebuild, so the bubble updates
/// immediately instead of on next scroll/rebuild.
final planningLinkProvider = FutureProvider.autoDispose
    .family<AddToPlanningResult?, String>((ref, messageId) {
      final repository = ref.watch(aiAssistantRepositoryProvider);
      return repository.getPlanningLink(messageId);
    });
