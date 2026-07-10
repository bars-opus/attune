import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/models/profile_role.dart';
import 'package:attune/features/profile/repositories/profile_repository_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client;

  SupabaseProfileRepository(this._client);

  @override
  Future<Profile> getProfile(String userId) async {
    final response =
        await _client.from('profiles').select().eq('id', userId).single();

    return Profile.fromJson(response);
  }

  /// Fetch profile by user id — userId MUST be passed in
  @override
  Future<Profile?> fetchProfile(String userId) async {
    final response =
        await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (response == null) return null;
    return Profile.fromJson(response);
  }

  /// Create empty profile for a new user.
  ///
  /// Idempotent: uses UPSERT with `ignoreDuplicates` so two concurrent
  /// callers (e.g. `_handleNewUser` racing with `UsernameCreationScreen`)
  /// both succeed without a unique-violation. Safe to call repeatedly.
  @override
  Future<void> createProfile(String userId) async {
    await _client.from('profiles').upsert(
      {
        'id': userId,
        'username': null,
        'bio': null,
        'avatar_url': null,
      },
      ignoreDuplicates: true,
    );
  }

  /// Update username.
  ///
  /// `isUsernameAvailable` + `updateUsername` is a TOCTOU race — another user
  /// can claim the same username in the window between the two calls. The DB
  /// must have a UNIQUE constraint on `profiles.username` (case-insensitive),
  /// and we translate the resulting 23505 (unique_violation) into a clear
  /// "username just got taken" error here.
  @override
  Future<Profile> updateUsername(String userId, String username) async {
    try {
      final response = await _client
          .from('profiles')
          .update({
            'username': username.toLowerCase(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId)
          .select()
          .single();
      return Profile.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw Exception('That username was just taken. Please choose another.');
      }
      rethrow;
    }
  }

  /// Check username availability (no userId needed)
  @override
  Future<bool> isUsernameAvailable(String username) async {
    try {
      final normalized = username.trim().toLowerCase();
      final response =
          await _client
              .from('profiles')
              .select('username')
              .ilike('username', normalized)
              .maybeSingle();
      final isAvailable = response == null;
      return isAvailable;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<Profile> updateAvatar(String userId, String avatarUrl) async {
    final response =
        await _client
            .from('profiles')
            .update({
              'avatar_url': avatarUrl,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId)
            .select()
            .single();

    return Profile.fromJson(response);
  }

  @override
  Future<Profile> updateBio(String userId, String bio) async {
    final response =
        await _client
            .from('profiles')
            .update({
              'bio': bio,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId)
            .select()
            .single();

    return Profile.fromJson(response);
  }

  /// Optional: Combined update for multiple fields

  @override
  Future<Profile> updateProfile({
    required String userId,
    String? displayName,
    String? username,
    String? bio,
  }) async {
    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (displayName != null) updates['display_name'] = displayName;
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;

    final response =
        await _client
            .from('profiles')
            .update(updates)
            .eq('id', userId)
            .select()
            .single();

    return Profile.fromJson(response);
  }

  @override
  Future<Profile> updateDisplayName(String userId, String displayName) async {
    final response =
        await _client
            .from('profiles')
            .update({
              'display_name': displayName,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', userId)
            .select()
            .single();

    return Profile.fromJson(response);
  }

  /// Fetch all roles for a user
  Future<List<UserRole>> fetchUserRoles(String userId) async {
    final response = await _client
        .from('user_roles')
        .select()
        .eq('user_id', userId)
        .order('created_at');

    return response.map((json) => UserRole.fromJson(json)).toList();
  }

  /// Fetch active roles only
  Future<List<UserRole>> fetchActiveUserRoles(String userId) async {
    final response = await _client
        .from('user_roles')
        .select()
        .eq('user_id', userId)
        .eq('is_active', true)
        .order('created_at');

    return response.map((json) => UserRole.fromJson(json)).toList();
  }

  /// Check if user has a specific role
  Future<bool> hasRole(String userId, AccountType role) async {
    final response = await _client
        .from('user_roles')
        .select('id')
        .eq('user_id', userId)
        .eq('role', role.value)
        .eq('is_active', true)
        .maybeSingle();

    return response != null;
  }

  /// Add a role to a user
  Future<void> addRole(String userId, AccountType role,
      {Map<String, dynamic>? metadata}) async {
    await _client.from('user_roles').insert({
      'user_id': userId,
      'role': role.value,
      'metadata': metadata ?? {},
    });
  }

  /// Remove a role from a user
  Future<void> removeRole(String userId, AccountType role) async {
    await _client
        .from('user_roles')
        .delete()
        .eq('user_id', userId)
        .eq('role', role.value);
  }

  /// Update role metadata (e.g., shop_id for shop workers)
  Future<void> updateRoleMetadata(
      String userId, AccountType role, Map<String, dynamic> metadata) async {
    await _client
        .from('user_roles')
        .update({'metadata': metadata, 'updated_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId)
        .eq('role', role.value);
  }
}
