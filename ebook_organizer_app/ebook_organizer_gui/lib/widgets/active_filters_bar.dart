import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/local_library_provider.dart';

/// Widget displaying active filters as dismissible chips
class ActiveFiltersBar extends StatelessWidget {
  const ActiveFiltersBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<LocalLibraryProvider>(
      builder: (context, provider, _) {
        if (!provider.hasActiveFilters) {
          return const SizedBox.shrink();
        }

        final colorScheme = Theme.of(context).colorScheme;
        final chips = <Widget>[];

        // Search query chip
        if (provider.searchQuery != null && provider.searchQuery!.isNotEmpty) {
          chips.add(_buildChip(
            context,
            icon: Icons.search,
            label: 'Search: "${provider.searchQuery}"',
            backgroundColor: colorScheme.primaryContainer,
            labelColor: colorScheme.onPrimaryContainer,
            onDelete: () => provider.clearSearch(),
          ));
        }

        // Category chip
        if (provider.selectedCategory != null) {
          chips.add(_buildChip(
            context,
            icon: Icons.category,
            label: provider.selectedCategory!,
            backgroundColor: colorScheme.secondaryContainer,
            labelColor: colorScheme.onSecondaryContainer,
            onDelete: () => provider.clearCategory(),
          ));
        }

        // Format chip
        if (provider.selectedFormat != null) {
          chips.add(_buildChip(
            context,
            icon: Icons.description,
            label: provider.selectedFormat!.toUpperCase(),
            backgroundColor: _getFormatColor(provider.selectedFormat!).withOpacity(0.2),
            labelColor: _getFormatColor(provider.selectedFormat!),
            onDelete: () => provider.clearFormat(),
          ));
        }

        // Author chip
        if (provider.selectedAuthor != null) {
          chips.add(_buildChip(
            context,
            icon: Icons.person,
            label: provider.selectedAuthor!,
            backgroundColor: colorScheme.tertiaryContainer,
            labelColor: colorScheme.onTertiaryContainer,
            onDelete: () => provider.clearAuthor(),
          ));
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant.withOpacity(0.3),
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withOpacity(0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.filter_list,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < chips.length; i++) ...[
                        chips[i],
                        if (i < chips.length - 1) const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              if (provider.activeFilterCount > 1) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => provider.clearFilters(),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear All'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color labelColor,
    required VoidCallback onDelete,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: Chip(
        avatar: Icon(icon, size: 16, color: labelColor),
        label: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: backgroundColor,
        deleteIcon: Icon(Icons.close, size: 16, color: labelColor),
        onDeleted: onDelete,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
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
