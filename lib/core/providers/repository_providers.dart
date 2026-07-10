// lib/core/providers/repository_providers.dart (or similar)
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/repositories/storage_repository_interface.dart';
import 'package:attune/core/repositories/supabase/supabase_storage_repository.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

final storageRepositoryProvider = Provider<StorageRepository>((ref) {
  final supabaseClient = ref.watch(supabaseClientProvider);
  return SupabaseStorageRepository(supabaseClient);
});
