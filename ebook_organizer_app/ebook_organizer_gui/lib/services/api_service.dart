import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/ebook.dart';
import '../models/library_stats.dart';
import '../models/cloud_provider.dart';

class ApiService {
  static const String baseUrl = 'http://127.0.0.1:8000';

  // Health Check
  Future<bool> isBackendAvailable() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health')).timeout(
        const Duration(seconds: 3),
      );
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
  }) async {
    final queryParams = {
      'skip': skip.toString(),
      'limit': limit.toString(),
      if (category != null) 'category': category,
      if (subGenre != null) 'sub_genre': subGenre,
      if (author != null) 'author': author,
      if (search != null) 'search': search,
      if (format != null) 'format': format,
    };

    final uri = Uri.parse('$baseUrl/api/ebooks/').replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Ebook.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load ebooks: ${response.statusCode}');
    }
  }

  // Get single ebook
  Future<Ebook> getEbook(int id) async {
    final response = await http.get(Uri.parse('$baseUrl/api/ebooks/$id'));

    if (response.statusCode == 200) {
      return Ebook.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load ebook');
    }
  }

  // Update ebook metadata
  Future<Ebook> updateEbook(int id, Map<String, dynamic> updates) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/api/ebooks/$id'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(updates),
    );

    if (response.statusCode == 200) {
      return Ebook.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update ebook');
    }
  }

  // Delete ebook
  Future<void> deleteEbook(int id) async {
    final response = await http.delete(Uri.parse('$baseUrl/api/ebooks/$id'));

    if (response.statusCode != 200) {
      throw Exception('Failed to delete ebook');
    }
  }

  // Get library statistics
  Future<LibraryStats> getLibraryStats() async {
    final response = await http.get(Uri.parse('$baseUrl/api/ebooks/stats/library'));

    if (response.statusCode == 200) {
      return LibraryStats.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load library stats');
    }
  }

  // Get cloud providers status
  Future<List<CloudProvider>> getCloudProviders() async {
    final response = await http.get(Uri.parse('$baseUrl/api/cloud/providers'));

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => CloudProvider.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load cloud providers');
    }
  }

  // Trigger sync
  Future<Map<String, dynamic>> triggerSync({
    String? provider,
    bool fullSync = false,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/api/sync/trigger'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        if (provider != null) 'provider': provider,
        'full_sync': fullSync,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to trigger sync');
    }
  }

  // Get sync status
  Future<Map<String, dynamic>> getSyncStatus() async {
    final response = await http.get(Uri.parse('$baseUrl/api/sync/status'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get sync status');
    }
  }
}
