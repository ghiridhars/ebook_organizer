import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/local_ebook.dart';
import '../providers/local_library_provider.dart';
import '../services/epub_metadata_service.dart';
import '../services/backend_metadata_service.dart';
import '../services/conversion_service.dart';
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
    final provider = context.read<LocalLibraryProvider>();

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
        padding: const EdgeInsets.only(left: 24, right: 24, top: 24, bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with cover and basic info
            _buildHeader(colorScheme),
            const SizedBox(height: 32),

            // Legacy Quick actions card (for reference before bottom bar)
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
      // Floating quick actions bar at bottom
      bottomNavigationBar: _isEditing 
          ? null 
          : _buildFloatingActionsBar(context, provider, colorScheme),
    );
  }

  Widget _buildFloatingActionsBar(
    BuildContext context, 
    LocalLibraryProvider provider,
    ColorScheme colorScheme,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                icon: Icons.open_in_new,
                label: 'Open',
                color: colorScheme.primary,
                filled: true,
                onTap: () => provider.openEbook(_ebook),
              ),
              _buildActionButton(
                icon: Icons.edit,
                label: 'Edit',
                color: colorScheme.secondary,
                onTap: () => setState(() => _isEditing = true),
              ),
              // Convert to EPUB button - only for MOBI/AZW files
              if (conversionService.canConvertToEpub(_ebook.fileFormat))
                _buildActionButton(
                  icon: Icons.transform,
                  label: 'EPUB',
                  color: Colors.green,
                  onTap: _convertToEpub,
                ),
              _buildActionButton(
                icon: Icons.folder_open,
                label: 'Folder',
                color: colorScheme.tertiary,
                onTap: () => provider.openContainingFolder(_ebook),
              ),
              _buildActionButton(
                icon: Icons.copy,
                label: 'Copy',
                color: colorScheme.outline,
                onTap: _copyPath,
              ),
              _buildActionButton(
                icon: Icons.delete_outline,
                label: 'Remove',
                color: Colors.red,
                onTap: _removeFromIndex,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool filled = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: filled ? color : color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 22,
                color: filled ? Colors.white : color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
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
      String? pdfWriteError;
      print('[SaveChanges] PDF file detected: ${_ebook.filePath}');
      final backendAvailable = await backendMetadataService.isBackendAvailable();
      print('[SaveChanges] Backend available: $backendAvailable');
      
      if (backendAvailable) {
        final shouldUpdateFile = await _showUpdateFileDialog(format: 'PDF');
        print('[SaveChanges] User chose to update PDF file: $shouldUpdateFile');
        if (shouldUpdateFile == true) {
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('Updating PDF metadata via backend...')),
            );
          }

          print('[SaveChanges] Calling backendMetadataService.writeMetadata with:');
          print('[SaveChanges]   title: ${updatedEbook.title}');
          print('[SaveChanges]   author: ${updatedEbook.author}');
          print('[SaveChanges]   description: ${updatedEbook.description}');
          print('[SaveChanges]   tags: ${updatedEbook.tags}');
          
          final result = await backendMetadataService.writeMetadata(
            _ebook.filePath,
            title: updatedEbook.title,
            author: updatedEbook.author,
            description: updatedEbook.description,
            subjects: updatedEbook.tags,
          );
          fileUpdated = result.success;
          pdfWriteError = result.error;

          print('[SaveChanges] PDF file metadata write result: $fileUpdated, error: $pdfWriteError');

          if (mounted) {
            scaffoldMessenger.hideCurrentSnackBar();
            if (!fileUpdated && pdfWriteError != null) {
              scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Text('PDF file update failed: $pdfWriteError'),
                  duration: const Duration(seconds: 6),
                  backgroundColor: Colors.red[700],
                ),
              );
            }
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

  Future<void> _convertToEpub() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final provider = context.read<LocalLibraryProvider>();
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Convert to EPUB?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Convert "${_ebook.title}" to EPUB format?'),
            const SizedBox(height: 12),
            const Text(
              'The EPUB file will be created in the same folder as the original file.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    
    if (confirmed != true || !mounted) return;
    
    // Show progress indicator
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Converting to EPUB...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );
    
    // Call conversion service
    final result = await conversionService.convertMobiToEpub(_ebook.filePath);
    
    if (!mounted) return;
    scaffoldMessenger.hideCurrentSnackBar();
    
    if (result['success'] == true) {
      final outputPath = result['output_path'] as String?;
      
      // Ask if user wants to add to library
      final addToLibrary = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
          title: const Text('Conversion Complete!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('EPUB file created successfully.'),
              if (outputPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  outputPath.split(RegExp(r'[/\\]')).last,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 16),
              const Text('Would you like to add the new EPUB to your library?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Add to Library'),
            ),
          ],
        ),
      );
      
      if (addToLibrary == true && outputPath != null && mounted) {
        // Trigger a rescan to pick up the new file
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('EPUB added. Rescan your library to see it.')),
        );
      }
    } else {
      // Show error
      final error = result['error'] ?? 'Unknown error';
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Conversion failed: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
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
