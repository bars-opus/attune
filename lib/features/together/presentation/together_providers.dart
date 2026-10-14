import 'package:attune/features/planning/presentation/planning_providers.dart'
    show planningChangeSignalProvider;
import 'package:attune/features/timeline/presentation/providers/timeline_providers.dart'
    show togetherChangeSignalProvider;
import 'package:attune/core/config/env.dart';
import 'package:attune/core/utils/timezone_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/calendar_exporter.dart';
import '../data/device_busy_source.dart';
import '../data/share_intake.dart';
import '../data/together_ai_repository.dart';
import '../data/together_calendar_mirror.dart';
import '../data/together_live_activity.dart';
import '../data/together_widget_sync.dart';
import '../data/together_repository.dart';
import '../domain/calendar_feed.dart';
import '../domain/together_agenda.dart';
import '../domain/together_item.dart';
import '../domain/together_need.dart';
import '../domain/together_overlay.dart';
import '../domain/together_prefs.dart';
import '../domain/together_ritual.dart';
import '../domain/together_story.dart';

final togetherRepositoryProvider = Provider<TogetherRepository>(
  (ref) =>
      TogetherRepository(SupabaseTogetherRpcGateway(Supabase.instance.client)),
);

typedef TogetherRangeArgs =
    ({String relationshipId, DateTime start, DateTime end});

/// Everything on the couple's calendar between two dates (≤ 93 days).
/// Refetches on any Together change (events, moments, reminders) and any
/// Planning change, since Planning dates and to-dos are in it too.
final togetherRangeProvider = FutureProvider.autoDispose
    .family<List<TogetherItem>, TogetherRangeArgs>((ref, a) {
      ref.listen(
        togetherChangeSignalProvider(a.relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      ref.listen(
        planningChangeSignalProvider(a.relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      return ref
          .watch(togetherRepositoryProvider)
          .listItems(a.relationshipId, start: a.start, end: a.end);
    });

/// The signed-in user.
final togetherMeProvider = Provider<String?>(
  (ref) => Supabase.instance.client.auth.currentUser?.id,
);

/// The other member of the active relationship.
final togetherPartnerIdProvider = FutureProvider<String?>((ref) async {
  final me = ref.watch(togetherMeProvider);
  if (me == null) return null;
  final row =
      await Supabase.instance.client
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$me,user_b.eq.$me')
          .eq('status', 'active')
          .maybeSingle();
  if (row == null) return null;
  return (row['user_a'] == me ? row['user_b'] : row['user_a']) as String?;
});

/// The device's IANA zone, so a weekly 19:00 stays 19:00 across DST.
final togetherDeviceTimezoneProvider = FutureProvider<String>((ref) async {
  try {
    return await TimezoneUtils.getDeviceTimezone();
  } catch (_) {
    return 'UTC';
  }
});

/// "Now", overridable in tests.
final togetherClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The Agenda: the next 91 days of plans plus the last 93 days of moments.
final togetherAgendaProvider = FutureProvider.autoDispose
    .family<TogetherAgenda, String>((ref, relationshipId) async {
      final now = ref.watch(togetherClockProvider)();
      final up = togetherUpcomingRange(now);
      final past = togetherPastRange(now);
      final results = await Future.wait([
        ref.watch(
          togetherRangeProvider((
            relationshipId: relationshipId,
            start: up.start,
            end: up.end,
          )).future,
        ),
        ref.watch(
          togetherRangeProvider((
            relationshipId: relationshipId,
            start: past.start,
            end: past.end,
          )).future,
        ),
      ]);
      return togetherAgenda(
        upcoming: results[0],
        past: results[1],
        now: now,
        me: ref.watch(togetherMeProvider),
      );
    });

/// What's waiting on me (and my proposals waiting on my partner).
final togetherNeedsProvider = FutureProvider.autoDispose
    .family<List<TogetherNeed>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      ref.listen(
        planningChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      return ref.watch(togetherRepositoryProvider).listNeeds(relationshipId);
    });

final togetherPrefsProvider = FutureProvider.autoDispose
    .family<TogetherPrefs, String>(
      (ref, relationshipId) =>
          ref.watch(togetherRepositoryProvider).getPrefs(relationshipId),
    );

final togetherRitualsProvider = FutureProvider.autoDispose
    .family<List<TogetherRitual>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      return ref.watch(togetherRepositoryProvider).listRituals(relationshipId);
    });

/// Lived shared events I could add a line about (Phase 4 R4).
final togetherMemoryPromptsProvider = FutureProvider.autoDispose
    .family<List<MemoryPrompt>, String>((ref, relationshipId) async {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      final tz = await ref.watch(togetherDeviceTimezoneProvider.future);
      return ref
          .watch(togetherRepositoryProvider)
          .listMemoryPrompts(relationshipId, tz: tz);
    });

/// Earlier years on today's date (Phase 4 R6).
final togetherOnThisDayProvider = FutureProvider.autoDispose
    .family<List<OnThisDayItem>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      final now = ref.watch(togetherClockProvider)();
      return ref
          .watch(togetherRepositoryProvider)
          .listOnThisDay(
            relationshipId,
            DateTime(now.year, now.month, now.day),
          );
    });

/// A ritual's memories (Phase 4 R9).
final togetherRitualMemoriesProvider = FutureProvider.autoDispose
    .family<List<RitualMemory>, String>(
      (ref, ritualId) =>
          ref.watch(togetherRepositoryProvider).listRitualMemories(ritualId),
    );

