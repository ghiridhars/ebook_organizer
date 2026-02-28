import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/models/cloud_provider.dart';

void main() {
  group('CloudProvider', () {
    group('fromJson', () {
      test('parses full JSON', () {
        final json = {
          'provider': 'google_drive',
          'is_enabled': true,
          'is_authenticated': true,
          'last_sync': '2026-01-15T10:30:00.000',
          'folder_path': '/My Drive/eBooks',
        };

        final cp = CloudProvider.fromJson(json);
        expect(cp.provider, 'google_drive');
        expect(cp.isEnabled, true);
        expect(cp.isAuthenticated, true);
        expect(cp.lastSync, DateTime(2026, 1, 15, 10, 30));
        expect(cp.folderPath, '/My Drive/eBooks');
      });

      test('handles missing fields with defaults', () {
        final cp = CloudProvider.fromJson({});
        expect(cp.provider, '');
        expect(cp.isEnabled, false);
        expect(cp.isAuthenticated, false);
        expect(cp.lastSync, isNull);
        expect(cp.folderPath, isNull);
      });
    });

    group('displayName', () {
      test('returns Google Drive for google_drive', () {
        final cp = CloudProvider(
          provider: 'google_drive',
          isEnabled: true,
          isAuthenticated: false,
        );
        expect(cp.displayName, 'Google Drive');
      });

      test('returns OneDrive for onedrive', () {
        final cp = CloudProvider(
          provider: 'onedrive',
          isEnabled: true,
          isAuthenticated: false,
        );
        expect(cp.displayName, 'OneDrive');
      });

      test('returns raw provider string for unknown', () {
        final cp = CloudProvider(
          provider: 'dropbox',
          isEnabled: true,
          isAuthenticated: false,
        );
        expect(cp.displayName, 'dropbox');
      });
    });

    group('statusText', () {
      test('returns Disabled when not enabled', () {
        final cp = CloudProvider(
          provider: 'google_drive',
          isEnabled: false,
          isAuthenticated: false,
        );
        expect(cp.statusText, 'Disabled');
      });

      test('returns Not Connected when enabled but not authenticated', () {
        final cp = CloudProvider(
          provider: 'google_drive',
          isEnabled: true,
          isAuthenticated: false,
        );
        expect(cp.statusText, 'Not Connected');
      });

      test('returns Connected when enabled and authenticated', () {
        final cp = CloudProvider(
          provider: 'google_drive',
          isEnabled: true,
          isAuthenticated: true,
        );
        expect(cp.statusText, 'Connected');
      });
    });

    group('copyWith', () {
      test('creates copy with updated fields', () {
        final original = CloudProvider(
          provider: 'google_drive',
          isEnabled: false,
          isAuthenticated: false,
        );

        final copy = original.copyWith(isEnabled: true, isAuthenticated: true);
        expect(copy.provider, 'google_drive');
        expect(copy.isEnabled, true);
        expect(copy.isAuthenticated, true);
      });

      test('preserves fields when not specified', () {
        final original = CloudProvider(
          provider: 'onedrive',
          isEnabled: true,
          isAuthenticated: true,
          folderPath: '/Books',
        );

        final copy = original.copyWith();
        expect(copy.provider, 'onedrive');
        expect(copy.isEnabled, true);
        expect(copy.isAuthenticated, true);
        expect(copy.folderPath, '/Books');
      });
    });
  });
}
