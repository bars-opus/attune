// lib/presentation/providers/profile_image_provider.dart

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/providers/media_%20service_providers.dart';
import 'package:attune/core/providers/profile_providers/profile_provider.dart';
import 'package:attune/core/services/usecases/upload_media.dart';
import 'package:attune/core/services/usecases/upload_profile_image.dart';

// ==================== STATE CLASS ====================
class ProfileImageState {
  final bool isUploading;
  final String? error;
  final File? selectedImage; // For preview
  final double uploadProgress;

  ProfileImageState({
    this.isUploading = false,
    this.error,
    this.selectedImage,
    this.uploadProgress = 0.0,
  });

  ProfileImageState copyWith({
    bool? isUploading,
    String? error,
    File? selectedImage,
    double? uploadProgress,
  }) {
    return ProfileImageState(
      isUploading: isUploading ?? this.isUploading,
      error: error ?? this.error,
      selectedImage: selectedImage ?? this.selectedImage,
      uploadProgress: uploadProgress ?? this.uploadProgress,
    );
  }
}

// ==================== NOTIFIER ====================
class ProfileImageNotifier extends StateNotifier<ProfileImageState> {
  final UploadProfileImage _uploadProfileImage;
  final Ref _ref;

  ProfileImageNotifier({
    required UploadProfileImage uploadProfileImage,
    required Ref ref,
  }) : _uploadProfileImage = uploadProfileImage,
       _ref = ref,
       super(ProfileImageState());

  Future<void> pickAndUploadImage({required bool fromCamera}) async {
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = state.copyWith(error: 'Not logged in');
      return;
    }

    // Pick image first
    final imageService = _ref.read(imagePickerServiceProvider);
    final pickedFile = await imageService.pickImage(
      fromCamera: fromCamera,
      crop: true,
      cropRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    );

    if (pickedFile == null) return; // User cancelled

    // Show preview
    state = state.copyWith(
      selectedImage: pickedFile,
      isUploading: true,
      error: null,
    );

    try {
      // Use profile-specific use case with pre-picked file
      // Note: fromCamera is already handled by imageService.pickImage
      final result = await _uploadProfileImage.execute(
        userId: user.id,
        fromCamera: fromCamera,
        existingFile: pickedFile,
      );

      if (result != null) {
        // Invalidate profile to refresh UI
        _ref.invalidate(currentUserProfileProvider);
        state = state.copyWith(isUploading: false, selectedImage: null);
      } else {
        state = state.copyWith(
          isUploading: false,
          error: 'Upload failed',
          selectedImage: null,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        error: e.toString(),
        selectedImage: null,
      );
    }
  }

  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<File?> pickImageOnly({required bool fromCamera}) async {
    final imageService = _ref.read(imagePickerServiceProvider);
    final pickedFile = await imageService.pickImage(
      fromCamera: fromCamera,
      crop: true,
      cropRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    );
    if (pickedFile == null) return null;
    state = state.copyWith(selectedImage: pickedFile, error: null);
    return pickedFile;
  }

  void clearSelectedImage() {
    state = state.copyWith(selectedImage: null);
  }
}

// ==================== PROVIDERS ====================

final uploadMediaProvider = Provider<UploadMedia>((ref) {
  final mediaUploadService = ref.watch(mediaUploadServiceProvider);
  return UploadMedia(mediaUploadService: mediaUploadService);
});

final uploadProfileImageProvider = Provider<UploadProfileImage>((ref) {
  final uploadMedia = ref.watch(uploadMediaProvider);
  final profileRepository = ref.watch(profileRepositoryProvider);
  return UploadProfileImage(
    uploadMedia: uploadMedia,
    profileRepository: profileRepository,
  );
});

final profileImageProvider =
    StateNotifierProvider<ProfileImageNotifier, ProfileImageState>((ref) {
      final uploadProfileImage = ref.watch(uploadProfileImageProvider);
      return ProfileImageNotifier(
        uploadProfileImage: uploadProfileImage,
        ref: ref,
      );
    });
