import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/data/models/dating_profile_photo.dart';
import 'package:attune/features/dating/domain/services/dating_image_preparer.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingPhotosScreen extends ConsumerStatefulWidget {
  const DatingPhotosScreen({super.key});

  @override
  ConsumerState<DatingPhotosScreen> createState() => _DatingPhotosScreenState();
}

class _DatingPhotosScreenState extends ConsumerState<DatingPhotosScreen> {
  final _imagePicker = ImagePickerService();
  final Set<int> _uploadingPositions = {};

  Future<void> _addPhoto(int position) async {
    final picked = await _imagePicker.pickImage(
      fromCamera: false,
      crop: true,
      lockAspectRatio: true,
    );
    if (picked == null || !mounted) return;

    setState(() => _uploadingPositions.add(position));
    try {
      await ref.read(
        uploadDatingPhotoProvider((
          localPath: picked.path,
          position: position,
        )).future,
      );
    } on DatingImageRejected catch (rejected) {
      if (!mounted) return;
      context.showErrorSnackbar(_rejectionMessage(rejected.code));
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not upload that photo. Please try again.');
    } finally {
      if (mounted) setState(() => _uploadingPositions.remove(position));
    }
  }

  Future<void> _deletePhoto(String photoId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this photo?'),
        content: const Text('This can\'t be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(deleteDatingPhotoProvider(photoId).future);
  }

  String _rejectionMessage(String code) {
    switch (code) {
      case 'media_type_unsupported':
        return 'That file type isn\'t supported. Choose a JPG, PNG, or WebP image.';
      case 'media_too_large':
      case 'media_compress_failed':
        return 'That image is too large. Try a smaller one.';
      case 'media_decode_failed':
      case 'media_dimensions_excessive':
        return 'That image couldn\'t be read. Try a different one.';
      default:
        return 'That image couldn\'t be uploaded.';
    }
  }

  String _photoStatusMessage(DatingProfilePhoto photo) {
    if (photo.isPending) return 'Reviewing your photo...';
    if (photo.needsReview) return 'This photo needs a closer look — we\'ll follow up.';
    if (photo.isRejected) {
      switch (photo.rejectionReason) {
        case 'face_blurred':
          return 'This photo looks blurry. Try a clearer shot.';
        case 'face_underexposed':
          return 'This photo is too dark. Try better lighting.';
        case 'face_too_small':
          return 'Your face is too small in this photo. Try getting closer.';
        case 'image_too_small':
          return 'This image is too low-resolution. Try a larger photo.';
        case 'adult_content_detected':
        case 'violent_content_detected':
        case 'racy_content_detected':
          return 'This photo doesn\'t meet our content guidelines.';
        default:
          return 'This photo couldn\'t be approved.';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final photosAsync = ref.watch(datingPhotosProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Your photos',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: photosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: ErrorStateWidget(
            title: 'Something went wrong',
            subtitle: 'We couldn\'t load your photos right now. Please try again in a moment.',
          ),
        ),
        data: (photos) {
          final byPosition = {for (final p in photos) p.position: p};
          return Padding(
            padding: EdgeInsets.all(Spacing.md.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Add 1 to 4 photos. Clear, recent photos of just you work best.',
                  style: textTheme.bodyMedium,
                ),
                Gap(Spacing.lg.h),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: Spacing.md.w,
                  mainAxisSpacing: Spacing.md.h,
                  children: List.generate(4, (index) {
                    final position = index + 1;
                    final photo = byPosition[position];
                    final isUploading = _uploadingPositions.contains(position);

                    if (isUploading) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (photo == null) {
                      return InkWell(
                        onTap: () => _addPhoto(position),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                          ),
                          child: const Center(child: Icon(Icons.add_a_photo_outlined)),
                        ),
                      );
                    }
                    return GestureDetector(
                      onTap: () => _deletePhoto(photo.id),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(BorderRadiusTokens.md.r),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              photo.isApproved ? Icons.check_circle_outline : Icons.hourglass_empty,
                            ),
                            if (!photo.isApproved) ...[
                              Gap(Spacing.xs.h),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: Spacing.sm.w),
                                child: Text(
                                  _photoStatusMessage(photo),
                                  style: textTheme.labelSmall,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
