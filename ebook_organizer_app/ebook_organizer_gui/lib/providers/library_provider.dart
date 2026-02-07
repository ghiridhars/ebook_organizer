import 'package:flutter/foundation.dart';
import '../models/library_stats.dart';
import '../models/cloud_provider.dart';
import '../services/api_service.dart';

class LibraryProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();

  LibraryStats _stats = LibraryStats.empty();
  List<CloudProvider> _cloudProviders = [];
  bool _isLoading = false;
  bool _isSyncing = false;
  String? _error;
  String? _activeSourcePath;

  Map<String, dynamic>? _syncStatus;

  LibraryStats get stats => _stats;
  List<CloudProvider> get cloudProviders => _cloudProviders;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;
  Map<String, dynamic>? get syncStatus => _syncStatus;
  String? get activeSourcePath => _activeSourcePath;

  void setActiveSourcePath(String? path) {
    _activeSourcePath = path;
    notifyListeners();
    loadStats();
  }

  Future<void> loadStats() async {
    // Don't load stats without a source path - return empty
    if (_activeSourcePath == null) {
      _stats = LibraryStats.empty();
      notifyListeners();
      return;
    }
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stats = await _apiService.getLibraryStats(sourcePath: _activeSourcePath);
    } catch (e) {
      _error = 'Failed to load library stats: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadCloudProviders() async {
    try {
      _cloudProviders = await _apiService.getCloudProviders();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load cloud providers: $e';
      notifyListeners();
    }
  }

  Future<void> triggerSync({String? provider, bool fullSync = false, String? localPath}) async {
    _isSyncing = true;
    _error = null;
    _syncStatus = null;
    
    // Set active source path for scoped filtering
    if (localPath != null) {
      _activeSourcePath = localPath;
    }
    notifyListeners();

    try {
      await _apiService.triggerSync(provider: provider, fullSync: fullSync, localPath: localPath);
      
      // Poll for status
      bool active = true;
      while (active) {
        await Future.delayed(const Duration(seconds: 1));
        try {
          final status = await _apiService.getSyncStatus();
          _syncStatus = status;
          active = status['is_active'] == true;
          notifyListeners();
        } catch (e) {
           print('Error polling sync status: $e');
        }
      }

      await loadStats();
    } catch (e) {
      _error = 'Failed to trigger sync: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }
  Future<void> toggleProvider(String providerId, bool isEnabled) async {
    // Optimistic update
    final index = _cloudProviders.indexWhere((p) => p.provider == providerId);
    if (index != -1) {
      final oldStatus = _cloudProviders[index].isEnabled;
      _cloudProviders[index] = _cloudProviders[index].copyWith(isEnabled: isEnabled);
      notifyListeners();

      try {
        if (isEnabled) {
          // Trigger authentication flow if enabling
          // TODO: Implement full auth flow
          await _apiService.authenticateProvider(providerId);
        } else {
          // Disconnect if disabling
          await _apiService.disconnectProvider(providerId);
        }
      } catch (e) {
        // Revert on error
        _cloudProviders[index] = _cloudProviders[index].copyWith(isEnabled: oldStatus);
        _error = 'Failed to update provider: $e';
        notifyListeners();
      }
    }
  }
}
