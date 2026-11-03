import 'dart:async';

import 'package:attune/core/providers/shared_prefs_provider.dart';
import 'package:attune/features/couple_profile/data/about_us_outbox.dart';
import 'package:attune/features/couple_profile/data/couple_profile_service.dart';
import 'package:attune/features/couple_profile/domain/couple_profile.dart';
import 'package:attune/features/onboarding/presentation/providers/flow_flags.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersRepositoryProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/home/home_seams.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The outbox of the account signed in when it is called, or null
/// (signed out, or no SharedPreferences in a bare test host).
typedef AboutUsOutboxReader = AboutUsOutbox? Function();

/// Preflight F-1 (shared phones): a reader, not an outbox. The app's
/// ProviderScope outlives a sign-out and homeAuthProvider's object never
/// changes, so an outbox built once would keep the first account's id for
/// the whole run (a passive sign-out runs no wipe). Each call reads the
/// account signed in now, and the outbox it returns checks that account
/// again before each replayed send.
final aboutUsOutboxProvider = Provider<AboutUsOutboxReader>((ref) {
  final auth = ref.watch(homeAuthProvider);
  return () {
    final userId = auth.currentUser?.id;
    if (userId == null) return null;
    try {
      return AboutUsOutbox(
        ref.read(sharedPreferencesProvider),
        userId: userId,
        currentUserId: () => auth.currentUser?.id,
      );
    } catch (_) {
      return null;
    }
  };
});

/// The signed-in account's active relationship, read fresh at each call
/// (never cached across accounts), or null. Batch-3 fix round 1 (ruling
/// I-4): where a draft answer queued before the accept is re-routed.
final aboutUsLinkedRelationshipIdProvider =
    Provider<Future<String?> Function()>(
      (ref) => () async {
        final client = Supabase.instance.client;
        final userId = client.auth.currentUser?.id;
        if (userId == null) return null;
        final row = await client
            .from('relationships')
            .select('id')
            .eq('status', 'active')
            .or('user_a.eq.$userId,user_b.eq.$userId')
            .maybeSingle()
            .timeout(CoupleProfileService.timeout);
        return row?['id'] as String?;
      },
    );

/// Replays the signed-in account's queued About us answers (spec §3.14),
/// for OnboardingSyncService's flush on launch, resume and sign-in. With
/// About us off (the kill switch), nothing is sent and the answers stay
/// queued (fix round 1, M-1).
final aboutUsOutboxFlushProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    if (!ref.read(coupleProfileEnabledProvider)) return;
    final outbox = ref.read(aboutUsOutboxProvider)();
    if (outbox == null) return;
    await outbox.flush(
      ref.read(coupleProfileServiceProvider),
      linkedRelationshipId: ref.read(aboutUsLinkedRelationshipIdProvider),
    );
  },
);

/// W5 final review M-2 (ruling "M-2 replaced"): true when the relationship
/// already has a yearly anniversary-type reminder About us doesn't keep
/// (made by hand), beside which sync_anniversary_reminder adds none of its
/// own, so AU6 says so. False when it can't be read.
final aboutUsHandMadeAnniversaryProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, relationshipId) async {
      try {
        final reminders = await ref
            .read(remindersRepositoryProvider)
            .listReminders(relationshipId)
            .timeout(CoupleProfileService.timeout);
        return reminders.any(
          (r) => r.reminderType == 'anniversary' && r.recurrence == 'yearly',
        );
      } catch (_) {
        return false;
      }
    });

/// What a save did (spec §3.8 Errors): saved, or kept on this phone to
/// replay when back online.
enum AboutUsSaveOutcome { saved, queued }

