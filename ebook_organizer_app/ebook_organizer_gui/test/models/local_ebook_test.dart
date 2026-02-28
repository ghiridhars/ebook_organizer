import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/models/local_ebook.dart';
import 'package:ebook_organizer_gui/models/ebook_file_data.dart';

void main() {
  group('LocalEbook', () {
    final now = DateTime(2026, 1, 15, 10, 30);

    LocalEbook _makeEbook({
      int? id,
      String filePath = '/books/test.epub',
      String fileName = 'test.epub',
      String title = 'Test Book',
      String? author,
      String fileFormat = 'epub',
      int fileSize = 1024,
      DateTime? modifiedDate,
      DateTime? indexedAt,
      String? coverPath,
      String? description,
      String? category,
      String? subGenre,
      List<String> tags = const [],
    }) {
      return LocalEbook(
        id: id,
        filePath: filePath,
        fileName: fileName,
        title: title,
        author: author,
        fileFormat: fileFormat,
        fileSize: fileSize,
        modifiedDate: modifiedDate ?? now,
        indexedAt: indexedAt ?? now,
        coverPath: coverPath,
        description: description,
        category: category,
        subGenre: subGenre,
        tags: tags,
      );
    }

    group('fromFileData', () {
      test('extracts title from simple filename', () {
        final data = EbookFileData(
          fileName: 'My Great Book.epub',
          filePath: '/books/My Great Book.epub',
          fileSize: 2048,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.title, 'My Great Book');
        expect(ebook.author, isNull);
        expect(ebook.fileFormat, 'epub');
      });

      test('extracts author and title from "Author - Title" pattern', () {
        final data = EbookFileData(
          fileName: 'Tolkien - The Hobbit.pdf',
          filePath: '/books/Tolkien - The Hobbit.pdf',
          fileSize: 5000,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.title, 'The Hobbit');
        expect(ebook.author, 'Tolkien');
        expect(ebook.fileFormat, 'pdf');
      });

      test('extracts author from parentheses pattern', () {
        final data = EbookFileData(
          fileName: 'The Hobbit (Tolkien).mobi',
          filePath: '/books/The Hobbit (Tolkien).mobi',
          fileSize: 3000,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.title, 'The Hobbit');
        expect(ebook.author, 'Tolkien');
      });

      test('extracts author from brackets pattern', () {
        final data = EbookFileData(
          fileName: 'The Hobbit [Tolkien].epub',
          filePath: '/books/The Hobbit [Tolkien].epub',
          fileSize: 3000,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.title, 'The Hobbit');
        expect(ebook.author, 'Tolkien');
      });

      test('handles underscore-separated filenames', () {
        final data = EbookFileData(
          fileName: 'Tolkien_The_Hobbit.epub',
          filePath: '/books/Tolkien_The_Hobbit.epub',
          fileSize: 3000,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.title, 'The Hobbit');
        expect(ebook.author, 'Tolkien');
      });

      test('preserves file metadata fields', () {
        final data = EbookFileData(
          fileName: 'book.pdf',
          filePath: '/documents/book.pdf',
          fileSize: 999999,
          modifiedDate: now,
        );
        final ebook = LocalEbook.fromFileData(data);
        expect(ebook.filePath, '/documents/book.pdf');
        expect(ebook.fileName, 'book.pdf');
        expect(ebook.fileSize, 999999);
        expect(ebook.modifiedDate, now);
        expect(ebook.fileFormat, 'pdf');
      });
    });

    group('fromMap / toMap', () {
      test('round-trips through SQLite map', () {
        final original = _makeEbook(
          id: 42,
          title: 'Dune',
          author: 'Frank Herbert',
          category: 'Fiction',
          subGenre: 'Science Fiction',
          tags: ['sci-fi', 'classic'],
          description: 'Desert planet saga',
        );

        final map = original.toMap();
        final restored = LocalEbook.fromMap(map);

        expect(restored.id, 42);
        expect(restored.title, 'Dune');
        expect(restored.author, 'Frank Herbert');
        expect(restored.category, 'Fiction');
        expect(restored.subGenre, 'Science Fiction');
        expect(restored.tags, ['sci-fi', 'classic']);
        expect(restored.description, 'Desert planet saga');
      });

      test('handles null optional fields', () {
        final ebook = _makeEbook();
        final map = ebook.toMap();
        final restored = LocalEbook.fromMap(map);

        expect(restored.author, isNull);
        expect(restored.coverPath, isNull);
        expect(restored.description, isNull);
        expect(restored.category, isNull);
        expect(restored.subGenre, isNull);
        expect(restored.tags, isEmpty);
      });

      test('tags serialize as comma-separated string', () {
        final ebook = _makeEbook(tags: ['a', 'b', 'c']);
        final map = ebook.toMap();
        expect(map['tags'], 'a,b,c');
      });
    });

    group('copyWith', () {
      test('creates updated copy with new fields', () {
        final original = _makeEbook(title: 'Old Title', author: 'Old Author');
        final updated = original.copyWith(title: 'New Title');

        expect(updated.title, 'New Title');
        expect(updated.author, 'Old Author'); // unchanged
        expect(updated.filePath, original.filePath); // unchanged
      });

      test('preserves all fields when no arguments given', () {
        final original = _makeEbook(
          id: 1,
          title: 'Title',
          author: 'Author',
          category: 'Fiction',
          tags: ['tag1'],
        );
        final copy = original.copyWith();

        expect(copy.id, original.id);
        expect(copy.title, original.title);
        expect(copy.author, original.author);
        expect(copy.category, original.category);
        expect(copy.tags, original.tags);
      });
    });

    group('computed properties', () {
      test('fileSizeFormatted shows KB for small files', () {
        final ebook = _makeEbook(fileSize: 512 * 1024); // 512 KB
        expect(ebook.fileSizeFormatted, '512.0 KB');
      });

      test('fileSizeFormatted shows MB for medium files', () {
        final ebook = _makeEbook(fileSize: 5 * 1024 * 1024); // 5 MB
        expect(ebook.fileSizeFormatted, '5.0 MB');
      });

      test('fileSizeFormatted shows GB for large files', () {
        final ebook = _makeEbook(fileSize: 2 * 1024 * 1024 * 1024); // 2 GB
        expect(ebook.fileSizeFormatted, '2.00 GB');
      });

      test('displayAuthor falls back to Unknown Author', () {
        expect(_makeEbook(author: null).displayAuthor, 'Unknown Author');
        expect(_makeEbook(author: '').displayAuthor, 'Unknown Author');
        expect(_makeEbook(author: 'Tolkien').displayAuthor, 'Tolkien');
      });

      test('displayCategory falls back to Uncategorized', () {
        expect(_makeEbook(category: null).displayCategory, 'Uncategorized');
        expect(_makeEbook(category: '').displayCategory, 'Uncategorized');
        expect(_makeEbook(category: 'Fiction').displayCategory, 'Fiction');
      });

      test('hasLocalPath detects valid vs blob paths', () {
        expect(_makeEbook(filePath: '/books/test.epub').hasLocalPath, isTrue);
        expect(_makeEbook(filePath: 'blob:http://...').hasLocalPath, isFalse);
        expect(_makeEbook(filePath: '').hasLocalPath, isFalse);
      });
    });

    group('isSupported', () {
      test('recognizes all supported formats', () {
        for (final fmt in ['epub', 'mobi', 'pdf', 'azw', 'azw3', 'fb2', 'djvu', 'cbz', 'cbr']) {
          expect(LocalEbook.isSupported(fmt), isTrue, reason: '$fmt should be supported');
        }
      });

      test('rejects unsupported formats', () {
        expect(LocalEbook.isSupported('txt'), isFalse);
        expect(LocalEbook.isSupported('doc'), isFalse);
        expect(LocalEbook.isSupported('zip'), isFalse);
      });

      test('is case-insensitive', () {
        expect(LocalEbook.isSupported('EPUB'), isTrue);
        expect(LocalEbook.isSupported('Pdf'), isTrue);
      });
    });
  });
}
