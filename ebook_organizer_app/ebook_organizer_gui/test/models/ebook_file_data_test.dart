import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/models/ebook_file_data.dart';

void main() {
  group('EbookFileData', () {
    test('stores all fields correctly', () {
      final date = DateTime(2026, 1, 15);
      final data = EbookFileData(
        fileName: 'test.epub',
        filePath: '/books/test.epub',
        fileSize: 2048,
        modifiedDate: date,
        bytes: [0x50, 0x4B],
      );

      expect(data.fileName, 'test.epub');
      expect(data.filePath, '/books/test.epub');
      expect(data.fileSize, 2048);
      expect(data.modifiedDate, date);
      expect(data.bytes, [0x50, 0x4B]);
    });

    test('bytes defaults to null', () {
      final data = EbookFileData(
        fileName: 'test.pdf',
        filePath: '/test.pdf',
        fileSize: 1024,
        modifiedDate: DateTime.now(),
      );
      expect(data.bytes, isNull);
    });

    group('extension', () {
      test('extracts extension from filename', () {
        final data = EbookFileData(
          fileName: 'book.epub',
          filePath: '/book.epub',
          fileSize: 100,
          modifiedDate: DateTime.now(),
        );
        expect(data.extension, 'epub');
      });

      test('returns lowercase extension', () {
        final data = EbookFileData(
          fileName: 'Report.PDF',
          filePath: '/Report.PDF',
          fileSize: 100,
          modifiedDate: DateTime.now(),
        );
        expect(data.extension, 'pdf');
      });

      test('handles multiple dots in filename', () {
        final data = EbookFileData(
          fileName: 'my.great.book.mobi',
          filePath: '/my.great.book.mobi',
          fileSize: 100,
          modifiedDate: DateTime.now(),
        );
        expect(data.extension, 'mobi');
      });

      test('returns empty string for no extension', () {
        final data = EbookFileData(
          fileName: 'noextension',
          filePath: '/noextension',
          fileSize: 100,
          modifiedDate: DateTime.now(),
        );
        expect(data.extension, '');
      });
    });
  });
}
