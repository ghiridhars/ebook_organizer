import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/local_ebook.dart';
import '../providers/local_library_provider.dart';
import '../services/epub_metadata_service.dart';
import '../services/backend_metadata_service.dart';
import '../utils/platform_utils.dart' as platform;

/// Detail screen for viewing and editing local ebook information
class LocalEbookDetailScreen extends StatefulWidget {
  final LocalEbook ebook;

  const LocalEbookDetailScreen({super.key, required this.ebook});

  @override
  State<LocalEbookDetailScreen> createState() => _LocalEbookDetailScreenState();
}

class _LocalEbookDetailScreenState extends State<LocalEbookDetailScreen> {
  late LocalEbook _ebook;
  bool _isEditing = false;

  late TextEditingController _titleController;
  late TextEditingController _authorController;
  late TextEditingController _categoryController;
  late TextEditingController _descriptionController;
  late TextEditingController _tagsController;

  @override
  void initState() {
    super.initState();
    _ebook = widget.ebook;
    _initControllers();
  }

  void _initControllers() {
    _titleController = TextEditingController(text: _ebook.title);
    _authorController = TextEditingController(text: _ebook.author ?? '');
    _categoryController = TextEditingController(text: _ebook.category ?? '');
    _descriptionController = TextEditingController(text: _ebook.description ?? '');
    _tagsController = TextEditingController(text: _ebook.tags.join(', '));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _authorController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Ebook' : 'Ebook Details'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: 'Edit metadata',
            )
          else ...[
            TextButton(
              onPressed: _cancelEdit,
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: _saveChanges,
              child: const Text('Save'),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with cover and basic info
            _buildHeader(colorScheme),
            const SizedBox(height: 32),

            // Quick actions
            if (!_isEditing) ...[
              _buildQuickActions(),
              const SizedBox(height: 32),
            ],

            // Metadata section
            _buildMetadataSection(colorScheme),
            const SizedBox(height: 32),

            // File information section
            _buildFileInfoSection(colorScheme),

            if (!_isEditing) ...[
              const SizedBox(height: 32),
              // Danger zone
              _buildDangerZone(colorScheme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cover placeholder
        Container(
          width: 150,
          height: 220,
          decoration: BoxDecoration(
            color: _getFormatColor(_ebook.fileFormat).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getFormatColor(_ebook.fileFormat).withOpacity(0.3),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _getFormatIcon(_ebook.fileFormat),
                size: 64,
                color: _getFormatColor(_ebook.fileFormat),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: _getFormatColor(_ebook.fileFormat),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _ebook.fileFormat.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Basic info
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isEditing)
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                )
              else
                SelectableText(
                  _ebook.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const SizedBox(height: 8),
              if (_isEditing)
                TextField(
                  controller: _authorController,
                  decoration: const InputDecoration(
                    labelText: 'Author',
                    border: OutlineInputBorder(),
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(Icons.person, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      _ebook.displayAuthor,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              // Tags/chips row
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChip(
                    icon: Icons.description,
                    label: _ebook.fileFormat.toUpperCase(),
                    color: _getFormatColor(_ebook.fileFormat),
                  ),
                  _buildChip(
                    icon: Icons.folder,
                    label: _ebook.displayCategory,
                    color: colorScheme.secondary,
                  ),
                  _buildChip(
                    icon: Icons.storage,
                    label: _ebook.fileSizeFormatted,
                    color: colorScheme.tertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    final provider = context.read<LocalLibraryProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: () => provider.openEbook(_ebook),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Open'),
                ),
                OutlinedButton.icon(
                  onPressed: () => provider.openContainingFolder(_ebook),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Show in Folder'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _copyPath(),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy Path'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataSection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Metadata',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isEditing) ...[
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  hintText: 'e.g., Fiction, Science, History',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                  hintText: 'Add a description...',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags',
                  border: OutlineInputBorder(),
                  hintText: 'Comma-separated tags',
                ),
              ),
            ] else ...[
              _buildInfoRow('Category', _ebook.displayCategory),
              _buildInfoRow(
                'Description',
                _ebook.description?.isNotEmpty == true
                    ? _ebook.description!
                    : 'No description',
              ),
              _buildInfoRow(
                'Tags',
                _ebook.tags.isNotEmpty ? _ebook.tags.join(', ') : 'No tags',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileInfoSection(ColorScheme colorScheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insert_drive_file, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'File Information',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('File Name', _ebook.fileName),
            _buildInfoRow('File Path', _ebook.filePath, selectable: true),
            _buildInfoRow('Format', _ebook.fileFormat.toUpperCase()),
            _buildInfoRow('Size', _ebook.fileSizeFormatted),
            _buildInfoRow('Modified', _formatDate(_ebook.modifiedDate)),
            _buildInfoRow('Indexed', _formatDate(_ebook.indexedAt)),
            if (!kIsWeb) _buildFileExistsRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildFileExistsRow() {
    return FutureBuilder<bool>(
      future: platform.fileExists(_ebook.filePath),
      builder: (context, snapshot) {
        final exists = snapshot.data ?? false;
        final loading = snapshot.connectionState == ConnectionState.waiting;
        
        return _buildInfoRow(
          'File Exists',
          loading ? 'Checking...' : (exists ? 'Yes' : 'No (file may have been moved or deleted)'),
          valueColor: loading ? Colors.grey : (exists ? Colors.green : Colors.red),
        );
      },
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    bool selectable = false,
    Color? valueColor,
  }) {
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
            child: selectable
                ? SelectableText(
                    value,
                    style: TextStyle(color: valueColor),
                  )
                : Text(
                    value,
                    style: TextStyle(color: valueColor),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDangerZone(ColorScheme colorScheme) {
    return Card(
      color: Colors.red.withOpacity(0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.red),
                const SizedBox(width: 8),
                Text(
                  'Danger Zone',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Removing from index will not delete the actual file. '
              'You can re-scan your library to add it back.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _removeFromIndex,
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('Remove from Index'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _cancelEdit() {
    setState(() {
      _isEditing = false;
      _initControllers();
    });
  }

  Future<void> _saveChanges() async {
    final provider = context.read<LocalLibraryProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final updatedEbook = _ebook.copyWith(
      title: _titleController.text.trim(),
      author: _authorController.text.trim().isEmpty ? null : _authorController.text.trim(),
      category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      tags: _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList(),
    );

    // Determine format and offer appropriate metadata update options
    final format = _ebook.fileFormat.toLowerCase();
    bool fileUpdated = false;
    
    // File writing is not supported on web
    if (!kIsWeb && EpubMetadataService.isEpub(_ebook.filePath)) {
      // EPUB: Use native Dart implementation
      final shouldUpdateFile = await _showUpdateFileDialog(format: 'EPUB');
      if (shouldUpdateFile == true) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Updating EPUB metadata...')),
          );
        }

        final epubMetadata = EpubMetadata(
          title: updatedEbook.title,
          creator: updatedEbook.author,
          description: updatedEbook.description,
          subjects: updatedEbook.tags,
        );

        fileUpdated = await EpubMetadataService.instance.writeMetadata(
          _ebook.filePath,
          epubMetadata,
        );

        if (mounted) {
          scaffoldMessenger.hideCurrentSnackBar();
        }
      }
    } else if (!kIsWeb && format == 'pdf') {
      // PDF: Use Python backend
      final backendAvailable = await backendMetadataService.isBackendAvailable();
      
      if (backendAvailable) {
        final shouldUpdateFile = await _showUpdateFileDialog(format: 'PDF');
        if (shouldUpdateFile == true) {
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('Updating PDF metadata via backend...')),
            );
          }

          fileUpdated = await backendMetadataService.writeMetadata(
            _ebook.filePath,
            title: updatedEbook.title,
            author: updatedEbook.author,
            description: updatedEbook.description,
            subjects: updatedEbook.tags,
          );

          if (mounted) {
            scaffoldMessenger.hideCurrentSnackBar();
          }
        }
      } else {
        // Backend not available, inform user
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Backend not available. PDF metadata editing requires the Python backend running.'),
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } else if (format == 'mobi' || format == 'azw' || format == 'azw3') {
      // MOBI: Read-only format
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('MOBI format is read-only (proprietary format). Index will be updated.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    }

    // Update index database
    await provider.updateEbook(updatedEbook);

    if (mounted) {
      setState(() {
        _ebook = updatedEbook;
        _isEditing = false;
      });
      
      final format = _ebook.fileFormat.toLowerCase();
      String message;
      
      // On web, we can only update the index
      if (kIsWeb) {
        message = 'Metadata updated in index';
      } else if (EpubMetadataService.isEpub(_ebook.filePath) || format == 'pdf') {
        if (fileUpdated) {
          message = 'Metadata updated in index and ${format.toUpperCase()} file';
        } else {
          message = 'Metadata updated in index only';
        }
      } else if (format == 'mobi' || format == 'azw' || format == 'azw3') {
        message = 'Metadata updated in index (MOBI format is read-only)';
      } else {
        message = 'Metadata updated in index';
      }
      
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<bool?> _showUpdateFileDialog({required String format}) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update $format File?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is a $format file. Would you like to update the metadata inside the actual file?',
            ),
            const SizedBox(height: 16),
            const Text(
              'Note: A backup will be created during the update process.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Index Only'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Update File'),
          ),
        ],
      ),
    );
  }

  void _copyPath() {
    Clipboard.setData(ClipboardData(text: _ebook.filePath));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Path copied to clipboard')),
    );
  }

  void _removeFromIndex() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove from Index?'),
        content: Text(
          'This will remove "${_ebook.title}" from your library index. '
          'The file will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final provider = context.read<LocalLibraryProvider>();
              await provider.deleteFromIndex(_ebook.id!);
              if (mounted) {
                Navigator.pop(context);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
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
