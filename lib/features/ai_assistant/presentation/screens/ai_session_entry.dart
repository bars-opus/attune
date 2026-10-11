// lib/features/ai_assistant/presentation/screens/ai_session_entry.dart
//
// THE ONLY PLACE `AiSessionSheet` IS PUSHED (Plan D Task 9).
//
// Plan D has two entry points into a multi-turn session and they live
// in different widget subtrees: the composer's AI satellite, built by
// `chat_screen.dart` inside `_ChatScreenState`, and the long-press
// "Get ideas" tile, built by `ask_attune_mode_sheet.dart` which
// `message_bubble.dart` pushes onto the ROOT navigator from a
// `StatelessWidget`. Neither can see the other's `State`.
//
// ## RULING 24 LIVES IN THIS FILE
//
// **Two `AiSessionSheet`s must never be mounted at once.** Task 7's
// `aiSessionControllerProvider` is `NotifierProvider.autoDispose`
// keyed by nothing — it CANNOT be a `.family` keyed by session id,
// because the id does not exist until `prepare` returns and a replayed
// `prepare` returns the ORIGINAL session (Plan C Ruling 5, and that
// file's own header records why). So two sheets mounted under one
// `ProviderScope` resolve to the SAME notifier instance: each would
// write the other's phase, and each would see the other's turns
// appear. An AI session is modal by design, so a single-sheet
// invariant is the natural product behaviour as well as the honest
// consequence of the keying.
//
// The guard therefore has to be **as global as the controller is**,
// which means the provider container — not a `bool` in
// `_ChatScreenState`, which the long-press path cannot reach, and not
// a route-name check, which only sees one navigator.
// [aiSessionSheetMountedProvider] is that flag, and
// [openAiSessionSheet] is the only writer. A caller cannot forget it:
// pushing the sheet directly is what this function exists to replace,
// and `ai_session_entry_test.dart` scans all of `lib/` and fails unless
// THIS FILE holds the only `AiSessionSheet(` construction in it — so a
// future entry point that pushes the sheet itself fails that test even
// though every behavioural test would still pass.
//
// If a future product decision genuinely needs two concurrent
// sessions, the controller's key must become a **sheet-instance id**
// (a uuid minted by the opener, NOT the session id), and that is a
// deliberate change to Task 7's keying rather than something to work
// around here.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/ai_session_model.dart';
import '../providers/ai_session_provider.dart';
import 'ai_session_sheet.dart';

/// Whether an [AiSessionSheet] is currently mounted anywhere in this
/// provider container.
///
/// Container-scoped rather than widget-scoped deliberately: the
/// controller it protects is container-scoped too (see this file's
/// header), and the two entry points sit in subtrees with no common
/// `State`.
///
/// Written ONLY by [openAiSessionSheet], which sets it before the push
/// and clears it in the push future's `whenComplete` — so an ordinary
/// pop, a system back gesture and a `Navigator.pop` during an error
/// all release it, and a throw does not wedge it `true` forever.
final aiSessionSheetMountedProvider = StateProvider<bool>((ref) => false);

