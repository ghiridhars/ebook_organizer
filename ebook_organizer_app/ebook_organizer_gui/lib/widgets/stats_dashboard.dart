import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';

class StatsDashboard extends StatelessWidget {
  const StatsDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LibraryProvider>(
      builder: (context, cloudProvider, _) {
        if (cloudProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final cloudStats = cloudProvider.stats;

        // Use cloud stats directly (already scoped by backend)
        // Don't merge with local stats to avoid duplication
        final totalBooks = cloudStats.totalBooks;
        final totalSizeMb = cloudStats.totalSizeMb;
        
        final byCategory = Map<String, int>.from(cloudStats.byCategory);
        final byFormat = Map<String, int>.from(cloudStats.byFormat);
        final byCloudProvider = Map<String, int>.from(cloudStats.byCloudProvider);

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
                          '$totalBooks',
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
                          '${totalSizeMb.toStringAsFixed(1)} MB',
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
            if (byCategory.isNotEmpty) ...[
              Text(
                'By Category',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: byCategory.entries.map((entry) {
                      return ListTile(
                        leading: const Icon(Icons.category),
                        title: Text(entry.key.isEmpty ? 'Uncategorized' : entry.key),
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
            if (byFormat.isNotEmpty) ...[
              Text(
                'By Format',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: byFormat.entries.map((entry) {
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

            // By Provider
            if (byCloudProvider.isNotEmpty) ...[
              Text(
                'By Storage',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: byCloudProvider.entries.map((entry) {
                      final isLocal = entry.key == 'Local Storage';
                      return ListTile(
                        leading: Icon(isLocal ? Icons.computer : Icons.cloud),
                        title: Text(_formatProviderName(entry.key)),
                        trailing: Chip(
                          label: Text('${entry.value}'),
                          backgroundColor: isLocal ? Theme.of(context).colorScheme.tertiaryContainer : null,
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
