import 'dart:io';

/// Native platform utilities for desktop (Windows, Linux, macOS)

/// Check if a directory exists at the given path
Future<bool> directoryExists(String path) async {
  return Directory(path).existsSync();
}

/// Check if a file exists at the given path
Future<bool> fileExists(String path) async {
  return File(path).exists();
}

/// Open a file with the system's default application
Future<void> openFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw Exception('File does not exist: $path');
  }

  if (Platform.isWindows) {
    await Process.run('cmd', ['/c', 'start', '', path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [path]);
  } else if (Platform.isMacOS) {
    await Process.run('open', [path]);
  } else {
    throw UnsupportedError('File opening not supported on this platform');
  }
}

/// Open the containing folder for a file
Future<void> openContainingFolderPath(String path) async {
  final file = File(path);
  final directory = file.parent.path;

  if (Platform.isWindows) {
    await Process.run('explorer', ['/select,', path]);
  } else if (Platform.isLinux) {
    await Process.run('xdg-open', [directory]);
  } else if (Platform.isMacOS) {
    await Process.run('open', ['-R', path]);
  } else {
    throw UnsupportedError('Folder opening not supported on this platform');
  }
}

/// Get whether the current platform supports file operations
bool get supportsFileOperations => true;

/// Get whether the current platform supports directory scanning
bool get supportsScanDirectory => true;
