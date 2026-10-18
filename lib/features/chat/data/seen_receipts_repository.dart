import 'package:attune/features/chat/domain/seen_receipts.dart';
import 'package:attune/features/games/presentation/providers/games_hub_providers.dart'
    show supabaseClientProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One RPC call. The production value is `SupabaseClient.rpc`; tests pass a
/// recording function.
typedef SeenReceiptsRpc =
    Future<dynamic> Function(String fn, Map<String, dynamic> params);

class SeenReceiptsRepository {
  SeenReceiptsRepository(this._rpc);

  final SeenReceiptsRpc _rpc;

  Future<SeenReceipts> get(String relationshipId) async =>
      SeenReceipts.fromJson(
        await _rpc('get_seen_receipts', {'p_relationship_id': relationshipId}),
      );

  Future<SeenReceipts> set(String relationshipId, bool on) async =>
      SeenReceipts.fromJson(
        await _rpc('set_seen_receipts', {
          'p_relationship_id': relationshipId,
          'p_on': on,
        }),
      );
}

final seenReceiptsRepositoryProvider = Provider<SeenReceiptsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SeenReceiptsRepository((fn, params) => client.rpc(fn, params: params));
});

/// The couple's setting as the server reports it. Off while loading or on
/// error: a privacy toggle must never show "on" for a state it has not
/// confirmed.
final seenReceiptsProvider = FutureProvider.autoDispose
    .family<SeenReceipts, String>(
      (ref, relationshipId) =>
          ref.watch(seenReceiptsRepositoryProvider).get(relationshipId),
    );
