import 'dart:io';
import 'package:flutter/material.dart';
import '../models/local_ebook.dart';
import '../screens/local_ebook_detail_screen.dart';

/// Compact list item widget for list view mode
class LocalEbookListItem extends StatefulWidget {
  final LocalEbook ebook;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSecondaryTap;

  const LocalEbookListItem({
    super.key,
    required this.ebook,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
  });

  @override
  State<LocalEbookListItem> createState() => _LocalEbookListItemState();
}

class _LocalEbookListItemState extends State<LocalEbookListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ebook = widget.ebook;
    final colorScheme = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: _isHovered 
              ? colorScheme.surfaceVariant.withOpacity(0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Card(
          elevation: _isHovered ? 4 : 1,
          margin: EdgeInsets.zero,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap ?? () => _openDetailScreen(context),
            onDoubleTap: widget.onDoubleTap,
            onSecondaryTap: widget.onSecondaryTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  // Thumbnail
                  _buildThumbnail(ebook),
                  const SizedBox(width: 16),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ebook.title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          ebook.displayAuthor,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            // Category chip
                            if (ebook.category != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.secondaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  ebook.category!,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            // File size
                            Text(
                              ebook.fileSizeFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Format badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getFormatColor(ebook.fileFormat),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      ebook.fileFormat.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(LocalEbook ebook) {
    const double size = 56;
    
    if (ebook.coverPath != null && ebook.coverPath!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(ebook.coverPath!),
          width: size,
          height: size * 1.3,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildFormatIcon(ebook, size);
          },
        ),
      );
    }
    
    return _buildFormatIcon(ebook, size);
  }

  Widget _buildFormatIcon(LocalEbook ebook, double size) {
    return Container(
      width: size,
      height: size * 1.3,
      decoration: BoxDecoration(
        color: _getFormatColor(ebook.fileFormat).withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Icon(
          _getFormatIcon(ebook.fileFormat),
          size: 28,
          color: _getFormatColor(ebook.fileFormat),
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

/// List view for displaying local ebooks
class LocalEbookList extends StatelessWidget {
  final List<LocalEbook> ebooks;
  final Function(LocalEbook)? onEbookTap;
  final Function(LocalEbook)? onEbookDoubleTap;

  const LocalEbookList({
    super.key,
    required this.ebooks,
    this.onEbookTap,
    this.onEbookDoubleTap,
  });

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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: ebooks.length,
      itemBuilder: (context, index) {
        final ebook = ebooks[index];
        return LocalEbookListItem(
          ebook: ebook,
          onTap: onEbookTap != null ? () => onEbookTap!(ebook) : null,
          onDoubleTap: onEbookDoubleTap != null ? () => onEbookDoubleTap!(ebook) : null,
        );
      },
    );
  }
}
