import 'package:flutter/foundation.dart';

/// Web stub for BackendService
/// On web, the backend must be started externally
class BackendService {
  static BackendService? _instance;
  final bool _isRunning = false;
  String? _lastError;

  BackendService._();

  static BackendService get instance {
    _instance ??= BackendService._();
    return _instance!;
  }

  bool get isRunning => _isRunning;
  String? get lastError => _lastError;
  DateTime? get startedAt => null;
  bool get usingBundledBackend => false;
  String get baseUrl => 'http://127.0.0.1:8000';
  String get healthUrl => '$baseUrl/health';

  Future<bool> startBackend() async {
    debugPrint('[BackendService] Running on web - backend must be started externally');
    _lastError = 'Backend launching is not supported in web browsers. Please run the backend separately.';
    return false;
  }

  Future<void> stopBackend() async {
    // No-op on web
    debugPrint('[BackendService] Stop backend (web - no-op)');
  }

  Future<bool> restartBackend() async {
    debugPrint('[BackendService] Restart backend (web - no-op)');
    _lastError = 'Backend launching is not supported in web browsers. Please run the backend separately.';
    return false;
  }

  Future<Map<String, dynamic>?> getHealthStatus() async {
    // Cannot check health on web without a running backend
    return null;
  }
}
