// lib/domain/repositories/profile_repository_interface.dart


import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/models/profile_role.dart';

/// This Dart class is an abstract ProfileRepository.
abstract class ProfileRepository {
  // Read operations
  Future<Profile?> fetchProfile(String userId);
  Future<Profile> getProfile(String userId);

  // Write operations
  Future<Profile> updateDisplayName(String userId, String displayName);
  Future<Profile> updateUsername(String userId, String username);
  Future<Profile> updateBio(String userId, String bio);
  Future<Profile> updateAvatar(String userId, String publicUrl);
  Future<void> createProfile(String userId);

    // ✅ Add role methods to interface
  Future<List<UserRole>> fetchUserRoles(String userId);
  Future<List<UserRole>> fetchActiveUserRoles(String userId);
  Future<bool> hasRole(String userId, AccountType role);
  Future<void> addRole(String userId, AccountType role, {Map<String, dynamic>? metadata});
  Future<void> removeRole(String userId, AccountType role);
  Future<void> updateRoleMetadata(String userId, AccountType role, Map<String, dynamic> metadata);

  // Utility
  Future<bool> isUsernameAvailable(String username); // ✅ Add this

  // Optional: Combined update
  Future<Profile> updateProfile({
    required String userId,
    String? displayName,
    String? username,
    String? bio,
  });
}
