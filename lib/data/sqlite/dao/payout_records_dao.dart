import 'package:sqflite/sqflite.dart';

import '../../../domain/models/payout_record.dart';
import '../table_names.dart';

class PayoutRecordsDao {
  const PayoutRecordsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(PayoutRecord record) async {
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
}
