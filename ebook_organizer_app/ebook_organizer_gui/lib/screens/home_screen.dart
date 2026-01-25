import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ebook_provider.dart';
import '../providers/library_provider.dart';
import '../providers/local_library_provider.dart';
import '../widgets/ebook_grid.dart';
import '../widgets/search_bar_widget.dart';
import '../widgets/filter_chip_bar.dart';
import '../widgets/stats_dashboard.dart';
import 'local_library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    // Initialize providers
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EbookProvider>().initialize();
      context.read<LibraryProvider>().loadStats();
      context.read<LibraryProvider>().loadCloudProviders();
      context.read<LocalLibraryProvider>().loadEbooks();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      const LibraryView(),
      const LocalLibraryView(),
      const StatsView(),
      const SettingsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ebook Organizer'),
        elevation: 2,
        actions: [
          // Online/Offline indicator
          Consumer<EbookProvider>(
            builder: (context, provider, _) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Icon(
                      provider.isOnline ? Icons.cloud_done : Icons.cloud_off,
                      color: provider.isOnline ? Colors.green : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      provider.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        color: provider.isOnline ? Colors.green : Colors.orange,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Sync button
          Consumer<LibraryProvider>(
            builder: (context, provider, _) {
              return IconButton(
                icon: provider.isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                onPressed: provider.isSyncing
                    ? null
                    : () => provider.triggerSync(),
                tooltip: 'Sync with cloud',
              );
            },
          ),
        ],
      ),
      body: screens[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Local',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'Statistics',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SearchBarWidget(),
        const FilterChipBar(),
        Expanded(
          child: Consumer<EbookProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.error != null) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(provider.error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => provider.loadEbooksFromLocal(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }

              if (provider.ebooks.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.book_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No ebooks found',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        provider.isOnline
                            ? 'Sync with cloud storage to see your ebooks'
                            : 'Connect to internet and sync with cloud',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }

              return EbookGrid(ebooks: provider.ebooks);
            },
          ),
        ),
      ],
    );
  }
}

class StatsView extends StatelessWidget {
  const StatsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: StatsDashboard(),
    );
  }
}

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Cloud Storage',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        Consumer<LibraryProvider>(
          builder: (context, provider, _) {
            return Column(
              children: provider.cloudProviders.map((cloudProvider) {
                return Card(
                  child: ListTile(
                    leading: Icon(
                      cloudProvider.provider == 'google_drive'
                          ? Icons.cloud
                          : Icons.cloud_outlined,
                    ),
                    title: Text(cloudProvider.displayName),
                    subtitle: Text(cloudProvider.statusText),
                    trailing: Switch(
                      value: cloudProvider.isEnabled,
                      onChanged: (value) {
                        // TODO: Implement enable/disable
                      },
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 32),
        Text(
          'About',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0'),
          ),
        ),
      ],
    );
  }
}
