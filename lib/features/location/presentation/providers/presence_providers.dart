import 'dart:async';

import 'package:attune/core/services/app_content_visibility.dart';
import 'package:attune/core/utils/timezone_utils.dart';
import 'package:attune/features/chat/domain/services/chat_feature_flags.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/location/data/presence_gateway.dart';
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/data/presence_sampler.dart';
import 'package:attune/features/location/domain/couple_map_presence.dart';
import 'package:attune/features/location/domain/location_access.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:attune/features/location/domain/presence_config.dart';
import 'package:attune/features/location/domain/reunion.dart';
import 'package:attune/features/reminders/presentation/providers/reminders_providers.dart'
    show remindersListProvider;
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

final presenceGatewayProvider = Provider<PresenceGateway>(
  (ref) => SupabasePresenceGateway(ref.watch(supabaseClientProvider)),
);
final presenceSamplerProvider = Provider<PresenceSampler>(
  (ref) => GeolocatorPresenceSampler(),
);
final presenceTimezoneProvider = Provider<Future<String> Function()>(
  (ref) => () {
    // Re-read each time (records are debounced to one a minute): someone
    // who travels would otherwise keep their old zone until a restart.
    TimezoneUtils.clearCache();
    return TimezoneUtils.getDeviceTimezone();
  },
);

final presenceRepositoryProvider = Provider<PresenceRepository>(
  (ref) => PresenceRepository(
    ref.watch(presenceGatewayProvider),
    ref.watch(presenceSamplerProvider),
    ref.watch(presenceTimezoneProvider),
  ),
);

/// Every couple-map presence read, as it lands. The home-screen widget
/// listens here; it must never watch coupleMapPresenceProvider itself, or
/// that autoDispose provider would stay alive and keep sampling (widget
/// spec §4.1).
final presenceReadsProvider =
    Provider<StreamController<(String, CoupleMapPresence)>>((ref) {
      final c = StreamController<(String, CoupleMapPresence)>.broadcast();
      ref.onDispose(c.close);
      return c;
    });

/// The couple map's presence, refreshed on open, on each return to the
/// screen (once the lock is open) and every 15 minutes. Samples ONLY while
/// I'm sharing and not paused: someone who never opted in is never sampled
/// or prompted.
final coupleMapPresenceProvider = StreamProvider.autoDispose.family<
  CoupleMapPresence,
  String
>((ref, relationshipId) {
  final repo = ref.watch(presenceRepositoryProvider);
  final controller = StreamController<CoupleMapPresence>();
  var closed = false;
  var running = false;

  Future<void> refresh() async {
    if (closed || running) return;
    // Never while Attune is not on screen: the map tab stays mounted
    // behind the privacy cover (stories Wave 3), so the 15-minute tick
    // must not sample a fix or record while covered, backgrounded or
    // before the Safety lock opens on a return.
    if (!ref.read(appContentVisibleProvider)) return;
    running = true;
    try {
      var p = await repo.fetchMapPresence(relationshipId);
      if (!closed &&
          p.state.status == PresenceStatus.sharing &&
          await repo.record(relationshipId)) {
        p = await repo.fetchMapPresence(relationshipId);
      }
      if (!closed && !controller.isClosed) {
        controller.add(p);
        try {
          ref.read(presenceReadsProvider).add((relationshipId, p));
        } catch (_) {}
      }
    } catch (e, st) {
      // Surfaces as AsyncError, keeping the last known state as its value.
      if (!closed && !controller.isClosed) controller.addError(e, st);
    } finally {
      running = false;
    }
  }

  unawaited(refresh());
  final timer = Timer.periodic(PresenceConfig.refreshEvery, (_) => refresh());
  // "On app resume" means once Attune is on screen again, after the lock.
  ref.listen<bool>(appContentVisibleProvider, (prev, next) {
    if (next && prev == false) unawaited(refresh());
  });
  ref.onDispose(() {
    closed = true;
    timer.cancel();
    unawaited(controller.close());
  });
  return controller.stream;
});

/// My sharing state for one couple (off / sharing / paused until).
///
/// Not `whenData`: it drops the last value while refreshing and on error,
/// which would flash the privacy toggle Off on every refresh.
final presenceStateProvider = Provider.autoDispose
    .family<AsyncValue<PresenceState>, String>((ref, relationshipId) {
      final presence = ref.watch(coupleMapPresenceProvider(relationshipId));
      final state = presence.valueOrNull?.state;
      final AsyncValue<PresenceState> raw =
          presence.hasError
              ? AsyncError(
                presence.error!,
                presence.stackTrace ?? StackTrace.current,
              )
              : presence.isLoading
              ? const AsyncLoading()
              : AsyncData(state!);
      return state == null ? raw : raw.copyWithPrevious(AsyncData(state));
    });

/// The distance card's data (null when there's no honest answer).
final partnerDistanceProvider = StreamProvider.autoDispose
    .family<PartnerDistance?, String>((ref, relationshipId) async* {
      final p = await ref.watch(
        coupleMapPresenceProvider(relationshipId).future,
      );
      yield p.partnerDistance;
    });

/// The couple map ships dark until this flag is on (spec §9, rollback).
final coupleMapEnabledProvider = FutureProvider<bool>(
  (ref) => ChatFeatureFlags.isEnabled(
    ref.watch(supabaseClientProvider),
    ChatFeatureFlags.coupleMap,
  ),
);

/// Whether this device can take a fix, re-checked when the app resumes
/// (e.g. back from Settings). Never prompts.
final locationAccessProvider = FutureProvider.autoDispose<LocationAccess>((
  ref,
) {
  final lifecycle = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(lifecycle.dispose);
  return ref.watch(presenceSamplerProvider).access();
});

/// The distance with a reunion countdown from the shared calendar.
/// Keeps the last value through refreshes (valueOrNull), so the card
/// doesn't flicker.
final partnerDistanceWithReunionProvider = Provider.autoDispose
    .family<PartnerDistance?, String>((ref, relationshipId) {
      final d = ref.watch(partnerDistanceProvider(relationshipId)).valueOrNull;
      if (d == null) return null;
      final reminders =
          ref.watch(remindersListProvider).valueOrNull ?? const [];
      return withReunion(d, [for (final r in reminders) (r.title, r.remindAt)]);
    });
