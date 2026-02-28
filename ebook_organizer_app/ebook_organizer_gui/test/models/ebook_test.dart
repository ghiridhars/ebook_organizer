import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/models/ebook.dart';

void main() {
  final now = DateTime(2026, 1, 15, 10, 30);

  Ebook _makeEbook({
    int? id,
    String cloudProvider = 'google_drive',
    String cloudFileId = 'file123',
    String? cloudFilePath = '/ebooks/test.epub',
    String title = 'Test Book',
    String? author = 'Test Author',
    String? isbn,
    String? publisher,
    String? publishedDate,
    String? description,
    String? language,
    int? pageCount,
    String? category,
    String? subGenre,
    String fileFormat = 'epub',
    int? fileSize,
    String? fileHash,
    DateTime? lastSynced,
    bool isSynced = true,
    String syncStatus = 'synced',
    DateTime? createdAt,
    DateTime? updatedAt,
    List<String> tags = const [],
  }) {
    return Ebook(
      id: id,
      cloudProvider: cloudProvider,
      cloudFileId: cloudFileId,
      cloudFilePath: cloudFilePath,
      title: title,
      author: author,
      isbn: isbn,
      publisher: publisher,
      publishedDate: publishedDate,
      description: description,
      language: language,
      pageCount: pageCount,
      category: category,
      subGenre: subGenre,
      fileFormat: fileFormat,
      fileSize: fileSize,
      fileHash: fileHash,
      lastSynced: lastSynced ?? now,
      isSynced: isSynced,
      syncStatus: syncStatus,
      createdAt: createdAt ?? now,
      updatedAt: updatedAt ?? now,
      tags: tags,
    );
  }

  group('Ebook', () {
    group('fromJson', () {
      test('parses full JSON correctly', () {
        final json = {
          'id': 1,
          'cloud_provider': 'google_drive',
          'cloud_file_id': 'abc123',
          'cloud_file_path': '/books/test.epub',
          'title': 'Flutter in Action',
          'author': 'Eric Windmill',
          'isbn': '978-1617296147',
          'publisher': 'Manning',
          'published_date': '2020-01-01',
          'description': 'A great book',
          'language': 'en',
          'page_count': 368,
          'category': 'Technology',
          'sub_genre': 'Mobile Development',
          'file_format': 'epub',
          'file_size': 5242880,
          'file_hash': 'abc123hash',
          'last_synced': '2026-01-15T10:30:00.000',
          'is_synced': true,
          'sync_status': 'synced',
          'created_at': '2026-01-15T10:30:00.000',
          'updated_at': '2026-01-15T10:30:00.000',
          'tags': ['flutter', 'dart', 'mobile'],
        };

        final ebook = Ebook.fromJson(json);
        expect(ebook.id, 1);
        expect(ebook.cloudProvider, 'google_drive');
        expect(ebook.title, 'Flutter in Action');
        expect(ebook.author, 'Eric Windmill');
        expect(ebook.isbn, '978-1617296147');
        expect(ebook.pageCount, 368);
        expect(ebook.category, 'Technology');
        expect(ebook.tags, ['flutter', 'dart', 'mobile']);
      });

      test('handles missing optional fields with defaults', () {
        final json = {
          'last_synced': '2026-01-15T10:30:00.000',
          'created_at': '2026-01-15T10:30:00.000',
          'updated_at': '2026-01-15T10:30:00.000',
        };

        final ebook = Ebook.fromJson(json);
        expect(ebook.cloudProvider, '');
        expect(ebook.cloudFileId, '');
        expect(ebook.title, 'Unknown Title');
        expect(ebook.fileFormat, '');
        expect(ebook.isSynced, true);
        expect(ebook.syncStatus, 'synced');
        expect(ebook.tags, isEmpty);
      });

      test('parses tags from list of dynamic', () {
        final json = {
          'last_synced': '2026-01-15T10:30:00.000',
          'created_at': '2026-01-15T10:30:00.000',
          'updated_at': '2026-01-15T10:30:00.000',
          'tags': [1, 'two', true],
        };

        final ebook = Ebook.fromJson(json);
        expect(ebook.tags, ['1', 'two', 'true']);
      });
    });

    group('toJson', () {
      test('serializes all fields', () {
        final ebook = _makeEbook(
          id: 42,
          title: 'Test',
          author: 'Author',
          tags: ['a', 'b'],
          fileSize: 1024,
        );

        final json = ebook.toJson();
        expect(json['id'], 42);
        expect(json['title'], 'Test');
        expect(json['author'], 'Author');
        expect(json['file_size'], 1024);
        expect(json['tags'], ['a', 'b']);
        expect(json['cloud_provider'], 'google_drive');
      });
    });

    group('fromMap / toMap', () {
      test('round-trips correctly', () {
        final original = _makeEbook(
          id: 1,
          title: 'Round Trip',
          author: 'Author',
          tags: ['tag1', 'tag2'],
        );

        final map = original.toMap();
        final restored = Ebook.fromMap(map);

        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.author, original.author);
        expect(restored.tags, original.tags);
        expect(restored.isSynced, original.isSynced);
      });

      test('toMap converts isSynced to int', () {
        final ebook = _makeEbook(isSynced: true);
        expect(ebook.toMap()['is_synced'], 1);

        final ebook2 = _makeEbook(isSynced: false);
        expect(ebook2.toMap()['is_synced'], 0);
      });

      test('toMap joins tags with comma', () {
        final ebook = _makeEbook(tags: ['a', 'b', 'c']);
        expect(ebook.toMap()['tags'], 'a,b,c');
      });

      test('fromMap splits tags string', () {
        final map = _makeEbook().toMap();
        map['tags'] = 'x,y,z';
        final ebook = Ebook.fromMap(map);
        expect(ebook.tags, ['x', 'y', 'z']);
      });

      test('fromMap handles null tags', () {
        final map = _makeEbook().toMap();
        map['tags'] = null;
        final ebook = Ebook.fromMap(map);
        expect(ebook.tags, isEmpty);
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = _makeEbook(title: 'Old Title', category: 'Fiction');
        final copy = original.copyWith(title: 'New Title');

        expect(copy.title, 'New Title');
        expect(copy.category, 'Fiction'); // unchanged
        expect(copy.cloudProvider, original.cloudProvider);
      });

      test('preserves all fields when no args given', () {
        final original = _makeEbook(
          id: 5,
          title: 'Keep',
          author: 'Same',
          tags: ['t'],
        );
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.title, original.title);
        expect(copy.author, original.author);
        expect(copy.tags, original.tags);
      });
    });

    group('computed properties', () {
      test('fileSizeFormatted shows KB', () {
        final ebook = _makeEbook(fileSize: 512000); // ~500 KB
        expect(ebook.fileSizeFormatted, contains('KB'));
      });

      test('fileSizeFormatted shows MB', () {
        final ebook = _makeEbook(fileSize: 5242880); // 5 MB
        expect(ebook.fileSizeFormatted, contains('MB'));
      });

      test('fileSizeFormatted handles null', () {
        final ebook = _makeEbook(fileSize: null);
        expect(ebook.fileSizeFormatted, 'Unknown');
      });

      test('displayAuthor falls back to Unknown Author', () {
        expect(_makeEbook(author: null).displayAuthor, 'Unknown Author');
        expect(_makeEbook(author: '').displayAuthor, 'Unknown Author');
        expect(_makeEbook(author: 'Real Author').displayAuthor, 'Real Author');
      });

      test('displayCategory falls back to Uncategorized', () {
        expect(_makeEbook(category: null).displayCategory, 'Uncategorized');
        expect(_makeEbook(category: '').displayCategory, 'Uncategorized');
        expect(_makeEbook(category: 'Sci-Fi').displayCategory, 'Sci-Fi');
      });
    });
  });
}
