import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';

class StatsDashboard extends StatelessWidget {
  const StatsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final stats = provider.stats;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total books card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.library_books,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Books',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${stats.totalBooks}',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Total Size',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        Text(
                          '${stats.totalSizeMb.toStringAsFixed(1)} MB',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // By Category
            if (stats.byCategory.isNotEmpty) ...[
              Text(
                'By Category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: stats.byCategory.entries.map((entry) {
                      return ListTile(
                        leading: const Icon(Icons.category),
                        title: Text(entry.key),
                        trailing: Chip(
                          label: Text('${entry.value}'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // By Format
            if (stats.byFormat.isNotEmpty) ...[
              Text(
                'By Format',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: stats.byFormat.entries.map((entry) {
                      return ListTile(
                        leading: Icon(_getFormatIcon(entry.key)),
                        title: Text(entry.key.toUpperCase()),
                        trailing: Chip(
                          label: Text('${entry.value}'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // By Cloud Provider
            if (stats.byCloudProvider.isNotEmpty) ...[
              Text(
                'By Cloud Provider',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: stats.byCloudProvider.entries.map((entry) {
                      return ListTile(
                        leading: const Icon(Icons.cloud),
                        title: Text(_formatProviderName(entry.key)),
                        trailing: Chip(
                          label: Text('${entry.value}'),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  IconData _getFormatIcon(String format) {
    switch (format.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'epub':
        return Icons.menu_book;
      case 'mobi':
      case 'azw':
      case 'azw3':
        return Icons.import_contacts;
      default:
        return Icons.book;
    }
  }

  String _formatProviderName(String provider) {
    switch (provider) {
      case 'google_drive':
        return 'Google Drive';
      case 'onedrive':
        return 'OneDrive';
      default:
        return provider;
    }
  }
}
