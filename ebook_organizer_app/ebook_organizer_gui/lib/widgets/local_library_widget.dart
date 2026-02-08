import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_library_provider.dart';
import '../models/local_ebook.dart';
import '../screens/local_ebook_detail_screen.dart';

/// Widget displaying local library management UI
class LocalLibrarySection extends StatelessWidget {
  const LocalLibrarySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalLibraryProvider>(
      builder: (context, provider, _) {
        return Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.folder_special, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Local Library',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (provider.hasLibraryPath)
                      _StatusChip(
                        label: '${provider.stats?.totalBooks ?? 0} books',
                        color: Colors.blue,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Library path section
                _LibraryPathSection(provider: provider),
                
                if (provider.hasLibraryPath) ...[
                  const Divider(height: 32),
                  _LibraryStatsSection(provider: provider),
                  const SizedBox(height: 16),
                  _LibraryActionsSection(provider: provider),
                ],
                
                // Scan progress
                if (provider.isScanning) ...[
                  const SizedBox(height: 16),
                  _ScanProgressIndicator(provider: provider),
                ],
                
                // Error display
                if (provider.error != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: provider.error!),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LibraryPathSection extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _LibraryPathSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (!provider.hasLibraryPath) {
      return Column(
        children: [
          const Text(
            'No library folder selected. Choose a folder containing your ebook files to start organizing.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              final selected = await provider.chooseLibraryFolder();
              if (selected && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Library folder selected. Starting scan...')),
                );
                await provider.scanLibrary();
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Choose Library Folder'),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Library Path',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                provider.libraryPath!,
                style: const TextStyle(fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.folder_open),
          onPressed: () async {
            await provider.chooseLibraryFolder();
          },
          tooltip: 'Change folder',
        ),
      ],
    );
  }
}

class _LibraryStatsSection extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _LibraryStatsSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    final stats = provider.stats;
    if (stats == null) return const SizedBox.shrink();

    return Wrap(
      spacing: 24,
      runSpacing: 12,
      children: [
        _StatItem(
          icon: Icons.book,
          label: 'Total Books',
          value: '${stats.totalBooks}',
        ),
        _StatItem(
          icon: Icons.storage,
          label: 'Total Size',
          value: stats.totalSizeFormatted,
        ),
        _StatItem(
          icon: Icons.access_time,
          label: 'Last Scan',
          value: stats.lastScanFormatted,
        ),
        if (stats.formatCounts.isNotEmpty)
          _StatItem(
            icon: Icons.description,
            label: 'Formats',
            value: stats.formatCounts.keys.take(3).join(', '),
          ),
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }
}

class _LibraryActionsSection extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _LibraryActionsSection({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: provider.isScanning
              ? null
              : () async {
                  final result = await provider.scanLibrary();
                  if (context.mounted && result != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(result.summary)),
                    );
                  }
                },
          icon: provider.isScanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(provider.isScanning ? 'Scanning...' : 'Scan Now'),
        ),
        OutlinedButton.icon(
          onPressed: provider.isScanning
              ? null
              : () => _showClearConfirmation(context, provider),
          icon: const Icon(Icons.delete_sweep),
          label: const Text('Clear Index'),
        ),
      ],
    );
  }

  void _showClearConfirmation(BuildContext context, LocalLibraryProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Library Index?'),
        content: const Text(
          'This will remove all books from the index. Your files will not be deleted. '
          'You can scan the folder again to rebuild the index.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              provider.clearIndex();
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _ScanProgressIndicator extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _ScanProgressIndicator({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        Text(
          'Scanned ${provider.scanProgress} files, found ${provider.scanFound} ebooks...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid view for displaying local ebooks
class LocalEbookGrid extends StatelessWidget {
  final List<LocalEbook> ebooks;

  const LocalEbookGrid({super.key, required this.ebooks});

  @override
  Widget build(BuildContext context) {
    if (ebooks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No local ebooks found',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('Scan your library folder to see your ebooks here'),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: ebooks.length,
      itemBuilder: (context, index) {
        return LocalEbookCard(ebook: ebooks[index]);
      },
    );
  }
}

/// Card displaying a single local ebook with hover animations
class LocalEbookCard extends StatefulWidget {
  final LocalEbook ebook;

  const LocalEbookCard({super.key, required this.ebook});

  @override
  State<LocalEbookCard> createState() => _LocalEbookCardState();
}

class _LocalEbookCardState extends State<LocalEbookCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.read<LocalLibraryProvider>();
    final ebook = widget.ebook;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..scale(_isHovered ? 1.03 : 1.0),
        transformAlignment: Alignment.center,
        child: Card(
          clipBehavior: Clip.antiAlias,
          elevation: _isHovered ? 8 : 2,
          shadowColor: _isHovered 
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3) 
              : null,
          child: InkWell(
            onTap: () => _openDetailScreen(context),
            onDoubleTap: () => provider.openEbook(ebook),
            onSecondaryTap: () => _showContextMenu(context, provider),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Book cover
                Expanded(
                  flex: 3,
                  child: _buildCoverSection(ebook),
                ),
                // Book info
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ebook.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Category/SubGenre badges
                        if (ebook.category != null || ebook.subGenre != null)
                          Wrap(
                            spacing: 4,
                            runSpacing: 2,
                            children: [
                              if (ebook.category != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    ebook.category!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              if (ebook.subGenre != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    ebook.subGenre!,
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        const Spacer(),
                        Text(
                          ebook.displayAuthor,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          ebook.fileSizeFormatted,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCoverSection(LocalEbook ebook) {
    // If cover path exists, try to show the image
    if (ebook.coverPath != null && ebook.coverPath!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(ebook.coverPath!),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              // Fallback to format icon if image fails to load
              return _buildFormatPlaceholder(ebook);
            },
          ),
          // Format badge overlay
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _getFormatColor(ebook.fileFormat).withOpacity(0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                ebook.fileFormat.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // Default placeholder with format icon
    return _buildFormatPlaceholder(ebook);
  }

  Widget _buildFormatPlaceholder(LocalEbook ebook) {
    return Container(
      color: _getFormatColor(ebook.fileFormat).withOpacity(0.1),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _getFormatIcon(ebook.fileFormat),
              size: 48,
              color: _getFormatColor(ebook.fileFormat),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _getFormatColor(ebook.fileFormat),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                ebook.fileFormat.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetailScreen(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocalEbookDetailScreen(ebook: widget.ebook),
      ),
    );
  }

  void _showContextMenu(BuildContext context, LocalLibraryProvider provider) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                _openDetailScreen(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(context);
                provider.openEbook(widget.ebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Show in Folder'),
              onTap: () {
                Navigator.pop(context);
                provider.openContainingFolder(widget.ebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit Metadata'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(context, provider);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove from Index', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                provider.deleteFromIndex(widget.ebook.id!);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, LocalLibraryProvider provider) {
    final ebook = widget.ebook;
    final titleController = TextEditingController(text: ebook.title);
    final authorController = TextEditingController(text: ebook.author ?? '');
    final categoryController = TextEditingController(text: ebook.category ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Metadata'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: authorController,
              decoration: const InputDecoration(labelText: 'Author'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: categoryController,
              decoration: const InputDecoration(labelText: 'Category'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final updated = ebook.copyWith(
                title: titleController.text,
                author: authorController.text.isEmpty ? null : authorController.text,
                category: categoryController.text.isEmpty ? null : categoryController.text,
              );
              provider.updateEbook(updated);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
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
        return Icons.book;
      case 'cbz':
      case 'cbr':
        return Icons.collections_bookmark;
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
      case 'cbz':
      case 'cbr':
        return Colors.purple;
      default:
        return Colors.blue;
    }
  }
}
