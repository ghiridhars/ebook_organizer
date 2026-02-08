import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/ebook.dart';
import '../providers/ebook_provider.dart';

class EbookDetailScreen extends StatelessWidget {
  final Ebook ebook;

  const EbookDetailScreen({super.key, required this.ebook});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ebook Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              // TODO: Implement share
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cover placeholder
                Container(
                  width: 120,
                  height: 180,
                  decoration: BoxDecoration(
                    color: _getFormatColor(ebook.fileFormat).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getFormatColor(ebook.fileFormat).withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _getFormatIcon(ebook.fileFormat),
                        size: 48,
                        color: _getFormatColor(ebook.fileFormat),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ebook.fileFormat.toUpperCase(),
                        style: TextStyle(
                          color: _getFormatColor(ebook.fileFormat),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        ebook.title,
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        ebook.displayAuthor,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Colors.grey[700],
                            ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (ebook.category != null)
                            Chip(
                              avatar: Icon(
                                Icons.category,
                                size: 16,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              label: Text(ebook.category!),
                              backgroundColor: colorScheme.secondaryContainer,
                              labelStyle: TextStyle(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          if (ebook.subGenre != null)
                            Chip(
                              avatar: Icon(
                                Icons.label,
                                size: 16,
                                color: colorScheme.onTertiaryContainer,
                              ),
                              label: Text(ebook.subGenre!),
                              backgroundColor: colorScheme.tertiaryContainer,
                              labelStyle: TextStyle(
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          Chip(
                            avatar: const Icon(Icons.cloud, size: 16),
                            label: Text(ebook.cloudProvider),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Description
            if (ebook.description != null && ebook.description!.isNotEmpty) ...[
              Text(
                'Description',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                ebook.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),
            ],

            // Metadata Grid
            Text(
              'Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildDetailRow('Category', ebook.category),
                    _buildDetailRow('Sub-Genre', ebook.subGenre),
                    _buildDetailRow('Publisher', ebook.publisher),
                    _buildDetailRow('Published Date', ebook.publishedDate),
                    _buildDetailRow('ISBN', ebook.isbn),
                    _buildDetailRow('Language', ebook.language?.toUpperCase()),
                    _buildDetailRow('Pages', ebook.pageCount?.toString()),
                    _buildDetailRow('File Size', ebook.fileSizeFormatted),
                    _buildDetailRow('Sync Status', ebook.syncStatus),
                    _buildDetailRow('Last Synced', _formatDate(ebook.lastSynced)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
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
        return Icons.book;
      default:
        return Icons.description;
    }
  }

  Color _getFormatColor(String format) {
    switch (format.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'epub':
        return Colors.green;
      case 'mobi':
      case 'azw':
      case 'azw3':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }
}
