import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/models/library_stats.dart';

void main() {
  group('LibraryStats', () {
    group('fromJson', () {
      test('parses complete JSON', () {
        final json = {
          'total_books': 150,
          'by_category': {'Fiction': 80, 'Technology': 70},
          'by_format': {'epub': 100, 'pdf': 50},
          'by_cloud_provider': {'google_drive': 120, 'onedrive': 30},
          'total_size_mb': 2048.5,
          'last_sync': '2026-01-15T10:30:00.000',
        };

        final stats = LibraryStats.fromJson(json);
        expect(stats.totalBooks, 150);
        expect(stats.byCategory, {'Fiction': 80, 'Technology': 70});
        expect(stats.byFormat, {'epub': 100, 'pdf': 50});
        expect(stats.byCloudProvider, {'google_drive': 120, 'onedrive': 30});
        expect(stats.totalSizeMb, 2048.5);
        expect(stats.lastSync, DateTime(2026, 1, 15, 10, 30));
      });

      test('handles missing fields with defaults', () {
        final stats = LibraryStats.fromJson({});
        expect(stats.totalBooks, 0);
        expect(stats.byCategory, isEmpty);
        expect(stats.byFormat, isEmpty);
        expect(stats.byCloudProvider, isEmpty);
        expect(stats.totalSizeMb, 0.0);
        expect(stats.lastSync, isNull);
      });

      test('handles null last_sync', () {
        final stats = LibraryStats.fromJson({
          'total_books': 5,
          'last_sync': null,
        });
        expect(stats.lastSync, isNull);
      });

      test('converts total_size_mb int to double', () {
        final stats = LibraryStats.fromJson({
          'total_size_mb': 100,
        });
        expect(stats.totalSizeMb, 100.0);
        expect(stats.totalSizeMb, isA<double>());
      });
    });

    group('empty', () {
      test('creates zero-value stats', () {
        final stats = LibraryStats.empty();
        expect(stats.totalBooks, 0);
        expect(stats.byCategory, isEmpty);
        expect(stats.byFormat, isEmpty);
        expect(stats.byCloudProvider, isEmpty);
        expect(stats.totalSizeMb, 0.0);
        expect(stats.lastSync, isNull);
      });
    });
  });
}
