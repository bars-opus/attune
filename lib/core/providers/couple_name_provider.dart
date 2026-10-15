import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The name the couple chose for themselves (the chat name either partner
/// sets, e.g. "The Harolds"); null until one is chosen.
final coupleNameProvider = FutureProvider.autoDispose.family<String?, String>((
  ref,
  relationshipId,
) async {
  final row =
      await Supabase.instance.client
          .from('relationships')
          .select('chat_name')
          .eq('id', relationshipId)
          .maybeSingle();
  final name = (row?['chat_name'] as String?)?.trim();
  return name == null || name.isEmpty ? null : name;
});

/// The couple on its own ("The Harolds"), or "Couples" until they choose.
String coupleLabel(String? name) => name ?? 'Couples';

/// The couple inside a sentence ("A ritual for The Harolds"), or "couples".
String coupleInSentence(String? name) => name ?? 'couples';

/// The couple's journal: "The Harolds' journal", "Desmond's journal", or
/// "Couples journal" until a name is chosen.
String coupleJournalTitle(String? name) {
  if (name == null) return 'Couples journal';
  return name.endsWith('s') ? "$name' journal" : "$name's journal";
}
