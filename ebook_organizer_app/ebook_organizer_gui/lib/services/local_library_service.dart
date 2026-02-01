// Conditional export for platform-specific LocalLibraryService implementation
// On web: uses LocalLibraryServiceWeb (no directory scanning, file upload only)
// On native: uses LocalLibraryServiceNative (full directory scanning support)
export 'local_library_service_stub.dart'
    if (dart.library.io) 'local_library_service_native.dart';

// Re-export interface and models for convenience
export 'local_library_service_interface.dart';
