import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/local_ebook.dart';
import '../utils/app_config.dart';
import 'local_library_service_interface.dart';

/// Web-compatible implementation of LocalLibraryService
/// Uses in-memory storage since sqflite doesn't support web
/// Data will be lost on page refresh - this is a limitation of web platform
class LocalLibraryServiceWeb implements LocalLibraryServiceInterface {
  static final LocalLibraryServiceWeb instance = LocalLibraryServiceWeb._init();
  
  // In-memory storage for web
  final List<LocalEbook> _ebooks = [];
  final Map<String, String> _settings = {};
  int _nextId = 1;

  LocalLibraryServiceWeb._init();

  /// Supported ebook file extensions
  static Set<String> get supportedExtensions =>
      AppConfig.supportedFormats.map((f) => '.$f').toSet();

  /// Maximum file size to index
  static int get maxFileSize => AppConfig.maxFileSize;

  @override
  bool get supportsScanDirectory => false;

  @override
  bool get supportsFileUpload => true;

  @override
  Future<String?> getLibraryPath() async {
    // On web, there's no persistent library path
    return null;
  }

  @override
  Future<void> setLibraryPath(String libraryPath) async {
    // No-op on web
  }

  @override
  Future<DateTime?> getLastScanTime() async {
    final value = _settings['last_scan'];
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  @override
  Future<void> setLastScanTime(DateTime time) async {
    _settings['last_scan'] = time.toIso8601String();
  }

  @override
  Future<ScanResult> scanDirectory(
    String directoryPath, {
    bool recursive = true,
    void Function(int scanned, int found)? onProgress,
  }) async {
    // Not supported on web
    return ScanResult(
      success: false,
      error: 'Directory scanning is not supported on web. Please upload files using the button above.',
    );
  }

  @override
  Future<LocalEbook?> addEbookFromBytes({
    required String fileName,
    required List<int> bytes,
    required int fileSize,
    required DateTime modifiedDate,
  }) async {
    final extension = _getExtension(fileName).toLowerCase();
    if (!supportedExtensions.contains(extension)) {
      return null;
    }

    if (fileSize > maxFileSize) {
      return null;
    }

    // Extract metadata from file bytes
    final format = extension.substring(1).toLowerCase();
    String title = _extractTitleFromFileName(fileName);
    String? author;
    String? description;
    List<String>? tags;

    // Try to extract metadata for EPUB files
    if (format == 'epub') {
      try {
        final metadata = _readEpubMetadataFromBytes(bytes);
        if (metadata != null) {
          title = metadata['title'] ?? title;
          author = metadata['author'];
          description = metadata['description'];
          tags = (metadata['subjects'] as List<dynamic>?)?.cast<String>();
        }
      } catch (e) {
        // Silently fail - use filename-based title
      }
    }

    // Generate a unique path for web-uploaded files
    final uniquePath = 'web_upload_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    // Check if already exists (by filename and size)
    final existingIndex = _ebooks.indexWhere(
      (e) => e.fileName == fileName && e.fileSize == fileSize,
    );

    final ebook = LocalEbook(
      id: existingIndex >= 0 ? _ebooks[existingIndex].id : _nextId++,
      filePath: uniquePath,
      fileName: fileName,
      title: title,
      author: author,
      fileFormat: format,
      fileSize: fileSize,
      modifiedDate: modifiedDate,
      indexedAt: DateTime.now(),
      description: description,
      tags: tags ?? [],
    );

    if (existingIndex >= 0) {
      _ebooks[existingIndex] = ebook;
    } else {
      _ebooks.add(ebook);
    }

    return ebook;
  }

  String _getExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot);
  }

  /// Read EPUB metadata directly from bytes
  Map<String, dynamic>? _readEpubMetadataFromBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);

      // Find container.xml
      final containerFile = archive.findFile('META-INF/container.xml');
      if (containerFile == null) return null;

      final containerContent = String.fromCharCodes(containerFile.content as List<int>);
      final containerDoc = XmlDocument.parse(containerContent);

      // Get OPF path
      final rootfileElement = containerDoc.findAllElements('rootfile').firstOrNull;
      if (rootfileElement == null) return null;

      final opfPath = rootfileElement.getAttribute('full-path');
      if (opfPath == null) return null;

      // Read OPF file
      final opfFile = archive.findFile(opfPath);
      if (opfFile == null) return null;

      final opfContent = String.fromCharCodes(opfFile.content as List<int>);
      final opfDoc = XmlDocument.parse(opfContent);

      // Extract metadata
      final metadata = <String, dynamic>{};

      final metadataElement = opfDoc.findAllElements('metadata').firstOrNull;
      if (metadataElement != null) {
        // Title
        final titleElement = metadataElement.findAllElements('dc:title').firstOrNull ??
            metadataElement.findAllElements('title').firstOrNull;
        if (titleElement != null) {
          metadata['title'] = titleElement.innerText.trim();
        }

        // Creator/Author
        final creatorElement = metadataElement.findAllElements('dc:creator').firstOrNull ??
            metadataElement.findAllElements('creator').firstOrNull;
        if (creatorElement != null) {
          metadata['author'] = creatorElement.innerText.trim();
        }

        // Description
        final descElement = metadataElement.findAllElements('dc:description').firstOrNull ??
            metadataElement.findAllElements('description').firstOrNull;
        if (descElement != null) {
          metadata['description'] = descElement.innerText.trim();
        }

        // Subjects
        final subjectElements = metadataElement.findAllElements('dc:subject').toList() +
            metadataElement.findAllElements('subject').toList();
        if (subjectElements.isNotEmpty) {
          metadata['subjects'] = subjectElements.map((e) => e.innerText.trim()).toList();
        }
      }

      return metadata;
    } catch (e) {
      return null;
    }
  }

  String _extractTitleFromFileName(String fileName) {
    // Remove extension
    final lastDot = fileName.lastIndexOf('.');
    final nameWithoutExt = lastDot > 0 ? fileName.substring(0, lastDot) : fileName;
    
    // Clean up common patterns
    var title = nameWithoutExt
        .replaceAll(RegExp(r'[-_.]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Title case
    if (title.isNotEmpty) {
      title = title.split(' ').map((word) {
        if (word.isEmpty) return word;
        return word[0].toUpperCase() + word.substring(1).toLowerCase();
      }).join(' ');
    }
    
    return title.isNotEmpty ? title : fileName;
  }

  @override
  Future<List<LocalEbook>> getAllLocalEbooks({
    int? limit,
    int? offset,
    String? category,
    String? author,
    String? search,
    String? format,
    String? sortBy,
    bool ascending = true,
  }) async {
    var result = List<LocalEbook>.from(_ebooks);

    // Apply filters
    if (category != null) {
      result = result.where((e) => e.category == category).toList();
    }

    if (author != null) {
      final authorLower = author.toLowerCase();
      result = result.where((e) => 
        e.author?.toLowerCase().contains(authorLower) ?? false
      ).toList();
    }

    if (search != null && search.isNotEmpty) {
      final searchLower = search.toLowerCase();
      result = result.where((e) =>
        e.title.toLowerCase().contains(searchLower) ||
        (e.author?.toLowerCase().contains(searchLower) ?? false) ||
        e.fileName.toLowerCase().contains(searchLower)
      ).toList();
    }

    if (format != null) {
      result = result.where((e) => e.fileFormat == format).toList();
    }

    // Sort
    result.sort((a, b) {
      int comparison;
      switch (sortBy) {
        case 'author':
          comparison = (a.author ?? '').compareTo(b.author ?? '');
          break;
        case 'file_size':
          comparison = a.fileSize.compareTo(b.fileSize);
          break;
        case 'modified_date':
          comparison = a.modifiedDate.compareTo(b.modifiedDate);
          break;
        case 'indexed_at':
          comparison = a.indexedAt.compareTo(b.indexedAt);
          break;
        case 'title':
        default:
          comparison = a.title.compareTo(b.title);
      }
      return ascending ? comparison : -comparison;
    });

    // Apply pagination
    if (offset != null && offset > 0) {
      result = result.skip(offset).toList();
    }
    if (limit != null) {
      result = result.take(limit).toList();
    }

    return result;
  }

  @override
  Future<LocalEbook?> getLocalEbookById(int id) async {
    try {
      return _ebooks.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> updateLocalEbook(LocalEbook ebook) async {
    final index = _ebooks.indexWhere((e) => e.id == ebook.id);
    if (index >= 0) {
      _ebooks[index] = ebook;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> deleteLocalEbook(int id) async {
    final lengthBefore = _ebooks.length;
    _ebooks.removeWhere((e) => e.id == id);
    return lengthBefore - _ebooks.length;
  }

  @override
  Future<LocalLibraryStats> getStats() async {
    final totalCount = _ebooks.length;
    final totalSize = _ebooks.fold<int>(0, (sum, e) => sum + e.fileSize);

    // Count by format
    final formatCounts = <String, int>{};
    for (final ebook in _ebooks) {
      formatCounts[ebook.fileFormat] = (formatCounts[ebook.fileFormat] ?? 0) + 1;
    }

    // Count by category
    final categoryCounts = <String, int>{};
    for (final ebook in _ebooks) {
      if (ebook.category != null) {
        categoryCounts[ebook.category!] = (categoryCounts[ebook.category!] ?? 0) + 1;
      }
    }

    return LocalLibraryStats(
      totalBooks: totalCount,
      totalSize: totalSize,
      formatCounts: formatCounts,
      categoryCounts: categoryCounts,
      lastScan: await getLastScanTime(),
      libraryPath: null,
    );
  }

  @override
  Future<void> clearAllLocalEbooks() async {
    _ebooks.clear();
  }

  @override
  Future<List<String>> getFormats() async {
    final formats = _ebooks.map((e) => e.fileFormat).toSet().toList();
    formats.sort();
    return formats;
  }

  @override
  Future<List<String>> getCategories() async {
    final categories = _ebooks
        .where((e) => e.category != null)
        .map((e) => e.category!)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  @override
  Future<List<String>> getAuthors() async {
    final authors = _ebooks
        .where((e) => e.author != null && e.author!.isNotEmpty)
        .map((e) => e.author!)
        .toSet()
        .toList();
    authors.sort();
    return authors;
  }
}

// Typedef for compatibility with existing code
typedef LocalLibraryService = LocalLibraryServiceWeb;
