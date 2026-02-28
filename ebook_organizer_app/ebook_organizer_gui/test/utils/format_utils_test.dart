import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/utils/format_utils.dart';

void main() {
  group('getFormatIcon', () {
    test('returns correct icon for each supported format', () {
      expect(getFormatIcon('pdf'), Icons.picture_as_pdf);
      expect(getFormatIcon('epub'), Icons.menu_book);
      expect(getFormatIcon('mobi'), Icons.book);
      expect(getFormatIcon('azw'), Icons.book);
      expect(getFormatIcon('azw3'), Icons.book);
      expect(getFormatIcon('cbz'), Icons.collections_bookmark);
      expect(getFormatIcon('cbr'), Icons.collections_bookmark);
      expect(getFormatIcon('fb2'), Icons.article);
      expect(getFormatIcon('djvu'), Icons.document_scanner);
    });

    test('returns default icon for unknown format', () {
      expect(getFormatIcon('txt'), Icons.description);
      expect(getFormatIcon('doc'), Icons.description);
      expect(getFormatIcon('unknown'), Icons.description);
    });

    test('is case-insensitive', () {
      expect(getFormatIcon('PDF'), Icons.picture_as_pdf);
      expect(getFormatIcon('Epub'), Icons.menu_book);
      expect(getFormatIcon('MOBI'), Icons.book);
    });
  });

  group('getFormatColor', () {
    test('returns correct color for each supported format', () {
      expect(getFormatColor('pdf'), Colors.red);
      expect(getFormatColor('epub'), Colors.green);
      expect(getFormatColor('mobi'), Colors.orange);
      expect(getFormatColor('azw'), Colors.orange);
      expect(getFormatColor('azw3'), Colors.orange);
      expect(getFormatColor('cbz'), Colors.purple);
      expect(getFormatColor('cbr'), Colors.purple);
      expect(getFormatColor('fb2'), Colors.teal);
      expect(getFormatColor('djvu'), Colors.indigo);
    });

    test('returns default color for unknown format', () {
      expect(getFormatColor('txt'), Colors.blue);
      expect(getFormatColor('unknown'), Colors.blue);
    });

    test('is case-insensitive', () {
      expect(getFormatColor('PDF'), Colors.red);
      expect(getFormatColor('Epub'), Colors.green);
    });
  });
}
