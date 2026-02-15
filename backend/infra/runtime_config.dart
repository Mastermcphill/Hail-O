import 'dart:io';

enum BackendDbMode { sqlite, postgres }

class BackendRuntimeConfig {
  const BackendRuntimeConfig({
    required this.dbMode,
    this.databaseUrl,
    this.sqlitePath,
  });

  final BackendDbMode dbMode;
  final String? databaseUrl;
  final String? sqlitePath;

  bool get usePostgres => dbMode == BackendDbMode.postgres;

  static BackendRuntimeConfig fromEnvironment() {
    final env = Platform.environment;
    final configuredMode = env['BACKEND_DB_MODE']?.trim().toLowerCase();
    final databaseUrl = env['DATABASE_URL']?.trim();
    final sqlitePath = env['DB_PATH']?.trim();

    if (configuredMode == 'sqlite') {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.sqlite,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    if (configuredMode == 'postgres') {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.postgres,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    if (databaseUrl != null && databaseUrl.isNotEmpty) {
      return BackendRuntimeConfig(
        dbMode: BackendDbMode.postgres,
        databaseUrl: databaseUrl,
        sqlitePath: sqlitePath,
      );
    }
    return BackendRuntimeConfig(
      dbMode: BackendDbMode.sqlite,
      databaseUrl: databaseUrl,
      sqlitePath: sqlitePath,
    );
  }
}
