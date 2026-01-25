import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/local_ebook.dart';
import '../services/local_library_service.dart';

/// Provider for managing local ebook library state
class LocalLibraryProvider with ChangeNotifier {
  final LocalLibraryService _service = LocalLibraryService.instance;

  List<LocalEbook> _ebooks = [];
  LocalLibraryStats? _stats;
  bool _isLoading = false;
  bool _isScanning = false;
  String? _error;
  String? _libraryPath;
  int _scanProgress = 0;
  int _scanFound = 0;

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
  String? get error => _error;
  String? get libraryPath => _libraryPath;
  int get scanProgress => _scanProgress;
  int get scanFound => _scanFound;
  bool get hasLibraryPath => _libraryPath != null && _libraryPath!.isNotEmpty;

  String? get selectedCategory => _selectedCategory;
  String? get selectedFormat => _selectedFormat;
  String? get selectedAuthor => _selectedAuthor;
  String? get searchQuery => _searchQuery;
  String get sortBy => _sortBy;
  bool get sortAscending => _sortAscending;

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
    try {
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select your ebook library folder',
      );

      if (result != null) {
        // Verify directory exists
        if (!Directory(result).existsSync()) {
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

  /// Open ebook file with system default application
  Future<void> openEbook(LocalEbook ebook) async {
    try {
      final file = File(ebook.filePath);
      if (!await file.exists()) {
        _error = 'File no longer exists: ${ebook.filePath}';
        notifyListeners();
        return;
      }

      // Use platform-specific way to open file
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', ebook.filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [ebook.filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [ebook.filePath]);
      }
    } catch (e) {
      _error = 'Failed to open file: $e';
      notifyListeners();
    }
  }

  /// Open containing folder
  Future<void> openContainingFolder(LocalEbook ebook) async {
    try {
      final file = File(ebook.filePath);
      final directory = file.parent.path;

      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', ebook.filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [directory]);
      } else if (Platform.isMacOS) {
        await Process.run('open', ['-R', ebook.filePath]);
      }
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
}
