import 'package:test/test.dart';

import '../infra/runtime_config.dart';

void main() {
  test('defaults to sqlite when no DATABASE_URL is present', () {
    final config = BackendRuntimeConfig.fromEnvironmentMap(
      const <String, String>{},
    );
    expect(config.dbMode, BackendDbMode.sqlite);
    expect(config.dbSchema, 'public');
  });

  test('defaults to postgres when DATABASE_URL is present', () {
    final config = BackendRuntimeConfig.fromEnvironmentMap(
      const <String, String>{
        'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
      },
    );
    expect(config.dbMode, BackendDbMode.postgres);
    expect(config.dbSchema, 'hailo_prod');
  });

  test('explicit sqlite mode overrides DATABASE_URL', () {
    final config =
        BackendRuntimeConfig.fromEnvironmentMap(const <String, String>{
          'BACKEND_DB_MODE': 'sqlite',
          'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
        });
    expect(config.dbMode, BackendDbMode.sqlite);
    expect(config.dbSchema, 'public');
  });

  test('DB_SCHEMA override applies to postgres and sqlite mode', () {
    final postgresConfig =
        BackendRuntimeConfig.fromEnvironmentMap(const <String, String>{
          'BACKEND_DB_MODE': 'postgres',
          'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
          'DB_SCHEMA': 'hailo_staging',
        });
    expect(postgresConfig.dbMode, BackendDbMode.postgres);
    expect(postgresConfig.dbSchema, 'hailo_staging');

    final sqliteConfig = BackendRuntimeConfig.fromEnvironmentMap(
      const <String, String>{
        'BACKEND_DB_MODE': 'sqlite',
        'DB_SCHEMA': 'local_schema',
      },
    );
    expect(sqliteConfig.dbMode, BackendDbMode.sqlite);
    expect(sqliteConfig.dbSchema, 'local_schema');
  });
}
