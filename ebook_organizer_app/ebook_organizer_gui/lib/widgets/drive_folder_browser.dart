import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// A breadcrumb entry representing a folder in the navigation path
class _BreadcrumbEntry {
  final String id;
  final String name;

  const _BreadcrumbEntry({required this.id, required this.name});
}

/// Widget for browsing cloud folders (Google Drive / OneDrive) and selecting one for sync
class CloudFolderBrowser extends StatefulWidget {
  /// Cloud provider identifier ('google_drive' or 'onedrive')
  final String provider;
  final void Function(String folderId, String folderPath) onFolderSelected;

  const CloudFolderBrowser({
    super.key,
    required this.provider,
    required this.onFolderSelected,
  });

  @override
  State<CloudFolderBrowser> createState() => _CloudFolderBrowserState();
}

class _CloudFolderBrowserState extends State<CloudFolderBrowser> {
  final ApiService _apiService = ApiService();

  List<Map<String, dynamic>> _folders = [];
  bool _isLoading = false;
  String? _error;

  String get _rootLabel =>
      widget.provider == 'onedrive' ? 'OneDrive' : 'My Drive';

  // Navigation breadcrumb path
  late List<_BreadcrumbEntry> _breadcrumbs = [
    _BreadcrumbEntry(id: 'root', name: _rootLabel),
  ];

  String get _currentFolderId => _breadcrumbs.last.id;

  String get _currentPath =>
      _breadcrumbs.map((b) => b.name).join(' / ');

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _folders = await _apiService.listCloudFolders(widget.provider, parentId: _currentFolderId);
    } catch (e) {
      _error = 'Failed to load folders: $e';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToFolder(String folderId, String folderName) {
    setState(() {
      _breadcrumbs = [
        ..._breadcrumbs,
        _BreadcrumbEntry(id: folderId, name: folderName),
      ];
    });
    _loadFolders();
  }

  void _navigateToBreadcrumb(int index) {
    if (index >= _breadcrumbs.length - 1) return;
    setState(() {
      _breadcrumbs = _breadcrumbs.sublist(0, index + 1);
    });
    _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.folder_open, color: theme.colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(
                    'Select a ${_rootLabel} Folder',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the folder containing your ebooks to sync.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Breadcrumb path bar
              _buildBreadcrumbs(theme),
              const SizedBox(height: 12),

              // Folder list
              Flexible(child: _buildFolderList(theme)),

              const SizedBox(height: 16),

              // Select button
              FilledButton.icon(
                onPressed: () {
                  widget.onFolderSelected(_currentFolderId, _currentPath);
                },
                icon: const Icon(Icons.check),
                label: Text('Select "${ _breadcrumbs.last.name }"'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _breadcrumbs.length; i++) ...[
              if (i > 0)
                Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
              InkWell(
                onTap: i < _breadcrumbs.length - 1
                    ? () => _navigateToBreadcrumb(i)
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _breadcrumbs[i].name,
                    style: TextStyle(
                      fontWeight: i == _breadcrumbs.length - 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: i < _breadcrumbs.length - 1
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFolderList(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _loadFolders,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_folders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'No subfolders found',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'You can select this folder or navigate back.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _folders.length,
      itemBuilder: (context, index) {
        final folder = _folders[index];
        final name = folder['name'] as String? ?? 'Untitled';
        final id = folder['id'] as String? ?? '';

        return ListTile(
          leading: Icon(
            Icons.folder,
            color: widget.provider == 'onedrive'
                ? const Color(0xFF0078D4) // OneDrive blue
                : const Color(0xFFFBBC04), // Google Drive yellow
          ),
          title: Text(name),
          trailing: const Icon(Icons.chevron_right),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          onTap: () => _navigateToFolder(id, name),
        );
      },
    );
  }
}

/// Backward-compatible alias
class DriveFolderBrowser extends StatelessWidget {
  final void Function(String folderId, String folderPath) onFolderSelected;

  const DriveFolderBrowser({super.key, required this.onFolderSelected});

  @override
  Widget build(BuildContext context) {
    return CloudFolderBrowser(
      provider: 'google_drive',
      onFolderSelected: onFolderSelected,
    );
  }
}
