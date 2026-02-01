import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/ebook.dart';
import '../utils/database_utils.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ebook_organizer.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    // Initialize FFI for desktop platforms (uses shared utility)
    DatabaseUtils.initializeFfi();

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Create ebooks table
    await db.execute('''
      CREATE TABLE ebooks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cloud_provider TEXT NOT NULL,
        cloud_file_id TEXT NOT NULL UNIQUE,
        cloud_file_path TEXT,
        title TEXT NOT NULL,
        author TEXT,
        isbn TEXT,
        publisher TEXT,
        published_date TEXT,
        description TEXT,
        language TEXT,
        page_count INTEGER,
        category TEXT,
        sub_genre TEXT,
        file_format TEXT NOT NULL,
        file_size INTEGER,
        file_hash TEXT,
        last_synced TEXT NOT NULL,
        is_synced INTEGER DEFAULT 1,
        sync_status TEXT DEFAULT 'synced',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        tags TEXT
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_title ON ebooks(title)');
    await db.execute('CREATE INDEX idx_author ON ebooks(author)');
    await db.execute('CREATE INDEX idx_category ON ebooks(category)');
    await db.execute('CREATE INDEX idx_cloud_file_id ON ebooks(cloud_file_id)');
  }

  Future<int> insertEbook(Ebook ebook) async {
    final db = await database;
    return await db.insert('ebooks', ebook.toMap());
  }

  Future<List<Ebook>> getAllEbooks({
    int? limit,
    int? offset,
    String? category,
    String? subGenre,
    String? author,
    String? search,
    String? format,
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (category != null) {
      whereClause += 'category = ?';
      whereArgs.add(category);
    }

    if (subGenre != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'sub_genre = ?';
      whereArgs.add(subGenre);
    }

    if (author != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'author LIKE ?';
      whereArgs.add('%$author%');
    }

    if (search != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += '(title LIKE ? OR author LIKE ? OR description LIKE ?)';
      whereArgs.addAll(['%$search%', '%$search%', '%$search%']);
    }

    if (format != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'file_format = ?';
      whereArgs.add(format);
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'ebooks',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      limit: limit,
      offset: offset,
      orderBy: 'title ASC',
    );

    return List.generate(maps.length, (i) => Ebook.fromMap(maps[i]));
  }

  Future<Ebook?> getEbookById(int id) async {
    final db = await database;
    final maps = await db.query(
      'ebooks',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (maps.isEmpty) return null;
    return Ebook.fromMap(maps.first);
  }

  Future<int> updateEbook(Ebook ebook) async {
    final db = await database;
    return await db.update(
      'ebooks',
      ebook.toMap(),
      where: 'id = ?',
      whereArgs: [ebook.id],
    );
  }

  Future<int> deleteEbook(int id) async {
    final db = await database;
    return await db.delete(
      'ebooks',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> getEbookCount({
    String? category,
    String? format,
  }) async {
    final db = await database;
    
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (category != null) {
      whereClause = 'category = ?';
      whereArgs.add(category);
    }

    if (format != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'file_format = ?';
      whereArgs.add(format);
    }

    final result = await db.query(
      'ebooks',
      columns: ['COUNT(*) as count'],
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<String>> getDistinctCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ebooks',
      columns: ['DISTINCT category'],
      orderBy: 'category ASC',
    );

    return List.generate(maps.length, (i) => maps[i]['category'] as String? ?? 'Unknown');
  }

  Future<List<String>> getDistinctAuthors() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'ebooks',
      columns: ['DISTINCT author'],
      orderBy: 'author ASC',
    );

    return List.generate(maps.length, (i) => maps[i]['author'] as String? ?? 'Unknown');
  }

  Future<void> clearAllEbooks() async {
    final db = await database;
    await db.delete('ebooks');
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
  }
}
