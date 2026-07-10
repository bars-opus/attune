// lib/presentation/widgets/profile/editable_profile_avatar.dart
import 'dart:io';
import 'dart:ui';

import 'package:attune/core/providers/profile_image_provider.dart';
import 'package:attune/core/widgets/buttons/app_icon_button.dart';
import 'package:attune/core/widgets/profile_avatar_placeholder.dart';
import 'package:attune/features/auth/utility/auth_exports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EditableProfileAvatar extends ConsumerWidget {
  final String? currentAvatarUrl;
  final String currentUserId;
  final double size;
  final VoidCallback? onErrorDismiss;

  /// When provided, the widget only picks the image (no upload).
  /// The picked [File] is passed to this callback so the caller handles saving.
  final void Function(File)? onImagePicked;

  const EditableProfileAvatar({
    super.key,
    required this.currentAvatarUrl,
    this.currentUserId = '',
    this.size = 100,
    this.onErrorDismiss,
    this.onImagePicked,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageState = ref.watch(profileImageProvider);
    final colorScheme = Theme.of(context).colorScheme;

    // Determine image provider
    ImageProvider? imageProvider;

    if (imageState.selectedImage != null) {
      imageProvider = FileImage(imageState.selectedImage!);
    } else if (currentAvatarUrl != null && currentAvatarUrl!.isNotEmpty) {
      // localLogoPath can be either a Supabase HTTP URL (existing logo) or a
      // local file path (just picked, not yet uploaded). Use the right provider.
      imageProvider = currentAvatarUrl!.startsWith('http')
          ? NetworkImage(currentAvatarUrl!)
          : FileImage(File(currentAvatarUrl!));
    }

    return Center(
      child: Stack(
        alignment: FractionalOffset.center,
        children: [
          _maybeHero(
            child: GestureDetector(
              onTap: () {
                BottomSheetUtils.showDocumentationBottomSheet(
                  context: context,
                  maxHeight: 200.h,
                  widget: _showImageSourceDialog(context, ref),
                );
              },
              child: CircleAvatar(
                radius: size / 2,
                backgroundImage: imageProvider,
                backgroundColor: colorScheme.surface,
                child:
                    imageProvider == null
                        ? ProfileAvatarPlaceholder(isEdtting: true, size: size)
                        : null,
              ),
            ),
          ),

          // Loading overlay
          if (imageState.isUploading)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.3),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),

        

          // Error display
          if (imageState.error != null)
            Positioned(
              bottom: -10,
              right: -10,
              child: AppIconButton(
                icon: Icons.error,
                iconColor: Colors.red,
                onPressed: () {
                  ref.read(profileImageProvider.notifier).clearError();
                  onErrorDismiss?.call();
                  context.showErrorSnackbar(imageState.error ?? '');
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _maybeHero({required Widget child}) {
    if (currentUserId.isEmpty) return child;
    return Hero(tag: currentUserId, child: child);
  }

  Future<void> _handlePick(
    BuildContext context,
    WidgetRef ref,
    bool fromCamera,
  ) async {
    Navigator.pop(context);
    // iOS silently drops PHPickerViewController / ImageCropper presentation while
    // the bottom sheet is still animating. Wait for the animation to finish.
    await Future.delayed(const Duration(milliseconds: 350));
    if (onImagePicked != null) {
      final file = await ref
          .read(profileImageProvider.notifier)
          .pickImageOnly(fromCamera: fromCamera);
      if (file != null) onImagePicked!(file);
    } else {
      ref
          .read(profileImageProvider.notifier)
          .pickAndUploadImage(fromCamera: fromCamera);
    }
  }

  Widget _showImageSourceDialog(BuildContext context, WidgetRef ref) {
    final loc = AppLocalizations.of(context)!;
    return SafeArea(
      child: Wrap(
        children: [
          InfoRowWidget(
            subtitle: '',
            title: loc.editableProfileAvatarTakePhoto,
            icon: Icons.camera_alt,
            avatarRadius: 30.h,
            onTap: () => _handlePick(context, ref, true),
            disableTrailing: true,
            showAvatar: false,
            showTrailingArrow: false,
          ),
          InfoRowWidget(
            subtitle: '',
            title: loc.editableProfileAvatarChooseGallery,
            icon: Icons.photo_library,
            avatarRadius: 30.h,
            onTap: () => _handlePick(context, ref, false),
            disableTrailing: true,
            showAvatar: false,
            showTrailingArrow: false,
          ),
        ],
      ),
    );
  }
}
