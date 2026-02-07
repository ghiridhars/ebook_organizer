import 'package:flutter/foundation.dart';
import '../models/ebook.dart';
import '../services/api_service.dart';
import '../services/database_service.dart';

class EbookProvider with ChangeNotifier {
  final ApiService _apiService = ApiService();
  final DatabaseService _dbService = DatabaseService.instance;

  List<Ebook> _ebooks = [];
  List<Ebook> _filteredEbooks = [];
  bool _isLoading = false;
  bool _isOnline = false;
  String? _error;
  
  // Filters
  String? _selectedCategory;
  String? _selectedSubGenre;
  String? _searchQuery;
  String? _selectedFormat;

  List<Ebook> get ebooks => _filteredEbooks;
  bool get isLoading => _isLoading;
  bool get isOnline => _isOnline;
  String? get error => _error;
  String? get selectedCategory => _selectedCategory;
  String? get selectedSubGenre => _selectedSubGenre;
  String? get searchQuery => _searchQuery;
  String? get selectedFormat => _selectedFormat;

  Future<void> initialize() async {
    // Only check backend availability on startup
    // Don't auto-load books - wait for user to select a folder
    await checkBackendStatus();
  }

  Future<void> checkBackendStatus() async {
    _isOnline = await _apiService.isBackendAvailable();
    notifyListeners();
  }

  Future<void> checkBackendAndSync() async {
    _isOnline = await _apiService.isBackendAvailable();
    notifyListeners();

    if (_isOnline && _activeSourcePath != null) {
      await syncWithBackend(sourcePath: _activeSourcePath);
    }
  }

  Future<void> loadEbooksFromLocal() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _ebooks = await _dbService.getAllEbooks(
        category: _selectedCategory,
        subGenre: _selectedSubGenre,
        search: _searchQuery,
        format: _selectedFormat,
      );
      _filteredEbooks = List.from(_ebooks);
    } catch (e) {
      _error = 'Failed to load ebooks from local database: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  String? _activeSourcePath;
  
  String? get activeSourcePath => _activeSourcePath;

  Future<void> syncWithBackend({String? sourcePath}) async {
    if (!_isOnline) return;
    
    // Set active source path
    if (sourcePath != null) {
      _activeSourcePath = sourcePath;
    }

    try {
      final backendEbooks = await _apiService.getEbooks(sourcePath: _activeSourcePath);
      
      // Update local database
      await _dbService.clearAllEbooks();
      for (var ebook in backendEbooks) {
        await _dbService.insertEbook(ebook);
      }

      await loadEbooksFromLocal();
    } catch (e) {
      _error = 'Failed to sync with backend: $e';
      notifyListeners();
    }
  }

  Future<void> updateEbook(int id, Map<String, dynamic> updates) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (_isOnline) {
        // Update via API
        final updatedEbook = await _apiService.updateEbook(id, updates);
        // Update local database
        await _dbService.updateEbook(updatedEbook);
      } else {
        // Update only locally
        final ebook = await _dbService.getEbookById(id);
        if (ebook != null) {
          final updated = ebook.copyWith(
            title: updates['title'] ?? ebook.title,
            author: updates['author'] ?? ebook.author,
            category: updates['category'] ?? ebook.category,
            subGenre: updates['sub_genre'] ?? ebook.subGenre,
            description: updates['description'] ?? ebook.description,
            tags: updates['tags'] ?? ebook.tags,
            isSynced: false,
            syncStatus: 'pending',
          );
          await _dbService.updateEbook(updated);
        }
      }

      await loadEbooksFromLocal();
    } catch (e) {
      _error = 'Failed to update ebook: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  void setCategory(String? category) {
    _selectedCategory = category;
    loadEbooksFromLocal();
  }

  void setSubGenre(String? subGenre) {
    _selectedSubGenre = subGenre;
    loadEbooksFromLocal();
  }

  void setSearchQuery(String? query) {
    _searchQuery = query?.isEmpty == true ? null : query;
    loadEbooksFromLocal();
  }

  void setFormat(String? format) {
    _selectedFormat = format;
    loadEbooksFromLocal();
  }

  void clearFilters() {
    _selectedCategory = null;
    _selectedSubGenre = null;
    _searchQuery = null;
    _selectedFormat = null;
    loadEbooksFromLocal();
  }
}
