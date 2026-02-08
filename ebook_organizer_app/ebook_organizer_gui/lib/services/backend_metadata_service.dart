import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to communicate with Python backend for metadata operations.
/// Used for PDF and MOBI files where native Dart support is limited.
class BackendMetadataService {
  final String baseUrl;
  
  BackendMetadataService({this.baseUrl = 'http://localhost:8000'});
  
  /// Read metadata from a file using the Python backend.
  /// 
  /// Returns a map with metadata fields or null on error.
  Future<Map<String, dynamic>?> readMetadata(String filePath) async {
    try {
      final encodedPath = Uri.encodeComponent(filePath);
      final response = await http.get(
        Uri.parse('$baseUrl/api/metadata/read?file_path=$encodedPath'),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'metadata': data['metadata'],
            'format': data['format'],
            'writable': data['writable'],
          };
        }
      }
      return null;
    } catch (e) {
      print('Error reading metadata from backend: $e');
      return null;
    }
  }
  
  /// Write metadata to a file using the Python backend.
  /// 
  /// Returns true on success, false on failure.
  Future<bool> writeMetadata(String filePath, {
    String? title,
    String? author,
    String? description,
    String? publisher,
    String? language,
    List<String>? subjects,
  }) async {
    try {
      final encodedPath = Uri.encodeComponent(filePath);
      
      final body = <String, dynamic>{};
      if (title != null) body['title'] = title;
      if (author != null) body['author'] = author;
      if (description != null) body['description'] = description;
      if (publisher != null) body['publisher'] = publisher;
      if (language != null) body['language'] = language;
      if (subjects != null) body['subjects'] = subjects;
      
      final response = await http.put(
        Uri.parse('$baseUrl/api/metadata/write?file_path=$encodedPath'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('Error writing metadata via backend: $e');
      return false;
    }
  }
  
  /// Get supported formats from the backend.
  Future<List<Map<String, dynamic>>> getSupportedFormats() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/metadata/supported-formats'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['formats'] ?? []);
      }
      return [];
    } catch (e) {
      print('Error fetching supported formats: $e');
      return [];
    }
  }
  
  /// Check if the backend is available.
  Future<bool> isBackendAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/metadata/supported-formats'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// Check if a format is writable.
  bool isWritableFormat(String format) {
    final ext = format.toLowerCase();
    // MOBI is read-only
    return ext == '.epub' || ext == '.pdf' || ext == 'epub' || ext == 'pdf';
  }
}

// Global instance
final backendMetadataService = BackendMetadataService();