/// One About us target's answers (spec §5.3 `coupleProfileProvider`,
/// `coupleProfileDraftProvider`): fetched on open; the shared profile also
/// refetches on every together signal (either phone's edit, a reminder
/// change). A queued offline answer is shown on top until it is sent.
///
/// Shared phones (F-1): it belongs to the account signed in when it was
/// built. Another account signing in rebuilds it (that account's own
/// answers, never the last one's), and until then it sends and queues
/// nothing.
class CoupleProfileNotifier
    extends AutoDisposeFamilyAsyncNotifier<CoupleProfile, AboutUsTarget> {
  String? _userId;

  bool get _sameAccount =>
      ref.read(homeAuthProvider).currentUser?.id == _userId;

  /// This account's outbox, or null (signed out, or another account now).
  AboutUsOutbox? _outbox() {
    final outbox = ref.read(aboutUsOutboxProvider)();
    return outbox != null && outbox.userId == _userId ? outbox : null;
  }

  @override
  Future<CoupleProfile> build(AboutUsTarget target) async {
    final auth = ref.watch(homeAuthProvider);
    _userId = auth.currentUser?.id;
    final changes = auth.authStateChanges.listen((_) {
      if (auth.currentUser?.id != _userId) ref.invalidateSelf();
    });
    ref.onDispose(changes.cancel);
    final id = target.relationshipId;
    if (id != null) {
      ref.listen(togetherChangeSignalProvider(id), (previous, _) {
        // The first event is the subscription itself, not a change.
        if (previous == null || previous.isLoading) return;
        unawaited(_refetch());
      });
    }
    return _load(target);
  }

  Future<CoupleProfile> _load(AboutUsTarget target) async {
    final me = _userId;
    final outbox = _outbox();
    final service = ref.read(coupleProfileServiceProvider);
    // Something owed for this target: send it first, so the answer read
    // back is the latest (the last write wins, attributed now).
    if (outbox?.pending(target) != null) {
      await outbox!.flush(
        service,
        linkedRelationshipId: ref.read(aboutUsLinkedRelationshipIdProvider),
      );
      // Fix round 1, M-3: an await can outlast the account.
      if (!_stillFor(me)) throw const AboutUsOffline();
    }
    final profile = await service.fetch(target);
    if (!_stillFor(me)) throw const AboutUsOffline();
    final owed = outbox?.pending(target);
    return owed == null ? profile : profile.applying(owed);
  }

  /// True while [me] is still the account this was built for and the one
  /// signed in (an await can outlast a session).
  bool _stillFor(String? me) => _userId == me && _sameAccount;

  Future<void> _refetch() async {
    final me = _userId;
    if (!_stillFor(me)) return;
    try {
      final profile = await _load(arg);
      if (_stillFor(me)) state = AsyncData(profile);
    } catch (error) {
      debugPrint('[about-us] refetch failed: ${error.runtimeType}');
    }
  }

  /// Saves one answer. Offline: queued on this phone and shown at once;
  /// a refusal is rethrown for the screen to put in words. Another account
  /// signed in since this was built: nothing is sent or queued
  /// (AboutUsOffline), and an answer that was on its way is never queued
  /// for, or shown to, the next account.
  ///
  /// B3 fix round 2 (NI-1, NM-1): answers still queued for this target go
  /// first, each on its own as the replay sends them (a refusal drops only
  /// the one refused), then this one on its own, so a later replay can
  /// never undo it. While one is still owed, this one queues behind it.
  ///
  /// Fix round 5: a save to the shared profile first replays this
  /// account's queued draft answers (re-routed to the shared profile, as
  /// the replay does after the accept), so an older draft answer can never
  /// overwrite it later. The account is checked again after that replay.
  Future<AboutUsSaveOutcome> save(AboutUsPatch patch) async {
    final me = _userId;
    if (!_stillFor(me)) throw const AboutUsOffline();
    final service = ref.read(coupleProfileServiceProvider);
    final outbox = _outbox();
    const draft = AboutUsTarget.draft();
    if (outbox != null && !arg.isDraft && outbox.pending(draft) != null) {
      final replay = await outbox.flushTarget(
        service,
        draft,
        linkedRelationshipId: ref.read(aboutUsLinkedRelationshipIdProvider),
      );
      if (replay == AboutUsReplay.stopped || !_stillFor(me)) {
        throw const AboutUsOffline();
      }
      if (replay == AboutUsReplay.kept) return _queue(outbox, patch, me);
    }
    if (outbox != null && outbox.pending(arg) != null) {
      final replay = await outbox.flushTarget(
        service,
        arg,
        linkedRelationshipId: ref.read(aboutUsLinkedRelationshipIdProvider),
      );
      if (replay == AboutUsReplay.stopped || !_stillFor(me)) {
        throw const AboutUsOffline();
      }
      if (replay == AboutUsReplay.kept) return _queue(outbox, patch, me);
    }
    try {
      final saved = await service.update(arg, patch);
      if (_stillFor(me)) state = AsyncData(saved);
      return AboutUsSaveOutcome.saved;
    } on AboutUsOffline {
      final box = _stillFor(me) ? _outbox() : null;
      if (box == null) rethrow;
      return _queue(box, patch, me);
    }
  }

  /// Keeps [patch] on this phone, after anything already owed, and shows
  /// it at once.
  Future<AboutUsSaveOutcome> _queue(
    AboutUsOutbox outbox,
    AboutUsPatch patch,
    String? me,
  ) async {
    await outbox.enqueue(arg, patch);
    final current = state.valueOrNull;
    if (current != null && _stillFor(me)) {
      state = AsyncData(current.applying(patch));
    }
    return AboutUsSaveOutcome.queued;
  }
}

final coupleProfileProvider = AsyncNotifierProvider.autoDispose
    .family<CoupleProfileNotifier, CoupleProfile, AboutUsTarget>(
      CoupleProfileNotifier.new,
    );

/// The draft before linking (spec §5.3): the same notifier, the draft
/// target.
final coupleProfileDraftProvider = coupleProfileProvider(
  const AboutUsTarget.draft(),
);

/// AU2's suggested-date chips (spec §3.8, review I-12): none from Spec 1.
/// Spec 2 W9 overrides this from get_dating_link_origin ("The day you
/// matched: {date}"); a suggestion is never pre-filled.
final aboutUsDateSuggestionsProvider = Provider.autoDispose
    .family<List<AboutUsDateSuggestion>, String>(
      (ref, relationshipId) => const [],
    );

/// One AU2 chip: its words and the date it fills in when tapped.
@immutable
class AboutUsDateSuggestion {
  const AboutUsDateSuggestion({required this.label, required this.since});

  final String label;
  final TogetherSince since;
}
