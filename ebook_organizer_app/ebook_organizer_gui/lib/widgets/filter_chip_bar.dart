import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/ebook_provider.dart';

class FilterChipBar extends StatelessWidget {
  const FilterChipBar({super.key});

  static const List<String> categories = [
    'Fiction',
    'Non-Fiction',
    'Children',
    'Comics',
    'Reference',
  ];

  static const List<String> formats = [
    'EPUB',
    'PDF',
    'MOBI',
    'AZW',
    'AZW3',
  ];

  @override
  Widget build(BuildContext context) {
    return Consumer<EbookProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              // Category filters
              ...categories.map((category) {
                final isSelected = provider.selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(category),
                    selected: isSelected,
                    onSelected: (selected) {
                      provider.setCategory(selected ? category : null);
                    },
                  ),
                );
              }),
              const SizedBox(width: 8),
              const VerticalDivider(),
              const SizedBox(width: 8),
              // Format filters
              ...formats.map((format) {
                final isSelected = provider.selectedFormat == format.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    label: Text(format),
                    selected: isSelected,
                    onSelected: (selected) {
                      provider.setFormat(selected ? format.toLowerCase() : null);
                    },
                  ),
                );
              }),
              const SizedBox(width: 8),
              // Clear filters button
              if (provider.selectedCategory != null || provider.selectedFormat != null)
                TextButton.icon(
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear Filters'),
                  onPressed: () => provider.clearFilters(),
                ),
            ],
          ),
        );
      },
    );
  }
}
