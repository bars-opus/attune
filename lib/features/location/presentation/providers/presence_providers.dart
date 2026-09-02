import 'dart:async';

import 'package:attune/core/services/location_service.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:attune/features/location/data/presence_repository.dart';
import 'package:attune/features/location/domain/partner_distance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final presenceRepositoryProvider = Provider<PresenceRepository>((ref) {
  return PresenceRepository(
    ref.watch(supabaseClientProvider),
    LocationService(),
  );
});

/// Whether this user shares their location at all.
final isSharingPresenceProvider = FutureProvider<bool>((ref) async {
  return ref.watch(presenceRepositoryProvider).isSharing();
});

/// The couple's distance, refreshed periodically.
///
/// Periodic, not live. Distance is a slow-moving fact and the row shows it
/// in buckets anyway, so a live subscription would spend battery to
/// deliver a number that does not change -- and a number that updated in
/// real time would be readable as movement, which is the one thing this
/// feature must not be.
///
/// Fifteen minutes is the floor for sampling; the row itself only changes
/// when a bucket boundary is crossed.
final partnerDistanceProvider = StreamProvider.autoDispose
    .family<PartnerDistance?, String>((ref, relationshipId) {
      final repository = ref.watch(presenceRepositoryProvider);
      final controller = StreamController<PartnerDistance?>();
      Timer? timer;
      var closed = false;

      Future<void> refresh() async {
        if (closed) return;

        // Only refreshes a position that ALREADY exists. Opening the chat
        // list used to record one unconditionally, which meant a user who
        // turned sharing off had it silently switched back on the next
        // time they opened the app -- a privacy toggle that the app
        // overrode. Sharing now starts only from the settings toggle,
        // which is the one place the user asked for it.
        //
        // Still refreshed here rather than only on that tap: the server
        // refuses a distance when either position is stale, so a user who
        // opted in last week would otherwise see the row quietly vanish.
        if (await repository.isSharing()) {
          await repository.recordOwnPresence();
        }
        if (closed) return;
        final distance = await repository.fetchDistance(relationshipId);
        if (closed || controller.isClosed) return;
        controller.add(distance);
      }

      unawaited(refresh());
      timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());

      ref.onDispose(() {
        closed = true;
        timer?.cancel();
        unawaited(controller.close());
      });

      return controller.stream;
    });
