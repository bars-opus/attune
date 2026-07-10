// lib/core/providers/service_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/services/media/media_upload_service.dart';
import 'package:attune/core/providers/repository_providers.dart';

final imagePickerServiceProvider = Provider<ImagePickerService>((ref) {
  return ImagePickerService();
});

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  final storageRepo = ref.read(storageRepositoryProvider);
  final imagePickerService = ref.read(imagePickerServiceProvider);
  
  return MediaUploadService(
    storageRepo: storageRepo,
    imagePickerService: imagePickerService,
  );
});