/// The project URL the calendar link points at.
final togetherSupabaseUrlProvider = Provider<String>(
  (ref) => Environment.supabaseUrl,
);

final togetherCalendarFeedProvider =
    FutureProvider.autoDispose<CalendarFeedStatus>(
      (ref) => ref.watch(togetherRepositoryProvider).getCalendarFeedStatus(),
    );

/// Opens the phone's own calendar editor (Phase 5 R6).
final calendarExporterProvider = Provider<CalendarExporter>(
  (ref) => const Add2CalendarExporter(),
);

final deviceBusySourceProvider = Provider<DeviceBusySource>(
  (ref) => const DeviceCalendarPlusSource(),
);

final togetherOverlayProvider = FutureProvider.autoDispose
    .family<OverlayLevel, String>(
      (ref, relationshipId) =>
          ref.watch(togetherRepositoryProvider).getOverlay(relationshipId),
    );

/// When we're both free (empty unless both of us opted in).
final togetherFreeWindowsProvider = FutureProvider.autoDispose
    .family<List<FreeWindow>, String>((ref, relationshipId) {
      ref.listen(
        togetherChangeSignalProvider(relationshipId),
        (_, __) => ref.invalidateSelf(),
      );
      return ref
          .watch(togetherRepositoryProvider)
          .listFreeWindows(relationshipId);
    });

final togetherBusyStripsProvider = FutureProvider.autoDispose
    .family<List<BusyStrip>, String>(
      (ref, relationshipId) =>
          ref.watch(togetherRepositoryProvider).listBusyStrips(relationshipId),
    );

/// Reads my calendar's busy times and replaces what's on the server, if my
/// overlay is on and the phone lets us read (plan R4). Never throws.
Future<bool> syncBusyTimes(
  TogetherRepository repo,
  DeviceBusySource source,
  String relationshipId,
  DateTime now,
) async {
  try {
    if (await repo.getOverlay(relationshipId) == OverlayLevel.off) return false;
    if (!await source.hasAccess()) return false;
    // Our own plans, copied into the phone (Phase 8d), are already busy on
    // the server (§8.9 R3): never upload them again.
    final copy = await TogetherMirror.calendarId();
    final events = [
      for (final e in await source.read(now, now.add(const Duration(days: 14))))
        if (copy == null || e.calendarId != copy) e,
    ];
    await repo.replaceBusyBlocks(relationshipId, busyBlocksFrom(events, now));
    return true;
  } catch (_) {
    return false;
  }
}

final togetherAiRepositoryProvider = Provider<TogetherAiRepository>(
  (ref) =>
      TogetherAiRepository(SupabaseTogetherAiGateway(Supabase.instance.client)),
);

/// Whether Together's AI may run for this couple (flag on, both consented).
final togetherAiAvailableProvider = FutureProvider.autoDispose
    .family<bool, String>(
      (ref, relationshipId) async =>
          (await ref
              .watch(togetherAiRepositoryProvider)
              .status(relationshipId)).available,
    );

/// The home-screen card, opted into on this phone (Phase 8a R2). Off by default.
class TogetherWidgetEnabled extends AsyncNotifier<bool> {
  static const key = enabledKey;

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> set(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherWidgetSync.clear();
    state = AsyncData(on);
  }
}

final togetherWidgetEnabledProvider =
    AsyncNotifierProvider<TogetherWidgetEnabled, bool>(
      TogetherWidgetEnabled.new,
    );

/// The lock-screen plan, opted into on this phone (Phase 8c R4). Off by
/// default.
class TogetherLiveEnabled extends AsyncNotifier<bool> {
  static const key = liveEnabledKey;

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  Future<void> set(bool on) async {
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherLiveActivity.end();
    state = AsyncData(on);
  }
}

final togetherLiveEnabledProvider =
    AsyncNotifierProvider<TogetherLiveEnabled, bool>(TogetherLiveEnabled.new);

/// Whether this phone can show it at all (iOS 16.2+, allowed in Settings).
final togetherLiveSupportedProvider = FutureProvider<bool>(
  (ref) => TogetherLiveActivity.isSupported(),
);

/// The calendar copy, opted into on this phone (Phase 8d). Off by default.
class TogetherMirrorEnabled extends AsyncNotifier<bool> {
  static const key = mirrorEnabledKey;

  @override
  Future<bool> build() async =>
      (await SharedPreferences.getInstance()).getBool(key) ?? false;

  /// Turning it on needs calendar access first; refused, it stays off and
  /// this returns false so the caller can say how to allow it.
  Future<bool> set(bool on) async {
    if (on && !await TogetherMirror.ensureAccess()) {
      state = const AsyncData(false);
      return false;
    }
    await (await SharedPreferences.getInstance()).setBool(key, on);
    if (!on) await TogetherMirror.clear();
    state = AsyncData(on);
    return true;
  }
}

final togetherMirrorEnabledProvider =
    AsyncNotifierProvider<TogetherMirrorEnabled, bool>(
      TogetherMirrorEnabled.new,
    );

final shareSourceProvider = Provider<ShareSource>(
  (ref) => const ReceiveSharingIntentSource(),
);

/// A note shared from another app, waiting for Together (Phase 8b R3).
class PendingShare {
  const PendingShare(this.text, this.at);
  final String text;
  final DateTime at;

  bool expiredAt(DateTime now) =>
      now.difference(at) > const Duration(minutes: 10);
}

final pendingShareProvider = StateProvider<PendingShare?>((ref) => null);
