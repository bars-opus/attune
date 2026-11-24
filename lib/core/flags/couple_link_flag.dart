// Spec 2 W9 (R-W9-16 as amended; Task 5 fix round 2, review M-7; S-7, R15):
// the one read that tells a couple's Relationship home and About us whether
// dating_couple_link is on. It is made for every couple, Dating or not, so
// it goes on the app's own client and never on Dating's: a person who never
// used Dating sends no install id (Dating's device header stays on its own
// traffic). get_dating_home() carries `couple_link` in every answer it
// gives a signed-in caller, including the one it gives a request with no
// trusted-device header (reverify_device); without the header it stores
// nothing (the trusted-device touch needs this phone's id) and it has no
// other write. Dating's own reads are unchanged (Dating's client).
import 'package:attune/features/auth/providers/auth_provider.dart'
    show supabaseClientProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// get_dating_home()'s raw answer, read on the app's client.
typedef CoupleLinkFlagRead = Future<Object?> Function();

/// Spec 2 W9 final client fix (M-2): the longest the couple link's reads on
/// the app's client wait (the flag read, and the couple side's calls in
/// couple_link_couple_side.dart). A read that hangs (a captive portal, a
/// stalled connection) then fails, and a failed flag read is asked again on
/// the next resume or reconnect.
const kCoupleLinkReadTimeout = Duration(seconds: 10);

final coupleLinkFlagReadProvider = Provider<CoupleLinkFlagRead>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return () async => await client.rpc('get_dating_home');
});
