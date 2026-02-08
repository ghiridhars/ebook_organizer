import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to handle ebook format conversions via the Python backend.
/// Uses Calibre's ebook-convert tool for high-quality conversions.
class ConversionService {
  final String baseUrl;
  
  ConversionService({this.baseUrl = 'http://localhost:8000'});
  
  /// Check if Calibre is available on the system.
  /// 
  /// Returns a map with 'available' (bool), 'path', and 'version'.
  Future<Map<String, dynamic>> checkCalibre() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/conversion/check-calibre'),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
      return {'available': false, 'error': 'Backend returned ${response.statusCode}'};
    } catch (e) {
      return {'available': false, 'error': e.toString()};
    }
  }
  
  /// Convert a MOBI/AZW file to EPUB format.
  /// 
  /// Returns a map with 'success', 'output_path', 'message', and optionally 'error'.
  Future<Map<String, dynamic>> convertMobiToEpub(String filePath, {String? outputPath}) async {
    try {
      final body = <String, dynamic>{
        'file_path': filePath,
      };
      if (outputPath != null) {
        body['output_path'] = outputPath;
      }
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/conversion/mobi-to-epub'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ).timeout(const Duration(minutes: 5)); // Conversion can take a while
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message': 'File not found',
          'error': 'The specified file does not exist',
        };
      } else if (response.statusCode == 409) {
        return {
          'success': false,
          'message': 'Output file already exists',
          'error': 'An EPUB file with this name already exists. Delete it first.',
        };
      } else if (response.statusCode == 503) {
        return {
          'success': false,
          'message': 'Calibre not found',
          'error': 'Please install Calibre from https://calibre-ebook.com',
        };
      } else {
        try {
          final errorData = jsonDecode(response.body);
          return {
            'success': false,
            'message': 'Conversion failed',
            'error': errorData['detail'] ?? 'Unknown error',
          };
        } catch (_) {
          return {
            'success': false,
            'message': 'Conversion failed',
            'error': 'Server returned ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Conversion failed',
        'error': e.toString(),
      };
    }
  }
  
  /// Check if a file format can be converted to EPUB.
  bool canConvertToEpub(String format) {
    final ext = format.toLowerCase().replaceAll('.', '');
    return ['mobi', 'azw', 'azw3'].contains(ext);
  }
}

// Global instance
final conversionService = ConversionService();
