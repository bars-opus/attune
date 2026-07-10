// Web stub: mirrors the image_cropper API surface used in this project.
// All crop operations are no-ops; callers guard with kIsWeb before calling.

class CropAspectRatio {
  final double ratioX;
  final double ratioY;
  const CropAspectRatio({required this.ratioX, required this.ratioY});
}

class CroppedFile {
  final String path;
  CroppedFile(this.path);
}

enum CropAspectRatioPreset { square, ratio3x2, ratio4x3, ratio5x3, ratio5x4, ratio7x5, ratio16x9 }

class AndroidUiSettings {
  const AndroidUiSettings({
    String? toolbarTitle,
    dynamic toolbarColor,
    dynamic toolbarWidgetColor,
    CropAspectRatioPreset? initAspectRatio,
    bool? lockAspectRatio,
  });
}

class IOSUiSettings {
  const IOSUiSettings({String? title, bool? aspectRatioLockEnabled});
}

class ImageCropper {
  Future<CroppedFile?> cropImage({
    required String sourcePath,
    CropAspectRatio? aspectRatio,
    List<dynamic> uiSettings = const [],
  }) async =>
      null;
}
