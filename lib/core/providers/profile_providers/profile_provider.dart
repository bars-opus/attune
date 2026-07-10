import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/models/profile_role.dart';
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

/// Returns the user's highest-priority active role.
/// Priority: shop > worker > client.
/// Returns null when not logged in; never throws — errors fall back to client.
final currentUserPrimaryRoleProvider = FutureProvider<AccountType?>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return null;
  try {
    final repo = ref.watch(profileRepositoryProvider);
    final roles = await repo.fetchActiveUserRoles(userId);
    if (roles.isEmpty) return AccountType.client;
    const priority = [
      AccountType.shop,
      AccountType.worker,
      AccountType.client,
    ];
    for (final p in priority) {
      if (roles.any((r) => r.role == p)) return p;
    }
    return AccountType.client;
  } catch (_) {
    return AccountType.client;
  }
});

/// True if the current user is a freelancer worker (is_freelancer = true in workers table).
/// Returns false for shop owners, shop employees, clients, or if not in workers table.
final currentUserIsFreelancerProvider = FutureProvider<bool>((ref) async {
  final userId = ref.watch(currentUserProvider)?.id;
  if (userId == null) return false;
  try {
    final client = ref.watch(supabaseClientProvider);
    final response = await client
        .from('workers')
        .select('is_freelancer')
        .eq('user_id', userId)
        .eq('is_active', true)
        .maybeSingle();
    return response?['is_freelancer'] as bool? ?? false;
  } catch (_) {
    return false;
  }
});
