// Spec 2 W3c (§3.2 D12, D8): the person's own card, one entry per account,
// memory only.
import 'package:attune/features/dating/card/dating_card.dart';
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/photos/dating_photos_providers.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart'
    show DatingPhotoList;
import 'package:attune/features/dating/setup/dating_setup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class DatingPreviewGateway {
  Future<DatingCard?> preview();
}

class DatingPreviewRepository implements DatingPreviewGateway {
  DatingPreviewRepository(this._rpc);

  final DatingRpc _rpc;

  @override
  Future<DatingCard?> preview() async {
    final raw = await _rpc.call('get_dating_profile_preview');
    if (raw is! Map || raw['ok'] != true) {
      throw StateError('preview:${raw is Map ? raw['reason'] : 'shape'}');
    }
    final card = raw['card'];
    return card is Map
        ? DatingCard.fromJson(Map<String, dynamic>.from(card))
        : null;
  }
}

final datingPreviewGatewayProvider = Provider<DatingPreviewGateway>(
  (ref) => DatingPreviewRepository(ref.watch(datingRpcProvider)),
);

final datingPreviewProvider = FutureProvider.autoDispose
    .family<DatingCard?, String?>((ref, account) async {
      if (account == null) return null;
      // A saved answer or a photo change (an edit link, R-40) reads the card
      // again: only when a value already read changes, so opening the step
      // reads it once, and D9's checks (still mounted below) re-read nothing
      // until a photo really changes.
      void again<T>(T? previous, T? next) {
        if (previous != null && previous != next) ref.invalidateSelf();
      }

      ref.listen(
        datingMyProfileProvider(account).select((v) => v.valueOrNull),
        again,
      );
      ref.listen(
        datingPhotosProvider(account).select(
          (v) => switch (v.valueOrNull) {
            final list? => datingPhotoSignature(list),
            null => null,
          },
        ),
        again,
      );
      return ref.read(datingPreviewGatewayProvider).preview();
    });

/// What the card shows of the photos: which, where, and whether each may
/// show (never a caption or a storage key).
String datingPhotoSignature(DatingPhotoList list) => [
  list.afterMutual,
  for (final p in list.photos) '${p.id}:${p.position}:${p.moderationState}',
].join(',');
