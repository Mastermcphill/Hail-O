import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('backend migration SQL includes required indexes and uniqueness', () async {
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
    final marketplaceSql = sqlByName['005_marketplace_core.sql'] ?? '';
    final ledgerSql = sqlByName['006_billing_ledger_entries.sql'] ?? '';
    final entitlementsSql = sqlByName['007_marketplace_entitlements.sql'] ?? '';

    expect(
      authSql.contains('CREATE INDEX IF NOT EXISTS idx_auth_credentials_email'),
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
    expect(
      marketplaceSql.contains('UNIQUE(user_id, idempotency_key)'),
      isTrue,
      reason: 'marketplace purchase idempotency uniqueness must exist',
    );
    expect(
      marketplaceSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_marketplace_webhook_provider_event',
      ),
      isTrue,
      reason: 'webhook replay dedupe index must exist',
    );
    expect(
      ledgerSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_billing_ledger_provider_ref_type',
      ),
      isTrue,
      reason: 'billing ledger replay dedupe index must exist',
    );
    expect(
      entitlementsSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS ux_marketplace_entitlements_active_type',
      ),
      isTrue,
      reason: 'single active entitlement row per type must exist',
    );
  });
}