/// Pushes one [AiSessionSheet] onto [navigator], or does nothing if one
/// is already mounted (RULING 24).
///
/// Returns `true` when a sheet was pushed and `false` when the open was
/// refused because one was already up. **The refusal is silent on
/// purpose**: both entry points are reached by a deliberate tap, and
/// the only way to see one is to already be looking at the sheet the
/// invariant is protecting, so there is nothing to tell the user that
/// the sheet in front of them does not already say.
///
/// [utcOffsetMinutes] is **the offset the UI displayed**, resolved by
/// the caller rather than here, because the server refuses an
/// out-of-range offset rather than clamping — a clamped offset computes
/// a different civil day than the user saw (§4.2, and the N3 fix).
///
/// Takes a [NavigatorState] rather than a [BuildContext] for the same
/// reason `message_bubble.dart`'s `_buildAskAttuneOpener` does: the
/// long-press call site's element can be recycled by the message
/// `ListView` before the tapped callback runs, and `Navigator.of` on a
/// deactivated context throws.
///
/// Takes a [ProviderContainer] rather than a `WidgetRef`, and that is
/// RULING 29's lesson applied rather than restated. Every `WidgetRef`
/// method begins with `_assertNotDisposed()`
/// (`flutter_riverpod/src/consumer.dart:612-621`, read, not assumed),
/// so a `WidgetRef` held into the `whenComplete` below would throw
/// `Bad state: Cannot use "ref" after the widget was disposed` on the
/// ordinary path where the CALLER is gone before the sheet is — a chat
/// screen popped while the sheet is still up, which is exactly how
/// Task 8's first sheet wiring crashed 18 teardowns. The container is
/// owned by `ProviderScope`, outlives every widget under it, and
/// `containerOf` is resolved once here while the caller is definitely
/// mounted.
bool openAiSessionSheet({
  required ProviderContainer container,
  required NavigatorState navigator,
  required String relationshipId,
  required AiSessionKind initialKind,
  required int utcOffsetMinutes,
  required ValueChanged<String> onShared,
  String? targetMessageId,
}) {
  if (container.read(aiSessionSheetMountedProvider)) return false;
  if (!navigator.mounted) return false;

  container.read(aiSessionSheetMountedProvider.notifier).state = true;

  // The controller is `.autoDispose` and the PREVIOUS sheet may have
  // been popped only moments ago, so the instance can still be alive
  // on its disposal delay with a finished session's phase in it.
  // Invalidating here makes "a sheet opened" mean "a fresh session",
  // which is §1's "no previous assistant result is context for a later
  // call" — the same guarantee `assistDraftProvider.autoDispose` buys
  // the single-turn sheets.
  container.invalidate(aiSessionControllerProvider);

  navigator
      .push<void>(
        MaterialPageRoute<void>(
          builder:
              (_) => AiSessionSheet(
                relationshipId: relationshipId,
                initialKind: initialKind,
                utcOffsetMinutes: utcOffsetMinutes,
                onShared: onShared,
                targetMessageId: targetMessageId,
              ),
        ),
      )
      .whenComplete(() {
        // `whenComplete` rather than `then`: a route that completes with
        // an error, or is removed by a route-level pop during a
        // teardown, must still release the flag, or the entry point is
        // dead for the rest of the app session.
        //
        // The container is read here, never a `WidgetRef` — see this
        // function's doc.
        //
        // The write is guarded because the whole `ProviderScope` can be
        // torn down with this route still open, which is what every
        // widget test's teardown does, and `readProviderElement` throws
        // `StateError` on a disposed container
        // (`riverpod/src/framework/container.dart:418-424`, read).
        //
        // **THE CATCH IS THE GUARD, and that is a measurement rather
        // than a style choice.** Riverpod 2.6.1 exposes no public
        // `disposed` getter (only a private `_disposed`), and
        // `container.exists` — the one accessor with NO disposed check
        // (`container.dart:245`) — is NOT a usable probe: it returns
        // **true** after dispose, because disposal does not clear the
        // element map it reads. My first version gated on `exists` and
        // a test of that premise caught it; the guard would have fallen
        // straight through to the throwing `read`, in exactly the
        // teardown Ruling 29 is about. `ai_session_entry_test.dart`
        // pins both halves so this cannot be "simplified" back.
        //
        // Releasing a flag nobody can read any more is a no-op worth
        // skipping, not an error worth throwing into a route's
        // completion.
        try {
          container.read(aiSessionSheetMountedProvider.notifier).state = false;
        } on StateError {
          // The container went away first. Nothing left to release.
        }
      });

  return true;
}

/// The offset the UI is displaying right now, in minutes east of UTC.
///
/// One function so the composer entry point and the long-press entry
/// point cannot disagree about the civil day — `prepare` records it and
/// every later `review_context` must match it, and the server refuses
/// rather than clamping.
int displayedUtcOffsetMinutes([DateTime? now]) =>
    (now ?? DateTime.now()).timeZoneOffset.inMinutes;
