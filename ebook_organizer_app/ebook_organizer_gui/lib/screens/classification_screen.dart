import 'package:flutter/material.dart';
import '../providers/local_library_provider.dart';
import '../services/api_service.dart';

/// Full-screen classification screen with table layout.
///
/// Replaces the old _AutoClassifyDialog with a dedicated route featuring:
/// - Stats strip with progress bar
/// - Search/filter toolbar
/// - Table with inline category/sub-genre dropdowns
/// - Sticky bottom action bar
class ClassificationScreen extends StatefulWidget {
  final LocalLibraryProvider provider;

  const ClassificationScreen({super.key, required this.provider});

  @override
  State<ClassificationScreen> createState() => _ClassificationScreenState();
}

class _ClassificationScreenState extends State<ClassificationScreen> {
  final ApiService _api = ApiService();

  // Data
  Map<String, dynamic>? _stats;
  Map<String, List<String>> _taxonomy = {};
  List<_BookRow> _books = [];

  // Override tracking: bookId -> {category, sub_genre}
  final Map<int, Map<String, String>> _overrides = {};

  // UI state
  bool _loading = true;
  bool _applying = false;
  String? _error;
  String _searchQuery = '';
  String? _filterCategory;
  bool _showOverridesOnly = false;
  String _sortColumn = 'title';
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getOrganizationStats(sourcePath: widget.provider.libraryPath),
        _api.getTaxonomy(),
        _api.getClassificationPreview(
          sourcePath: widget.provider.libraryPath,
          limit: 500,
        ),
      ]);

      final stats = results[0] as Map<String, dynamic>;
      final taxonomy = results[1] as Map<String, List<String>>;
      final preview = results[2] as Map<String, dynamic>;

      // Flatten tree into book rows
      final books = <_BookRow>[];
      final tree = (preview['tree'] as Map<String, dynamic>?) ?? {};
      for (final catEntry in tree.entries) {
        final subGenres = catEntry.value as Map<String, dynamic>;
        for (final sgEntry in subGenres.entries) {
          final bookList = sgEntry.value as List<dynamic>;
          for (final book in bookList) {
            final m = book as Map<String, dynamic>;
            books.add(_BookRow(
              id: m['id'] as int? ?? 0,
              title: m['title'] as String? ?? 'Unknown',
              author: m['author'] as String? ?? '',
              filePath: m['cloud_file_path'] as String? ?? m['file_path'] as String? ?? '',
              aiCategory: catEntry.key,
              aiSubGenre: sgEntry.key,
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _taxonomy = taxonomy;
        _books = books;
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

  // Effective category/sub-genre considering overrides
  String _effectiveCategory(_BookRow book) =>
      _overrides[book.id]?['category'] ?? book.aiCategory;
  String _effectiveSubGenre(_BookRow book) =>
      _overrides[book.id]?['sub_genre'] ?? book.aiSubGenre;
  bool _isOverridden(_BookRow book) => _overrides.containsKey(book.id);

  List<_BookRow> get _filteredBooks {
    var list = _books.where((b) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!b.title.toLowerCase().contains(q) &&
            !b.author.toLowerCase().contains(q)) {
          return false;
        }
      }
      if (_filterCategory != null && _effectiveCategory(b) != _filterCategory) {
        return false;
      }
      if (_showOverridesOnly && !_isOverridden(b)) {
        return false;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'author':
          cmp = a.author.compareTo(b.author);
          break;
        case 'category':
          cmp = _effectiveCategory(a).compareTo(_effectiveCategory(b));
          break;
        case 'sub_genre':
          cmp = _effectiveSubGenre(a).compareTo(_effectiveSubGenre(b));
          break;
        default:
          cmp = a.title.compareTo(b.title);
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  void _setSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Future<void> _applyClassification() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final result = await _api.batchClassifyEbooks(
        sourcePath: widget.provider.libraryPath,
        limit: 500,
        overrides: _overrides.isEmpty ? null : _overrides,
      );
      if (!mounted) return;

      // Sync to local SQLite
      final classifications =
          result['classifications'] as Map<String, dynamic>? ?? {};
      if (classifications.isNotEmpty) {
        final syncData = <String, Map<String, String?>>{};
        for (final entry in classifications.entries) {
          final data = entry.value as Map<String, dynamic>;
          syncData[entry.key] = {
            'category': data['category'] as String?,
            'sub_genre': data['sub_genre'] as String?,
          };
        }
        await widget.provider.updateClassifications(syncData);
      }

      if (!mounted) return;

      // Pop with result
      Navigator.pop(context, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _applying = false;
      });
    }
  }

  // ──────────────────────── Build ────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.auto_awesome, color: Colors.amber, size: 24),
            const SizedBox(width: 10),
            const Text('Classify Library'),
          ],
        ),
        actions: [
          if (_overrides.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                onPressed: () => setState(() => _overrides.clear()),
                icon: const Icon(Icons.undo, size: 16),
                label: Text('Reset ${_overrides.length}'),
                style: TextButton.styleFrom(foregroundColor: Colors.orange),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _applying || _loading ? null : _applyClassification,
              icon: _applying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: Text(_applying ? 'Applying...' : 'Apply All'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : Column(
                  children: [
                    _buildStatsStrip(colorScheme),
                    _buildToolbar(colorScheme),
                    Expanded(child: _buildBookTable(colorScheme)),
                    if (_overrides.isNotEmpty) _buildBottomBar(colorScheme),
                  ],
                ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text('Error: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _loadAllData, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  // ──────────────────── Stats Strip ────────────────────

  Widget _buildStatsStrip(ColorScheme colorScheme) {
    final total = _stats?['total_books'] ?? 0;
    final classified = _stats?['classified_books'] ?? 0;
    final unclassified = _stats?['unclassified_books'] ?? 0;
    final coverage = (_stats?['coverage_percent'] ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _buildStatChip(Icons.book, '$total', 'Total', Colors.blue),
          const SizedBox(width: 16),
          _buildStatChip(
              Icons.check_circle, '$classified', 'Classified', Colors.green),
          const SizedBox(width: 16),
          _buildStatChip(
              Icons.pending, '$unclassified', 'Unclassified', Colors.orange),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${coverage.toStringAsFixed(1)}% organized',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: coverage / 100,
                    minHeight: 8,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.green),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(
      IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Toolbar ────────────────────

  Widget _buildToolbar(ColorScheme colorScheme) {
    final categories = _taxonomy.keys.toList()..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // Search
          Expanded(
            flex: 3,
            child: SizedBox(
              height: 38,
              child: TextField(
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'Search books...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () =>
                              setState(() => _searchQuery = ''),
                        )
                      : null,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  isDense: true,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Category filter
          SizedBox(
            height: 38,
            child: DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.outline),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String?>(
                  value: _filterCategory,
                  hint: const Text('All Categories', style: TextStyle(fontSize: 13)),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('All Categories')),
                    ...categories.map((c) => DropdownMenuItem(
                          value: c,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getCategoryIcon(c),
                                  size: 16, color: _getCategoryColor(c)),
                              const SizedBox(width: 6),
                              Text(c, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        )),
                  ],
                  onChanged: (v) =>
                      setState(() => _filterCategory = v),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Overrides toggle
          FilterChip(
            label: Text(
              'Overrides (${_overrides.length})',
              style: const TextStyle(fontSize: 12),
            ),
            selected: _showOverridesOnly,
            onSelected: (v) =>
                setState(() => _showOverridesOnly = v),
            avatar: Icon(
              Icons.edit_note,
              size: 16,
              color: _showOverridesOnly ? Colors.white : Colors.orange,
            ),
            selectedColor: Colors.orange,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
          ),

          const Spacer(),

          // Book count
          Text(
            '${_filteredBooks.length} of ${_books.length} books',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Table ────────────────────

  Widget _buildBookTable(ColorScheme colorScheme) {
    final filtered = _filteredBooks;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              _books.isEmpty
                  ? 'No books to classify'
                  : 'No books match your filters',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table header
        _buildTableHeader(colorScheme),

        // Table rows
        Expanded(
          child: ListView.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final book = filtered[index];
              return _buildTableRow(book, index, colorScheme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // Override indicator column
          const SizedBox(width: 32),
          _buildHeaderCell('Title', 'title', flex: 4),
          _buildHeaderCell('Author', 'author', flex: 2),
          _buildHeaderCell('Category', 'category', flex: 2),
          _buildHeaderCell('Sub-Genre', 'sub_genre', flex: 2),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String label, String column, {int flex = 1}) {
    final isActive = _sortColumn == column;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _setSort(column),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: isActive
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (isActive)
              Icon(
                _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableRow(
      _BookRow book, int index, ColorScheme colorScheme) {
    final cat = _effectiveCategory(book);
    final sg = _effectiveSubGenre(book);
    final overridden = _isOverridden(book);
    final catColor = _getCategoryColor(cat);
    final subGenres = _taxonomy[cat] ?? [];

    return Container(
      decoration: BoxDecoration(
        color: overridden
            ? Colors.orange.withValues(alpha: 0.06)
            : index.isEven
                ? colorScheme.surface
                : colorScheme.surfaceContainerLow,
        border: overridden
            ? Border(left: BorderSide(color: Colors.orange, width: 3))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          // Override indicator
          SizedBox(
            width: 32,
            child: overridden
                ? Tooltip(
                    message: 'Manually overridden',
                    child: IconButton(
                      icon: const Icon(Icons.undo, size: 16,
                          color: Colors.orange),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () =>
                          setState(() => _overrides.remove(book.id)),
                      tooltip: 'Reset this override',
                    ),
                  )
                : null,
          ),

          // Title
          Expanded(
            flex: 4,
            child: Text(
              book.title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: overridden ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),

          // Author
          Expanded(
            flex: 2,
            child: Text(
              book.author.isNotEmpty ? book.author : '—',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),

          // Category dropdown
          Expanded(
            flex: 2,
            child: _buildCategoryDropdown(book, cat, catColor),
          ),

          // Sub-genre dropdown
          Expanded(
            flex: 2,
            child: _buildSubGenreDropdown(book, cat, sg, subGenres),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryDropdown(
      _BookRow book, String currentCat, Color catColor) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: catColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: catColor.withValues(alpha: 0.25)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentCat,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16, color: catColor),
          style: TextStyle(
            fontSize: 12,
            color: catColor,
            fontWeight: FontWeight.w600,
          ),
          items: [
            // Ensure the current category is always in the list
            if (!_taxonomy.containsKey(currentCat))
              DropdownMenuItem(
                value: currentCat,
                child: Row(
                  children: [
                    Icon(_getCategoryIcon(currentCat),
                        size: 14, color: _getCategoryColor(currentCat)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(currentCat,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: _getCategoryColor(currentCat))),
                    ),
                  ],
                ),
              ),
            ..._taxonomy.keys.map((c) {
              return DropdownMenuItem(
                value: c,
                child: Row(
                  children: [
                    Icon(_getCategoryIcon(c),
                        size: 14, color: _getCategoryColor(c)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(c,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, color: _getCategoryColor(c))),
                    ),
                  ],
                ),
              );
            }),
          ],
          onChanged: (newCat) {
            if (newCat == null || newCat == currentCat) return;
            final newSubGenres = _taxonomy[newCat] ?? [];
            final newSg = newSubGenres.isNotEmpty ? newSubGenres.first : '';
            setState(() {
              _overrides[book.id] = {
                'category': newCat,
                'sub_genre': newSg,
              };
            });
          },
        ),
      ),
    );
  }

  Widget _buildSubGenreDropdown(
      _BookRow book, String currentCat, String currentSg,
      List<String> subGenres) {
    // Ensure the current value exists in the list
    final effectiveSubGenres = subGenres.contains(currentSg)
        ? subGenres
        : [currentSg, ...subGenres];

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentSg,
          isDense: true,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          items: effectiveSubGenres.map((sg) {
            return DropdownMenuItem(
              value: sg,
              child: Text(sg,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
            );
          }).toList(),
          onChanged: (newSg) {
            if (newSg == null || newSg == currentSg) return;
            setState(() {
              _overrides[book.id] = {
                'category': currentCat,
                'sub_genre': newSg,
              };
            });
          },
        ),
      ),
    );
  }

  // ──────────────────── Bottom Bar ────────────────────

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.edit_note, color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Text(
                  '${_overrides.length} book${_overrides.length == 1 ? '' : 's'} manually reassigned',
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => setState(() => _overrides.clear()),
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('Reset All'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _applying ? null : _applyClassification,
            icon: _applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check, size: 18),
            label: Text(_applying ? 'Applying...' : 'Apply Classification'),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Helpers ────────────────────

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Fiction':
        return Icons.auto_stories;
      case 'Non-Fiction':
        return Icons.history_edu;
      case 'Children':
        return Icons.child_care;
      case 'Reference':
        return Icons.menu_book;
      case '_Uncategorized':
        return Icons.help_outline;
      default:
        return Icons.folder;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Fiction':
        return Colors.purple;
      case 'Non-Fiction':
        return Colors.blue;
      case 'Children':
        return Colors.pink;
      case 'Reference':
        return Colors.teal;
      case '_Uncategorized':
        return Colors.grey;
      default:
        return Colors.indigo;
    }
  }
}

/// Internal data class for a book row in the table
class _BookRow {
  final int id;
  final String title;
  final String author;
  final String filePath;
  final String aiCategory;
  final String aiSubGenre;

  const _BookRow({
    required this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.aiCategory,
    required this.aiSubGenre,
  });
}
