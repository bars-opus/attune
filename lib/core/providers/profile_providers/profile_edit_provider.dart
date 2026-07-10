// lib/presentation/providers/profile_edit_provider.dart
import 'dart:async';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/features/profile/models/profile.dart';
import 'package:attune/features/profile/models/profile_edit_state.dart';
import 'package:attune/features/profile/repositories/profile_repository_interface.dart';
import 'package:attune/features/profile/services/username_service.dart';
import 'package:riverpod/riverpod.dart';

// State class

class ProfileEditNotifier extends StateNotifier<ProfileEditState> {
  final ProfileRepository _repository;
  final UsernameService _usernameService;
  final Ref _ref;
  final String _userId;

  Timer? _displayNameTimer;
  Timer? _usernameTimer;
  Timer? _bioTimer;

  ProfileEditNotifier({
    required ProfileRepository repository,
    required UsernameService usernameService,
    required Ref ref,
    required String userId,
    required ProfileEditState initialState,
  }) : _repository = repository,
       _usernameService = usernameService,
       _ref = ref,
       _userId = userId,
       super(initialState);

  // Initialize from profile
  static ProfileEditNotifier create({
    required Ref ref,
    required String userId,
    required Profile? initialProfile,
  }) {
    final repository = ref.read(profileRepositoryProvider);
    final usernameService = ref.read(usernameServiceProvider);
    return ProfileEditNotifier(
      repository: repository,
      usernameService: usernameService,
      ref: ref,
      userId: userId,
      initialState: ProfileEditState(
        displayName: initialProfile?.displayName ?? '',
        username: initialProfile?.username ?? '',
        bio: initialProfile?.bio ?? '',
      ),
    );
  }

  // Field setters with debounce
  void setDisplayName(String value) {
    // Update local state immediately (optimistic UI)
    state = state.copyWith(displayName: value, displayNameError: null);

    // Debounce save
    _displayNameTimer?.cancel();
    _displayNameTimer = Timer(const Duration(milliseconds: 800), () {
      _saveDisplayName(value);
    });
  }

  void setUsername(String value) {
    // Validate locally first using UsernameService
    final validation = _usernameService.validateUsername(value);
    if (!validation.isValid) {
      state = state.copyWith(
        username: value,
        usernameError: validation.errorMessage,
      );
      return;
    }

    // Update local state
    state = state.copyWith(username: value, usernameError: null);

    // Debounce save
    _usernameTimer?.cancel();
    _usernameTimer = Timer(const Duration(milliseconds: 800), () {
      _saveUsername(value);
    });
  }

  void setBio(String value) {
    state = state.copyWith(bio: value, bioError: null);

    _bioTimer?.cancel();
    _bioTimer = Timer(const Duration(milliseconds: 800), () {
      _saveBio(value);
    });
  }

  // Save methods
  Future<void> _saveDisplayName(String value) async {
    // Don't save if unchanged

    state = state.copyWith(isSavingDisplayName: true);

    try {
      await _repository.updateDisplayName(_userId, value);

      // Success - update state with saved value and clear saving flag
      state = state.copyWith(
        displayName: value,
        isSavingDisplayName: false,
        displayNameError: null,
      );

      // Invalidate global profile provider to refresh other screens
      _ref.invalidate(currentUserProfileProvider);
    } catch (e) {
      state = state.copyWith(
        isSavingDisplayName: false,
        displayNameError: 'Failed to save: $e',
      );
    }
  }

  Future<void> _saveUsername(String value) async {
    // Additional availability check before saving
    final isAvailable = await _usernameService.isUsernameAvailable(value);
    if (!isAvailable) {
      state = state.copyWith(
        isSavingUsername: false,
        usernameError: 'Username already taken',
      );
      return;
    }

    state = state.copyWith(isSavingUsername: true);

    try {
      await _repository.updateUsername(_userId, value);

      state = state.copyWith(
        username: value,
        isSavingUsername: false,
        usernameError: null,
      );

      _ref.invalidate(currentUserProfileProvider);
    } catch (e) {
      state = state.copyWith(
        isSavingUsername: false,
        usernameError: 'Failed to save: $e',
      );
    }
  }

  Future<void> _saveBio(String value) async {
    state = state.copyWith(isSavingBio: true);

    try {
      await _repository.updateBio(_userId, value);

      state = state.copyWith(bio: value, isSavingBio: false, bioError: null);

      _ref.invalidate(currentUserProfileProvider);
    } catch (e) {
      state = state.copyWith(
        isSavingBio: false,
        bioError: 'Failed to save: $e',
      );
    }
  }

  // Manual save all (optional - if you want a save button alternative)
  Future<void> saveAll() async {
    // Cancel any pending timers
    _displayNameTimer?.cancel();
    _usernameTimer?.cancel();
    _bioTimer?.cancel();

    // Save all fields that have changes
    if (state.displayName.isNotEmpty) {
      await _saveDisplayName(state.displayName);
    }
    if (state.username.isNotEmpty && state.usernameError == null) {
      await _saveUsername(state.username);
    }
    if (state.bio.isNotEmpty) {
      await _saveBio(state.bio);
    }
  }

  // Reset to original values
  void resetToOriginal(Profile originalProfile) {
    state = state.copyWith(
      displayName: originalProfile.displayName ?? '',
      username: originalProfile.username ?? '',
      bio: originalProfile.bio ?? '',
      displayNameError: null,
      usernameError: null,
      bioError: null,
    );
  }

  @override
  void dispose() {
    _displayNameTimer?.cancel();
    _usernameTimer?.cancel();
    _bioTimer?.cancel();
    super.dispose();
  }
}

// Provider factory
final profileEditProvider =
    StateNotifierProvider.family<ProfileEditNotifier, ProfileEditState, String>(
      (ref, userId) {
        // Get current profile for initial values
        final profileAsync = ref.watch(currentUserProfileProvider);
        final profile = profileAsync.valueOrNull;
        return ProfileEditNotifier.create(
          ref: ref,
          userId: userId,
          initialProfile: profile,
        );
      },
    );
