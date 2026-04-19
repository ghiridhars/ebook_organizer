import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/local_library_provider.dart';
import '../models/local_ebook.dart';
import '../widgets/local_library_widget.dart';
import '../widgets/local_ebook_list_item.dart';
import '../widgets/active_filters_bar.dart';
import '../widgets/skeleton_widgets.dart';
import '../widgets/drive_folder_browser.dart';
import '../services/api_service.dart';
import 'classification_screen.dart';
import 'reorganize_screen.dart';

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
        return Column(
          children: [
            // Source toggle (Local / Google Drive / OneDrive)
            _SourceToggle(provider: provider),
            // Conditional content based on source
            Expanded(
              child: provider.isDriveSource
                  ? _buildDriveContent(context, provider)
                  : provider.isOnedriveSource
                      ? _buildOnedriveContent(context, provider)
                      : _buildLocalContent(context, provider),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildLocalContent(BuildContext context, LocalLibraryProvider provider) {
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
  }

  Widget _buildDriveContent(BuildContext context, LocalLibraryProvider provider) {
    // Not authenticated — show connect button
    if (!provider.isDriveAuthenticated) {
      return _DriveConnectScreen(provider: provider);
    }

    // No folder selected — show folder browser
    if (!provider.hasDriveFolder) {
      return DriveFolderBrowser(
        onFolderSelected: (folderId, folderPath) {
          provider.selectDriveFolder(folderId, folderPath);
          provider.triggerDriveSync();
        },
      );
    }

    // Folder selected — show toolbar + books (synced from Drive)
    return Column(
      children: [
        _DriveToolbar(provider: provider),
        const ActiveFiltersBar(),
        Expanded(child: _buildContent(provider)),
      ],
    );
  }

  Widget _buildOnedriveContent(BuildContext context, LocalLibraryProvider provider) {
    // Not authenticated — show connect button
    if (!provider.isOnedriveAuthenticated) {
      return _CloudConnectScreen(provider: provider, cloudProvider: 'onedrive');
    }

    // No folder selected — show folder browser
    if (!provider.hasOnedriveFolder) {
      return CloudFolderBrowser(
        provider: 'onedrive',
        onFolderSelected: (folderId, folderPath) {
          provider.selectOnedriveFolder(folderId, folderPath);
          provider.triggerOnedriveSync();
        },
      );
    }

    // Folder selected — show toolbar + books
    return Column(
      children: [
        _CloudToolbar(provider: provider, cloudProvider: 'onedrive'),
        const ActiveFiltersBar(),
        Expanded(child: _buildContent(provider)),
      ],
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
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
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

/// Source toggle bar: Local ↔ Google Drive ↔ OneDrive
class _SourceToggle extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _SourceToggle({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<LibrarySource>(
              segments: const [
                ButtonSegment(
                  value: LibrarySource.local,
                  label: Text('Local'),
                  icon: Icon(Icons.folder),
                ),
                ButtonSegment(
                  value: LibrarySource.googleDrive,
                  label: Text('Google Drive'),
                  icon: Icon(Icons.cloud),
                ),
                ButtonSegment(
                  value: LibrarySource.oneDrive,
                  label: Text('OneDrive'),
                  icon: Icon(Icons.cloud_outlined),
                ),
              ],
              selected: {provider.source},
              onSelectionChanged: (selected) {
                provider.setSource(selected.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Screen shown when Google Drive is not authenticated
class _DriveConnectScreen extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _DriveConnectScreen({required this.provider});

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
                Icons.cloud_off,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Connect Google Drive',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Sign in with your Google account to browse\n'
              'and sync ebooks from Google Drive.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final api = ApiService();
                  final authUrl = await api.authenticateProvider('google_drive');

                  // Open the Google consent page in the browser
                  final uri = Uri.parse(authUrl);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    throw Exception('Could not open browser');
                  }

                  if (!context.mounted) return;

                  // Show dialog for user to paste the authorization code
                  final code = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('Paste Authorization Code'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'After signing in with Google, copy the authorization '
                              'code from the browser and paste it below.',
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Authorization code',
                                border: OutlineInputBorder(),
                              ),
                              autofocus: true,
                              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                            child: const Text('Connect'),
                          ),
                        ],
                      );
                    },
                  );

                  if (code == null || code.isEmpty) return;

                  // Exchange the code for tokens
                  await api.exchangeOAuthCode('google_drive', code);
                  await provider.checkDriveAuth();

                  if (context.mounted && provider.isDriveAuthenticated) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Google Drive connected!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to connect: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Toolbar for Google Drive source view (replaces _Toolbar when in Drive mode)
class _DriveToolbar extends StatelessWidget {
  final LocalLibraryProvider provider;

  const _DriveToolbar({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          // Drive folder path + actions
          Row(
            children: [
              const Icon(Icons.cloud, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  provider.driveFolderPath ?? 'My Drive',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Change folder
              TextButton.icon(
                onPressed: () => provider.clearDriveFolder(),
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Change'),
              ),
              const SizedBox(width: 8),
              // Sync button
              IconButton.filled(
                onPressed: provider.isDriveSyncing
                    ? null
                    : () => provider.triggerDriveSync(),
                icon: provider.isDriveSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                tooltip: 'Sync from Drive',
              ),
            ],
          ),
          if (provider.isDriveSyncing) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
    );
  }
}

/// Generic connect screen for any cloud provider (OneDrive, etc.)
class _CloudConnectScreen extends StatelessWidget {
  final LocalLibraryProvider provider;
  final String cloudProvider;

  const _CloudConnectScreen({required this.provider, required this.cloudProvider});

  String get _displayName => cloudProvider == 'onedrive' ? 'OneDrive' : 'Google Drive';
  String get _signInLabel => cloudProvider == 'onedrive' ? 'Sign in with Microsoft' : 'Sign in with Google';
  String get _description => cloudProvider == 'onedrive'
      ? 'Sign in with your Microsoft account to browse\nand sync ebooks from OneDrive.'
      : 'Sign in with your Google account to browse\nand sync ebooks from Google Drive.';

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
                Icons.cloud_off,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Connect $_displayName',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                try {
                  final api = ApiService();
                  final authUrl = await api.authenticateProvider(cloudProvider);

                  final uri = Uri.parse(authUrl);
                  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                    throw Exception('Could not open browser');
                  }

                  if (!context.mounted) return;

                  final code = await showDialog<String>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('Paste Authorization Code'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'After signing in with ${cloudProvider == 'onedrive' ? 'Microsoft' : 'Google'}, '
                              'copy the authorization code from the browser and paste it below.',
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Authorization code',
                                border: OutlineInputBorder(),
                              ),
                              autofocus: true,
                              onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                            child: const Text('Connect'),
                          ),
                        ],
                      );
                    },
                  );

                  if (code == null || code.isEmpty) return;

                  await api.exchangeOAuthCode(cloudProvider, code);
                  if (cloudProvider == 'onedrive') {
                    await provider.checkOnedriveAuth();
                  } else {
                    await provider.checkDriveAuth();
                  }

                  if (context.mounted) {
                    final isAuth = cloudProvider == 'onedrive'
                        ? provider.isOnedriveAuthenticated
                        : provider.isDriveAuthenticated;
                    if (isAuth) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$_displayName connected!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to connect: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.login),
              label: Text(_signInLabel),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Generic toolbar for any cloud source (OneDrive, etc.)
