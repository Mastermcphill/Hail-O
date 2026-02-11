import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/wallet_transfer.dart';
import '../table_names.dart';

class WalletTransfersDao {
  const WalletTransfersDao(this.db);

  final DatabaseExecutor db;

  Future<void> insert(
    WalletTransfer transfer, {
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'wallet_transfer_insert_requires_orchestrator',
      );
    }
    await db.insert(
      TableNames.walletTransfers,
      transfer.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<WalletTransfer?> findById(String transferId) async {
    final rows = await db.query(
      TableNames.walletTransfers,
      where: 'transfer_id = ?',
      whereArgs: <Object>[transferId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WalletTransfer.fromMap(rows.first);
  }

  Future<WalletTransfer?> findByIdempotency({
    required String idempotencyScope,
    required String idempotencyKey,
  }) async {
    final rows = await db.query(
      TableNames.walletTransfers,
      where: 'idempotency_scope = ? AND idempotency_key = ?',
      whereArgs: <Object>[idempotencyScope, idempotencyKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WalletTransfer.fromMap(rows.first);
  }

  Future<List<WalletTransfer>> listByReference(String referenceId) async {
    final rows = await db.query(
      TableNames.walletTransfers,
      where: 'reference_id = ?',
      whereArgs: <Object>[referenceId],
      orderBy: 'created_at ASC',
    );
    return rows.map(WalletTransfer.fromMap).toList(growable: false);
  }
}
