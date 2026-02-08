import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/local_ebook.dart';
import '../services/local_library_service.dart';
import '../utils/platform_utils.dart';

/// View mode for displaying ebooks
enum ViewMode { grid, list }

/// Provider for managing local ebook library state
class LocalLibraryProvider with ChangeNotifier {
  final LocalLibraryService _service = LocalLibraryService.instance;
  static const String _viewModeKey = 'local_library_view_mode';

  List<LocalEbook> _ebooks = [];
  LocalLibraryStats? _stats;
  bool _isLoading = false;
  bool _isScanning = false;
  bool _isUploading = false;
  String? _error;
  String? _libraryPath;
  int _scanProgress = 0;
  int _scanFound = 0;
  
  // View mode
  ViewMode _viewMode = ViewMode.grid;

  // Filters
  String? _selectedCategory;
  String? _selectedFormat;
  String? _selectedAuthor;
  String? _searchQuery;
  String _sortBy = 'title';
  bool _sortAscending = true;

  // Getters
  List<LocalEbook> get ebooks => _ebooks;
  LocalLibraryStats? get stats => _stats;
  bool get isLoading => _isLoading;
  bool get isScanning => _isScanning;
  bool get isUploading => _isUploading;
  String? get error => _error;
  String? get libraryPath => _libraryPath;
  int get scanProgress => _scanProgress;
  int get scanFound => _scanFound;
  bool get hasLibraryPath => _libraryPath != null && _libraryPath!.isNotEmpty;

  /// Returns true if file upload is supported (always true, works on all platforms)
  bool get supportsFileUpload => _service.supportsFileUpload;

  String? get selectedCategory => _selectedCategory;
  String? get selectedFormat => _selectedFormat;
  String? get selectedAuthor => _selectedAuthor;
  String? get searchQuery => _searchQuery;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;
  
  // View mode
  ViewMode get viewMode => _viewMode;
  bool get isGridView => _viewMode == ViewMode.grid;
  bool get isListView => _viewMode == ViewMode.list;
  
  // Active filters check
  bool get hasActiveFilters => 
      _selectedCategory != null || 
      _selectedFormat != null || 
      _selectedAuthor != null ||
      (_searchQuery != null && _searchQuery!.isNotEmpty);
  
  int get activeFilterCount {
    int count = 0;
    if (_selectedCategory != null) count++;
    if (_selectedFormat != null) count++;
    if (_selectedAuthor != null) count++;
    if (_searchQuery != null && _searchQuery!.isNotEmpty) count++;
    return count;
  }

  /// Get filtered ebooks (the _ebooks list is already filtered by the service)
  List<LocalEbook> get filteredEbooks => _ebooks;

