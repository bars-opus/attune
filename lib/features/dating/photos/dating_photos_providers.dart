// Spec 2 W3c (D8, C-5): the photos, one entry per account, memory only; the
// picker and the cropper are seams (tests replace them) that never copy a
// picked photo to a permanent directory (R-23).
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/photos/dating_photos_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

final datingPhotosGatewayProvider = Provider<DatingPhotosGateway>(
  (ref) => DatingPhotosRepository(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider).storage,
  ),
);

final datingPhotosProvider = FutureProvider.autoDispose
    .family<DatingPhotoList, String?>((ref, account) async {
      if (account == null) return const DatingPhotoList();
      return ref.read(datingPhotosGatewayProvider).list();
    });

final datingImagePreparerProvider = Provider<DatingImagePreparer>(
  (ref) => const DatingImagePreparer(),
);

/// The system picker (gallery); its file is a temporary copy the step deletes.
/// No full metadata (T10 fix 1, I-3): on iOS that would ask for access to the
/// whole library, and EXIF is stripped before upload anyway.
final datingPhotoPickerProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async =>
          (await ImagePicker().pickImage(
            source: ImageSource.gallery,
            requestFullMetadata: false,
          ))?.path,
);

/// Crop to just you (§3.2 D9), into the cache directory; deleted after.
final datingPhotoCropperProvider =
    Provider<Future<String?> Function(String path)>(
      (ref) =>
          (path) async =>
              (await ImageCropper().cropImage(sourcePath: path))?.path,
    );
