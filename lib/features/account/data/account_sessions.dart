import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One signed-in session on this account (Spec 2; research 06 §3 F7 (1)).
/// Coarse on purpose: a platform label, never an IP or a place.
class SignedInDevice {
  const SignedInDevice({
    required this.sessionId,
    required this.label,
    required this.platform,
    required this.signedInAt,
    required this.lastActiveAt,
    required this.isCurrent,
  });

  factory SignedInDevice.fromRow(Map<String, dynamic> row) => SignedInDevice(
    sessionId: row['session_id'] as String,
    label: row['device_label'] as String?,
    platform: row['platform'] as String?,
    signedInAt: DateTime.parse(row['signed_in_at'] as String),
    lastActiveAt: DateTime.parse(row['last_active_at'] as String),
    isCurrent: row['is_current'] as bool? ?? false,
  );

  final String sessionId;
  final String? label;
  final String? platform;
  final DateTime signedInAt;
  final DateTime lastActiveAt;
  final bool isCurrent;
}

typedef SessionsRpc =
    Future<dynamic> Function(String fn, [Map<String, dynamic>? params]);

class AccountSessionsRepository {
  AccountSessionsRepository(this._rpc, this._signOutOthers);

  final SessionsRpc _rpc;
  final Future<void> Function() _signOutOthers;

  Future<List<SignedInDevice>> list() async {
    final rows = await _rpc('list_my_sessions') as List<dynamic>? ?? const [];
    return [
      for (final r in rows)
        SignedInDevice.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }

  /// Names this session so the other phones can tell it apart.
  Future<void> registerThisDevice() => _rpc('register_my_device', {
    'p_label': thisDeviceLabel(),
    'p_platform': thisDevicePlatform(),
  });

  /// Revokes every other session's refresh token (ruling R2-10).
  Future<void> signOutOtherDevices() => _signOutOthers();
}

String thisDevicePlatform() {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'other';
}

String thisDeviceLabel() {
  if (kIsWeb) return 'Web';
  if (Platform.isIOS) {
    final m = RegExp(
      r'Version ([0-9.]+)',
    ).firstMatch(Platform.operatingSystemVersion);
    return m == null ? 'iPhone or iPad' : 'iPhone or iPad · iOS ${m.group(1)}';
  }
  if (Platform.isAndroid) return 'Android phone';
  return 'This device';
}

/// Sessions in [now] that are not this phone and were not seen before.
/// First run ([known] null) reports nothing: everything there is the baseline.
Set<String> newSessionIds({
  required Set<String>? known,
  required List<SignedInDevice> now,
}) {
  if (known == null) return const {};
  return {
    for (final d in now)
      if (!d.isCurrent && !known.contains(d.sessionId)) d.sessionId,
  };
}

final accountSessionsRepositoryProvider = Provider<AccountSessionsRepository>((
  ref,
) {
  final client = Supabase.instance.client;
  return AccountSessionsRepository(
    (fn, [params]) => client.rpc(fn, params: params),
    () => client.auth.signOut(scope: SignOutScope.others),
  );
});

final signedInDevicesProvider =
    FutureProvider.autoDispose<List<SignedInDevice>>(
      (ref) => ref.watch(accountSessionsRepositoryProvider).list(),
    );
