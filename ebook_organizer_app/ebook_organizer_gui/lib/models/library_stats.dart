/// Library statistics model
class LibraryStats {
  final int totalBooks;
  final Map<String, int> byCategory;
  final Map<String, int> byFormat;
  final Map<String, int> byCloudProvider;
  final double totalSizeMb;
  final DateTime? lastSync;

  LibraryStats({
    required this.totalBooks,
    required this.byCategory,
    required this.byFormat,
    required this.byCloudProvider,
    required this.totalSizeMb,
    this.lastSync,
  });

  factory LibraryStats.fromJson(Map<String, dynamic> json) {
    return LibraryStats(
      totalBooks: json['total_books'] ?? 0,
      byCategory: Map<String, int>.from(json['by_category'] ?? {}),
      byFormat: Map<String, int>.from(json['by_format'] ?? {}),
      byCloudProvider: Map<String, int>.from(json['by_cloud_provider'] ?? {}),
      totalSizeMb: (json['total_size_mb'] ?? 0.0).toDouble(),
      lastSync: json['last_sync'] != null ? DateTime.parse(json['last_sync']) : null,
    );
  }

  factory LibraryStats.empty() {
    return LibraryStats(
      totalBooks: 0,
      byCategory: {},
      byFormat: {},
      byCloudProvider: {},
      totalSizeMb: 0.0,
    );
  }
}
