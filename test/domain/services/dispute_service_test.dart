import 'package:flutter_test/flutter_test.dart';
import 'package:hail_o_finance_core/data/sqlite/hailo_database.dart';
import 'package:hail_o_finance_core/domain/errors/domain_errors.dart';
import 'package:hail_o_finance_core/domain/services/dispute_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'dispute resolve enforces admin role, refund cap, and idempotent replay',
    () async {
      final now = DateTime.utc(2026, 2, 11, 12);
      final db = await HailODatabase().open(databasePath: inMemoryDatabasePath);
      addTearDown(db.close);

      await _seedUsersRideAndPayout(db, now);

      final service = DisputeService(db, nowUtc: () => now);

      final opened = await service.openDispute(
        disputeId: 'dispute_1',
        rideId: 'ride_dispute_1',
        openedBy: 'rider_dispute_1',
        reason: 'fare mismatch',
        idempotencyKey: 'dispute_open_1',
      );
      expect(opened['ok'], true);

      expect(
        () => service.resolveDispute(
          disputeId: 'dispute_1',
          resolverUserId: 'driver_dispute_1',
          resolverIsAdmin: false,
          refundMinor: 1000,
          idempotencyKey: 'dispute_resolve_forbidden',
        ),
        throwsA(
          isA<UnauthorizedActionError>().having(
            (e) => e.code,
            'code',
            'dispute_resolve_forbidden',
          ),
        ),
      );

      expect(
        () => service.resolveDispute(
          disputeId: 'dispute_1',
          resolverUserId: 'admin_dispute_1',
          resolverIsAdmin: true,
          refundMinor: 20000,
          idempotencyKey: 'dispute_resolve_too_much',
        ),
        throwsA(
          isA<DomainInvariantError>().having(
            (e) => e.code,
            'code',
            'refund_exceeds_paid',
          ),
        ),
      );

      final resolved = await service.resolveDispute(
        disputeId: 'dispute_1',
        resolverUserId: 'admin_dispute_1',
        resolverIsAdmin: true,
        refundMinor: 3000,
        idempotencyKey: 'dispute_resolve_1',
      );
      final replay = await service.resolveDispute(
        disputeId: 'dispute_1',
        resolverUserId: 'admin_dispute_1',
        resolverIsAdmin: true,
        refundMinor: 3000,
        idempotencyKey: 'dispute_resolve_1',
      );

      expect(resolved['ok'], true);
      expect(resolved['refund_minor'], 3000);
      expect(replay['replayed'], true);

      final disputeRows = await db.query(
        'disputes',
        where: 'id = ?',
        whereArgs: const <Object>['dispute_1'],
        limit: 1,
      );
      expect(disputeRows.first['status'], 'resolved');
      expect(disputeRows.first['refund_minor_total'], 3000);

      final reversals = await db.query('wallet_reversals');
      expect(reversals.length, 1);

      final riderCreditRows = await db.query(
        'wallet_ledger',
        where: 'owner_id = ? AND kind = ?',
        whereArgs: const <Object>['rider_dispute_1', 'dispute_refund_credit'],
      );
      expect(riderCreditRows.length, 1);
      expect(riderCreditRows.first['amount_minor'], 3000);
    },
  );
}

Future<void> _seedUsersRideAndPayout(dynamic db, DateTime now) async {
  for (final user in <Map<String, String>>[
    <String, String>{'id': 'rider_dispute_1', 'role': 'rider'},
    <String, String>{'id': 'driver_dispute_1', 'role': 'driver'},
    <String, String>{'id': 'admin_dispute_1', 'role': 'admin'},
  ]) {
    await db.insert('users', <String, Object?>{
      'id': user['id'],
      'role': user['role'],
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    });
  }

  await db.insert('rides', <String, Object?>{
    'id': 'ride_dispute_1',
    'rider_id': 'rider_dispute_1',
    'driver_id': 'driver_dispute_1',
    'trip_scope': 'intra_city',
    'status': 'finance_settled',
    'bidding_mode': 1,
    'base_fare_minor': 10000,
    'premium_markup_minor': 0,
    'charter_mode': 0,
    'daily_rate_minor': 0,
    'total_fare_minor': 10000,
    'connection_fee_minor': 0,
    'connection_fee_paid': 0,
    'created_at': now.toIso8601String(),
    'updated_at': now.toIso8601String(),
  });

  await db.insert('wallets', <String, Object?>{
    'owner_id': 'driver_dispute_1',
    'wallet_type': 'driver_a',
    'balance_minor': 10000,
    'reserved_minor': 0,
    'currency': 'NGN',
    'updated_at': now.toIso8601String(),
    'created_at': now.toIso8601String(),
  });

  await db.insert('wallet_ledger', <String, Object?>{
    'owner_id': 'driver_dispute_1',
    'wallet_type': 'driver_a',
    'direction': 'credit',
    'amount_minor': 10000,
    'balance_after_minor': 10000,
    'kind': 'ride_settlement',
    'reference_id': 'ride_dispute_1',
    'idempotency_scope': 'ride_settlement',
    'idempotency_key': 'ride_settlement_seed_1',
    'created_at': now.toIso8601String(),
  });

  await db.insert('escrow_holds', <String, Object?>{
    'id': 'escrow_dispute_1',
    'ride_id': 'ride_dispute_1',
    'holder_user_id': 'rider_dispute_1',
    'amount_minor': 10000,
    'status': 'released',
    'release_mode': 'manual_override',
    'created_at': now.toIso8601String(),
    'released_at': now.toIso8601String(),
    'idempotency_scope': 'escrow_release',
    'idempotency_key': 'escrow_release_dispute_1',
  });

  await db.insert('payout_records', <String, Object?>{
    'id': 'payout_dispute_1',
    'ride_id': 'ride_dispute_1',
    'escrow_id': 'escrow_dispute_1',
    'trigger': 'manual_override',
    'status': 'completed',
    'recipient_owner_id': 'driver_dispute_1',
    'recipient_wallet_type': 'driver_a',
    'total_paid_minor': 10000,
    'commission_gross_minor': 10000,
    'commission_saved_minor': 0,
    'commission_remainder_minor': 10000,
    'premium_locked_minor': 0,
    'driver_allowance_minor': 0,
    'cash_debt_minor': 0,
    'penalty_due_minor': 0,
    'breakdown_json': '{}',
    'idempotency_scope': 'ride_settlement',
    'idempotency_key': 'settlement:escrow_dispute_1',
    'created_at': now.toIso8601String(),
  });
}
