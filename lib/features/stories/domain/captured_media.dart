/// What a camera capture produces, independent of where it is going.
///
/// [CaptureCameraScreen] (`lib/features/chat/presentation/screens/
/// capture_camera_screen.dart`) returns this from a completed capture.
/// It carries no destination — no conversation, no story id — so the
/// same result type works for the streak adapter today and the story
/// adapter later (spec §6).
library;

enum CapturedMediaType { image, video }

class CapturedMedia {
  const CapturedMedia({
    required this.path,
    required this.type,
    required this.width,
    required this.height,
    this.durationMs, // null for an image
  });

  final String path;
  final CapturedMediaType type;
  final int width;
  final int height;
  final int? durationMs;
}
