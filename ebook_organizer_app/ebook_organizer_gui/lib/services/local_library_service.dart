import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/local_ebook.dart';
import 'epub_metadata_service.dart';
import 'backend_metadata_service.dart';

/// Service for managing local ebook library
class LocalLibraryService {
  static final LocalLibraryService instance = LocalLibraryService._init();
  static Database? _database;

  LocalLibraryService._init();

  /// Supported ebook file extensions
  static const Set<String> supportedExtensions = {
    '.epub', '.mobi', '.pdf', '.azw', '.azw3', '.fb2', '.djvu', '.cbz', '.cbr'
  };

  /// Maximum file size to index (500 MB)
  static const int maxFileSize = 500 * 1024 * 1024;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('local_library.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for desktop platforms
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final dbFilePath = path.join(dbPath, filePath);

    return await openDatabase(
      dbFilePath,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Create local_ebooks table
    await db.execute('''
      CREATE TABLE local_ebooks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        file_name TEXT NOT NULL,
        title TEXT NOT NULL,
        author TEXT,
        file_format TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        modified_date TEXT NOT NULL,
        indexed_at TEXT NOT NULL,
        cover_path TEXT,
        description TEXT,
        category TEXT,
        tags TEXT
      )
    ''');

    // Create settings table for library paths
    await db.execute('''
      CREATE TABLE library_settings(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL
      )
    ''');

    // Create indexes
    await db.execute('CREATE INDEX idx_local_title ON local_ebooks(title)');
    await db.execute('CREATE INDEX idx_local_author ON local_ebooks(author)');
    await db.execute('CREATE INDEX idx_local_format ON local_ebooks(file_format)');
    await db.execute('CREATE INDEX idx_local_category ON local_ebooks(category)');
  }

  /// Get stored library path
  Future<String?> getLibraryPath() async {
    final db = await database;
    final result = await db.query(
      'library_settings',
      where: 'key = ?',
      whereArgs: ['library_path'],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  /// Set library path
  Future<void> setLibraryPath(String libraryPath) async {
    final db = await database;
    await db.insert(
      'library_settings',
      {'key': 'library_path', 'value': libraryPath},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get last scan time
  Future<DateTime?> getLastScanTime() async {
    final db = await database;
    final result = await db.query(
      'library_settings',
      where: 'key = ?',
      whereArgs: ['last_scan'],
    );
    if (result.isEmpty) return null;
    return DateTime.parse(result.first['value'] as String);
  }

  /// Set last scan time
  Future<void> setLastScanTime(DateTime time) async {
    final db = await database;
    await db.insert(
      'library_settings',
      {'key': 'last_scan', 'value': time.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Create LocalEbook from file, reading EPUB metadata if applicable
  Future<LocalEbook> _createEbookFromFile(File file, {bool useBackend = false}) async {
    // First create basic ebook from filename
    final ebook = LocalEbook.fromFile(file);
    
    // If it's an EPUB, try to read embedded metadata (native Dart)
    if (EpubMetadataService.isEpub(file.path)) {
      try {
        final metadata = await EpubMetadataService.instance.readMetadata(file.path);
        if (metadata != null) {
          return LocalEbook(
            filePath: ebook.filePath,
            fileName: ebook.fileName,
            title: metadata.title?.isNotEmpty == true ? metadata.title! : ebook.title,
            author: metadata.creator?.isNotEmpty == true ? metadata.creator : ebook.author,
            fileFormat: ebook.fileFormat,
            fileSize: ebook.fileSize,
            modifiedDate: ebook.modifiedDate,
            indexedAt: ebook.indexedAt,
            description: metadata.description,
            tags: metadata.subjects,
          );
        }
      } catch (e) {
        // Fall back to filename-based extraction
        print('Failed to read EPUB metadata for ${file.path}: $e');
      }
    }
    // For PDF/MOBI, try to read metadata via Python backend
    else if (useBackend && (ebook.fileFormat == 'pdf' || ebook.fileFormat == 'mobi')) {
      try {
        final result = await backendMetadataService.readMetadata(file.path);
        if (result != null && result['metadata'] != null) {
          final metadata = result['metadata'] as Map<String, dynamic>;
          return LocalEbook(
            filePath: ebook.filePath,
            fileName: ebook.fileName,
            title: metadata['title']?.toString().isNotEmpty == true 
                ? metadata['title'] as String 
                : ebook.title,
            author: metadata['author']?.toString().isNotEmpty == true 
                ? metadata['author'] as String 
                : ebook.author,
            fileFormat: ebook.fileFormat,
            fileSize: ebook.fileSize,
            modifiedDate: ebook.modifiedDate,
            indexedAt: ebook.indexedAt,
            description: metadata['description'] as String?,
            tags: (metadata['subjects'] as List<dynamic>?)?.cast<String>() ?? [],
          );
        }
      } catch (e) {
        print('Failed to read ${ebook.fileFormat.toUpperCase()} metadata for ${file.path}: $e');
      }
    }
    
    return ebook;
  }

  /// Scan directory for ebook files
  Future<ScanResult> scanDirectory(
    String directoryPath, {
    bool recursive = true,
    void Function(int scanned, int found)? onProgress,
  }) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      return ScanResult(
        success: false,
        error: 'Directory does not exist: $directoryPath',
      );
    }

    // Check if backend is available for PDF/MOBI metadata reading
    final backendAvailable = await backendMetadataService.isBackendAvailable();
    if (backendAvailable) {
      print('Backend available - will read PDF/MOBI metadata during scan');
    }

    final db = await database;
    int scannedCount = 0;
    int foundCount = 0;
    int addedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    final errors = <String>[];

    try {
      // Get existing file paths for quick lookup
      final existingFiles = await db.query('local_ebooks', columns: ['file_path', 'modified_date']);
      final existingMap = {
        for (var row in existingFiles) 
          row['file_path'] as String: DateTime.parse(row['modified_date'] as String)
      };

      // Collect all ebook files
      final List<FileSystemEntity> files = recursive
          ? await directory.list(recursive: true, followLinks: false).toList()
          : await directory.list(followLinks: false).toList();

      for (final entity in files) {
        scannedCount++;

        if (entity is! File) continue;

        final extension = path.extension(entity.path).toLowerCase();
        if (!supportedExtensions.contains(extension)) continue;

        foundCount++;
        onProgress?.call(scannedCount, foundCount);

        try {
          final stat = await entity.stat();
          
          // Skip files that are too large
          if (stat.size > maxFileSize) {
            skippedCount++;
            continue;
          }

          final filePath = entity.path;
          final existingModified = existingMap[filePath];

          if (existingModified != null) {
            // File already indexed - check if modified
            if (stat.modified.isAfter(existingModified)) {
              // Update existing entry
              final ebook = await _createEbookFromFile(entity, useBackend: backendAvailable);
              await db.update(
                'local_ebooks',
                ebook.toMap()..remove('id'),
                where: 'file_path = ?',
                whereArgs: [filePath],
              );
              updatedCount++;
            } else {
              skippedCount++;
            }
          } else {
            // New file - add to database
            final ebook = await _createEbookFromFile(entity, useBackend: backendAvailable);
            await db.insert('local_ebooks', ebook.toMap()..remove('id'));
            addedCount++;
          }
        } catch (e) {
          errors.add('Error processing ${entity.path}: $e');
        }
      }

      // Remove entries for files that no longer exist
      final currentPaths = files
          .whereType<File>()
          .where((f) => supportedExtensions.contains(path.extension(f.path).toLowerCase()))
          .map((f) => f.path)
          .toSet();
      
      int removedCount = 0;
      for (final existingPath in existingMap.keys) {
        if (!currentPaths.contains(existingPath)) {
          await db.delete('local_ebooks', where: 'file_path = ?', whereArgs: [existingPath]);
          removedCount++;
        }
      }

      await setLastScanTime(DateTime.now());

      return ScanResult(
        success: true,
        scannedCount: scannedCount,
        foundCount: foundCount,
        addedCount: addedCount,
        updatedCount: updatedCount,
        skippedCount: skippedCount,
        removedCount: removedCount,
        errors: errors,
      );
    } catch (e) {
      return ScanResult(
        success: false,
        error: 'Scan failed: $e',
        errors: errors,
      );
    }
  }

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
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (category != null) {
      whereClause += 'category = ?';
      whereArgs.add(category);
    }

    if (author != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'author LIKE ?';
      whereArgs.add('%$author%');
    }

    if (search != null && search.isNotEmpty) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += '(title LIKE ? OR author LIKE ? OR file_name LIKE ?)';
      whereArgs.addAll(['%$search%', '%$search%', '%$search%']);
    }

    if (format != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'file_format = ?';
      whereArgs.add(format);
    }

    String orderBy = sortBy ?? 'title';
    orderBy += ascending ? ' ASC' : ' DESC';

    final List<Map<String, dynamic>> maps = await db.query(
      'local_ebooks',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      limit: limit,
      offset: offset,
      orderBy: orderBy,
    );

    return List.generate(maps.length, (i) => LocalEbook.fromMap(maps[i]));
  }

  /// Get local ebook by ID
  Future<LocalEbook?> getLocalEbookById(int id) async {
    final db = await database;
    final maps = await db.query(
      'local_ebooks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return LocalEbook.fromMap(maps.first);
  }

  /// Update local ebook metadata
  Future<int> updateLocalEbook(LocalEbook ebook) async {
    final db = await database;
    return await db.update(
      'local_ebooks',
      ebook.toMap(),
      where: 'id = ?',
      whereArgs: [ebook.id],
    );
  }

  /// Delete local ebook entry (not the file)
  Future<int> deleteLocalEbook(int id) async {
    final db = await database;
    return await db.delete(
      'local_ebooks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get library statistics
  Future<LocalLibraryStats> getStats() async {
    final db = await database;
    
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM local_ebooks');
    final totalCount = Sqflite.firstIntValue(countResult) ?? 0;

    final sizeResult = await db.rawQuery('SELECT SUM(file_size) as total FROM local_ebooks');
    final totalSize = sizeResult.first['total'] as int? ?? 0;

    final formatResult = await db.rawQuery(
      'SELECT file_format, COUNT(*) as count FROM local_ebooks GROUP BY file_format ORDER BY count DESC'
    );
    final formatCounts = {
      for (var row in formatResult) 
        row['file_format'] as String: row['count'] as int
    };

    final categoryResult = await db.rawQuery(
      'SELECT category, COUNT(*) as count FROM local_ebooks WHERE category IS NOT NULL GROUP BY category ORDER BY count DESC LIMIT 10'
    );
    final categoryCounts = {
      for (var row in categoryResult) 
        row['category'] as String: row['count'] as int
    };

    return LocalLibraryStats(
      totalBooks: totalCount,
      totalSize: totalSize,
      formatCounts: formatCounts,
      categoryCounts: categoryCounts,
      lastScan: await getLastScanTime(),
      libraryPath: await getLibraryPath(),
    );
  }

  /// Clear all local ebook entries
  Future<void> clearAllLocalEbooks() async {
    final db = await database;
    await db.delete('local_ebooks');
  }

  /// Get unique formats in library
  Future<List<String>> getFormats() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT file_format FROM local_ebooks ORDER BY file_format'
    );
    return result.map((r) => r['file_format'] as String).toList();
  }

  /// Get unique categories in library
  Future<List<String>> getCategories() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT category FROM local_ebooks WHERE category IS NOT NULL ORDER BY category'
    );
    return result.map((r) => r['category'] as String).toList();
  }

  /// Get unique authors in library
  Future<List<String>> getAuthors() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT author FROM local_ebooks WHERE author IS NOT NULL AND author != "" ORDER BY author'
    );
    return result.map((r) => r['author'] as String).toList();
  }
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
