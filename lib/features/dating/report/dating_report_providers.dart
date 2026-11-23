// Spec 2 W7a (§3.7; D8 shared phones): the report gateway, and the
// restricted person's read, one entry per account, in memory only.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_rpc.dart';
import 'package:attune/features/dating/lock/dating_unlock.dart'
    show DatingSessionMemory;
import 'package:attune/features/dating/report/dating_report.dart';
import 'package:attune/features/dating/report/dating_report_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final datingReportGatewayProvider = Provider<DatingReportGateway>(
  (ref) => DatingReportRepository(ref.watch(datingRpcProvider)),
);

/// The restriction [account] sees: the next account's entry starts
/// loading, never holding the last one's.
final datingRestrictionProvider = FutureProvider.autoDispose
    .family<DatingRestrictionRead, String?>((ref, account) async {
      if (account == null) return DatingRestrictionRead.none;
      return ref.read(datingReportGatewayProvider).restriction();
    });

/// Fix round 1 (I-1): the report's request keys, one store per account
/// (memory only, D8), so a sheet opened again after a busy or failed
/// answer sends the same request (the server files it once); an answer
/// that is final frees the key. Spec 2 W8a (§6.7): a key's
/// signature holds what was typed, so quick exit and sign-out empty it
/// (Dating's session entry in the device wipe registry).
final datingReportKeysProvider = Provider.family<DatingActionKeys, String?>((
  ref,
  account,
) {
  final keys = DatingActionKeys();
  DatingSessionMemory.track(keys, ref, keys.clear);
  return keys;
});
