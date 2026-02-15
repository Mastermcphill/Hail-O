class ApiConfig {
  const ApiConfig({required this.baseUrl});

  static const String defaultDevelopmentBaseUrl = 'http://localhost:8080';
  static const String defaultProductionBaseUrl =
      'https://hail-o-api.onrender.com';

  final String baseUrl;

  factory ApiConfig.fromEnvironment() {
    const override = String.fromEnvironment(
      'HAILO_API_BASE_URL',
      defaultValue: '',
    );
    if (override.isNotEmpty) {
      return ApiConfig(baseUrl: _normalize(override));
    }
    const environment = String.fromEnvironment(
      'HAILO_API_ENV',
      defaultValue: 'development',
    );
    if (environment.toLowerCase() == 'production') {
      return const ApiConfig(baseUrl: defaultProductionBaseUrl);
    }
    return const ApiConfig(baseUrl: defaultDevelopmentBaseUrl);
  }

  static ApiConfig fromValues({
    String? baseUrl,
    String environment = 'development',
  }) {
    final normalizedBaseUrl = (baseUrl ?? '').trim();
    if (normalizedBaseUrl.isNotEmpty) {
      return ApiConfig(baseUrl: _normalize(normalizedBaseUrl));
    }
    if (environment.toLowerCase() == 'production') {
      return const ApiConfig(baseUrl: defaultProductionBaseUrl);
    }
    return const ApiConfig(baseUrl: defaultDevelopmentBaseUrl);
  }

  static String _normalize(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
