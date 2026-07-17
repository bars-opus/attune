import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/repositories/supabase_profile_repository.dart';
import 'package:attune/features/profile/repositories/profile_repository_interface.dart';
import 'package:attune/features/profile/services/username_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'profile_provider.g.dart';

// Repository provider (rename to avoid conflict)
@riverpod
ProfileRepository profileRepository(ProfileRepositoryRef ref) {
  final supabaseClient = ref.watch(supabaseClientProvider);
  return SupabaseProfileRepository(supabaseClient);
}

// Current user profile provider
@riverpod
Future<Profile?> currentUserProfile(CurrentUserProfileRef ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Future.value(null);
  final repo = ref.watch(profileRepositoryProvider);
  return repo.fetchProfile(user.id);
}

// Add this to your profile_provider.dart
@riverpod
Future<Profile?> profile(ProfileRef ref, {required String userId}) {
  final repo = ref.watch(profileRepositoryProvider);
  return repo.fetchProfile(userId);
}

// Username service provider
final usernameServiceProvider = Provider<UsernameService>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return UsernameService(repository: repository);
});

/// Provider that gives just the current user's display name
@riverpod
Future<String> currentUserDisplayName(CurrentUserDisplayNameRef ref) async {
  final profile = await ref.watch(currentUserProfileProvider.future);
  return profile?.displayName ?? profile?.username ?? 'Client';
}

