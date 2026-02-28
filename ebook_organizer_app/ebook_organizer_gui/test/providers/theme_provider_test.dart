import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ebook_organizer_gui/providers/theme_provider.dart';

void main() {
  group('ThemeProvider', () {
    late ThemeProvider provider;

    setUp(() {
      provider = ThemeProvider();
    });

    test('defaults to system theme mode', () {
      expect(provider.themeMode, ThemeMode.system);
    });

    test('is not initialized by default', () {
      expect(provider.initialized, false);
    });

    group('boolean getters', () {
      test('isDarkMode is false by default', () {
        expect(provider.isDarkMode, false);
      });

      test('isLightMode is false by default', () {
        expect(provider.isLightMode, false);
      });

      test('isSystemMode is true by default', () {
        expect(provider.isSystemMode, true);
      });
    });

    group('setThemeMode (without SharedPreferences)', () {
      test('changes theme mode and notifies listeners', () async {
        var notified = false;
        provider.addListener(() => notified = true);

        await provider.setThemeMode(ThemeMode.dark);
        expect(provider.themeMode, ThemeMode.dark);
        expect(provider.isDarkMode, true);
        expect(provider.isLightMode, false);
        expect(provider.isSystemMode, false);
        expect(notified, true);
      });

      test('does not notify if same mode', () async {
        var notifyCount = 0;
        provider.addListener(() => notifyCount++);

        await provider.setThemeMode(ThemeMode.system); // already system
        expect(notifyCount, 0);
      });
    });

    group('toggleTheme', () {
      test('toggles from system to dark', () async {
        // system is default, toggle goes to dark (not light → dark)
        await provider.toggleTheme();
        expect(provider.themeMode, ThemeMode.dark);
      });

      test('toggles from dark to light', () async {
        await provider.setThemeMode(ThemeMode.dark);
        await provider.toggleTheme();
        expect(provider.themeMode, ThemeMode.light);
      });

      test('toggles from light to dark', () async {
        await provider.setThemeMode(ThemeMode.light);
        await provider.toggleTheme();
        expect(provider.themeMode, ThemeMode.dark);
      });
    });

    group('cycleThemeMode', () {
      test('cycles system → light → dark → system', () async {
        expect(provider.themeMode, ThemeMode.system);

        await provider.cycleThemeMode();
        expect(provider.themeMode, ThemeMode.light);

        await provider.cycleThemeMode();
        expect(provider.themeMode, ThemeMode.dark);

        await provider.cycleThemeMode();
        expect(provider.themeMode, ThemeMode.system);
      });
    });

    group('themeModeIcon', () {
      test('returns correct icon for each mode', () async {
        expect(provider.themeModeIcon, Icons.brightness_auto);

        await provider.setThemeMode(ThemeMode.light);
        expect(provider.themeModeIcon, Icons.light_mode);

        await provider.setThemeMode(ThemeMode.dark);
        expect(provider.themeModeIcon, Icons.dark_mode);
      });
    });

    group('themeModeLabel', () {
      test('returns correct label for each mode', () async {
        expect(provider.themeModeLabel, 'System');

        await provider.setThemeMode(ThemeMode.light);
        expect(provider.themeModeLabel, 'Light');

        await provider.setThemeMode(ThemeMode.dark);
        expect(provider.themeModeLabel, 'Dark');
      });
    });
  });
}
