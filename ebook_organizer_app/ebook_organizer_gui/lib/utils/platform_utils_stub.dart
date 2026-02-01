/// Stub platform utilities for web
/// File operations are not available on web
library;

/// Check if a directory exists at the given path
Future<bool> directoryExists(String path) async {
  // On web, always return false - no local file system access
  return false;
}

/// Check if a file exists at the given path
Future<bool> fileExists(String path) async {
  // On web, always return false - no local file system access
  return false;
}

/// Open a file with the system's default application
Future<void> openFile(String path) async {
  // Not supported on web
  throw UnsupportedError('File opening is not supported on web');
}

/// Open the containing folder for a file
Future<void> openContainingFolderPath(String path) async {
  // Not supported on web
  throw UnsupportedError('Folder opening is not supported on web');
}

/// Get whether the current platform supports file operations
bool get supportsFileOperations => false;

/// Get whether the current platform supports directory scanning
bool get supportsScanDirectory => false;
