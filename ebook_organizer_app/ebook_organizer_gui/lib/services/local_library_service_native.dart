import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import '../models/local_ebook.dart';
import '../utils/database_utils.dart';
import '../utils/app_config.dart';
import 'local_library_service_interface.dart';
import 'epub_metadata_service.dart';
import 'backend_metadata_service.dart';

/// Native (Desktop) implementation of LocalLibraryService
/// Supports directory scanning and file operations
class LocalLibraryServiceNative implements LocalLibraryServiceInterface {
  static final LocalLibraryServiceNative instance = LocalLibraryServiceNative._init();
  static Database? _database;

  LocalLibraryServiceNative._init();

  /// Supported ebook file extensions (from AppConfig)
  static Set<String> get supportedExtensions => 
      AppConfig.supportedFormats.map((f) => '.$f').toSet();

  /// Maximum file size to index (from AppConfig)
  static int get maxFileSize => AppConfig.maxFileSize;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('local_library.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for desktop platforms (uses shared utility)
    DatabaseUtils.initializeFfi();

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

  @override
  bool get supportsScanDirectory => true;

  @override
  bool get supportsFileUpload => true;

  @override
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

  @override
  Future<void> setLibraryPath(String libraryPath) async {
    final db = await database;
    await db.insert(
      'library_settings',
      {'key': 'library_path', 'value': libraryPath},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
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

  @override
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

  @override
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

  @override
  Future<LocalEbook?> addEbookFromBytes({
    required String fileName,
    required List<int> bytes,
    required int fileSize,
    required DateTime modifiedDate,
  }) async {
    final extension = path.extension(fileName).toLowerCase();
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
        print('Failed to read EPUB metadata: $e');
      }
    }

    // Generate a unique path for uploaded files
    final uniquePath = 'upload_${DateTime.now().millisecondsSinceEpoch}_$fileName';

    final ebook = LocalEbook(
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

    final db = await database;
    
    // Check if already exists
    final existing = await db.query(
      'local_ebooks',
      where: 'file_name = ? AND file_size = ?',
      whereArgs: [fileName, fileSize],
    );

    if (existing.isNotEmpty) {
      // Update existing
      await db.update(
        'local_ebooks',
        ebook.toMap()..remove('id'),
        where: 'file_name = ? AND file_size = ?',
        whereArgs: [fileName, fileSize],
      );
      return ebook.copyWith(id: existing.first['id'] as int);
    } else {
      // Insert new
      final id = await db.insert('local_ebooks', ebook.toMap()..remove('id'));
      return ebook.copyWith(id: id);
    }
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
      print('Error parsing EPUB: $e');
      return null;
    }
  }

  String _extractTitleFromFileName(String fileName) {
    final nameWithoutExt = path.basenameWithoutExtension(fileName);
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

  @override
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

  @override
  Future<int> updateLocalEbook(LocalEbook ebook) async {
    final db = await database;
    return await db.update(
      'local_ebooks',
      ebook.toMap(),
      where: 'id = ?',
      whereArgs: [ebook.id],
    );
  }

  @override
  Future<int> deleteLocalEbook(int id) async {
    final db = await database;
    return await db.delete(
      'local_ebooks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
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

  @override
  Future<void> clearAllLocalEbooks() async {
    final db = await database;
    await db.delete('local_ebooks');
  }

  @override
  Future<List<String>> getFormats() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT file_format FROM local_ebooks ORDER BY file_format'
    );
    return result.map((r) => r['file_format'] as String).toList();
  }

  @override
  Future<List<String>> getCategories() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT category FROM local_ebooks WHERE category IS NOT NULL ORDER BY category'
    );
    return result.map((r) => r['category'] as String).toList();
  }

  @override
  Future<List<String>> getAuthors() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT DISTINCT author FROM local_ebooks WHERE author IS NOT NULL AND author != "" ORDER BY author'
    );
    return result.map((r) => r['author'] as String).toList();
  }
}

// Re-export as the default service name for backward compatibility
// Use conditional import to select the right implementation
typedef LocalLibraryService = LocalLibraryServiceNative;
