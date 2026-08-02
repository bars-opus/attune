import 'package:attune/core/services/media/image_picker_service.dart';
import 'package:attune/core/utils/exports/export_screens.dart';
import 'package:attune/features/dating/presentation/providers/dating_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DatingVerificationScreen extends ConsumerStatefulWidget {
  const DatingVerificationScreen({super.key});

  @override
  ConsumerState<DatingVerificationScreen> createState() =>
      _DatingVerificationScreenState();
}

class _DatingVerificationScreenState extends ConsumerState<DatingVerificationScreen> {
  final _imagePicker = ImagePickerService();
  bool _isSubmitting = false;

  Future<void> _captureAndSubmit() async {
    // Camera only — no gallery import, per spec §4.
    final picked = await _imagePicker.pickImage(
      fromCamera: true,
      crop: true,
      lockAspectRatio: true,
    );
    if (picked == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      final state = await ref.read(
        submitVerificationSelfieProvider((localPath: picked.path)).future,
      );
      if (!mounted) return;
      if (state == 'pending') {
        // The Rekognition call itself failed (not a low-confidence match) —
        // spec §4 step 6 requires a retry offer here, not a false success.
        context.showErrorSnackbar(
          'We couldn\'t complete verification just now. Please try again.',
        );
        return;
      }
      // Both 'verified' and 'needs_review' are genuine completed outcomes
      // from the caller's point of view — neither is shown as a badge
      // anywhere (spec §6), so the copy stays identical either way.
      context.showSuccessSnackbar('Verification submitted.');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnackbar('Could not submit your photo just now. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          'Confirm your photos',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(Spacing.md.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We compare your verification selfie to your profile photos to confirm '
              'they\'re consistent. The comparison happens once, the result is a '
              'simple pass/fail, and it\'s never used to affect who you\'re matched with.',
              style: textTheme.bodyMedium,
            ),
            const Spacer(),
            AppButton(
              label: _isSubmitting ? 'Submitting...' : 'Take a photo to confirm',
              onPressed: _isSubmitting ? null : _captureAndSubmit,
              size: ButtonSize.large,
              width: double.infinity,
            ),
          ],
        ),
      ),
    );
  }
}
