// Spec 2 W2 (D0; D8 shared phones): everything here belongs to the
// signed-in account, lives in memory only, and is read again when the
// account changes (another account on the same phone never sees it).
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/gentle_wait/gentle_wait_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in account's id (null when signed out).
final gentleWaitAccountProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

final gentleWaitGatewayProvider = Provider<GentleWaitGateway>(
  (ref) => GentleWaitRepository(Supabase.instance.client),
);

/// D0's data, one entry per account (D8, batch 5 fix round 1 I-2): the
/// next account's entry starts empty, never holding the last one's answers
/// as a previous value, and the last one's is disposed with its listeners
/// (and when D0 closes).
final gentleWaitProvider = FutureProvider.autoDispose
    .family<GentleWait, String?>((ref, account) {
      return ref.read(gentleWaitGatewayProvider).read();
    });

/// Whether the phone has a connection (§3.0 offline rule). Dating keeps
/// its own: it imports nothing from the chat feature (§7.4).
final datingOnlineProvider = StreamProvider.autoDispose<bool>((ref) async* {
  final connectivity = Connectivity();
  yield await connectivity.checkConnectivity() != ConnectivityResult.none;
  await for (final result in connectivity.onConnectivityChanged) {
    yield result != ConnectivityResult.none;
  }
});
