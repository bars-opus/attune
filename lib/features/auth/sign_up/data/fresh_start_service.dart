import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What start-fresh-account answered (Spec 1 W6a, §3.5 DM1, §4.5).
enum FreshStartResult {
  /// The old account is parked; a new code makes a new account.
  done,

  /// The nonce can't be used (used, older than 15 minutes, not ours).
  invalid,

  /// Five tries an hour from this network.
  tryLater,

  /// Offline, a timeout, or the server couldn't finish.
  unavailable,
}

/// The one call DM1's "I'm new to Attune" makes, with no session.
abstract class FreshStartGateway {
  Future<FreshStartResult> start(String nonce);
}

class SupabaseFreshStartGateway implements FreshStartGateway {
  SupabaseFreshStartGateway(this._functions);

  final FunctionsClient Function() _functions;

  static const timeout = Duration(seconds: 20);

  @override
  Future<FreshStartResult> start(String nonce) async {
    try {
      await _functions()
          .invoke('start-fresh-account', body: {'nonce': nonce})
          .timeout(timeout);
      return FreshStartResult.done;
    } on FunctionException catch (error) {
      return switch (error.status) {
        400 => FreshStartResult.invalid,
        429 => FreshStartResult.tryLater,
        _ => FreshStartResult.unavailable,
      };
    } catch (error) {
      // Never the nonce or the number (spec §4.1 rule 5).
      debugPrint('[fresh-start] failed: ${error.runtimeType}');
      return FreshStartResult.unavailable;
    }
  }
}

final freshStartGatewayProvider = Provider<FreshStartGateway>(
  (ref) => SupabaseFreshStartGateway(() => Supabase.instance.client.functions),
);
