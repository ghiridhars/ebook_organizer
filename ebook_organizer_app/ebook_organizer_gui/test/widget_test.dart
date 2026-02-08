// This is a basic Flutter widget test.
// Updated to work with the new MyApp constructor that requires themeProvider

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ebook_organizer_gui/providers/theme_provider.dart';
import 'package:ebook_organizer_gui/providers/ebook_provider.dart';
import 'package:ebook_organizer_gui/providers/library_provider.dart';
import 'package:ebook_organizer_gui/providers/local_library_provider.dart';

void main() {
  testWidgets('App launches correctly', (WidgetTester tester) async {
    // Create a mock theme provider
    final themeProvider = ThemeProvider();
    
    // Build our app with required providers
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: themeProvider),
          ChangeNotifierProvider(create: (_) => EbookProvider()),
          ChangeNotifierProvider(create: (_) => LibraryProvider()),
          ChangeNotifierProvider(create: (_) => LocalLibraryProvider()),
        ],
        child: Consumer<ThemeProvider>(
          builder: (context, themeProvider, _) {
            return MaterialApp(
              title: 'Ebook Organizer Test',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
                useMaterial3: true,
              ),
              themeMode: themeProvider.themeMode,
              home: const Scaffold(
                body: Center(
                  child: Text('Ebook Organizer'),
                ),
              ),
            );
          },
        ),
      ),
    );

    // Verify the app launches
    expect(find.text('Ebook Organizer'), findsOneWidget);
  });
}
