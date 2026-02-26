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
        sqlByName['007_marketplace_webhooks.sql'] ?? '';
    final billingLedgerSql = sqlByName['008_billing_ledger_entries.sql'] ?? '';
    final entitlementSql = sqlByName['010_marketplace_entitlements.sql'] ?? '';
    final referralCouponSql = sqlByName['013_referrals_coupons.sql'] ?? '';
    final creditsSql = sqlByName['014_credits_wallet.sql'] ?? '';
    final invoicesDunningCommsSql =
        sqlByName['015_invoices_dunning_comms.sql'] ?? '';
    final riskSql = sqlByName['016_risk_engine.sql'] ?? '';
    final paymentIntentsSql = sqlByName['017_payment_intents.sql'] ?? '';
    final webhookEventsSql = sqlByName['018_webhook_events.sql'] ?? '';
    final phoneAuthSql = sqlByName['019_auth_phone_otp.sql'] ?? '';
    final profileRolesSql = sqlByName['020_user_profile_roles.sql'] ?? '';
    final dispatchSql = sqlByName['021_dispatch_trips.sql'] ?? '';

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
    expect(
      entitlementSql.contains(
        'CREATE TABLE IF NOT EXISTS marketplace_entitlements',
      ),
      isTrue,
      reason: 'marketplace entitlements table must exist',
    );
    expect(
      entitlementSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_marketplace_entitlements_active_unique',
      ),
      isTrue,
      reason: 'active entitlement uniqueness must exist',
    );
    expect(
      entitlementSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_marketplace_entitlements_purchase_effective_desc',
      ),
      isTrue,
      reason: 'entitlement purchase timeline index must exist',
    );
    expect(
      entitlementSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_marketplace_entitlements_user_effective_desc',
      ),
      isTrue,
      reason: 'entitlement user timeline index must exist',
    );

    expect(
      referralCouponSql.contains('CREATE TABLE IF NOT EXISTS referral_codes'),
      isTrue,
      reason: 'referral codes table must exist',
    );
    expect(
      referralCouponSql.contains('UNIQUE(code_id, referred_user_id)'),
      isTrue,
      reason: 'referral use dedupe uniqueness must exist',
    );
    expect(
      referralCouponSql.contains('CREATE TABLE IF NOT EXISTS coupons'),
      isTrue,
      reason: 'coupons table must exist',
    );
    expect(
      referralCouponSql.contains(
        'CREATE TABLE IF NOT EXISTS coupon_redemptions',
      ),
      isTrue,
      reason: 'coupon redemptions table must exist',
    );
    expect(
      referralCouponSql.contains('UNIQUE(coupon_id, user_id, purchase_id)'),
      isTrue,
      reason: 'coupon redemption dedupe uniqueness must exist',
    );

    expect(
      creditsSql.contains('CREATE TABLE IF NOT EXISTS org_credits'),
      isTrue,
      reason: 'org credits table must exist',
    );
    expect(
      creditsSql.contains('CREATE TABLE IF NOT EXISTS credit_ledger'),
      isTrue,
      reason: 'credit ledger table must exist',
    );

    expect(
      invoicesDunningCommsSql.contains(
        'CREATE TABLE IF NOT EXISTS billing_invoices',
      ),
      isTrue,
      reason: 'billing invoices table must exist',
    );
    expect(
      invoicesDunningCommsSql.contains(
        'CREATE TABLE IF NOT EXISTS dunning_cases',
      ),
      isTrue,
      reason: 'dunning cases table must exist',
    );
    expect(
      invoicesDunningCommsSql.contains(
        'CREATE TABLE IF NOT EXISTS dunning_attempts',
      ),
      isTrue,
      reason: 'dunning attempts table must exist',
    );
    expect(
      invoicesDunningCommsSql.contains(
        'CREATE TABLE IF NOT EXISTS comms_outbox',
      ),
      isTrue,
      reason: 'comms outbox table must exist',
    );
    expect(
      invoicesDunningCommsSql.contains('dedupe_key TEXT NOT NULL UNIQUE'),
      isTrue,
      reason: 'comms outbox dedupe uniqueness must exist',
    );

    expect(
      riskSql.contains('CREATE TABLE IF NOT EXISTS risk_scores'),
      isTrue,
      reason: 'risk scores table must exist',
    );
    expect(
      riskSql.contains('CREATE TABLE IF NOT EXISTS risk_events'),
      isTrue,
      reason: 'risk events table must exist',
    );
    expect(
      riskSql.contains('CREATE TABLE IF NOT EXISTS risk_rules'),
      isTrue,
      reason: 'risk rules table must exist',
    );
    expect(
      paymentIntentsSql.contains('CREATE TABLE IF NOT EXISTS payment_intents'),
      isTrue,
      reason: 'payment intents table must exist',
    );
    expect(
      paymentIntentsSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_intents_purchase_active_unique',
      ),
      isTrue,
      reason: 'payment intents active uniqueness must exist',
    );
    expect(
      webhookEventsSql.contains('CREATE TABLE IF NOT EXISTS webhook_events'),
      isTrue,
      reason: 'webhook events table must exist',
    );
    expect(
      webhookEventsSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_webhook_events_provider_event',
      ),
      isTrue,
      reason: 'webhook events dedupe index must exist',
    );
    expect(
      phoneAuthSql.contains('CREATE TABLE IF NOT EXISTS users'),
      isTrue,
      reason: 'phone-auth users table must exist',
    );
    expect(
      phoneAuthSql.contains('phone_e164 TEXT NOT NULL UNIQUE'),
      isTrue,
      reason: 'phone-auth users phone uniqueness must exist',
    );
    expect(
      phoneAuthSql.contains('CREATE TABLE IF NOT EXISTS otp_challenges'),
      isTrue,
      reason: 'otp challenges table must exist',
    );
    expect(
      phoneAuthSql.contains('CREATE TABLE IF NOT EXISTS refresh_tokens'),
      isTrue,
      reason: 'refresh tokens table must exist',
    );
    expect(
      phoneAuthSql.contains(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_refresh_tokens_token_hash',
      ),
      isTrue,
      reason: 'refresh token hash uniqueness must exist',
    );
    expect(
      profileRolesSql.contains('CREATE TABLE IF NOT EXISTS user_profiles'),
      isTrue,
      reason: 'user profiles table must exist',
    );
    expect(
      profileRolesSql.contains('CREATE TABLE IF NOT EXISTS user_roles'),
      isTrue,
      reason: 'user roles table must exist',
    );
    expect(
      profileRolesSql.contains('UNIQUE(user_id, role)'),
      isTrue,
      reason: 'user role uniqueness must exist',
    );
    expect(
      dispatchSql.contains('CREATE TABLE IF NOT EXISTS trips'),
      isTrue,
      reason: 'dispatch trips table must exist',
    );
    expect(
      dispatchSql.contains('CREATE TABLE IF NOT EXISTS trip_events'),
      isTrue,
      reason: 'dispatch trip events table must exist',
    );
    expect(
      dispatchSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_trips_user_created_desc',
      ),
      isTrue,
      reason: 'dispatch trips user timeline index must exist',
    );
    expect(
      dispatchSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_trips_status_created_desc',
      ),
      isTrue,
      reason: 'dispatch trips status timeline index must exist',
    );
    expect(
      dispatchSql.contains(
        'CREATE INDEX IF NOT EXISTS idx_trip_events_trip_created',
      ),
      isTrue,
      reason: 'dispatch trip events timeline index must exist',
    );
  });
}
