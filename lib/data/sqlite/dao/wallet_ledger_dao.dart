import 'package:sqflite/sqflite.dart';

import '../../../domain/errors/domain_errors.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/wallet_ledger_entry.dart';
import '../table_names.dart';

class WalletLedgerDao {
  const WalletLedgerDao(this.db);

  final DatabaseExecutor db;

  Future<int> append(
    WalletLedgerEntry entry, {
    required bool viaOrchestrator,
  }) async {
    if (!viaOrchestrator) {
      throw const DomainInvariantError(
        code: 'wallet_ledger_append_requires_orchestrator',
      );
    }
    return db.insert(
      TableNames.walletLedger,
      entry.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<List<WalletLedgerEntry>> listByWallet(
    String ownerId,
    WalletType walletType,
  ) async {
    final rows = await db.query(
      TableNames.walletLedger,
      where: 'owner_id = ? AND wallet_type = ?',
      whereArgs: <Object>[ownerId, walletType.dbValue],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(WalletLedgerEntry.fromMap).toList(growable: false);
  }

  Future<List<WalletLedgerEntry>> listAll() async {
    final rows = await db.query(
      TableNames.walletLedger,
      orderBy: 'created_at ASC, id ASC',
    );
    return rows.map(WalletLedgerEntry.fromMap).toList(growable: false);
  }

  Future<WalletLedgerEntry?> findById(int id) async {
    final rows = await db.query(
      TableNames.walletLedger,
      where: 'id = ?',
      whereArgs: <Object>[id],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WalletLedgerEntry.fromMap(rows.first);
  }

  Future<List<WalletLedgerEntry>> listCreditsByReference(
    String referenceId,
  ) async {
    final rows = await db.query(
      TableNames.walletLedger,
      where: 'reference_id = ? AND direction = ?',
      whereArgs: <Object>[referenceId, LedgerDirection.credit.dbValue],
      orderBy: 'created_at DESC, id DESC',
    );
    return rows.map(WalletLedgerEntry.fromMap).toList(growable: false);
  }
}
