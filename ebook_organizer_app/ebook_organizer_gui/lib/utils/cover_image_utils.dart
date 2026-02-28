// Conditional export for platform-safe cover image loading
export 'cover_image_utils_stub.dart'
    if (dart.library.io) 'cover_image_utils_native.dart';
