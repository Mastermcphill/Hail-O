import 'dart:io';

enum BackendDbMode { sqlite, postgres }

class BackendRuntimeConfig {
  const BackendRuntimeConfig({
    required this.dbMode,
    required this.dbSchema,
    this.databaseUrl,
    this.sqlitePath,
  });

  final BackendDbMode dbMode;
  final String dbSchema;
  final String? databaseUrl;
  final String? sqlitePath;

  bool get usePostgres => dbMode == BackendDbMode.postgres;

  static BackendRuntimeConfig fromEnvironment() {
    return fromEnvironmentMap(Platform.environment);
  }

  static BackendRuntimeConfig fromEnvironmentMap(Map<String, String> env) {
    final configuredMode = env['BACKEND_DB_MODE']?.trim().toLowerCase();
    final databaseUrl = env['DATABASE_URL']?.trim();
    final sqlitePath = env['DB_PATH']?.trim();
    final configuredSchema = env['DB_SCHEMA']?.trim();
    final hasConfiguredSchema =
        configuredSchema != null && configuredSchema.isNotEmpty;
    final sqliteSchema = hasConfiguredSchema ? configuredSchema : 'public';
    final postgresSchema = hasConfiguredSchema
        ? configuredSchema
        : 'hailo_prod';

    if (configuredMode == 'sqlite') {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.sqlite,
        dbSchema: sqliteSchema,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    if (configuredMode == 'postgres') {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.postgres,
        dbSchema: postgresSchema,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    if (databaseUrl != null && databaseUrl.isNotEmpty) {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.postgres,
        dbSchema: postgresSchema,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    return BackendRuntimeConfig(
      dbMode: BackendDbMode.sqlite,
      dbSchema: sqliteSchema,
      databaseUrl: databaseUrl,
      sqlitePath: sqlitePath,
    );
  }
}
