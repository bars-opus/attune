// Spec 2 W9 final client fix (I-1; S-7, R15): the couple side of "Become a
// couple on Attune", on the app's own client: the Relationship home's card
// (its read and its dismiss), the match date for About us and How we met.
// A couple reads them, Dating or not, so they are couples traffic and never
// carry Dating's install id (Dating's device header). None of the four needs
// it: the server checks membership of the relationship, never the trusted
// device. Only these four functions go through here; the chat side (the
// link page's read, asking, the second Yes, Not right now, taking it back)
// stays on Dating's client (DatingLinkRepository).
import 'package:attune/core/flags/couple_link_flag.dart'
    show kCoupleLinkReadTimeout;
import 'package:attune/features/auth/providers/auth_provider.dart'
    show supabaseClientProvider;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The couple side's four functions (any other name is refused).
const coupleLinkCoupleSideFunctions = {
  'get_dating_post_link_offer',
  'dismiss_dating_post_link_offer',
  'get_dating_link_origin',
  'get_how_we_met',
};

/// One couple-side call's raw answer, on the app's client.
typedef CoupleLinkCoupleCall =
    Future<Object?> Function(String fn, Map<String, dynamic> params);

final coupleLinkCoupleCallProvider = Provider<CoupleLinkCoupleCall>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return (fn, params) async {
    if (!coupleLinkCoupleSideFunctions.contains(fn)) {
      throw ArgumentError.value(fn, 'fn', 'not a couple-side call');
    }
    return await client.rpc(fn, params: params).timeout(kCoupleLinkReadTimeout);
  };
});
