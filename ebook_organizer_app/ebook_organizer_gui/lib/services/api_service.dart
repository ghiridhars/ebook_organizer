import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ebook.dart';
import '../models/library_stats.dart';
import '../models/cloud_provider.dart';
import '../utils/app_config.dart';

/// Custom exception for API errors with detailed information
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final String? responseBody;

  ApiException(this.message, {this.statusCode, this.responseBody});

  @override
  String toString() => statusCode != null 
      ? 'ApiException: $message (HTTP $statusCode)' 
      : 'ApiException: $message';
}

class ApiService {
  final AppConfig _config = AppConfig.instance;

  String get baseUrl => _config.apiBaseUrl;

  /// Common headers (Content-Type + optional API key)
  Map<String, String> get _headers {
    final h = <String, String>{'Content-Type': 'application/json'};
    final key = _config.apiKey;
    if (key != null && key.isNotEmpty) {
      h['X-API-Key'] = key;
    }
    return h;
  }

  /// Make a GET request with proper error handling and timeout
  Future<http.Response> _get(String path, {Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      return await http.get(uri, headers: _headers).timeout(
        timeout ?? _config.requestTimeout,
        onTimeout: () => throw TimeoutException('Request timed out'),
      );
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    } catch (e) {
      // Handle network errors (SocketException on native, ClientException on web)
      throw ApiException('Network error: Unable to connect to server. $e');
    }
  }

  /// Make a POST request with proper error handling and timeout
  Future<http.Response> _post(String path, {Map<String, dynamic>? body, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      return await http.post(
        uri,
        headers: _headers,
        body: body != null ? json.encode(body) : null,
      ).timeout(
        timeout ?? _config.requestTimeout,
        onTimeout: () => throw TimeoutException('Request timed out'),
      );
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    } catch (e) {
      throw ApiException('Network error: Unable to connect to server. $e');
    }
  }

  /// Make a PATCH request with proper error handling and timeout
  Future<http.Response> _patch(String path, {required Map<String, dynamic> body, Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      return await http.patch(
        uri,
        headers: _headers,
        body: json.encode(body),
      ).timeout(
        timeout ?? _config.requestTimeout,
        onTimeout: () => throw TimeoutException('Request timed out'),
      );
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    } catch (e) {
      throw ApiException('Network error: Unable to connect to server. $e');
    }
  }

