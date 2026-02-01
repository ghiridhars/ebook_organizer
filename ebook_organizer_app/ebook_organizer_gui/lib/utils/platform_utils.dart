// Conditional export for platform-specific utilities
export 'platform_utils_stub.dart'
    if (dart.library.io) 'platform_utils_native.dart';
