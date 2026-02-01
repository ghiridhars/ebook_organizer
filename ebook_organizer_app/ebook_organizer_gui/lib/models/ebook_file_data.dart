/// Platform-agnostic file data for ebooks
/// Works on both web and native platforms
class EbookFileData {
  final String fileName;
  final String filePath; // On web, this could be a blob URL or empty
  final int fileSize;
  final DateTime modifiedDate;
  final List<int>? bytes; // File bytes (useful for web uploads)

  EbookFileData({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.modifiedDate,
    this.bytes,
  });

  /// Get file extension
  String get extension {
    if (fileName.contains('.')) {
      return fileName.split('.').last.toLowerCase();
    }
    return '';
  }
}