  /// Make a DELETE request with proper error handling and timeout
  Future<http.Response> _delete(String path, {Duration? timeout}) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      return await http.delete(uri, headers: _headers).timeout(
        timeout ?? _config.requestTimeout,
        onTimeout: () => throw TimeoutException('Request timed out'),
      );
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    } catch (e) {
      throw ApiException('Network error: Unable to connect to server. $e');
    }
  }

  // Health Check
  Future<bool> isBackendAvailable() async {
    try {
      final response = await _get('/health', timeout: _config.healthCheckTimeout);
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get all ebooks with filters
  Future<List<Ebook>> getEbooks({
    int skip = 0,
    int limit = 100,
    String? category,
    String? subGenre,
    String? author,
    String? search,
    String? format,
    String? sourcePath,
  }) async {
    final queryParams = {
      'skip': skip.toString(),
      'limit': limit.toString(),
      if (category != null) 'category': category,
      if (subGenre != null) 'sub_genre': subGenre,
      if (author != null) 'author': author,
      if (search != null) 'search': search,
      if (format != null) 'format': format,
      if (sourcePath != null) 'source_path': sourcePath,
    };

    final uri = Uri.parse('$baseUrl/api/ebooks/').replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri).timeout(_config.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Ebook.fromJson(json)).toList();
      } else {
        throw ApiException(
          'Failed to load ebooks',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    } catch (e) {
      throw ApiException('Network error: Unable to connect to server. $e');
    }
  }

  // Get single ebook
  Future<Ebook> getEbook(int id) async {
    final response = await _get('/api/ebooks/$id');

    if (response.statusCode == 200) {
      return Ebook.fromJson(json.decode(response.body));
    } else if (response.statusCode == 404) {
      throw ApiException('Ebook not found', statusCode: 404);
    } else {
      throw ApiException(
        'Failed to load ebook',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Update ebook metadata
  Future<Ebook> updateEbook(int id, Map<String, dynamic> updates) async {
    final response = await _patch('/api/ebooks/$id', body: updates);

    if (response.statusCode == 200) {
      return Ebook.fromJson(json.decode(response.body));
    } else if (response.statusCode == 404) {
      throw ApiException('Ebook not found', statusCode: 404);
    } else {
      throw ApiException(
        'Failed to update ebook',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Delete ebook
  Future<void> deleteEbook(int id) async {
    final response = await _delete('/api/ebooks/$id');

    if (response.statusCode == 404) {
      throw ApiException('Ebook not found', statusCode: 404);
    } else if (response.statusCode != 200) {
      throw ApiException(
        'Failed to delete ebook',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Get library statistics
  Future<LibraryStats> getLibraryStats({String? sourcePath}) async {
    String path = '/api/ebooks/stats/library';
    if (sourcePath != null) {
      path += '?source_path=${Uri.encodeComponent(sourcePath)}';
    }
    final response = await _get(path);

    if (response.statusCode == 200) {
      return LibraryStats.fromJson(json.decode(response.body));
    } else {
      throw ApiException(
        'Failed to load library stats',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Get cloud providers status
  Future<List<CloudProvider>> getCloudProviders() async {
    final response = await _get('/api/cloud/providers');

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => CloudProvider.fromJson(json)).toList();
    } else {
      throw ApiException(
        'Failed to load cloud providers',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Trigger sync
  Future<Map<String, dynamic>> triggerSync({
    String? provider,
    bool fullSync = false,
    String? localPath,
    String? folderId,
  }) async {
    final response = await _post(
      '/api/sync/trigger',
      body: {
        if (provider != null) 'provider': provider,
        'full_sync': fullSync,
        if (localPath != null) 'local_path': localPath,
        if (folderId != null) 'folder_id': folderId,
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to trigger sync',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // Get sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final response = await _get('/api/sync/status');

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to get sync status',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Initiate OAuth — returns the auth URL the user must visit.
  Future<String> authenticateProvider(String provider) async {
    final response = await _post(
      '/api/cloud/providers/$provider/authenticate',
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to authenticate provider',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
    final data = json.decode(response.body);
    return data['auth_url'] as String;
  }

  /// Exchange the OAuth authorization code for tokens.
  Future<void> exchangeOAuthCode(String provider, String code) async {
    final response = await _get(
      '/api/cloud/providers/$provider/callback?code=${Uri.encodeComponent(code)}',
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to exchange authorization code',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  Future<void> disconnectProvider(String provider) async {
    final response = await _post(
      '/api/cloud/providers/$provider/disconnect',
    );

    if (response.statusCode != 200) {
      throw ApiException(
        'Failed to disconnect provider',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// List folders in a cloud provider (for folder browser UI)
  Future<List<Map<String, dynamic>>> listDriveFolders({String parentId = 'root'}) async {
    return listCloudFolders('google_drive', parentId: parentId);
  }

  /// List ebook files in a cloud provider folder
  Future<List<Map<String, dynamic>>> listDriveFiles({String? folderId}) async {
    return listCloudFiles('google_drive', folderId: folderId);
  }

  /// Generic: list folders for any cloud provider
  Future<List<Map<String, dynamic>>> listCloudFolders(String provider, {String parentId = 'root'}) async {
    final response = await _get(
      '/api/cloud/providers/$provider/folders?parent_id=${Uri.encodeComponent(parentId)}',
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['folders'] ?? []);
    } else {
      throw ApiException(
        'Failed to list $provider folders',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Generic: list ebook files for any cloud provider
  Future<List<Map<String, dynamic>>> listCloudFiles(String provider, {String? folderId}) async {
    String path = '/api/cloud/providers/$provider/files';
    if (folderId != null) {
      path += '?folder=${Uri.encodeComponent(folderId)}';
    }
    final response = await _get(path);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<Map<String, dynamic>>.from(data['files'] ?? []);
    } else {
      throw ApiException(
        'Failed to list $provider files',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  // ==========================================================================
  // ORGANIZATION API
  // ==========================================================================

  /// Get the full taxonomy tree structure
  Future<Map<String, List<String>>> getTaxonomy() async {
    final response = await _get('/api/organization/taxonomy');

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(response.body);
      return data.map((key, value) => 
        MapEntry(key, List<String>.from(value)));
    } else {
      throw ApiException(
        'Failed to load taxonomy',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Get organization coverage statistics
  Future<Map<String, dynamic>> getOrganizationStats({String? sourcePath}) async {
    String path = '/api/organization/stats';
    if (sourcePath != null) {
      path += '?source_path=${Uri.encodeComponent(sourcePath)}';
    }
    final response = await _get(path);

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to load organization stats',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Classify a single ebook
  Future<Map<String, dynamic>> classifyEbook(int ebookId, {bool forceReclassify = false}) async {
    final response = await _post(
      '/api/organization/classify/$ebookId',
      body: {'force_reclassify': forceReclassify},
      timeout: _config.classificationTimeout,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else if (response.statusCode == 404) {
      throw ApiException('Ebook not found', statusCode: 404);
    } else {
      throw ApiException(
        'Failed to classify ebook',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Batch classify multiple ebooks
  Future<Map<String, dynamic>> batchClassifyEbooks({
    List<int>? ebookIds,
    String? sourcePath,
    bool forceReclassify = false,
    int limit = 100,
    Map<int, Map<String, String>>? overrides,
  }) async {
    final Map<String, dynamic> body = {
      if (ebookIds != null) 'ebook_ids': ebookIds,
      if (sourcePath != null) 'source_path': sourcePath,
      'force_reclassify': forceReclassify,
      'limit': limit,
    };

    if (overrides != null && overrides.isNotEmpty) {
      body['overrides'] = overrides.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    final response = await _post(
      '/api/organization/batch-classify',
      body: body,
      timeout: _config.classificationTimeout,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to batch classify ebooks',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Update an ebook's classification manually
  Future<Ebook> updateEbookClassification(int ebookId, {String? category, String? subGenre}) async {
    final uri = Uri.parse('$baseUrl/api/organization/classify/$ebookId');
    try {
      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          if (category != null) 'category': category,
          if (subGenre != null) 'sub_genre': subGenre,
        }),
      ).timeout(_config.classificationTimeout);

      if (response.statusCode == 200) {
        return Ebook.fromJson(json.decode(response.body));
      } else if (response.statusCode == 400) {
        final error = json.decode(response.body);
        throw ApiException(error['detail'] ?? 'Invalid classification');
      } else {
        throw ApiException(
          'Failed to update classification',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    }
  }

  /// Get unclassified ebooks
  Future<List<Ebook>> getUnclassifiedEbooks({
    String? sourcePath,
    int skip = 0,
    int limit = 100,
  }) async {
    final queryParams = {
      'skip': skip.toString(),
      'limit': limit.toString(),
      if (sourcePath != null) 'source_path': sourcePath,
    };

    final uri = Uri.parse('$baseUrl/api/organization/unclassified')
        .replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri).timeout(_config.requestTimeout);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Ebook.fromJson(json)).toList();
      } else {
        throw ApiException(
          'Failed to load unclassified ebooks',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    }
  }

  /// Get classification preview (dry run)
  Future<Map<String, dynamic>> getClassificationPreview({
    String? sourcePath,
    int limit = 100,
  }) async {
    final queryParams = {
      'limit': limit.toString(),
      if (sourcePath != null) 'source_path': sourcePath,
    };

    final uri = Uri.parse('$baseUrl/api/organization/preview')
        .replace(queryParameters: queryParams);
    try {
      final response = await http.get(uri).timeout(_config.classificationTimeout);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw ApiException(
          'Failed to load classification preview',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }
    } on TimeoutException {
      throw ApiException('Request timed out. Please check your connection.');
    }
  }

  // ===========================================================================
  // REORGANIZATION API
  // ===========================================================================

  /// Get reorganization preview (planned file moves/copies)
  Future<Map<String, dynamic>> getReorganizePreview({
    required String destination,
    String? sourcePath,
    bool includeUnclassified = false,
    String operation = 'move',
  }) async {
    final response = await _post(
      '/api/organization/reorganize-preview',
      body: {
        'destination': destination,
        if (sourcePath != null) 'source_path': sourcePath,
        'include_unclassified': includeUnclassified,
        'operation': operation,
      },
      timeout: _config.classificationTimeout,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to generate reorganization preview',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }

  /// Execute file reorganization (move or copy)
  Future<Map<String, dynamic>> reorganizeFiles({
    required String destination,
    String? sourcePath,
    bool includeUnclassified = false,
    String operation = 'move',
  }) async {
    final response = await _post(
      '/api/organization/reorganize',
      body: {
        'destination': destination,
        if (sourcePath != null) 'source_path': sourcePath,
        'include_unclassified': includeUnclassified,
        'operation': operation,
      },
      timeout: _config.classificationTimeout,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw ApiException(
        'Failed to reorganize files',
        statusCode: response.statusCode,
        responseBody: response.body,
      );
    }
  }
}
