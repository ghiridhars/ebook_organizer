/// Ebook model class
class Ebook {
  final int? id;
  final String cloudProvider;
  final String cloudFileId;
  final String? cloudFilePath;
  final String title;
  final String? author;
  final String? isbn;
  final String? publisher;
  final String? publishedDate;
  final String? description;
  final String? language;
  final int? pageCount;
  final String? category;
  final String? subGenre;
  final String fileFormat;
  final int? fileSize;
  final String? fileHash;
  final DateTime lastSynced;
  final bool isSynced;
  final String syncStatus;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;

  Ebook({
    this.id,
    required this.cloudProvider,
    required this.cloudFileId,
    this.cloudFilePath,
    required this.title,
    this.author,
    this.isbn,
    this.publisher,
    this.publishedDate,
    this.description,
    this.language,
    this.pageCount,
    this.category,
    this.subGenre,
    required this.fileFormat,
    this.fileSize,
    this.fileHash,
    required this.lastSynced,
    this.isSynced = true,
    this.syncStatus = 'synced',
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
  });

  /// Create from JSON (API response)
  factory Ebook.fromJson(Map<String, dynamic> json) {
    return Ebook(
      id: json['id'],
      cloudProvider: json['cloud_provider'] ?? '',
      cloudFileId: json['cloud_file_id'] ?? '',
      cloudFilePath: json['cloud_file_path'],
      title: json['title'] ?? 'Unknown Title',
      author: json['author'],
      isbn: json['isbn'],
      publisher: json['publisher'],
      publishedDate: json['published_date'],
      description: json['description'],
      language: json['language'],
      pageCount: json['page_count'],
      category: json['category'],
      subGenre: json['sub_genre'],
      fileFormat: json['file_format'] ?? '',
      fileSize: json['file_size'],
      fileHash: json['file_hash'],
      lastSynced: DateTime.parse(json['last_synced']),
      isSynced: json['is_synced'] ?? true,
      syncStatus: json['sync_status'] ?? 'synced',
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  /// Convert to JSON (API request)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cloud_provider': cloudProvider,
      'cloud_file_id': cloudFileId,
      'cloud_file_path': cloudFilePath,
      'title': title,
      'author': author,
      'isbn': isbn,
      'publisher': publisher,
      'published_date': publishedDate,
      'description': description,
      'language': language,
      'page_count': pageCount,
      'category': category,
      'sub_genre': subGenre,
      'file_format': fileFormat,
      'file_size': fileSize,
      'file_hash': fileHash,
      'last_synced': lastSynced.toIso8601String(),
      'is_synced': isSynced,
      'sync_status': syncStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tags': tags,
    };
  }

  /// Create from SQLite database map
  factory Ebook.fromMap(Map<String, dynamic> map) {
    return Ebook(
      id: map['id'],
      cloudProvider: map['cloud_provider'] ?? '',
      cloudFileId: map['cloud_file_id'] ?? '',
      cloudFilePath: map['cloud_file_path'],
      title: map['title'] ?? 'Unknown Title',
      author: map['author'],
      isbn: map['isbn'],
      publisher: map['publisher'],
      publishedDate: map['published_date'],
      description: map['description'],
      language: map['language'],
      pageCount: map['page_count'],
      category: map['category'],
      subGenre: map['sub_genre'],
      fileFormat: map['file_format'] ?? '',
      fileSize: map['file_size'],
      fileHash: map['file_hash'],
      lastSynced: DateTime.parse(map['last_synced']),
      isSynced: map['is_synced'] == 1,
      syncStatus: map['sync_status'] ?? 'synced',
      createdAt: DateTime.parse(map['created_at']),
      updatedAt: DateTime.parse(map['updated_at']),
      tags: map['tags'] != null ? (map['tags'] as String).split(',') : [],
    );
  }

  /// Convert to SQLite database map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cloud_provider': cloudProvider,
      'cloud_file_id': cloudFileId,
      'cloud_file_path': cloudFilePath,
      'title': title,
      'author': author,
      'isbn': isbn,
      'publisher': publisher,
      'published_date': publishedDate,
      'description': description,
      'language': language,
      'page_count': pageCount,
      'category': category,
      'sub_genre': subGenre,
      'file_format': fileFormat,
      'file_size': fileSize,
      'file_hash': fileHash,
      'last_synced': lastSynced.toIso8601String(),
      'is_synced': isSynced ? 1 : 0,
      'sync_status': syncStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tags': tags.join(','),
    };
  }

  /// Copy with method for updates
  Ebook copyWith({
    int? id,
    String? cloudProvider,
    String? cloudFileId,
    String? cloudFilePath,
    String? title,
    String? author,
    String? isbn,
    String? publisher,
    String? publishedDate,
    String? description,
    String? language,
    int? pageCount,
    String? category,
    String? subGenre,
    String? fileFormat,
    int? fileSize,
    String? fileHash,
    DateTime? lastSynced,
    bool? isSynced,
    String? syncStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String>? tags,
  }) {
    return Ebook(
      id: id ?? this.id,
      cloudProvider: cloudProvider ?? this.cloudProvider,
      cloudFileId: cloudFileId ?? this.cloudFileId,
      cloudFilePath: cloudFilePath ?? this.cloudFilePath,
      title: title ?? this.title,
      author: author ?? this.author,
      isbn: isbn ?? this.isbn,
      publisher: publisher ?? this.publisher,
      publishedDate: publishedDate ?? this.publishedDate,
      description: description ?? this.description,
      language: language ?? this.language,
      pageCount: pageCount ?? this.pageCount,
      category: category ?? this.category,
      subGenre: subGenre ?? this.subGenre,
      fileFormat: fileFormat ?? this.fileFormat,
      fileSize: fileSize ?? this.fileSize,
      fileHash: fileHash ?? this.fileHash,
      lastSynced: lastSynced ?? this.lastSynced,
      isSynced: isSynced ?? this.isSynced,
      syncStatus: syncStatus ?? this.syncStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? this.tags,
    );
  }

  /// Get formatted file size
  String get fileSizeFormatted {
    if (fileSize == null) return 'Unknown';
    final kb = fileSize! / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  /// Get display author (handle null/empty)
  String get displayAuthor => author?.isNotEmpty == true ? author! : 'Unknown Author';

  /// Get display category
  String get displayCategory => category?.isNotEmpty == true ? category! : 'Uncategorized';
}
