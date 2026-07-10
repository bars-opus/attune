// lib/presentation/providers/upload_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:attune/features/auth/providers/auth_provider.dart';
import 'package:attune/core/providers/media_%20service_providers.dart';
import 'package:attune/core/repositories/models/media_upload.dart';
import 'package:attune/core/services/media/media_upload_service.dart';

class UploadState {
  final bool isUploading;
  final double progress;
  final UploadResult? result;
  final String? error;

  UploadState({
    this.isUploading = false,
    this.progress = 0.0,
    this.result,
    this.error,
  });

  UploadState copyWith({
    bool? isUploading,
    double? progress,
    UploadResult? result,
    String? error,
  }) {
    return UploadState(
      isUploading: isUploading ?? this.isUploading,
      progress: progress ?? this.progress,
      result: result ?? this.result,
      error: error,
    );
  }
}

class UploadNotifier extends StateNotifier<UploadState> {
  final MediaUploadService _mediaUploadService;
  final Ref _ref;

  UploadNotifier({
    required MediaUploadService mediaUploadService,
    required Ref ref,
  })  : _mediaUploadService = mediaUploadService,
        _ref = ref,
        super(UploadState());

  Future<UploadResult?> upload({
    required MediaUploadRequest request,
    required bool fromCamera,
    bool shouldCrop = false,
    CropAspectRatio? cropRatio,
  }) async {
    // Get current user
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      state = state.copyWith(error: 'User not logged in');
      return null;
    }

    state = state.copyWith(isUploading: true, error: null);

    try {
      final result = await _mediaUploadService.pickAndUpload(
        request: request,
        fromCamera: fromCamera,
        userId: user.id, // ✅ Pass userId here
        shouldCrop: shouldCrop,
        cropRatio: cropRatio,
      );

      if (result != null) {
        state = state.copyWith(
          isUploading: false,
          result: result,
        );
      } else {
        state = state.copyWith(isUploading: false);
      }
      
      return result;
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        error: e.toString(),
      );
      return null;
    }
  }

  void reset() {
    state = UploadState();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Generic provider factory
final uploadProvider = StateNotifierProvider.family<UploadNotifier, UploadState, String>(
  (ref, uploadType) {
    final mediaUploadService = ref.watch(mediaUploadServiceProvider);
    return UploadNotifier(
      mediaUploadService: mediaUploadService,
      ref: ref,
    );
  },
);
