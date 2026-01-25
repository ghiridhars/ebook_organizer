import 'dart:io';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;

class BackendService {
  static BackendService? _instance;
  Shell? _shell;
  bool _isRunning = false;

  BackendService._();

  static BackendService get instance {
    _instance ??= BackendService._();
    return _instance!;
  }

  bool get isRunning => _isRunning;

  Future<bool> startBackend() async {
    if (_isRunning) {
      return true;
    }

    try {
      // Get the backend directory path (adjust based on your structure)
      final currentDir = Directory.current.path;
      final backendDir = path.join(
        path.dirname(currentDir),
        'backend',
      );

      // Check if backend directory exists
      if (!Directory(backendDir).existsSync()) {
        return false;
      }

      // Create shell for running backend
      _shell = Shell(
        workingDirectory: backendDir,
        environment: {'PYTHONUNBUFFERED': '1'},
      );

      // Start backend in background
      // Prefer the bundled virtualenv interpreter when available to ensure deps are present
      final venvPython = Platform.isWindows
          ? path.join(backendDir, 'venv', 'Scripts', 'python.exe')
          : path.join(backendDir, 'venv', 'bin', 'python');
      final pythonCmd = File(venvPython).existsSync()
          ? venvPython
          : (Platform.isWindows ? 'python' : 'python3');
      
      _shell!.run('$pythonCmd -m app.main').then((_) {
        _isRunning = false;
      }).catchError((error) {
        _isRunning = false;
      });

      // Wait a bit for backend to start
      await Future.delayed(const Duration(seconds: 3));
      _isRunning = true;

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> stopBackend() async {
    if (_shell != null) {
      try {
        _shell!.kill();
        _shell = null;
        _isRunning = false;
      } catch (e) {
        // Error stopping backend
      }
    }
  }
}
