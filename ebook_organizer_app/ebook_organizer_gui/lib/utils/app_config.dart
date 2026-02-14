/// Application configuration for the Ebook Organizer
/// 
/// Configuration values can be overridden via environment variables
/// or by modifying these defaults for different environments.
class AppConfig {
  // Private constructor for singleton
  AppConfig._();
  
  static final AppConfig _instance = AppConfig._();
  static AppConfig get instance => _instance;

  // API Configuration
  String _apiHost = '127.0.0.1';
  int _apiPort = 8000;
  bool _useHttps = false;

  /// The API host address
  String get apiHost => _apiHost;
  
  /// The API port
  int get apiPort => _apiPort;
  
  /// Whether to use HTTPS
  bool get useHttps => _useHttps;

  /// The full base URL for API calls
  String get apiBaseUrl {
    final protocol = _useHttps ? 'https' : 'http';
    return '$protocol://$_apiHost:$_apiPort';
  }

  /// HTTP request timeout duration
  Duration get requestTimeout => const Duration(seconds: 30);

  /// Health check timeout (shorter for quick connectivity checks)
  Duration get healthCheckTimeout => const Duration(seconds: 3);

  /// Classification timeout (longer for batch operations that hit external APIs)
  Duration get classificationTimeout => const Duration(seconds: 120);

  /// Configure the API endpoint
  /// Call this before making any API requests if you need to change defaults
  void configureApi({
    String? host,
    int? port,
    bool? useHttps,
  }) {
    if (host != null) _apiHost = host;
    if (port != null) _apiPort = port;
    if (useHttps != null) _useHttps = useHttps;
  }

  /// Supported ebook file extensions
  static const Set<String> supportedFormats = {
    'epub', 'pdf', 'mobi', 'azw', 'azw3', 'fb2', 'djvu', 'cbz', 'cbr'
  };

  /// Maximum file size for indexing (in bytes) - 500 MB
  static const int maxFileSize = 500 * 1024 * 1024;
}
