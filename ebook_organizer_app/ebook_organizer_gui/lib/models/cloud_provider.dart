/// Cloud provider status model
class CloudProvider {
  final String provider;
  final bool isEnabled;
  final bool isAuthenticated;
  final DateTime? lastSync;
  final String? folderPath;

  CloudProvider({
    required this.provider,
    required this.isEnabled,
    required this.isAuthenticated,
    this.lastSync,
    this.folderPath,
  });

  factory CloudProvider.fromJson(Map<String, dynamic> json) {
    return CloudProvider(
      provider: json['provider'] ?? '',
      isEnabled: json['is_enabled'] ?? false,
      isAuthenticated: json['is_authenticated'] ?? false,
      lastSync: json['last_sync'] != null ? DateTime.parse(json['last_sync']) : null,
      folderPath: json['folder_path'],
    );
  }

  String get displayName {
    switch (provider) {
      case 'google_drive':
        return 'Google Drive';
      case 'onedrive':
        return 'OneDrive';
      default:
        return provider;
    }
  }

  String get statusText {
    if (!isEnabled) return 'Disabled';
    if (!isAuthenticated) return 'Not Connected';
    return 'Connected';
  }

  CloudProvider copyWith({
    String? provider,
    bool? isEnabled,
    bool? isAuthenticated,
    DateTime? lastSync,
    String? folderPath,
  }) {
    return CloudProvider(
      provider: provider ?? this.provider,
      isEnabled: isEnabled ?? this.isEnabled,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      lastSync: lastSync ?? this.lastSync,
      folderPath: folderPath ?? this.folderPath,
    );
  }
}