class _CloudToolbar extends StatelessWidget {
  final LocalLibraryProvider provider;
  final String cloudProvider;

  const _CloudToolbar({required this.provider, required this.cloudProvider});

  String get _displayName => cloudProvider == 'onedrive' ? 'OneDrive' : 'My Drive';
  String? get _folderPath => cloudProvider == 'onedrive' ? provider.onedriveFolderPath : provider.driveFolderPath;
  bool get _isSyncing => cloudProvider == 'onedrive' ? provider.isOnedriveSyncing : provider.isDriveSyncing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                cloudProvider == 'onedrive' ? Icons.cloud_outlined : Icons.cloud,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _folderPath ?? _displayName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  if (cloudProvider == 'onedrive') {
                    provider.clearOnedriveFolder();
                  } else {
                    provider.clearDriveFolder();
                  }
                },
                icon: const Icon(Icons.folder_open, size: 18),
                label: const Text('Change'),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSyncing
                    ? null
                    : () {
                        if (cloudProvider == 'onedrive') {
                          provider.triggerOnedriveSync();
                        } else {
                          provider.triggerDriveSync();
                        }
                      },
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                tooltip: 'Sync from $_displayName',
              ),
            ],
          ),
          if (_isSyncing) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ],
      ),
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
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        children: [
          // Search bar + action buttons row
          Row(
            children: [
              Expanded(
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
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: provider.setSearchQuery,
                ),
              ),
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
              // More actions menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                tooltip: 'More actions',
                onSelected: (value) {
                  switch (value) {
                    case 'classify':
                      _showAutoClassifyDialog(context, provider);
                    case 'reorganize':
                      _showReorganizeScreen(context, provider);
                    case 'settings':
                      _showSettingsDialog(context, provider);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'classify',
                    child: ListTile(
                      leading: Icon(Icons.auto_awesome),
                      title: Text('Auto-classify books'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'reorganize',
                    child: ListTile(
                      leading: Icon(Icons.drive_file_move_outline),
                      title: Text('Reorganize files'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'settings',
                    child: ListTile(
                      leading: Icon(Icons.settings),
                      title: Text('Library settings'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Filter dropdowns row
          Row(
            children: [
              Expanded(child: _FormatDropdown(provider: provider)),
              const SizedBox(width: 8),
              Expanded(child: _CategoryDropdown(provider: provider)),
              const SizedBox(width: 8),
              Expanded(child: _AuthorDropdown(provider: provider)),
              const SizedBox(width: 8),
              Expanded(child: _SortDropdown(provider: provider)),
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
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (context) => ClassificationScreen(provider: provider),
      ),
    );
    
    // Show snackbar with results and refresh library
    if (result != null && context.mounted) {
      final newlyClassified = result['newly_classified'] ?? 0;
      final failed = result['failed'] ?? 0;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'âœ… Classified $newlyClassified books${failed > 0 ? ' ($failed failed)' : ''}',
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

  void _showReorganizeScreen(BuildContext context, LocalLibraryProvider provider) async {
    final result = await Navigator.push<Map<String, dynamic>?>(
      context,
      MaterialPageRoute(
        builder: (context) => ReorganizeScreen(provider: provider),
      ),
    );

    if (result != null && context.mounted) {
      final succeeded = result['succeeded'] ?? 0;
      final failed = result['failed'] ?? 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Reorganized $succeeded files${failed > 0 ? ' ($failed failed)' : ''}',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );

      await provider.loadEbooks();
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
      isExpanded: true,
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
      isExpanded: true,
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

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final api = ApiService();
      final taxonomy = await api.getTaxonomy();
      if (mounted) {
        setState(() {
          _categories = taxonomy.keys.toList()..sort();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: widget.provider.selectedCategory,
      hint: const Text('All categories'),
      underline: const SizedBox(),
      isExpanded: true,
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem(value: null, child: Text('All categories')),
        ..._categories.map(
          (c) => DropdownMenuItem(value: c, child: Text(c)),
        ),
      ],
      onChanged: widget.provider.setCategory,
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

  @override
  void initState() {
    super.initState();
    _loadAuthors();
  }

  Future<void> _loadAuthors() async {
    try {
      final authors = await widget.provider.getAuthors();
      if (mounted) {
        setState(() {
          _authors = authors;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String?>(
      value: widget.provider.selectedAuthor,
      hint: const Text('All authors'),
      underline: const SizedBox(),
      isExpanded: true,
      borderRadius: BorderRadius.circular(8),
      items: [
        const DropdownMenuItem(value: null, child: Text('All authors')),
        ..._authors.map(
          (a) => DropdownMenuItem(value: a, child: Text(a)),
        ),
      ],
      onChanged: widget.provider.setAuthor,
    );
  }
}

