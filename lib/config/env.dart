import 'api_config.dart';

enum AppEnvironment { dev, staging, production }

class AppEnv {
  AppEnv._();

  static AppEnvironment get current {
    final raw = const String.fromEnvironment('ENV', defaultValue: '');
    final normalized = raw.trim().toLowerCase();
    switch (normalized) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'production':
      case 'prod':
        return AppEnvironment.production;
      default:
        final legacy = ApiConfig.environment;
        if (legacy == HailoEnvironment.staging) {
          return AppEnvironment.staging;
        }
        if (legacy == HailoEnvironment.prod) {
          return AppEnvironment.production;
        }
        return AppEnvironment.dev;
    }
  }

  static bool get isProduction => current == AppEnvironment.production;
  static bool get isStaging => current == AppEnvironment.staging;
  static String get name => current.name;
}
