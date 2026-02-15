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
  /// Returns a record with success status and optional error message.
  Future<({bool success, String? error})> writeMetadata(String filePath, {
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
      
      print('[BackendMetadataService] writeMetadata called for: $filePath');
      print('[BackendMetadataService] Request body: $body');
      print('[BackendMetadataService] Fields being sent: ${body.keys.toList()}');
      print('[BackendMetadataService] Empty/null fields NOT sent: '
          'title=${title == null ? "null" : (title.isEmpty ? "empty" : "set")}, '
          'author=${author == null ? "null" : (author.isEmpty ? "empty" : "set")}, '
          'description=${description == null ? "null" : (description.isEmpty ? "empty" : "set")}, '
          'publisher=${publisher == null ? "null" : (publisher.isEmpty ? "empty" : "set")}');
      
      final url = '$baseUrl/api/metadata/write?file_path=$encodedPath';
      print('[BackendMetadataService] PUT $url');
      
      final response = await http.put(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 30));
      
      print('[BackendMetadataService] Response status: ${response.statusCode}');
      print('[BackendMetadataService] Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final success = data['success'] == true;
        final error = data['error'] as String?;
        print('[BackendMetadataService] Backend reported success=$success, message=${data['message']}, error=$error');
        return (success: success, error: error);
      }
      print('[BackendMetadataService] Non-200 response: ${response.statusCode}');
      return (success: false, error: 'Backend returned status ${response.statusCode}');
    } catch (e, stackTrace) {
      print('[BackendMetadataService] Error writing metadata via backend: $e');
      print('[BackendMetadataService] Stack trace: $stackTrace');
      return (success: false, error: 'Connection error: $e');
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
