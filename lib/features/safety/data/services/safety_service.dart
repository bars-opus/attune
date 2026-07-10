import 'package:supabase_flutter/supabase_flutter.dart';

class SafetyService {
  final SupabaseClient _supabase;

  SafetyService(this._supabase);

  Future<List<Map<String, dynamic>>> getMySafetyResourceEvents() async {
    final response = await _supabase.rpc('get_my_safety_resource_events');
    if (response is! List) {
      return const <Map<String, dynamic>>[];
    }

    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }
}
