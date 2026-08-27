// lib/features/settings/data/account_deletion_service.dart
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when account deletion fails, mirroring
/// RelationshipLifecycleException's shape
/// (relationship_lifecycle_service.dart) so error handling stays
/// consistent across this codebase's destructive actions.
class AccountDeletionException implements Exception {
  const AccountDeletionException(this.message);
  final String message;

  @override
  String toString() => 'AccountDeletionException: $message';
}

/// Client half of the GDPR account-deletion endpoint required by
/// ATTUNE_MASTER_SPEC.md §10 ("User can delete account and all data at any
/// time").
///
/// All the erasure logic lives server-side in the `delete-account` edge
/// function — this only carries the caller's JWT to it. The client is
/// deliberately given no ability to specify WHICH account to delete: the
/// function derives that from the verified token alone.
class AccountDeletionService {
  AccountDeletionService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  /// Longer than the 30s used elsewhere: this request cascades a delete
  /// across ~40 tables plus auth, and a client-side timeout would NOT
  /// cancel that server-side work — it would only leave the user staring
  /// at an error for an account that is, in fact, being deleted.
  static const _timeout = Duration(seconds: 60);

  SupabaseClient get _safeClient => _client ?? Supabase.instance.client;

  /// Permanently deletes the signed-in user's account.
  ///
  /// On success the auth user no longer exists, so the caller must sign out
  /// locally — any retained session is now pointing at a deleted identity.
  Future<void> deleteAccount() async {
    try {
      final response = await _safeClient.functions
          .invoke(
            'delete-account',
            // `confirm` is required by the function: it makes an accidental
            // or replayed invocation a 400 rather than an erasure.
            body: {'confirm': true},
            method: HttpMethod.delete,
          )
          .timeout(_timeout);

      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw AccountDeletionException(data['error'].toString());
      }
    } catch (error) {
      // Logs the type only — never the message, which could carry the
      // address or id of the account being deleted (§10 / checklist 4.4).
      debugPrint('[account-deletion] failed: ${error.runtimeType}');
      if (error is AccountDeletionException) rethrow;
      throw const AccountDeletionException(
        'Could not delete your account. Please try again.',
      );
    }
  }
}
