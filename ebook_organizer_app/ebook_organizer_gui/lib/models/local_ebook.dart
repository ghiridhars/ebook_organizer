import 'package:flutter/foundation.dart' show debugPrint;
import 'ebook_file_data.dart';
import '../services/epub_metadata_service.dart';

/// Model for locally stored ebook files
class LocalEbook {
  final int? id;
  final String filePath;
  final String fileName;
  final String title;
  final String? author;
  final String fileFormat;
  final int fileSize;
  final DateTime modifiedDate;
  final DateTime indexedAt;
  final String? coverPath;
  final String? description;
  final String? category;
  final String? subGenre;
  final List<String> tags;

  LocalEbook({
    this.id,
    required this.filePath,
    required this.fileName,
    required this.title,
    this.author,
    required this.fileFormat,
    required this.fileSize,
    required this.modifiedDate,
    required this.indexedAt,
    this.coverPath,
    this.description,
    this.category,
    this.subGenre,
    this.tags = const [],
  });

  /// Create from file data (works on all platforms including web)
  factory LocalEbook.fromFileData(EbookFileData fileData) {
    final fileName = fileData.fileName;
    final extension = fileData.extension;
    
    // Extract title from filename (remove extension)
    String baseName = fileName;
    if (fileName.contains('.')) {
      baseName = fileName.substring(0, fileName.lastIndexOf('.'));
    }
    
    // Try to extract author and title from common filename patterns
    String title = baseName;
    String? author;
    
    // Pattern 1: "Author - Title" or "Title - Author"
    if (baseName.contains(' - ')) {
      final parts = baseName.split(' - ');
      if (parts.length == 2) {
        final first = parts[0].trim();
        final second = parts[1].trim();
        
        if (first.length < second.length && _looksLikeName(first)) {
          author = first;
          title = second;
        } else if (_looksLikeName(second)) {
          title = first;
          author = second;
        } else {
          author = first;
          title = second;
        }
      }
    }
    // Pattern 2: "Title (Author)" or "Title [Author]"
    else if (baseName.contains('(') && baseName.contains(')')) {
      final match = RegExp(r'^(.+?)\s*\(([^)]+)\)\s*$').firstMatch(baseName);
      if (match != null) {
        title = match.group(1)!.trim();
        final inParens = match.group(2)!.trim();
        if (_looksLikeName(inParens)) {
          author = inParens;
        }
      }
    }
    else if (baseName.contains('[') && baseName.contains(']')) {
      final match = RegExp(r'^(.+?)\s*\[([^\]]+)\]\s*$').firstMatch(baseName);
      if (match != null) {
        title = match.group(1)!.trim();
        final inBrackets = match.group(2)!.trim();
        if (_looksLikeName(inBrackets)) {
          author = inBrackets;
        }
      }
    }
    // Pattern 3: "Author_Title" with underscores
    else if (baseName.contains('_') && !baseName.contains(' ')) {
      final parts = baseName.split('_');
      if (parts.length >= 2) {
        final first = parts[0].trim();
        if (_looksLikeName(first)) {
          author = first;
          title = parts.sublist(1).join(' ');
        }
      }
    }
    
    // Clean up title
    title = title
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    
    // Clean up author if extracted
    if (author != null) {
      author = author
          .replaceAll('_', ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (author.isEmpty) author = null;
    }

    return LocalEbook(
      filePath: fileData.filePath,
      fileName: fileName,
      title: title,
      author: author,
      fileFormat: extension,
      fileSize: fileData.fileSize,
      modifiedDate: fileData.modifiedDate,
      indexedAt: DateTime.now(),
    );
  }

  /// Create from dart:io File (native platforms only)
  /// On web, use fromFileData with file picker result instead
  factory LocalEbook.fromFile(dynamic file) {
    final stat = file.statSync();
    final String path = file.path;
    final fileName = path.split(RegExp(r'[/\\]')).last;
    
    return LocalEbook.fromFileData(EbookFileData(
      fileName: fileName,
      filePath: path,
      fileSize: stat.size,
      modifiedDate: stat.modified,
    ));
  }

  /// Create from file with EPUB metadata reading (async version)
  /// Works on native platforms; on web, metadata reading may be limited
  static Future<LocalEbook> fromFileDataWithMetadata(
    EbookFileData fileData, {
    Future<EpubMetadata?> Function(String path)? metadataReader,
  }) async {
    final ebook = LocalEbook.fromFileData(fileData);
    
    if (ebook.fileFormat.toLowerCase() == 'epub' && metadataReader != null) {
      try {
        final metadata = await metadataReader(fileData.filePath);
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
        debugPrint('Failed to read EPUB metadata: $e');
      }
    }
    
    return ebook;
  }
  
  /// Helper to check if a string looks like a person's name
  static bool _looksLikeName(String s) {
    if (s.isEmpty || s.length > 50) return false;
    final words = s.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty || words.length > 5) return false;
    int capitalizedCount = 0;
    for (final word in words) {
      if (word[0] == word[0].toUpperCase()) capitalizedCount++;
    }
    return capitalizedCount >= words.length / 2;
  }

