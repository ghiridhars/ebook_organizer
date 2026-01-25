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

  LibraryStats get stats => _stats;
  List<CloudProvider> get cloudProviders => _cloudProviders;
  bool get isLoading => _isLoading;
  bool get isSyncing => _isSyncing;
  String? get error => _error;

  Future<void> loadStats() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _stats = await _apiService.getLibraryStats();
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

  Future<void> triggerSync({String? provider, bool fullSync = false}) async {
    _isSyncing = true;
    _error = null;
    notifyListeners();

    try {
      await _apiService.triggerSync(provider: provider, fullSync: fullSync);
      await Future.delayed(const Duration(seconds: 2));
      await loadStats();
    } catch (e) {
      _error = 'Failed to trigger sync: $e';
    }

    _isSyncing = false;
    notifyListeners();
  }
}
