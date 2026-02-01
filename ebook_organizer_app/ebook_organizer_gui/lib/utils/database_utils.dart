import 'package:flutter/foundation.dart' show kIsWeb;
import 'database_utils_stub.dart'
    if (dart.library.io) 'database_utils_ffi.dart' as platform;

/// Shared database utilities to avoid code duplication
class DatabaseUtils {
  static bool _initialized = false;

  /// Initialize FFI for desktop platforms (Windows/Linux)
  /// Safe to call multiple times - will only initialize once
  /// Does nothing on web platform
  static void initializeFfi() {
    // Skip on web - sqflite uses IndexedDB on web automatically
    if (_initialized || kIsWeb) return;
    
    platform.initializeFfi();
    _initialized = true;
  }
}
