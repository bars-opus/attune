import 'dart:io' show Platform;

import 'package:attune/core/notifications/services/onesignal_service.dart';
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
  AccountSessionsRepository(
    this._rpc,
    this._signOutOthers, {
    String? Function()? pushSubscriptionToKeep,
    void Function()? refreshPushRegistration,
  }) : _pushSubscriptionToKeep = pushSubscriptionToKeep,
       _refreshPushRegistration = refreshPushRegistration;

  final SessionsRpc _rpc;
  final Future<void> Function() _signOutOthers;

  /// This phone's push subscription id (null: it has none).
  final String? Function()? _pushSubscriptionToKeep;

  /// Re-sends this phone's own registration once the stop has run: with no
  /// id known when it asked (OneSignal still starting), the server stopped
  /// this phone too (fix round 2 #3).
  final void Function()? _refreshPushRegistration;

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

  /// Revokes every other session's refresh token (ruling R2-10), then stops
  /// their pushes at once (chat review #18, fix I2): a revoked phone only
  /// notices at its next token refresh, up to an hour later. Best-effort
  /// and bounded: a failure there never fails the revoke.
  Future<void> signOutOtherDevices() async {
    await _signOutOthers();
    try {
      await _rpc('deactivate_other_push_subscriptions', {
        'p_keep_subscription_id': _pushSubscriptionToKeep?.call(),
      }).timeout(const Duration(seconds: 3));
    } catch (_) {
      // Nothing logged here (Spec 2: no device log in account code). The
      // revoked phones still opt out when their session ends.
    }
    // Even after a failure or timeout: the stop may still have run.
    try {
      _refreshPushRegistration?.call();
    } catch (_) {}
  }
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
    pushSubscriptionToKeep: () =>
        ref.read(oneSignalServiceProvider).currentSubscriptionId,
    refreshPushRegistration: () =>
        ref.read(oneSignalServiceProvider).refreshRegistration(),
  );
});

final signedInDevicesProvider =
    FutureProvider.autoDispose<List<SignedInDevice>>(
      (ref) => ref.watch(accountSessionsRepositoryProvider).list(),
    );
