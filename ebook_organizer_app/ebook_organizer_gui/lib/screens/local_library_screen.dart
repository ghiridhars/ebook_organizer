import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_library_provider.dart';
import '../models/local_ebook.dart';
import '../widgets/local_library_widget.dart';

/// Full-screen view for browsing local ebooks
class LocalLibraryView extends StatefulWidget {
  const LocalLibraryView({super.key});

  @override
  State<LocalLibraryView> createState() => _LocalLibraryViewState();
}

class _LocalLibraryViewState extends State<LocalLibraryView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalLibraryProvider>(
      builder: (context, provider, _) {
        // On web, show a different UI since directory scanning isn't supported
        if (kIsWeb && !provider.hasLibraryPath && provider.filteredEbooks.isEmpty) {
          return _WebSetupScreen(provider: provider);
        }
        
        // Show setup screen if no library path (desktop only)
        if (!kIsWeb && !provider.hasLibraryPath) {
          return _SetupScreen(provider: provider);
        }

        return Column(
          children: [
            // Toolbar
            _Toolbar(
              provider: provider,
              searchController: _searchController,
            ),
            // Content
            Expanded(
              child: provider.isScanning && provider.filteredEbooks.isEmpty
                  ? _ScanningView(provider: provider)
                  : LocalEbookGrid(ebooks: provider.filteredEbooks),
            ),
          ],
        );
      },
    );
  }
}

/// Web-specific setup screen
class _WebSetupScreen extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _WebSetupScreen({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.cloud_upload,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Web Browser Mode',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Upload your ebook files to manage them in the browser.\n'
              'Note: Data is stored in memory and will be lost on page refresh.\n'
              'For persistent local library, use the desktop app.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (provider.isUploading)
              const CircularProgressIndicator()
            else
              FilledButton.icon(
                onPressed: () async {
                  final count = await provider.uploadFiles();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(count > 0 
                          ? 'Successfully added $count ebook(s)!'
                          : 'No files were added'),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.upload_file),
                label: const Text('Upload Ebook Files'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              'Supported formats: EPUB, MOBI, PDF, AZW, AZW3, FB2, DJVU, CBZ, CBR',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupScreen extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _SetupScreen({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_books,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Set Up Your Local Library',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Choose a folder containing your ebook files.\n'
              'The app will scan and index all supported formats:\n'
              'EPUB, MOBI, PDF, AZW, AZW3, FB2, DJVU, CBZ, CBR',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                final selected = await provider.chooseLibraryFolder();
                if (selected && context.mounted) {
                  await provider.scanLibrary();
                }
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Library Folder'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
            const SizedBox(height: 48),
            // Features list
            _FeaturesList(),
          ],
        ),
      ),
    );
  }
}

