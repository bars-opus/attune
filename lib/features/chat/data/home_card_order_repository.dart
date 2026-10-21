import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a person's own order for the Conversations cards (below the chat)
/// is kept: user_preferences.home_card_order, private to them.
abstract class HomeCardOrderRepository {
  /// Their saved order of card ids, or null for the default.
  Future<List<String>?> load();

  Future<void> save(List<String> order);
}

class SupabaseHomeCardOrderRepository implements HomeCardOrderRepository {
  SupabaseHomeCardOrderRepository(this._client);
  final SupabaseClient _client;

  String? get _me => _client.auth.currentUser?.id;

  @override
  Future<List<String>?> load() async {
    final me = _me;
    if (me == null) return null;
    final row =
        await _client
            .from('user_preferences')
            .select('home_card_order')
            .eq('user_id', me)
            .maybeSingle();
    final order = row?['home_card_order'];
    return order is List ? [for (final id in order) id as String] : null;
  }

  @override
  Future<void> save(List<String> order) async {
    final me = _me;
    if (me == null) return;
    // Their own row only (RLS); the rest of their preferences stay as set.
    await _client.from('user_preferences').upsert({
      'user_id': me,
      'home_card_order': order,
    }, onConflict: 'user_id');
  }
}

final homeCardOrderRepositoryProvider = Provider<HomeCardOrderRepository>(
  (ref) => SupabaseHomeCardOrderRepository(ref.watch(supabaseClientProvider)),
);
