// Spec 2 W3a (§4.10 per-state providers; D8 shared phones): every Dating
// read belongs to the signed-in account, lives in memory only, and is
// disposed when nothing shows it. Another account on the same phone starts
// from nothing.
import 'package:attune/features/auth/providers/auth_provider.dart'
    show currentUserProvider;
import 'package:attune/features/dating/data/dating_home.dart';
import 'package:attune/features/dating/data/dating_home_repository.dart';
import 'package:attune/features/dating/data/dating_lifecycle_repository.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The signed-in account's id (null when signed out).
final datingAccountProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider.select((u) => u?.id)),
);

final datingRpcProvider = Provider<DatingRpc>(
  (ref) => DatingRpc(ref.watch(datingSupabaseClientProvider)),
);

final datingHomeGatewayProvider = Provider<DatingHomeGateway>(
  (ref) => DatingHomeRepository(ref.watch(datingRpcProvider)),
);

final datingLifecycleGatewayProvider = Provider<DatingLifecycleGateway>(
  (ref) => DatingLifecycleRepository(ref.watch(datingRpcProvider)),
);

/// The home, one entry per account: the next account's entry starts as a
/// plain loading value, never holding the last one's state.
final datingHomeProvider = FutureProvider.autoDispose
    .family<DatingHome, String?>((ref, account) async {
      if (account == null) {
        return const DatingHome(state: DatingHomeState.unavailable);
      }
      return ref.read(datingHomeGatewayProvider).read();
    });

/// The countries Dating is open in. Config only, with no personal data, so
/// it is the one Dating provider not keyed to the account (D8 exception).
final datingAvailabilityProvider =
    FutureProvider.autoDispose<DatingAvailability>(
      (ref) => ref.read(datingHomeGatewayProvider).availability(),
    );
