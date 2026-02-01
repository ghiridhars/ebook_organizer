import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;

class BackendService {
  static BackendService? _instance;
  Shell? _shell;
  bool _isRunning = false;
  String? _lastError;

  BackendService._();

  static BackendService get instance {
    _instance ??= BackendService._();
    return _instance!;
  }

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;

  void _logToFile(String message) {
    try {
      final logFile = io.File('backend_debug.log');
      final timestamp = DateTime.now().toIso8601String();
      logFile.writeAsStringSync('[$timestamp] $message\n', mode: io.FileMode.append);
    } catch (e) {
      // If file logging fails, still try debugPrint as fallback
      debugPrint('Failed to write to log file: $e');
      debugPrint(message);
    }
  }

  Future<bool> startBackend() async {
    if (_isRunning) {
      return true;
    }

    _lastError = null;

    try {
      // Get the backend directory path (adjust based on your structure)
      final currentDir = io.Directory.current.path;
      
      // Detect if running from built app (production) or development
      final isProduction = currentDir.contains('build');
      
      final backendDir = isProduction
        ? path.join(currentDir, '..', '..', '..', '..', 'backend')  // From build/windows/runner: up 4 levels
        : path.join(currentDir, '..', 'backend');  // From ebook_organizer_gui: up 1 level

      // Check if backend directory exists
      if (!io.Directory(backendDir).existsSync()) {
        _lastError = 'Backend directory not found: $backendDir (currentDir: $currentDir, isProduction: $isProduction)';
        _logToFile('[BackendService] $_lastError');
        return false;
      }

      // Create shell for running backend
      _shell = Shell(
        workingDirectory: backendDir,
        environment: {'PYTHONUNBUFFERED': '1'},
      );

      // Start backend in background
      // Prefer the bundled virtualenv interpreter when available to ensure deps are present
      final venvPython = io.Platform.isWindows
          ? path.join(backendDir, 'venv', 'Scripts', 'python.exe')
          : path.join(backendDir, 'venv', 'bin', 'python');
      final pythonCmd = io.File(venvPython).existsSync()
          ? venvPython
          : (io.Platform.isWindows ? 'python' : 'python3');
      
      _logToFile('[BackendService] Starting backend with: $pythonCmd -m app.main');
      
      _shell!.run('$pythonCmd -m app.main').then((_) {
        _logToFile('[BackendService] Backend process exited normally');
        _isRunning = false;
      }).catchError((error) {
        _lastError = 'Backend error: $error';
        _logToFile('[BackendService] $_lastError');
        _isRunning = false;
      });

      // Wait a bit for backend to start
      await Future.delayed(const Duration(seconds: 3));
      _isRunning = true;
      _logToFile('[BackendService] Backend started successfully');

      return true;
    } catch (e) {
      _lastError = 'Failed to start backend: $e';
      _logToFile('[BackendService] $_lastError');
      return false;
    }
  }

  Future<void> stopBackend() async {
    if (_shell != null) {
      try {
        _shell!.kill();
        _shell = null;
        _isRunning = false;
        _logToFile('[BackendService] Backend stopped');
      } catch (e) {
        _logToFile('[BackendService] Error stopping backend: $e');
      }
    }
  }
}
