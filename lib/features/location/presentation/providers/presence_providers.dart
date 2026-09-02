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
        // Records our own position before reading the distance: the
        // server refuses to answer unless BOTH partners are sharing, so a
        // stale own-position would silently blank the row.
        await repository.recordOwnPresence();
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
