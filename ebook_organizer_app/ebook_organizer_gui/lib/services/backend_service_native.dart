import 'dart:io' as io;
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:process_run/shell.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;

/// Configuration for backend service
class BackendConfig {
  static const String host = '127.0.0.1';
  static const int port = 8000;
  static const Duration startupTimeout = Duration(seconds: 30);
  static const Duration healthCheckInterval = Duration(milliseconds: 500);
  static const int maxRetries = 60; // 30 seconds with 500ms interval
  static const Duration retryDelay = Duration(milliseconds: 500);
}

/// Backend service for managing the Python FastAPI backend process
class BackendService {
  static BackendService? _instance;
  Shell? _shell;
  bool _isRunning = false;
  String? _lastError;
  DateTime? _startedAt;

  BackendService._();

  static BackendService get instance {
    _instance ??= BackendService._();
    return _instance!;
  }

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  DateTime? get startedAt => _startedAt;
  
  String get baseUrl => 'http://${BackendConfig.host}:${BackendConfig.port}';
  String get healthUrl => '$baseUrl/health';

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    debugPrint('[$timestamp] [BackendService] $message');
    
    // Also write to log file for debugging
    try {
      final logFile = io.File('backend_debug.log');
      logFile.writeAsStringSync('[$timestamp] $message\n', mode: io.FileMode.append);
    } catch (e) {
      // Ignore file logging errors
    }
  }

  /// Check if the configured port is available
  Future<bool> _isPortAvailable() async {
    try {
      final socket = await io.Socket.connect(
        BackendConfig.host,
        BackendConfig.port,
        timeout: const Duration(milliseconds: 100),
      );
      await socket.close();
      return false; // Port is in use
    } catch (e) {
      return true; // Port is available
    }
  }

  /// Check if the backend is healthy by calling the health endpoint
  Future<bool> _checkHealth() async {
    try {
      final response = await http.get(
        Uri.parse(healthUrl),
      ).timeout(const Duration(seconds: 2));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'healthy';
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Wait for the backend to become healthy with retry logic
  Future<bool> _waitForHealthy({int maxAttempts = BackendConfig.maxRetries}) async {
    _log('Waiting for backend to become healthy...');
    
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      if (await _checkHealth()) {
        _log('Backend is healthy after $attempt attempt(s)');
        return true;
      }
      
      if (attempt % 10 == 0) {
        _log('Still waiting for backend... (attempt $attempt/$maxAttempts)');
      }
      
      await Future.delayed(BackendConfig.healthCheckInterval);
    }
    
    _log('Backend failed to become healthy after $maxAttempts attempts');
    return false;
  }

  /// Find the backend directory relative to current working directory
  String? _findBackendDirectory() {
    final currentDir = io.Directory.current.path;
    
    // Try multiple possible locations
    final possiblePaths = [
      path.join(currentDir, '..', 'backend'),  // From ebook_organizer_gui
      path.join(currentDir, 'backend'),         // From ebook_organizer_app
      path.join(currentDir, '..', '..', 'backend'),  // From nested build dir
      path.join(currentDir, '..', '..', '..', '..', 'backend'),  // Deep nested
    ];
    
    for (final backendPath in possiblePaths) {
      final normalized = path.normalize(backendPath);
      if (io.Directory(normalized).existsSync()) {
        // Verify it's the right directory by checking for app/main.py
        final mainPy = io.File(path.join(normalized, 'app', 'main.py'));
        if (mainPy.existsSync()) {
          return normalized;
        }
      }
    }
    
    return null;
  }

  /// Find the Python executable (prefer venv)
  String _findPythonExecutable(String backendDir) {
    final venvPython = io.Platform.isWindows
        ? path.join(backendDir, 'venv', 'Scripts', 'python.exe')
        : path.join(backendDir, 'venv', 'bin', 'python');
    
    if (io.File(venvPython).existsSync()) {
      return venvPython;
    }
    
    return io.Platform.isWindows ? 'python' : 'python3';
  }

  /// Start the backend process with health checking
  Future<bool> startBackend() async {
    if (_isRunning) {
      _log('Backend already running');
      return true;
    }

    _lastError = null;

    try {
      // Check if backend is already running (maybe from another instance)
      if (await _checkHealth()) {
        _log('Backend is already running externally');
        _isRunning = true;
        _startedAt = DateTime.now();
        return true;
      }

      // Check if port is available
      if (!await _isPortAvailable()) {
        // Something else is using the port, check if it's our backend
        if (await _checkHealth()) {
          _log('Backend detected on port, using existing instance');
          _isRunning = true;
          _startedAt = DateTime.now();
          return true;
        } else {
          _lastError = 'Port ${BackendConfig.port} is already in use by another application';
          _log(_lastError!);
          return false;
        }
      }

      // Find backend directory
      final backendDir = _findBackendDirectory();
      if (backendDir == null) {
        _lastError = 'Backend directory not found. Current dir: ${io.Directory.current.path}';
        _log(_lastError!);
        return false;
      }

      _log('Found backend at: $backendDir');

      // Find Python executable
      final pythonCmd = _findPythonExecutable(backendDir);
      _log('Using Python: $pythonCmd');

      // Create shell for running backend
      _shell = Shell(
        workingDirectory: backendDir,
        environment: {'PYTHONUNBUFFERED': '1'},
      );

      // Start backend in background
      _log('Starting backend with: $pythonCmd -m app.main');
      
      _shell!.run('$pythonCmd -m app.main').then((_) {
        _log('Backend process exited normally');
        _isRunning = false;
      }).catchError((error) {
        _lastError = 'Backend error: $error';
        _log(_lastError!);
        _isRunning = false;
      });

      // Wait for backend to become healthy
      final healthy = await _waitForHealthy();
      
      if (healthy) {
        _isRunning = true;
        _startedAt = DateTime.now();
        _log('Backend started successfully');
        return true;
      } else {
        _lastError = 'Backend failed to start within timeout';
        _log(_lastError!);
        await stopBackend();
        return false;
      }
    } catch (e, stackTrace) {
      _lastError = 'Failed to start backend: $e';
      _log('$_lastError\n$stackTrace');
      return false;
    }
  }

  /// Stop the backend process gracefully
  Future<void> stopBackend() async {
    if (_shell != null) {
      try {
        _log('Stopping backend...');
        _shell!.kill();
        _shell = null;
        _isRunning = false;
        _startedAt = null;
        _log('Backend stopped');
      } catch (e) {
        _log('Error stopping backend: $e');
      }
    }
  }

  /// Restart the backend process
  Future<bool> restartBackend() async {
    _log('Restarting backend...');
    await stopBackend();
    await Future.delayed(const Duration(seconds: 1));
    return await startBackend();
  }

  /// Check current backend health status
  Future<Map<String, dynamic>?> getHealthStatus() async {
    try {
      final response = await http.get(
        Uri.parse(healthUrl),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
    } catch (e) {
      // Backend not responding
    }
    return null;
  }
}