  /// Initialize provider
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      _libraryPath = await _service.getLibraryPath();
      await loadStats();
      await loadEbooks();
    } catch (e) {
      _error = 'Failed to initialize local library: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load library statistics
  Future<void> loadStats() async {
    try {
      _stats = await _service.getStats();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load stats: $e';
      notifyListeners();
    }
  }

  /// Load ebooks from local database
  Future<void> loadEbooks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _ebooks = await _service.getAllLocalEbooks(
        category: _selectedCategory,
        format: _selectedFormat,
        author: _selectedAuthor,
        search: _searchQuery,
        sortBy: _sortBy,
        ascending: _sortAscending,
      );
    } catch (e) {
      _error = 'Failed to load local ebooks: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Choose library folder
  Future<bool> chooseLibraryFolder() async {
    // Directory selection is not meaningful on web
    if (kIsWeb || !supportsScanDirectory) {
      _error = 'Directory selection is not supported on web. Please upload files individually.';
      notifyListeners();
      return false;
    }
    
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your ebook library folder',
      );

      if (result != null) {
        // Verify directory exists
        if (!await directoryExists(result)) {
          _error = 'Selected directory does not exist';
          notifyListeners();
          return false;
        }

        _libraryPath = result;
        await _service.setLibraryPath(result);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to select folder: $e';
      notifyListeners();
      return false;
    }
  }

  /// Scan library folder for ebooks
  Future<ScanResult?> scanLibrary({bool recursive = true}) async {
    if (_libraryPath == null || _libraryPath!.isEmpty) {
      _error = 'No library folder selected';
      notifyListeners();
      return null;
    }

    _isScanning = true;
    _scanProgress = 0;
    _scanFound = 0;
    _error = null;
    notifyListeners();

    try {
      final result = await _service.scanDirectory(
        _libraryPath!,
        recursive: recursive,
        onProgress: (scanned, found) {
          _scanProgress = scanned;
          _scanFound = found;
          notifyListeners();
        },
      );

      if (!result.success) {
        _error = result.error;
      }

      // Reload data after scan
      await loadStats();
      await loadEbooks();

      return result;
    } catch (e) {
      _error = 'Scan failed: $e';
      return ScanResult(success: false, error: _error);
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }

  /// Clear library index (keeps files, removes database entries)
  Future<void> clearIndex() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _service.clearAllLocalEbooks();
      _ebooks = [];
      await loadStats();
    } catch (e) {
      _error = 'Failed to clear index: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Upload ebook files (works on all platforms including web)
  Future<int> uploadFiles() async {
    _isUploading = true;
    _error = null;
    notifyListeners();

    int successCount = 0;

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: ['epub', 'mobi', 'pdf', 'azw', 'azw3', 'fb2', 'djvu', 'cbz', 'cbr'],
        withData: true, // Important: get file bytes for web
      );

      if (result != null && result.files.isNotEmpty) {
        for (final file in result.files) {
          if (file.bytes != null && file.name.isNotEmpty) {
            final ebook = await _service.addEbookFromBytes(
              fileName: file.name,
              bytes: file.bytes!,
              fileSize: file.size,
              modifiedDate: DateTime.now(),
            );
            if (ebook != null) {
              successCount++;
            }
          }
        }

        // Reload data after upload
        await loadStats();
        await loadEbooks();
      }
    } catch (e) {
      _error = 'Failed to upload files: $e';
    }

    _isUploading = false;
    notifyListeners();
    return successCount;
  }

  /// Update ebook metadata
  Future<void> updateEbook(LocalEbook ebook) async {
    try {
      await _service.updateLocalEbook(ebook);
      await loadEbooks();
    } catch (e) {
      _error = 'Failed to update ebook: $e';
      notifyListeners();
    }
  }

  /// Delete ebook from index (not the file)
  Future<void> deleteFromIndex(int id) async {
    try {
      await _service.deleteLocalEbook(id);
      await loadEbooks();
      await loadStats();
    } catch (e) {
      _error = 'Failed to delete ebook: $e';
      notifyListeners();
    }
  }

  /// Update classifications for books by file path
  Future<int> updateClassifications(Map<String, Map<String, String?>> classifications) async {
    try {
      final count = await _service.updateClassifications(classifications);
      if (count > 0) {
        await loadEbooks();
        await loadStats();
      }
      return count;
    } catch (e) {
      _error = 'Failed to update classifications: $e';
      notifyListeners();
      return 0;
    }
  }

  /// Open ebook file with system default application
  Future<void> openEbook(LocalEbook ebook) async {
    // File operations are not supported on web
    if (kIsWeb || !supportsFileOperations) {
      _error = 'Opening local files is not supported in web browsers';
      notifyListeners();
      return;
    }
    
    try {
      if (!await fileExists(ebook.filePath)) {
        _error = 'File no longer exists: ${ebook.filePath}';
        notifyListeners();
        return;
      }

      await openFile(ebook.filePath);
    } catch (e) {
      _error = 'Failed to open file: $e';
      notifyListeners();
    }
  }

  /// Open containing folder
  Future<void> openContainingFolder(LocalEbook ebook) async {
    // File operations are not supported on web
    if (kIsWeb || !supportsFileOperations) {
      _error = 'Opening folders is not supported in web browsers';
      notifyListeners();
      return;
    }
    
    try {
      await openContainingFolderPath(ebook.filePath);
    } catch (e) {
      _error = 'Failed to open folder: $e';
      notifyListeners();
    }
  }

  // Filter methods
  void setCategory(String? category) {
    _selectedCategory = category;
    loadEbooks();
  }

  void setFormat(String? format) {
    _selectedFormat = format;
    loadEbooks();
  }

  /// Alias for setFormat to match UI expectations
  void setFormatFilter(String? format) => setFormat(format);

  void setAuthor(String? author) {
    _selectedAuthor = author;
    loadEbooks();
  }

  /// Alias for setAuthor to match UI expectations
  void setAuthorFilter(String? author) => setAuthor(author);

  void setSearchQuery(String? query) {
    _searchQuery = query?.isEmpty == true ? null : query;
    loadEbooks();
  }

  void setSortBy(String sortBy, {bool? ascending}) {
    _sortBy = sortBy;
    if (ascending != null) _sortAscending = ascending;
    loadEbooks();
  }

  void toggleSortOrder() {
    _sortAscending = !_sortAscending;
    loadEbooks();
  }

  void clearFilters() {
    _selectedCategory = null;
    _selectedFormat = null;
    _selectedAuthor = null;
    _searchQuery = null;
    loadEbooks();
  }

  /// Get available formats in library
  Future<List<String>> getFormats() async {
    return await _service.getFormats();
  }

  /// Get available categories in library
  Future<List<String>> getCategories() async {
    return await _service.getCategories();
  }

  /// Get available authors in library
  Future<List<String>> getAuthors() async {
    return await _service.getAuthors();
  }

  // View mode methods
  
  /// Load saved view mode preference
  Future<void> loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_viewModeKey);
      if (saved == 'list') {
        _viewMode = ViewMode.list;
      } else {
        _viewMode = ViewMode.grid;
      }
      notifyListeners();
    } catch (e) {
      // Ignore, use default
    }
  }

  /// Set view mode and persist
  Future<void> setViewMode(ViewMode mode) async {
    if (_viewMode == mode) return;
    
    _viewMode = mode;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModeKey, mode == ViewMode.list ? 'list' : 'grid');
    } catch (e) {
      // Ignore persistence errors
    }
  }

  /// Toggle between grid and list view
  Future<void> toggleViewMode() async {
    final newMode = _viewMode == ViewMode.grid ? ViewMode.list : ViewMode.grid;
    await setViewMode(newMode);
  }
  
  // Individual filter clear methods
  void clearCategory() {
    _selectedCategory = null;
    loadEbooks();
  }
  
  void clearFormat() {
    _selectedFormat = null;
    loadEbooks();
  }
  
  void clearAuthor() {
    _selectedAuthor = null;
    loadEbooks();
  }
  
  void clearSearch() {
    _searchQuery = null;
    loadEbooks();
  }
}
