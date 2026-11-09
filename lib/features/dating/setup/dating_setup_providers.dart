// Spec 2 W3b (D8): the setup lists and the person's own answers, one entry
// per account, memory only, disposed with the step that shows them.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/setup/dating_setup_models.dart';
import 'package:attune/features/dating/setup/dating_setup_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingSetupGatewayProvider = Provider<DatingSetupGateway>(
  (ref) => DatingSetupRepository(ref.watch(datingRpcProvider)),
);

final datingSetupListsProvider = FutureProvider.autoDispose
    .family<DatingSetupLists, String?>((ref, account) async {
      if (account == null) return const DatingSetupLists();
      return ref.read(datingSetupGatewayProvider).lists();
    });

final datingMyProfileProvider = FutureProvider.autoDispose
    .family<DatingMyProfile, String?>((ref, account) async {
      if (account == null) return const DatingMyProfile(exists: false);
      return ref.read(datingSetupGatewayProvider).myProfile();
    });
