import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records and reads EULA acceptance, so the agreement is presented once per
/// user (or again after the terms change) rather than on every sign-in.
///
/// Acceptance lives on public.users via record_eula_acceptance /
/// get_eula_acceptance (see 20260814120000_eula_acceptance.sql). Both are
/// SECURITY DEFINER and scoped to auth.uid(), so a caller can only ever read
/// or write their own acceptance.
class EulaAcceptanceService {
  EulaAcceptanceService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const timeout = Duration(seconds: 15);

  /// Bump when the EULA text materially changes — anyone whose stored version
  /// differs is prompted again. Keep in sync with the copy in
  /// LegalDocumentationData.eula.
  static const currentVersion = '1';

  SupabaseClient? get _safeClient {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// True when the signed-in user still needs to accept the current EULA.
  ///
  /// Fails closed: if the check itself errors (offline, RPC unavailable), the
  /// caller is told acceptance IS required rather than silently skipping
  /// consent. Showing the sheet one extra time is the recoverable failure;
  /// letting someone through without agreeing is not.
  Future<bool> needsAcceptance() async {
    final client = _safeClient;
    if (client == null || client.auth.currentUser == null) return true;

    try {
      final accepted = await client
          .rpc('get_eula_acceptance')
          .timeout(timeout);
      return accepted != currentVersion;
    } catch (error) {
      debugPrint('[eula] acceptance check failed: ${error.runtimeType}');
      return true;
    }
  }

  /// Records acceptance of the current EULA version for the signed-in user.
  /// Throws on failure so the caller can keep the user on the consent step
  /// instead of advancing as though consent was captured.
  Future<void> recordAcceptance() async {
    final client = _safeClient;
    if (client == null || client.auth.currentUser == null) {
      throw StateError('Cannot record EULA acceptance without a signed-in user');
    }

    await client
        .rpc('record_eula_acceptance', params: {'p_version': currentVersion})
        .timeout(timeout);
  }
}
