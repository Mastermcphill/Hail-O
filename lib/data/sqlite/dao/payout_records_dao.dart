import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/payout_record.dart';
import '../table_names.dart';

class PayoutRecordsDao {
  const PayoutRecordsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(
    PayoutRecord record, {
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'payout_insert_requires_orchestrator',
      );
    }
    await db.insert(
      TableNames.payoutRecords,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<PayoutRecord?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.payoutRecords,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PayoutRecord.fromMap(rows.first);
  }

  Future<PayoutRecord?> findByEscrowId(String escrowId) async {
    final rows = await db.query(
      TableNames.payoutRecords,
      where: 'escrow_id = ?',
      whereArgs: <Object>[escrowId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PayoutRecord.fromMap(rows.first);
  }

  Future<PayoutRecord?> findLatestByRideId(String rideId) async {
    final rows = await db.query(
      TableNames.payoutRecords,
      where: 'ride_id = ?',
      whereArgs: <Object>[rideId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return PayoutRecord.fromMap(rows.first);
  }
}
