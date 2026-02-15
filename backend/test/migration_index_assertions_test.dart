import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'backend migration SQL includes required indexes and uniqueness',
    () async {
      final root = Directory.current.path;
      final migrationsDir = Directory(p.join(root, 'migrations'));
      expect(await migrationsDir.exists(), isTrue);

      final sqlByName = <String, String>{};
      await for (final entity in migrationsDir.list()) {
        if (entity is! File || !entity.path.toLowerCase().endsWith('.sql')) {
          continue;
        }
        sqlByName[p.basename(entity.path)] = await entity.readAsString();
      }

      final authSql = sqlByName['002_auth_credentials.sql'] ?? '';
      final rideSql = sqlByName['003_ride_request_metadata.sql'] ?? '';
      final opsSql = sqlByName['004_operational_records.sql'] ?? '';

      expect(
        authSql.contains(
          'CREATE INDEX IF NOT EXISTS idx_auth_credentials_email',
        ),
        isTrue,
        reason: 'auth email lookup index must exist',
      );
      expect(
        rideSql.contains(
          'CREATE INDEX IF NOT EXISTS idx_ride_request_metadata_rider_id',
        ),
        isTrue,
        reason: 'ride metadata rider_id lookup index must exist',
      );
      expect(
        opsSql.contains('UNIQUE(operation_type, entity_id, idempotency_key)'),
        isTrue,
        reason: 'operational idempotency uniqueness must exist',
      );
    },
  );
}
