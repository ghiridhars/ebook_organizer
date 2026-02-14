import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/local_library_provider.dart';
import '../services/api_service.dart';

/// Full-screen reorganization screen for moving/copying ebooks
/// into a Category/SubGenre/Author folder structure.
class ReorganizeScreen extends StatefulWidget {
  final LocalLibraryProvider provider;

  const ReorganizeScreen({super.key, required this.provider});

  @override
  State<ReorganizeScreen> createState() => _ReorganizeScreenState();
}

class _ReorganizeScreenState extends State<ReorganizeScreen> {
  final ApiService _api = ApiService();

  // Configuration
  String? _destination;
  String _operation = 'move';
  bool _includeUnclassified = false;

  // Preview data
  List<_PlannedMoveRow> _plannedMoves = [];
  int _classifiedFiles = 0;
  int _unclassifiedFiles = 0;
  int _collisions = 0;

  // UI state
  bool _loading = false;
  bool _applying = false;
  String? _error;
  String _searchQuery = '';
  String _sortColumn = 'title';
  bool _sortAscending = true;

  // ──────────────────────── Actions ────────────────────────

  Future<void> _pickDestination() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select destination folder for reorganized library',
    );
    if (result != null) {
      setState(() {
        _destination = result;
        _plannedMoves = [];
        _error = null;
      });
    }
  }

  Future<void> _loadPreview() async {
    if (_destination == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final preview = await _api.getReorganizePreview(
        destination: _destination!,
        sourcePath: widget.provider.libraryPath,
        includeUnclassified: _includeUnclassified,
        operation: _operation,
      );

      final moves = (preview['planned_moves'] as List<dynamic>)
          .map((m) => _PlannedMoveRow(
                ebookId: m['ebook_id'] as int,
                sourcePath: m['source_path'] as String,
                targetPath: m['target_path'] as String,
                title: m['title'] as String,
                author: m['author'] as String,
                category: m['category'] as String? ?? '',
                subGenre: m['sub_genre'] as String? ?? '',
              ))
          .toList();

      if (!mounted) return;
      setState(() {
        _plannedMoves = moves;
        _classifiedFiles = preview['classified_files'] as int? ?? 0;
        _unclassifiedFiles = preview['unclassified_files'] as int? ?? 0;
        _collisions = preview['collisions'] as int? ?? 0;
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

  Future<void> _applyReorganization() async {
    setState(() {
      _applying = true;
      _error = null;
    });
    try {
      final result = await _api.reorganizeFiles(
        destination: _destination!,
        sourcePath: widget.provider.libraryPath,
        includeUnclassified: _includeUnclassified,
        operation: _operation,
      );

      if (!mounted) return;

      // Sync file paths to local SQLite (only for move operations)
      final pathMappings =
          (result['path_mappings'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v as String)) ??
              {};
      if (pathMappings.isNotEmpty && _operation == 'move') {
        await widget.provider.updateFilePaths(pathMappings);
        await widget.provider.updateLibraryPath(_destination!);
      }

      if (!mounted) return;
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
        title: const Row(
          children: [
            Icon(Icons.drive_file_move, color: Colors.blue, size: 24),
            SizedBox(width: 10),
            Text('Reorganize Library'),
          ],
        ),
        actions: [
          if (_plannedMoves.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed:
                    _applying || _loading ? null : _applyReorganization,
                icon: _applying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check, size: 18),
                label: Text(_applying
                    ? 'Applying...'
                    : '${_operation == 'move' ? 'Move' : 'Copy'} ${_plannedMoves.length} files'),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _plannedMoves.isEmpty
                  ? _buildConfigPanel(colorScheme)
                  : Column(
                      children: [
                        _buildSummaryStrip(colorScheme),
                        _buildSearchBar(colorScheme),
                        Expanded(child: _buildPreviewTable(colorScheme)),
                        _buildBottomBar(colorScheme),
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
              onPressed: _plannedMoves.isNotEmpty ? _loadPreview : () => setState(() => _error = null),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────── Config Panel ────────────────────

  Widget _buildConfigPanel(ColorScheme colorScheme) {
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: Card(
            margin: const EdgeInsets.all(32),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Row(
                  children: [
                    Icon(Icons.drive_file_move,
                        color: colorScheme.primary, size: 28),
                    const SizedBox(width: 12),
                    Text(
                      'Reorganize Files',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Organize your ebook files into a structured folder hierarchy based on their classification.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),

                // Destination picker
                Text('Destination Folder',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDestination,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      border:
                          Border.all(color: colorScheme.outline.withValues(alpha: 0.5)),
                      borderRadius: BorderRadius.circular(8),
                      color: colorScheme.surfaceContainerLow,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_open,
                            color: _destination != null
                                ? Colors.amber
                                : colorScheme.onSurfaceVariant,
                            size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _destination ?? 'Choose destination folder...',
                            style: TextStyle(
                              color: _destination != null
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.edit,
                            size: 16, color: colorScheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Operation toggle
                Text('Operation',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'move',
                        groupValue: _operation,
                        onChanged: (v) =>
                            setState(() => _operation = v!),
                        title: const Text('Move'),
                        subtitle: const Text('Relocate files',
                            style: TextStyle(fontSize: 12)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        value: 'copy',
                        groupValue: _operation,
                        onChanged: (v) =>
                            setState(() => _operation = v!),
                        title: const Text('Copy'),
                        subtitle: const Text('Keep originals',
                            style: TextStyle(fontSize: 12)),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Include unclassified
                CheckboxListTile(
                  value: _includeUnclassified,
                  onChanged: (v) =>
                      setState(() => _includeUnclassified = v ?? false),
                  title: const Text('Include unclassified books'),
                  subtitle: const Text(
                      'Place them in an "Unclassified" folder',
                      style: TextStyle(fontSize: 12)),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 24),

                // Folder structure preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Folder Structure',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      Text(
                        'Destination/\n'
                        '  Category/\n'
                        '    Sub-Genre/\n'
                        '      Author/\n'
                        '        book.epub',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Generate preview button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _destination != null ? _loadPreview : null,
                    icon: const Icon(Icons.preview, size: 18),
                    label: const Text('Generate Preview'),
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

  // ──────────────────── Summary Strip ────────────────────

  Widget _buildSummaryStrip(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border:
            Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          _buildStatChip(Icons.description, '${_plannedMoves.length}',
              'Total', Colors.blue),
          const SizedBox(width: 16),
          _buildStatChip(Icons.check_circle, '$_classifiedFiles',
              'Classified', Colors.green),
          if (_unclassifiedFiles > 0) ...[
            const SizedBox(width: 16),
            _buildStatChip(Icons.help_outline, '$_unclassifiedFiles',
                'Unclassified', Colors.orange),
          ],
          if (_collisions > 0) ...[
            const SizedBox(width: 16),
            _buildStatChip(Icons.warning_amber, '$_collisions',
                'Collisions', Colors.red),
          ],
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _operation == 'move'
                  ? Colors.blue.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: _operation == 'move'
                      ? Colors.blue.withValues(alpha: 0.25)
                      : Colors.green.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _operation == 'move'
                      ? Icons.drive_file_move
                      : Icons.file_copy,
                  size: 16,
                  color:
                      _operation == 'move' ? Colors.blue : Colors.green,
                ),
                const SizedBox(width: 6),
                Text(
                  _operation == 'move' ? 'Move' : 'Copy',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _operation == 'move'
                        ? Colors.blue
                        : Colors.green,
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
                fontSize: 12,
                color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Search Bar ────────────────────

  Widget _buildSearchBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        border:
            Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            height: 36,
            child: TextField(
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search by title or author...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          const Spacer(),
          Text(
            '${_filteredMoves.length} of ${_plannedMoves.length} files',
            style: TextStyle(
                fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _plannedMoves = [];
                _error = null;
              });
            },
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Change Settings'),
            style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ──────────────────── Preview Table ────────────────────

  List<_PlannedMoveRow> get _filteredMoves {
    var moves = _plannedMoves;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      moves = moves
          .where((m) =>
              m.title.toLowerCase().contains(q) ||
              m.author.toLowerCase().contains(q))
          .toList();
    }
    moves.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'title':
          cmp = a.title.toLowerCase().compareTo(b.title.toLowerCase());
          break;
        case 'author':
          cmp = a.author.toLowerCase().compareTo(b.author.toLowerCase());
          break;
        case 'category':
          cmp = a.category.compareTo(b.category);
          break;
        case 'target':
          cmp = a.targetPath.compareTo(b.targetPath);
          break;
        default:
          cmp = 0;
      }
      return _sortAscending ? cmp : -cmp;
    });
    return moves;
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
  }

  Widget _buildPreviewTable(ColorScheme colorScheme) {
    final moves = _filteredMoves;

    return Column(
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: Row(
            children: [
              _buildHeaderCell('Title', 'title', flex: 3),
              _buildHeaderCell('Author', 'author', flex: 2),
              _buildHeaderCell('Category', 'category', flex: 2),
              _buildHeaderCell('Target Path', 'target', flex: 4),
            ],
          ),
        ),
        // Data rows
        Expanded(
          child: ListView.builder(
            itemCount: moves.length,
            itemBuilder: (context, index) {
              final move = moves[index];
              return _buildMoveRow(move, index, colorScheme);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCell(String label, String column, {int flex = 1}) {
    final isActive = _sortColumn == column;
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () => _onSort(column),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isActive ? Colors.blue : null,
              ),
            ),
            if (isActive)
              Icon(
                _sortAscending
                    ? Icons.arrow_upward
                    : Icons.arrow_downward,
                size: 14,
                color: Colors.blue,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMoveRow(
      _PlannedMoveRow move, int index, ColorScheme colorScheme) {
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: isEven ? null : colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          // Title
          Expanded(
            flex: 3,
            child: Text(
              move.title,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Author
          Expanded(
            flex: 2,
            child: Text(
              move.author,
              style: TextStyle(
                fontSize: 13,
                color: move.author == 'Unknown Author'
                    ? colorScheme.onSurfaceVariant
                    : null,
                fontStyle: move.author == 'Unknown Author'
                    ? FontStyle.italic
                    : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Category / SubGenre
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  move.category.isNotEmpty ? move.category : 'Unclassified',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: move.category.isEmpty
                        ? Colors.orange
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (move.subGenre.isNotEmpty)
                  Text(
                    move.subGenre,
                    style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Target path
          Expanded(
            flex: 4,
            child: Tooltip(
              message: move.targetPath,
              child: Text(
                _shortenPath(move.targetPath),
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _shortenPath(String path) {
    if (_destination == null) return path;
    if (path.startsWith(_destination!)) {
      return '...${path.substring(_destination!.length)}';
    }
    return path;
  }

  // ──────────────────── Bottom Bar ────────────────────

  Widget _buildBottomBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border:
            Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _operation == 'move'
                  ? 'Files will be moved to the destination. Original files will be removed. Database paths will be updated.'
                  : 'Files will be copied to the destination. Original files remain unchanged.',
              style: TextStyle(
                  fontSize: 12, color: colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _plannedMoves = [];
                _error = null;
              });
            },
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Back to Settings'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _applying ? null : _applyReorganization,
            icon: _applying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(
                    _operation == 'move'
                        ? Icons.drive_file_move
                        : Icons.file_copy,
                    size: 18),
            label: Text(_applying
                ? 'Processing...'
                : '${_operation == 'move' ? 'Move' : 'Copy'} ${_plannedMoves.length} Files'),
          ),
        ],
      ),
    );
  }
}

// ──────────────────── Data Class ────────────────────

class _PlannedMoveRow {
  final int ebookId;
  final String sourcePath;
  final String targetPath;
  final String title;
  final String author;
  final String category;
  final String subGenre;

  const _PlannedMoveRow({
    required this.ebookId,
    required this.sourcePath,
    required this.targetPath,
    required this.title,
    required this.author,
    required this.category,
    required this.subGenre,
  });
}