  /// Create from SQLite database map
  factory LocalEbook.fromMap(Map<String, dynamic> map) {
    return LocalEbook(
      id: map['id'],
      filePath: map['file_path'] ?? '',
      fileName: map['file_name'] ?? '',
      title: map['title'] ?? 'Unknown',
      author: map['author'],
      fileFormat: map['file_format'] ?? '',
      fileSize: map['file_size'] ?? 0,
      modifiedDate: DateTime.parse(map['modified_date']),
      indexedAt: DateTime.parse(map['indexed_at']),
      coverPath: map['cover_path'],
      description: map['description'],
      category: map['category'],
      subGenre: map['sub_genre'],
      tags: map['tags'] != null && map['tags'].isNotEmpty 
          ? (map['tags'] as String).split(',') 
          : [],
    );
  }

  /// Convert to SQLite database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'file_path': filePath,
      'file_name': fileName,
      'title': title,
      'author': author,
      'file_format': fileFormat,
      'file_size': fileSize,
      'modified_date': modifiedDate.toIso8601String(),
      'indexed_at': indexedAt.toIso8601String(),
      'cover_path': coverPath,
      'description': description,
      'category': category,
      'sub_genre': subGenre,
      'tags': tags.join(','),
    };
  }

  /// Copy with method for updates
  LocalEbook copyWith({
    int? id,
    String? filePath,
    String? fileName,
    String? title,
    String? author,
    String? fileFormat,
    int? fileSize,
    DateTime? modifiedDate,
    DateTime? indexedAt,
    String? coverPath,
    String? description,
    String? category,
    String? subGenre,
    List<String>? tags,
  }) {
    return LocalEbook(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      fileName: fileName ?? this.fileName,
      title: title ?? this.title,
      author: author ?? this.author,
      fileFormat: fileFormat ?? this.fileFormat,
      fileSize: fileSize ?? this.fileSize,
      modifiedDate: modifiedDate ?? this.modifiedDate,
      indexedAt: indexedAt ?? this.indexedAt,
      coverPath: coverPath ?? this.coverPath,
      description: description ?? this.description,
      category: category ?? this.category,
      subGenre: subGenre ?? this.subGenre,
      tags: tags ?? this.tags,
    );
  }

  /// Get formatted file size
  String get fileSizeFormatted {
    final kb = fileSize / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  /// Get display author
  String get displayAuthor => author?.isNotEmpty == true ? author! : 'Unknown Author';

  /// Get display category
  String get displayCategory => category?.isNotEmpty == true ? category! : 'Uncategorized';

  /// Check if file path is valid (not a web blob URL)
  bool get hasLocalPath => filePath.isNotEmpty && !filePath.startsWith('blob:');

  /// Supported ebook formats
  static const List<String> supportedFormats = [
    'epub', 'mobi', 'pdf', 'azw', 'azw3', 'fb2', 'djvu', 'cbz', 'cbr'
  ];

  /// Check if format is supported
  static bool isSupported(String extension) {
    return supportedFormats.contains(extension.toLowerCase());
  }
}

// Note: EpubMetadata, LocalLibraryStats, and ScanResult are defined in the service files
// to maintain backward compatibility with existing code.
// - EpubMetadata: see epub_metadata_service.dart
// - LocalLibraryStats: see local_library_service_interface.dart  
// - ScanResult: see local_library_service_interface.dart
