// lib/domain/repositories/profile_repository_interface.dart


import 'package:attune/features/profile/models/profile.dart';

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
