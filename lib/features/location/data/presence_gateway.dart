import 'package:supabase_flutter/supabase_flutter.dart';

/// The presence RPC seam (tests use a fake; mirrors PlanningRpcGateway).
abstract class PresenceGateway {
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params});
}

class SupabasePresenceGateway implements PresenceGateway {
  SupabasePresenceGateway(this._supabase);
  final SupabaseClient _supabase;
  @override
  Future<dynamic> rpc(String fn, {Map<String, dynamic>? params}) =>
      _supabase.rpc(fn, params: params);
}