class _FeaturesList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final features = [
      ('Offline Access', 'Manage your books without internet', Icons.wifi_off),
      ('Quick Search', 'Find any book instantly', Icons.search),
      ('Auto Organize', 'Index and categorize automatically', Icons.auto_awesome),
      ('Open with Default App', 'Read in your favorite reader', Icons.open_in_new),
    ];

    return Wrap(
      spacing: 32,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: features.map((f) => SizedBox(
        width: 180,
        child: Row(
          children: [
            Icon(f.$3, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.$1, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    f.$2,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      )).toList(),
    );
  }
}

class _Toolbar extends StatelessWidget {
  final LocalLibraryProvider provider;
  final TextEditingController searchController;

  const _Toolbar({
    required this.provider,
    required this.searchController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withOpacity(0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search bar
              Expanded(
                flex: 2,
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    hintText: 'Search local ebooks...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              searchController.clear();
                              provider.setSearchQuery('');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),
              const SizedBox(width: 16),
              // Format filter
              _FormatDropdown(provider: provider),
              const SizedBox(width: 8),
              // Author filter
              _AuthorDropdown(provider: provider),
              const SizedBox(width: 8),
              // Sort dropdown
              _SortDropdown(provider: provider),
              const SizedBox(width: 8),
              // Scan button
              IconButton.filled(
                onPressed: provider.isScanning ? null : () => provider.scanLibrary(),
                icon: provider.isScanning
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                tooltip: 'Rescan library',
              ),
              const SizedBox(width: 8),
              // Settings button
              IconButton(
                onPressed: () => _showSettingsDialog(context, provider),
                icon: const Icon(Icons.settings),
                tooltip: 'Library settings',
              ),
            ],
          ),
          // Stats row
          if (provider.stats != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '${provider.filteredEbooks.length} of ${provider.stats!.totalBooks} books',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(),
                Text(
                  provider.stats!.totalSizeFormatted,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(width: 16),
                Text(
                  'Last scan: ${provider.stats!.lastScanFormatted}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showSettingsDialog(BuildContext context, LocalLibraryProvider provider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Library Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Library Path'),
              subtitle: Text(
                provider.libraryPath ?? 'Not set',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.folder_open),
                onPressed: () async {
                  await provider.chooseLibraryFolder();
                  if (context.mounted) Navigator.pop(context);
                },
              ),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Rescan Library'),
              subtitle: const Text('Re-index all ebooks in the folder'),
              onTap: () {
                Navigator.pop(context);
                provider.scanLibrary();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep),
              title: const Text('Clear Index'),
              subtitle: const Text('Remove all books from index (files not deleted)'),
              onTap: () async {
                Navigator.pop(context);
                await provider.clearIndex();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _FormatDropdown extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _FormatDropdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: provider.selectedFormat,
      hint: const Text('All formats'),
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem(value: null, child: Text('All formats')),
        ...LocalEbook.supportedFormats.map(
          (f) => DropdownMenuItem(value: f, child: Text(f.toUpperCase())),
        ),
      ],
      onChanged: provider.setFormatFilter,
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _SortDropdown({required this.provider});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: provider.sortBy,
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(8),
      items: const [
        DropdownMenuItem(value: 'title', child: Text('Sort by Title')),
        DropdownMenuItem(value: 'author', child: Text('Sort by Author')),
        DropdownMenuItem(value: 'date_added', child: Text('Sort by Date Added')),
        DropdownMenuItem(value: 'file_size', child: Text('Sort by Size')),
        DropdownMenuItem(value: 'format', child: Text('Sort by Format')),
      ],
      onChanged: (value) => provider.setSortBy(value ?? 'title'),
    );
  }
}

class _AuthorDropdown extends StatefulWidget {
  final LocalLibraryProvider provider;

  const _AuthorDropdown({required this.provider});

  @override
  State<_AuthorDropdown> createState() => _AuthorDropdownState();
}

class _AuthorDropdownState extends State<_AuthorDropdown> {
  List<String> _authors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAuthors();
    // Listen to provider changes to reload authors after scanning
    widget.provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    // Reload authors when scanning completes
    if (!widget.provider.isScanning && !_loading) {
      _loadAuthors();
    }
  }

  Future<void> _loadAuthors() async {
    final authors = await widget.provider.getAuthors();
    if (mounted) {
      setState(() {
        _authors = authors;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 120,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_authors.isEmpty) {
      return const Text('No authors', style: TextStyle(color: Colors.grey));
    }

    // Ensure selected value is in the list, otherwise reset to null
    final selectedValue = widget.provider.selectedAuthor;
    final isValidSelection = selectedValue == null || _authors.contains(selectedValue);

    return DropdownButton<String?>(
      value: isValidSelection ? selectedValue : null,
      hint: const Text('All authors'),
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem(value: null, child: Text('All authors')),
        ..._authors.map(
          (a) => DropdownMenuItem(
            value: a,
            child: Text(
              a.length > 20 ? '${a.substring(0, 20)}...' : a,
            ),
          ),
        ),
      ],
      onChanged: (value) {
        widget.provider.setAuthorFilter(value);
        // Reload authors in case new ones were added
        _loadAuthors();
      },
    );
  }
}

class _ScanningView extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _ScanningView({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            'Scanning library...',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned ${provider.scanProgress} files, found ${provider.scanFound} ebooks',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
