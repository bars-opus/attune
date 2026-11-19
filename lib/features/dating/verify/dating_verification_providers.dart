// Spec 2 W4a (D8, C-5): the verification state, one entry per account,
// memory only; the camera is a seam (tests replace it) whose file the flow
// deletes as soon as it is read.
import 'package:attune/features/dating/data/dating_providers.dart';
import 'package:attune/features/dating/data/dating_supabase_client.dart';
import 'package:attune/features/dating/verify/dating_verification.dart';
import 'package:attune/features/dating/verify/dating_verification_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart'
    show Permission, PermissionCheckShortcuts, openAppSettings;

final datingVerificationGatewayProvider = Provider<DatingVerificationGateway>(
  (ref) => DatingVerificationRepository.of(
    ref.watch(datingRpcProvider),
    ref.watch(datingSupabaseClientProvider),
  ),
);

/// The person's own verification state; the next account's entry starts
/// as a plain loading value, never holding the last one's (D8).
final datingVerificationProvider = FutureProvider.autoDispose
    .family<DatingVerification, String?>((ref, account) async {
      if (account == null) return DatingVerification.unavailable;
      return ref.read(datingVerificationGatewayProvider).status();
    });

/// The human route's camera (§3.3.3: camera only, never the gallery), the
/// front camera, no metadata; its file is deleted by the flow once read.
final datingReviewCameraProvider = Provider<Future<String?> Function()>(
  (ref) =>
      () async =>
          (await ImagePicker().pickImage(
            source: ImageSource.camera,
            preferredCameraDevice: CameraDevice.front,
            requestFullMetadata: false,
          ))?.path,
);

/// Final fix (M-4): the camera's permission, read once the human route's
/// camera was refused (a seam: tests replace it).
class DatingCameraAccess {
  const DatingCameraAccess();

  /// Whether only the phone's Settings can allow the camera now (refused
  /// for good, or on iOS refused once). Unreadable: false.
  Future<bool> blocked() async {
    try {
      return await Permission.camera.isPermanentlyDenied;
    } catch (_) {
      return false;
    }
  }

  /// Opens this app's page in the phone's Settings.
  Future<void> openSettings() async {
    try {
      await openAppSettings();
    } catch (_) {
      // Nothing to do: the line still says where to allow it.
    }
  }
}

final datingCameraAccessProvider = Provider<DatingCameraAccess>(
  (ref) => const DatingCameraAccess(),
);

/// Fix round 1 (I-2): reads the person's verification state again, for
/// this account only, after an answer that may not tell the whole story
/// (`DatingVerifyAnswer.readStatusAgain`: busy, failed, a closed session).
extension DatingVerificationReread on WidgetRef {
  Future<DatingVerification> rereadDatingVerification(String? account) =>
      refresh(datingVerificationProvider(account).future);
}
