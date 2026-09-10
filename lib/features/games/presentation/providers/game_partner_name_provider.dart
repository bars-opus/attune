import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The partner's name, for any game to address them by.
///
/// Games said "Them" and "Their move". That is how you describe a
/// stranger, and these are two people who chose each other -- a board
/// reading "You 14 / Them 20" is the app being oddly formal about the
/// person sitting next to you.
///
/// One provider rather than a fourth copy: Truth or Dare, 36 Questions
/// and the quiz each grew their own partnerNameProvider against their
/// own repository, so a game could only have a partner's name by
/// depending on an unrelated game's data layer. This one belongs to the
/// games layer and reads the same source they all do.
final gamePartnerNameProvider = FutureProvider<String?>((ref) async {
  final supabase = Supabase.instance.client;
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) return null;

  final relationship =
      await supabase
          .from('relationships')
          .select('user_a, user_b')
          .or('user_a.eq.$userId,user_b.eq.$userId')
          .eq('status', 'active')
          .maybeSingle();
  if (relationship == null) return null;

  final partnerId =
      relationship['user_a'] == userId
          ? relationship['user_b'] as String?
          : relationship['user_a'] as String?;
  if (partnerId == null) return null;

  final profile =
      await supabase
          .from('profiles')
          .select('display_name')
          .eq('id', partnerId)
          .maybeSingle();

  final name = (profile?['display_name'] as String?)?.trim();
  return (name == null || name.isEmpty) ? null : name;
});

/// The partner's name, or a neutral stand-in while it loads or is unset.
///
/// Null rather than a baked-in default comes back from the provider so
/// each caller decides: a board column wants something short, a sentence
/// wants something that reads. Both need SOMETHING, because a label that
/// renders empty is worse than a formal one.
String partnerNameOr(WidgetRef ref, {String fallback = 'Partner'}) {
  final name = ref.watch(gamePartnerNameProvider).valueOrNull;
  return (name == null || name.isEmpty) ? fallback : name;
}
