// Spec 2 W4b (§3.3.4, S-7, C-6, R15): the one Supabase client every Dating
// repository uses. Dating's own client: every request it makes (RPC,
// edge function, storage) carries this install's id as x-attune-device,
// and it signs in with the app's current session token. No other request
// carries the id, so Opinions and couples traffic can't be linked to the
// hash Dating stores; the app's own client and lib/main.dart are not
// changed. Without the project's config (a build with no backend) it is
// the app's own client, as before. Fix round 1: the session token is
// refreshed first when expired (I-1); the builder is its own function, so
// its wiring is tested (I-2); datingDeviceReadyProvider says whether the
// phone has an id at all (I-4).
import 'package:attune/core/config/env.dart';
import 'package:attune/core/device/install_id.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// The trusted-device header (the server reads only this name).
const datingDeviceHeader = 'x-attune-device';

/// Adds the install's id to each request; without one (or when it can't
/// be read), sends it as is: the server then treats the phone as
/// untrusted once Dating is bound, and answers reverify_device.
class DatingDeviceHttpClient extends http.BaseClient {
  DatingDeviceHttpClient(this._deviceId, [http.Client? inner])
    : _inner = inner ?? http.Client();

  final Future<String?> Function() _deviceId;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String? id;
    try {
      id = await _deviceId();
    } catch (_) {
      id = null;
    }
    if (id != null) request.headers[datingDeviceHeader] = id;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

/// Fix round 1 (I-1): the app's session token for a Dating request. With
/// its own accessToken callback the Dating client skips the refresh the
/// app's client runs before each request, so an expired session (the first
/// reads after a long resume) is refreshed here first (gotrue shares one
/// refresh between concurrent callers). A refresh that fails sends the
/// current token, and the server answers 401, as it would the app's client.
Future<String?> datingAccessToken(GoTrueClient auth) async {
  if (auth.currentSession?.isExpired ?? false) {
    try {
      await auth.refreshSession();
    } catch (_) {
      // the current token: a 401, as on the app's own client
    }
  }
  return auth.currentSession?.accessToken;
}

/// Fix round 1 (I-2): the Dating client itself: every request through
/// [DatingDeviceHttpClient] (RPC, edge functions, storage), signed in with
/// [accessToken], never refreshing a session of its own.
SupabaseClient datingSupabaseClient({
  required String url,
  required String key,
  required Future<String?> Function() deviceId,
  required Future<String?> Function() accessToken,
  http.Client? inner,
}) => SupabaseClient(
  url,
  key,
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: DatingDeviceHttpClient(deviceId, inner),
  accessToken: accessToken,
);

final datingSupabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (Environment.supabaseUrl.isEmpty || Environment.supabaseAnonKey.isEmpty) {
    return Supabase.instance.client;
  }
  final app = Supabase.instance.client;
  final client = datingSupabaseClient(
    url: Environment.supabaseUrl,
    key: Environment.supabaseAnonKey,
    deviceId: ref.watch(installIdStoreProvider).ensure,
    accessToken: () => datingAccessToken(app.auth),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Fix round 1 (I-4 ruling): whether this phone has an install id. False
/// (a keystore that can't be read or written) means no Dating request can
/// name the phone: the server answers reverify_device and the checks
/// device_unavailable, so the app shows a calm line and never offers the
/// re-check (Task 7), which could only answer the same.
final datingDeviceReadyProvider = FutureProvider.autoDispose<bool>(
  (ref) async => (await ref.watch(installIdStoreProvider).ensure()) != null,
);
