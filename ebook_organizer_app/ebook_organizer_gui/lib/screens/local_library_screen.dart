import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_library_provider.dart';
import '../models/local_ebook.dart';
import '../widgets/local_library_widget.dart';
import '../widgets/local_ebook_list_item.dart';
import '../widgets/active_filters_bar.dart';
import '../widgets/skeleton_widgets.dart';
import '../services/api_service.dart';

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
            // Active filters bar
            const ActiveFiltersBar(),
            // Content
            Expanded(
              child: _buildContent(provider),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildContent(LocalLibraryProvider provider) {
    // Show skeleton loading during initial load
    if (provider.isLoading && provider.filteredEbooks.isEmpty) {
      return provider.isGridView 
          ? const SkeletonBookGrid() 
          : const SkeletonBookList();
    }
    
    // Show scanning progress with skeleton
    if (provider.isScanning && provider.filteredEbooks.isEmpty) {
      return Stack(
        children: [
          provider.isGridView 
              ? const SkeletonBookGrid() 
              : const SkeletonBookList(),
          Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Scanning library...',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Found ${provider.scanFound} ebooks (${provider.scanProgress} files scanned)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // Show grid or list view based on preference
    if (provider.isGridView) {
      return LocalEbookGrid(ebooks: provider.filteredEbooks);
    } else {
      return LocalEbookList(
        ebooks: provider.filteredEbooks,
        onEbookDoubleTap: (ebook) => provider.openEbook(ebook),
      );
    }
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
              // Category filter
              _CategoryDropdown(provider: provider),
              const SizedBox(width: 8),
              // Author filter
              _AuthorDropdown(provider: provider),
              const SizedBox(width: 8),
              // Sort dropdown
              _SortDropdown(provider: provider),
              const SizedBox(width: 8),
              // View mode toggle
              IconButton(
                onPressed: () => provider.toggleViewMode(),
                icon: Icon(
                  provider.isGridView ? Icons.view_list : Icons.grid_view,
                ),
                tooltip: provider.isGridView ? 'Switch to list view' : 'Switch to grid view',
              ),
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
              // Auto-classify button
              IconButton(
                onPressed: () => _showAutoClassifyDialog(context, provider),
                icon: const Icon(Icons.auto_awesome),
                tooltip: 'Auto-classify books',
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

  void _showAutoClassifyDialog(BuildContext context, LocalLibraryProvider provider) async {
    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => _AutoClassifyDialog(provider: provider),
    );
    
    // Show snackbar with results and refresh library
    if (result != null && context.mounted) {
      final newlyClassified = result['newly_classified'] ?? 0;
      final failed = result['failed'] ?? 0;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Classified $newlyClassified books${failed > 0 ? ' ($failed failed)' : ''}',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      
      // Refresh the library to show updated classifications
      await provider.loadEbooks();
    }
  }
}

/// Dialog for auto-classifying books with tree preview
class _AutoClassifyDialog extends StatefulWidget {
  final LocalLibraryProvider provider;

  const _AutoClassifyDialog({required this.provider});

  @override
  State<_AutoClassifyDialog> createState() => _AutoClassifyDialogState();
}

class _AutoClassifyDialogState extends State<_AutoClassifyDialog> {
  final ApiService _api = ApiService();
  bool _loading = true;
  bool _loadingPreview = false;
  bool _classifying = false;
  Map<String, dynamic>? _stats;
  Map<String, dynamic>? _preview;
  Map<String, dynamic>? _result;
  String? _error;
  Set<String> _expandedCategories = {};
  
  // Phase 3: Manual override state
  Map<String, List<String>> _taxonomy = {}; // category -> [sub_genres]
  // Map of book_id -> {category, sub_genre} for overrides
  Map<int, Map<String, String>> _overrides = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Load stats and taxonomy in parallel
      final results = await Future.wait([
        _api.getOrganizationStats(sourcePath: widget.provider.libraryPath),
        _api.getTaxonomy(),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>;
        _taxonomy = results[1] as Map<String, List<String>>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadPreview() async {
    if (!mounted) return;
    setState(() {
      _loadingPreview = true;
      _error = null;
    });
    try {
      final preview = await _api.getClassificationPreview(
        sourcePath: widget.provider.libraryPath,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loadingPreview = false;
        // Expand non-uncategorized categories by default
        _expandedCategories = {};
        final tree = preview['tree'] as Map<String, dynamic>? ?? {};
        for (final cat in tree.keys) {
          if (cat != '_Uncategorized') {
            _expandedCategories.add(cat);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingPreview = false;
      });
    }
  }

  Future<void> _classify() async {
    if (!mounted) return;
    setState(() {
      _classifying = true;
      _error = null;
    });
    try {
      final result = await _api.batchClassifyEbooks(
        sourcePath: widget.provider.libraryPath,
        limit: 100,
        overrides: _overrides.isEmpty ? null : _overrides,
      );
      if (!mounted) return;
      
      // Extract classifications and sync to local SQLite
      final classifications = result['classifications'] as Map<String, dynamic>? ?? {};
      if (classifications.isNotEmpty) {
        final syncData = <String, Map<String, String?>>{};
        for (final entry in classifications.entries) {
          final filePath = entry.key;
          final data = entry.value as Map<String, dynamic>;
          syncData[filePath] = {
            'category': data['category'] as String?,
            'sub_genre': data['sub_genre'] as String?,
          };
        }
        // Sync to local SQLite
        await widget.provider.updateClassifications(syncData);
      }
      
      setState(() {
        _result = result;
        _classifying = false;
        _preview = null; // Clear preview after applying
      });
      // Reload stats to show updated counts in dialog
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _classifying = false;
      });
    }
  }

  void _closeWithResult() {
    Navigator.pop(context, _result);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.amber, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-Classify Books',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                        Text(
                          '📂 Files stay in place - only metadata is updated',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onPrimaryContainer.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
            
            // Content
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _buildError()
                      : _preview != null
                          ? _buildTreePreview()
                          : _buildStatsView(),
            ),
            
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_result != null)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '✅ Classified ${_result!['newly_classified']} books',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                        ),
                      ),
                    ),
                  const SizedBox(width: 12),
                  if (_preview == null && _stats != null && (_stats!['unclassified_books'] ?? 0) > 0)
                    FilledButton.tonal(
                      onPressed: _loadingPreview ? null : _loadPreview,
                      child: _loadingPreview
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Preview Plan'),
                    ),
                  if (_preview != null && _result == null) ...[
                    TextButton(
                      onPressed: () => setState(() => _preview = null),
                      child: const Text('Back'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _classifying ? null : _classify,
                      icon: _classifying
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check),
                      label: Text(_classifying ? 'Applying...' : 'Apply Classification'),
                    ),
                  ],
                  // Show close button after classification completes
                  if (_result != null)
                    FilledButton.icon(
                      onPressed: _closeWithResult,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Done'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Error: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsView() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          Row(
            children: [
              _buildStatCard('Total Books', _stats!['total_books']?.toString() ?? '0', Icons.book, Colors.blue),
              const SizedBox(width: 12),
              _buildStatCard('Classified', _stats!['classified_books']?.toString() ?? '0', Icons.check_circle, Colors.green),
              const SizedBox(width: 12),
              _buildStatCard('Unclassified', _stats!['unclassified_books']?.toString() ?? '0', Icons.pending, Colors.orange),
            ],
          ),
          const SizedBox(height: 24),
          
          // Progress bar
          Text('Organization Progress', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (_stats!['coverage_percent'] ?? 0) / 100,
            minHeight: 12,
            borderRadius: BorderRadius.circular(6),
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
          ),
          const SizedBox(height: 4),
          Text('${(_stats!['coverage_percent'] ?? 0).toStringAsFixed(1)}% organized'),
          
          const Spacer(),
          
          // Info text
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Click "Preview Plan" to see the proposed organization for unclassified books before applying.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  /// Build the effective tree by applying overrides to the original preview data
  Map<String, dynamic> _buildEffectiveTree() {
    final originalTree = (_preview?['tree'] as Map<String, dynamic>?) ?? {};
    if (_overrides.isEmpty) return originalTree;

    // Flatten all books with their current placement
    final allBooks = <Map<String, dynamic>>[];
    for (final catEntry in originalTree.entries) {
      final subGenres = catEntry.value as Map<String, dynamic>;
      for (final sgEntry in subGenres.entries) {
        final books = sgEntry.value as List<dynamic>;
        for (final book in books) {
          final bookMap = Map<String, dynamic>.from(book as Map);
          final bookId = bookMap['id'] as int?;
          if (bookId != null && _overrides.containsKey(bookId)) {
            // Override applied
            bookMap['_override_category'] = _overrides[bookId]!['category'];
            bookMap['_override_sub_genre'] = _overrides[bookId]!['sub_genre'];
          } else {
            bookMap['_override_category'] = catEntry.key;
            bookMap['_override_sub_genre'] = sgEntry.key;
          }
          allBooks.add(bookMap);
        }
      }
    }

    // Rebuild tree from overridden placements
    final newTree = <String, dynamic>{};
    for (final book in allBooks) {
      final cat = book['_override_category'] as String;
      final sg = book['_override_sub_genre'] as String;
      newTree.putIfAbsent(cat, () => <String, dynamic>{});
      (newTree[cat] as Map<String, dynamic>).putIfAbsent(sg, () => <dynamic>[]);
      ((newTree[cat] as Map<String, dynamic>)[sg] as List<dynamic>).add(book);
    }
    return newTree;
  }

  void _applyOverride(int bookId, String category, String subGenre) {
    setState(() {
      _overrides[bookId] = {'category': category, 'sub_genre': subGenre};
    });
  }

  void _showEditDialog(BuildContext context, Map<String, dynamic> book, String currentCategory, String currentSubGenre) {
    String selectedCategory = currentCategory;
    String selectedSubGenre = currentSubGenre;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final subGenres = _taxonomy[selectedCategory] ?? [];
            if (!subGenres.contains(selectedSubGenre)) {
              selectedSubGenre = subGenres.isNotEmpty ? subGenres.first : '';
            }
            return AlertDialog(
              title: Text(
                book['title'] ?? 'Unknown',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: _taxonomy.keys.map((cat) => DropdownMenuItem(
                      value: cat,
                      child: Text(cat),
                    )).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() {
                        selectedCategory = val;
                        final newSubGenres = _taxonomy[val] ?? [];
                        selectedSubGenre = newSubGenres.isNotEmpty ? newSubGenres.first : '';
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('Sub-Genre', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: selectedSubGenre.isNotEmpty ? selectedSubGenre : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: (subGenres).map((sg) => DropdownMenuItem(
                      value: sg,
                      child: Text(sg),
                    )).toList(),
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() => selectedSubGenre = val);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final bookId = book['id'] as int?;
                    if (bookId != null && selectedSubGenre.isNotEmpty) {
                      _applyOverride(bookId, selectedCategory, selectedSubGenre);
                    }
                    Navigator.pop(ctx);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTreePreview() {
    final tree = _buildEffectiveTree();
    final categoryCounts = <String, int>{};
    for (final catEntry in tree.entries) {
      int count = 0;
      for (final sgEntry in (catEntry.value as Map<String, dynamic>).values) {
        count += (sgEntry as List<dynamic>).length;
      }
      categoryCounts[catEntry.key] = count;
    }
    
    if (tree.isEmpty) {
      return const Center(child: Text('No books to classify'));
    }

    final hasOverrides = _overrides.isNotEmpty;
    
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Proposed Organization (${_preview?['total_to_classify'] ?? 0} books)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (hasOverrides)
                TextButton.icon(
                  onPressed: () => setState(() => _overrides.clear()),
                  icon: const Icon(Icons.undo, size: 16),
                  label: Text('Reset ${_overrides.length} override${_overrides.length == 1 ? '' : 's'}'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (hasOverrides)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '${_overrides.length} book${_overrides.length == 1 ? '' : 's'} manually reassigned',
                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ...tree.entries.map((catEntry) {
          final category = catEntry.key;
          final subGenres = catEntry.value as Map<String, dynamic>;
          final count = categoryCounts[category] ?? 0;
          final isExpanded = _expandedCategories.contains(category);
          
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category header
              InkWell(
                onTap: () => setState(() {
                  if (isExpanded) {
                    _expandedCategories.remove(category);
                  } else {
                    _expandedCategories.add(category);
                  }
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Row(
                    children: [
                      Icon(
                        isExpanded ? Icons.expand_more : Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(width: 8),
                      Icon(_getCategoryIcon(category), color: _getCategoryColor(category)),
                      const SizedBox(width: 8),
                      Text(
                        category,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(category).withOpacity(0.3),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$count books',
                          style: TextStyle(
                            color: _getCategoryColor(category),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Sub-genres and books
              if (isExpanded)
                ...subGenres.entries.map((sgEntry) {
                  final subGenre = sgEntry.key;
                  final books = sgEntry.value as List<dynamic>;
                  
                  return DragTarget<Map<String, dynamic>>(
                    onAcceptWithDetails: (details) {
                      final book = details.data;
                      final bookId = book['id'] as int?;
                      if (bookId != null) {
                        _applyOverride(bookId, category, subGenre);
                      }
                    },
                    builder: (context, candidateData, rejectedData) {
                      final isDropTarget = candidateData.isNotEmpty;
                      return Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDropTarget
                                    ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
                                    : null,
                                border: isDropTarget
                                    ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
                                    : null,
                                borderRadius: isDropTarget ? BorderRadius.circular(8) : null,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isDropTarget ? Icons.folder_open : Icons.folder_outlined,
                                    size: 18,
                                    color: isDropTarget
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    subGenre,
                                    style: TextStyle(
                                      color: isDropTarget
                                          ? Theme.of(context).colorScheme.primary
                                          : Theme.of(context).colorScheme.onSurface,
                                      fontWeight: isDropTarget ? FontWeight.bold : null,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '(${books.length})',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                                  ),
                                  if (isDropTarget) ...[
                                    const Spacer(),
                                    Icon(Icons.add_circle, size: 18, color: Theme.of(context).colorScheme.primary),
                                  ],
                                ],
                              ),
                            ),
                            ...books.map((book) {
                              final bookMap = book as Map<String, dynamic>;
                              final bookId = bookMap['id'] as int?;
                              final isOverridden = bookId != null && _overrides.containsKey(bookId);
                              
                              return Draggable<Map<String, dynamic>>(
                                data: bookMap,
                                feedback: Material(
                                  elevation: 6,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).colorScheme.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.menu_book, size: 14),
                                        const SizedBox(width: 8),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 250),
                                          child: Text(
                                            bookMap['title'] ?? 'Unknown',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                childWhenDragging: Opacity(
                                  opacity: 0.3,
                                  child: _buildBookRow(bookMap, category, subGenre, isOverridden),
                                ),
                                child: _buildBookRow(bookMap, category, subGenre, isOverridden),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  );
                }),
            ],
          );
        }),
      ],
    );
  }

  Widget _buildBookRow(Map<String, dynamic> book, String category, String subGenre, bool isOverridden) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, right: 8, bottom: 4),
      child: Row(
        children: [
          Icon(
            Icons.drag_indicator,
            size: 14,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.menu_book,
            size: 14,
            color: isOverridden
                ? Colors.orange
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              book['title'] ?? 'Unknown',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isOverridden
                    ? Colors.orange.shade700
                    : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontWeight: isOverridden ? FontWeight.w600 : null,
              ),
            ),
          ),
          if (isOverridden)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.edit, size: 12, color: Colors.orange.shade600),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showEditDialog(context, book, category, subGenre),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.swap_horiz,
                size: 16,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Fiction': return Icons.auto_stories;
      case 'Non-Fiction': return Icons.history_edu;
      case 'Children': return Icons.child_care;
      case 'Reference': return Icons.menu_book;
      case '_Uncategorized': return Icons.help_outline;
      default: return Icons.folder;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Fiction': return Colors.purple;
      case 'Non-Fiction': return Colors.blue;
      case 'Children': return Colors.pink;
      case 'Reference': return Colors.teal;
      case '_Uncategorized': return Colors.grey;
      default: return Colors.indigo;
    }
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

class _CategoryDropdown extends StatefulWidget {
  final LocalLibraryProvider provider;

  const _CategoryDropdown({required this.provider});

  @override
  State<_CategoryDropdown> createState() => _CategoryDropdownState();
}

class _CategoryDropdownState extends State<_CategoryDropdown> {
  List<String> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    widget.provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    widget.provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (!widget.provider.isScanning && !_loading) {
      _loadCategories();
    }
  }

  Future<void> _loadCategories() async {
    final categories = await widget.provider.getCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 100,
        child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    if (_categories.isEmpty) {
      return const Text('No categories', style: TextStyle(color: Colors.grey));
    }

    return DropdownButton<String?>(
      value: widget.provider.selectedCategory,
      hint: const Text('All categories'),
      underline: const SizedBox(),
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem(value: null, child: Text('All categories')),
        ..._categories.map(
          (c) => DropdownMenuItem(
            value: c,
            child: Text(
              c.length > 20 ? '${c.substring(0, 20)}...' : c,
            ),
          ),
        ),
      ],
      onChanged: (value) => widget.provider.setCategory(value),
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
