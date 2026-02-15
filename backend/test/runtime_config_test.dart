import 'package:test/test.dart';

import '../infra/runtime_config.dart';

void main() {
  test('defaults to sqlite when no DATABASE_URL is present', () {
    final config = BackendRuntimeConfig.fromEnvironmentMap(
      const <String, String>{},
    );
    expect(config.dbMode, BackendDbMode.sqlite);
  });

  test('defaults to postgres when DATABASE_URL is present', () {
    final config = BackendRuntimeConfig.fromEnvironmentMap(
      const <String, String>{
        'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
      },
    );
    expect(config.dbMode, BackendDbMode.postgres);
  });

  test('explicit sqlite mode overrides DATABASE_URL', () {
    final config =
        BackendRuntimeConfig.fromEnvironmentMap(const <String, String>{
          'BACKEND_DB_MODE': 'sqlite',
          'DATABASE_URL': 'postgres://hailo:secret@localhost:5432/hailo',
        });
    expect(config.dbMode, BackendDbMode.sqlite);
  });
}
