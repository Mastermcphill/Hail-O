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
    final marketplaceWebhookSql =
        sqlByName['006_marketplace_webhooks.sql'] ?? '';
    final billingLedgerSql = sqlByName['007_billing_ledger_entries.sql'] ?? '';

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
      marketplaceSql.contains('CREATE TABLE IF NOT EXISTS marketplace_offers'),
      isTrue,
      reason: 'marketplace offers table must exist',
    );
    expect(
      marketplaceSql.contains(
        'CREATE TABLE IF NOT EXISTS marketplace_purchases',
      ),
      isTrue,
      reason: 'marketplace purchases table must exist',
    );
    expect(
      marketplaceSql.contains('UNIQUE(user_id, idempotency_key)'),
      isTrue,
      reason: 'marketplace purchase idempotency uniqueness must exist',
    );
    expect(
      marketplaceSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_marketplace_timeline_purchase_created_desc',
      ),
      isTrue,
      reason: 'timeline query index must exist',
    );
    expect(
      marketplaceWebhookSql.contains(
        'CREATE TABLE IF NOT EXISTS marketplace_webhook_events',
      ),
      isTrue,
      reason: 'marketplace webhook events table must exist',
    );
    expect(
      marketplaceWebhookSql.contains('UNIQUE(provider, provider_event_id)'),
      isTrue,
      reason: 'webhook dedupe uniqueness must exist',
    );
    expect(
      billingLedgerSql.contains(
        'CREATE TABLE IF NOT EXISTS billing_ledger_entries',
      ),
      isTrue,
      reason: 'billing ledger table must exist',
    );
    expect(
      billingLedgerSql.contains('UNIQUE(provider, provider_ref, entry_type)'),
      isTrue,
      reason: 'billing ledger dedupe uniqueness must exist',
    );
    expect(
      billingLedgerSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_billing_ledger_purchase_occurred_desc',
      ),
      isTrue,
      reason: 'billing ledger purchase timeline index must exist',
    );
    expect(
      billingLedgerSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_billing_ledger_user_occurred_desc',
      ),
      isTrue,
      reason: 'billing ledger user timeline index must exist',
    );
  });
}
