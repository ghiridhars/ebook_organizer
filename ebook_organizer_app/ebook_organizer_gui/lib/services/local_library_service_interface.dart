import '../models/local_ebook.dart';

/// Abstract interface for local library operations
/// Platform-specific implementations handle the actual file operations
abstract class LocalLibraryServiceInterface {
  /// Get stored library path (null on web)
  Future<String?> getLibraryPath();

  /// Set library path (no-op on web)
  Future<void> setLibraryPath(String libraryPath);

  /// Get last scan time
  Future<DateTime?> getLastScanTime();

  /// Set last scan time
  Future<void> setLastScanTime(DateTime time);

  /// Scan directory for ebook files (not available on web)
  Future<ScanResult> scanDirectory(
    String directoryPath, {
    bool recursive = true,
    void Function(int scanned, int found)? onProgress,
  });

  /// Add ebook from bytes (for web file upload)
  Future<LocalEbook?> addEbookFromBytes({
    required String fileName,
    required List<int> bytes,
    required int fileSize,
    required DateTime modifiedDate,
  });

  /// Get all local ebooks
  Future<List<LocalEbook>> getAllLocalEbooks({
    int? limit,
    int? offset,
    String? category,
    String? author,
    String? search,
    String? format,
    String? sortBy,
    bool ascending = true,
  });

  /// Get local ebook by ID
  Future<LocalEbook?> getLocalEbookById(int id);

  /// Update local ebook metadata
  Future<int> updateLocalEbook(LocalEbook ebook);

  /// Delete local ebook entry
  Future<int> deleteLocalEbook(int id);

  /// Get library statistics
  Future<LocalLibraryStats> getStats();

  /// Clear all local ebook entries
  Future<void> clearAllLocalEbooks();

  /// Get unique formats in library
  Future<List<String>> getFormats();

  /// Get unique categories in library
  Future<List<String>> getCategories();

  /// Get unique authors in library
  Future<List<String>> getAuthors();

  /// Check if directory scanning is supported (false on web)
  bool get supportsScanDirectory;

  /// Check if the platform supports file uploads
  bool get supportsFileUpload;
}

/// Result of a library scan
class ScanResult {
  final bool success;
  final String? error;
  final int scannedCount;
  final int foundCount;
  final int addedCount;
  final int updatedCount;
  final int skippedCount;
  final int removedCount;
  final List<String> errors;

  ScanResult({
    required this.success,
    this.error,
    this.scannedCount = 0,
    this.foundCount = 0,
    this.addedCount = 0,
    this.updatedCount = 0,
    this.skippedCount = 0,
    this.removedCount = 0,
    this.errors = const [],
  });

  String get summary {
    if (!success) return error ?? 'Scan failed';
    return 'Found $foundCount ebooks: $addedCount added, $updatedCount updated, $removedCount removed';
  }
}

/// Local library statistics
class LocalLibraryStats {
  final int totalBooks;
  final int totalSize;
  final Map<String, int> formatCounts;
  final Map<String, int> categoryCounts;
  final DateTime? lastScan;
  final String? libraryPath;

  LocalLibraryStats({
    required this.totalBooks,
    required this.totalSize,
    required this.formatCounts,
    required this.categoryCounts,
    this.lastScan,
    this.libraryPath,
  });

  String get totalSizeFormatted {
    final kb = totalSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  String get lastScanFormatted {
    if (lastScan == null) return 'Never';
    final diff = DateTime.now().difference(lastScan!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }
}
