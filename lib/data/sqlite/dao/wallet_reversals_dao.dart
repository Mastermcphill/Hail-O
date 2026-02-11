import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/wallet_reversal_record.dart';
import '../table_names.dart';

class WalletReversalsDao {
  const WalletReversalsDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(
    WalletReversalRecord record, {
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'wallet_reversal_insert_requires_orchestrator',
      );
    }
    await db.insert(
      TableNames.walletReversals,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<WalletReversalRecord?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.walletReversals,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WalletReversalRecord.fromMap(rows.first);
  }

  Future<WalletReversalRecord?> findByOriginalLedgerId(
    int originalLedgerId,
  ) async {
    final rows = await db.query(
      TableNames.walletReversals,
      where: 'original_ledger_id = ?',
      whereArgs: <Object>[originalLedgerId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WalletReversalRecord.fromMap(rows.first);
  }

  Future<List<WalletReversalRecord>> listAll() async {
    final rows = await db.query(
      TableNames.walletReversals,
      orderBy: 'created_at ASC',
    );
    return rows.map(WalletReversalRecord.fromMap).toList(growable: false);
  }
}
