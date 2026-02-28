import 'package:flutter/material.dart';

/// Shared utility for consistent ebook format display across the app.
/// Provides canonical icon and color mappings for all supported formats.

/// Returns the appropriate Material icon for the given ebook format.
IconData getFormatIcon(String format) {
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
    case 'fb2':
      return Icons.article;
    case 'djvu':
      return Icons.document_scanner;
    default:
      return Icons.description;
  }
}

/// Returns the brand color associated with the given ebook format.
Color getFormatColor(String format) {
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
    case 'fb2':
      return Colors.teal;
    case 'djvu':
      return Colors.indigo;
    default:
      return Colors.blue;
  }
}
