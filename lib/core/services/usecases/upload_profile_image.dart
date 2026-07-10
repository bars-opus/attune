// lib/domain/usecases/upload_profile_image.dart

import 'dart:io';

import 'package:attune/features/profile/repositories/profile_repository_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:attune/core/utils/image_cropper_platform.dart';
import 'package:attune/core/repositories/models/media_upload.dart';
import 'package:attune/core/services/usecases/upload_media.dart';

class UploadProfileImage {
  final UploadMedia _uploadMedia;
  final ProfileRepository _profileRepository;

  UploadProfileImage({
    required UploadMedia uploadMedia,
    required ProfileRepository profileRepository,
  }) : _uploadMedia = uploadMedia,
       _profileRepository = profileRepository;

  Future<UploadResult?> execute({
    required String userId,
    required bool fromCamera,
    File? existingFile,
  }) async {
    try {
      // On web, cropping is not supported, so disable it
      final shouldCrop = !kIsWeb; // No cropping on web

      // Only pass cropRatio if we're actually cropping (mobile only)
      final cropRatio =
          shouldCrop ? const CropAspectRatio(ratioX: 1, ratioY: 1) : null;

      final result = await _uploadMedia.execute(
        bucket: 'avatars',
        userId: userId,
        mediaType: MediaType.image,
        customPath: '$userId/avatar.jpg',
        upsert: true,
        metadata: {'type': 'profile_avatar'},
        shouldPick: existingFile == null,
        existingFile: existingFile,
        fromCamera: fromCamera,
        shouldCrop: shouldCrop,
        cropRatio: cropRatio,
      );

      if (result == null) {
        debugPrint('UploadProfileImage: Upload failed');
        return null;
      }

      // Update profile with new avatar URL (cache-bust already applied by MediaUploadService)
      await _profileRepository.updateAvatar(userId, result.publicUrl);

      debugPrint('UploadProfileImage: Success for user $userId');
      return result;
    } catch (e) {
      debugPrint('UploadProfileImage error: $e');
      return null;
    }
  }
}
