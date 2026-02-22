import '../migration.dart';

class M0005RideSettlementPayoutRecords extends Migration {
  const M0005RideSettlementPayoutRecords();

  @override
  int get version => 5;

  @override
  String get name => 'm0005_ride_settlement_payout_records';

  @override
  String get checksum => 'm0005_ride_settlement_payout_records_v2';

  @override
  List<String> get upSql => <String>[
    '''
    CREATE TABLE IF NOT EXISTS payout_records (
      id TEXT PRIMARY KEY,
      ride_id TEXT NOT NULL,
      escrow_id TEXT NOT NULL,
      trigger TEXT NOT NULL CHECK(trigger IN ('geofence','manual_override')),
      status TEXT NOT NULL CHECK(status IN ('completed','failed')),
      recipient_owner_id TEXT NOT NULL,
      recipient_wallet_type TEXT NOT NULL,
      total_paid_minor INTEGER NOT NULL DEFAULT 0,
      commission_gross_minor INTEGER NOT NULL DEFAULT 0,
      commission_saved_minor INTEGER NOT NULL DEFAULT 0,
      commission_remainder_minor INTEGER NOT NULL DEFAULT 0,
      premium_locked_minor INTEGER NOT NULL DEFAULT 0,
      driver_allowance_minor INTEGER NOT NULL DEFAULT 0,
      cash_debt_minor INTEGER NOT NULL DEFAULT 0,
      penalty_due_minor INTEGER NOT NULL DEFAULT 0,
      breakdown_json TEXT NOT NULL DEFAULT '{}',
      idempotency_scope TEXT NOT NULL,
      idempotency_key TEXT NOT NULL,
      created_at TEXT NOT NULL,
      UNIQUE(idempotency_scope, idempotency_key),
      FOREIGN KEY(ride_id) REFERENCES rides(id),
      FOREIGN KEY(escrow_id) REFERENCES escrow_holds(id)
    )
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_payout_records_ride_created
    ON payout_records(ride_id, created_at DESC)
    ''',
    '''
    CREATE INDEX IF NOT EXISTS idx_payout_records_escrow
    ON payout_records(escrow_id)
    ''',
  ];
}
