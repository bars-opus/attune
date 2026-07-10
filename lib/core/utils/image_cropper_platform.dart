// Resolves to the real package on native (dart:io available) and
// a no-op stub on web (dart:io absent).
export 'image_cropper_stub.dart' if (dart.library.io) 'image_cropper_impl.dart';
