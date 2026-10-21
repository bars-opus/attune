// lib/core/notifications/data/push_subscription_registry.dart
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tells the server which OneSignal device subscription belongs to the
/// signed-in person (chat review #18): the server pushes only to these,
/// never to the external_id alias. Both calls run as auth.uid() server-side
/// (register_push_subscription / unregister_push_subscription).
abstract class PushSubscriptionRegistry {
  Future<void> register({
    required String subscriptionId,
    required String platform,
  });
  Future<void> unregister(String subscriptionId);

  /// Plan 1b final review I1: deactivates this device's subscription
  /// whoever it belongs to, with or without a session (an owed release
  /// after an offline sign-out). release_push_subscription answers nothing.
  Future<void> release(String subscriptionId);
}

class SupabasePushSubscriptionRegistry implements PushSubscriptionRegistry {
  SupabasePushSubscriptionRegistry(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register({
    required String subscriptionId,
    required String platform,
  }) => _client.rpc(
    'register_push_subscription',
    params: {'p_subscription_id': subscriptionId, 'p_platform': platform},
  );

  @override
  Future<void> unregister(String subscriptionId) => _client.rpc(
    'unregister_push_subscription',
    params: {'p_subscription_id': subscriptionId},
  );

  @override
  Future<void> release(String subscriptionId) => _client.rpc(
    'release_push_subscription',
    params: {'p_subscription_id': subscriptionId},
  );
}

final pushSubscriptionRegistryProvider = Provider<PushSubscriptionRegistry>(
  (ref) => SupabasePushSubscriptionRegistry(ref.watch(supabaseClientProvider)),
);

/// register_push_subscription refused because this phone's session was
/// revoked (signed out from another device) or has run out: the phone is
/// on its way to signed out, so retrying is pointless.
bool isPushSessionRevoked(Object error) =>
    error is PostgrestException &&
    error.message.contains('push_subscription:session_revoked');

/// The server refused the subscription id as malformed: resending it can
/// never succeed, so an owed release holding it is dropped.
bool isPushSubscriptionInvalid(Object error) =>
    error is PostgrestException &&
    error.message.contains('push_subscription:invalid');
